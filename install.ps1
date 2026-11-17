<#
.SYNOPSIS
    dotfiles installer for Windows. Safe to re-run.

.DESCRIPTION
    Installs tools with scoop, links configs into place and runs post-setup.
    Works in Windows PowerShell 5.1 (first run on a fresh machine) and PowerShell 7.

    Logs:  logs\install-<timestamp>.log         (everything)
           logs\install-errors-<timestamp>.log  (only when something failed)

.EXAMPLE
    .\install.ps1                 # everything
    .\install.ps1 -LinksOnly      # only (re)create config links
    .\install.ps1 -DryRun         # show what would happen, change nothing
#>
[CmdletBinding()]
param(
    [switch]$LinksOnly,
    [switch]$SkipPackages,
    [switch]$NoPost,
    [switch]$DryRun,

    # Target locations, overridable for tests
    [string]$ProfilePath,
    [string]$LocalAppDataPath = $env:LOCALAPPDATA,
    [string]$AppDataPath = $env:APPDATA,
    [string]$BackupRoot,
    [string]$LogDir
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not $ProfilePath) {
    $ProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
}
if (-not $BackupRoot) { $BackupRoot = Join-Path $HOME '.dotfiles-backup' }
if (-not $LogDir)     { $LogDir = Join-Path $Root 'logs' }
$BackupDir = Join-Path $BackupRoot $Timestamp
$LogFile   = Join-Path $LogDir "install-$Timestamp.log"
$ErrorLog  = Join-Path $LogDir "install-errors-$Timestamp.log"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$script:ErrorCount = 0

# ------------------------------------------------------------
#  Logging
# ------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogFile -Value ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message)
}

function Write-Err {
    param([string]$Message, [string]$Detail)
    $script:ErrorCount++
    Write-Host "ERROR $Message" -ForegroundColor Red
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] ERROR {1}' -f (Get-Date), $Message
    Add-Content -Path $LogFile  -Value $line
    Add-Content -Path $ErrorLog -Value $line
    if ($Detail) { Add-Content -Path $ErrorLog -Value ($Detail.TrimEnd() + [Environment]::NewLine) }
}

function Write-Section { param([string]$Title) Write-Log ''; Write-Log "==> $Title" }

# Run a native command; output goes to the log, failures to the error log
function Invoke-Native {
    param([string]$Description, [string]$Exe, [string[]]$Arguments)
    if ($DryRun) { Write-Log "[dry-run] ${Description}: $Exe $($Arguments -join ' ')"; return $true }
    Write-Log "  - $Description"
    try {
        $out = & $Exe @Arguments 2>&1 | Out-String
        $rc = $LASTEXITCODE
    } catch {
        Write-Err "$Description failed: $($_.Exception.Message)"
        return $false
    }
    if ($out) { Add-Content -Path $LogFile -Value $out.TrimEnd() }
    if ($rc -ne 0 -and $null -ne $rc) {
        Write-Err "$Description failed (exit $rc): $Exe $($Arguments -join ' ')" $out
        return $false
    }
    return $true
}

# Run a native command with a time limit (for steps that can hang on a stuck download)
function Invoke-NativeTimeout {
    param([string]$Description, [string]$Exe, [string[]]$Arguments, [int]$TimeoutSeconds)
    if ($DryRun) { Write-Log "[dry-run] ${Description}: $Exe $($Arguments -join ' ')"; return $true }
    Write-Log "  - $Description"
    $outFile = [IO.Path]::GetTempFileName(); $errFile = [IO.Path]::GetTempFileName()
    try {
        $quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
        $proc = Start-Process -FilePath $Exe -ArgumentList $quoted -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $proc.Kill()
            Write-Err "$Description timed out after $TimeoutSeconds s" ((Get-Content $outFile, $errFile -Raw) -join '')
            return $false
        }
        $out = ((Get-Content $outFile, $errFile -Raw) -join '')
        if ($out) { Add-Content -Path $LogFile -Value $out.TrimEnd() }
        if ($proc.ExitCode -ne 0) { Write-Err "$Description failed (exit $($proc.ExitCode))" $out; return $false }
        return $true
    } catch {
        Write-Err "$Description failed: $($_.Exception.Message)"
        return $false
    } finally { Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue }
}

