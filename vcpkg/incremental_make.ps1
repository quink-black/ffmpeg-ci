# incremental_make.ps1 - Incremental make without full rebuild
# Usage: .\incremental_make.ps1 [-Debug] [-Jobs N]

param(
    [switch]$Debug,     # Build debug version (default: release)
    [int]$Jobs = 0      # Number of parallel jobs (0 = auto)
)

$ErrorActionPreference = "Stop"

$VCPKG_ROOT = "$env:USERPROFILE\work\vcpkg"
$FFMPEG_SOURCE = "$env:USERPROFILE\work\ffmpeg"

# Determine build directory
$buildType = if ($Debug) { "x64-windows-dbg" } else { "x64-windows-rel" }
$buildDir = Join-Path $VCPKG_ROOT "buildtrees\ffmpeg\$buildType"

if (-not (Test-Path $buildDir)) {
    Write-Host "Build directory not found: $buildDir" -ForegroundColor Red
    Write-Host "Please run a full build first using rebuild_ffmpeg.ps1" -ForegroundColor Yellow
    exit 1
}

# Determine job count
if ($Jobs -eq 0) {
    $Jobs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FFmpeg Incremental Build" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build Type: $buildType"
Write-Host "Build Dir:  $buildDir"
Write-Host "Jobs:       $Jobs"
Write-Host ""

# Run make in MSYS2 environment
$msys2Path = "C:\msys64\usr\bin\bash.exe"
if (-not (Test-Path $msys2Path)) {
    # Try alternative path
    $msys2Path = "$env:USERPROFILE\msys64\usr\bin\bash.exe"
}

if (Test-Path $msys2Path) {
    Write-Host "Running incremental make via MSYS2..." -ForegroundColor Green
    $buildDirUnix = $buildDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
    & $msys2Path -lc "cd '$buildDirUnix' && make -j$Jobs"
} else {
    Write-Host "MSYS2 not found. Trying native make..." -ForegroundColor Yellow
    Push-Location $buildDir
    try {
        & make -j$Jobs
    } finally {
        Pop-Location
    }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Make FAILED!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Incremental build completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: To install the updated libraries, run:" -ForegroundColor Yellow
Write-Host "  .\rebuild_ffmpeg.ps1" -ForegroundColor White
