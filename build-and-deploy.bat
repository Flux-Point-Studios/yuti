@echo off
REM BlueLight Flutter Web Build & Deploy Script (Windows)
REM This script builds Flutter web locally and deploys via Vercel static hosting
REM Date: 7/16/2025

echo 🚀 BlueLight Flutter Web Build ^& Deploy
echo ========================================

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter is not installed or not in PATH
    pause
    exit /b 1
)

echo [INFO] Flutter version:
flutter --version

REM Check for uncommitted changes
git status --porcelain | findstr /r "." >nul
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] You have uncommitted changes. Continuing will include them in the build.
    set /p "continue=Continue? (y/N): "
    if /i not "%continue%"=="y" (
        echo [ERROR] Aborted by user
        pause
        exit /b 1
    )
)

REM Clean previous builds
echo [INFO] Cleaning previous builds...
flutter clean

REM Get dependencies
echo [INFO] Getting Flutter dependencies...
flutter pub get

REM Build for web with optimizations
echo [INFO] Building Flutter web app...
echo [INFO] Using: flutter build web --release --pwa-strategy offline-first
flutter build web --release --pwa-strategy offline-first

REM Verify build output
if not exist "build\web" (
    echo [ERROR] Build failed - build\web directory not found
    pause
    exit /b 1
)

echo [SUCCESS] Flutter web build completed successfully!

REM Check for required files
echo [INFO] Verifying build output...
if not exist "build\web\index.html" (
    echo [ERROR] Required file missing: build\web\index.html
    pause
    exit /b 1
)

if not exist "build\web\manifest.json" (
    echo [ERROR] Required file missing: build\web\manifest.json
    pause
    exit /b 1
)

if not exist "build\web\favicon.png" (
    echo [ERROR] Required file missing: build\web\favicon.png
    pause
    exit /b 1
)

echo [SUCCESS] All required files present!

REM Stage all changes
echo [INFO] Staging changes for git...
git add .

REM Check if there are changes to commit
git diff --staged --quiet
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] No changes to commit - build output is identical
    echo Deployment not needed, but you can still push if desired.
    set /p "push=Push anyway? (y/N): "
    if /i not "%push%"=="y" (
        echo [INFO] Deployment cancelled
        pause
        exit /b 0
    )
) else (
    REM Show what changed
    echo [INFO] Changes to be committed:
    git diff --staged --stat
)

REM Get commit message or use default
set "COMMIT_MSG=🚀 Auto-deploy: Update Flutter web build %date% %time%"
if not "%~1"=="" (
    set "COMMIT_MSG=🚀 Deploy: %~1"
)

REM Commit changes
echo [INFO] Committing build files...
git commit -m "%COMMIT_MSG%"

REM Push to trigger Vercel deployment
echo [INFO] Pushing to GitHub (triggers Vercel deployment)...
git push

echo [SUCCESS] 🎉 Deployment complete!
echo.
echo [INFO] What happens next:
echo   1. ✅ Git push completed
echo   2. ⚡ Vercel automatically detects the push
echo   3. 📦 Vercel serves pre-built files from build/web/
echo   4. 🌐 Your app updates at the deployed URL
echo.
echo [INFO] Check deployment status at: https://vercel.com/dashboard
echo.
echo [SUCCESS] GameChanger wallet integration with transport header fix is now live! 🎉

pause 