# mcps.ps1 - Lightweight TUI Clone of Midnight Commander for PowerShell
# Author: Gemini CLI Agent
# Date: June 2026

# Force UTF-8 encoding for Output and console to support Unicode Box drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Store initial console settings to restore on exit
$oldTreatControlC = [Console]::TreatControlCAsInput
$oldCursorVisible = [Console]::CursorVisible
$oldForegroundColor = [Console]::ForegroundColor
$oldBackgroundColor = [Console]::BackgroundColor

# Define box drawing characters dynamically to prevent file encoding/ANSI issues on different host systems
$global:ChHoriz  = [string][char]0x2500  # ─
$global:ChVert   = [string][char]0x2502  # │
$global:ChTopL   = [string][char]0x250c  # ┌
$global:ChTopR   = [string][char]0x2510  # ┐
$global:ChBotL   = [string][char]0x2514  # └
$global:ChBotR   = [string][char]0x2518  # ┘

# Helper to truncate strings from left (great for paths)
function Truncate-String {
    param(
        [string]$str,
        [int]$maxLength
    )
    if ($str.Length -le $maxLength) {
        return $str
    }
    if ($maxLength -le 3) {
        return $str.Substring(0, $maxLength)
    }
    return "..." + $str.Substring($str.Length - ($maxLength - 3))
}

# Helper to write colored text at specific console coordinates
function Write-Text {
    param(
        [int]$col,
        [int]$row,
        [string]$text,
        $fg = $null,
        $bg = $null
    )
    # Clamp values to avoid cursor position errors on resize
    $maxW = [Console]::WindowWidth
    $maxH = [Console]::WindowHeight
    if ($col -lt 0) { $col = 0 }
    if ($row -lt 0) { $row = 0 }
    if ($col -ge $maxW) { $col = $maxW - 1 }
    if ($row -ge $maxH) { $row = $maxH - 1 }
    
    [Console]::SetCursorPosition($col, $row)
    
    $oldFg = [Console]::ForegroundColor
    $oldBg = [Console]::BackgroundColor
    
    if ($fg -ne $null) { [Console]::ForegroundColor = $fg }
    if ($bg -ne $null) { [Console]::BackgroundColor = $bg }
    
    # Clip text if it exceeds line bounds
    if ($col + $text.Length -gt $maxW) {
        $text = $text.Substring(0, $maxW - $col)
    }
    
    [Console]::Write($text)
    
    if ($fg -ne $null) { [Console]::ForegroundColor = $oldFg }
    if ($bg -ne $null) { [Console]::BackgroundColor = $oldBg }
}

# Load panel directory items
function Load-PanelDirectory {
    param(
        $panelState,
        [string]$newPath
    )
    # Resolve absolute path
    $resolvedPath = (Resolve-Path -LiteralPath $newPath -ErrorAction SilentlyContinue).Path
    if (-not $resolvedPath) {
        $resolvedPath = $newPath
    }
    
    # Check if directory exists
    if (-not [System.IO.Directory]::Exists($resolvedPath)) {
        return "Directory does not exist: $resolvedPath"
    }

    try {
        $items = @()
        
        # Add parent directory ".." if not root
        $dirInfo = [System.IO.DirectoryInfo]::new($resolvedPath)
        if ($dirInfo.Parent) {
            $items += [PSCustomObject]@{
                Name          = ".."
                FullName      = $dirInfo.Parent.FullName
                Attributes    = [System.IO.FileAttributes]::Directory
                Length        = $null
                LastWriteTime = $null
                IsParent      = $true
                PSIsContainer = $true
            }
        }
        
        $realItems = Get-ChildItem -LiteralPath $resolvedPath -ErrorAction SilentlyContinue
        # Sort directories first, then files
        $dirs = $realItems | Where-Object { $_.PSIsContainer } | Sort-Object Name
        $files = $realItems | Where-Object { -not $_.PSIsContainer } | Sort-Object Name
        
        $items += $dirs
        $items += $files
        
        $panelState.Path = $resolvedPath
        $panelState.Items = $items
        # Keep selected index in bounds
        if ($panelState.SelectedIndex -ge $items.Count) {
            $panelState.SelectedIndex = [Math]::Max(0, $items.Count - 1)
        }
        return $null # Success
    } catch {
        return $_.Exception.Message
    }
}

# Get Active Panel State
function Get-ActivePanelState {
    if ($global:state.ActivePanel -eq 'Left') {
        return $global:state.Left
    } else {
        return $global:state.Right
    }
}

