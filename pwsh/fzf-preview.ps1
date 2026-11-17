# fzf preview for Ctrl+T in PowerShell: directory tree or file contents.
param([string]$Path)

if (-not $Path) { return }
$Path = $Path.Trim('"', "'")

if (Test-Path -LiteralPath $Path -PathType Container) {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --color=always --group-directories-first -- $Path
    } else {
        Get-ChildItem -LiteralPath $Path | Select-Object -ExpandProperty Name
    }
} elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat --color=always --style=plain,numbers -- $Path
    } else {
        Get-Content -LiteralPath $Path -TotalCount 200
    }
}
