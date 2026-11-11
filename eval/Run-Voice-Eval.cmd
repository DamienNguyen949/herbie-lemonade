@echo off
rem Herbie performance eval: laptop specs, typed vs voice accuracy, Whisper accuracy and speed. Lemonade Server must be running.
title Herbie performance eval
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0eval-voice.ps1" %*
echo.
echo   Done. Press any key to close.
pause >nul
