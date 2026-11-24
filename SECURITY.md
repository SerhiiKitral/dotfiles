# Security information for the dotfiles configuration

This document is written in ASD-STE100 Simplified Technical English. Technical names (programs, files, commands) are given in their usual form.

## 1. Purpose and scope

This document gives the data for a security approval of this configuration.

The configuration contains:

- Shell settings for zsh (WSL) and PowerShell 7 (Windows).
- A Neovim configuration with plugins and external tools.
- Two installers: `install.ps1` (Windows) and `install.sh` (WSL, Ubuntu/Debian).

This document tells you:

- Which programs the installers install.
- Which plugins and tools Neovim downloads.
- Which network connections occur, and when.
- Which parts can execute code.
- Which changes the installers make to the system.
- Which steps decrease the risk.

The data in this document agrees with the repository state of 24 November 2026. When you change the configuration, change this document too.

## 2. Summary of the risks

| No. | Risk | Where | Level |
|---|---|---|---|
| R1 | The installers execute remote scripts without a checksum or signature check. | `install.ps1`, `install.sh` | High |
| R2 | The installers download "latest" releases. The version is not fixed. | `install.sh`, scoop | Medium |
| R3 | `install.ps1` sets the PowerShell Gallery to "Trusted". This setting stays after the installation. | `install.ps1` | Medium |
| R4 | Mason uses a second, community package registry (`Crashdummyy/mason-registry`). | `nvim/lua/plugins/mason.lua` | Medium |
| R5 | Neovim downloads and compiles native code (treesitter parsers) and downloads prebuilt binaries. | nvim-treesitter, blink.cmp, Mason | Medium |
| R6 | Language servers and debuggers can execute code from the project that you open. | roslyn, debugpy, netcoredbg | Medium |
| R7 | Neovim makes automatic network connections at start (update checks, tool installation). | lazy.nvim, mason-tool-installer | Low |
| R8 | Shell plugins (zinit) are not fixed to a version. | `zsh/.zshrc` | Low |

Section 12 gives the steps that decrease each risk.

## 3. Systems

| System | Shell | Package manager | Configuration location |
|---|---|---|---|
| Windows 10/11 | PowerShell 7 (`pwsh`) | scoop | `%LOCALAPPDATA%\nvim`, `%APPDATA%\yazi\config`, PowerShell profile |
| WSL 2 (Linux) | zsh | apt (`install.sh`) | `~/.config/nvim`, `~/.zshrc`, `~/.config/yazi` |

Note: The current WSL distribution is Fedora 42. `install.sh` uses apt, so it does not operate on Fedora. On Fedora, the tools were installed by hand (dnf, official release archives, Mason).

## 4. Installers

### 4.1 `install.ps1` (Windows)

The installer does these steps:

1. It installs scoop. It downloads `https://get.scoop.sh` and executes the script directly.
2. It installs the scoop packages from `packages/scoop.txt` (section 5).
3. It sets the PowerShell Gallery to "Trusted" and installs the PSFzf module.
4. It makes directory junctions from the repository to the configuration locations.
5. It writes a stub to the PowerShell 7 profile. The stub loads `pwsh/profile.ps1` from the repository.
6. It starts Neovim in headless mode three times: plugin restore, Mason tool installation, treesitter parser installation.

Rights:

- The installer operates as a normal user. It does not need administrator rights.
- In Windows Sandbox only, it installs scoop with `-RunAsAdmin`.
- The README tells you to start the installer with `-ExecutionPolicy Bypass`. This setting applies only to that one process.

Backups and logs:

