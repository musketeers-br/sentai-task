# SentaiTask — Roadmap de Specs

**Atualizado**: 2026-09-23 · **Deadline contest**: 2026-09-27 · **Meta interna**: 2026-09-25
**Equipe**: 2 devs · **Capacidade restante**: ~36h líquidas (6h/dev/dia × 3 dias)

---

## Estado atual (23/09)

| Frente | Estado | Evidência |
|---|---|---|
| **Backend (003)** | 70/73 tasks, 81 testes passando no IRIS 2026.2 | Modelo, REST, dispatch, validação, registry, SSE, schedule implementados |
| **Frontend (002)** | Tracer bullet especificado, não implementado | plan.md + research.md + data-model.md prontos, `frontend/` não existe |
| **Spike (001)** | Concluído | Fixes 1-5 aplicados, chaining inviável via API |

### Backend: o que falta

| Task | Descrição | Bloqueio |
|---|---|---|
| T070 | Quickstart end-to-end (web app CSP → HTTP) | Configuração do instance |
| T072 | Executar sanitation (527 órfãos, fingerprint `137624262-527`) | Aprovação do operador |
| T073 | Verificar recusa de schedule destrutivo via HTTP | Depende de T070 |

### Frontend: nada implementado

O `frontend/` não existe ainda. O tracer bullet prova que SvelteKit + Svelte Flow compila num
container IRIS — é o risco que o plan.md queria retirar. A partir do tracer, as fases
subsequentes consomem os endpoints P0 do backend, que já estão implementados.

---

## Specs: 10 features

```
specs/
  001-admin-adapter/            # auth, contratos fixados, contexto instância
  002-task-catalog/             # tasks, upcoming, history, run/suspend, editor
  003-flow-canvas/              # editor visual + persistência JSON do fluxo
  004-flow-dispatcher/          # resolve ordem, dispara onda, guarda GUIDs
  005-step-catalog/             # tipos de passo como wrappers de %SYS.Task
  006-run-control/              # status, cancel, pause, resume, timeline
  007-wqm-categories/           # CRUD + vínculo fluxo → categoria
  008-admin-coverage/           # leitura fina das 5 áreas da API
  009-workmgr-steps/            # P2 — passos customizados via WorkMgr
  010-task-chaining/            # P2 — RunAfterGUID (inviável, placeholder)
```

---

## Classificação Front / Back e estado de implementação