# Get Inactive Panel State
function Get-InactivePanelState {
    if ($global:state.ActivePanel -eq 'Left') {
        return $global:state.Right
    } else {
        return $global:state.Left
    }
}

# Format panel items for the double column grid layout
function Format-PanelLine {
    param(
        $item,
        [int]$width
    )
    if ($item.IsParent) {
        $name = ".."
        $sizeStr = "<UP>"
        $dateStr = ""
    } else {
        $name = $item.Name
        if ($item.PSIsContainer) {
            $name = $name + "/"
            $sizeStr = "<DIR>"
        } else {
            $size = $item.Length
            if ($size -ge 1GB) {
                $sizeStr = "$([Math]::Round($size / 1GB, 1))G"
            } elseif ($size -ge 1MB) {
                $sizeStr = "$([Math]::Round($size / 1MB, 1))M"
            } elseif ($size -ge 1KB) {
                $sizeStr = "$([Math]::Round($size / 1KB, 1))K"
            } else {
                $sizeStr = "$size"
            }
        }
        $dateStr = $item.LastWriteTime.ToString("yyyy-MM-dd")
    }

    if ($width -ge 40) {
        $innerWidth = $width - 2
        $nameWidth = $innerWidth - 19
        $sizeWidth = 7
        $dateWidth = 10
        
        $pName = if ($name.Length -gt $nameWidth) { 
            $name.Substring(0, $nameWidth - 3) + "..." 
        } else { 
            $name.PadRight($nameWidth) 
        }
        $pSize = $sizeStr.PadLeft($sizeWidth)
        $pDate = $dateStr.PadLeft($dateWidth)
        
        return "$pName$($global:ChVert)$pSize$($global:ChVert)$pDate"
    } else {
        $innerWidth = $width - 2
        if ($name.Length -gt $innerWidth) {
            return $name.Substring(0, $innerWidth - 3) + "..."
        } else {
            return $name.PadRight($innerWidth)
        }
    }
}

# Draw Top Header Line
function Draw-Header {
    $W = [Console]::WindowWidth
    $title = " MCPS (v1.0.0) - PowerShell Midnight Commander"
    $title = $title.PadRight($W)
    Write-Text 0 0 $title 'White' 'DarkBlue'
}

# Draw bottom status line inside each panel box
function Draw-PanelStatus {
    param(
        $panelState,
        [int]$startCol,
        [int]$width,
        [bool]$isActive
    )
    $H = [Console]::WindowHeight
    $row = $H - 4
    
    # Draw vertical borders for status row
    Write-Text $startCol $row "$($global:ChVert)" 'Cyan' 'Black'
    Write-Text ($startCol + $width - 1) $row "$($global:ChVert)" 'Cyan' 'Black'
    
    $innerWidth = $width - 2
    $statusText = ""
    
    if ($panelState.Items.Count -gt 0) {
        $item = $panelState.Items[$panelState.SelectedIndex]
        if ($item.IsParent) {
            $statusText = "Up to parent directory"
        } else {
            if ($item.PSIsContainer) {
                $statusText = "Directory: $($item.Name)"
            } else {
                $size = $item.Length
                $sizeStr = if ($size -ge 1GB) {
                    "$([Math]::Round($size / 1GB, 2)) GB"
                } elseif ($size -ge 1MB) {
                    "$([Math]::Round($size / 1MB, 2)) MB"
                } elseif ($size -ge 1KB) {
                    "$([Math]::Round($size / 1KB, 2)) KB"
                } else {
                    "$size Bytes"
                }
                $statusText = "$($item.Name) ($sizeStr)"
            }
        }
    } else {
        $statusText = "Empty Directory"
    }
    
    if ($statusText.Length -gt $innerWidth) {
        $statusText = $statusText.Substring(0, $innerWidth)
    } else {
        $statusText = $statusText.PadRight($innerWidth)
    }
    
    $fg = if ($isActive) { 'Yellow' } else { 'Gray' }
    Write-Text ($startCol + 1) $row $statusText $fg 'DarkBlue'
}

