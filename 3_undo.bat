@echo off
rem KOA Reforged data pack - put the original patch_0.pak back. Close the game first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0koar_data.ps1" undo
pause