- The installer moves existing configuration folders to `~\.dotfiles-backup\<timestamp>`. It does not delete them.
- The installer writes logs to `logs\` in the repository. The logs contain command output only. They do not contain passwords.

### 4.2 `install.sh` (WSL)

The installer does these steps:

1. It installs the apt packages from `packages/apt.txt` (section 6.1). This step uses `sudo`.
2. It downloads tools that apt does not supply, or supplies in an old version (section 6.2).
3. It makes symbolic links from the repository to the configuration locations.
4. It starts Neovim in headless mode three times, as `install.ps1` does.

Integrity:

- The installer downloads with `curl -fsSL` over HTTPS.
- The installer does not compare checksums or signatures.
- The installer executes three remote scripts directly through a pipe to the shell: zoxide, oh-my-posh and `dotnet-install.sh`.

WARNING: A REMOTE SCRIPT THAT IS PIPED TO THE SHELL CAN EXECUTE ANY COMMAND WITH YOUR USER RIGHTS. IF THE SERVER IS NOT SAFE, YOUR SYSTEM IS NOT SAFE.

## 5. Windows applications (scoop)

All packages come from the scoop `main` bucket (`https://github.com/ScoopInstaller/Main`). Scoop downloads the files from the vendor URL in each manifest. Scoop compares the SHA-256 hash in the manifest with the downloaded file.

| Package | Purpose | Publisher / source |
|---|---|---|
| git | Version control. Downloads Neovim plugins. | Git for Windows |
| pwsh | PowerShell 7 | Microsoft |
| fzf | Fuzzy finder for the shell | junegunn/fzf (GitHub) |
| zoxide | Directory jump command (`cd`) | ajeetdsouza/zoxide (GitHub) |
| bat | File viewer with colors (fzf preview) | sharkdp/bat (GitHub) |
| eza | File list command (`ls`) | eza-community/eza (GitHub) |
| yazi | Terminal file manager | sxyazi/yazi (GitHub) |
| oh-my-posh | Shell prompt | JanDeDobbeleer/oh-my-posh (GitHub) |
| file | File type detection (yazi) | GnuWin / file |
| 7zip | Archive tool (yazi, scoop) | 7-Zip (Igor Pavlov) |
| jq | JSON tool | jqlang/jq (GitHub) |
| neovim | Text editor | neovim/neovim (GitHub) |
| ripgrep | Text search (Neovim picker) | BurntSushi/ripgrep (GitHub) |
| fd | File search (Neovim picker) | sharkdp/fd (GitHub) |
| mingw | gcc compiler. Compiles treesitter parsers. | MinGW-w64 (winlibs build) |
| nodejs-lts | Node.js. Mason installs npm packages with it. | OpenJS Foundation |
| python | Python. Mason installs pip packages with it. | Python Software Foundation |
| dotnet-sdk | .NET SDK. Roslyn, CSharpier and netcoredbg need it. | Microsoft |

PowerShell module:

| Module | Purpose | Source |
|---|---|---|
| PSFzf | fzf key bindings in PowerShell | PowerShell Gallery |

The font (JetBrainsMono Nerd Font Mono) is in the repository, in `fonts/`. You install it by hand. Its license is `OFL.txt`.

## 6. WSL applications

### 6.1 apt packages (`packages/apt.txt`)

These packages come from the distribution repositories. apt makes sure that the package signatures are correct.

| Package | Purpose |
|---|---|
| zsh | Shell |
| git, curl, wget, unzip, xz-utils, file | Basic tools for the installer and the plugins |
| build-essential | C compiler. Compiles treesitter parsers. |
| ripgrep, fd-find, bat | Search and preview tools |
| python3, python3-venv, python3-pip | Mason installs Python tools into virtual environments. |
| libicu-dev | Library that .NET needs |
| wslu | Opens links in the Windows browser (typst preview) |

### 6.2 Direct downloads (`install.sh`)

