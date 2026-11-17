#!/usr/bin/env bash
# ============================================================
#  dotfiles installer for WSL / Linux. Safe to re-run.
#
#  ./install.sh                 everything: packages, links, post-setup
#  ./install.sh --links-only    only (re)create config links
#  ./install.sh --skip-packages links + post-setup
#  ./install.sh --dry-run       show what would happen, change nothing
#
#  Logs:   logs/install-<timestamp>.log         (everything)
#          logs/install-errors-<timestamp>.log  (only when something failed)
# ============================================================
[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"
set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${DOTFILES_TARGET_HOME:-$HOME}"          # overridable for tests
CONFIG_DIR="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"
BIN_DIR="$TARGET_HOME/.local/bin"
OPT_DIR="$TARGET_HOME/.local/opt"
LOG_DIR="${DOTFILES_LOG_DIR:-$DOTFILES_ROOT/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/install-$TIMESTAMP.log"
ERROR_LOG="$LOG_DIR/install-errors-$TIMESTAMP.log"
BACKUP_DIR="$TARGET_HOME/.dotfiles-backup/$TIMESTAMP"

DO_PACKAGES=1
DO_LINKS=1
DO_POST=1
DRY_RUN=0
ERRORS=0

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^#  \{0,1\}//'
}

while (( $# )); do
  case "$1" in
    --links-only)    DO_PACKAGES=0; DO_POST=0 ;;
    --skip-packages) DO_PACKAGES=0 ;;
    --no-post)       DO_POST=0 ;;
    --dry-run)       DRY_RUN=1 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

mkdir -p "$LOG_DIR" || { echo "Cannot create log directory $LOG_DIR" >&2; exit 1; }

# ------------------------------------------------------------
#  Logging
# ------------------------------------------------------------
log() {
  printf '%s\n' "$*"
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG_FILE"
}
warn() { log "WARN  $*"; }
err() {
  ERRORS=$((ERRORS + 1))
  printf '\033[31mERROR\033[0m %s\n' "$*" >&2
  printf '[%s] ERROR %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
}
section() { log ""; log "==> $*"; }

# run "description" command args...  -> output to the log, failures to the error log
run() {
  local desc=$1; shift
  if (( DRY_RUN )); then log "[dry-run] $desc: $*"; return 0; fi
  log "  - $desc"
  local out rc
  out=$("$@" 2>&1); rc=$?
  [[ -n $out ]] && printf '%s\n' "$out" >> "$LOG_FILE"
  if (( rc != 0 )); then
    err "$desc failed (exit $rc): $*"
    { printf '%s\n' "$out" | tail -n 25; echo; } >> "$ERROR_LOG"
    return "$rc"
  fi
  return 0
}

have() { command -v "$1" >/dev/null 2>&1; }

# version_ge 0.11.2 0.10  -> true
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

