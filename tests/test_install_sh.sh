#!/usr/bin/env bash
# shellcheck disable=SC2088  # "~" in test messages is text, not a path
# Tests for install.sh (links, idempotence, backups, error logging).
# Runs entirely in a temporary sandbox; never touches your real home.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Run the sandboxed installer: sb_install [args...]; sets OUT and RC
sb_install() {
  OUT="$(env -u XDG_CONFIG_HOME DOTFILES_TARGET_HOME="$SB_HOME" DOTFILES_LOG_DIR="$SB_LOGS" \
    bash "$SB_REPO/install.sh" "$@" 2>&1)"
  RC=$?
}
error_logs() { compgen -G "$SB_LOGS/install-errors-*.log" || true; }

# ------------------------------------------------------------
test_case "syntax"
assert_true "install.sh parses" bash -n "$REPO_ROOT/install.sh"
if command -v shellcheck >/dev/null; then
  if out="$(shellcheck -S warning "$REPO_ROOT/install.sh" 2>&1)"; then pass "shellcheck clean"
  else fail "shellcheck clean" "$out"; fi
else
  skip "shellcheck not installed"
fi

# ------------------------------------------------------------
test_case "fresh install (--links-only)"
make_sandbox
sb_install --links-only
assert_eq 0 "$RC" "exits 0"
assert_link "$SB_HOME/.zshrc"            "$SB_REPO/zsh/.zshrc" "~/.zshrc linked"
assert_link "$SB_HOME/.config/nvim"      "$SB_REPO/nvim"       "~/.config/nvim linked"
assert_link "$SB_HOME/.config/yazi"      "$SB_REPO/yazi"       "~/.config/yazi linked"
assert_link "$SB_HOME/.config/ohmyposh"  "$SB_REPO/ohmyposh"   "~/.config/ohmyposh linked"
assert_true "~/.zshrc.local template created" test -f "$SB_HOME/.zshrc.local"
assert_eq "" "$(error_logs)" "no error log written"
assert_true "full log written" bash -c "compgen -G \"$SB_LOGS/install-*.log\" >/dev/null"

# ------------------------------------------------------------
test_case "re-run is idempotent"
sleep 1   # new timestamp, so a new backup dir would be detectable
sb_install --links-only
assert_eq 0 "$RC" "exits 0"
assert_true "reports existing links as ok" grep -q "ok $SB_HOME/.zshrc" <<<"$OUT"
assert_false "no backup directory created" test -d "$SB_HOME/.dotfiles-backup"
assert_link "$SB_HOME/.zshrc" "$SB_REPO/zsh/.zshrc" "link unchanged"
cleanup_sandbox

# ------------------------------------------------------------
test_case "existing files are backed up, not overwritten"
make_sandbox
printf 'old zshrc\n' > "$SB_HOME/.zshrc"
mkdir -p "$SB_HOME/.config/nvim" && printf 'old init\n' > "$SB_HOME/.config/nvim/init.lua"
sb_install --links-only
assert_eq 0 "$RC" "exits 0"
backup="$(compgen -G "$SB_HOME/.dotfiles-backup/*" | head -n1)"
assert_true "backup directory created" test -d "$backup"
assert_eq "old zshrc" "$(cat "$backup/.zshrc" 2>/dev/null)" "old .zshrc preserved"
assert_eq "old init" "$(cat "$backup/.config/nvim/init.lua" 2>/dev/null)" "old nvim config preserved"
assert_link "$SB_HOME/.zshrc" "$SB_REPO/zsh/.zshrc" "~/.zshrc now linked"
cleanup_sandbox

# ------------------------------------------------------------
test_case "links pointing elsewhere are replaced"
make_sandbox
mkdir -p "$SB_HOME/.config" "$SANDBOX/elsewhere"
ln -s "$SANDBOX/elsewhere" "$SB_HOME/.config/yazi"
sb_install --links-only
assert_eq 0 "$RC" "exits 0"
assert_link "$SB_HOME/.config/yazi" "$SB_REPO/yazi" "yazi link fixed"
assert_true "old target untouched" test -d "$SANDBOX/elsewhere"
cleanup_sandbox

# ------------------------------------------------------------
test_case "existing ~/.zshrc.local is kept"
make_sandbox
printf 'CONDA_ROOT=/opt/conda\n' > "$SB_HOME/.zshrc.local"
sb_install --links-only
assert_eq "CONDA_ROOT=/opt/conda" "$(cat "$SB_HOME/.zshrc.local")" ".zshrc.local unchanged"
cleanup_sandbox

# ------------------------------------------------------------
test_case "--dry-run changes nothing"
make_sandbox
sb_install --links-only --dry-run
assert_eq 0 "$RC" "exits 0"
assert_false "no ~/.zshrc created" test -e "$SB_HOME/.zshrc"
assert_false "no ~/.config created" test -e "$SB_HOME/.config"
assert_true "announces dry run" grep -q "DRY RUN" <<<"$OUT"
cleanup_sandbox

# ------------------------------------------------------------
test_case "errors are logged and the run continues"
make_sandbox
printf 'not a directory\n' > "$SB_HOME/.config"     # makes ~/.config/* impossible
sb_install --links-only
assert_eq 1 "$RC" "exits 1"
errlog="$(error_logs | head -n1)"
assert_true "error log written" test -s "$errlog"
assert_contains "$errlog" "nvim" "error log names the failed link"
assert_link "$SB_HOME/.zshrc" "$SB_REPO/zsh/.zshrc" "other links still created"
assert_true "summary points to the error log" grep -q "Details: $errlog" <<<"$OUT"
cleanup_sandbox

# ------------------------------------------------------------
test_case "argument handling"
make_sandbox
sb_install --bogus
assert_eq 2 "$RC" "unknown option exits 2"
sb_install --help
assert_eq 0 "$RC" "--help exits 0"
cleanup_sandbox

summary
