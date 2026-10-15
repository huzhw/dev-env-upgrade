@echo off
rem mvninfo - print effective Maven local repository (dev-env-upgrade skill)
rem Shim: forwards to check-versions.ps1 -Repo
setlocal
set "SCRIPT=F:\idea-workspase-skills\dev-env-upgrade\scripts\check-versions.ps1"
if not exist "%SCRIPT%" (
  echo [mvninfo] ERROR: script not found: %SCRIPT%
  echo [mvninfo] The dev-env-upgrade skill repo may have moved.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Repo %*
exit /b %ERRORLEVEL%