is_wsl() { [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/version 2>/dev/null; }

SUDO=""
if (( EUID != 0 )); then SUDO="sudo"; fi

export DOTNET_ROOT="$TARGET_HOME/.dotnet"
export PATH="$BIN_DIR:$TARGET_HOME/.fzf/bin:$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *)             ARCH=unknown ;;
esac

# Download $1 to a temp file, print its path
fetch() {
  local url=$1 tmp
  tmp="$(mktemp -d)/$(basename "$url")"
  run "download $(basename "$url")" curl -fsSL "$url" -o "$tmp" >&2 || return 1
  printf '%s' "$tmp"
}

# ------------------------------------------------------------
#  Packages
# ------------------------------------------------------------
install_apt_packages() {
  if ! have apt-get; then warn "apt-get not found, skipping apt packages"; return; fi
  if [[ -n $SUDO ]] && ! (( DRY_RUN )); then
    sudo -v || { err "sudo authentication failed"; return 1; }
  fi
  run "apt-get update" $SUDO apt-get update
  local pkg
  while IFS= read -r pkg; do
    pkg="${pkg%%#*}"; pkg="${pkg//[[:space:]]/}"
    [[ -z $pkg ]] && continue
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log "  ok $pkg"
    else
      run "apt install $pkg" $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    fi
  done < "$DOTFILES_ROOT/packages/apt.txt"
}

make_name_shims() {
  # Debian/Ubuntu ship bat as batcat and fd as fdfind
  if have batcat && ! have bat; then run "bat -> batcat shim" ln -sf "$(command -v batcat)" "$BIN_DIR/bat"; fi
  if have fdfind && ! have fd;  then run "fd -> fdfind shim"  ln -sf "$(command -v fdfind)" "$BIN_DIR/fd"; fi
}

install_nvim() {
  if have nvim; then
    local v; v="$(nvim --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')"
    if version_ge "$v" "0.12"; then log "  ok nvim $v"; return; fi
    warn "nvim $v is too old (config needs 0.12+), installing the latest release"
  fi
  [[ $ARCH == unknown ]] && { err "nvim: unsupported architecture $(uname -m)"; return 1; }
  local arch=$ARCH; [[ $arch == aarch64 ]] && arch=arm64
  local name="nvim-linux-$arch"
  (( DRY_RUN )) && { log "[dry-run] install $name"; return; }
  local tar; tar="$(fetch "https://github.com/neovim/neovim/releases/latest/download/$name.tar.gz")" || return 1
  mkdir -p "$OPT_DIR" "$BIN_DIR"
  rm -rf "${OPT_DIR:?}/$name"
  run "extract nvim" tar -xzf "$tar" -C "$OPT_DIR" || return 1
  run "link nvim" ln -sfn "$OPT_DIR/$name/bin/nvim" "$BIN_DIR/nvim"
}

install_fzf() {
  if have fzf; then
    local v; v="$(fzf --version | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?')"
    if version_ge "$v" "0.48"; then log "  ok fzf $v"; return; fi
    warn "fzf $v is too old for 'fzf --zsh', installing to ~/.fzf"
  fi
  if [[ -d $TARGET_HOME/.fzf/.git ]]; then
    run "update ~/.fzf" git -C "$TARGET_HOME/.fzf" pull --ff-only
  else
    run "clone fzf" git clone --depth 1 https://github.com/junegunn/fzf.git "$TARGET_HOME/.fzf" || return 1
  fi
  run "install fzf binary" "$TARGET_HOME/.fzf/install" --bin
}

install_zoxide() {
  if have zoxide; then log "  ok zoxide"; return; fi
  run "install zoxide" bash -c \
    "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir '$BIN_DIR'"
}

install_oh_my_posh() {
  if have oh-my-posh; then log "  ok oh-my-posh"; return; fi
  run "install oh-my-posh" bash -c "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d '$BIN_DIR'"
}

install_yazi() {
  if have yazi; then log "  ok yazi"; return; fi
  [[ $ARCH == unknown ]] && { err "yazi: unsupported architecture"; return 1; }
  (( DRY_RUN )) && { log "[dry-run] install yazi"; return; }
  local name="yazi-$ARCH-unknown-linux-gnu" zip dir
  zip="$(fetch "https://github.com/sxyazi/yazi/releases/latest/download/$name.zip")" || return 1
  dir="$(dirname "$zip")"
  run "unzip yazi" unzip -oq "$zip" -d "$dir" || return 1
  mkdir -p "$BIN_DIR"
  run "install yazi binaries" install -m 755 "$dir/$name/yazi" "$dir/$name/ya" "$BIN_DIR/"
}

# eza: the aliases use --no-symlinks, added in eza 0.18.20. Ubuntu's apt
# package is older, so the release binary goes to ~/.local/bin (first on PATH).
install_eza() {
  if have eza; then
    local v; v="$(eza --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d v)"
    if version_ge "$v" "0.18.20"; then log "  ok eza $v"; return; fi
    warn "eza ${v:-?} is too old for --no-symlinks, installing the latest release to $BIN_DIR"
  fi
  [[ $ARCH == unknown ]] && { err "eza: unsupported architecture"; return 1; }
  (( DRY_RUN )) && { log "[dry-run] install eza"; return; }
  local tgz; tgz="$(fetch "https://github.com/eza-community/eza/releases/latest/download/eza_$ARCH-unknown-linux-gnu.tar.gz")" || return 1
  mkdir -p "$BIN_DIR"
  run "extract eza" tar -xzf "$tgz" -C "$BIN_DIR" || return 1
  hash -r
}

# Node.js: Mason installs basedpyright and json-lsp with npm
install_node() {
  if have node; then
    local v; v="$(node --version | tr -d v)"
    if version_ge "$v" "20"; then log "  ok node $v"; return; fi
    warn "node $v is too old, installing the current LTS"
  fi
  local arch
  case $ARCH in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) err "node: unsupported architecture"; return 1 ;; esac
  (( DRY_RUN )) && { log "[dry-run] install node LTS"; return; }
  local base="https://nodejs.org/dist/latest-v24.x" name tar
  name="$(curl -fsSL "$base/SHASUMS256.txt" 2>>"$LOG_FILE" | grep -oE "node-v[0-9.]+-linux-$arch\.tar\.xz" | head -n1)"
  [[ -z $name ]] && { err "node: could not find a release in $base"; return 1; }
  tar="$(fetch "$base/$name")" || return 1
  mkdir -p "$OPT_DIR" "$BIN_DIR"
  run "extract node" tar -xJf "$tar" -C "$OPT_DIR" || return 1
  ln -sfn "$OPT_DIR/${name%.tar.xz}" "$OPT_DIR/node"
  local b
  for b in node npm npx; do ln -sf "$OPT_DIR/node/bin/$b" "$BIN_DIR/$b"; done
  log "  installed $(node --version 2>/dev/null) to $OPT_DIR/node"
}

