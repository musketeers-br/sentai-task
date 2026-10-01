# Caso de uso — a janela de manutenção semanal

*Leia isto em [inglês](use-case-weekly-maintenance.md).*

O fluxo que este documento percorre vem com a aplicação como
**Weekly maintenance window** — o build da imagem o semeia, então um `docker compose up -d`
recém-criado já o lista (veja [O fluxo já vem semeado](#o-fluxo-já-vem-semeado)). Ele usa todos
os step types que o catálogo marca `available: true` no IRIS 2026.2, cada um pela razão que
sua entrada de catálogo declara, e exercita o que torna um fluxo mais do que uma lista de
tarefas: waves paralelas, dependências, fan-in joins, um único gate de validação, a confirmação
digitada de um step destrutivo e resultados guardados por step.

## O problema de onde ele parte

Integrity checks, trocas de journal, purges e checagens de disco costumam viver soltos no Task
Manager, com a ordem e o "o que acontece se um falhar" na cabeça de alguém. Se o disco enche
de madrugada, o integrity check roda mesmo assim e falha feio. Se ele falha, ninguém sabe se o
purge rodou por cima. Este caso de uso transforma esse runbook tácito em um fluxo declarado:

1. **Portão de espaço em disco** — nada pesado começa sem espaço para rodar.
2. **Snapshot do espaço** — o retrato "antes", guardado com o run.
3. **Journal novo** — o trabalho da janela não ultrapassa o arquivo de journal atual.
4. **Verificação em paralelo** — dois integrity checks como uma única wave.
5. **Fechamento da janela** — limpar o histórico antigo de tarefas, só se tudo acima deu certo.

## Pré-condições

- O compose stack: `docker compose up -d` (o serviço `iris` basta; nenhum target server
  participa deste exemplo).
- Uma conta de operador — na imagem dev, `_SYSTEM` / `SYS`. Toda chamada roda com a credencial
  do próprio operador, e a recusa da plataforma é o `failureReason` do step, palavra por
  palavra (Constituição III).
- **Validar** exige `%Admin_Manage:USE` e leitura no IRISSYS (a validação lê as categorias WQM
  com o token do operador). A troca de journal exige `%Admin_Operate:USE` — sem isso, a
  plataforma recusa com o próprio texto `#921`. O resto a plataforma decide.
- **O despacho é manual no v1.** `purge-task-history`, `switch-journal`,
  `storage-headroom-check` e `db-size-report` são steps in-process, que não são scheduláveis
  (`IN_PROCESS_NOT_SCHEDULABLE`) — um run agendado não tem operador. O despacho manual é o
  caminho v1 suportado, de qualquer forma.

## O esquadrão e o plano de ataque

```
WAVE 1 — recon (só leitura, em paralelo)     WAVE 3 — o ataque (em paralelo)
  01 storage-headroom-check (15%)            04 integrity-check (USER)
  02 db-size-report                          05 integrity-check (%SYS)
        |                                           |
        v  fan-in ALL_MUST_SUCCEED                  v  fan-in ALL_MUST_SUCCEED
WAVE 2 — suporte                            WAVE 4 — fechamento da janela
  03 switch-journal                          06 purge-task-history (30d, %SYS)
                                              ! destrutivo: digitar "%SYS" no Run now
```

| Step | Tipo | Papel, nas palavras do próprio catálogo |
|---|---|---|
| 01 | `storage-headroom-check` (`minFreePercent: 15`) | "Avisar quando o espaço em disco está acabando" — o portão: o padrão que o próprio README sugere é colocá-lo à frente, para os integrity checks atrás dele só começarem quando houver espaço |
| 02 | `db-size-report` | "Reportar quanto espaço cada database e arquivo de journal ocupa, para mostrar para onde o crescimento vai" — o snapshot "antes", guardado no `result` do step |
| 03 | `switch-journal` | "Rolar o journal para um arquivo novo, para que uma janela de manutenção longa não ultrapasse o atual" — antes do trabalho pesado, não depois |
| 04 | `integrity-check` (USER) | "Verificar que as estruturas internas da database estão íntegras" — um job da plataforma com GUID próprio e relatório próprio |
| 05 | `integrity-check` (%SYS) | O mesmo, em paralelo — dois jobs independentes numa wave |
| 06 | `purge-task-history` (`keepDays: 30`) | "Apagar o histórico de tarefas terminadas, mantendo os dias mais recentes" — o fechamento da janela, e só se tudo acima deu certo; `keepDays: 30` preserva as entradas da própria janela |

Os namespaces `USER` e `%SYS` existem em qualquer instância IRIS, e `Default` é uma categoria
WQM embutida — por isso o fluxo semeado valida limpo em qualquer instalação, não só no compose
stack.

## Montando

### No canvas

Arraste os cinco step types da paleta (os in-process ficam no grupo **Custom** da paleta) e
conecte `01 → 03 ← 02`, `03 → 04`, `03 → 05`, `04 → 06 ← 05`; arestas que fechariam um ciclo
são recusadas no ato do desenho. Duas arestas num mesmo nó se encontram num diamante — esse nó
espera por todas.

Você não precisa saber os nomes dos step types. A busca da paleta aceita o **trabalho, não o
nome da ferramenta** — scores medidos no `all-minilm` do stack dev:

| Você digita | SUGGESTED oferece primeiro |
|---|---|
| `check my globals are sound` | Integrity check (0.47) |
| `rotate the journal` | Switch journal (0.55) |
| `free up disk space` | Storage headroom check (0.59), Compact globals (0.49 — listado, mas `available: false`, logo não adicionável) |

Nada fora do catálogo fechado é sugerido, nunca (Constituição II).

### Pela API

O JSON abaixo é o fluxo que a semente cria — espelha, byte a byte, o bloco
`XData WeeklyMaintenance` de [`src/sentai/demo/DemoFlows.cls`](../src/sentai/demo/DemoFlows.cls):

```json
{
  "schemaVersion": 1,
  "name": "Weekly maintenance window",
  "defaultCategory": "Default",
  "steps": [
    {"id": "01", "type": "storage-headroom-check", "taskName": "Storage headroom", "namespace": "%SYS", "parameters": {"minFreePercent": 15}, "timeoutMinutes": 10, "wqmCategory": "Default"},
    {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "timeoutMinutes": 10, "wqmCategory": "Default"},
    {"id": "03", "type": "switch-journal", "taskName": "Switch journal", "namespace": "%SYS", "timeoutMinutes": 5, "wqmCategory": "Default"},
    {"id": "04", "type": "integrity-check", "taskName": "Integrity check - USER", "namespace": "USER", "timeoutMinutes": 45, "wqmCategory": "Default"},
    {"id": "05", "type": "integrity-check", "taskName": "Integrity check - %SYS", "namespace": "%SYS", "timeoutMinutes": 45, "wqmCategory": "Default"},
    {"id": "06", "type": "purge-task-history", "taskName": "Purge task history", "namespace": "%SYS", "parameters": {"keepDays": 30}, "timeoutMinutes": 10, "wqmCategory": "Default"}
  ],
  "edges": [
    {"source": "01", "target": "03"},
    {"source": "02", "target": "03"},
    {"source": "03", "target": "04"},
    {"source": "03", "target": "05"},
    {"source": "04", "target": "06"},
    {"source": "05", "target": "06"}
  ],
  "joins": [
    {"target": "03", "policy": "ALL_MUST_SUCCEED"},
    {"target": "06", "policy": "ALL_MUST_SUCCEED"}
  ],
  "canvasGeometry": {
    "viewport": {"x": 0, "y": 40, "zoom": 0.85},
    "nodes": {
      "01": {"x": 0, "y": 0, "width": 240},
      "02": {"x": 0, "y": 220, "width": 240},
      "03": {"x": 340, "y": 110, "width": 240},
      "04": {"x": 680, "y": 0, "width": 240},
      "05": {"x": 680, "y": 220, "width": 240},
      "06": {"x": 1020, "y": 110, "width": 240}
    }
  }
}
```

`canvasGeometry` é só apresentação — o dispatcher nunca o lê; a ordem de execução vem só das
arestas.

## Validar

```sh
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/validate
# {"errors":[],"warnings":[]}
```

O fluxo semeado responde exatamente isso — verificado no stack dev. O mesmo gate roda de novo
no despacho, então um fluxo que falha aqui nunca roda. Os findings caem **no nó a que dizem
respeito**; cada um carrega um código:

| Se você quebrar... | O nó mostra |
|---|---|
| a categoria de um step (`wqmCategory: "NONEXISTENT"`) | `CATEGORY_NOT_FOUND` |
| um parâmetro declarado (`minFreePercent: 150`) | `PARAM_OUT_OF_RANGE` (com `parameter: minFreePercent`) |
| uma chave que o tipo não declara (`keepDays` no 02) | `PARAM_UNKNOWN` |
| um namespace que não existe | `NAMESPACE_NOT_FOUND` |

## Despachar

No canvas: **Run now** pede a senha uma vez (o run ganha seu próprio sign-in, renova a própria
credencial sozinho, e a senha não fica guardada) e — como o step 06 é destrutivo — pede que
você **digite `%SYS`**, o namespace sobre o qual ele atua. O backend confere o valor digitado;
erro é um 428 mostrado verbatim, e o diálogo continua aberto.

Pela API, o equivalente são dois corpos: a confirmação digitada e a credencial do run (sem a
qual o run para quando expira o token de 60 segundos da plataforma):

```sh
PAIR=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login)
ACCESS=$(echo "$PAIR" | jq -r .access_token)
REFRESH=$(echo "$PAIR" | jq -r .refresh_token)

curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/dispatch \
  -H "Authorization: Bearer $ACCESS" -H "Content-Type: application/json" \
  -d '{"confirmations": [{"stepId": "06", "typedName": "%SYS"}],
       "runCredential": {"refreshToken": "'"$REFRESH"'"}}'
# 202 {"guid": "<runGuid>", "state": "running", ...}
```

O run tem **uma identidade**: o operador que o despachou. Os steps in-process rodam como esse
operador (`executedAs` diz quem), e a plataforma decide, naquele momento, se ele pode — a
recusa vira o `failureReason` do step, palavra por palavra. Um `runCredential` de outra pessoa
é recusado com 403 `RUN_CREDENTIAL_USER_MISMATCH` antes de qualquer coisa começar.

## Acompanhar o run

No canvas as waves acendem em ordem: `01` e `02` juntos, depois `03`, depois `04` e `05`
juntos, depois `06`. Pela API:

```sh
curl -N http://localhost:52773/csp/sentai/api/v1/runs/<runGuid>/events -H "Authorization: Bearer $ACCESS"
# event: step-state-changed ... event: run-terminal
```

- **Os resultados ficam por step** (`GET /runs/<runGuid>` → `steps[].result`): o de 02 é
  `databases[]`, cada database com `sizeMB` e `freeMB`; os de 04/05 carregam o relatório de
  integrity check da própria plataforma; o de 01 nomeia cada local verificado. Um resultado
  maior que 8000 caracteres mantém os primeiros elementos da sua maior lista e acrescenta
  `"truncated": true`.
- **Cancele um step** (`POST /runs/<guid>/steps/<stepGuid>/cancel`) sem tocar no irmão de
  wave. Cancelar um job da plataforma em execução faz o IRIS logar
  `ERROR #7802 … unexpectedly shut down` e reportar o container como `unhealthy` — o run está
  bem; limpe o alerta com `do $SYSTEM.Monitor.Clear()` no `%SYS`.
- **Rode de novo um step que falhou** (`POST …/steps/<stepGuid>/rerun`) — só quem despachou
  pode (403 `RERUN_NOT_BY_DISPATCHER` para qualquer outro).

## Quando as coisas dão errado — o produto continua honesto

- **Disco abaixo de 15%** — o 01 falha, nomeando cada local com sua porcentagem livre. Nada
  downstream roda: a falha se propaga pelo join `ALL_MUST_SUCCEED`, e 03–06 transitam direto
  para `failed` com o motivo "One or more required inputs failed". O run relata falha parcial,
  nunca sucesso (Constituição IV: um run parcialmente falho nunca é reportado como sucesso).
- **O operador não pode trocar journal** — a plataforma recusa; o texto `#921` dela é o
  `failureReason` do step, nada reinterpretado.
- **Erro de digitação na confirmação** — 428 com o `detail` do backend, verbatim.
- **Um integrity check trava** — cancele só ele; o irmão segue; o join no 06 nunca o vê dar
  certo, e o 06 não roda.

## O fluxo já vem semeado

- **O build da imagem compose o semeia.** Depois do load do módulo, o build executa
  `iris-demo.script`, uma chamada `Do ##class(sentai.demo.DemoFlows).EnsureSeeded()`, então um
  `docker compose up -d --build` recém-criado abre com o exemplo na lista de flows.
- **Uma instalação via `zpm "install sentai-task"` traz o seeder, não o dado.** Uma linha num
  `iris session`, no namespace do módulo, cria o fluxo:

  ```objectscript
  Do ##class(sentai.demo.DemoFlows).EnsureSeeded()
  ```

- **Idempotente por nome.** Um fluxo com esse nome que já exista — editado ou não — é devolvido
  intocado; a semente nunca sobrescreve o trabalho de um operador, e uma demo removida não é
  ressuscitada por um `zpm load` posterior.
- **Remoção** (a API não tem deleção de flows) é uma chamada:

  ```objectscript
  Do ##class(sentai.demo.DemoFlows).Remove()
  ```

  Um fluxo que você já despachou é preservado: `Remove` recusa com `SentaiFlowHasRuns` em vez
  de órfar os runs que guardam seu histórico.

Targets distribuídos (DPI-I-588 — um step rodando em outra instância IRIS) ganham um exemplo
próprio; até lá, veja a seção *Target servers from the canvas* do README.

## Referências

- [README](../README.md) — modelo de flows, step types declarados, busca semântica de step types
- [Limitações conhecidas](limitations.md) — o conjunto suportado no v1 e por que o despacho é manual
- `src/sentai/registry/StepType.cls` — o catálogo fechado, o único lugar onde uma capability é declarada
- `src/sentai/demo/DemoFlows.cls` — a definição semeada (o JSON acima espelha seu XData)

---

*Este documento é tradução de [use-case-weekly-maintenance.md](use-case-weekly-maintenance.md),
a versão mantida.*