| Tool | Download URL | Method | Checksum |
|---|---|---|---|
| Neovim | `github.com/neovim/neovim/releases/latest` | Archive | No |
| fzf | `github.com/junegunn/fzf` | `git clone --depth 1` | No |
| zoxide | `raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh` | Script piped to `sh` | No |
| oh-my-posh | `ohmyposh.dev/install.sh` | Script piped to `bash` | No |
| yazi | `github.com/sxyazi/yazi/releases/latest` | Archive | No |
| eza | `github.com/eza-community/eza/releases/latest` | Archive | No |
| Node.js (v24 LTS) | `nodejs.org/dist/latest-v24.x` | Archive | No (the installer reads `SHASUMS256.txt` only to find the file name) |
| .NET SDK (LTS) | `dot.net/v1/dotnet-install.sh` | Script piped to `bash` | No |
| win32yank | `github.com/equalsraf/win32yank/releases/latest` | Archive | No |

All tools go into the user home directory (`~/.local/bin`, `~/.local/opt`, `~/.dotnet`, `~/.fzf`). They do not go into system folders.

## 7. Shell plugins and integrations

### 7.1 zsh (`zsh/.zshrc`)

| Item | Source | Version control |
|---|---|---|
| zinit (plugin manager) | `github.com/zdharma-continuum/zinit` (cloned at first start) | Not fixed |
| zsh-completions | `zsh-users/zsh-completions` | Not fixed |
| fzf-tab | `Aloxaf/fzf-tab` | Not fixed |
| zsh-autosuggestions | `zsh-users/zsh-autosuggestions` | Not fixed |
| zsh-syntax-highlighting | `zsh-users/zsh-syntax-highlighting` | Not fixed |

At start, `.zshrc` executes the output of these local programs with `eval`: `fzf --zsh`, `zoxide init`, `oh-my-posh init`. Conda (optional) executes `conda shell.zsh hook` when you first type `conda`.

`.zshrc` loads `~/.zshrc.local` if the file exists. This file is not in the repository.

### 7.2 PowerShell (`pwsh/profile.ps1`)

At start, the profile executes the output of `zoxide init powershell` and `oh-my-posh init pwsh` with `Invoke-Expression`. It loads PSReadLine and PSFzf.

The profile loads `pwsh/profile.local.ps1` if the file exists. This file is not in the repository.

PSReadLine keeps the command history (50 000 lines) in the user profile. Do not type passwords on the command line.

## 8. Neovim plugins

lazy.nvim installs the plugins from GitHub with git. The file `nvim/lazy-lock.json` fixes each plugin to one commit. `Lazy! restore` installs exactly these commits.

| Plugin (GitHub repository) | Purpose | Security note |
|---|---|---|
| folke/lazy.nvim | Plugin manager | Clones itself from GitHub at first start. Update check is on (section 10). |
| saghen/blink.cmp | Completion | Downloads a prebuilt Rust binary (fuzzy matcher) from its GitHub release. |
| akinsho/bufferline.nvim | Buffer tabs | None |
| stevearc/conform.nvim | Code format | Starts external formatters (section 9). |
| lewis6991/gitsigns.nvim | Git signs | Starts `git`. |
| folke/lazydev.nvim | Lua development help | None |
| nvim-lualine/lualine.nvim | Status line | None |
| mason-org/mason.nvim | Tool installer | Downloads and installs executables (section 9). |
| WhoIsSethDaniel/mason-tool-installer.nvim | Installs the Mason tool list | Installs missing tools at each start. |
| nvim-mini/mini.icons, mini.misc, mini.move, mini.pairs, mini.surround | Editor helpers | None |
| folke/noice.nvim, MunifTanjim/nui.nvim | Command line UI | None |
| mfussenegger/nvim-dap | Debugger client | Starts debug adapters. Executes the program that you debug. |
| mfussenegger/nvim-dap-python | Python debug settings | Uses debugpy from Mason. |
| rcarriga/nvim-dap-ui, nvim-neotest/nvim-nio, theHamsta/nvim-dap-virtual-text | Debugger UI | None |
| neovim/nvim-lspconfig | Language server settings | Starts language servers (section 9). |
| nvim-treesitter/nvim-treesitter, nvim-treesitter-textobjects | Syntax parsers | Downloads parser source code and compiles it into native libraries. |
| nvim-lua/plenary.nvim | Lua library | None |
| seblyng/roslyn.nvim | C# language server client | Starts Roslyn. Roslyn loads the project with MSBuild. |
| folke/snacks.nvim | Picker, notifications | Starts `rg`, `fd`, `git`. |
| folke/todo-comments.nvim, folke/trouble.nvim, folke/ts-comments.nvim, folke/which-key.nvim | Editor helpers | None |
| folke/tokyonight.nvim | Color scheme | None |
| chomosuke/typst-preview.nvim | Typst preview | Starts a local web server and opens the browser. Can download helper binaries. |
| mikavilpas/yazi.nvim | yazi in Neovim | Starts `yazi`. Contains a git submodule (`yazi-rs/plugins`). |

