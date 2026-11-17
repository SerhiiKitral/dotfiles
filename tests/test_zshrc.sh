#!/usr/bin/env bash
# shellcheck disable=SC2088  # "~" in test messages is text, not a path
# Tests for zsh/.zshrc: loads cleanly, logs missing tools, path-segment deletion.
# Uses a sandbox home with a stub zinit, so no network and no plugins are needed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v zsh >/dev/null; then
  test_case "zsh"
  skip "zsh not installed"
  summary; exit $?
fi
ZSH_BIN="$(command -v zsh)"

# Sandbox: linked config, stub zinit, PATH with almost nothing on it
setup_zsh_sandbox() {
  make_sandbox
  env -u XDG_CONFIG_HOME DOTFILES_TARGET_HOME="$SB_HOME" DOTFILES_LOG_DIR="$SB_LOGS" \
    bash "$SB_REPO/install.sh" --links-only >/dev/null 2>&1
  mkdir -p "$SB_HOME/.local/share/zinit/zinit.git" "$SANDBOX/bin"
  printf 'zinit() { : }\n' > "$SB_HOME/.local/share/zinit/zinit.git/zinit.zsh"
  local tool
  for tool in mkdir tail rm cat mv cp chmod grep getent; do
    command -v "$tool" >/dev/null && ln -s "$(command -v "$tool")" "$SANDBOX/bin/$tool"
  done
  ZLOG="$SB_HOME/.local/state/dotfiles/zsh-errors.log"
}

# zsh_run 'commands'  -> interactive zsh in the sandbox; sets OUT, ERR, RC
# --no-globalrcs: skip the distro's /etc/zshrc etc. Those files differ per distro
# (Fedora's runs /etc/profile.d scripts) and would fail on the sandbox's tiny PATH;
# the tests are about this repo's .zshrc, not the system's files.
zsh_run() {
  local errfile="$SANDBOX/stderr"
  OUT="$(env -i HOME="$SB_HOME" PATH="$SANDBOX/bin" TERM=xterm-256color \
    "$ZSH_BIN" --no-globalrcs -i -c "$1" 2>"$errfile" </dev/null)"
  RC=$?
  ERR="$(cat "$errfile")"
}

# ------------------------------------------------------------
test_case "syntax"
assert_true "zsh -n passes" "$ZSH_BIN" -n "$REPO_ROOT/zsh/.zshrc"

# ------------------------------------------------------------
test_case "startup in a bare environment"
setup_zsh_sandbox
zsh_run 'print -r -- "DOTFILES=$DOTFILES"'
assert_eq 0 "$RC" "exits 0"
assert_eq "" "$ERR" "nothing printed to stderr"
assert_true "DOTFILES points at the repo" grep -qx "DOTFILES=$SB_REPO" <<<"$OUT"
assert_false "no desktop prompt outside WSL" grep -q "First run" <<<"$OUT"

# ------------------------------------------------------------
test_case "insecure completion directory does not stop startup"
# Group/world-writable dirs in fpath make compinit ask y/n (and abort without a terminal)
mkdir -p "$SANDBOX/insecure-completions" && chmod 777 "$SANDBOX/insecure-completions"
printf 'fpath=(%s $fpath)\n' "$SANDBOX/insecure-completions" >> "$SB_HOME/.zshenv"
rm -f "$SB_HOME/.zcompdump"*
zsh_run 'print -r -- started'
assert_eq 0 "$RC" "exits 0"
assert_eq "" "$ERR" "no prompt or error on stderr"
assert_true "shell finished starting" grep -qx "started" <<<"$OUT"
assert_contains "$ZLOG" "insecure completion dirs" "insecure dir is logged"
sed -i '/insecure-completions/d' "$SB_HOME/.zshenv"

