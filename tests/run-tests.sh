#!/usr/bin/env bash
# Run every test suite available on this machine (WSL/Linux).
# Failures from all suites go to one file: logs/test-errors-<timestamp>.log
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

TEST_ERROR_LOG="$PWD/logs/test-errors-$(date +%Y%m%d-%H%M%S).log"
export TEST_ERROR_LOG
mkdir -p logs
failed=()

run_suite() {
  local name=$1; shift
  printf '\n\033[1;36m### %s\033[0m\n' "$name"
  "$@" || failed+=("$name")
}

run_suite "install.sh" bash tests/test_install_sh.sh
run_suite "zshrc"      bash tests/test_zshrc.sh
run_suite "nvim"       bash tests/test_nvim.sh
if command -v pwsh >/dev/null; then
  run_suite "PowerShell" pwsh -NoProfile -File tests/test_pwsh.ps1
else
  printf '\n(pwsh not installed: PowerShell suite skipped)\n'
fi

printf '\n'
if (( ${#failed[@]} )); then
  printf '\033[31mFailed suites: %s\033[0m\nDetails: %s\n' "${failed[*]}" "$TEST_ERROR_LOG"
  exit 1
fi
printf '\033[32mAll suites passed.\033[0m\n'