| Spec | Lado | Back implementado? | Front implementado? |
|---|---|---|---|
| 001-admin-adapter | **Back** | **Sim** (T004, T005 — auth/refresh no Dispatcher) | N/A |
| 002-task-catalog | Full-stack | **Parcial** (T065-T067 — TaskService, /catalog/*) | Não |
| 003-flow-canvas | Front-heavy | **Sim** (T014-T020 — Flow/Step/Edge/Join CRUD) | Não |
| 004-flow-dispatcher | **Back** | **Sim** (T038-T040 — DAG→waves→WQM, ^SentaiRun) | N/A |
| 005-step-catalog | Full-stack | **Sim** (T003, T007 — registry 7 types) | Não |
| 006-run-control | Full-stack | **Sim** (T036-T037, T041-T050 — Run/StepRun, SSE, cancel/pause) | Não |
| 007-wqm-categories | Full-stack | **Sim** (T062-T064 — Category CRUD, invariante) | Não |
| 008-admin-coverage | **Back** | Não | N/A |
| 009-workmgr-steps | **Back** | Não | N/A |
| 010-task-chaining | **Back** | Morto (spike 001: GUID não exposto) | N/A |

**Conclusão**: o backend P0 está essencialmente pronto. O gargalo é o frontend.

---

## Grafo de dependências

```
                    ┌─────────────┐
                    │ 001-admin   │ ✅ back done
                    │   adapter   │
                    └──────┬──────┘
                           │ auth token
              ┌────────────┼────────────────┐
              ▼            ▼                ▼
     ┌────────────┐  ┌───────────┐   ┌───────────┐
     │ 002-task   │  │ 003-flow  │   │ 008-admin │
     │  catalog   │  │  canvas   │   │ coverage  │
     │ back:parcl │  │ back:✅   │   │ cortado   │
     │ front:NÃO  │  │ front:NÃO │   └───────────┘
     └────────────┘  └─────┬─────┘
              │            │
              │      ┌─────┼──────────┐
              │      ▼     ▼          ▼
              │  ┌───────┐ ┌────────┐ ┌───────────┐
              │  │ 004   │ │ 005    │ │ 007-wqm   │
              │  │ disp. │ │ steps  │ │ categories│
              │  │ ✅    │ │ ✅back │ │ ✅back    │
              │  └───┬───┘ └────────┘ └───────────┘
              │      │
              │      ▼
              │  ┌───────┐
              └─►│ 006   │
                 │ run   │
                 │ ✅back│
                 └───┬───┘
                     │
           ┌─────────┼──────────┐
           ▼                    ▼
      ┌──────────┐        ┌──────────┐
      │ 009 P2   │        │ 010 P2   │
      │ cortado  │        │ morto    │
      └──────────┘        └──────────┘
```

---

## O que pode rodar em paralelo AGORA (23-25/09)

O backend P0 desbloqueou tudo no front. Os dois devs podem trabalhar em frontend simultaneamente,
ou dev 2 pode fechar T070/T072/T073 enquanto dev 1 ataca o frontend.

### Paralelo recomendado

| Dev 1 (Front) | Dev 2 (Front ou Back) |
|---|---|
| **003**: tracer bullet (scaffold SvelteKit, Svelte Flow, Dockerfile multi-stage) | **T070/T072/T073**: fechar as 3 tasks restantes do backend |
| **003**: paleta, drag-drop, edges, inspector | **002**: task catalog UI (lista, detalhe, history) |
| **006**: live run UI (SSE + timeline) | **005**: formulário dinâmico por step type |
| **007**: WQM UI (UI-005 nesting diagram) | Polish, README contest |

### O que NÃO precisa de sequência

| Par | Paralelo? | Razão |
|---|---|---|
| 003-front + 002-front | ✅ Sim | Telas independentes, APIs diferentes |
| 003-front + 005-front | ✅ Sim | Paleta vs formulário, sem conflito |
| 006-front + 002-front | ✅ Sim | Live run vs catalog, rotas diferentes |
| 007-front + qualquer | ✅ Sim | Tela isolada (UI-005) |

### O que precisa de sequência

| Spec | Depende de | Porque |
|---|---|---|
| 003-front fase 2 (composição) | 003-front tracer bullet | Precisa do scaffold funcionando |
| 006-front (live run) | 003-front (canvas base) | Reutiliza o canvas com nodes em estado |
| 005-front (formulário) | 003-front (inspector) | Formulário vive dentro do inspector |

---

## Estimativa revisada (36h restantes)

| Spec | Horas | Lado | Corte |
|---|---|---|---|
| 003-flow-canvas front | 16 | Front | Mantém integral (é o produto) |
| 006-run-control front | 6 | Front | Timeline simplificada |
| 002-task-catalog front | 4 | Front | Lista + history. **Corta**: editor 35 props |
| 005-step-catalog front | 4 | Front | Formulário para 3 types (integrity, compact, purge-audit) |
| 007-wqm-categories front | 3 | Front | UI-005 simplificado |
| Backend T070/T072/T073 | 2 | Back | Fechar as 3 tasks |
| README + polish | 1 | Ambos | |
| **Total** | **36h** | | Encaixa no budget |

### O que cortou vs roadmap anterior

| Spec | Decisão |
|---|---|
| 008-admin-coverage | **Cortado** — README declara cobertura reduzida |
| 009-workmgr-steps | **Cortado** — P2, não entra |
| 010-task-chaining | **Morto** — spike 001 provou inviável |
| 001-admin-adapter back | **Já feito** — dentro do 003-backend |
| 004-flow-dispatcher back | **Já feito** — dentro do 003-backend |

---

## Timeline dia-a-dia

### Dia 3 — 23/09 (hoje)

| Dev 1 | Dev 2 |
|---|---|
| 003: scaffold `frontend/`, SvelteKit + Svelte Flow | T070: web app CSP, quickstart end-to-end |
| 003: TracerNode, TracerCanvas, fixture, rota | T072: executar sanitation (com aprovação) |
| **Entrega**: container servindo 3 nós | **Entrega**: backend 73/73, instance limpo |

### Dia 4 — 24/09

| Dev 1 | Dev 2 |
|---|---|
| 003: paleta, drag-drop, edges, inspector | 002: task catalog UI (lista, detalhe) |
| 003: persistência JSON (save/load via API) | 005: formulário por step type (3 types) |
| **Entrega**: canvas editável salva no IRIS | **Entrega**: catalog + step forms |

### Dia 5 — 25/09 (meta interna)

| Dev 1 | Dev 2 |
|---|---|
| 006: live run UI (SSE, state nodes, timeline) | 007: WQM UI (UI-005, nesting diagram) |
| 003: validação visual (erros/warnings no canvas) | README do contest |
| **Entrega**: **demo completa** | **Entrega**: WQM + docs |

### Dia 6 — 26/09

| Dev 1 | Dev 2 |
|---|---|
| Temas (dark/light toggle) | Edge cases, testes Playwright |
| Polish visual | Polish |

### Dia 7 — 27/09 — Submit

---

## Pergunta central de cada spec

| Spec | Pergunta que o spec.md fecha |
|---|---|
| 001 | Formato real de cada resposta da SysAdmin API? Refresh do token? 403 por privilégio faltante? |
| 002 | Quais das 35 props no formulário vs "Advanced"? Editável vs read-only? |
| 003 | O que é um fluxo válido? Onda paralela vs junção? O que o editor recusa salvar? |
| 004 | Falha parcial — passo falha, os outros continuam? Fluxo para, pula ou segue? |
| 005 | Pré-condição por tipo? Quais destrutivos? Parâmetros → formulário como? |
| 006 | Passo cancelado → fluxo em que estado? Pausar passo pausa fluxo? "Concluído com falhas"? |
| 007 | Vínculo fluxo→categoria obrigatório? Deletar categoria em uso → 409? |
| 008 | Suportado, indisponível e não configurado em cada uma das 5 áreas? |

---

## Notas

- O backend foi implementado como spec 003-backend-objectscript (monolítico), não dividido em
  specs separadas. As 10 specs do roadmap se aplicam como **features lógicas** para organizar o
  trabalho de frontend, não como pastas físicas separadas no backend.

- O `openapi.yaml` em `specs/002-canvas-ui/contracts/` continua sendo a fonte de verdade.

- Decisão de escopo pós-validação: flows com passos destrutivos **não são agendáveis** no v1
  (`DESTRUCTIVE_NOT_SCHEDULABLE`). Dispatch manual com confirmação tipada continua funcionando.
