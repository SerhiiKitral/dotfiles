# Run the PowerShell test suite on Windows.
# (The bash suites run in WSL: ./tests/run-tests.sh)
# Failures go to logs\test-errors-<timestamp>.log
$repo = Split-Path -Parent $PSScriptRoot
$env:TEST_ERROR_LOG = Join-Path (Join-Path $repo 'logs') ("test-errors-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$pwshExe = (Get-Process -Id $PID).Path

& $pwshExe -NoProfile -File (Join-Path $PSScriptRoot 'test_pwsh.ps1')
$code = $LASTEXITCODE

if ($code -ne 0) { Write-Host "`nSome tests failed. Details: $env:TEST_ERROR_LOG" -ForegroundColor Red }
else { Write-Host "`nAll tests passed." -ForegroundColor Green }
exit $code
