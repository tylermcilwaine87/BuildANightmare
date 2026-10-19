@echo off
cd /d "%~dp0"
title Rojo - Build A Nightmare
echo Installing the Rojo plugin into Roblox Studio...
rojo.exe plugin install
echo.
echo ==========================================================
echo  Rojo is running. LEAVE THIS WINDOW OPEN while you work.
echo  In Roblox Studio: Plugins tab  ^>  Rojo  ^>  Connect
echo  To stop: close this window.
echo ==========================================================
echo.
rojo.exe serve
pause