# Render a single panel (Left or Right)
function Draw-Panel {
    param(
        $panelState,
        [int]$startCol,
        [int]$width,
        [bool]$isActive
    )
    $H = [Console]::WindowHeight
    $visibleHeight = $H - 6 # Row 2 to Row H-5 inclusive (H-6 items)
    
    # Adjust scrolling offsets so selected item is always visible
    if ($panelState.SelectedIndex -lt $panelState.TopIndex) {
        $panelState.TopIndex = $panelState.SelectedIndex
    }
    if ($panelState.SelectedIndex -ge ($panelState.TopIndex + $visibleHeight)) {
        $panelState.TopIndex = $panelState.SelectedIndex - $visibleHeight + 1
    }
    if ($panelState.TopIndex -lt 0) { $panelState.TopIndex = 0 }
    
    # 1. Top Border with Path Title
    $title = " [ $(Truncate-String $panelState.Path ($width - 8)) ] "
    $borderLen = $width - $title.Length - 2
    $leftBar = "$($global:ChTopL)$($global:ChHoriz)"
    $rightBar = ($global:ChHoriz * ($borderLen - 1)) + "$($global:ChTopR)"
    $topLine = $leftBar + $title + $rightBar
    if ($topLine.Length -gt $width) {
        $topLine = $topLine.Substring(0, $width)
    }
    
    Write-Text $startCol 1 $topLine 'Cyan' 'Black'
    
    # 2. Draw Items
    for ($i = 0; $i -lt $visibleHeight; $i++) {
        $itemIdx = $panelState.TopIndex + $i
        $row = 2 + $i
        
        # Left Border
        Write-Text $startCol $row "$($global:ChVert)" 'Cyan' 'Black'
        # Right Border
        Write-Text ($startCol + $width - 1) $row "$($global:ChVert)" 'Cyan' 'Black'
        
        if ($itemIdx -lt $panelState.Items.Count) {
            $item = $panelState.Items[$itemIdx]
            $lineText = Format-PanelLine $item $width
            
            $fg = 'White'
            $bg = 'DarkBlue'
            
            if ($item.PSIsContainer -or $item.IsParent) {
                $fg = 'Cyan'
            }
            
            if ($itemIdx -eq $panelState.SelectedIndex) {
                if ($isActive) {
                    $fg = 'Black'
                    $bg = 'Cyan'
                } else {
                    $fg = 'White'
                    $bg = 'DarkGray'
                }
            }
            
            Write-Text ($startCol + 1) $row $lineText $fg $bg
        } else {
            # Empty line
            $emptyLine = " " * ($width - 2)
            Write-Text ($startCol + 1) $row $emptyLine 'White' 'DarkBlue'
        }
    }
    
    # 3. Draw bottom stats
    Draw-PanelStatus $panelState $startCol $width $isActive
    
    # 4. Bottom Border
    $bottomLine = "$($global:ChBotL)" + ($global:ChHoriz * ($width - 2)) + "$($global:ChBotR)"
    Write-Text $startCol ($H - 3) $bottomLine 'Cyan' 'Black'
}

# Draw Bottom F-Key Action Bar
function Draw-Footer {
    $W = [Console]::WindowWidth
    $H = [Console]::WindowHeight
    
    # Clear and fill row with cyan
    Write-Text 0 ($H - 1) (" " * $W) 'Black' 'Cyan'
    
    $items = @(
        @{ Key = "2"; Label = "Rename" },
        @{ Key = "3"; Label = "View" },
        @{ Key = "4"; Label = "Edit" },
        @{ Key = "5"; Label = "Copy" },
        @{ Key = "6"; Label = "Move" },
        @{ Key = "7"; Label = "MkDir" },
        @{ Key = "8"; Label = "Delete" },
        @{ Key = "10"; Label = "Quit" }
    )
    
    $col = 1
    foreach ($item in $items) {
        Write-Text $col ($H - 1) $item.Key 'White' 'Black'
        $col += $item.Key.Length
        Write-Text $col ($H - 1) "$($item.Label) " 'Black' 'Cyan'
        $col += $item.Label.Length + 1
    }
}

# Show a short message/status line at Row H-2
function Show-Message {
    param(
        [string]$message,
        [string]$fg = 'Red',
        [string]$bg = 'Black'
    )
    $W = [Console]::WindowWidth
    $row = [Console]::WindowHeight - 2
    $paddedMsg = $message.PadRight($W).Substring(0, $W)
    Write-Text 0 $row $paddedMsg $fg $bg
}

