@echo off
title Cooper Lab Variant Database
echo.
echo  ╔═══════════════════════════════════════════╗
echo  ║   Cooper Lab Variant Database  v1.0.1    ║
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

:: Create placeholder files for volumes if they don't exist
if not exist "col_state_v2.json"           echo {} > col_state_v2.json
if not exist "candidates.csv"              echo > candidates.csv
if not exist "domain_cache.rds"            copy nul domain_cache.rds >nul
if not exist "column_mapping_config.json"  echo {} > column_mapping_config.json
if not exist "annotations"                 mkdir annotations
if not exist "New_genotypes"               mkdir New_genotypes

echo  Starting app (first run may take a moment)...
echo.

:: Start the container in background
docker compose up -d

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
echo  Close this window to stop the app, or run stop.bat
echo.
pause

:: Stop on window close
docker compose down
