<#
.SYNOPSIS
    Test install.ps1 in Windows Sandbox: a throwaway Windows that is wiped when you close it.

.DESCRIPTION
    Generates a Windows Sandbox configuration that maps this repo (read-only) into the
    sandbox, opens it, and copies the repo to the sandbox user's home so you can run
    .\install.ps1 there. Nothing on your real machine is changed. Close the Sandbox
    window to throw everything away.

    Needs Windows 10/11 Pro, Enterprise or Education with Windows Sandbox enabled.

.EXAMPLE
    .\sandbox\Start-WindowsSandbox.ps1
    .\sandbox\Start-WindowsSandbox.ps1 -MemoryMB 4096
#>
[CmdletBinding()]
param(
    [int]$MemoryMB = 8192,
    [string]$OutFile = (Join-Path ([IO.Path]::GetTempPath()) 'dotfiles-test.wsb'),
    [switch]$NoLaunch
)

$repo = Split-Path -Parent $PSScriptRoot
$sandboxRepo = 'C:\dotfiles-host'

function ConvertTo-XmlText { param([string]$Text) [Security.SecurityElement]::Escape($Text) }

$config = @"
<Configuration>
  <MemoryInMB>$MemoryMB</MemoryInMB>
  <Networking>Enable</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$(ConvertTo-XmlText $repo)</HostFolder>
      <SandboxFolder>$sandboxRepo</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File $sandboxRepo\sandbox\sandbox-start.ps1</Command>
  </LogonCommand>
</Configuration>
"@

Set-Content -Path $OutFile -Value $config -Encoding UTF8
Write-Host "Sandbox configuration: $OutFile"
if ($NoLaunch) { return }

$exe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
if (-not (Test-Path $exe)) {
    Write-Host ''
    Write-Host 'Windows Sandbox is not enabled. In an administrator PowerShell run:' -ForegroundColor Yellow
    Write-Host '  Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    Write-Host 'then restart Windows and run this script again.'
    Write-Host '(Windows Home does not include Windows Sandbox; see README "Testing in a sandbox".)'
    exit 1
}
Start-Process -FilePath $OutFile
Write-Host 'Windows Sandbox is starting. Close its window to delete everything inside it.'
