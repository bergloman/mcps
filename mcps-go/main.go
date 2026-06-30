package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// Version is the current version of the application, dynamically injected during release builds.
var Version = "dev"

// PanelState tracks state of left and right file panels
type PanelState struct {
	Table         *tview.Table
	Path          string
	Items         []os.DirEntry
	HasParent     bool
	SelectedIndex int
}

// AppState keeps track of global application states
type AppState struct {
	App         *tview.Application
	Pages       *tview.Pages
	Left        *PanelState
	Right       *PanelState
	ActivePanel *PanelState
	PromptLine  *tview.InputField
}

func main() {
	app := tview.NewApplication()
	pages := tview.NewPages()

	currentDir, err := os.Getwd()
	if err != nil {
		currentDir = "."
	}
	// Resolve absolute path
	if abs, err := filepath.Abs(currentDir); err == nil {
		currentDir = abs
	}

	leftTable := tview.NewTable().SetBorders(false).SetSelectable(true, false)
	rightTable := tview.NewTable().SetBorders(false).SetSelectable(true, false)

	promptLine := tview.NewInputField().
		SetLabel("").
		SetFieldBackgroundColor(tcell.ColorBlack).
		SetFieldTextColor(tcell.ColorWhite)

	state := &AppState{
		App:   app,
		Pages: pages,
		Left: &PanelState{
			Table: leftTable,
			Path:  currentDir,
		},
		Right: &PanelState{
			Table: rightTable,
			Path:  currentDir,
		},
		PromptLine: promptLine,
	}
	state.ActivePanel = state.Left

	// Set footer TUI component (MC-style action bar using Table for 100% reliable rendering)
	footerTable := tview.NewTable().SetBorders(false)
	footerTable.SetBackgroundColor(tcell.ColorDarkBlue)

	keys := []string{"2", "3", "4", "5", "6", "7", "8", "10"}
	labels := []string{"Rename", "View", "Edit", "Copy", "Move", "MkDir", "Delete", "Quit"}

	col := 0
	for i := 0; i < len(keys); i++ {
		// Key cell: White text on Black background
		keyCell := tview.NewTableCell(" " + keys[i] + " ").
			SetTextColor(tcell.ColorWhite).
			SetBackgroundColor(tcell.ColorBlack).
			SetAlign(tview.AlignCenter)
		footerTable.SetCell(0, col, keyCell)
		col++

		// Label cell: Black text on Aqua (Cyan) background
		labelCell := tview.NewTableCell(" " + labels[i] + " ").
			SetTextColor(tcell.ColorBlack).
			SetBackgroundColor(tcell.ColorAqua).
			SetAlign(tview.AlignLeft)
		footerTable.SetCell(0, col, labelCell)
		col++

		// Separator space (only if not the last item)
		if i < len(keys)-1 {
			spaceCell := tview.NewTableCell(" ").
				SetBackgroundColor(tcell.ColorDarkBlue)
			footerTable.SetCell(0, col, spaceCell)
			col++
		}
	}

	// Header bar: White text on DarkBlue background, displaying version
	headerText := fmt.Sprintf(" MCPS (%s) - High-Performance Go Edition", Version)
	header := tview.NewTextView()
	header.SetTextColor(tcell.ColorWhite)
	header.SetBackgroundColor(tcell.ColorDarkBlue)
	header.SetText(headerText)

	// Set grids/layout (panels occupy the middle row, maximizing space)
	grid := tview.NewGrid().
		SetRows(1, 0, 1, 1).
		SetColumns(0, 0).
		SetBorders(false)

	grid.AddItem(header, 0, 0, 1, 2, 0, 0, false)
	grid.AddItem(leftTable, 1, 0, 1, 1, 0, 0, true)
	grid.AddItem(rightTable, 1, 1, 1, 1, 0, 0, false)
	grid.AddItem(promptLine, 2, 0, 1, 2, 0, 0, false)
	grid.AddItem(footerTable, 3, 0, 1, 2, 0, 0, false)

	pages.AddPage("main", grid, true, true)

	// Configure table properties and styles
	setupTable(state.Left)
	setupTable(state.Right)

	// Load initial directories
	state.LoadDirectory(state.Left, state.Left.Path)
	state.LoadDirectory(state.Right, state.Right.Path)

	// Setup table selections & focus
	leftTable.SetDoneFunc(func(key tcell.Key) {
		if key == tcell.KeyTab {
			app.SetFocus(rightTable)
			state.ActivePanel = state.Right
			setupTableHighlight(state)
		}
	})

	rightTable.SetDoneFunc(func(key tcell.Key) {
		if key == tcell.KeyTab {
			app.SetFocus(leftTable)
			state.ActivePanel = state.Left
			setupTableHighlight(state)
		}
	})

	// Table item double-click or Enter
	leftTable.SetSelectedFunc(func(row, column int) {
		state.OnEnter()
	})
	rightTable.SetSelectedFunc(func(row, column int) {
		state.OnEnter()
	})

	setupTableHighlight(state)

	// Application level keycaptures for F-keys
	app.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyTab:
			if app.GetFocus() == leftTable {
				app.SetFocus(rightTable)
				state.ActivePanel = state.Right
			} else if app.GetFocus() == rightTable {
				app.SetFocus(leftTable)
				state.ActivePanel = state.Left
			}
			setupTableHighlight(state)
			return nil
		case tcell.KeyF2:
			state.OnRename()
			return nil
		case tcell.KeyF3:
			state.OnView()
			return nil
		case tcell.KeyF4:
			state.OnEdit()
			return nil
		case tcell.KeyF5:
			state.OnCopy()
			return nil
		case tcell.KeyF6:
			state.OnMove()
			return nil
		case tcell.KeyF7:
			state.OnMkdir()
			return nil
		case tcell.KeyF8:
			state.OnDelete()
			return nil
		case tcell.KeyF10:
			app.Stop()
			return nil
		}
		return event
	})

	if err := app.SetRoot(pages, true).Run(); err != nil {
		fmt.Printf("Error running application: %v\n", err)
		os.Exit(1)
	}
}