# ------------------------------------------------------------
test_case "missing tools are logged, not shown"
assert_true "error log created" test -s "$ZLOG"
assert_contains "$ZLOG" "fzf not found" "fzf logged"
assert_contains "$ZLOG" "zoxide not found" "zoxide logged"
assert_contains "$ZLOG" "oh-my-posh not found" "oh-my-posh logged"
assert_contains "$ZLOG" "eza not found" "eza logged"
zsh_run 'dotlog 5'
assert_true "dotlog prints entries" grep -q "not found" <<<"$OUT"
zsh_run 'dotlog clear; dotlog'
assert_true "dotlog clear empties the log" grep -q "No errors logged." <<<"$OUT"

# ------------------------------------------------------------
test_case "functions, aliases and key bindings"
zsh_run 'for f in desk set-desktop y rfgrep dots dotlog winopen; do whence -w $f; done'
for f in desk set-desktop y rfgrep dots dotlog winopen; do
  assert_true "$f is a function" grep -q "^$f: function" <<<"$OUT"
done
zsh_run 'alias la'
assert_true "la falls back to 'ls -A' without eza" grep -q "ls -A" <<<"$OUT"
zsh_run "bindkey '^H'; bindkey '^[[3;5~'; bindkey '^N'"
assert_true "Ctrl+Backspace -> path-backward-kill-word" grep -q "path-backward-kill-word" <<<"$OUT"
assert_true "Ctrl+Delete -> path-kill-word" grep -q "path-kill-word" <<<"$OUT"
assert_true "Ctrl+N -> rfgrep widget" grep -q "_rfgrep_widget" <<<"$OUT"

# ------------------------------------------------------------
test_case "desktop setting and local overrides"
mkdir -p "$SANDBOX/Desktop" "$SB_HOME/.config/zsh"
printf '%s\n' "$SANDBOX/Desktop" > "$SB_HOME/.config/zsh/desktop"
printf 'export LOCAL_MARK=loaded\n' > "$SB_HOME/.zshrc.local"
zsh_run 'print -r -- "D=$DESKTOP"; print -r -- "L=$LOCAL_MARK"; desk; print -r -- "PWD=$PWD"'
assert_true "saved desktop exported" grep -qx "D=$SANDBOX/Desktop" <<<"$OUT"
assert_true "~/.zshrc.local sourced" grep -qx "L=loaded" <<<"$OUT"
assert_true "desk changes directory" grep -qx "PWD=$SANDBOX/Desktop" <<<"$OUT"
: > "$SB_HOME/.config/zsh/desktop"
zsh_run 'desk'
assert_true "empty setting -> helpful message" grep -q "Run: set-desktop" <<<"$OUT"

# ------------------------------------------------------------
test_case "Ctrl+Backspace deletes one path segment"
# Drive a real interactive zsh through a pseudo-terminal
widget_out="$(SB_HOME="$SB_HOME" SBIN="$SANDBOX/bin" ZBIN="$ZSH_BIN" timeout 20 "$ZSH_BIN" -f -c '
  zmodload zsh/zpty || exit 3
  zpty t env -i HOME="$SB_HOME" PATH="$SBIN" TERM=dumb "$ZBIN" --no-globalrcs -i
  sleep 1
  zpty -w -n t "print -r -- RESULT:/mnt/c/Users/User1/file.txt"
  zpty -w -n t $'"'"'\x08\x08\r'"'"'      # Ctrl+Backspace twice, then Enter
  # read until the command output line appears (or timeout kills us)
  zpty -r t out "*RESULT:/mnt/c/Users/"$'"'"'\r'"'"'"*"
  zpty -d t
  print -r -- "$out"
' 2>/dev/null | tr -d '\r')"
if grep -q "^RESULT:/mnt/c/Users/\$" <<<"$widget_out"; then
  pass "two presses remove file.txt and User1/"
else
  fail "two presses remove file.txt and User1/" "$(grep -a 'RESULT' <<<"$widget_out" | tail -n 3)"
fi
cleanup_sandbox

summary
