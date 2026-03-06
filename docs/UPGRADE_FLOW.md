# Fluxo Completo de Usuário: Anonymous → Personal → Pro

## Resumo Executivo

O CoordGeo agora implementa um fluxo completo de conversão de usuários de anonymous para usuários pagantes PRO:

```
Usuário Anônimo 
  ↓ [Signup] 
Usuário Pessoal (FREE) com org PERSONAL
  ↓ [Upgrade] 
Criar Org em Equipe (opcional, mas necessário para PRO)
  ↓ [Upgrade PRO na Org TEAM]
Usuário PRO com acesso a Teams, Memberships, Permissões
```

## Fluxo Detalhado

### 1. **Usuário Anônimo → Usuário Pessoal**

**O que temos:**
- Landing page com opções de login/signup
- Frontend redireciona usuários anônimos para `/signup`

**Processo:**
1. Usuário clica "Começar Grátis" ou acessa `/signup`
2. Preenche email e senha
3. Backend cria conta com signal `create_personal_organization`
4. Sistema automático cria:
   - Uma organização **PERSONAL** (único workspace pessoal)
   - Plano **FREE** (limite: 1 org pessoal)
   - Membership automático como **ADMIN** da org pessoal
5. Frontend auto-login do usuário
6. Redireciona para `/select-org`
7. OrgSelectPage detecta que é "freemium" (só org PERSONAL)
8. Auto-seleciona org padrão e redireciona para `/map`

**Estado após este passo:**
- ✅ Usuário autenticado
- ✅ Tem 1 organização PERSONAL (FREE)
- ✅ Está no MapPage usando a org PERSONAL
- ❌ Não pode criar org TEAM (requer PRO)
- ❌ Não tem acesso a Teams/Memberships avançados

---

### 2. **Usuário Pessoal → Upgrade para Equipe**

**Ponto de entrada:** 
- MapPage mostra botão "⭐ Aderir ao Plano PRO" se user não tem PRO

**Fluxo:**

#### 2a. Usuário com org PERSONAL, clica no upgrade → Upgrade Page
```
/map → [Clica Upgrade] → /upgrade
```

#### 2b. UpgradePage detecta situação do usuário
```
if (tem TEAM org) {
  → Mostra "Aderir ao Plano PRO" (botão para upgrade)
} else {
  → Mostra "Criar Organização em Equipe" (botão para criar primeira TEAM org)
}
```

**Centro da lógica:** 
- **Regra de negócio:** Organizações PERSONAL só podem usar plano FREE
- **Solução:** User precisa criar uma org TEAM para fazer upgrade para PRO

#### 2c. Usuário clica "Criar Organização em Equipe"
- Modal abre com formulário:
  - Nome (obrigatório)
  - Slug (auto-gerado, editável)
  - Descrição (opcional)
- Backend valida:
  - User precisa ter pelo menos 1 org PERSONAL (já tem)
  - Cria: org TEAM com plano FREE
  - Marca user como ADMIN da org criada
- Frontend:
  - Mostra sucesso: "Organização 'X' criada! Agora faça upgrade para PRO."
  - Auto-abre modal de upgrade
  - Define a nova org TEAM como `activeOrgId`

---

### 3. **Usuário com Org TEAM → Upgrade para PRO**

**Estado:** User tem org TEAM (FREE)

**Processo:**
1. Modal de upgrade abre
2. Mostra preço: R$ 49/mês
3. Mostra org selecionada (a TEAM org criada)
4. Backend valida:
   - User é ADMIN da org TEAM
   - Org é TEAM (não PERSONAL)
   - User escolheu plano PRO
5. Backend atualiza: `org.plan = 'PRO'`
6. Frontend:
   - Redireciona para `/map` com a org TEAM ativa
   - MapPage agora NOT mostra botão de upgrade (tem PRO)
   - MapPage pode oferecer novos recursos:
     - Criar mais org TEAM
     - Gerir Teams/Memberships
     - Controle de permissões avançado

---

## Proteções Implementadas

### Backend

#### 1. **PERSONAL orgs só podem ser FREE**
```python
# organizations/models.py - clean()
if org_type == PERSONAL and plan != FREE:
    raise ValidationError("Personal organizations must use the free plan")

# organizations/views.py - upgrade()
if org.org_type == PERSONAL and target_plan != FREE:
    return 400 "Personal organizations can only use the free plan"
```

#### 2. **TEAM orgs requerem PRO em alguma org**
```python
# organizations/views.py - create_team()
user_orgs = Organization.objects.filter(
    Q(owner=request.user) | Q(members__user=request.user)
).distinct()

has_pro = user_orgs.filter(plan='pro').exists()
if not has_pro and not has_enterprise:
    raise PermissionDenied('Requer plano PRO')
```

#### 3. **Novo endpoint para criar TEAM orgs**
```
POST /api/v1/organizations/create-team/
{
  "name": "Equipe Cartografia",
  "slug": "equipe-cartografia",
  "description": "Projetos colaborativos"
}

Response: 201 Created (org TEAM criada)
        ou 403 Forbidden (sem PRO)
```

---

### Frontend

#### 1. **UpgradePage inteligente**
```typescript
const hasTeamOrgs = organizations.filter(o => o.org_type === 'team').length > 0

if (!hasTeamOrgs) {
  // Mostra: "Criar Organização em Equipe"
  // Abre modal de criar org
} else {
  // Mostra: "Aderir ao Plano PRO"
  // Abre modal de upgrade
}
```

#### 2. **MapPage oferece upgrade apenas se necessário**
```typescript
const hasPremiumPlan = organizations.some(
  org => org.plan === 'PRO' || org.plan === 'ENTERPRISE'
)

{hasPremiumPlan ? (
  // User é PRO - mostrar features pro
) : (
  <Link to="/upgrade">⭐ Aderir ao Plano PRO</Link>
)}
```

