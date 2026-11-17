-- Cross-platform helpers so the same config runs on WSL/Linux and Windows.
-- Loaded first in init.lua. Use elsewhere with:
--   local platform = require("utils.platform")

local M = {}

M.is_win = vim.fn.has("win32") == 1
M.is_wsl = vim.fn.has("wsl") == 1
M.is_linux = not M.is_win and vim.fn.has("unix") == 1

-- Where Mason installs packages
M.mason = vim.fn.stdpath("data") .. "/mason"

-- Mason adds its bin/ to PATH only once it is set up; do it now so other
-- plugins (e.g. nvim-treesitter looking for the tree-sitter CLI) find its tools
vim.env.PATH = M.mason .. "/bin" .. (M.is_win and ";" or ":") .. vim.env.PATH

-- Path to an executable inside a Mason package, e.g.
--   M.mason_exe("debugpy", "venv/bin/python", "venv/Scripts/python.exe")
function M.mason_exe(package, unix_path, windows_path)
	return M.mason .. "/packages/" .. package .. "/" .. (M.is_win and windows_path or unix_path)
end

if M.is_win then
	-- Windows PowerShell (the built-in powershell.exe, 5.1) for :!, :terminal
	-- and plugins that shell out. -NoProfile keeps :! commands fast and plain.
	-- Based on :help shell-powershell, adjusted for 5.1: no Remove-Alias or
	-- $PSStyle (PowerShell 7 only), and no tee (5.1's Tee-Object writes UTF-16,
	-- which nvim can't read as an error file), so :make output goes to the file only.
	vim.o.shell = "powershell"
	vim.o.shellcmdflag = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -Command "
		.. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();"
		.. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';"
	vim.o.shellredir = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'
	vim.o.shellpipe = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'
	vim.o.shellquote = ""
	vim.o.shellxquote = ""

	-- nvim-treesitter (main branch) compiles parsers with `tree-sitter build`,
	-- which looks for MSVC by default; point it at MinGW's gcc instead
	if not vim.env.CC and vim.fn.executable("gcc") == 1 then
		vim.env.CC = "gcc"
	end
elseif M.is_wsl then
	-- Share the clipboard with Windows (install.sh installs win32yank.exe)
	if vim.fn.executable("win32yank.exe") == 1 then
		vim.g.clipboard = {
			name = "win32yank-wsl",
			copy = { ["+"] = "win32yank.exe -i --crlf", ["*"] = "win32yank.exe -i --crlf" },
			paste = { ["+"] = "win32yank.exe -o --lf", ["*"] = "win32yank.exe -o --lf" },
			cache_enabled = 0,
		}
	end
end

return M
