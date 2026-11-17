# ============================================================
#  dotfiles: PowerShell 7 profile
#  Loaded by the stub that install.ps1 writes to $PROFILE.
#  Machine-specific settings go in pwsh\profile.local.ps1 (not in git).
# ============================================================

if (-not $env:DOTFILES) { $env:DOTFILES = Split-Path -Parent $PSScriptRoot }

# ------------------------------------------------------------
#  Error log: problems during startup go here instead of the screen
# ------------------------------------------------------------
$DotLogDir = if ($env:DOTFILES_LOG_DIR) { $env:DOTFILES_LOG_DIR }
             elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dotfiles' }
             else { Join-Path $HOME '.local/state/dotfiles' }
$DotLogFile = Join-Path $DotLogDir 'pwsh-errors.log'

function Write-DotLog {
    param([string]$Message)
    try {
        if (-not (Test-Path $DotLogDir)) { New-Item -ItemType Directory -Path $DotLogDir -Force | Out-Null }
        Add-Content -Path $DotLogFile -Value ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message)
    } catch { }
}

# `dotlog` shows the last entries, `dotlog clear` empties the log
function dotlog {
    param([string]$Arg = '30')
    if ($Arg -eq 'clear') { Clear-Content -Path $DotLogFile -ErrorAction SilentlyContinue; return }
    if ((Test-Path $DotLogFile) -and (Get-Item $DotLogFile).Length -gt 0) {
        Get-Content -Path $DotLogFile -Tail ([int]$Arg)
    } else { 'No errors logged.' }
}

function Test-DotCommand { param([string]$Name) [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue) }

$DotPrevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Stop'      # make every failure catchable below

# ============================================================
#  Environment
# ============================================================
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

$env:FZF_DEFAULT_OPTS = @(
    "--bind 'ctrl-h:unix-word-rubout'"
    "--bind 'ctrl-delete:kill-word'"
    "--bind 'alt-l:preview-up'"
    "--bind 'alt-n:preview-down'"
    "--bind 'alt-u:preview-half-page-up'"
    "--bind 'alt-e:preview-half-page-down'"
    "--bind 'alt-y:preview-page-up'"
    "--bind 'alt-i:preview-page-down'"
) -join ' '
$DotPreviewScript = Join-Path $env:DOTFILES 'pwsh/fzf-preview.ps1'
$env:FZF_CTRL_T_OPTS = "--preview 'pwsh -NoLogo -NoProfile -File ""$DotPreviewScript"" {}' --preview-window=right:50% --color=border:#808080"

# yazi on Windows needs `file`; fall back to the one bundled with Git
if (-not (Test-DotCommand 'file') -and -not $env:YAZI_FILE_ONE) {
    foreach ($candidate in @(
        (Join-Path $HOME 'scoop/apps/git/current/usr/bin/file.exe'),
        'C:\Program Files\Git\usr\bin\file.exe')) {
        if (Test-Path $candidate) { $env:YAZI_FILE_ONE = $candidate; break }
    }
}

# ============================================================
#  Helpers
# ============================================================
. (Join-Path $PSScriptRoot 'lib/PathSegments.ps1')

# ============================================================
#  PSReadLine (only in a real interactive console)
# ============================================================
$DotInteractive = ($Host.Name -eq 'ConsoleHost') -and [Environment]::UserInteractive -and
                  -not ([Environment]::GetCommandLineArgs() -match '^-NonI')

if ($DotInteractive) {
    try {
        Import-Module PSReadLine
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineOption -MaximumHistoryCount 50000
        Set-PSReadLineOption -HistoryNoDuplicates
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd
        Set-PSReadLineOption -PredictionSource History       # like zsh-autosuggestions
        Set-PSReadLineOption -PredictionViewStyle InlineView

        # Up/Down: prefix history search
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

        # Path-segment editing (same behaviour as the zsh widgets)
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Backspace' -BriefDescription 'BackwardKillPathSegment' -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            $start = Get-DotSegmentStart $line $cursor
            if ($start -lt $cursor) { [Microsoft.PowerShell.PSConsoleReadLine]::Delete($start, $cursor - $start) }
        }
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Delete' -BriefDescription 'KillPathSegment' -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            $end = Get-DotSegmentEnd $line $cursor
            if ($end -gt $cursor) { [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor, $end - $cursor) }
        }
        Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -BriefDescription 'BackwardPathSegment' -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition((Get-DotSegmentStart $line $cursor))
        }
        Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -BriefDescription 'ForwardPathSegment' -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition((Get-DotSegmentEnd $line $cursor))
        }

        # Ctrl+X Ctrl+E: edit the current command in nvim
        Set-PSReadLineKeyHandler -Chord 'Ctrl+x,Ctrl+e' -Function ViEditVisually

        # Ctrl+N: rfgrep without losing what you typed
        Set-PSReadLineKeyHandler -Chord 'Ctrl+n' -BriefDescription 'rfgrep' -ScriptBlock {
            rfgrep
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    } catch { Write-DotLog "PSReadLine: $_" }

    # fzf: Ctrl+T files, Ctrl+R history, Tab completion (like fzf-tab)
    if (Test-DotCommand 'fzf') {
        try {
            Import-Module PSFzf
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
            if (Test-DotCommand 'fd') { Set-PsFzfOption -EnableFd }
            Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
        } catch { Write-DotLog "PSFzf: $_ (install with: Install-Module PSFzf -Scope CurrentUser)" }
    } else { Write-DotLog 'fzf not found: Ctrl+T/Ctrl+R/fzf Tab unavailable' }
}

