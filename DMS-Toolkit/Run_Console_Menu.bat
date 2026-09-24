@echo off
chcp 65001 >nul
title DMS Deployment Console Menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run_Console_Menu.ps1"
pause
