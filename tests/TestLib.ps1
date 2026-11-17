# Minimal test helpers for PowerShell (no Pester needed).
# Failures are printed and appended to $env:TEST_ERROR_LOG.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:TEST_ERROR_LOG) {
    $env:TEST_ERROR_LOG = Join-Path (Join-Path $script:RepoRoot 'logs') ("test-errors-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
}
New-Item -ItemType Directory -Path (Split-Path -Parent $env:TEST_ERROR_LOG) -Force | Out-Null

$script:Pass = 0; $script:Fail = 0; $script:Skip = 0; $script:CurrentTest = ''

function Test-Case { param([string]$Name) $script:CurrentTest = $Name; Write-Host ''; Write-Host $Name -ForegroundColor White }

function Pass { param([string]$Message) $script:Pass++; Write-Host "  ok   $Message" -ForegroundColor Green }

function Fail {
    param([string]$Message, [string]$Detail)
    $script:Fail++
    Write-Host "  FAIL $Message" -ForegroundColor Red
    $entry = "[{0:yyyy-MM-dd HH:mm:ss}] {1} :: {2}" -f (Get-Date), $script:CurrentTest, $Message
    if ($Detail) { $entry += [Environment]::NewLine + (($Detail -split "`n") | ForEach-Object { "    $_" }) -join [Environment]::NewLine }
    Add-Content -Path $env:TEST_ERROR_LOG -Value $entry
}

function Skip { param([string]$Message) $script:Skip++; Write-Host "  skip $Message" -ForegroundColor Yellow }

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -eq $Actual) { Pass $Message } else { Fail $Message "expected: $Expected`nactual:   $Actual" }
}

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail)
    if ($Condition) { Pass $Message } else { Fail $Message $Detail }
}

function Get-LinkTargetPath {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) { return $null }
    $t = $item.Target; if ($t -is [array]) { $t = $t[0] }
    return ([IO.Path]::GetFullPath([string]$t)).TrimEnd('\', '/')
}

function Assert-Link {
    param([string]$Path, [string]$Target, [string]$Message)
    $actual = Get-LinkTargetPath $Path
    $expected = ([IO.Path]::GetFullPath($Target)).TrimEnd('\', '/')
    if ($actual -and $actual -eq $expected) { Pass $Message }
    else { Fail $Message "$Path -> $actual, expected -> $expected" }
}

# Fresh sandbox: copy of the repo + empty target folders
function New-Sandbox {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Get-ChildItem -LiteralPath $script:RepoRoot -Force |
        Where-Object { $_.Name -notin @('.git', 'logs') } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $repo -Recurse -Force }
    $sb = [pscustomobject]@{
        Root         = $root
        Repo         = $repo
        LocalAppData = Join-Path $root 'LocalAppData'
        AppData      = Join-Path $root 'AppData'
        Profile      = Join-Path (Join-Path $root 'Documents') 'PowerShell/Microsoft.PowerShell_profile.ps1'
        Backup       = Join-Path $root 'backup'
        Logs         = Join-Path $root 'logs'
    }
    foreach ($d in @($sb.LocalAppData, $sb.AppData)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $sb
}

function Remove-Sandbox {
    param($Sandbox)
    if (-not $Sandbox) { return }
    # Remove links first so we never recurse into the repo through them
    Get-ChildItem -LiteralPath $Sandbox.Root -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType } | Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { if ($IsWindows) { cmd /c rmdir "$($_.FullName)" 2>&1 | Out-Null } else { $_.Delete() } }
    Remove-Item -LiteralPath $Sandbox.Root -Recurse -Force -ErrorAction SilentlyContinue
}

# Run install.ps1 inside the sandbox in a child pwsh; returns @{ Code; Output }
function Invoke-SandboxInstall {
    param($Sandbox, [string[]]$ExtraArgs = @())
    $installArgs = @(
        '-NoProfile', '-File', (Join-Path $Sandbox.Repo 'install.ps1'),
        '-LocalAppDataPath', $Sandbox.LocalAppData,
        '-AppDataPath', $Sandbox.AppData,
        '-ProfilePath', $Sandbox.Profile,
        '-BackupRoot', $Sandbox.Backup,
        '-LogDir', $Sandbox.Logs
    ) + $ExtraArgs
    $pwshExe = (Get-Process -Id $PID).Path
    $output = & $pwshExe @installArgs 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $output }
}

function Show-Summary {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed, {2} skipped" -f $script:Pass, $script:Fail, $script:Skip)
    if ($script:Fail -gt 0) { Write-Host "Failure details: $env:TEST_ERROR_LOG"; return 1 }
    return 0
}