func setupTable(p *PanelState) {
	p.Table.SetBorders(false)
	p.Table.SetSelectable(true, false)
	p.Table.SetEvaluateAllRows(true)
	p.Table.SetBackgroundColor(tcell.ColorDarkBlue)
}

func setupTableHighlight(state *AppState) {
	// Set cyan borders/titles for the active panel and gray for inactive
	activeColor := tcell.ColorAqua
	inactiveColor := tcell.ColorDarkGray

	// Active panel selected style: Black text on Aqua (Cyan) background
	activeSelectedStyle := tcell.StyleDefault.
		Foreground(tcell.ColorBlack).
		Background(tcell.ColorAqua)

	// Inactive panel selected style: White text on DarkGray background
	inactiveSelectedStyle := tcell.StyleDefault.
		Foreground(tcell.ColorWhite).
		Background(tcell.ColorDarkGray)

	if state.ActivePanel == state.Left {
		state.Left.Table.SetBorderColor(activeColor).SetBorder(true).SetTitle(" [ Left: " + state.Left.Path + " ] ")
		state.Left.Table.SetSelectedStyle(activeSelectedStyle)

		state.Right.Table.SetBorderColor(inactiveColor).SetBorder(true).SetTitle(" [ Right: " + state.Right.Path + " ] ")
		state.Right.Table.SetSelectedStyle(inactiveSelectedStyle)
	} else {
		state.Left.Table.SetBorderColor(inactiveColor).SetBorder(true).SetTitle(" [ Left: " + state.Left.Path + " ] ")
		state.Left.Table.SetSelectedStyle(inactiveSelectedStyle)

		state.Right.Table.SetBorderColor(activeColor).SetBorder(true).SetTitle(" [ Right: " + state.Right.Path + " ] ")
		state.Right.Table.SetSelectedStyle(activeSelectedStyle)
	}
}

