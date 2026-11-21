@echo off
rem Build the headless Einstein harness against Albert's emulation core.
rem   ALBERT_CORE  the einstein repository's emulator
rem                (default: %USERPROFILE%\OneDrive\Documents\GitHub\einstein\emulator)
rem Output: build\einstein\speedrun_check.exe
setlocal EnableDelayedExpansion
cd /d "%~dp0\..\.."

if "%ALBERT_CORE%"=="" set "ALBERT_CORE=%USERPROFILE%\OneDrive\Documents\GitHub\einstein\emulator"
set "CORELIB=!ALBERT_CORE!\build\src\core\ein_core.lib"
if not exist "!CORELIB!" set "CORELIB=!ALBERT_CORE!\build-core\src\core\ein_core.lib"
if not exist "!CORELIB!" (
    echo Albert core library not found under !ALBERT_CORE!
    exit /b 1
)

rem (run from MSYS2's make, ProgramFiles(x86) may not be set)
set "PF86=%ProgramFiles(x86)%"
if "!PF86!"=="" set "PF86=C:\Program Files (x86)"
set "VSWHERE=!PF86!\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if "!VSPATH!"=="" (
    echo Visual Studio C++ toolset not found
    exit /b 1
)
call "!VSPATH!\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

if not exist build\einstein mkdir build\einstein
cl /nologo /std:c++20 /EHsc /O2 /MT /W3 /I "!ALBERT_CORE!\src\core" ^
   /Fe:build\einstein\speedrun_check.exe /Fo:build\einstein\ ^
   tests\einstein\speedrun_check.cpp "!CORELIB!"
exit /b %errorlevel%