# .NET SDK (LTS): roslyn language server, csharpier, netcoredbg
install_dotnet() {
  if have dotnet && [[ -n "$(dotnet --list-sdks 2>/dev/null)" ]]; then log "  ok dotnet $(dotnet --version 2>/dev/null)"; return; fi
  run "install .NET SDK (LTS) to ~/.dotnet" bash -c \
    "curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS --install-dir '$DOTNET_ROOT'"
}

# wslview: lets nvim (typst-preview, gx) open links in the Windows browser
install_wslu() {
  is_wsl || return 0
  if have wslview; then log "  ok wslu"; return; fi
  have apt-get && run "apt install wslu" $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y wslu
}

install_win32yank() {
  is_wsl || return 0
  if have win32yank.exe; then log "  ok win32yank"; return; fi
  (( DRY_RUN )) && { log "[dry-run] install win32yank"; return; }
  local zip; zip="$(fetch "https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip")" || return 1
  mkdir -p "$BIN_DIR"
  run "unzip win32yank" unzip -oq "$zip" win32yank.exe -d "$BIN_DIR" && chmod +x "$BIN_DIR/win32yank.exe"
}

install_packages() {
  section "Packages"
  mkdir -p "$BIN_DIR"
  install_apt_packages
  make_name_shims
  install_nvim
  install_fzf
  install_zoxide
  install_oh_my_posh
  install_yazi
  install_eza
  install_win32yank
  install_wslu
  install_node
  install_dotnet
  have viu || log "  (optional) viu is not installed; image previews in Ctrl+T need: cargo install viu"
}

