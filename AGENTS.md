# MCPS

This repository contains two lightweight, terminal-based clones of the classic Linux Midnight Commander tool:
1. **PowerShell Version (`mcps-ps/mcps.ps1`):** A zero-dependency script designed for instant, portable use in PowerShell environments.
2. **Go Version (`mcps-go/`):** A compiled, high-performance TUI implementation designed for zero screen flicker, instant folder queries, and native cross-platform speed.

---

## Features (Both Versions)
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

The Go version is built on top of the robust `tview` and `tcell` libraries. It resolves all rendering limits and flickering of PowerShell, offering massive speed improvements.

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

---

## 🛠️ PowerShell Version (`mcps-ps`)

A pure PowerShell script that runs directly in your terminal. Perfect for quick tasks where Go is not installed on the system.

### Running the Script
Ensure your execution policy allows running scripts locally, then execute:
```powershell
.\mcps-ps\mcps.ps1
```

By default, both versions open in your current working directory and display it in both panels.