# Draw prompt input dialog inside Row H-2 without cluttering screen
function Get-TUIInput {
    param(
        [string]$prompt,
        [int]$col,
        [int]$row,
        [string]$defaultValue = ""
    )
    $W = [Console]::WindowWidth
    $clearStr = " " * ($W - $col)
    Write-Text $col $row $clearStr 'White' 'Black'
    
    Write-Text $col $row $prompt 'Yellow' 'Black'
    $promptLen = $prompt.Length
    $inputCol = $col + $promptLen
    
    [Console]::CursorVisible = $true
    
    $buffer = $defaultValue
    # Limit default val to screen space
    if ($inputCol + $buffer.Length -ge $W) {
        $buffer = $buffer.Substring(0, $W - $inputCol - 1)
    }
    Write-Text $inputCol $row $buffer 'White' 'Black'
    [Console]::SetCursorPosition($inputCol + $buffer.Length, $row)
    
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [System.ConsoleKey]::Enter) {
            break
        }
        if ($key.Key -eq [System.ConsoleKey]::Escape) {
            $buffer = $null
            break
        }
        if ($key.Key -eq [System.ConsoleKey]::Backspace) {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                [Console]::SetCursorPosition($inputCol + $buffer.Length, $row)
                [Console]::Write(" ")
                [Console]::SetCursorPosition($inputCol + $buffer.Length, $row)
            }
        } else {
            if ($key.KeyChar -ne [char]0 -and $inputCol + $buffer.Length -lt $W - 1) {
                $buffer += $key.KeyChar
                [Console]::Write($key.KeyChar)
            }
        }
    }
    [Console]::CursorVisible = $false
    return $buffer
}

# Dialog confirmation at Row H-2
function Get-TUIConfirm {
    param(
        [string]$prompt,
        [int]$col,
        [int]$row
    )
    $W = [Console]::WindowWidth
    $clearStr = " " * ($W - $col)
    Write-Text $col $row $clearStr 'White' 'Black'
    Write-Text $col $row "$prompt (y/N) " 'Yellow' 'Black'
    
    $key = [Console]::ReadKey($true)
    if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
        return $true
    }
    return $false
}

# Enter-ViewerMode (F3)
function Enter-ViewerMode {
    param([string]$filePath)
    if (-not [System.IO.File]::Exists($filePath)) {
        Show-Message "File does not exist: $filePath"
        [Console]::ReadKey($true) | Out-Null
        return
    }
    
    try {
        $lines = Get-Content -LiteralPath $filePath -ErrorAction Stop
    } catch {
        Show-Message "Error reading file: $_"
        [Console]::ReadKey($true) | Out-Null
        return
    }
    
    $topLine = 0
    $W = [Console]::WindowWidth
    $H = [Console]::WindowHeight
    
    while ($true) {
        [Console]::Clear()
        
        # Draw Viewer header
        $title = " Viewer: [ $filePath ] "
        $titlePad = [Math]::Max(0, [int](($W - $title.Length)/2))
        Write-Text 0 0 ($global:ChHoriz * $W) 'Gray' 'Black'
        Write-Text $titlePad 0 $title 'White' 'DarkBlue'
        
        # Draw help footer
        $footer = " Esc/F10: Exit $($global:ChVert) Up/Down: Scroll $($global:ChVert) PageUp/PageDown: Scroll Page "
        Write-Text 0 ($H - 1) ($footer.PadRight($W)) 'Black' 'Cyan'
        
        $visibleHeight = $H - 2
        for ($i = 0; $i -lt $visibleHeight; $i++) {
            $lineIdx = $topLine + $i
            $row = $i + 1
            if ($lineIdx -lt $lines.Count) {
                $lineText = $lines[$lineIdx]
                if ($lineText.Length -gt $W) {
                    $lineText = $lineText.Substring(0, $W)
                } else {
                    $lineText = $lineText.PadRight($W)
                }
                Write-Text 0 $row $lineText 'White' 'Black'
            } else {
                Write-Text 0 $row (" " * $W) 'White' 'Black'
            }
        }
        
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [System.ConsoleKey]::Escape -or $key.Key -eq [System.ConsoleKey]::F10 -or $key.Key -eq [System.ConsoleKey]::F3) {
            break
        }
        if ($key.Key -eq [System.ConsoleKey]::UpArrow) {
            if ($topLine -gt 0) { $topLine-- }
        }
        if ($key.Key -eq [System.ConsoleKey]::DownArrow) {
            if ($topLine + $visibleHeight -lt $lines.Count) { $topLine++ }
        }
        if ($key.Key -eq [System.ConsoleKey]::PageUp) {
            $topLine = [Math]::Max(0, $topLine - $visibleHeight)
        }
        if ($key.Key -eq [System.ConsoleKey]::PageDown) {
            $topLine = [Math]::Min([Math]::Max(0, $lines.Count - $visibleHeight), $topLine + $visibleHeight)
        }
    }
    [Console]::Clear()
}

