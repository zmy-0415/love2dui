@echo off
setlocal
cd /d "%~dp0"

set "LOVE_DIR=C:\workspace\love2dsrc\build"
set "APP_NAME=NotepadPP"
set "OUT_DIR=dist"

echo ==============================================
echo  Package Notepad++ clone into standalone exe
echo ==============================================

echo [1/4] Clean output directory...
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%"

echo [2/4] Create .love archive (zip of sources)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path @('main.lua','conf.lua','lumi','npp') -DestinationPath '%OUT_DIR%\%APP_NAME%.zip' -Force"
if errorlevel 1 goto :error
ren "%OUT_DIR%\%APP_NAME%.zip" "%APP_NAME%.love"

echo [3/4] Merge love.exe + .love into a single exe...
copy /b "%LOVE_DIR%\love.exe" + "%OUT_DIR%\%APP_NAME%.love" "%OUT_DIR%\%APP_NAME%.exe" >nul
if errorlevel 1 goto :error

echo [4/4] Copy runtime DLLs and license...
copy "%LOVE_DIR%\libliblove.dll" "%OUT_DIR%" >nul
copy "%LOVE_DIR%\license.txt"    "%OUT_DIR%" >nul
set "MINGW_BIN=C:\msys64\ucrt64\bin"
for %%D in (SDL3.dll lua51.dll libfreetype-6.dll libharfbuzz-0.dll libglib-2.0-0.dll libgraphite2.dll libmodplug-1.dll libogg-0.dll libopenal-1.dll libpng16-16.dll libtheora-1.dll libvorbis-0.dll libvorbisfile-3.dll libgcc_s_seh-1.dll libwinpthread-1.dll libstdc++-6.dll zlib1.dll libbrotlidec.dll libbrotlicommon.dll libbz2-1.dll libiconv-2.dll) do (
  copy "%MINGW_BIN%\%%D" "%OUT_DIR%" >nul
)

echo.
echo Done! Output folder: %OUT_DIR%
dir /b "%OUT_DIR%"
echo.
echo Run "%OUT_DIR%\%APP_NAME%.exe" (no Love2D install required).
pause
exit /b 0

:error
echo.
echo [ERROR] Packaging failed.
pause
exit /b 1