# ============================================================
#  Functions & aliases
# ============================================================
if (Test-DotCommand 'eza') {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza -1 --no-symlinks --color=auto --group-directories-first --sort=name @args }
    function la { eza -a -1 --no-symlinks --color=auto --group-directories-first --sort=name @args }
} else {
    Write-DotLog 'eza not found: ls is Get-ChildItem'
    function la { Get-ChildItem -Force @args }
}

if (Test-DotCommand 'bat') {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat @args }
} else { Write-DotLog 'bat not found: cat is Get-Content' }

function c { Clear-Host; [Console]::Write("`e[3J") }
Set-Alias -Name vim -Value nvim

# yazi: `y` opens yazi; quitting with q changes to the last directory
function y {
    $tmp = (New-TemporaryFile).FullName
    try {
        yazi @args --cwd-file="$tmp"
        $cwd = Get-Content -Path $tmp -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($cwd -and $cwd -ne $PWD.Path -and (Test-Path -LiteralPath $cwd -PathType Container)) {
            Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
        }
    } finally { Remove-Item -Path $tmp -ErrorAction SilentlyContinue }
}

# Open a folder or file in Explorer (default: current folder)
function winopen { param([string]$Path = '.') Invoke-Item -LiteralPath $Path }

# Desktop: Windows knows where it is, no detection needed
$env:DESKTOP = [Environment]::GetFolderPath('Desktop')
function desk {
    if ($env:DESKTOP -and (Test-Path $env:DESKTOP)) { Set-Location $env:DESKTOP }
    else { 'Desktop folder not found.' }
}

function dots { Set-Location $env:DOTFILES }

# Live ripgrep -> fzf -> nvim (Enter opens the line; multi-select builds a quickfix list)
function rfgrep {
    foreach ($tool in 'rg', 'fzf', 'nvim') {
        if (-not (Test-DotCommand $tool)) { Write-Warning "rfgrep needs $tool"; Write-DotLog "rfgrep: $tool not found"; return }
    }
    $query  = $args -join ' '
    $rg     = 'rg --column --line-number --no-heading --color=always --smart-case'
    $preview = if (Test-DotCommand 'bat') { 'bat --style=numbers --color=always --highlight-line {2} {1}' } else { '' }
    $opener = if ($IsWindows) {
        'if %FZF_SELECT_COUNT%==0 (nvim {1} +{2}) else (nvim +cw -q {+f})'
    } else {
        'if [ "$FZF_SELECT_COUNT" -eq 0 ]; then nvim {1} +{2}; else nvim +cw -q {+f}; fi'
    }
    $fzfArgs = @(
        '--ansi', '--multi', '--disabled', '--query', $query,
        '--bind', "start:reload:$rg {q}",
        '--bind', "change:reload:$rg {q}",
        '--color', 'hl:-1:underline,hl+:-1:underline:reverse',
        '--prompt', 'rg> ',
        '--delimiter', ':',
        '--preview-window', 'up,60%,+{2}-7/7,<80(up)',
        '--bind', "enter:become:$opener",
        '--bind', "ctrl-o:execute:$opener"
    )
    if ($preview) { $fzfArgs += @('--preview', $preview) }
    & fzf @fzfArgs
}

# ============================================================
#  Tool integrations
# ============================================================
if (Test-DotCommand 'zoxide') {
    try { Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) }) }
    catch { Write-DotLog "zoxide: $_" }
} else { Write-DotLog 'zoxide not found: cd is Set-Location' }

if (Test-DotCommand 'oh-my-posh') {
    try {
        $ompConfig = Join-Path $env:DOTFILES 'ohmyposh/config.toml'
        oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
    } catch { Write-DotLog "oh-my-posh: $_" }
} else { Write-DotLog 'oh-my-posh not found: default prompt' }

# ============================================================
#  Machine-specific overrides (not tracked in git)
# ============================================================
$DotLocalProfile = Join-Path $PSScriptRoot 'profile.local.ps1'
if (Test-Path $DotLocalProfile) {
    try { . $DotLocalProfile } catch { Write-DotLog "profile.local.ps1: $_" }
}

$ErrorActionPreference = $DotPrevEAP
