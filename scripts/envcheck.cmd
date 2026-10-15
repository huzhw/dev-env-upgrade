@echo off
rem envcheck - dev environment version check (dev-env-upgrade skill)
rem Shim: forwards to check-versions.ps1 (full check)
setlocal
set "SCRIPT=F:\idea-workspase-skills\dev-env-upgrade\scripts\check-versions.ps1"
if not exist "%SCRIPT%" (
  echo [envcheck] ERROR: script not found: %SCRIPT%
  echo [envcheck] The dev-env-upgrade skill repo may have moved.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
