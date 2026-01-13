# Android Build Script for Crypto Wallet Pro
# Run this from the frontend directory

# Stop on errors
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Crypto Wallet Pro - Android Build    " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check Flutter
Write-Host "`n[1/6] Checking Flutter installation..." -ForegroundColor Yellow
flutter --version

# Clean previous build
Write-Host "`n[2/6] Cleaning previous build..." -ForegroundColor Yellow
flutter clean

# Get dependencies
Write-Host "`n[3/6] Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# Build options
Write-Host "`n[4/6] Select build type:" -ForegroundColor Yellow
Write-Host "  1. Debug APK (for testing)"
Write-Host "  2. Release APK (signed, for distribution)"
Write-Host "  3. App Bundle (AAB for Play Store)"
$buildChoice = Read-Host "Enter choice (1-3)"

switch ($buildChoice) {
    "1" {
        Write-Host "`n[5/6] Building Debug APK..." -ForegroundColor Yellow
        flutter build apk --debug
        $outputPath = "build/app/outputs/flutter-apk/app-debug.apk"
    }
    "2" {
        # Check for keystore
        if (!(Test-Path "android/key.properties")) {
            Write-Host "`n⚠️  No key.properties found!" -ForegroundColor Red
            Write-Host "For signed release builds, create android/key.properties" -ForegroundColor Yellow
            Write-Host "See android/key.properties.example for template`n" -ForegroundColor Yellow
            
            $continue = Read-Host "Continue with debug signing? (y/n)"
            if ($continue -ne "y") {
                Write-Host "Build cancelled." -ForegroundColor Red
                exit 1
            }
        }
        
        Write-Host "`n[5/6] Building Release APK..." -ForegroundColor Yellow
        flutter build apk --release
        $outputPath = "build/app/outputs/flutter-apk/app-release.apk"
    }
    "3" {
        # Check for keystore
        if (!(Test-Path "android/key.properties")) {
            Write-Host "`n⚠️  No key.properties found!" -ForegroundColor Red
            Write-Host "App Bundles MUST be signed for Play Store submission" -ForegroundColor Yellow
            Write-Host "Create android/key.properties first`n" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "`n[5/6] Building App Bundle (AAB)..." -ForegroundColor Yellow
        flutter build appbundle --release
        $outputPath = "build/app/outputs/bundle/release/app-release.aab"
    }
    default {
        Write-Host "Invalid choice!" -ForegroundColor Red
        exit 1
    }
}

# Check result
Write-Host "`n[6/6] Build complete!" -ForegroundColor Green

if (Test-Path $outputPath) {
    $fileSize = (Get-Item $outputPath).Length / 1MB
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nOutput: $outputPath" -ForegroundColor Cyan
    Write-Host "Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
    
    # Open output folder
    $openFolder = Read-Host "`nOpen output folder? (y/n)"
    if ($openFolder -eq "y") {
        $folder = Split-Path $outputPath
        explorer $folder
    }
} else {
    Write-Host "`n❌ Build failed! Output not found." -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Done!" -ForegroundColor Green