// LoadDirectory re-scans filesystem and redraws the specific panel table
func (state *AppState) LoadDirectory(p *PanelState, path string) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		absPath = path
	}
	p.Path = absPath

	p.Table.Clear()

	// Title Row Headers
	p.Table.SetCell(0, 0, tview.NewTableCell("Name").SetSelectable(false).SetTextColor(tcell.ColorYellow).SetAttributes(tcell.AttrBold))
	p.Table.SetCell(0, 1, tview.NewTableCell("Size").SetSelectable(false).SetTextColor(tcell.ColorYellow).SetAttributes(tcell.AttrBold).SetAlign(tview.AlignRight))
	p.Table.SetCell(0, 2, tview.NewTableCell("Date").SetSelectable(false).SetTextColor(tcell.ColorYellow).SetAttributes(tcell.AttrBold).SetAlign(tview.AlignRight))

	entries, err := os.ReadDir(absPath)
	if err != nil {
		p.Table.SetCell(1, 0, tview.NewTableCell(fmt.Sprintf("Error: %v", err)).SetTextColor(tcell.ColorRed))
		return
	}

	p.Items = nil
	p.HasParent = false

	// Add parent folder entry if not at root
	parent := filepath.Dir(absPath)
	if parent != absPath {
		p.HasParent = true
		p.Table.SetCell(1, 0, tview.NewTableCell("..").SetTextColor(tcell.ColorAqua))
		p.Table.SetCell(1, 1, tview.NewTableCell("<UP>").SetTextColor(tcell.ColorAqua).SetAlign(tview.AlignRight))
		p.Table.SetCell(1, 2, tview.NewTableCell("").SetAlign(tview.AlignRight))
	}

	// Sort directories first, then files
	var dirs []os.DirEntry
	var files []os.DirEntry
	for _, entry := range entries {
		if entry.IsDir() {
			dirs = append(dirs, entry)
		} else {
			files = append(files, entry)
		}
	}

	sort.Slice(dirs, func(i, j int) bool {
		return strings.ToLower(dirs[i].Name()) < strings.ToLower(dirs[j].Name())
	})
	sort.Slice(files, func(i, j int) bool {
		return strings.ToLower(files[i].Name()) < strings.ToLower(files[j].Name())
	})

	p.Items = append(dirs, files...)

	offset := 1
	if p.HasParent {
		offset = 2
	}

	for i, item := range p.Items {
		row := i + offset
		info, _ := item.Info()

		var nameStr string
		var sizeStr string
		var dateStr string
		nameColor := tcell.ColorWhite

		if item.IsDir() {
			nameStr = item.Name() + "/"
			nameColor = tcell.ColorAqua
			sizeStr = "<DIR>"
		} else {
			nameStr = item.Name()
			if info != nil {
				sizeStr = formatSize(info.Size())
			}
		}

		if info != nil {
			dateStr = info.ModTime().Format("2006-01-02")
		}

		p.Table.SetCell(row, 0, tview.NewTableCell(nameStr).SetTextColor(nameColor))
		p.Table.SetCell(row, 1, tview.NewTableCell(sizeStr).SetTextColor(nameColor).SetAlign(tview.AlignRight))
		p.Table.SetCell(row, 2, tview.NewTableCell(dateStr).SetTextColor(nameColor).SetAlign(tview.AlignRight))
	}

	p.Table.Select(1, 0)
	setupTableHighlight(state)
}

func (state *AppState) GetSelectedItem() (string, string, bool, bool) {
	p := state.ActivePanel
	row, _ := p.Table.GetSelection()
	if row < 1 {
		return "", "", false, false
	}

	if row == 1 && p.HasParent {
		parent := filepath.Dir(p.Path)
		return "..", parent, true, true
	}

	offset := 1
	if p.HasParent {
		offset = 2
	}

	idx := row - offset
	if idx < 0 || idx >= len(p.Items) {
		return "", "", false, false
	}

	item := p.Items[idx]
	fullName := filepath.Join(p.Path, item.Name())
	return item.Name(), fullName, item.IsDir(), false
}

func (state *AppState) OnEnter() {
	_, fullName, isDir, isParent := state.GetSelectedItem()
	if fullName == "" {
		return
	}

	if isDir || isParent {
		state.LoadDirectory(state.ActivePanel, fullName)
		// Refresh inactive panel if same path
		inactive := state.GetInactivePanel()
		if inactive.Path == state.ActivePanel.Path {
			state.LoadDirectory(inactive, inactive.Path)
		}
	} else {
		// Launch standard shell opener for file
		state.openFileWithDefaultHandler(fullName)
	}
}

