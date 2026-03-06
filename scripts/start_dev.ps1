# start_dev.ps1 - Development Server Startup (Windows PowerShell)
# Usage: .\scripts\start_dev.ps1

param(
    [switch]$Kill,
    [switch]$Help
)

if ($Help) {
    Write-Host "start_dev.ps1 - Iniciar servidores de desenvolvimento"
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\scripts\start_dev.ps1              # Inicia backend + frontend"
    Write-Host "  .\scripts\start_dev.ps1 -Kill        # Para servidores"
    Write-Host "  .\scripts\start_dev.ps1 -Help        # Mostra ajuda"
    exit 0
}

function Write-Status {
    param([string]$Message, [string]$Status = "Info")
    switch ($Status) {
        "Success" { Write-Host "✓ $Message" -ForegroundColor Green }
        "Error"   { Write-Host "✗ $Message" -ForegroundColor Red }
        "Warning" { Write-Host "⚠ $Message" -ForegroundColor Yellow }
        default   { Write-Host "● $Message" -ForegroundColor Cyan }
    }
}

$ROOT_DIR = Split-Path -Parent $PSScriptRoot
$BACKEND_DIR = Join-Path $ROOT_DIR "coordgeo-backend"
$FRONTEND_DIR = Join-Path $ROOT_DIR "coordgeo-frontend"
$BACKEND_PORT = 8000
$FRONTEND_PORT = 5173

Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  INICIALIZAR SERVIDOR DE DESENVOLVIMENTO      ║" -ForegroundColor Green
Write-Host "║  coordgeo (Full-Stack)                        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# Kill old processes if needed
function CleanupServers {
    Write-Status "Limpando processos antigos..."
    
    # Kill Gunicorn
    Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*gunicorn*" } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Kill Node/Vite
    Get-Process | Where-Object { $_.ProcessName -like "*node*" } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 2
    Write-Status "Limpeza concluída" "Success"
}

if ($Kill) {
    CleanupServers
    Write-Status "Servidores parados" "Success"
    exit 0
}

# Cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host ""
    Write-Status "Parando servidores..."
    Get-Process | Where-Object { $_.ProcessName -like "*python*" -and $_.CommandLine -like "*gunicorn*" } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Process | Where-Object { $_.ProcessName -like "*node*" } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

# Kill old processes first
CleanupServers

# Check prerequisites
Write-Status "[1/4] Verificando pré-requisitos..."

if (-not (Test-Path "$BACKEND_DIR\venv\Scripts\python.exe")) {
    Write-Status "Python venv não encontrado em $BACKEND_DIR\venv" "Error"
    exit 1
}
Write-Status "Python venv encontrado" "Success"

$NODE_VERSION = Invoke-Expression "wsl bash -ic 'node --version'" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Status "Node.js não encontrado ou erro ao verificar" "Error"
    exit 1
}
Write-Status "Node.js $NODE_VERSION" "Success"

# Backend startup
Write-Status "[2/4] Iniciando backend (Gunicorn en porta $BACKEND_PORT)..."

# Check if port is free
$portInUse = Get-NetTCPConnection -LocalPort $BACKEND_PORT -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
if ($portInUse) {
    Write-Status "Porta $BACKEND_PORT já está em uso" "Error"
    exit 1
}

# Start Gunicorn via WSL
$backendCmd = "cd $BACKEND_DIR && ./venv/bin/python -m gunicorn config.wsgi:application --bind 127.0.0.1:$BACKEND_PORT --workers 2 --timeout 120 --access-logfile - --error-logfile -"
$null = wsl bash -c $backendCmd 2>$null &

Start-Sleep -Seconds 2
Write-Status "Gunicorn iniciado" "Success"

# Frontend startup
Write-Status "[3/4] Iniciando frontend (Vite em porta $FRONTEND_PORT)..."

# Check if port is free
$portInUse = Get-NetTCPConnection -LocalPort $FRONTEND_PORT -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
if ($portInUse) {
    Write-Status "Porta $FRONTEND_PORT já está em uso" "Error"
    exit 1
}

# Start Vite via WSL
$viteCmd = "cd $FRONTEND_DIR && nvm use 20.19.4 > /dev/null 2>&1 && npm run dev"
$null = wsl bash -ic $viteCmd 2>$null &

Start-Sleep -Seconds 5
Write-Status "Vite iniciado" "Success"

# Display URLs
Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  URLs DE ACESSO                               ║" -ForegroundColor Green
Write-Host "╠════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║ Frontend (Vite):" -ForegroundColor Green
Write-Host "║   http://localhost:$FRONTEND_PORT" -ForegroundColor Green
Write-Host "║" -ForegroundColor Green
Write-Host "║ Backend (Gunicorn):" -ForegroundColor Green
Write-Host "║   http://127.0.0.1:$BACKEND_PORT" -ForegroundColor Green
Write-Host "║" -ForegroundColor Green
Write-Host "║ API:" -ForegroundColor Green
Write-Host "║   http://127.0.0.1:$BACKEND_PORT/api/v1/" -ForegroundColor Green
Write-Host "╠════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║ Pressione Ctrl+C para parar os servidores" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Status "[4/4] Servidores prontos" "Success"
Write-Host ""

# Keep script running
$null = Read-Host "Pressione Enter para parar (ou Ctrl+C)"
