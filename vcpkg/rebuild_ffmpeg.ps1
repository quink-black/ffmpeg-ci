# rebuild_ffmpeg.ps1 - Clean rebuild ffmpeg
# Usage: .\rebuild_ffmpeg.ps1 [-Clean]

param(
    [switch]$Clean  # If specified, remove ffmpeg first before rebuild
)

$ErrorActionPreference = "Stop"

$VCPKG_ROOT = "$env:USERPROFILE\work\vcpkg"
$OVERLAY_PORTS = "$env:USERPROFILE\work\ffmpeg-ci\vcpkg"

$vcpkgExe = Join-Path $VCPKG_ROOT "vcpkg.exe"

if ($Clean) {
    Write-Host "Removing existing ffmpeg installation..." -ForegroundColor Yellow
    & $vcpkgExe remove ffmpeg --triplet=x64-windows
    
    Write-Host "Cleaning buildtrees..." -ForegroundColor Yellow
    $buildtrees = Join-Path $VCPKG_ROOT "buildtrees\ffmpeg"
    if (Test-Path $buildtrees) {
        Remove-Item -Recurse -Force $buildtrees
        Write-Host "Buildtrees cleaned." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Rebuilding ffmpeg with all-gpl features..." -ForegroundColor Cyan

& $vcpkgExe install "ffmpeg[all-gpl]" `
    --overlay-ports="$OVERLAY_PORTS" `
    --triplet=x64-windows `
    --recurse

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build FAILED!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Build completed!" -ForegroundColor Green