# ------------------------------------------------------------
#  Links
# ------------------------------------------------------------
# link SOURCE DEST: make DEST a symlink to SOURCE, backing up whatever was there
link() {
  local src=$1 dst=$2
  if [[ ! -e $src ]]; then err "link: source missing: $src"; return 1; fi
  if [[ -L $dst && "$(readlink "$dst")" == "$src" ]]; then
    log "  ok $dst"
    return 0
  fi
  if (( DRY_RUN )); then log "[dry-run] link $dst -> $src"; return 0; fi

  if ! mkdir -p "$(dirname "$dst")" 2>>"$LOG_FILE"; then
    err "link: cannot create parent directory of $dst"
    return 1
  fi

  if [[ -L $dst ]]; then
    log "  replacing link $dst (was -> $(readlink "$dst"))"
    rm -f "$dst" || { err "link: cannot remove old link $dst"; return 1; }
  elif [[ -e $dst ]]; then
    local rel
    if [[ $dst == "$TARGET_HOME"/* ]]; then rel="${dst#"$TARGET_HOME"/}"; else rel="$(basename "$dst")"; fi
    mkdir -p "$(dirname "$BACKUP_DIR/$rel")" &&
      mv "$dst" "$BACKUP_DIR/$rel" 2>>"$LOG_FILE" || { err "link: cannot back up $dst"; return 1; }
    log "  backed up $dst -> $BACKUP_DIR/$rel"
  fi

  if ln -s "$src" "$dst" 2>>"$LOG_FILE"; then
    log "  linked $dst -> $src"
  else
    err "link: ln -s failed for $dst"
    return 1
  fi
}

create_local_template() {
  local file="$TARGET_HOME/.zshrc.local"
  [[ -e $file ]] && return 0
  (( DRY_RUN )) && { log "[dry-run] create $file"; return 0; }
  cat > "$file" <<'EOF' || { err "cannot create $file"; return 1; }
# Machine-specific zsh settings (not tracked in git).
# Examples:
# CONDA_ROOT="$HOME/miniconda3"
# export SOME_TOKEN="..."
EOF
  log "  created $file (machine-specific settings)"
}

# Ubuntu/Debian's /etc/zsh/zshrc runs its own compinit before ~/.zshrc: that
# doubles startup work and asks a y/n question if a completion dir is insecure.
# This line (read from ~/.zshenv, before /etc/zsh/zshrc) turns it off.
ensure_zshenv() {
  local file="$TARGET_HOME/.zshenv" line="skip_global_compinit=1"
  if [[ -f $file ]] && grep -qx "$line" "$file"; then log "  ok $file"; return 0; fi
  (( DRY_RUN )) && { log "[dry-run] add $line to $file"; return 0; }
  printf '\n# Added by dotfiles install.sh: ~/.zshrc runs compinit itself\n%s\n' "$line" >> "$file" \
    || { err "cannot write $file"; return 1; }
  log "  added $line to $file"
}

link_configs() {
  section "Config links"
  link "$DOTFILES_ROOT/zsh/.zshrc" "$TARGET_HOME/.zshrc"
  link "$DOTFILES_ROOT/nvim"       "$CONFIG_DIR/nvim"
  link "$DOTFILES_ROOT/yazi"       "$CONFIG_DIR/yazi"
  link "$DOTFILES_ROOT/ohmyposh"   "$CONFIG_DIR/ohmyposh"
  create_local_template
  ensure_zshenv
}

# ------------------------------------------------------------
#  Post-setup
# ------------------------------------------------------------
post_setup() {
  section "Post-setup"
  if have zsh; then
    local zsh_path current
    zsh_path="$(command -v zsh)"
    current="$(getent passwd "$(id -un)" | cut -d: -f7)"
    if [[ $current != */zsh ]]; then
      run "set zsh as login shell" $SUDO chsh -s "$zsh_path" "$(id -un)"
    else
      log "  ok login shell is zsh"
    fi
  else
    warn "zsh not installed, login shell unchanged"
  fi

  if have nvim && [[ -f $DOTFILES_ROOT/nvim/init.lua ]]; then
    # Order matters: Mason installs the tree-sitter CLI that compiles the parsers.
    # Timeouts keep a stuck download (e.g. GitHub API rate limit) from hanging the install.
    run "install nvim plugins (lazy.nvim)" timeout 900 nvim --headless "+Lazy! restore" +qa
    run "install LSPs, formatters and debuggers (Mason)" timeout 1800 nvim --headless "+MasonToolsInstallSync" +qa
    run "compile treesitter parsers" timeout 900 nvim --headless "+TSInstallSync" +qa
  fi
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
log "dotfiles: $DOTFILES_ROOT"
log "target home: $TARGET_HOME"
(( DRY_RUN )) && log "DRY RUN: nothing will be changed"

(( DO_PACKAGES )) && install_packages
(( DO_LINKS ))    && link_configs
(( DO_POST ))     && post_setup

log ""
if (( ERRORS > 0 )); then
  log "Finished with $ERRORS error(s). Details: $ERROR_LOG"
  exit 1
fi
log "Done. Full log: $LOG_FILE"
[[ -d $BACKUP_DIR ]] && log "Previous configs were backed up to $BACKUP_DIR"
(( DO_LINKS && ! DRY_RUN )) && log "Open a new terminal (or run: exec zsh) to load the config."
exit 0
