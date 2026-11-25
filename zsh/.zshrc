# ============================================================
#  dotfiles: zsh config (linked to ~/.zshrc by install.sh)
#  Machine-specific settings go in ~/.zshrc.local (not in git).
# ============================================================

# Repo root, resolved through the ~/.zshrc symlink
export DOTFILES="${DOTFILES:-${${(%):-%x}:A:h:h}}"

# ------------------------------------------------------------
#  Error log: problems during startup go here instead of the screen
# ------------------------------------------------------------
DOTFILES_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/zsh-errors.log"
_dot_log() {
  mkdir -p "${DOTFILES_LOG:h}" 2>/dev/null
  print -r -- "[${(%):-%D{%Y-%m-%d %H:%M:%S}}] $*" >> "$DOTFILES_LOG"
}
# `dotlog` shows the last entries, `dotlog clear` empties the log
dotlog() {
  if [[ $1 == clear ]]; then : > "$DOTFILES_LOG"; return; fi
  [[ -s $DOTFILES_LOG ]] && tail -n "${1:-30}" "$DOTFILES_LOG" || print "No errors logged."
}

# ============================================================
#  PATH & environment
# ============================================================
typeset -U path PATH
[[ -d $HOME/.dotnet ]] && export DOTNET_ROOT="$HOME/.dotnet"   # installed by install.sh
path=(
  $HOME/.fzf/bin
  $HOME/.cargo/bin
  $HOME/.local/bin
  $HOME/.dotnet
  $HOME/.dotnet/tools
  $path
)
export PATH
export EDITOR="nvim"
export VISUAL="nvim"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniconda3}"   # override in ~/.zshrc.local

export FZF_DEFAULT_OPTS="\
  --bind 'ctrl-h:unix-word-rubout' \
  --bind 'ctrl-delete:kill-word' \
  --bind 'alt-l:preview-up' \
  --bind 'alt-n:preview-down' \
  --bind 'alt-u:preview-half-page-up' \
  --bind 'alt-e:preview-half-page-down' \
  --bind 'alt-y:preview-page-up' \
  --bind 'alt-i:preview-page-down'"
export FZF_CTRL_T_OPTS="--preview '[[ -d {} ]] && eza --tree --level=2 --color=always --group-directories-first {} || (file --mime-type {} | grep -q image && viu -w 40 -h 20 {} || bat --color=always --style=plain,numbers {})' --preview-window=right:50% --color=border:#808080 --bind 'enter:become(echo {}),ctrl-o:become(if [[ \$FZF_SELECT_COUNT -eq 0 ]]; then kitty -e nvim {}; else for entry in {+}; do [[ -n \"\$entry\" ]] && code \"\$entry\"; done; fi)'"

# ============================================================
#  Zinit & plugins
# ============================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" 2>>"$DOTFILES_LOG" \
    || _dot_log "zinit: git clone failed"
fi

if [[ -r "${ZINIT_HOME}/zinit.zsh" ]]; then
  source "${ZINIT_HOME}/zinit.zsh"
  _have_zinit=1
else
  _dot_log "zinit: not available, plugins skipped"
  _have_zinit=0
fi

(( _have_zinit )) && zinit light zsh-users/zsh-completions