function Test-Command { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ------------------------------------------------------------
#  Packages (scoop)
# ------------------------------------------------------------
function Test-Admin {
    if (-not $OnWindows) { return $false }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScoopRoot { if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' } }

function Install-Scoop {
    if (Test-Command 'scoop') { Write-Log '  ok scoop'; return $true }
    if ($DryRun) { Write-Log '[dry-run] install scoop'; return $true }
    Write-Log '  - installing scoop'
    try {
        $installer = Invoke-RestMethod -Uri 'https://get.scoop.sh' -ErrorAction Stop
        $scoopArgs = @()
        if (Test-Admin) {
            # Scoop refuses to install as admin unless asked; Windows Sandbox always runs as admin
            Write-Log '  running as administrator: installing scoop with -RunAsAdmin'
            $scoopArgs = @('-RunAsAdmin')
        }
        & ([scriptblock]::Create($installer)) @scoopArgs *>> $LogFile
        $env:PATH = (Join-Path (Get-ScoopRoot) 'shims') + ';' + $env:PATH
    } catch {
        Write-Err "scoop installation failed: $($_.Exception.Message)" $_.ScriptStackTrace
        return $false
    }
    if (-not (Test-Command 'scoop')) { Write-Err 'scoop is still not available after installation'; return $false }
    return $true
}

function Install-ScoopPackages {
    $scoopRoot = Get-ScoopRoot
    $listFile = Join-Path $Root 'packages\scoop.txt'
    foreach ($raw in Get-Content -Path $listFile) {
        $line = ($raw -replace '#.*$', '').Trim()
        if (-not $line) { continue }
        $parts = $line.Split('/')
        if ($parts.Count -ne 2) { Write-Err "packages\scoop.txt: expected bucket/app, got '$line'"; continue }
        $bucket = $parts[0]; $app = $parts[1]

        if (-not (Test-Path (Join-Path $scoopRoot "buckets\$bucket"))) {
            if (-not (Invoke-Native "add scoop bucket $bucket" 'scoop' @('bucket', 'add', $bucket))) { continue }
        }
        if (Test-Path (Join-Path $scoopRoot "apps\$app\current")) {
            Write-Log "  ok $app"
        } else {
            Invoke-Native "scoop install $line" 'scoop' @('install', $line) | Out-Null
        }
    }
}

function Install-PSFzf {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Write-Err 'PSFzf: pwsh (PowerShell 7) not found, cannot install the module'; return }
    $check = '$m = Get-Module -ListAvailable PSFzf; if ($m) { exit 0 } else { exit 1 }'
    & $pwsh.Source -NoProfile -Command $check 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Log '  ok PSFzf'; return }
    Invoke-Native 'install PSFzf module' $pwsh.Source @('-NoProfile', '-Command',
        'Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module PSFzf -Scope CurrentUser -Force -ErrorAction Stop') | Out-Null
}

function Install-Packages {
    Write-Section 'Packages'
    if (-not $OnWindows) { Write-Log '  not on Windows, skipping scoop'; return }
    if (-not (Install-Scoop)) { return }
    if ($DryRun) { Write-Log '[dry-run] scoop install packages from packages\scoop.txt'; return }
    Install-ScoopPackages
    Install-PSFzf
}

# ------------------------------------------------------------
#  Links
# ------------------------------------------------------------
function Get-NormalizedPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
}

function Get-LinkTarget {
    param($Item)
    $target = $Item.Target
    if ($target -is [array]) { $target = $target[0] }
    return [string]$target
}

function Remove-DirLink {
    param([string]$Path)
    if ($OnWindows) { cmd /c rmdir "$Path" 2>&1 | Out-Null }   # removes only the link
    else { Remove-Item -LiteralPath $Path -Force }
}

function Backup-Item {
    param([string]$Path)
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $dest = Join-Path $BackupDir (Split-Path -Leaf $Path)
    if (Test-Path -LiteralPath $dest) { $dest = "$dest-$([guid]::NewGuid().ToString('N').Substring(0, 6))" }
    Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
    Write-Log "  backed up $Path -> $dest"
}

# Make $Destination a directory link (junction on Windows) pointing at $Source
function New-DirLink {
    param([string]$Source, [string]$Destination)
    try {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            Write-Err "link: source missing: $Source"; return
        }
        $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.LinkType) {
            if ((Get-NormalizedPath (Get-LinkTarget $existing)) -eq (Get-NormalizedPath $Source)) {
                Write-Log "  ok $Destination"; return
            }
        }
        if ($DryRun) { Write-Log "[dry-run] link $Destination -> $Source"; return }

        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }

        if ($existing) {
            if ($existing.LinkType) {
                Write-Log "  replacing link $Destination (was -> $(Get-LinkTarget $existing))"
                Remove-DirLink $Destination
            } else {
                Backup-Item $Destination
            }
        }

        $type = 'SymbolicLink'; if ($OnWindows) { $type = 'Junction' }
        New-Item -ItemType $type -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        Write-Log "  linked $Destination -> $Source"
    } catch {
        Write-Err "link $Destination failed: $($_.Exception.Message)" $_.ScriptStackTrace
    }
}

