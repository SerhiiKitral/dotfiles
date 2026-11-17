# Tests for install.ps1, pwsh/profile.ps1 and the path-segment helpers.
# Runs in temporary sandboxes; never touches your real profile or AppData.
# Usage:  pwsh -NoProfile -File tests/test_pwsh.ps1

. (Join-Path $PSScriptRoot 'TestLib.ps1')
$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------
Test-Case 'syntax: all PowerShell files parse'
Get-ChildItem -Path $RepoRoot -Recurse -Filter *.ps1 -File |
    Where-Object { $_.FullName -notmatch '[\\/](logs|\.git)[\\/]' } |
    ForEach-Object {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
        $rel = $_.FullName.Substring($RepoRoot.Length + 1)
        Assert-True ($errors.Count -eq 0) "$rel parses" (($errors | ForEach-Object { "$($_.Message) (line $($_.Extent.StartLineNumber))" }) -join "`n")
    }

Test-Case 'scripts for Windows PowerShell 5.1 are plain ASCII (it reads BOM-less files as ANSI)'
foreach ($rel in 'install.ps1', 'sandbox/Start-WindowsSandbox.ps1', 'sandbox/sandbox-start.ps1') {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $RepoRoot $rel))
    Assert-True (-not ($bytes | Where-Object { $_ -gt 127 })) "no non-ASCII bytes in $rel"
}

Test-Case 'fonts are installed by hand, not by the installer'
Assert-True (-not (Select-String -Path (Join-Path $RepoRoot 'packages/scoop.txt') -Pattern '^\s*nerd-fonts/' -Quiet)) 'scoop.txt has no font packages'
Assert-True (-not (Select-String -Path (Join-Path $RepoRoot 'install.ps1') -Pattern 'SkipFonts' -Quiet)) 'install.ps1 has no font option'

Test-Case 'Windows Sandbox configuration'
$wsb = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-test-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.wsb')
& (Join-Path $RepoRoot 'sandbox/Start-WindowsSandbox.ps1') -OutFile $wsb -NoLaunch -MemoryMB 4096 6>$null
try {
    [xml]$cfg = Get-Content $wsb -Raw
    Assert-Equal $RepoRoot $cfg.Configuration.MappedFolders.MappedFolder.HostFolder 'maps this repo into the sandbox'
    Assert-Equal 'true' $cfg.Configuration.MappedFolders.MappedFolder.ReadOnly 'the repo is mapped read-only'
    Assert-Equal '4096' $cfg.Configuration.MemoryInMB 'memory setting is applied'
    Assert-True ($cfg.Configuration.LogonCommand.Command -match 'sandbox-start\.ps1') 'runs sandbox-start.ps1 at logon'
} catch { Fail 'configuration is valid XML' $_.Exception.Message }
finally { Remove-Item $wsb -ErrorAction SilentlyContinue }

# ------------------------------------------------------------
Test-Case 'path segments: Ctrl+Backspace / Ctrl+Delete logic'
. (Join-Path $RepoRoot 'pwsh/lib/PathSegments.ps1')

function Invoke-BackwardKill([string]$line) {
    $start = Get-DotSegmentStart $line $line.Length
    return $line.Substring(0, $start)
}
$line = 'cd C:\Users\User1\file.txt'
$line = Invoke-BackwardKill $line; Assert-Equal 'cd C:\Users\User1\' $line 'removes file.txt first'
$line = Invoke-BackwardKill $line; Assert-Equal 'cd C:\Users\' $line 'then User1\'
$line = Invoke-BackwardKill $line; Assert-Equal 'cd C:\' $line 'then Users\'
Assert-Equal '/mnt/c/Users/' (Invoke-BackwardKill '/mnt/c/Users/User1/') 'forward slashes work too'
Assert-Equal 'nvim ' (Invoke-BackwardKill 'nvim my-file.txt') 'dashes and dots stay inside a segment'
Assert-Equal 0 (Get-DotSegmentStart '' 0) 'empty line is safe'
Assert-Equal 0 (Get-DotSegmentStart 'abc' 99) 'cursor past the end is clamped'