The configuration also contains two local modules: `utils/platform.lua` (system settings) and `utils/floating-terminal.lua` (terminal window).

## 9. Mason tools

Mason installs these tools into the Neovim data folder (`stdpath("data")/mason`). The tools are not installed system-wide. Mason does not fix the tool versions in this configuration. It installs the version from the registry.

| Tool | Purpose | Source type |
|---|---|---|
| basedpyright | Python language server | npm |
| ruff | Python lint and format | PyPI |
| lua-language-server | Lua language server | GitHub release |
| roslyn-language-server | C# language server | Mason main registry (Microsoft package) |
| tinymist | Typst language server | GitHub release |
| clangd | C/C++ language server | GitHub release |
| json-lsp | JSON language server | npm |
| lemminx | XML language server | GitHub release |
| stylua | Lua format | GitHub release |
| shfmt | Shell format | GitHub release |
| csharpier | C# format | NuGet (.NET tool) |
| clang-format | C/C++ format | PyPI |
| xmlformatter | XML format | PyPI |
| jq | JSON format | GitHub release |
| netcoredbg | .NET debugger | GitHub release |
| debugpy | Python debugger | PyPI |
| tree-sitter-cli | Builds treesitter parsers | GitHub release |

To see the exact source and version of a tool, open `:Mason` and push `<CR>` on the tool name.

Registries:

| Registry | Owner | Status |
|---|---|---|
| `github:mason-org/mason-registry` | Mason project (official) | Necessary |
| `github:Crashdummyy/mason-registry` | Private person (community) | Not necessary. Roslyn now comes from the main registry. |

Treesitter parsers: bash, c, c_sharp, elixir, heex, html, javascript, json, lua, markdown, markdown_inline, python, query, typst, vim, vimdoc, xml (and dtd as a dependency of xml). nvim-treesitter downloads the source code from the GitHub repository of each parser. The local compiler (gcc) builds each parser into a native library. Neovim loads the libraries into its process.

## 10. Network connections

| When | Program | Destination | Purpose |
|---|---|---|---|
| Installation | scoop | GitHub, vendor sites | Applications |
| Installation | apt, curl | Distribution mirrors, GitHub, nodejs.org, dot.net, ohmyposh.dev | Applications |
| Installation | PowerShellGet | powershellgallery.com | PSFzf |
| First zsh start | git | github.com | zinit and zsh plugins |
| Neovim start | lazy.nvim | github.com | Update check (`checker = { enabled = true }`) |
| Neovim start | mason-tool-installer | GitHub, npm, PyPI, NuGet | Installs missing tools |
| Neovim start / `:TSUpdate` | nvim-treesitter | github.com | Parser source code |
| blink.cmp update | blink.cmp | github.com | Prebuilt binary |
| `:Lazy update`, `:Lazy sync` | lazy.nvim | github.com | Plugin updates |
| Typst preview | typst-preview | localhost only | Local preview server |
| Open a project | language servers, `dotnet` | NuGet (if the project restores packages) | Project dependencies |