# compinit: full security check at most once a day, fast path otherwise
autoload -Uz compinit compaudit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
_zcompdump_old=( $_zcompdump(N.mh+24) )
if [[ ! -f $_zcompdump ]] || (( ${#_zcompdump_old} )); then
  # -i: skip completion dirs that other users can write to instead of stopping
  # startup with a y/n question (happens with some package managers and on CI)
  _insecure=( ${(f)"$(compaudit 2>/dev/null)"} )
  (( ${#_insecure} )) && _dot_log "compinit: ignored insecure completion dirs: ${_insecure[*]} (fix: chmod g-w,o-w <dir>)"
  unset _insecure
  compinit -i
else
  compinit -C
fi
unset _zcompdump _zcompdump_old

if (( _have_zinit )); then
  zinit cdreplay -q
  zinit light Aloxaf/fzf-tab              # after compinit, before widget wrappers
  zinit light zsh-users/zsh-autosuggestions
fi
# zsh-syntax-highlighting is loaded at the very END of this file

# ============================================================
#  Completion styling
# ============================================================
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --no-symlinks --color=always --group-directories-first --sort=name $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --no-symlinks --color=always --group-directories-first --sort=name $realpath'

# ============================================================
#  Options & history
# ============================================================
setopt interactive_comments

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=$HISTSIZE
setopt share_history
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt hist_reduce_blanks

# ============================================================
#  Functions
# ============================================================
rfgrep() (
  rm -f /tmp/rg-fzf-{r,f}
  RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case "
  OPENER='if [[ $FZF_SELECT_COUNT -eq 0 ]]; then
           nvim {1} +{2}     # No selection. Open the current line in Vim.
         else
           nvim +cw -q {+f} # Build quickfix list for the selected items.
         fi'
  INITIAL_QUERY="${*:-}"
  fzf --ansi --multi --disabled --query "$INITIAL_QUERY" \
      --bind "start:reload:$RG_PREFIX {q}" \
      --bind "change:reload:sleep 0.1; $RG_PREFIX {q} || true" \
      --bind 'ctrl-n:transform:[[ ! $FZF_PROMPT =~ rg ]] &&
        echo "rebind(change)+change-prompt(1. rg> )+disable-search+transform-query:echo \{q} > /tmp/rg-fzf-f; cat /tmp/rg-fzf-r" ||
        echo "unbind(change)+change-prompt(2. fzf> )+enable-search+transform-query:echo \{q} > /tmp/rg-fzf-r; cat /tmp/rg-fzf-f"' \
      --color "hl:-1:underline,hl+:-1:underline:reverse" \
      --prompt '1. rg> ' \
      --delimiter : \
      --header 'CTRL-N: Switch between rg/fzf' \
      --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
      --preview-window 'up,60%,+{2}-7/7,<80(up)' \
      --bind "enter:become:$OPENER" \
      --bind "ctrl-o:execute:$OPENER"
)

winopen() {
  explorer.exe "$(wslpath -w "$(realpath "${1:-.}")")"
}

# yazi: `y` opens yazi; quitting with q changes the shell to the last directory
y() {
  local tmp cwd
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [[ -n $cwd && $cwd != "$PWD" ]] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Jump to the dotfiles repo
dots() { cd "$DOTFILES" }

# ============================================================
#  Keybindings
# ============================================================
bindkey -e

bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
[[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" history-search-backward
[[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" history-search-forward

bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# Path-aware word widgets: "/" is a separator, so Ctrl+Backspace on
# /mnt/c/Users/User1/file.txt removes file.txt -> User1/ -> Users/ ...
# Alt+Backspace keeps the whole-word behaviour.
_path_word() {
  local WORDCHARS=${WORDCHARS//\//}
  zle ${WIDGET#path-}
}
for _w in backward-kill-word kill-word backward-word forward-word; do
  zle -N path-$_w _path_word
done
unset _w

bindkey '^H'      path-backward-kill-word   # Ctrl+Backspace
bindkey '^[[3;5~' path-kill-word            # Ctrl+Delete
bindkey '^[[1;5D' path-backward-word        # Ctrl+Left
bindkey '^[[1;5C' path-forward-word         # Ctrl+Right

# Ctrl+N: rfgrep, keeping what you typed and staying out of history
_rfgrep_widget() {
  zle push-input
  BUFFER=" rfgrep"
  zle accept-line
}
zle -N _rfgrep_widget
bindkey '^N' _rfgrep_widget

# Ctrl+X Ctrl+E: edit the current command in nvim
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# ============================================================
#  Aliases (only when the tool exists, otherwise logged)
# ============================================================
if (( $+commands[eza] )); then
  alias ls='eza -1 --color=auto --group-directories-first --sort=name'
  alias la='eza -a -1 --color=auto --group-directories-first --sort=name'
else
  _dot_log "eza not found: ls/la use the system ls"
  alias la='ls -A'
fi
if (( $+commands[bat] )); then
  alias cat='bat'
else
  _dot_log "bat not found: cat is not aliased"
fi
alias c='clear && printf "\033[3J"'
alias vim='nvim'

# ============================================================
#  Shell integrations (fzf after fzf-tab, so TAB falls back correctly)
# ============================================================
if (( $+commands[fzf] )); then
  eval "$(fzf --zsh 2>>"$DOTFILES_LOG")" || _dot_log "fzf: init failed"
else
  _dot_log "fzf not found: Ctrl+T/Ctrl+R/Alt+C unavailable"
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init --cmd cd zsh 2>>"$DOTFILES_LOG")" || _dot_log "zoxide: init failed"
else
  _dot_log "zoxide not found: cd is the plain builtin"
fi

_omp_config="${XDG_CONFIG_HOME:-$HOME/.config}/ohmyposh/config.toml"
if (( $+commands[oh-my-posh] )); then
  eval "$(oh-my-posh init zsh --config "$_omp_config" 2>>"$DOTFILES_LOG")" \
    || _dot_log "oh-my-posh: init failed (config: $_omp_config)"
else
  _dot_log "oh-my-posh not found: default prompt"
fi
unset _omp_config

# ============================================================
#  Conda (lazy: the hook runs the first time you type `conda`)
# ============================================================
if [[ -x "$CONDA_ROOT/bin/conda" ]]; then
  conda() {
    unfunction conda
    local __conda_setup
    if __conda_setup="$("$CONDA_ROOT/bin/conda" shell.zsh hook 2>>"$DOTFILES_LOG")"; then
      eval "$__conda_setup"
    elif [[ -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
      . "$CONDA_ROOT/etc/profile.d/conda.sh"
    else
      _dot_log "conda: hook failed, adding $CONDA_ROOT/bin to PATH"
      path=("$CONDA_ROOT/bin" $path)
    fi
    conda "$@"
  }
fi

# ============================================================
#  Windows Desktop (WSL): detected once, saved, re-run with `set-desktop`
# ============================================================
DESKTOP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/desktop"

set-desktop() {
  local -a candidates
  local win d choice

  if (( $+commands[powershell.exe] )); then
    print -P "%F{8}Asking Windows where the Desktop is...%f"
    win=$(powershell.exe -NoProfile -NonInteractive -Command \
      '[Environment]::GetFolderPath("Desktop")' 2>>"$DOTFILES_LOG" | tr -d '\r')
    [[ -n $win ]] && win=$(wslpath -u "$win" 2>>"$DOTFILES_LOG")
    [[ -d $win ]] && candidates+=("$win")
  fi

  for d in /mnt/c/Users/*/{Desktop,OneDrive*/Desktop}(N/); do
    [[ $d == /mnt/c/Users/(Public|Default|Default\ User|All\ Users)/* ]] && continue
    candidates+=("$d")
  done
  candidates=( ${(u)candidates} )

  if (( ${#candidates} )); then
    if (( $+commands[fzf] )); then
      choice=$(printf '%s\n' "${candidates[@]}" | fzf --height=~40% --reverse \
        --prompt='Desktop> ' --header='Pick your Desktop (Esc = type a path)')
    else
      print "Pick your Desktop folder:"
      select choice in "${candidates[@]}"; do [[ -n $choice ]] && break; done
    fi
  else
    print -P "%F{yellow}No Desktop folder found automatically.%f"
  fi

  if [[ -z $choice ]]; then
    read -r "choice?Desktop path (leave empty to skip): "
    choice=${choice/#\~/$HOME}
  fi

  mkdir -p "${DESKTOP_CONF:h}"
  if [[ -n $choice && -d $choice ]]; then
    print -r -- "$choice" > "$DESKTOP_CONF"
    export DESKTOP="$choice"
    print -P "%F{green}Desktop set to:%f $DESKTOP"
    print -P "%F{8}Active now, no restart needed. Use 'desk' to go there, \$DESKTOP in commands, 'set-desktop' to change it.%f"
  else
    if [[ -n $choice ]]; then
      print -P "%F{red}Not a directory:%f $choice"
      _dot_log "set-desktop: '$choice' is not a directory"
    fi
    : > "$DESKTOP_CONF"
    unset DESKTOP
    print -P "%F{yellow}Desktop not set. Run 'set-desktop' any time to configure it.%f"
  fi
}

desk() {
  if [[ -d $DESKTOP ]]; then
    cd "$DESKTOP"
  else
    print "Desktop not set. Run: set-desktop"
  fi
}

if [[ -f $DESKTOP_CONF ]]; then
  DESKTOP=$(<"$DESKTOP_CONF")
  [[ -n $DESKTOP ]] && export DESKTOP || unset DESKTOP
elif [[ -n $WSL_DISTRO_NAME && -t 0 ]]; then
  print -P "%F{cyan}First run: let's find your Windows Desktop.%f"
  set-desktop
fi

# ============================================================
#  Machine-specific overrides (not tracked in git)
# ============================================================
[[ -r ~/.zshrc.local ]] && source ~/.zshrc.local

# ============================================================
#  Must be last: highlights every widget defined above
# ============================================================
(( _have_zinit )) && zinit light zsh-users/zsh-syntax-highlighting
unset _have_zinit
