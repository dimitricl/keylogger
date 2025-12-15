@echo off
title Arret du keylogger...

cd /d "%~dp0"

echo ============================================
echo    Arret du keylogger v2...
echo ============================================
echo.

REM Tuer le processus pythonw.exe de ton venv uniquement
for /f "tokens=2 delims=," %%P in ('tasklist /FI "IMAGENAME eq pythonw.exe" /FO CSV /NH') do (
    REM Verifier le chemin du process
    wmic process where "ProcessId=%%P" get CommandLine /value | find /I "keylogger_client_v2.py" >nul 2>&1
    if not errorlevel 1 (
        echo [*] Arret du processus keylogger (PID %%P)
        taskkill /PID %%P /F >nul 2>&1
    )
)

echo.
echo [✓] Demande d'arret envoyee. 
echo Si aucun processus n'etait en cours, rien n'a ete tue.
echo.
pause
exit /b 0

