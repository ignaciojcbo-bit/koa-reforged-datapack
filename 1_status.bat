@echo off
rem KOA Reforged data pack - read-only: what patch_0.pak is installed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0koar_data.ps1" status
pause
