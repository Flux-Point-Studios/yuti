@echo off
echo ========================================
echo Building Flutter Web with Environment Variables
echo ========================================

REM Read environment variables from .env.local if they exist
REM For now, we'll use the values directly

echo Building with environment variables...

flutter build web --release --pwa-strategy offline-first ^
  --dart-define=T_BACKEND_API_KEY=9d94b0e91c8bdebe6ee1fa7ada205bed276931895ed94aa05c7e245b99e599ee ^
  --dart-define=T_BACKEND_URL=https://api.fluxpointstudios.com ^
  --dart-define=IS_MAINNET=true

if %ERRORLEVEL% neq 0 (
    echo Build failed with error code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo Build completed successfully!
echo Build output is in build/web directory
echo ======================================== 