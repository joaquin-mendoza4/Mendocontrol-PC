@echo off
title Controlar PC
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