$text = 'C:\Users\User1\file.txt'
Assert-Equal 8 (Get-DotSegmentEnd $text 2) 'Ctrl+Delete from after C:\ stops after Users'
Assert-Equal $text.Length (Get-DotSegmentEnd $text 15) 'Ctrl+Delete at the last segment goes to the end'

# ------------------------------------------------------------
Test-Case 'install.ps1: fresh run (-LinksOnly)'
$sb = New-Sandbox
try {
    $r = Invoke-SandboxInstall $sb @('-LinksOnly')
    Assert-Equal 0 $r.Code 'exits 0'
    Assert-Link (Join-Path $sb.LocalAppData 'nvim') (Join-Path $sb.Repo 'nvim') 'nvim config linked'
    Assert-Link (Join-Path (Join-Path $sb.AppData 'yazi') 'config') (Join-Path $sb.Repo 'yazi') 'yazi config linked'
    Assert-True (Test-Path $sb.Profile) 'profile stub written'
    $stub = Get-Content $sb.Profile -Raw
    Assert-True ($stub -match [regex]::Escape($sb.Repo)) 'stub points at the repo'
    Assert-True ($stub -match 'Managed by dotfiles') 'stub is marked as managed'
    Assert-True (Test-Path (Join-Path $sb.Repo 'pwsh/profile.local.ps1')) 'profile.local.ps1 template created'
    Assert-True (-not (Get-ChildItem $sb.Logs -Filter 'install-errors-*' -ErrorAction SilentlyContinue)) 'no error log written'

    Test-Case 'install.ps1: re-run is idempotent'
    Start-Sleep -Seconds 1
    $r = Invoke-SandboxInstall $sb @('-LinksOnly')
    Assert-Equal 0 $r.Code 'exits 0'
    Assert-True ($r.Output -match 'ok .*nvim') 'reports existing links as ok'
    Assert-True (-not (Test-Path $sb.Backup)) 'nothing backed up'
} finally { Remove-Sandbox $sb }

# ------------------------------------------------------------
Test-Case 'install.ps1: existing configs are backed up'
$sb = New-Sandbox
try {
    New-Item -ItemType Directory -Path (Join-Path $sb.LocalAppData 'nvim') -Force | Out-Null
    Set-Content -Path (Join-Path $sb.LocalAppData 'nvim/init.lua') -Value 'old init'
    New-Item -ItemType Directory -Path (Split-Path $sb.Profile) -Force | Out-Null
    Set-Content -Path $sb.Profile -Value '# my old profile'
    $r = Invoke-SandboxInstall $sb @('-LinksOnly')
    Assert-Equal 0 $r.Code 'exits 0'
    $backup = Get-ChildItem $sb.Backup -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    Assert-True ($null -ne $backup) 'backup directory created'
    if ($backup) {
        Assert-Equal 'old init' ((Get-Content (Join-Path $backup.FullName 'nvim/init.lua') -Raw).Trim()) 'old nvim config preserved'
        Assert-Equal '# my old profile' ((Get-Content (Join-Path $backup.FullName 'Microsoft.PowerShell_profile.ps1') -Raw).Trim()) 'old profile preserved'
    }
    Assert-Link (Join-Path $sb.LocalAppData 'nvim') (Join-Path $sb.Repo 'nvim') 'nvim now linked'
} finally { Remove-Sandbox $sb }

# ------------------------------------------------------------
Test-Case 'install.ps1: -DryRun changes nothing'
$sb = New-Sandbox
try {
    $r = Invoke-SandboxInstall $sb @('-LinksOnly', '-DryRun')
    Assert-Equal 0 $r.Code 'exits 0'
    Assert-True (-not (Test-Path (Join-Path $sb.LocalAppData 'nvim'))) 'no nvim link'
    Assert-True (-not (Test-Path $sb.Profile)) 'no profile written'
} finally { Remove-Sandbox $sb }