func (state *AppState) openFileWithDefaultHandler(path string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", "", path)
	case "darwin":
		cmd = exec.Command("open", path)
	default:
		cmd = exec.Command("xdg-open", path)
	}
	_ = cmd.Start()
}

func (state *AppState) GetInactivePanel() *PanelState {
	if state.ActivePanel == state.Left {
		return state.Right
	}
	return state.Left
}

// Refresh both panel directory states
func (state *AppState) Refresh() {
	leftSelName, _, _, _ := state.GetSelectionName(state.Left)
	rightSelName, _, _, _ := state.GetSelectionName(state.Right)

	state.LoadDirectory(state.Left, state.Left.Path)
	state.LoadDirectory(state.Right, state.Right.Path)

	state.RestoreSelection(state.Left, leftSelName)
	state.RestoreSelection(state.Right, rightSelName)
}

func (state *AppState) GetSelectionName(p *PanelState) (string, bool, bool, bool) {
	row, _ := p.Table.GetSelection()
	if row < 1 {
		return "", false, false, false
	}
	if row == 1 && p.HasParent {
		return "..", false, true, true
	}
	offset := 1
	if p.HasParent {
		offset = 2
	}
	idx := row - offset
	if idx < 0 || idx >= len(p.Items) {
		return "", false, false, false
	}
	return p.Items[idx].Name(), p.Items[idx].IsDir(), false, false
}

func (state *AppState) RestoreSelection(p *PanelState, targetName string) {
	if targetName == "" {
		return
	}
	if targetName == ".." && p.HasParent {
		p.Table.Select(1, 0)
		return
	}

	offset := 1
	if p.HasParent {
		offset = 2
	}

	for i, item := range p.Items {
		if item.Name() == targetName {
			p.Table.Select(i+offset, 0)
			return
		}
	}
	p.Table.Select(1, 0)
}

func (state *AppState) ShowActionPrompt(promptLabel, defaultValue string, onConfirm func(string)) {
	state.PromptLine.SetLabel("[yellow]" + promptLabel + " ")
	state.PromptLine.SetText(defaultValue)
	state.PromptLine.SetLabelColor(tcell.ColorYellow)
	state.PromptLine.SetFieldTextColor(tcell.ColorWhite)
	state.PromptLine.SetFieldBackgroundColor(tcell.ColorBlack)
	
	state.PromptLine.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape {
			// Abort prompt
			state.PromptLine.SetLabel("")
			state.PromptLine.SetText("")
			state.PromptLine.SetInputCapture(nil)
			state.App.SetFocus(state.ActivePanel.Table)
			return nil
		}
		if event.Key() == tcell.KeyEnter {
			val := state.PromptLine.GetText()
			// Clear prompt
			state.PromptLine.SetLabel("")
			state.PromptLine.SetText("")
			state.PromptLine.SetInputCapture(nil)
			state.App.SetFocus(state.ActivePanel.Table)
			
			if strings.TrimSpace(val) != "" {
				onConfirm(val)
			}
			return nil
		}
		return event
	})
	
	state.App.SetFocus(state.PromptLine)
}

func (state *AppState) ShowActionConfirm(promptLabel string, onConfirm func()) {
	state.PromptLine.SetLabel("[red]" + promptLabel + " (y/N): ")
	state.PromptLine.SetText("")
	state.PromptLine.SetLabelColor(tcell.ColorRed)
	state.PromptLine.SetFieldTextColor(tcell.ColorWhite)
	state.PromptLine.SetFieldBackgroundColor(tcell.ColorBlack)
	
	state.PromptLine.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		key := event.Key()
		r := event.Rune()
		
		if key == tcell.KeyEscape || r == 'n' || r == 'N' {
			// Abort prompt
			state.PromptLine.SetLabel("")
			state.PromptLine.SetText("")
			state.PromptLine.SetInputCapture(nil)
			state.App.SetFocus(state.ActivePanel.Table)
			return nil
		}
		
		if r == 'y' || r == 'Y' || key == tcell.KeyEnter {
			// Confirm prompt
			state.PromptLine.SetLabel("")
			state.PromptLine.SetText("")
			state.PromptLine.SetInputCapture(nil)
			state.App.SetFocus(state.ActivePanel.Table)
			onConfirm()
			return nil
		}
		
		return event
	})

	state.App.SetFocus(state.PromptLine)
}

