@echo off
rem Run the project's make in MSYS2 (UCRT64) from cmd or PowerShell:
rem   make test        (cmd)
rem   .\make test      (PowerShell)
rem Needs MSYS2 in C:\msys64 (or set MSYS2_ROOT); see CLAUDE.md.
setlocal
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "MSYSTEM=UCRT64"
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "cd \"$0\" && make \"$@\"" "%~dp0." %*
