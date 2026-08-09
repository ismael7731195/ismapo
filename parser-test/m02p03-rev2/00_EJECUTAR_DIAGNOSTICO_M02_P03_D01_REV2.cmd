@echo off
setlocal EnableExtensions
chcp 65001 >nul
title AGROINPACO ERP - M02-P03 D01 REV2 - DIAGNOSTICO SOLO LECTURA
set "SCRIPT=%~dp001_EJECUTAR_DIAGNOSTICO_M02_P03_D01_REV2.ps1"
echo.
echo AGROINPACO ERP - M02-P03 D01 REV2
echo Diagnostico tecnico de solo lectura
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "CODIGO=%ERRORLEVEL%"
echo.
echo CODIGO_FINAL=%CODIGO%
echo.
pause
exit /b %CODIGO%