// Error helper
func (state *AppState) showModalError(message string) {
	modal := tview.NewModal().
		SetText("Error:\n" + message).
		AddButtons([]string{"OK"}).
		SetDoneFunc(func(buttonIndex int, buttonLabel string) {
			state.Pages.RemovePage("modal")
			state.App.SetFocus(state.ActivePanel.Table)
		})
	modal.SetBackgroundColor(tcell.ColorDarkRed)

	state.Pages.AddPage("modal", modal, true, true)
	state.App.SetFocus(modal)
}

// F2 Rename operation
func (state *AppState) OnRename() {
	name, fullName, _, isParent := state.GetSelectedItem()
	if fullName == "" || isParent {
		return
	}

	state.ShowActionPrompt("Rename to:", name, func(newName string) {
		dest := filepath.Join(state.ActivePanel.Path, newName)
		if err := os.Rename(fullName, dest); err != nil {
			state.showModalError(err.Error())
		} else {
			state.Refresh()
			state.RestoreSelection(state.ActivePanel, newName)
		}
	})
}

// F3 View operation
func (state *AppState) OnView() {
	_, fullName, isDir, isParent := state.GetSelectedItem()
	if fullName == "" || isDir || isParent {
		return
	}

	data, err := os.ReadFile(fullName)
	if err != nil {
		state.showModalError(err.Error())
		return
	}

	textView := tview.NewTextView().
		SetDynamicColors(false).
		SetText(string(data))

	textView.SetBorder(true).
		SetTitle(" Viewer: [ " + fullName + " ] ").
		SetBorderColor(tcell.ColorAqua)

	// Close on Esc, F3, or F10
	textView.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEscape || event.Key() == tcell.KeyF3 || event.Key() == tcell.KeyF10 {
			state.Pages.RemovePage("viewer")
			state.App.SetFocus(state.ActivePanel.Table)
			return nil
		}
		return event
	})

	state.Pages.AddPage("viewer", textView, true, true)
	state.App.SetFocus(textView)
}

// F4 Edit operation
func (state *AppState) OnEdit() {
	_, fullName, isDir, isParent := state.GetSelectedItem()
	if isDir || isParent {
		return
	}

	var data []byte
	if fullName != "" {
		var err error
		data, err = os.ReadFile(fullName)
		if err != nil && !os.IsNotExist(err) {
			state.showModalError(err.Error())
			return
		}
	}

	// Create file name if F4 pressed in an empty directory
	if fullName == "" {
		state.ShowActionPrompt("Create file name:", "", func(fileName string) {
			newPath := filepath.Join(state.ActivePanel.Path, fileName)
			state.openTextEditor(newPath, []byte{})
		})
	} else {
		state.openTextEditor(fullName, data)
	}
}

func (state *AppState) openTextEditor(path string, data []byte) {
	editor := tview.NewTextArea()
	editor.SetTextStyle(tcell.StyleDefault.Foreground(tcell.ColorWhite).Background(tcell.ColorBlack))
	editor.SetText(string(data), false)

	updateTitle := func() {
		editor.SetBorder(true).
			SetTitle(" Editor: [ " + path + " ] ").
			SetBorderColor(tcell.ColorAqua)
	}
	updateTitle()

	editor.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		// Save file on F2
		if event.Key() == tcell.KeyF2 {
			err := os.WriteFile(path, []byte(editor.GetText()), 0644)
			if err != nil {
				state.showModalError(err.Error())
			} else {
				state.Refresh()
				state.RestoreSelection(state.ActivePanel, filepath.Base(path))
				// Temporary saved notify
				editor.SetTitle(" Saved! [ " + path + " ] ").SetBorderColor(tcell.ColorGreen)
				go func() {
					time.Sleep(1 * time.Second)
					state.App.QueueUpdateDraw(func() {
						updateTitle()
					})
				}()
			}
			return nil
		}

		// Exit on Esc, F4, or F10
		if event.Key() == tcell.KeyEscape || event.Key() == tcell.KeyF4 || event.Key() == tcell.KeyF10 {
			state.Pages.RemovePage("editor")
			state.App.SetFocus(state.ActivePanel.Table)
			state.Refresh()
			return nil
		}
		return event
	})

	flex := tview.NewFlex().
		AddItem(editor, 0, 1, true)

	state.Pages.AddPage("editor", flex, true, true)
	state.App.SetFocus(editor)
}

