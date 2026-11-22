@echo off
rem ============================================================
rem  Windows helper: converts all audio files in a folder to .dfpwm
rem  - drag a folder onto this file, or double-click (uses ..\music)
rem  - needs node.js + ffmpeg (ffmpeg.exe next to this file or in PATH)
rem ============================================================
chcp 65001 >nul
setlocal
set "HERE=%~dp0"

if "%~1"=="" (
    set "MUSIC=%HERE%..\music"
) else (
    set "MUSIC=%~1"
)

if not exist "%MUSIC%" (
    echo Folder not found: %MUSIC%
    echo Drag your music folder onto convert.bat, or put your songs in ..\music
    pause
    exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] node.js not found. Install it from https://nodejs.org
    pause
    exit /b 1
)

node "%HERE%convert.js" "%MUSIC%" %2
echo.
pause
