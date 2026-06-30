# MCPS (Midnight Commander PowerShell)

A lightweight, high-performance, terminal-based clone of the classic Linux Midnight Commander tool, written in Go.

## 🚀 Features
- **TUI Structure:** Gorgeous double-panel grid layout supporting simultaneous views of different directories.
- **Tab Navigation:** Switch active panels instantly using the `Tab` key.
- **File Actions:** Inline renaming (F2), file viewing (F3), built-in text editor (F4), copying (F5), moving (F6), creating directories (F7), deleting (F8), and clean terminal exit (F10).
- **High-Performance:** Compiled binary utilizing `tview` and `tcell` for zero screen flicker, instant folder queries, and cross-platform native speed.

## 💻 Quick Start

### Running the App
Pre-compiled binaries for **Windows**, **Linux**, and **macOS** are automatically built and published on the [Releases](https://github.com/bergloman/mcps/releases) page.

1. Download the executable for your platform.
2. Run it from your terminal:
   - **Windows:** `.\mcps.exe`
   - **Linux/macOS:** `./mcps`

### Local Compilation
If you have Go installed, you can compile and run MCPS locally:

```powershell
# Build using the provided build script
.\build.ps1

# The compiled binary will be placed inside the git-ignored bin/ directory:
.\bin\mcps.exe
```

## 📖 Documentation
For comprehensive details on features, compilation, and the release procedure, please refer to [AGENTS.md](./AGENTS.md).
