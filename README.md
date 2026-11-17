# dotfiles

My shell and editor setup for **WSL (zsh)** and **Windows (PowerShell 7)**: one repo, one install command per machine.

| Folder | What it is | Linked to (WSL) | Linked to (Windows) |
|---|---|---|---|
| `zsh/.zshrc` | zsh config | `~/.zshrc` | — |
| `pwsh/profile.ps1` | PowerShell 7 profile | — | loaded by a stub in `$PROFILE` |
| `nvim/` | Neovim config | `~/.config/nvim` | `%LOCALAPPDATA%\nvim` |
| `yazi/` | yazi config | `~/.config/yazi` | `%APPDATA%\yazi\config` |
| `ohmyposh/` | prompt theme (shared) | `~/.config/ohmyposh` | read from the repo |
| `fonts/JetBrainsMonoNerdFontMono/` | JetBrainsMono Nerd Font Mono + its license | installed by hand (Step 9) | installed by hand (Step 9) |
| `packages/` | tool lists for the installers | | |
| `tests/` | test suites | | |

Configs are **linked**, not copied: editing a file in the repo changes the live config immediately.

---

## Part 1: First-time setup (do this once)

### Step 1: Create the repository on GitHub

1. Go to <https://github.com/new>.
2. Name it `dotfiles`. Public or private both work; choose **private** if you are unsure.
3. Leave "Add a README", ".gitignore" and "license" **unchecked** (the repo already has them).
4. Click **Create repository** and keep the page open; you need its URL (`https://github.com/<you>/dotfiles.git`).

### Step 2: Put the files in place (in WSL)

```bash
cd ~
unzip /mnt/c/Users/<you>/Downloads/dotfiles.zip    # creates ~/dotfiles
cd ~/dotfiles
chmod +x install.sh tests/*.sh
```

### Step 3: Your Neovim config is already included

`nvim/` contains your config (from your NvimConfig repo, latest commit "addad bigfile support") with a few changes so it also runs on Windows:

| File | Change | Why |
|---|---|---|
| `init.lua` | first line: `require("utils.platform")` | loads the OS-specific settings before everything else |
| `lua/utils/platform.lua` | **new** | Windows: Windows PowerShell (`powershell.exe`, 5.1) as nvim's shell, `CC=gcc` for compiling parsers. WSL: clipboard via win32yank. Both: Mason's `bin/` on PATH early, and Windows/Linux paths into Mason packages |
| `lua/plugins/dap.lua` | netcoredbg and debugpy paths go through `utils.platform`; the C# dll finder normalizes paths | on Windows, Mason has `netcoredbg.exe` and `venv\Scripts\python.exe`, and paths use backslashes |
| `lua/plugins/treesitter.lua` | waits for Mason before compiling parsers; adds `:TSInstallSync` | on a fresh machine the tree-sitter CLI (installed by Mason) isn't there yet, so every parser failed on first launch |

Everything else is untouched.

**Optional: keep your nvim git history.** The simple way (Step 6 as written) starts nvim's history fresh inside this repo; your old NvimConfig repo stays on GitHub as an archive. To carry the history over instead, replace Step 6 with:

```bash
cd ~/dotfiles
mv nvim /tmp/nvim-new                      # set the updated config aside
git init
git add .
git commit -m "Initial dotfiles"
git branch -M main
git subtree add --prefix=nvim git@github-personal:SerhiiKitral/NvimConfig.git master
cp -r /tmp/nvim-new/. nvim/                # apply the cross-platform changes on top
git add nvim
git commit -m "nvim: cross-platform changes"
git remote add origin https://github.com/<you>/dotfiles.git
git push -u origin main
```

Afterwards you can archive NvimConfig on GitHub (Settings → Archive this repository).

### What the installers set up for nvim

| Your config uses | Needs | WSL (`install.sh`) | Windows (`install.ps1`) |
|---|---|---|---|
| `vim.treesitter.select`, `vim.lsp.config` | Neovim 0.12+ | latest release | scoop `neovim` |
| nvim-treesitter (main branch) | C compiler, tree-sitter CLI | `build-essential`; CLI via Mason | `mingw` (gcc); CLI via Mason |
| basedpyright, json-lsp | Node.js | Node 24 LTS to `~/.local/opt/node` | `nodejs-lts` |
| ruff, debugpy, clang-format, xmlformatter | Python with venv | `python3`, `python3-venv`, `python3-pip` | `python` |
| roslyn, csharpier, netcoredbg | .NET SDK | .NET LTS to `~/.dotnet` | `dotnet-sdk` |
| snacks picker | ripgrep, fd | `ripgrep`, `fd-find` | `ripgrep`, `fd` |
| clipboard `unnamedplus` | clipboard tool | `win32yank.exe` | built in |
| typst-preview (opens a browser) | link opener | `wslu` (wslview) | built in |

