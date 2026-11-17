# shellcheck shell=bash disable=SC2034
# Minimal test helpers (no external dependencies).
# Failures are printed and appended to $TEST_ERROR_LOG.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
: "${TEST_ERROR_LOG:=$REPO_ROOT/logs/test-errors-$(date +%Y%m%d-%H%M%S).log}"
export TEST_ERROR_LOG
mkdir -p "$(dirname "$TEST_ERROR_LOG")"

PASS=0
FAIL=0
SKIP=0
CURRENT_TEST=""

test_case() { CURRENT_TEST="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }

pass() { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }

fail() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  {
    printf '[%s] %s :: %s\n' "$(date '+%F %T')" "$CURRENT_TEST" "$1"
    [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/    /'
  } >> "$TEST_ERROR_LOG"
}

skip() { SKIP=$((SKIP + 1)); printf '  \033[33mskip\033[0m %s\n' "$1"; }

assert_eq() {      # expected actual message
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "expected: $1"$'\n'"actual:   $2"; fi
}
assert_true() {    # message command...
  local msg=$1; shift
  if "$@"; then pass "$msg"; else fail "$msg" "command failed: $*"; fi
}
assert_false() {
  local msg=$1; shift
  if "$@"; then fail "$msg" "command unexpectedly succeeded: $*"; else pass "$msg"; fi
}
assert_link() {    # link target message
  if [[ -L $1 && "$(readlink "$1")" == "$2" ]]; then pass "$3"
  else fail "$3" "$1 -> $(readlink "$1" 2>/dev/null || echo '<not a link>'), expected -> $2"; fi
}
assert_contains() { # file pattern message
  if grep -q -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3" "'$2' not found in $1"; fi
}

# Fresh sandbox: copy of the repo + empty home, removed on exit
make_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
  mkdir -p "$SANDBOX/home" "$SANDBOX/logs"
  mkdir -p "$SANDBOX/repo"
  (cd "$REPO_ROOT" && tar --exclude=./logs --exclude=./.git -cf - .) | (cd "$SANDBOX/repo" && tar -xf -)
  SB_REPO="$SANDBOX/repo"
  SB_HOME="$SANDBOX/home"
  SB_LOGS="$SANDBOX/logs"
}
cleanup_sandbox() { [[ -n ${SANDBOX:-} && -d $SANDBOX ]] && rm -rf "$SANDBOX"; SANDBOX=""; }

summary() {
  printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
  if (( FAIL > 0 )); then
    printf 'Failure details: %s\n' "$TEST_ERROR_LOG"
    return 1
  fi
  return 0
}
