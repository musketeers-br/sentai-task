# Data Model: Run Log and Run History

## 1. Entities

**LogEntry** (exists, `sentai.model.LogEntry`): `run`, `at` (`%TimeStamp`, now with
milliseconds), `stepId` (optional), `severity` (`info` | `warning` | `error`), `message` (≤ 4000
characters). If the platform's text is longer, the narrator writes it in several consecutive
entries marked `(1/2)`, `(2/2)`, so the text stays whole (FR-002).

**RunSummary** (list item, new projection, not persisted):

| Field | Source |
|---|---|
| `seq` | `Run.%Id()` |
| `guid`, `flowId`, `flowRevision`, `state`, `startedAt`, `finishedAt`, `dispatchedBy` | `Run` (as today) |
| `flowName` | `Flow.name` (current) |
| `totalDurationMs` | `Run.TotalDurationMs()` |
| `stepCounts` | `{queued, running, paused, completed, failed, cancelled}` over the latest attempt per step |

**RunExport** (file, client-built): see plan D-10.

## 2. Log message catalog

`RunNarrator` is the only writer. `#nn` is the step id; `<…>` is data; text in quotes is the
platform's, verbatim.

| Fact | Called from | Severity | Step | Message |
|---|---|---|---|---|
| Run dispatched | `WaveDispatcher.CreateRun` | info | — | `Run dispatched by <user> (flow revision <n>, <k> steps)` |
| Step queued → running | `StepRun.TransitionTo` | info | #nn | `#nn <taskName> started on <local\|target>` |
| Step → completed | `StepRun.TransitionTo` | info | #nn | `#nn completed in <duration>` |
| Step → failed | `StepRun.TransitionTo` | error | #nn | `#nn failed after <duration>: "<failureReason>"` |
| Step → cancelled | `StepRun.TransitionTo` | warning | #nn | `#nn cancelled` |
| Step → paused / resumed | `StepRun.TransitionTo` | info | #nn | `#nn paused` / `#nn resumed` |
| Join blocked | `ComputeEligibleSteps` | error | #nn | `#nn not started: input #mm <failed\|cancelled> (all inputs must succeed)` |
| Re-run queued | `WaveDispatcher.RerunStep` (the new attempt is saved as `queued`, not transitioned) | info | #nn | `#nn re-run queued (attempt <a>)` |
| Operator request accepted | REST control handlers | info | #nn or — | `<user> asked to <cancel\|pause\|re-run> <the run\|#nn>` |
| Operator request refused | REST control handlers | warning | #nn or — | `<user> asked to <action> <what>; refused: "<problem detail>"` |
| Target stopped answering | `MarkTargetFailed` (first in an outage) | warning | — | `Target <name> did not answer: "<transport error>"; retrying every 30 s` |
| Target answers again | `MarkTargetAnswered` | info | — | `Target <name> answers again` |
| Run credential renewal refused | `RenewRunCredentialIfDue` | warning | — | `Renewing the run's credential was refused: HTTP <status> "<summary>"` |
| Run finished | `FinalizeRun` | info / error (failed) / warning (cancelled) | — | `Run <state>: <c> completed, <f> failed, <x> cancelled (<duration>)` |

`<duration>` uses the format of the canvas's step timers (`1m 00s`, `850 ms`).

## 3. Outage flag

`^IRIS.Temp.sentaiTargetCred(runGuid, "%down", target) = 1` while an outage is open. It is set
with the first "did not answer" entry and killed with "answers again". It is erased with the
run's credentials (`EraseRunCredential` kills the whole run subtree already).

## 4. Frontend state

- `RunsQuery = { flow?: string; state?: RunState }`, round-tripped with the address (`runs.ts`).
- `RunsPage = { items: RunSummaryView[]; next: number | null; status: 'loading' | 'ready' | 'error'; error? }`.
  `mergePage(a, b)` appends by `seq` and drops duplicates.