function Get-ProfileStub {
    $rootLiteral = $Root -replace "'", "''"
    return @(
        '# Managed by dotfiles install.ps1 - edit pwsh\profile.ps1 in the repo instead.'
        "`$env:DOTFILES = '$rootLiteral'"
        ". (Join-Path (Join-Path `$env:DOTFILES 'pwsh') 'profile.ps1')"
    ) -join [Environment]::NewLine
}

function Set-ProfileStub {
    try {
        $stub = Get-ProfileStub
        $existing = $null
        if (Test-Path -LiteralPath $ProfilePath) { $existing = (Get-Content -LiteralPath $ProfilePath -Raw) }
        if ($existing -and $existing.Trim() -eq $stub.Trim()) { Write-Log "  ok $ProfilePath"; return }
        if ($DryRun) { Write-Log "[dry-run] write profile stub $ProfilePath"; return }

        $parent = Split-Path -Parent $ProfilePath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
        if ($existing -and $existing -notmatch 'Managed by dotfiles') { Backup-Item $ProfilePath }

        Set-Content -LiteralPath $ProfilePath -Value $stub -Encoding UTF8 -ErrorAction Stop
        Write-Log "  wrote profile stub $ProfilePath"
    } catch {
        Write-Err "profile stub failed: $($_.Exception.Message)" $_.ScriptStackTrace
    }
}

function New-LocalProfileTemplate {
    $file = Join-Path (Join-Path $Root 'pwsh') 'profile.local.ps1'
    if ((Test-Path -LiteralPath $file) -or $DryRun) { return }
    try {
        Set-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop -Value @(
            '# Machine-specific PowerShell settings (not tracked in git).'
            '# Example: conda'
            '# (& "$HOME\miniconda3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | Invoke-Expression'
        )
        Write-Log "  created $file (machine-specific settings)"
    } catch { Write-Err "cannot create ${file}: $($_.Exception.Message)" }
}

function Set-ConfigLinks {
    Write-Section 'Config links'
    if (-not $LocalAppDataPath -or -not $AppDataPath) {
        Write-Err 'LOCALAPPDATA/APPDATA are not set; pass -LocalAppDataPath and -AppDataPath'
        return
    }
    New-DirLink (Join-Path $Root 'nvim') (Join-Path $LocalAppDataPath 'nvim')
    New-DirLink (Join-Path $Root 'yazi') (Join-Path (Join-Path $AppDataPath 'yazi') 'config')
    Set-ProfileStub
    New-LocalProfileTemplate
}

# ------------------------------------------------------------
#  Post-setup
# ------------------------------------------------------------
function Invoke-PostSetup {
    Write-Section 'Post-setup'
    # Windows PowerShell 5.1 is left alone: no profile, no execution policy change.
    # PowerShell 7 runs profile scripts by default (its default policy is RemoteSigned).
    $nvimInit = Join-Path (Join-Path $Root 'nvim') 'init.lua'
    if ((Test-Command 'nvim') -and (Test-Path $nvimInit)) {
        # Order matters: Mason installs the tree-sitter CLI that compiles the parsers
        $nvimExe = (Get-Command nvim).Source
        Invoke-NativeTimeout 'install nvim plugins (lazy.nvim)' $nvimExe @('--headless', '+Lazy! restore', '+qa') 900 | Out-Null
        Invoke-NativeTimeout 'install LSPs, formatters and debuggers (Mason)' $nvimExe @('--headless', '+MasonToolsInstallSync', '+qa') 1800 | Out-Null
        Invoke-NativeTimeout 'compile treesitter parsers' $nvimExe @('--headless', '+TSInstallSync', '+qa') 900 | Out-Null
    }

    Write-Log ''
    Write-Log '  Manual steps (once):'
    Write-Log '  - Install a Nerd Font and select it in Windows Terminal (README, Step 9)'
    Write-Log '  - Optional: Windows Terminal > Settings > Startup > Default profile: PowerShell (the 7.x one)'
    Write-Log '  Windows PowerShell 5.1 is unchanged; your setup loads only in PowerShell 7 (pwsh).'
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
Write-Log "dotfiles: $Root"
Write-Log "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
if ($DryRun) { Write-Log 'DRY RUN: nothing will be changed' }

if (-not $LinksOnly -and -not $SkipPackages) { Install-Packages }
Set-ConfigLinks
if (-not $LinksOnly -and -not $NoPost) { Invoke-PostSetup }

Write-Log ''
if ($script:ErrorCount -gt 0) {
    Write-Log "Finished with $($script:ErrorCount) error(s). Details: $ErrorLog"
    exit 1
}
Write-Log "Done. Full log: $LogFile"
if (Test-Path $BackupDir) { Write-Log "Previous configs were backed up to $BackupDir" }
if (-not $DryRun) { Write-Log 'Open a new PowerShell 7 window to load the profile.' }
exit 0
