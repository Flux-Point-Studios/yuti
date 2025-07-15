@echo off
REM Cardevia PWA Deployment Script for Windows
REM This script builds the Flutter app for web and prepares it for PWA deployment

echo 🚀 Starting Cardevia PWA deployment process...

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter is not installed or not in PATH
    pause
    exit /b 1
)

echo [INFO] Flutter version:
flutter --version

REM Clean previous builds
echo [INFO] Cleaning previous builds...
flutter clean

REM Get dependencies
echo [INFO] Getting Flutter dependencies...
flutter pub get

REM Build for web with optimizations
echo [INFO] Building Flutter app for web (PWA)...

REM Build for web with PWA optimizations
echo [INFO] Building with PWA optimizations and offline-first strategy...
flutter build web --release --pwa-strategy offline-first

REM Verify build output
if not exist "build\web" (
    echo [ERROR] Build failed - build\web directory not found
    pause
    exit /b 1
)

echo [SUCCESS] Flutter web build completed successfully!

REM Check for required PWA files
echo [INFO] Verifying PWA files...

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

REM Check for icons
if not exist "build\web\icons" (
    echo [ERROR] Icons directory missing in build output
    pause
    exit /b 1
)

echo [SUCCESS] All required PWA files are present!

REM Display build info
echo [INFO] Build information:
echo   📁 Build directory: %CD%\build\web
echo   📱 PWA Manifest: %CD%\build\web\manifest.json
echo   🖼️  Icons: %CD%\build\web\icons\
echo   📄 Index file: %CD%\build\web\index.html

REM Show deployment options
echo.
echo [INFO] 🚀 Deployment Options:
echo.
echo 1. 🔥 Firebase Hosting:
echo    - Run: firebase deploy
echo    - Make sure firebase.json points to build/web
echo.
echo 2. ⚡ Vercel:
echo    - Run: vercel --prod
echo    - Or use Vercel CLI in build/web directory
echo.
echo 3. 🌐 Netlify:
echo    - Drag and drop build/web folder to Netlify
echo    - Or use Netlify CLI: netlify deploy --prod --dir=build/web
echo.
echo 4. 📦 Other static hosting:
echo    - Upload contents of build/web to your web server
echo    - Ensure HTTPS is enabled
echo.

REM Optional: Auto-deploy if deployment target is specified
if "%1"=="firebase" (
    echo [INFO] Auto-deploying to Firebase...
    where firebase >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        firebase deploy
        echo [SUCCESS] Deployed to Firebase Hosting!
    ) else (
        echo [ERROR] Firebase CLI not found. Install with: npm install -g firebase-tools
    )
) else if "%1"=="vercel" (
    echo [INFO] Auto-deploying to Vercel...
    where vercel >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        cd build\web
        vercel --prod
        cd ..\..
        echo [SUCCESS] Deployed to Vercel!
    ) else (
        echo [ERROR] Vercel CLI not found. Install with: npm install -g vercel
    )
)

echo [SUCCESS] PWA build and preparation completed! 🎉
echo [INFO] Next steps:
echo   1. Deploy to your hosting platform using HTTPS
echo   2. Test PWA installation on mobile devices
echo   3. Run Lighthouse audit to verify PWA compliance
echo   4. Test offline functionality

echo.
echo [INFO] Testing commands:
echo   • Lighthouse audit: lighthouse https://your-domain.com --view
echo   • Local testing: flutter run -d chrome (for development)
echo.

pause 