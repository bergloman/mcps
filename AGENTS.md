# MCPS

This repository contains a compiled, high-performance, terminal-based clone of the classic Linux Midnight Commander tool:
- **Go Version (`mcps-go/`):** A compiled, high-performance TUI implementation designed for zero screen flicker, instant folder queries, and native cross-platform speed.

---

## Features
- **TUI Structure:** Gorgeous double-panel grid layout supporting simultaneous views of different directories.
- **Tab Navigation:** Switch active panels instantly using the `Tab` key.
- **F2 - Rename:** Simple, clean, and inline in-place file/directory renames.
- **F3 - Viewer:** High-performance textual file viewing with page scroll navigation.
- **F4 - Editor:** Built-in full-screen high-contrast text editing with save (`F2`) support and clean ESC/F4 exit.
- **F5 - Copy:** Recursive copy with pre-filled destination suggestions.
- **F6 - Move:** Cross-device moving (with native fallbacks for crossing volumes).
- **F7 - MkDir:** Fast folder creation.
- **F8 - Delete:** Recursive delete with safety confirmations.
- **F10 - Quit:** Clean terminal exit.

---

## 🚀 Go Version (`mcps-go`)

The Go version is built on top of the robust `tview` and `tcell` libraries. It resolves all rendering limits and flickering of traditional shells, offering massive speed improvements.

### Requirements
- Go 1.21 or newer.

### Build & Installation
To build the compiled high-performance binary:

1. **Navigate to the Go folder:**
   ```powershell
   cd mcps-go
   ```

2. **Download & Clean Dependencies:**
   ```powershell
   go mod tidy
   ```

3. **Build the Executable:**
   * **For Windows:**
     ```powershell
     go build -o mcps.exe
     ```
   * **For Linux/macOS:**
     ```bash
     go build -o mcps
     ```

### Running the App
* **On Windows:**
  ```powershell
  .\mcps.exe
  ```
* **On Linux/macOS:**
  ```bash
  ./mcps
  ```

By default, the application opens in your current working directory and displays it in both panels.

---

## 📦 Release Procedure

To release a new version of MCPS, follow these exact steps:

### Pre-requisites
1. Ensure the workspace is clean and all functional changes are tested and compiled locally.
2. Determine the release version (using semantic versioning, e.g., `v1.0.0`).

### Execution Checklist
1. **Local Build Check:** Run compilation locally to verify no build regressions exist:
   ```powershell
   cd mcps-go
   go build -ldflags="-s -w -X 'main.Version=v1.0.0'" -o mcps.exe main.go
   Remove-Item -Force mcps.exe
   cd ..
   ```
2. **Commit Changes:** Stage and commit all uncommitted changes (like updates to `AGENTS.md` or source files) with an appropriate commit message.
3. **Tagging:** Create a new git tag matching the version format `v*`:
   ```powershell
   git tag -a v1.0.0 -m "Release v1.0.0"
   ```
4. **Push Changes & Tags:** Push both the commit branch and the tags to the remote repository:
   ```powershell
   git push origin main
   git push origin v1.0.0
   ```
5. **Verify GitHub Action:** Monitor the "Release Builds" GitHub Action workflow. Once completed, verify that the compiled binaries (Windows, Linux, macOS) are attached to the release on the repository's Releases page.
