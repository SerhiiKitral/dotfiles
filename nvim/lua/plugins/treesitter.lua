return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false, -- main branch does not support lazy-loading
	build = ":TSUpdate",
	config = function()
		local parsers = {
			"bash",
			"c",
			"c_sharp",
			"elixir",
			"heex",
			"html",
			"javascript",
			"json",
			"lua",
			"markdown",
			"markdown_inline",
			"python",
			"query",
			"typst",
			"vim",
			"vimdoc",
			"xml",
		}
		local function install()
			return require("nvim-treesitter").install(parsers)
		end

		-- Parsers are compiled with the tree-sitter CLI, which Mason installs.
		-- On a fresh machine it isn't there yet: wait for Mason to finish first.
		if vim.fn.executable("tree-sitter") == 1 then
			install()
		else
			vim.api.nvim_create_autocmd("User", {
				pattern = "MasonToolsUpdateCompleted",
				once = true,
				callback = function()
					vim.schedule(install)
				end,
			})
		end

		-- Blocking install, used by install.sh / install.ps1: nvim --headless +TSInstallSync +qa
		vim.api.nvim_create_user_command("TSInstallSync", function()
			install():wait(10 * 60 * 1000)
		end, { desc = "Install this config's treesitter parsers and wait" })

		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local buf = args.buf
				if not pcall(vim.treesitter.start, buf) then
					return -- no parser for this filetype
				end
				-- Use treesitter indents only where the language has indent rules;
				-- otherwise keep Neovim's built-in indenting (e.g. for C#)
				local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
				if lang and vim.treesitter.query.get(lang, "indents") then
					vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end

				-- Incremental selection (built into Neovim 0.12).
				-- Buffer-local, so <CR> still works in quickfix etc.
				vim.keymap.set({ "n", "x" }, "<CR>", function()
					vim.treesitter.select("parent", vim.v.count1)
				end, { buffer = buf, desc = "Expand selection" })
				vim.keymap.set("x", "<BS>", function()
					vim.treesitter.select("child", vim.v.count1)
				end, { buffer = buf, desc = "Shrink selection" })
			end,
		})
	end,
}