After installing tools, both installers run three headless nvim steps in this order (each with a time limit, so a stuck download can't hang the install):

1. `Lazy! restore`: plugins at the versions in `lazy-lock.json`
2. `MasonToolsInstallSync`: all language servers, formatters and debuggers from `mason-tool-installer.lua`
3. `TSInstallSync`: compiles your 17 treesitter parsers

Then run `:checkhealth` once in nvim to confirm everything is green.

### Step 4: Move machine-specific settings out of the repo

Anything that differs per machine or is secret goes in files that git ignores:

- WSL: `~/.zshrc.local` (created by the installer). Example: `CONDA_ROOT="$HOME/miniconda3"` if conda lives elsewhere.
- Windows: `pwsh\profile.local.ps1` in the repo folder (created by the installer, ignored by git). Example: your conda hook.

Never commit tokens or passwords.

### Step 5: Run the tests

```bash
sudo apt install -y shellcheck        # optional: lints install.sh
./tests/run-tests.sh
```

Four suites run in temporary folders (your real home and configs are never touched): `install.sh`, the zshrc, the nvim config, and (if PowerShell 7 is installed) the PowerShell files. All should pass. Failures are written to `logs/test-errors-<timestamp>.log`.

### Step 6: First commit and push

```bash
cd ~/dotfiles
git init
git add .
git commit -m "Initial dotfiles"
git branch -M main
git remote add origin https://github.com/<you>/dotfiles.git
git push -u origin main
```

If git asks who you are first:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

The repo includes a GitHub Actions workflow (`.github/workflows/test.yml`) that runs all tests on Linux **and** on a real Windows machine after every push. Results are in the repo's **Actions** tab.

### Step 7: Install on WSL

Preview first, then run the full install. It skips everything you already have, so on your current machine it mostly adds what your nvim config needs (Node, .NET, Python venv, wslu) and links the configs:

```bash
./install.sh --dry-run        # shows what would change, changes nothing
./install.sh                  # installs what's missing, links configs, sets up nvim
exec zsh                      # reload
```

Your old configs (including your current `~/.config/nvim`) are **moved**, not deleted, to `~/.dotfiles-backup/<timestamp>/`. If you only want the links, use `./install.sh --links-only`.

On a **new** WSL machine:

```bash
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

### Step 8: Install on Windows

Open **Windows PowerShell** (the built-in one is fine) as a **normal user, not admin** (scoop refuses to install as admin):

```powershell
winget install --id Git.Git -e
# close and reopen PowerShell so git is on PATH
git clone https://github.com/<you>/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`-ExecutionPolicy Bypass` lets the installer run just this once; it doesn't change any setting.

**Windows PowerShell 5.1 stays exactly as it is.** The installer doesn't touch its profile or its execution policy, so it keeps its default prompt and behavior; nvim also uses it for `:!` commands and its terminal. Your setup (oh-my-posh, aliases, key bindings) loads only in **PowerShell 7**, which you start with `pwsh` or pick in Windows Terminal.

This installs scoop and everything in `packages\scoop.txt` (PowerShell 7, nvim, gcc, Node, Python, .NET SDK, fzf, ripgrep, fd, bat, eza, yazi, zoxide, oh-my-posh), the PSFzf module, links nvim and yazi configs, points your PowerShell 7 profile at the repo, and installs nvim plugins, Mason tools and parsers.

### Step 9: Install the font (manual, once)

Your prompt, yazi, eza and nvim use icons that only Nerd Fonts contain. The font lives in this repo, in `fonts/JetBrainsMonoNerdFontMono/` (all weights plus its license, `OFL.txt`), and is installed by hand, not by the scripts.

1. In Explorer, open `fonts\JetBrainsMonoNerdFontMono` in your Windows copy of the repo (`$HOME\dotfiles\fonts\JetBrainsMonoNerdFontMono`).
2. Select all the `.ttf` files, right-click and choose **Install**. If Windows says the font is already installed, you're done; skip replacing it (replacing while Windows Terminal is open creates duplicate `_0` files).
3. In **Windows Terminal → Settings**:
   - **Defaults → Appearance → Font face:** `JetBrainsMono Nerd Font Mono`
   - Optional, **Startup → Default profile:** `PowerShell` (the 7.x one) if you want new tabs to open with your setup. Leave it as is to keep Windows PowerShell as the default.
   - Click **Save**.

One install covers both WSL and PowerShell, because Windows Terminal draws the text for both. Open a new tab: you should see your oh-my-posh prompt with icons.

If you also run a Linux terminal inside WSL (for example kitty through WSLg), install the font there as well:

```bash
mkdir -p ~/.local/share/fonts/JetBrainsMonoNerdFontMono
cp ~/dotfiles/fonts/JetBrainsMonoNerdFontMono/*.ttf ~/.local/share/fonts/JetBrainsMonoNerdFontMono/
fc-cache -f
```

---

## Testing in a sandbox (optional, before touching your real setup)

Both sandboxes are throwaway copies of the system: test the full install there, then delete them. Your real WSL distro and Windows account are never touched.

### WSL: a temporary distro

In PowerShell on Windows:

```powershell
wsl --update                                     # --name needs WSL 2.4.4 or newer
wsl --install Ubuntu-24.04 --name dotfiles-test  # asks you to create a user
```

Inside the new distro (it opens automatically; later: `wsl -d dotfiles-test`):

```bash
cd ~
unzip /mnt/c/Users/<you>/Downloads/dotfiles.zip   # or: git clone <your repo URL> dotfiles
cd dotfiles && chmod +x install.sh tests/*.sh
./install.sh
exec zsh
```

Then try nvim, `y`, Ctrl+Backspace, and run `./tests/run-tests.sh`. When done, back in Windows PowerShell:

```powershell
wsl --unregister dotfiles-test    # deletes the distro and everything in it
```

The test distro can read your Windows files under `/mnt/c`, but nothing in the install writes there.

### Windows: Windows Sandbox

Windows Sandbox is a disposable Windows built into **Pro, Enterprise and Education** editions. Everything inside it is deleted when you close its window.

1. Enable it once, in an **administrator** PowerShell, then restart:
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
   ```
2. From your Windows copy of the repo:
   ```powershell
   cd $HOME\dotfiles
   powershell -ExecutionPolicy Bypass -File .\sandbox\Start-WindowsSandbox.ps1
   ```
   The sandbox opens with your repo mapped in read-only, copies it to `C:\Users\WDAGUtilityAccount\dotfiles` and opens PowerShell there.
3. Inside the sandbox run `.\install.ps1`, then open `pwsh` and `nvim` to try things out. The install downloads a few GB (Node, Python, .NET, gcc, Mason tools), so give it time.
4. Close the Sandbox window. Everything is gone.

Notes: the sandbox runs as administrator, so `install.ps1` installs scoop with `-RunAsAdmin` there (on your real machine, keep running it as a normal user). The sandbox has no Nerd Font or Windows Terminal, so icons show as boxes in its console; that's expected.

**Windows Home** has no Windows Sandbox. The closest equivalent is a temporary local user: Settings → Accounts → Other users → Add account → "I don't have this person's sign-in information" → "Add a user without a Microsoft account". Sign in as that user, run the install (scoop, the profile and nvim data are all per-user), then sign out, remove the account and choose **Delete account and data**.

---

## Part 2: Daily use

| Task | WSL | Windows |
|---|---|---|
| Go to the repo | `dots` | `dots` |
| Save changes | `git add -A && git commit -m "..." && git push` | same |
| Get changes from the other machine | `git pull` | `git pull` |
| Re-link after adding a config | `./install.sh --links-only` | `.\install.ps1 -LinksOnly` |
| See startup errors | `dotlog` | `dotlog` |
| Clear startup errors | `dotlog clear` | `dotlog clear` |
| Run tests | `./tests/run-tests.sh` | `.\tests\run-tests.ps1` |
| Reinstall nvim tools | `nvim --headless +MasonToolsInstallSync +qa` | same |
| Recompile parsers | `nvim --headless +TSInstallSync +qa` | same |

Keep **two clones**: `~/dotfiles` in WSL and `$HOME\dotfiles` in Windows, synced with push/pull. Don't point WSL at the Windows copy through `/mnt/c`: it is slow and mixes file permissions and line endings.

### Feature reference

| Feature | zsh (WSL) | PowerShell (Windows) |
|---|---|---|
| Delete one path segment | Ctrl+Backspace | Ctrl+Backspace |
| Delete the whole word/path | Alt+Backspace | — |
| Delete segment forward | Ctrl+Delete | Ctrl+Delete |
| Move by segment | Ctrl+Left / Ctrl+Right | Ctrl+Left / Ctrl+Right |
| Prefix history search | Up / Down | Up / Down |
| Fuzzy files / history / dirs | Ctrl+T / Ctrl+R / Alt+C | Ctrl+T / Ctrl+R |
| Fuzzy Tab completion | fzf-tab | PSFzf |
| Live ripgrep → nvim | Ctrl+N or `rfgrep` | Ctrl+N or `rfgrep` |
| Edit command in nvim | Ctrl+X Ctrl+E | Ctrl+X Ctrl+E |
| yazi, stay in last folder on quit | `y` | `y` |
| Go to Desktop | `desk` (`set-desktop` to change) | `desk` |
| Open in Explorer | `winopen [path]` | `winopen [path]` |

`rfgrep` on Windows has live search, preview and opening in nvim (multi-select builds a quickfix list), but not the Ctrl+N switch between rg and fzf modes inside fzf.

---

## Logs and troubleshooting

| What | Where |
|---|---|
| Installer, everything | `logs/install-<timestamp>.log` |
| Installer, errors only | `logs/install-errors-<timestamp>.log` (only created when something failed) |
| zsh startup problems | `~/.local/state/dotfiles/zsh-errors.log` |
| PowerShell startup problems | `%LOCALAPPDATA%\dotfiles\pwsh-errors.log` |
| Test failures | `logs/test-errors-<timestamp>.log` |

Both installers keep going after an error, finish everything else, print the error log path and exit with code 1. Fix the cause and simply run them again: every step skips what is already done.

**Common issues**

- *"running scripts is disabled on this system"* in PowerShell 7: run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` **in PowerShell 7** (`pwsh`). PowerShell 7 keeps its own setting, so this doesn't change Windows PowerShell 5.1.
- *A scoop package fails*: names occasionally move between buckets. Search with `scoop search <name>` and fix the line in `packages\scoop.txt`.
- *A download fails in `install.sh`*: release file names occasionally change upstream. The error log shows the URL; update it in `install.sh`.
- *Ctrl+Backspace does nothing in zsh*: press Ctrl+V then Ctrl+Backspace at the prompt. It should print `^H`; if it prints something else, bind that sequence in `zsh/.zshrc`.
- *Icons show as boxes*: the terminal font is not a Nerd Font (Step 9).
- *`dotlog` lists "X not found"*: that tool isn't installed. Run the installer again, or install it manually.
- *Mason step timed out or failed*: Mason uses the GitHub API, which has an hourly limit per IP address. Wait a while and run `nvim --headless +MasonToolsInstallSync +qa` (or open nvim and run `:MasonToolsInstall`).
- *Roslyn reports a missing .NET runtime*: install the version it names, e.g. WSL `curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0 --runtime dotnet --install-dir ~/.dotnet`, Windows `scoop install versions/dotnet9-sdk`.
- *Parsers fail to compile on Windows*: check `gcc --version` works in a new terminal. If it does and compiling still fails, install the MSVC compiler: `winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --passive"`, then run `$env:CC=$null; nvim --headless +TSInstallSync +qa`.

## Adding something new

- **A tool**: add it to `packages/apt.txt` (if apt has a recent version) or as a function in `install.sh`, and to `packages/scoop.txt`.
- **A config folder**: put it in the repo and add one `link` line to `link_configs` in `install.sh` and one `New-DirLink` line to `Set-ConfigLinks` in `install.ps1`. Add a matching check to the tests.

## Installer options

```text
./install.sh                  everything
./install.sh --links-only     only links
./install.sh --skip-packages  links + post-setup
./install.sh --no-post        skip login shell change and plugin install
./install.sh --dry-run        show what would happen

.\install.ps1                 everything
.\install.ps1 -LinksOnly      only links
.\install.ps1 -SkipPackages   links + post-setup
.\install.ps1 -NoPost         skip post-setup
.\install.ps1 -DryRun         show what would happen
```
