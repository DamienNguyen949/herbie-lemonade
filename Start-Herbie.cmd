@echo off
rem Double-click to start Herbie. Lemonade Server must be running too.
rem Different Lemonade port? Example: Start-Herbie.cmd -Lemonade http://localhost:8000
title Herbie
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve-herbie.ps1" %*
if errorlevel 1 (
  echo.
  echo   Herbie stopped with a problem. Read the message above, then press any key to close.
  pause >nul
)
