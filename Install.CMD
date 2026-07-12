@echo off
color 0a
setlocal
title Overseer Installer

echo Checking Dependencies
echo =====================
echo NodeJS
call npm -v >nul 2>&1
if %errorlevel% neq 0 (
    echo [x] NodeJS is missing and is required for this application
    goto ERROR
)
echo PowerShell
powershell -NoLogo -Command "exit 0" >nul 2>&1
if %errorlevel% neq 0 (
    echo [x] PowerShell is missing
    goto ERROR
)
echo.
echo Downloading Node_Modules
echo ========================
call npm ci
if %errorlevel% neq 0 (
    echo [x] Failed to download Node modules
    goto ERROR
)

echo Downloading Powsershell Modules
echo ===============================
ECHO NuGet
powershell -Command "Install-PackageProvider -Name NuGet -Force -Scope CurrentUser" >nul 2>&1
powershell -Command "Register-PackageSource -Name NuGet -ProviderName NuGet -Location https://www.nuget.org/api/v2 -Trusted -Force" >nul 2>&1
ECHO SQLite
powershell -Command "Install-Package System.Data.SQLite.Core -Scope CurrentUser" >nul 2>&1
if %errorlevel% neq 0 (
    echo [x] Failed to download sqlite module for Powershell
    goto ERROR
)
powershell -Command "Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted" >nul 2>&1

echo Building Local Enviorment
echo =========================
call npm run build 2>&1
if %errorlevel% neq 0 (
    echo [x] Failed to download Node modules
    goto ERROR
)

goto DONE

:ERROR
color F4
echo Setup has failed! Check the error message and try again.
goto END

:DONE
echo.
echo ===================================
echo Installation completed successfully.

:END
timeout /t 5 >nul
endlocal
