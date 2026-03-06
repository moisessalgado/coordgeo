# Scripts de Deploy e Verificação

## 1. `start_dev.sh` / `start_dev.ps1` — Iniciar Servidores de Desenvolvimento

Inicia backend (Gunicorn) + frontend (Vite) em ambiente de desenvolvimento com hot reload.

> Recomendação principal: execute os comandos em um terminal WSL (não PowerShell).

### No WSL (Bash)

```bash
cd /home/moises/dev/coordgeo
./scripts/start_dev.sh
```

### No PowerShell (Windows)

```powershell
# Fallback (quando precisar iniciar via PowerShell)
wsl --cd /home/moises/dev/coordgeo bash -lc './scripts/start_dev.sh'

# Ou via PowerShell:
.\scripts\start_dev.ps1
```

### O que acontece

- ✅ Limpa processos antigos (Gunicorn, Vite, Node.js)
- ✅ Verifica pré-requisitos (Python venv, Node.js)
- ✅ Inicia backend (Gunicorn em http://127.0.0.1:8000)
- ✅ Inicia frontend (Vite em http://localhost:5173)
- ✅ Exibe URLs de acesso
- ✅ Mantém servidores rodando até Ctrl+C

**Tempo de startup:** ~5-8 segundos

### URLs de Acesso

| Serviço | URL |
|---------|-----|
| Frontend | http://localhost:5173 |
| Backend | http://127.0.0.1:8000 |
| API | http://127.0.0.1:8000/api/v1 |

### Parar Servidores

Pressione **Ctrl+C** no terminal onde o script está rodando. Cleanup automático mata Gunicorn e Vite.

---

## 2. `verify_local.sh` — Validação Completa (CI/CD)

Script de validação total: testes, linting, build, smoke tests. Ideal para CI/CD.

### No WSL (Bash)

```bash
cd /home/moises/dev/coordgeo
./scripts/verify_local.sh
```

### No PowerShell

```powershell
wsl --cd /home/moises/dev/coordgeo bash -lc './scripts/verify_local.sh'
```

### O que valida

**Backend:**
- Migrate: aplica pendentes
- Check: valida settings
- Tests: roda suite (keepdb=true)
- HTTP: valida endpoints GET/POST

**Frontend:**
- Lint: ESLint check
- Build: Vite production build
- Preview: sobe preview server e valida HTTP 200

**Cleanup:** mata Gunicorn e preview automaticamente

### Logs

- `/tmp/coordgeo_gunicorn.log`
- `/tmp/coordgeo_preview.log`

### Tempo de Execução

~80-120 segundos (testes + build)

---

## 3. Fluxo de Desenvolvimento Recomendado

### Primeira Execução (Setup)

```bash
./scripts/verify_local.sh  # Valida integridade completa
```

### Desenvolvimento Iterativo

```bash
./scripts/start_dev.sh     # Inicia servidores com hot reload
# ...trabalhe nos arquivos...
# Frontend recarrega automaticamente
# Backend: interrompa e rode ./scripts/start_dev.sh novamente se alterar models/migrations
```

### Antes de Commit

```bash
./scripts/verify_local.sh  # Confirma tudo passa (testes, lint, build)
```

---

## Variáveis de Ambiente

### Backend (`.env` em `coordgeo-backend/`)

```env
DEBUG=True
DATABASE_URL=postgresql://django:password@localhost:5432/geodjango
SECRET_KEY=your-secret-key-here
```

### Frontend (`.env` em `coordgeo-frontend/`)

```env
VITE_API_URL=http://127.0.0.1:8000
```

---

## Troubleshooting

### Porta Já em Uso

```bash
# Mata Gunicorn
pkill -f "gunicorn config.wsgi"

# Mata Vite
pkill -f "vite"

# Tenta novamente
./scripts/start_dev.sh
```

### Node.js Version Error (Frontend)

Vite 7 requer Node 20.19+ ou 22.12+

```bash
# Via nvm (recomendado)
nvm use 20.19.4
npm run dev

# Via WSL no PowerShell
wsl --cd /home/moises/dev/coordgeo/coordgeo-frontend bash -lc 'source "$HOME/.nvm/nvm.sh" && nvm use 20.19.4 && npm run dev'
```

### Backend Crasha com Erro de Banco

```bash
# Verifique PostgreSQL
pg_isready -h localhost -p 5432

# Aplique migrações
cd coordgeo-backend
python manage.py migrate
```

### Vite não inicia no WSL

Garanta Node.js correto:

```bash
nvm list
nvm use 20.19.4
npm run dev
```
