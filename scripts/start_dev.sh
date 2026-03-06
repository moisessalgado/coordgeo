#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get root directory (parent of scripts dir)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/coordgeo-backend"
FRONTEND_DIR="$ROOT_DIR/coordgeo-frontend"

# Ports
BACKEND_PORT="8000"
FRONTEND_PORT="5173"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Limpando processos...${NC}"
    
    # Kill Gunicorn processes
    if pgrep -f "gunicorn config.wsgi" > /dev/null 2>&1; then
        echo "Parando Gunicorn..."
        pkill -f "gunicorn config.wsgi" || true
        sleep 1
    fi
    
    # Kill Vite dev server
    if pgrep -f "vite" > /dev/null 2>&1; then
        echo "Parando Vite..."
        pkill -f "vite" || true
        sleep 1
    fi
    
    echo -e "${GREEN}Limpeza concluída${NC}"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Header
clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  INICIALIZAR SERVIDOR DE DESENVOLVIMENTO      ║${NC}"
echo -e "${GREEN}║  coordgeo (Full-Stack)                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/5] Verificando pré-requisitos...${NC}"

# Check Python in backend
if [ ! -f "$BACKEND_DIR/venv/bin/python" ]; then
    echo -e "${RED}✗ Python venv não encontrado em $BACKEND_DIR/venv${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python venv encontrado${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js não instalado${NC}"
    exit 1
fi
CURRENT_NODE=$(node --version)
echo -e "${GREEN}✓ Node.js instalado: $CURRENT_NODE${NC}"

# Kill old processes
echo -e "\n${YELLOW}[2/5] Limpando processos antigos...${NC}"
cleanup 2>/dev/null || true
sleep 1

# Backend startup
echo -e "\n${YELLOW}[3/5] Iniciando backend (Gunicorn)...${NC}"

cd "$BACKEND_DIR"

# Check if port is free
if lsof -i :$BACKEND_PORT > /dev/null 2>&1; then
    echo -e "${RED}✗ Porta $BACKEND_PORT está em uso${NC}"
    exit 1
fi

# Start Gunicorn in background
"$BACKEND_DIR/venv/bin/python" -m gunicorn \
    config.wsgi:application \
    --bind 127.0.0.1:$BACKEND_PORT \
    --workers 2 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    > /tmp/gunicorn.log 2>&1 &

GUNICORN_PID=$!
sleep 2

# Verify Gunicorn started
if ! kill -0 $GUNICORN_PID 2>/dev/null; then
    echo -e "${RED}✗ Falha ao iniciar Gunicorn${NC}"
    cat /tmp/gunicorn.log
    exit 1
fi

echo -e "${GREEN}✓ Gunicorn iniciado (PID: $GUNICORN_PID)${NC}"

# Frontend startup
echo -e "\n${YELLOW}[4/5] Iniciando frontend (Vite)...${NC}"

cd "$FRONTEND_DIR"

# Check if port is free
if lsof -i :$FRONTEND_PORT > /dev/null 2>&1; then
    echo -e "${RED}✗ Porta $FRONTEND_PORT está em uso${NC}"
    cleanup
    exit 1
fi

# Check and use correct Node version with nvm if available
if command -v nvm &> /dev/null || [ -s "$NVM_DIR/nvm.sh" ]; then
    # Source nvm if not already loaded
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    # Switch to v20
    nvm use 20.19.4 > /dev/null 2>&1 || true
fi

# Start Vite dev server in background
npm run dev > /tmp/vite.log 2>&1 &

VITE_PID=$!
sleep 3

# Verify Vite started
if ! kill -0 $VITE_PID 2>/dev/null; then
    echo -e "${RED}✗ Falha ao iniciar Vite${NC}"
    cat /tmp/vite.log
    cleanup
    exit 1
fi

echo -e "${GREEN}✓ Vite iniciado (PID: $VITE_PID)${NC}"

# Display URLs
echo -e "\n${YELLOW}[5/5] Servidores em execução${NC}"
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  URLs DE ACESSO                               ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} Frontend (Vite):"
echo -e "${GREEN}║${NC}   http://localhost:$FRONTEND_PORT"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC} Backend (Gunicorn):"
echo -e "${GREEN}║${NC}   http://127.0.0.1:$BACKEND_PORT"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC} API:"
echo -e "${GREEN}║${NC}   http://127.0.0.1:$BACKEND_PORT/api/v1/"
echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} Pressione Ctrl+C para parar os servidores"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Log file locations
echo -e "Log files:"
echo -e "  Backend:  ${YELLOW}/tmp/gunicorn.log${NC}"
echo -e "  Frontend: ${YELLOW}/tmp/vite.log${NC}"
echo ""

# Keep script running
wait
