@echo off
cd /d "%~dp0"
rem LOVE build directory; override with: set LOVE_DIR=... before running
if not defined LOVE_DIR set "LOVE_DIR=C:\workspace\love2dsrc\build"
if not exist "%LOVE_DIR%\love.exe" (
    echo [ERROR] love.exe not found in "%LOVE_DIR%"
    echo Set LOVE_DIR in run.bat, or define it as an environment variable.
    pause
    exit /b 1
)
"%LOVE_DIR%\love.exe" . %*
