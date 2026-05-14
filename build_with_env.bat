@echo off
echo ========================================
echo Building Flutter Web with Environment Variables
echo ========================================

REM Required environment variables (set these in your shell or .env.local before running):
REM   T_BACKEND_API_KEY  - AI backend auth token (rotate via Flux Point Studios backend ops)
REM   T_BACKEND_URL      - AI backend base URL (defaults to api.fluxpointstudios.com)
REM   IS_MAINNET         - true / false

if "%T_BACKEND_API_KEY%"=="" (
    echo ERROR: T_BACKEND_API_KEY is not set. Set it in your shell or .env.local before building.
    exit /b 1
)

if "%T_BACKEND_URL%"=="" set T_BACKEND_URL=https://api.fluxpointstudios.com
if "%IS_MAINNET%"=="" set IS_MAINNET=true

echo Building with environment variables...

flutter build web --release --pwa-strategy offline-first ^
  --dart-define=T_BACKEND_API_KEY=%T_BACKEND_API_KEY% ^
  --dart-define=T_BACKEND_URL=%T_BACKEND_URL% ^
  --dart-define=IS_MAINNET=%IS_MAINNET%

if %ERRORLEVEL% neq 0 (
    echo Build failed with error code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo Build completed successfully!
echo Build output is in build/web directory
echo ========================================
