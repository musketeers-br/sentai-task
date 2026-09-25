# Prompts para spec 004 — Backend Hardening

---

## 1. Prompt para `/specify`

A spec já está escrita em `specs/004-backend-hardening/spec.md` com 7 FRs, 3 user stories e 4
cenários de aceite. O `/specify` pode ser usado para revisar e refinar, mas a spec está pronta
para `/plan`.

Se quiser rodar `/specify` mesmo assim:

```
Revise e refine a spec 004-backend-hardening.

@specs/004-backend-hardening/spec.md
@specs/003-backend-objectscript/quickstart-evidence.md
@specs/003-backend-objectscript/HANDOFF.md
@specs/001-validate-async-job-contract/compatibility.md

Esta spec NÃO adiciona features. Ela reduz o backend ao que é comprovadamente verdadeiro
no ambiente alvo (IRIS 2026.2). Tudo que não foi provado em T070 é bloqueado ou documentado
como limitação.

Decisões fechadas (não reabrir):
- D-1: support set = integrity-check + defragment-globals
- D-2: scheduling não-operacional (401 no fire time)
- D-3: MaxTotalWorkers=0 significa unbounded

Mantenha o escopo cirúrgico: ~8 tasks, ~3 horas.
```

---

## 2. Prompt para `/plan`

```
Gere o plano de implementação para o 004-backend-hardening.

@specs/004-backend-hardening/spec.md
@specs/003-backend-objectscript/HANDOFF.md
@specs/003-backend-objectscript/quickstart-evidence.md

## Restrição tática

Esta é a menor spec do projeto. Não há tracer bullet — o backend já existe com 86 testes
passando. O plano é uma lista de correções cirúrgicas no código existente.

## Tarefas esperadas (ordem sugerida, test-first)

### T001 — Adicionar campo `available` ao StepType registry
- `src/sentai/registry/StepType.cls`: adicionar `available` ao XData
- `integrity-check` e `defragment-globals`: `available: true`
- `compact-globals`, `switch-journal`, `purge-audit-records`, `purge-task-history`, `custom`: `available: false`
- Teste: `StepTypeTest` verifica o campo para cada type

### T002 — Regra de validação STEP_TYPE_NOT_SUPPORTED_ON_TARGET
- `src/sentai/validation/FlowValidator.cls`: nova regra no `Validate()`
- Produz erro para cada step cujo type tem `available = false`
- Bloqueia dispatch e schedule (mesmos gates)
- Teste: flow com `compact-globals` → erro nomeando o step e o type

### T003 — Regra de validação CATEGORY_NOT_FOUND
- `src/sentai/validation/FlowValidator.cls`: nova regra
- Consulta as categorias existentes na plataforma (ou cache local)
- Erro para step cujo `wqmCategory` não existe, e para `defaultCategory` do flow
- Teste: flow com categoria "NONEXISTENT" → erro

### T004 — Corrigir endpoint WQM write (F-1)
- `src/sentai/wqm/CategoryService.cls`: mudar de `POST /v2/wqm-categories/<name>` para
  `PUT /api/admin/v2/wqm-category?name=<name>`
- Teste: `CategoryServiceTest` verifica URL e método HTTP

### T005 — Corrigir invariante nesting para MaxTotalWorkers=0 (F-4)
- `src/sentai/validation/FlowValidator.cls` ou `CategoryService.cls`
- `0` em `maxWorkers`/`maxTotalWorkers` = unbounded (trata como +∞)
- Teste: categoria com `MaxTotalWorkers=0` passa invariante

### T006 — Atualizar testes existentes afetados
- `StepTypeTest`: incluir `available`
- `ValidateEndpointTest`: flow com tipo não suportado → erro adicional
- `DispatchEndpointTest`: dispatch com tipo não suportado → recusado
- `ScheduleEndpointTest`: schedule com tipo não suportado → recusado

### T007 — Atualizar REST response do registry
- Se existir endpoint `GET /catalog/step-types`: incluir `available` na resposta
- Se o frontend consome o registry por outro caminho: ajustar

### T008 — Documentação
- README.md: known limitations (scheduling, step types, token 60s)
- quickstart.md: ajustar passos que usam tipos não suportados
- HANDOFF.md: marcar E-1, E-2, E-3 como "addressed by spec 004"

## Restrições
- Sem endpoints novos
- Sem mudança no schema JSON do flow
- Todos os 86 testes existentes devem passar (com ajustes)
- ObjectScript puro
- ~3 horas de trabalho
```

---

## 2b. Prompt para `/tasks` (após Clarifications de escopo mínimo, 2026-09-23)

```
Generate tasks.md for 004-backend-hardening.

@specs/004-backend-hardening/spec.md
@specs/004-backend-hardening/plan.md
@specs/004-backend-hardening/data-model.md
@specs/004-backend-hardening/quickstart.md
@specs/004-backend-hardening/contracts/api-delta.md

The spec is the source of truth. Its "Clarifications — minimum shippable scope" session
(2026-09-23) postdates plan.md and supersedes it where they conflict:

1. D-1 amended: support set = `integrity-check` ONLY. `defragment-globals` is
   `available: false`. Every plan/data-model/quickstart/contract reference to defragment as
   supported or best-effort is stale.
2. Quickstart reduced to the minimum acceptance path: (a) 2–3 `integrity-check` steps
   fan-out/fan-in on an existing category → validate `errors: []` → dispatch 202 → SSE to
   `completed`; (b) unsupported type refused with STEP_TYPE_NOT_SUPPORTED_ON_TARGET;
   (c) unknown category refused with CATEGORY_NOT_FOUND. Scheduling, >60 s/401, real WQM write,
   defragment probe, destructive-schedule refusal and sanitation move to an "Evidence / notes"
   section — not acceptance.
3. Scheduling: no code change, not in acceptance path; README uses the D-2 wording verbatim.
4. US-3 removed; documentation is FR-007 (cross-cutting), done in the final polish task.

Task requirements:
- First task: reconcile stale artifacts (data-model.md availability table, quickstart.md,
  contracts/api-delta.md example message, plan.md T001 fixture `SupportedGraph()` → all
  `integrity-check`, plan risk row on defragment). Docs only, ~15 min.
- Then keep the plan's test-first order: scaffolding → FR-001 availability → FR-002 blocking
  (validate/dispatch/schedule/rerun) → FR-005 zero-unbounded → FR-004 WQM write → FR-006
  category existence → FR-007 docs + real-instance run of the reduced quickstart.
- Group by user story: US1 (FR-001..003), US2 (FR-004..006), then Polish (FR-007, FR-008).
- Mark [P] only where files do not overlap (FlowValidator.cls is shared by FR-002/FR-005/FR-006:
  sequential).
- Each task names the exact file(s) and the test class it adds or adjusts.
- SC-001 is now 6 unsupported types × 4 paths = 24 refusals.
- Budget: ≤ 9 tasks, ~3 h total. No new endpoints, no schema change, no test deleted.
- Do not add tasks for token refresh, scheduled-run auth, parameter forwarding or proving
  defragment.
```

---

## 3. Como iniciar a sessão

```
Estou finalizando o backend do SentaiTask. Esta spec é cirúrgica: reduz o backend ao que
a plataforma IRIS 2026.2 realmente suporta e corrige 2 bugs de contrato.

Leia:
@specs/004-backend-hardening/spec.md
@specs/003-backend-objectscript/quickstart-evidence.md
@specs/003-backend-objectscript/HANDOFF.md

Depois execute /plan usando o prompt em:
@specs/004-backend-hardening/PROMPTS.md §2

A spec já está escrita — pule direto para o plano.
```
