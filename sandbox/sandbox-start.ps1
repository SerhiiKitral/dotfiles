# Runs inside Windows Sandbox at logon (see Start-WindowsSandbox.ps1).
# Copies the read-only mapped repo to a writable folder and opens PowerShell there.
$source = 'C:\dotfiles-host'
$target = Join-Path $HOME 'dotfiles'

if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force |
        Where-Object { $_.Name -notin @('logs', '.git') } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force }
}

$welcome = @"
Write-Host 'dotfiles test sandbox' -ForegroundColor Cyan
Write-Host 'Everything here is deleted when you close the Sandbox window.'
Write-Host ''
Write-Host 'Run the installer:   .\install.ps1'
Write-Host 'Dry run first:       .\install.ps1 -DryRun'
Write-Host 'Afterwards open:     pwsh   (your new profile loads)'
Write-Host ''
"@
# -EncodedCommand avoids quoting problems with Start-Process in Windows PowerShell 5.1
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($welcome))
Start-Process -FilePath 'powershell.exe' -WorkingDirectory $target -ArgumentList @(
    '-NoExit', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
)