# Enter-EditorMode (F4)
function Enter-EditorMode {
    param([string]$filePath)
    
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $modified = $false
    
    if ([System.IO.File]::Exists($filePath)) {
        try {
            $content = Get-Content -LiteralPath $filePath
            if ($content) {
                foreach ($line in $content) {
                    $lines.Add($line)
                }
            } else {
                $lines.Add("")
            }
        } catch {
            Show-Message "Error reading file: $_"
            [Console]::ReadKey($true) | Out-Null
            return
        }
    } else {
        $lines.Add("")
    }
    
    $curLine = 0
    $curCol = 0
    $topLine = 0
    $leftCol = 0
    
    $W = [Console]::WindowWidth
    $H = [Console]::WindowHeight
    
    while ($true) {
        [Console]::Clear()
        
        $modIndicator = if ($modified) { "*" } else { "" }
        $title = " Editor: [ $filePath ]$modIndicator "
        $titlePad = [Math]::Max(0, [int](($W - $title.Length)/2))
        Write-Text 0 0 ($global:ChHoriz * $W) 'Gray' 'Black'
        Write-Text $titlePad 0 $title 'White' 'DarkBlue'
        
        $status = " Line: $($curLine + 1)/$($lines.Count) $($global:ChVert) Col: $($curCol + 1) "
        Write-Text ($W - $status.Length - 2) 0 $status 'Yellow' 'Black'
        
        $footer = " F2: Save $($global:ChVert) Esc/F10: Quit $($global:ChVert) Arrows: Move $($global:ChVert) Enter: New Line $($global:ChVert) Backspace: Del "
        Write-Text 0 ($H - 1) ($footer.PadRight($W)) 'Black' 'Cyan'
        
        $visibleHeight = $H - 2
        
        # Vertical Scrolling adjustments
        if ($curLine -lt $topLine) {
            $topLine = $curLine
        }
        if ($curLine -ge ($topLine + $visibleHeight)) {
            $topLine = $curLine - $visibleHeight + 1
        }
        
        # Horizontal Scrolling adjustments
        if ($curCol -lt $leftCol) {
            $leftCol = $curCol
        }
        if ($curCol -ge ($leftCol + $W - 1)) {
            $leftCol = $curCol - $W + 2
        }
        
        for ($i = 0; $i -lt $visibleHeight; $i++) {
            $lineIdx = $topLine + $i
            $row = $i + 1
            if ($lineIdx -lt $lines.Count) {
                $lineText = $lines[$lineIdx]
                if ($lineText.Length -gt $leftCol) {
                    $slice = $lineText.Substring($leftCol)
                } else {
                    $slice = ""
                }
                
                if ($slice.Length -gt $W) {
                    $slice = $slice.Substring(0, $W)
                } else {
                    $slice = $slice.PadRight($W)
                }
                Write-Text 0 $row $slice 'White' 'Black'
            } else {
                Write-Text 0 $row (" " * $W) 'White' 'Black'
            }
        }
        
        # Render blinking cursor at character position
        [Console]::CursorVisible = $true
        $screenX = $curCol - $leftCol
        $screenY = ($curLine - $topLine) + 1
        [Console]::SetCursorPosition($screenX, $screenY)
        
        $key = [Console]::ReadKey($true)
        [Console]::CursorVisible = $false
        
        # Escape or F10 to exit
        if ($key.Key -eq [System.ConsoleKey]::Escape -or $key.Key -eq [System.ConsoleKey]::F10 -or $key.Key -eq [System.ConsoleKey]::F4) {
            if ($modified) {
                $saveChoice = Get-TUIConfirm "File modified. Save changes?" 0 ($H - 2)
                if ($saveChoice) {
                    try {
                        [System.IO.File]::WriteAllLines($filePath, $lines)
                    } catch {
                        Show-Message "Error saving: $_"
                        [Console]::ReadKey($true) | Out-Null
                    }
                }
            }
            break
        }
        
        # Save file (F2)
        if ($key.Key -eq [System.ConsoleKey]::F2) {
            try {
                [System.IO.File]::WriteAllLines($filePath, $lines)
                $modified = $false
                Show-Message "File saved successfully!" 'Green' 'Black'
                Start-Sleep -Milliseconds 600
            } catch {
                Show-Message "Error saving: $_"
                [Console]::ReadKey($true) | Out-Null
            }
            continue
        }
        
        # Cursor Navigations
        if ($key.Key -eq [System.ConsoleKey]::UpArrow) {
            if ($curLine -gt 0) {
                $curLine--
                if ($curCol -gt $lines[$curLine].Length) {
                    $curCol = $lines[$curLine].Length
                }
            }
        }
        elseif ($key.Key -eq [System.ConsoleKey]::DownArrow) {
            if ($curLine -lt ($lines.Count - 1)) {
                $curLine++
                if ($curCol -gt $lines[$curLine].Length) {
                    $curCol = $lines[$curLine].Length
                }
            }
        }
        elseif ($key.Key -eq [System.ConsoleKey]::LeftArrow) {
            if ($curCol -gt 0) {
                $curCol--
            } elseif ($curLine -gt 0) {
                $curLine--
                $curCol = $lines[$curLine].Length
            }
        }
        elseif ($key.Key -eq [System.ConsoleKey]::RightArrow) {
            if ($curCol -lt $lines[$curLine].Length) {
                $curCol++
            } elseif ($curLine -lt ($lines.Count - 1)) {
                $curLine++
                $curCol = 0
            }
        }
        elseif ($key.Key -eq [System.ConsoleKey]::Home) {
            $curCol = 0
        }
        elseif ($key.Key -eq [System.ConsoleKey]::End) {
            $curCol = $lines[$curLine].Length
        }
        
        # Text insertions & deletions
        elseif ($key.Key -eq [System.ConsoleKey]::Enter) {
            $currentLineText = $lines[$curLine]
            $leftSide = $currentLineText.Substring(0, $curCol)
            $rightSide = $currentLineText.Substring($curCol)
            
            $lines[$curLine] = $leftSide
            $lines.Insert($curLine + 1, $rightSide)
            $curLine++
            $curCol = 0
            $modified = $true
        }
        elseif ($key.Key -eq [System.ConsoleKey]::Backspace) {
            if ($curCol -gt 0) {
                $currentLineText = $lines[$curLine]
                $lines[$curLine] = $currentLineText.Remove($curCol - 1, 1)
                $curCol--
                $modified = $true
            } elseif ($curLine -gt 0) {
                $prevLineText = $lines[$curLine - 1]
                $curCol = $prevLineText.Length
                $lines[$curLine - 1] = $prevLineText + $lines[$curLine]
                $lines.RemoveAt($curLine)
                $curLine--
                $modified = $true
            }
        }
        elseif ($key.Key -eq [System.ConsoleKey]::Delete) {
            if ($curCol -lt $lines[$curLine].Length) {
                $lines[$curLine] = $lines[$curLine].Remove($curCol, 1)
                $modified = $true
            } elseif ($curLine -lt ($lines.Count - 1)) {
                $lines[$curLine] = $lines[$curLine] + $lines[$curLine + 1]
                $lines.RemoveAt($curLine + 1)
                $modified = $true
            }
        }
        else {
            if ($key.KeyChar -ne [char]0) {
                $lines[$curLine] = $lines[$curLine].Insert($curCol, $key.KeyChar)
                $curCol++
                $modified = $true
            }
        }
    }
    [Console]::Clear()
}