// F5 Copy operation
func (state *AppState) OnCopy() {
	name, fullName, _, isParent := state.GetSelectedItem()
	if fullName == "" || isParent {
		return
	}

	defaultDest := filepath.Join(state.GetInactivePanel().Path, name)

	state.ShowActionPrompt("Copy to:", defaultDest, func(dest string) {
		go func() {
			err := copyRecursive(fullName, dest)
			state.App.QueueUpdateDraw(func() {
				if err != nil {
					state.showModalError(err.Error())
				} else {
					state.Refresh()
				}
			})
		}()
	})
}

// F6 Move operation
func (state *AppState) OnMove() {
	name, fullName, _, isParent := state.GetSelectedItem()
	if fullName == "" || isParent {
		return
	}

	defaultDest := filepath.Join(state.GetInactivePanel().Path, name)

	state.ShowActionPrompt("Move to:", defaultDest, func(dest string) {
		go func() {
			err := moveRecursive(fullName, dest)
			state.App.QueueUpdateDraw(func() {
				if err != nil {
					state.showModalError(err.Error())
				} else {
					state.Refresh()
				}
			})
		}()
	})
}

// F7 Mkdir operation
func (state *AppState) OnMkdir() {
	state.ShowActionPrompt("Create Directory:", "", func(dirName string) {
		newPath := filepath.Join(state.ActivePanel.Path, dirName)
		if err := os.MkdirAll(newPath, 0755); err != nil {
			state.showModalError(err.Error())
		} else {
			state.Refresh()
			state.RestoreSelection(state.ActivePanel, dirName)
		}
	})
}

// F8 Delete operation
func (state *AppState) OnDelete() {
	name, fullName, _, isParent := state.GetSelectedItem()
	if fullName == "" || isParent {
		return
	}

	msg := fmt.Sprintf("Delete '%s'?", name)
	state.ShowActionConfirm(msg, func() {
		go func() {
			err := os.RemoveAll(fullName)
			state.App.QueueUpdateDraw(func() {
				if err != nil {
					state.showModalError(err.Error())
				} else {
					state.Refresh()
				}
			})
		}()
	})
}

// Formatting size helper
func formatSize(size int64) string {
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d B", size)
	}
	div, exp := int64(unit), 0
	for n := size / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(size)/float64(div), "KMGT"[exp])
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err = io.Copy(out, in); err != nil {
		return err
	}

	si, err := os.Stat(src)
	if err != nil {
		return err
	}
	return os.Chmod(dst, si.Mode())
}

func copyDir(src, dst string) error {
	si, err := os.Stat(src)
	if err != nil {
		return err
	}

	if err = os.MkdirAll(dst, si.Mode()); err != nil {
		return err
	}

	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		dstPath := filepath.Join(dst, entry.Name())

		if entry.IsDir() {
			if err = copyDir(srcPath, dstPath); err != nil {
				return err
			}
		} else {
			if err = copyFile(srcPath, dstPath); err != nil {
				return err
			}
		}
	}
	return nil
}

func copyRecursive(src, dst string) error {
	stat, err := os.Stat(src)
	if err != nil {
		return err
	}

	// If destination is a directory, append source name to it
	dstStat, err := os.Stat(dst)
	if err == nil && dstStat.IsDir() {
		dst = filepath.Join(dst, filepath.Base(src))
	}

	if stat.IsDir() {
		return copyDir(src, dst)
	}
	return copyFile(src, dst)
}

func moveRecursive(src, dst string) error {
	stat, err := os.Stat(src)
	if err != nil {
		return err
	}

	dstStat, err := os.Stat(dst)
	if err == nil && dstStat.IsDir() {
		dst = filepath.Join(dst, filepath.Base(src))
	}

	err = os.Rename(src, dst)
	if err == nil {
		return nil
	}

	// Fallback to copy and delete if cross-device moves
	if stat.IsDir() {
		err = copyDir(src, dst)
	} else {
		err = copyFile(src, dst)
	}
	if err != nil {
		return err
	}
	return os.RemoveAll(src)
}
