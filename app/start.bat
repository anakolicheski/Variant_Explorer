@echo off
title Cooper Lab Variant Database
echo.
echo  ╔═══════════════════════════════════════════╗
echo  ║        Cooper Lab Variant Database        ║
echo  ╚═══════════════════════════════════════════╝
echo.

:: Check Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo  ERROR: Docker is not running.
    echo  Please start Docker Desktop and try again.
    echo.
    pause
    exit /b 1
)

:: Create the folders that are mounted into the container
if not exist "annotations"    mkdir annotations
if not exist "New_genotypes"  mkdir New_genotypes
if not exist "app_state"      mkdir app_state

:: One-time move of phenotype / CRAM files from the old location
if exist "Phenotypes.xlsx" if not exist "app_state\Phenotypes.xlsx" copy "Phenotypes.xlsx" "app_state\" >nul
if exist "cram_paths.xlsx" if not exist "app_state\cram_paths.xlsx" copy "cram_paths.xlsx" "app_state\" >nul

echo  Starting app (first run, or after an update, may take a few minutes)...
echo.

:: Start the container in background. --build rebuilds the image when the
:: app files changed; it is quick otherwise.
docker compose up -d --build

:: Wait for app to be ready
echo  Waiting for app to start...
:wait
timeout /t 2 /nobreak >nul
curl -s http://localhost:3838 >nul 2>&1
if %errorlevel% neq 0 goto wait

:: Open browser
echo  Opening browser...
start "" "http://localhost:3838"
echo.
echo  App is running at http://localhost:3838
echo  Press any key in this window to stop the app.
echo  (Closing the window instead leaves the app running; run stop.bat to stop it.)
echo.
pause

docker compose down