# Enter directory or open file (Enter)
function Enter-SelectedItem {
    $active = Get-ActivePanelState
    if ($active.Items.Count -eq 0) { return }
    $item = $active.Items[$active.SelectedIndex]
    
    if ($item.PSIsContainer -or $item.IsParent) {
        $err = Load-PanelDirectory $active $item.FullName
        if ($err) {
            Show-Message "Error entering directory: $err"
            [Console]::ReadKey($true) | Out-Null
        }
    } else {
        try {
            # Open file with default shell handler (non-blocking)
            Start-Process -FilePath $item.FullName -ErrorAction Stop
        } catch {
            Show-Message "Could not open file: $_"
            [Console]::ReadKey($true) | Out-Null
        }
    }
}

# Refresh both panel lists
function Refresh-Panels {
    $leftSelName = if ($global:state.Left.Items.Count -gt 0 -and $global:state.Left.SelectedIndex -lt $global:state.Left.Items.Count) {
        $global:state.Left.Items[$global:state.Left.SelectedIndex].Name
    } else { $null }
    
    $rightSelName = if ($global:state.Right.Items.Count -gt 0 -and $global:state.Right.SelectedIndex -lt $global:state.Right.Items.Count) {
        $global:state.Right.Items[$global:state.Right.SelectedIndex].Name
    } else { $null }

    Load-PanelDirectory $global:state.Left $global:state.Left.Path | Out-Null
    Load-PanelDirectory $global:state.Right $global:state.Right.Path | Out-Null
    
    # Keep cursor on the same items
    if ($leftSelName) {
        $idx = -1
        for ($i = 0; $i -lt $global:state.Left.Items.Count; $i++) {
            if ($global:state.Left.Items[$i].Name -eq $leftSelName) {
                $idx = $i
                break
            }
        }
        if ($idx -ne -1) { $global:state.Left.SelectedIndex = $idx }
    }
    if ($rightSelName) {
        $idx = -1
        for ($i = 0; $i -lt $global:state.Right.Items.Count; $i++) {
            if ($global:state.Right.Items[$i].Name -eq $rightSelName) {
                $idx = $i
                break
            }
        }
        if ($idx -ne -1) { $global:state.Right.SelectedIndex = $idx }
    }
}

