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
