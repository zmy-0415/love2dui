@echo off
cd /d "%~dp0"
rem LOVE build directory; override with: set LOVE_DIR=... before running
if not defined LOVE_DIR set "LOVE_DIR=C:\workspace\love2dsrc\build"
if not exist "%LOVE_DIR%\lovec.exe" (
    echo [ERROR] lovec.exe not found in "%LOVE_DIR%"
    echo Set LOVE_DIR in test.bat, or define it as an environment variable.
    pause
    exit /b 1
)
type nul > verify.flag
"%LOVE_DIR%\lovec.exe" .
set TEST_EXIT=%errorlevel%
del verify.flag >nul 2>nul
echo.
if "%TEST_EXIT%"=="0" (
    echo [PASS] All tests passed.
) else (
    echo [FAIL] Some tests failed. Exit code: %TEST_EXIT%
)
pause
exit /b %TEST_EXIT%