No component sends telemetry from this configuration on purpose. Some tools have their own telemetry settings. For example, the .NET SDK sends telemetry by default. To stop .NET telemetry, set `DOTNET_CLI_TELEMETRY_OPTOUT=1`.

## 11. Code execution from files that you open

These parts can execute code that is in the project or the file:

- **Roslyn** loads C# projects with MSBuild. MSBuild targets in a `.csproj` file can execute commands.
- **netcoredbg and debugpy** execute the program that you start in the debugger.
- **conform.nvim** starts formatters on save. A formatter can read a configuration file from the project (for example `.editorconfig`, `pyproject.toml`, `.clang-format`).
- **Neovim terminal and `:!`** execute shell commands. On Windows, Neovim uses `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned`.

Neovim settings:

- `exrc` is off (default). Neovim does not execute `.nvim.lua` files from the project.
- `modeline` uses the default value. Modelines can set options only. They cannot execute commands.

CAUTION: DO NOT OPEN A C# PROJECT FROM AN UNKNOWN SOURCE IN NEOVIM. ROSLYN CAN EXECUTE BUILD COMMANDS FROM THE PROJECT FILE.

## 12. Steps to decrease the risk

Do these steps before you request approval, or write the reason why you do not do them.

| Risk | Step |
|---|---|
| R1 | Download each installer script first. Read it. Then execute the local file. Do not pipe a remote script to the shell. |
| R1 | Compare the SHA-256 hash of each archive with the hash that the publisher gives (for example `SHASUMS256.txt` for Node.js). |
| R2 | Replace "latest" URLs with URLs that contain a fixed version number. |
| R3 | After the installation, set the PowerShell Gallery back to "Untrusted": `Set-PSRepository PSGallery -InstallationPolicy Untrusted` |
| R4 | Remove the line `"github:Crashdummyy/mason-registry",` from `nvim/lua/plugins/mason.lua`. |
| R5 | Use only the parsers and tools that you need. Remove the others from the lists. |
| R6 | Open unknown projects only in a disposable environment (Windows Sandbox or a test WSL distribution). The repository README tells you how. |
| R7 | To stop the automatic update check, set `checker = { enabled = false }` in `nvim/lua/config/lazy.lua`. |
| R7 | To stop the automatic tool installation, set `run_on_start = false` in `mason-tool-installer.lua`. Then install tools only with `:MasonToolsInstall`. |
| R8 | Fix each zinit plugin to a commit with the `ver` ice, for example `zinit ice ver"<commit>"`. |

## 13. How to examine the installed state

Windows (PowerShell 7):

```powershell
scoop list                                   # installed applications and versions
scoop status                                 # applications with updates
Get-InstalledModule                          # PowerShell modules
Get-PSRepository                             # PowerShell Gallery trust setting
Get-Item "$env:LOCALAPPDATA\nvim" | Select-Object LinkType, Target
```

WSL (zsh):

```bash
nvim --version
ls -l ~/.local/bin ~/.local/opt              # tools that install.sh downloaded
ls ~/.local/share/zinit/plugins              # zsh plugins
```

Neovim (both systems):

```vim
:Lazy                  " plugins and their commits
:Mason                 " installed tools, versions and sources
:checkhealth           " status of all components
```

The file `nvim/lazy-lock.json` is the full list of plugin commits. Keep it in git. Approve a plugin update when you approve a change to this file.

## 14. Data and credentials

- The repository does not contain passwords, tokens or keys.
- The local files `~/.zshrc.local` and `pwsh/profile.local.ps1` are not in git (`.gitignore`). Do not put secrets in files that are in the repository.
- The shell history files keep all commands that you type.
- On WSL, win32yank copies the Neovim clipboard to the Windows clipboard. Other Windows programs can read the clipboard.
- The installer logs are in `logs/`. Do not commit them if they contain local paths or user names that you must keep private.
