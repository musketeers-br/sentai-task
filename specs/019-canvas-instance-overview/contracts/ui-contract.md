# UI contract: Canvas Instance Overview

**Consumes**: spec 018 `GET /overview`, `GET /overview/readings/{area}`,
`POST /overview/reports/{stepType}`, `POST /overview/areas/{area}/flow`, and — only when present —
`POST /overview/processes/{pid}/{action}`, `GET /overview/process-actions`
([018 api-delta](../../018-instance-overview-api/contracts/api-delta.md)). No other new call.

## Client methods (`src/lib/api/client.ts`)

| Method | Call | Returns |
|---|---|---|
| `overviewSummary()` | `GET /overview` | `ApiResult<AreaCardView[]>` |
| `overviewReading(area)` | `GET /overview/readings/{area}` | `ApiResult<ReadingView>` |
| `overviewReport(stepType, parameters)` | `POST /overview/reports/{stepType}` | `ApiResult<CardReport>`; 422 → `kind: 'validation'` |
| `overviewFlow(area, parameters)` | `POST /overview/areas/{area}/flow` | `ApiResult<{ flowId: string; hasErrors: boolean }>` |
| `processAction(pid, action, confirmation?)` | US5 only | `ApiResult<unknown>`; 428 → `kind: 'problem'` |

## Screen and test ids

| Element | Accessible name / test id |
|---|---|
| Top-bar tab | button `Overview` (first tab), `aria-current="page"` when shown |
| Card | `data-testid="area-card"` + `data-area="<id>"` + `data-state="ok|refused|unreachable|running"` |
| Refusal text | `data-testid="card-refusal"` (HTTP status + platform text verbatim) |
| Buttons | `Refresh`, `Open` (instance cards), `Run report`, `Open report`, `Schedule this check` |
| Detail table | `role="table"` named `<Label> rows`; header buttons sort; input labelled `Filter rows` |
| Auto-refresh | checkbox labelled `Auto-refresh every 10 s` |
| Report viewer | the existing `data-testid="result-panel"` |

## Wording rules

- No "CPU", "memory" or "log" on its own: the memory card is **Shared memory**; the process column
  `CPUTime` is headed **CPU time (process)** (FR-006).
- Refusals show `HTTP <status> — <platform summary>` exactly as spec 009's target states do.
