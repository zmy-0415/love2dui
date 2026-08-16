@echo off
cd /d "%~dp0"
type nul > verify.flag
"C:\Program Files\LOVE\lovec.exe" .
set TEST_EXIT=%errorlevel%
del verify.flag >nul 2>nul
echo.
if "%TEST_EXIT%"=="0" (
    echo [PASS] All tests passed.
) else (
    echo [FAIL] Some tests failed. Exit code: %TEST_EXIT%
)
pause
