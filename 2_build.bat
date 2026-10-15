@echo off
rem KOA Reforged data pack - add our items and stack sizes to data\patch_0.pak.
rem Needs about 5 GB free space while it works. Close the game first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0koar_data.ps1" build
pause
