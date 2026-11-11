@echo off
title Cooper Lab Variant Explorer
echo.
echo  ╔═══════════════════════════════════════════╗
echo  ║        Cooper Lab Variant Explorer        ║
echo  ╚═══════════════════════════════════════════╝
echo.

:: Always work from the folder this script is in (also from a shortcut)
cd /d "%~dp0"
for %%f in (Dockerfile docker-compose.yml renv.lock) do (
    if not exist "%%f" (
        echo  ERROR: %%f was not found in %CD%
        echo  start.bat must be in the app folder, next to Dockerfile and renv.lock.
        echo.
        pause
        exit /b 1
    )
)

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

echo  Data folder: %CD%
echo  Starting app (first run, or after an update, may take a few minutes)...
echo.

:: Remove any running copy first. Only one copy can use port 3838, and a copy
:: started from another folder would otherwise keep answering with its data.
docker rm -f variant-explorer >nul 2>&1

:: --build rebuilds the image when the app files changed; it is quick otherwise
docker compose up -d --build
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Docker could not build or start the app. See the messages above.
    pause
    exit /b 1
)

:: Wait up to ~5 minutes for the app to respond
echo  Waiting for app to start...
set /a tries=0
:wait
timeout /t 2 /nobreak >nul
curl -s http://localhost:3838 >nul 2>&1
if %errorlevel% equ 0 goto ready
set /a tries+=1
if %tries% lss 150 goto wait

echo.
echo  ERROR: The app did not start within 5 minutes. Last lines of the log:
echo  ------------------------------------------------------------------
docker logs --tail 25 variant-explorer
echo  ------------------------------------------------------------------
echo  Send the lines above to whoever maintains the app.
docker compose down
pause
exit /b 1

:ready
echo  Opening browser...
start "" "http://localhost:3838"
echo.
echo  App is running at http://localhost:3838
echo  Data folder: %CD%
echo  Press any key in this window to stop the app.
echo  (If you close the window instead, run stop.bat to stop it.)
echo.
pause

docker compose down