# Navigate cursor up/down
function Navigate-Selection {
    param([int]$delta)
    $active = Get-ActivePanelState
    if ($active.Items.Count -eq 0) { return }
    
    $newIndex = $active.SelectedIndex + $delta
    if ($newIndex -ge 0 -and $newIndex -lt $active.Items.Count) {
        $active.SelectedIndex = $newIndex
    }
}

# Navigate page-wise Up/Down
function Page-Selection {
    param([int]$multiplier)
    $active = Get-ActivePanelState
    if ($active.Items.Count -eq 0) { return }
    
    $H = [Console]::WindowHeight
    $visibleHeight = $H - 6
    $delta = $visibleHeight * $multiplier
    
    $newIndex = $active.SelectedIndex + $delta
    if ($newIndex -lt 0) {
        $newIndex = 0
    }
    if ($newIndex -ge $active.Items.Count) {
        $newIndex = $active.Items.Count - 1
    }
    $active.SelectedIndex = $newIndex
}

# Render Entire Screen
function Draw-Screen {
    $W = [Console]::WindowWidth
    $leftWidth = [int]($W / 2)
    $rightWidth = $W - $leftWidth
    
    Draw-Header
    Draw-Panel $global:state.Left 0 $leftWidth ($global:state.ActivePanel -eq 'Left')
    Draw-Panel $global:state.Right $leftWidth $rightWidth ($global:state.ActivePanel -eq 'Right')
    Draw-Footer
}

# Handle keyboard actions
function Handle-KeyPress {
    $keyInfo = [Console]::ReadKey($true)
    $H = [Console]::WindowHeight
    
    switch ($keyInfo.Key) {
        'F10' {
            $global:state.Running = $false
        }
        'Tab' {
            if ($global:state.ActivePanel -eq 'Left') {
                $global:state.ActivePanel = 'Right'
            } else {
                $global:state.ActivePanel = 'Left'
            }
        }
        'UpArrow' {
            Navigate-Selection -1
        }
        'DownArrow' {
            Navigate-Selection 1
        }
        'PageUp' {
            Page-Selection -1
        }
        'PageDown' {
            Page-Selection 1
        }
        'Enter' {
            Enter-SelectedItem
        }
        'F2' {
            $active = Get-ActivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.IsParent) {
                    $newName = Get-TUIInput "Rename to: " 0 ($H - 2) $item.Name
                    if ($newName -and $newName -ne $item.Name) {
                        try {
                            Show-Message "Renaming..." 'Yellow' 'Black'
                            Rename-Item -LiteralPath $item.FullName -NewName $newName -ErrorAction Stop
                            
                            # Reload the panel directory
                            Load-PanelDirectory $active $active.Path | Out-Null
                            
                            # Keep selection on the renamed item
                            $idx = -1
                            for ($i = 0; $i -lt $active.Items.Count; $i++) {
                                if ($active.Items[$i].Name -eq $newName) {
                                    $idx = $i
                                    break
                                }
                            }
                            if ($idx -ne -1) {
                                $active.SelectedIndex = $idx
                            }
                            
                            # Also refresh inactive panel if it's viewing the same path
                            $inactive = Get-InactivePanelState
                            if ($inactive.Path -eq $active.Path) {
                                Load-PanelDirectory $inactive $inactive.Path | Out-Null
                            }
                            
                            Show-Message "Rename complete!" 'Green' 'Black'
                        } catch {
                            Show-Message "Rename error: $_"
                            [Console]::ReadKey($true) | Out-Null
                        }
                    } else {
                        Show-Message "" # Clear the action line on cancellation or no change
                    }
                }
            }
        }
        'F3' {
            $active = Get-ActivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.PSIsContainer -and -not $item.IsParent) {
                    Enter-ViewerMode $item.FullName
                }
            }
        }
        'F4' {
            $active = Get-ActivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.PSIsContainer -and -not $item.IsParent) {
                    Enter-EditorMode $item.FullName
                    Refresh-Panels
                }
            } else {
                $name = Get-TUIInput "Create file name: " 0 ($H - 2)
                if ($name) {
                    $newPath = Join-Path $active.Path $name
                    Enter-EditorMode $newPath
                    Refresh-Panels
                } else {
                    Show-Message "" # Clear the action line on cancellation
                }
            }
        }
        'F5' {
            $active = Get-ActivePanelState
            $inactive = Get-InactivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.IsParent) {
                    $defaultDest = Join-Path $inactive.Path $item.Name
                    $dest = Get-TUIInput "Copy to: " 0 ($H - 2) $defaultDest
                    if ($dest) {
                        try {
                            Show-Message "Copying..." 'Yellow' 'Black'
                            Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force -ErrorAction Stop
                            Refresh-Panels
                            Show-Message "Copy complete!" 'Green' 'Black'
                        } catch {
                            Show-Message "Copy error: $_"
                            [Console]::ReadKey($true) | Out-Null
                        }
                    } else {
                        Show-Message "" # Clear the action line on cancellation
                    }
                }
            }
        }
        'F6' {
            $active = Get-ActivePanelState
            $inactive = Get-InactivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.IsParent) {
                    $defaultDest = Join-Path $inactive.Path $item.Name
                    $dest = Get-TUIInput "Move to: " 0 ($H - 2) $defaultDest
                    if ($dest) {
                        try {
                            Show-Message "Moving..." 'Yellow' 'Black'
                            Move-Item -LiteralPath $item.FullName -Destination $dest -Force -ErrorAction Stop
                            Refresh-Panels
                            Show-Message "Move complete!" 'Green' 'Black'
                        } catch {
                            Show-Message "Move error: $_"
                            [Console]::ReadKey($true) | Out-Null
                        }
                    } else {
                        Show-Message "" # Clear the action line on cancellation
                    }
                }
            }
        }
        'F7' {
            $active = Get-ActivePanelState
            $name = Get-TUIInput "Create directory: " 0 ($H - 2)
            if ($name) {
                $newPath = Join-Path $active.Path $name
                try {
                    New-Item -ItemType Directory -Path $newPath -ErrorAction Stop | Out-Null
                    Refresh-Panels
                    Show-Message "Directory created!" 'Green' 'Black'
                } catch {
                    Show-Message "MkDir error: $_"
                    [Console]::ReadKey($true) | Out-Null
                }
            } else {
                Show-Message "" # Clear the action line on cancellation
            }
        }
        'F8' {
            $active = Get-ActivePanelState
            if ($active.Items.Count -gt 0) {
                $item = $active.Items[$active.SelectedIndex]
                if (-not $item.IsParent) {
                    $confirm = Get-TUIConfirm "Are you sure you want to delete '$($item.Name)'?" 0 ($H - 2)
                    if ($confirm) {
                        try {
                            Show-Message "Deleting..." 'Yellow' 'Black'
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                            Refresh-Panels
                            Show-Message "Deletion complete!" 'Green' 'Black'
                        } catch {
                            Show-Message "Delete error: $_"
                            [Console]::ReadKey($true) | Out-Null
                        }
                    } else {
                        Show-Message "" # Clear the action line on cancellation
                    }
                }
            }
        }
    }
}

