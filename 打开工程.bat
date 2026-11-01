@echo off
rem ===============================================================
rem  Open the Manyu project in DevEco Studio (double-click to run)
rem ===============================================================
set DEVECO=D:\DevEco Studio\bin\devecostudio64.exe
set PROJ=%~dp0app

if not exist "%DEVECO%" (
  echo [ERROR] DevEco Studio not found: %DEVECO%
  echo Edit this .bat and change the DEVECO variable if installed elsewhere.
  pause
  exit /b 1
)
if not exist "%PROJ%\build-profile.json5" (
  echo [ERROR] Project folder incomplete: %PROJ%
  pause
  exit /b 1
)

echo Starting DevEco Studio with the Manyu project...
start "" "%DEVECO%" "%PROJ%"
exit /b 0