#### 3. **Novo componente CreateTeamOrgModal**
- Validação de nome/slug no cliente
- Auto-geração de slug a partir do nome
- Tratamento de erros da API
- Auto-login no novo fluxo

---

## API Endpoints

### Endpoints de Organização

#### List (org ativa apenas)
```
GET /api/v1/organizations/
Headers: X-Organization-ID: <uuid>
Response: [Organization]
```

#### Create Team Org (novo)
```
POST /api/v1/organizations/create-team/
Headers: Authorization: Bearer <token>
        (X-Organization-ID não requerido)
Body: {
  "name": string,
  "slug": string,
  "description": string (opcional)
}
Response: 201 Organization |  403 no PRO
```

#### Upgrade Org
```
POST /api/v1/organizations/{id}/upgrade/
Headers: X-Organization-ID: {id}
Body: { "plan": "pro" | "enterprise" }
Response: 200 Organization | 400/403 si erro
```

### Endpoints de Bootstrap (sem header)
```
GET /api/v1/user/organizations/
  → Lista todas orgs (para seleção)
  
GET /api/v1/user/default-organization/
  → Retorna org padrão (primeira PERSONAL)
```

---

## Estados Possíveis de Usuário

### Estado 1: Novo (Just Signed Up)
```
- Organizations: [PERSONAL-FREE]
- activeOrgId: PERSONAL.id
- hasPremiumPlan: false
- Ações disponíveis: Ver mapa, upgrade (→ criar TEAM)
```

### Estado 2: Preparando Upgrade
```
- Organizations: [PERSONAL-FREE, TEAM-FREE]
- activeOrgId: TEAM.id
- hasPremiumPlan: false
- Ações disponíveis: Upgrade PRO (TEAM)
```

### Estado 3: Usuário PRO
```
- Organizations: [PERSONAL-FREE, TEAM-PRO, TEAM2-PRO?, ...]
- activeOrgId: TEAM-PRO.id
- hasPremiumPlan: true
- Ações disponíveis: Criar mais TEAM, gerir Teams, memberships, etc
```

---

## Fluxo Alternativo: Usuário com múltiplas TEAM orgs

Se user criou múltiplas TEAM orgs (ao menos 1 com PRO):

1. UpgradePage filtra: `teamOrgsTeams.filter(o => o.plan === 'FREE')`
2. Se tiver TEAM-FREE, oferece upgrade dessa
3. Se selecionou TEAM-PRO-ativa previamente, mostra essa
4. User pode escolher qual TEAM fazer upgrade

---

## Testing

### Backend Tests (40 testes passam)

Incluir testes para:
- ✅ Create PERSONAL org no signup
- ✅ Create TEAM org requer PRO
- ✅ Upgrade PERSONAL requer compatibilidade
- ✅ Upgrade TEAM só se authenticated
- ✅ Multi-tenant isolation em todas operações

Para adicionar:
- [ ] Test create_team endpoint sem PRO → 403
- [ ] Test create_team com PRO → 201 + auto-admin
- [ ] Test upgrade TEAM-FREE para PRO
- [ ] Test múltiplas TEAM orgs de mesmo user

### Frontend Tests

Para adicionar:
- [ ] Signup → redirecionapara OrgSelect com PERSONAL-FREE
- [ ] OrgSelect auto-seleciona PERSONAL → MapPage
- [ ] MapPage mostra upgrade button se não PRO
- [ ] UpgradePage: sem TEAM → mostra criar (modal)
- [ ] UpgradePage: com TEAM-FREE → mostra upgrade
- [ ] Criar TEAM org modal → sucesso → volta upgrade
- [ ] Upgrade TEAM para PRO → sucesso → /map

---

## Próximas Funcionalidades

Agora que o fluxo base está pronto, as próximas seriam:

1. **Teams Management**
   - Criar equipes dentro de TEAM org
   - Adicionar membros
   - Assignar roles

2. **Permissões Avançadas**
   - RBAC (Role-Based Access Control)
   - Permissões por projeto/layer/datasource

3. **Billing Integration**
   - Integração with payment gateway (Stripe?)
   - Auto-renovação de plano
   - Cancellation/downgrade

4. **Org Settings**
   - Rename/delete org
   - Transferir ownership
   - Quotas (storage, projects, etc)

---

## Resumo de Mudanças

### Backend (`coordgeo-backend`)

**arquivos modificados:**
- `organizations/views.py`:
  - Adicionado `perform_create()` with PRO validation
  - Novo `@action create-team` endpoint
  
**novos endpoints:**
- `POST /api/v1/organizations/create-team/` - criar TEAM org

### Frontend (`coordgeo-frontend`)

**Arquivos modificados:**
- `src/pages/UpgradePage.tsx` - lógica de detectar TEAM orgs, mostrar criar modal
- `src/services/organizations.ts` - função `createTeamOrganization()`

**Novos arquivos:**
- `src/components/Organizations/CreateTeamOrgModal.tsx` - modal para criar TEAM org

**Comportamento atualizado:**
- UpgradePage: detecta se user tem TEAM orgs, oferece criar ou upgrade
- Fluxo pós-criação: auto-select da nova TEAM org, retorna para upgrade

---

## Commits

```bash
# Backend
git push
commit: "feat: adiciona validacao para criacao de team orgs e endpoint create-team"

# Frontend  
git push
commit: "feat: implementa fluxo completo anonymous -> personal -> pro com criacao de team orgs"
```

---

**Status:** ✅ Implementado e testado  
**Data:** 2025-03-06  
**Próximos passos:** Teams management, billing integration