# --- Main Application Execution ---

try {
    # Enter exclusive input mode and hide cursor
    [Console]::TreatControlCAsInput = $true
    try {
        [Console]::CursorVisible = $false
    } catch {}
    
    [Console]::Clear()
    
    # Initialize Global Application State
    $currentDir = (Get-Location).Path
    $global:state = [PSCustomObject]@{
        Running     = $true
        ActivePanel = 'Left'
        Left        = [PSCustomObject]@{
            Path          = $currentDir
            Items         = @()
            SelectedIndex = 0
            TopIndex      = 0
        }
        Right       = [PSCustomObject]@{
            Path          = $currentDir
            Items         = @()
            SelectedIndex = 0
            TopIndex      = 0
        }
    }
    
    # Initial load of panels
    Load-PanelDirectory $global:state.Left $global:state.Left.Path | Out-Null
    Load-PanelDirectory $global:state.Right $global:state.Right.Path | Out-Null
    
    $global:W = [Console]::WindowWidth
    $global:H = [Console]::WindowHeight
    
    # Main Application Loop
    while ($global:state.Running) {
        # Dynamically monitor window resize
        if ([Console]::WindowWidth -ne $global:W -or [Console]::WindowHeight -ne $global:H) {
            $global:W = [Console]::WindowWidth
            $global:H = [Console]::WindowHeight
            [Console]::Clear()
        }
        
        # Draw screen and process inputs
        Draw-Screen
        Handle-KeyPress
    }
} finally {
    # Restore console state gracefully
    [Console]::TreatControlCAsInput = $oldTreatControlC
    try {
        [Console]::CursorVisible = $oldCursorVisible
    } catch {}
    [Console]::ForegroundColor = $oldForegroundColor
    [Console]::BackgroundColor = $oldBackgroundColor
    [Console]::Clear()
}
