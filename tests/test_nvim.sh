#!/usr/bin/env bash
# Tests for the nvim config: every Lua file compiles, the platform helper
# gives the right paths on each OS, no Linux-only paths sneak back in, and
# the installers provide everything the config depends on.
# Plugins are not downloaded, so this runs offline in a few seconds.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NVIM_DIR="$REPO_ROOT/nvim"

# ------------------------------------------------------------
test_case "installers provide what the nvim config needs"
for pkg in build-essential python3-venv python3-pip xz-utils wget libicu-dev; do
  assert_true "apt.txt has $pkg" grep -qx "$pkg" "$REPO_ROOT/packages/apt.txt"
done
for fn in install_nvim install_node install_dotnet install_win32yank install_wslu; do
  assert_true "install.sh defines $fn" grep -q "^$fn()" "$REPO_ROOT/install.sh"
done
assert_true "install.sh requires nvim 0.12+" grep -q 'version_ge "$v" "0.12"' "$REPO_ROOT/install.sh"
for app in main/neovim main/mingw main/nodejs-lts main/python main/dotnet-sdk main/ripgrep main/fd; do
  assert_true "scoop.txt has $app" grep -q "^$app\\b" "$REPO_ROOT/packages/scoop.txt"
done
assert_true "install.sh installs Mason tools" grep -q "MasonToolsInstallSync" "$REPO_ROOT/install.sh"
assert_true "install.ps1 installs Mason tools" grep -q "MasonToolsInstallSync" "$REPO_ROOT/install.ps1"
assert_true "install.sh compiles parsers after Mason" bash -c "grep -n 'MasonToolsInstallSync\|TSInstallSync' '$REPO_ROOT/install.sh' | tail -n1 | grep -q TSInstallSync"
assert_true "install.ps1 compiles parsers after Mason" bash -c "grep -n 'MasonToolsInstallSync\|TSInstallSync' '$REPO_ROOT/install.ps1' | tail -n1 | grep -q TSInstallSync"
assert_true "treesitter waits for Mason's tree-sitter CLI on a fresh machine" grep -q "MasonToolsUpdateCompleted" "$NVIM_DIR/lua/plugins/treesitter.lua"

# ------------------------------------------------------------
test_case "no Linux-only paths in the config"
# Mason paths must go through utils.platform so they also work on Windows
bad="$(grep -rnE 'mason/(bin|packages)/|venv/bin/' "$NVIM_DIR/lua" --include='*.lua' \
  | grep -v 'lua/utils/platform.lua' | grep -v 'platform\.' || true)"
assert_eq "" "$bad" "Mason paths use utils.platform"
assert_true "init.lua loads utils.platform first" bash -c "head -n1 '$NVIM_DIR/init.lua' | grep -q 'utils.platform'"

if ! command -v nvim >/dev/null; then
  test_case "nvim"
  skip "nvim not installed: Lua checks skipped"
  summary; exit $?
fi

# Run a Lua snippet in a clean nvim with the config's lua/ on the path; prints its output
nvim_lua() {
  nvim --clean --headless --cmd "set rtp^=$NVIM_DIR" -c "lua $1" -c 'qa!' 2>&1
}

# ------------------------------------------------------------
test_case "every Lua file compiles"
while IFS= read -r file; do
  rel="${file#"$NVIM_DIR"/}"
  out="$(nvim --clean --headless -c "lua local f, e = loadfile([[$file]]); if not f then io.stdout:write(e) end" -c 'qa!' 2>&1)"
  if [[ -z $out ]]; then pass "$rel"; else fail "$rel" "$out"; fi
done < <(find "$NVIM_DIR" -name '*.lua' -type f | sort)

# ------------------------------------------------------------
test_case "utils.platform"
out="$(nvim_lua 'local p = require("utils.platform"); io.stdout:write(tostring(p.is_win), " ", tostring(p.is_linux))')"
assert_eq "false true" "$out" "detects Linux"
out="$(nvim_lua 'local p = require("utils.platform"); io.stdout:write(p.mason_exe("debugpy", "venv/bin/python", "venv/Scripts/python.exe"))')"
assert_true "Linux debugpy path" grep -q '/mason/packages/debugpy/venv/bin/python$' <<<"$out"
out="$(nvim_lua 'local p = require("utils.platform"); p.is_win = true; io.stdout:write(p.mason_exe("netcoredbg", "", "netcoredbg/netcoredbg.exe"))')"
assert_true "Windows netcoredbg path" grep -q '/mason/packages/netcoredbg/netcoredbg/netcoredbg.exe$' <<<"$out"
out="$(nvim_lua 'local p = require("utils.platform"); p.is_win = true; io.stdout:write(p.mason_exe("debugpy", "venv/bin/python", "venv/Scripts/python.exe"))')"
assert_true "Windows debugpy path" grep -q '/mason/packages/debugpy/venv/Scripts/python.exe$' <<<"$out"

# ------------------------------------------------------------
test_case "Windows shell settings (simulated Windows)"
# Pretend to be Windows, then load utils.platform and read the shell options it set
win_lua='local real = vim.fn.has; vim.fn.has = function(f) if f == "win32" then return 1 end if f == "wsl" then return 0 end return real(f) end; require("utils.platform")'
out="$(nvim_lua "$win_lua; io.stdout:write(vim.o.shell)")"
assert_eq "powershell" "$out" "uses Windows PowerShell (5.1), not pwsh"
out="$(nvim_lua "$win_lua; io.stdout:write(vim.o.shellcmdflag)")"
assert_true "starts it without a profile" grep -q -- "-NoProfile" <<<"$out"
assert_false "no PowerShell-7-only commands (Remove-Alias, \$PSStyle)" grep -qE 'Remove-Alias|PSStyle' <<<"$out"
out="$(nvim_lua "$win_lua; io.stdout:write(vim.o.shellpipe)")"
assert_false "shellpipe avoids tee (UTF-16 in 5.1)" grep -qi 'tee' <<<"$out"

# ------------------------------------------------------------
test_case "C# dll finder works with Windows-style paths"
# Same matching logic as lua/plugins/dap.lua (win = true simulates Windows normalization)
out="$(nvim_lua '
  local match = function(path) return vim.fs.normalize(path, { win = path:find("\\") ~= nil }):match("/bin/Debug/") ~= nil end
  io.stdout:write(tostring(match([[C:\Users\me\proj\bin\Debug\net8.0]])), " ",
                  tostring(match("/home/me/proj/bin/Debug/net8.0")), " ",
                  tostring(match("/home/me/proj/obj/Debug/net8.0")))')"
assert_eq "true true false" "$out" "matches bin/Debug on both systems, not obj/"

summary
