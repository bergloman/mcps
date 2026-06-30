<#
.SYNOPSIS
    Builds the MCPS Go application.
.PARAMETER Version
    Specifies the version string to inject into the binary. Defaults to git tag or 'dev'.
.EXAMPLE
    .\build.ps1 -Version "v1.0.0"
#>
param(
    [string]$Version = ""
)

# Move to script directory
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
if ($PSScriptRoot) {
    Set-Location $PSScriptRoot
}

# Auto-detect version if not supplied
if ([string]::IsNullOrWhiteSpace($Version)) {
    $gitTag = git describe --tags --always 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitTag) {
        $Version = $gitTag.Trim()
    } else {
        $Version = "dev"
    }
}

Write-Host "Building MCPS ($Version)..." -ForegroundColor Cyan

# Check if Go is installed
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go compiler is not installed or not in system PATH. Please install Go 1.21+."
    exit 1
}

# Ensure bin directory exists at root
$binDir = Join-Path $PSScriptRoot "bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

# Define output names
$outputName = "mcps"
if ($IsWindows -or $env:OS -like "*Windows*") {
    $outputName += ".exe"
}

$outputPath = Join-Path $binDir $outputName

# Run the build inside mcps-go
Push-Location mcps-go
try {
    Write-Host "Running go build..." -ForegroundColor Gray
    go build -ldflags="-s -w -X 'main.Version=$Version'" -o $outputPath main.go
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Build Succeeded! Executable is at: .\bin\$outputName" -ForegroundColor Green
    } else {
        Write-Error "Go build failed."
        exit 1
    }
} finally {
    Pop-Location
}
