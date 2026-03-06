# Verificacao Local

Script para validar backend + frontend localmente em uma unica execucao.

## Executar no WSL

```bash
cd /home/moises/dev/coordgeo
./scripts/verify_local.sh
```

## Executar no PowerShell

```powershell
wsl bash -ic 'cd /home/moises/dev/coordgeo; ./scripts/verify_local.sh'
```

## O que ele valida

- Backend: `migrate`, `check`, `run_tests.py` (keepdb)
- Backend: pasta em `coordgeo-backend/`
- Backend runtime: sobe Gunicorn e valida endpoints HTTP basicos
- Frontend: `npm run lint`, `npm run build`
- Frontend runtime: sobe `vite preview` e valida HTTP 200

Logs de runtime:

- `/tmp/coordgeo_gunicorn.log`
- `/tmp/coordgeo_preview.log`
