# Copilot Instructions — coordgeo (Full-Stack Workspace)

> This workspace contains both **coordgeo-backend/** (Django REST + PostGIS) and **coordgeo-frontend/** (React + Vite + TypeScript). Instructions for both are combined here.

---

## 📁 Workspace Structure

```
coordgeo/
├── coordgeo-backend/    # Django/DRF + GeoDjango + PostGIS (multi-tenant API)
├── coordgeo-frontend/   # React 19 + Vite 7 + TypeScript + MapLibre GL
└── .github/    # This file
```

---

## ⚠️ REPOSITORY SEPARATION (CRITICAL)

**Backend development:**
- ALL backend code → **[coordgeo-backend](https://github.com/moisessalgado/coordgeo-backend)** repository
- Models, views, serializers, tests, migrations, settings, docs
- Push backend commits to `github.com/moisessalgado/coordgeo-backend`

**Frontend development:**
- ALL frontend code → **[coordgeo-frontend](https://github.com/moisessalgado/coordgeo-frontend)** repository
- React components, services, state management, styling, tests, configs
- Push frontend commits to `github.com/moisessalgado/coordgeo-frontend`

**Root repository (coordgeo):**
- Deployment & integration scripts only (e.g., `scripts/verify_local.sh`)
- Consolidated Copilot instructions (this file)
- Workspace configuration (`.github/`, `coordgeo.code-workspace`)
- Push integration commits to `github.com/moisessalgado/coordgeo` (orchestration repository)

**Golden Rule:** When developing, use local folders (`coordgeo-backend/`, `coordgeo-frontend/`) but always commit to their respective remote repositories. Root repo stays separate for infrastructure automation.

---

# 🔧 Backend Instructions (Django)

## 1) Escopo
- Repositório backend Django/DRF + GeoDjango + PostGIS (`coordgeo-backend/`).
- Existe frontend separado em `../coordgeo-frontend` (React + Vite).

## 2) Arquitetura atual
- Multi-tenant com `Organization` como boundary.
- Contexto de org vem de `organizations.permissions.IsOrgMember` (não middleware).
- `IsOrgMember` lê `X-Organization-ID`, valida membership e define `request.active_organization`.
- ViewSets org-scoped filtram por org ativa em `get_queryset()` e forçam org em `perform_create()`.

## 3) Contrato com frontend (não quebrar)
- API canônica: `/api/v1/`.
- Compatibilidade legada: `/api/` (mesmas rotas, depreciação futura).
- JWT:
  - `POST /api/v1/token/` (e legado `/api/token/`)
  - `POST /api/v1/token/refresh/` (e legado `/api/token/refresh/`)
- Bootstrap de organizações sem header:
  - `GET /api/v1/user/organizations/` (e legado `/api/user/organizations/`)
- Endpoints org-scoped exigem `Authorization: Bearer <token>` + `X-Organization-ID`.
- Erros esperados: header ausente 400; sem membership 403.
- List endpoints mantêm shape paginado DRF: `count/next/previous/results`.

## 4) Fluxo de desenvolvimento
- Setup: `.env` a partir de `.env.example` + Postgres/PostGIS.
- Comandos principais em `coordgeo-backend/`:
  - `python manage.py migrate`
  - `python manage.py runserver`
  - `python manage.py test -v 2`
  - `python run_tests.py` (`keepdb=True`)

## 5) Padrões de implementação
- Nunca confiar em `organization` no payload do cliente.
- Sempre usar `request.active_organization` para filtro e criação.
- Referências de padrão:
  - `organizations/permissions.py`
  - `accounts/views.py`
  - `projects/views.py`
  - `data/views.py`
  - `permissions/views.py`

## 6) Validação antes de PR
- Backend: `python manage.py test -v 2`.
- Mudanças que impactam integração: validar frontend com `npm run build` e `npm run lint`.

## 7) Referências rápidas
- `config/urls.py`
- `api/urls.py`
- `config/settings.py`
- `api/tests.py`
- `../coordgeo-frontend/docs/FRONTEND_BUILD_PLAN.md`

## Multi-Tenant Testing Requirements

Every org-scoped ViewSet must have these tests:

1. **Isolation test**: User from org_a should NOT see org_b's data
2. **Creation enforcement test**: Cannot create resource with foreign org ID
3. **Permission test**: Member vs Admin access (when applicable)
4. **Queryset filtering test**: Verify only active org data returned
5. **Cascade deletion test**: Org deletion removes all owned data
6. **Missing header test**: Returns 400 when X-Organization-ID absent
7. **Unauthorized org test**: Returns 403 when user not member of org in header

Example test structure:
```python
def test_organization_isolation(self):
    # User from org_a should NOT see org_b's data
    self.client.force_authenticate(user=self.user_a)
    headers = {'HTTP_X_ORGANIZATION_ID': str(self.org_a.id)}
    response = self.client.get('/api/projects/', **headers)
    project_ids = [p['id'] for p in response.data['results']]
    self.assertNotIn(str(self.project_b.id), project_ids)

def test_missing_organization_header(self):
    self.client.force_authenticate(user=self.user_a)
    response = self.client.get('/api/projects/')  # No header
    self.assertEqual(response.status_code, 400)

def test_unauthorized_organization(self):
    self.client.force_authenticate(user=self.user_a)
    headers = {'HTTP_X_ORGANIZATION_ID': str(self.org_b.id)}  # user_a not member
    response = self.client.get('/api/projects/', **headers)
    self.assertEqual(response.status_code, 403)
```

## Database & Setup

**Database**: PostgreSQL 13+ with PostGIS extension (not SQLite).

**Critical requirements:**
- PostGIS extension must be enabled
- All foreign keys to `Organization` must have `db_index=True`
- Use spatial indexes on all geometry fields
- Test database must use PostGIS template

**Connection** (from `config/settings.py`):
- Host: localhost, Port: 5432, Name: geodjango
- Credentials: User `django` / Password stored in settings (dev-only)
- Test DB uses PostGIS template: `template_postgis`

**Required system packages** (from README):
```bash
sudo apt install binutils libproj-dev gdal-bin libgdal-dev libgeos-dev libpq-dev postgresql postgresql-contrib postgis
```

## API Structure

**Router-based DRF** (`api/urls.py`): Single `DefaultRouter` registers all ViewSets → auto-generates URL patterns.

**Registered endpoints**:
- `/api/users/` → UserViewSet
- `/api/organizations/` → OrganizationViewSet
- `/api/memberships/` → MembershipViewSet
- `/api/teams/` → TeamViewSet
- `/api/projects/` → ProjectViewSet
- `/api/layers/` → LayerViewSet
- `/api/datasources/` → DatasourceViewSet
- `/api/permissions/` → PermissionViewSet

All endpoints support list, create, retrieve, update, destroy actions.

## API Response Standards (Required)

**All list endpoints MUST:**
- Be paginated (use DRF's `PageNumberPagination`)
- Support filtering (use `django-filter` or `DjangoFilterBackend`)
- Support ordering (`ordering_fields` in ViewSet)
- Include proper permission classes

**Standard DRF paginated response:**
```json
{
  "count": 42,
  "next": "http://api.example.com/api/projects/?page=2",
  "previous": null,
  "results": [...]
}
```

**Never return unbounded querysets.** This is a performance and security issue.

**Spatial data in responses:**
- Use GeoJSON format for geometry fields
- Consider separate detail endpoint for full geometries
- List endpoints should return simplified or bounding box only

## Running & Testing

### WSL + Virtualenv (critical for AI agents)

- Your development flow is WSL-first. Prefer running commands directly inside a WSL terminal.
- Avoid native PowerShell commands for backend/frontend runtime tasks whenever possible.
- Always run Python commands from `coordgeo-backend/` using the local virtualenv at `./venv`.
- Prefer invoking the interpreter directly (`./venv/bin/python`) instead of relying on `python` from PATH.
- **Canonical backend test command (inside WSL terminal):**
  ```bash
  cd /home/moises/dev/coordgeo/coordgeo-backend
  ./venv/bin/python manage.py test -v 2
  ```
- **Alternative test command (inside WSL terminal):**
  ```bash
  cd /home/moises/dev/coordgeo/coordgeo-backend
  ./venv/bin/python run_tests.py
  ```
- **Development server (inside WSL terminal):**
  ```bash
  cd /home/moises/dev/coordgeo/coordgeo-backend
  ./venv/bin/python manage.py runserver
  ```
- If activation is needed in a terminal session:
  ```bash
  cd /home/moises/dev/coordgeo/coordgeo-backend
  source venv/bin/activate
  ```
  then run `python ...` in the same WSL session.
- If a command must be launched from PowerShell, use this wrapper pattern:
  ```bash
  wsl --cd /home/moises/dev/coordgeo/coordgeo-backend bash -lc "./venv/bin/python manage.py test -v 2"
  ```
- Do not use `wsl -ic` directly (unsupported). Use `wsl bash -ic ...` or `wsl --cd ... bash -lc ...`.

**Production server** (Gunicorn required for PMTiles HTTP Range header support):
```bash
gunicorn config.wsgi:application --bind 127.0.0.1:8000
```

## Common Workflows

1. **Adding a new API feature**: Create ViewSet in app's views.py with multi-tenant filtering using `request.active_organization`, register in api/urls.py.
2. **Adding org-scoped data**: ForeignKey to Organization, filter by `request.active_organization` in get_queryset().
3. **User authentication checks**: Use `self.request.user` in ViewSets; JWT middleware enforces auth.
4. **Spatial data**: Use `GeometryField` in models, include geometry in serializers for GeoJSON output.
5. **Role-based access**: Check `request.active_membership.role` (MEMBER or ADMIN) in permissions classes before modifying org data.

## Git Conventions

**Commit messages**: Always write commit messages in **Portuguese (pt-BR)** whenever possible. Use clear, descriptive messages following conventional commits style:

```
feat: adiciona endpoint para filtrar projetos por região
fix: corrige vazamento de dados entre organizações
docs: atualiza documentação da API de datasources
refactor: reorganiza estrutura de testes de isolamento
test: adiciona testes para permissões de camadas
chore: atualiza dependências do projeto
```

**Branch naming**: Use Portuguese for feature branches: `feature/nome-da-funcionalidade`, `fix/correcao-do-bug`, `docs/atualizacao-readme`.

## Security Checklist (Pre-Merge)

Before merging any PR with org-scoped data:
- [ ] `get_queryset()` filters by `request.active_organization`
- [ ] `perform_create()` uses `request.active_organization` (NEVER from client/request.data)
- [ ] Permission classes include `IsAuthenticated`
- [ ] Multi-tenant isolation tests pass (Org A ≠ Org B)
- [ ] Tests include missing/invalid `X-Organization-ID` header scenarios
- [ ] List endpoints are paginated
- [ ] No unbounded querysets exposed
- [ ] Spatial indexes on all geometry fields
- [ ] No sensitive data (passwords/keys) in code

## SaaS Future-Proofing

The `Organization` model should support future quota enforcement:
- `subscription_plan` - Free/Pro/Enterprise tiers
- `user_limit` - Max users per org
- `storage_limit` - Max data storage
- `datasource_limit` - Max datasources
- `project_limit` - Max projects

When implementing creation endpoints, consider adding quota validation hooks for future scalability.

## Key Backend Files Reference

- **Models**: `accounts/models.py` (User), `organizations/models.py` (Org/Team/Membership), `projects/models.py` (Project/Layer), `data/models.py` (Datasource)
- **API Configuration**: `config/settings.py`, `api/urls.py`
- **Tests**: `accounts/tests/test_api_isolation.py` (multi-tenant pattern example)

---

# ⚛️ Frontend Instructions (React)

## 1) Escopo
- Este repositório é o cliente `coordgeo-frontend/` (React + TypeScript + Vite).
- Existe um backend separado em `../coordgeo-backend` (Django REST + multi-tenant).
- Mantenha mudanças focadas no frontend, exceto quando o contrato de API exigir ajuste coordenado.

## 2) Arquitetura atual
- **Stack runtime**: React 19, React Router, Axios, Zustand, MapLibre GL (`package.json`).
- **Build tooling**: Vite 7 + TypeScript.
- **Styling**: Tailwind v4 via plugin Vite (`@tailwindcss/vite` in `vite.config.ts`).
- **Global CSS**: `src/index.css` with `@import "tailwindcss";`.
- **State Management**: Zustand stores for auth, orgs, map data.

## 3) Contrato com o backend (não quebrar)
- API canônica do backend: `/api/v1/`.
- Compatibilidade legada ainda existe em `/api/`.
- **Auth JWT**:
  - `POST /api/v1/token/` (preferido)
  - `POST /api/v1/token/refresh/` (preferido)
- **Bootstrap de organizações** (sem header de org):
  - `GET /api/v1/user/organizations/` (preferido)
- **Endpoints org-scoped** exigem:
  - `Authorization: Bearer <access_token>`
  - `X-Organization-ID: <uuid>`
- **Semântica esperada de erro**:
  - Header ausente → 400
  - Usuário sem membership na org → 403
- **Listagens**: Seguem paginação DRF: `count`, `next`, `previous`, `results` (`PAGE_SIZE=50`).

## 4) Fluxo de desenvolvimento
- **Node.js requirement**: `20.19+` (ou `22.12+`) para Vite 7.
- **Comandos principais** (na pasta `coordgeo-frontend/`):
  - `npm run dev` - Inicia Vite dev server (porta 5173)
  - `npm run build` - Build de produção
  - `npm run lint` - ESLint check
- Fluxo recomendado: rodar frontend no terminal WSL já com `nvm` carregado.
- Se usar `nvm`, prefira shell interativo (`bash -ic`) para carregar a versão correta do Node.
- Se precisar executar pelo PowerShell, prefira:
  `wsl --cd /home/moises/dev/coordgeo/coordgeo-frontend bash -lc 'source "$HOME/.nvm/nvm.sh" && nvm use 20.19.4 && npm run dev'`.
- Se ocorrer erro do `@tailwindcss/oxide`:
  ```bash
  rm -rf node_modules package-lock.json && npm install
  ```

## 5) Padrões de implementação
- Não inferir organização no cliente; sempre usar org selecionada explicitamente.
- Diferenciar claramente endpoints que pedem org header dos que não pedem.
- Ao criar cliente HTTP, centralizar base URL por env e headers de auth/org.
- Seguir o plano incremental em `docs/FRONTEND_BUILD_PLAN.md` para novas entregas.
- **Arquitetura de componentes**:
  - Pages em `src/pages/` (rotas principais)
  - Components em `src/components/` (organizados por feature: Map/, Projects/, etc.)
  - Services em `src/services/` (API clients, auth, geodata)
  - State em `src/state/` (Zustand stores)
  - Types em `src/types/` (TypeScript interfaces)

## 6) Validação antes de PR
- Frontend mínimo: `npm run build` e `npm run lint`.
- Se houver mudança no contrato de API, validar também no backend:
  - `python manage.py test -v 2` (em `coordgeo-backend/`).

## 7) Referências rápidas
- `package.json`
- `vite.config.ts`
- `src/index.css`
- `docs/FRONTEND_BUILD_PLAN.md`
- `../coordgeo-backend/api/urls.py`
- `../coordgeo-backend/organizations/permissions.py`

## Frontend Tech Stack Details

**Core Libraries**:
- React 19.2 + React DOM
- React Router 7 (client-side routing)
- TypeScript 5.9
- Vite 7.3 (dev server + build)

**State & HTTP**:
- Zustand 5.0 (lightweight state management)
- Axios 1.13 (HTTP client with interceptors)

**Mapping**:
- MapLibre GL 5.19 (open-source maps, not Mapbox)
- maplibre-gl-draw 1.6.9 (interactive drawing tools)
- @turf/turf 7.2.0 (client-side geoprocessing)

**Styling**:
- Tailwind CSS 4.2 via @tailwindcss/vite plugin

## Backend Integration Contract (Must Preserve)

**CORS Configuration**: Backend allows `localhost:5173`, `127.0.0.1:5173` (configured in `coordgeo-backend/config/settings.py`).

**Authentication Flow**:
1. User signs up/logs in → receives JWT tokens
2. Frontend stores tokens in localStorage
3. Axios interceptor adds `Authorization: Bearer <token>` to all requests
4. User selects organization → stores org ID in Zustand
5. Axios interceptor adds `X-Organization-ID: <uuid>` to org-scoped requests

**Endpoints that DON'T require X-Organization-ID**:
- `/api/v1/token/` (login)
- `/api/v1/token/refresh/` (refresh token)
- `/api/v1/user/organizations/` (list user's orgs for selection)

**Endpoints that REQUIRE X-Organization-ID**:
- All org-scoped resources: `/api/v1/projects/`, `/api/v1/layers/`, `/api/v1/datasources/`, etc.

**Error Handling**:
- Missing `X-Organization-ID` → Backend returns 400 → Frontend should redirect to org selection
- Unauthorized org → Backend returns 403 → Frontend should show error + redirect to org selection

## MapLibre GL + Drawing Integration

**GeoJSON Data URIs**:
- Inline GeoJSON datasources use `data:application/json,...` URIs
- Backend stores as `datasource_type: 'vector'` (no 'geojson' type exists in backend)
- Frontend detects data URIs and creates proper MapLibre GeoJSON sources

**Drawing Tools**:
- `maplibre-gl-draw` provides UI for drawing points, lines, polygons
- `@turf/turf` calculates geometry metrics (area, length, coordinates) client-side
- Drawn geometries saved as layers with inline GeoJSON datasources

**Layer Rendering**:
- MapContainer component manages map lifecycle
- Auto-syncs layers/datasources from Zustand store to MapLibre
- Supports visibility toggles, z-index ordering

## Testing Workflows

- **Backend full suite**: `python manage.py test -v 2` (inside `coordgeo-backend/`).
- **Backend helper**: `python run_tests.py` (uses `keepdb=True`).
- **Frontend**: Currently no test suite; use `npm run build` + `npm run lint` for validation.

## Git Conventions (Same as Backend)

**Commit messages**: Always write in **Portuguese (pt-BR)** when possible:

```
feat: adiciona controles de desenho no mapa
fix: corrige cache do Vite em datasource_type
docs: atualiza instruções do Copilot
refactor: reorganiza componentes de projetos
style: ajusta espaçamento no modal de layers
chore: atualiza dependências do frontend
```

## Key Frontend Files Reference

- **Entry Point**: `src/main.tsx` (React root + API interceptor config)
- **Routing**: `src/App.tsx` (route definitions + guards)
- **Pages**: `src/pages/LandingPage.tsx`, `LoginPage.tsx`, `SignupPage.tsx`, `OrgSelectPage.tsx`, `MapPage.tsx`
- **State**: `src/state/authStore.ts`, `orgStore.ts`, `mapStore.ts`
- **Services**: `src/services/api.ts` (axios config), `auth.ts`, `geodata.ts`, `apiErrors.ts`
- **Map Components**: `src/components/Map/MapContainer.tsx`, `DrawControls.tsx`, `CreateLayerModal.tsx`
- **Project Components**: `src/components/Projects/ProjectForm.tsx`, `CreateProjectModal.tsx`, `ProjectList.tsx`

---

## 🔄 Full-Stack Conventions

### Repository-Specific Commits

**CRITICAL:** Every commit must belong to EXACTLY ONE repository.

**Backend commits → push to `coordgeo-backend`:**
- Changes to `coordgeo-backend/accounts/`, `coordgeo-backend/organizations/`, `coordgeo-backend/projects/`, `coordgeo-backend/data/`, `coordgeo-backend/permissions/`
- Database migrations, models, serializers, views
- API endpoint changes
- Backend tests in `coordgeo-backend/tests_pytest/` or app-specific test folders
- Django configuration, settings, requirements.txt
- Backend documentation in `coordgeo-backend/docs/`

**Frontend commits → push to `coordgeo-frontend`:**
- Changes to `coordgeo-frontend/src/components/`, `coordgeo-frontend/src/pages/`, `coordgeo-frontend/src/services/`, `coordgeo-frontend/src/state/`, `coordgeo-frontend/src/types/`
- React components, hooks, TypeScript types
- Styling, CSS, Tailwind configuration
- Frontend build config (vite.config.ts, tsconfig.json, eslint.config.js)
- Frontend package.json, package-lock.json
- Frontend tests (when created)
- Frontend documentation in `coordgeo-frontend/docs/`

**Root repository commits → push to `coordgeo` (orchestration repo):**
- Changes to `scripts/` (deployment, verification, build automation)
- `.github/copilot-instructions.md` (this file)
- `coordgeo.code-workspace` (workspace configuration)
- `.gitignore` (root ignore rules)
- Root-level documentation explaining the orchestration structure
- **NEVER include backend or frontend source code**

### Workflow for Full-Stack Changes

When a feature requires API + frontend changes:

1. **Design API contract** - Define endpoint shape, request/response formats
2. **Implement backend first**:
   - Create models, migrations, serializers, views in `coordgeo-backend/`
   - Run `python manage.py test -v 2` to validate
   - Commit to `coordgeo-backend` repo
3. **Implement frontend**:
   - Update API client in `coordgeo-frontend/src/services/`
   - Add TypeScript types in `coordgeo-frontend/src/types/`
   - Create/update components in `coordgeo-frontend/src/components/`
   - Run `npm run build && npm run lint` to validate
   - Commit to `coordgeo-frontend` repo
4. **Test integration**:
   - Run `scripts/verify_local.sh` from root to validate both repos work together
   - If issues, fix in respective repo and re-run verification
5. **No mixed commits** - Keep backend and frontend changes in separate commits to separate repositories

### Communication Between Repos

- Backend exposes REST API at `/api/v1/` with proper CORS headers for frontend ports (5173, 4173, 3000)
- Frontend consumes via Axios client with JWT + X-Organization-ID headers
- Changes to API contract require coordination: **always update backend first, then frontend**
- Use `scripts/verify_local.sh` to confirm integration works before considering a feature complete