# ------------------------------------------------------------
Test-Case 'install.ps1: errors are logged and the run continues'
$sb = New-Sandbox
try {
    Remove-Item $sb.AppData -Recurse -Force
    Set-Content -Path $sb.AppData -Value 'not a directory'      # yazi link cannot be created
    $r = Invoke-SandboxInstall $sb @('-LinksOnly')
    Assert-Equal 1 $r.Code 'exits 1'
    $errLog = Get-ChildItem $sb.Logs -Filter 'install-errors-*' -ErrorAction SilentlyContinue | Select-Object -First 1
    Assert-True ($null -ne $errLog) 'error log written'
    if ($errLog) { Assert-True ((Get-Content $errLog.FullName -Raw) -match 'yazi') 'error log names the failed link' }
    Assert-Link (Join-Path $sb.LocalAppData 'nvim') (Join-Path $sb.Repo 'nvim') 'other links still created'
    Assert-True ($r.Output -match 'Details:') 'summary points to the error log'
} finally { Remove-Sandbox $sb }

# ------------------------------------------------------------
Test-Case 'install.ps1: long-running steps time out and are logged'
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'install.ps1'), [ref]$null, [ref]$null)
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
               $args[0].Name -in 'Invoke-NativeTimeout', 'Write-Log', 'Write-Err' }, $true) |
    ForEach-Object { Invoke-Expression $_.Extent.Text }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-timeout-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $tmp | Out-Null
$LogFile = Join-Path $tmp 'install.log'; $ErrorLog = Join-Path $tmp 'errors.log'; $DryRun = $false; $script:ErrorCount = 0
$pwshExe = (Get-Process -Id $PID).Path
$ok = Invoke-NativeTimeout 'quick step' $pwshExe @('-NoProfile', '-Command', 'Write-Output dotfiles-hello') 60 6>$null
Assert-True $ok 'a quick command succeeds'
Assert-True ((Get-Content $LogFile -Raw) -match 'dotfiles-hello') 'its output goes to the log'
$ok = Invoke-NativeTimeout 'stuck step' $pwshExe @('-NoProfile', '-Command', 'Start-Sleep 30') 2 6>$null
Assert-True (-not $ok) 'a stuck command is stopped'
Assert-True ((Test-Path $ErrorLog) -and ((Get-Content $ErrorLog -Raw) -match 'stuck step timed out')) 'the timeout is in the error log'
$ok = Invoke-NativeTimeout 'failing step' $pwshExe @('-NoProfile', '-Command', 'exit 3') 60 6>$null
Assert-True (-not $ok) 'a failing command is reported'
Assert-True ((Get-Content $ErrorLog -Raw) -match 'failing step failed \(exit 3\)') 'the exit code is in the error log'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
Test-Case 'profile.ps1: loads without tools and logs what is missing'
$sb = New-Sandbox
try {
    $logDir = Join-Path $sb.Root 'pwshlog'
    $script = @"
`$env:PATH = ''
`$env:DOTFILES_LOG_DIR = '$logDir'
. '$(Join-Path $sb.Repo 'pwsh/profile.ps1')'
foreach (`$f in 'desk','y','rfgrep','dotlog','dots','winopen','la') {
    if (Get-Command `$f -CommandType Function -ErrorAction SilentlyContinue) { "FN:`$f" }
}
"DOTFILES:`$env:DOTFILES"
"@
    $pwshExe = (Get-Process -Id $PID).Path
    $out = & $pwshExe -NoProfile -NonInteractive -Command $script 2>&1 | Out-String
    Assert-Equal 0 $LASTEXITCODE 'loads without a terminating error'
    $unexpected = ($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^(FN|DOTFILES):' }
    Assert-True (-not $unexpected) 'nothing else printed (errors go to the log)' ($unexpected -join "`n")
    foreach ($f in 'desk', 'y', 'rfgrep', 'dotlog', 'dots', 'winopen', 'la') {
        Assert-True ($out -match "FN:$f") "$f is defined"
    }
    Assert-True ($out -match [regex]::Escape("DOTFILES:$($sb.Repo)")) 'DOTFILES points at the repo'
    $logFile = Join-Path $logDir 'pwsh-errors.log'
    Assert-True (Test-Path $logFile) 'error log created'
    if (Test-Path $logFile) {
        $log = Get-Content $logFile -Raw
        Assert-True ($log -match 'zoxide not found') 'zoxide logged'
        Assert-True ($log -match 'oh-my-posh not found') 'oh-my-posh logged'
        Assert-True ($log -match 'eza not found') 'eza logged'
    }
} finally { Remove-Sandbox $sb }

exit (Show-Summary)
