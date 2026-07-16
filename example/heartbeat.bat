@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "log=%~dp0last-seen.txt"
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format o"`) do set "started=%%I"

:loop
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format o"`) do set "now=%%I"
>> "%log%" echo %started% - %now%
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 3" >nul
goto loop
