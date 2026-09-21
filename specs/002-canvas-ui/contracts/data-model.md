# Phase 1 — Data model

Feature: `001-flow-orchestrator` · Date: 2026-09-21

Persistence is IRIS classes under the `SENTAI` package plus one global for the GUID
registry. Nothing here duplicates what the Task Manager already stores; where a field
exists in IRIS, this model references it rather than copying it.

---

## Glossary *(Constitution IV)*

Terms taken from IRIS, used with their IRIS meaning and spelling:

`namespace` · `database directory` · `%SYS` · `%Admin_Task` · `%SYS.Task.Definition` ·
`TaskName` · `TimeQueued` · `TimeStarted` · `TimeFinished` · `Work Queue Manager` ·
`DefaultWorkers` · `MaxActiveWorkers` · `MaxWorkers` · `MaxTotalWorkers` · `AlwaysQueue`

Terms this product introduces, defined once, here:

| Term | Meaning |
|---|---|
| **Flow** | A named, versioned DAG of steps that an operator composes on the canvas |
| **Step** | One node of a flow: a step type plus its configuration |
| **Edge** | A directed dependency from one step to another |
| **Join** | The set of incoming edges on a step, plus a partial-failure policy |
| **Wave** | The set of steps that become eligible to run at the same moment |
| **Run** | One execution of one flow revision |
| **StepRun** | One execution of one step within a run |

None of these shadow an IRIS term.

---

## Entities

### Flow — `SENTAI.Model.Flow`

| Field | Type | Notes |
|---|---|---|
| `id` | `%String(32)` | Primary key |
| `name` | `%String(128)` | Unique per instance; shown in the header |
| `revision` | `%Integer` | Bumped on every save; a run pins the revision it started with |
| `savedAt` | `%TimeStamp` | Shown as `rev 14 · saved 02:41` |
| `savedBy` | `%String(64)` | IRIS username |
| `defaultCategory` | `%String(64)` | WQM category applied to steps that name none |
| `scheduleSpec` | `%String(256)` | What was handed to the Task Manager; null when unscheduled |
| `canvasGeometry` | `%Stream` | Node positions and viewport; presentation only, never read by the dispatcher |

**Rules**

- `name` is unique, case-insensitive.
- Saving bumps `revision` even if only geometry changed, so a run always pins something
  reproducible.
- `canvasGeometry` MUST NOT influence execution order. Order comes from edges alone.

---

### Step — `SENTAI.Model.Step`

| Field | Type | Notes |
|---|---|---|
| `id` | `%String(8)` | Stable within the flow; rendered as `#01`, `#02`, … |
| `flow` | ref Flow | Parent |
| `type` | `%String(48)` | See *Step types* below |
| `taskName` | `%String(128)` | Maps to the Task Manager's `TaskName` |
| `namespace` | `%String(64)` | e.g. `USER`, `%SYS` |
| `databaseDirectory` | `%String(256)` | Where the type needs one |
| `runAsUser` | `%String(64)` | IRIS username the task runs under |
| `parameters` | `%DynamicObject` | Type-specific; validated against the type's schema |
| `timeoutMinutes` | `%Integer` | 0 = no timeout |
| `wqmCategory` | `%String(64)` | Falls back to the flow default |
| `isDestructive` | `%Boolean` | **Derived from `type`, never stored as operator input** |

**Rules**

- `isDestructive` is computed from the step type registry. It cannot be turned off by
  editing the step *(Constitution I)*.
- A destructive step MUST carry `confirmationRequired = true`; the field exists but has
  no false branch in v1.
- `parameters` MUST validate against the type schema before the flow can be scheduled.

---

### Edge — `SENTAI.Model.Edge`

| Field | Type | Notes |
|---|---|---|
| `flow` | ref Flow | Parent |
| `source` | ref Step | |
| `target` | ref Step | |

**Rules**

- The edge set MUST be acyclic. Cycle detection runs on every mutation, not on save.
- An edge whose `target` has ≥2 incoming edges is rendered as part of a fan-in
  *(FR-004)*; this is derived, not a stored edge kind.

---

### Join — `SENTAI.Model.Join`

Logically the incoming-edge set of one step; stored as one row per target step that has
more than one.

| Field | Type | Notes |
|---|---|---|
| `target` | ref Step | |
| `policy` | enum | `ALL_MUST_SUCCEED` \| `PROCEED_ON_PARTIAL` \| `MIN_SUCCEEDED` |
| `minSucceeded` | `%Integer` | Only with `MIN_SUCCEEDED` |

**Rules**

- The policy in force MUST be visible on the canvas whenever any input has failed
  *(FR-025)*.
- Default is `ALL_MUST_SUCCEED` pending **O-1** in `research.md`.

---

### Run — `SENTAI.Model.Run`

| Field | Type | Notes |
|---|---|---|
| `guid` | `%String(36)` | Primary key, from `$SYSTEM.Util.CreateGUID()` |
| `flow` | ref Flow | |
| `flowRevision` | `%Integer` | Pinned at dispatch; edits afterwards do not affect this run |
| `startedAt` / `finishedAt` | `%TimeStamp` | |
| `dispatchedBy` | `%String(64)` | |
| `state` | enum | `running` \| `completed` \| `failed` \| `cancelled` |

**Derived, never stored**: `totalDuration` = `finishedAt - startedAt`;
`sumOfSteps` = Σ step durations. Both are shown, and they differ under parallelism —
that difference is the point of the history screen *(FR-036)*.

---

### StepRun — `SENTAI.Model.StepRun`

| Field | Type | Notes |
|---|---|---|
| `guid` | `%String(36)` | Primary key; generated **before** the step starts *(R-004)* |
| `run` | ref Run | |
| `stepId` | `%String(8)` | |
| `state` | enum | `queued` \| `running` \| `paused` \| `completed` \| `failed` \| `cancelled` |
| `timeQueued` | `%TimeStamp` | |
| `timeStarted` | `%TimeStamp` | Null while queued |
| `timeFinished` | `%TimeStamp` | Null until terminal |
| `failureReason` | `%String(2000)` | Verbatim from IRIS; never rewritten *(FR-022)* |
| `progressCurrent` / `progressTotal` | `%Integer` | Null where the type reports no progress |
| `confirmedBy` / `confirmedAt` | `%String(64)` / `%TimeStamp` | Destructive steps only *(FR-013)* |

**State machine**

```
queued ──► running ──► completed
  │           │
  │           ├──────► failed
  │           ├──────► paused ──► running
  │           └──────► cancelled
  └──────────────────► cancelled
```

Illegal transitions: `completed → *`, `failed → *`, `cancelled → *`,
`queued → running` without a GUID, `queued → paused`.

**Rules**

- A StepRun MUST exist with `timeQueued` set before its GUID is returned to the caller.
- `timeStarted - timeQueued` is the hatched segment and `timeFinished - timeStarted` the
  solid segment of the history bar *(FR-033)*.
- `failureReason` is stored and displayed byte-for-byte as IRIS produced it.

---

### WQM category — `SENTAI.Model.Category`

| Field | Type | Notes |
|---|---|---|
| `name` | `%String(64)` | e.g. `SENTAI.NIGHT` |
| `defaultWorkers` | `%Integer` | |
| `maxActiveWorkers` | `%Integer` | |
| `maxWorkers` | `%Integer` | |
| `maxTotalWorkers` | `%Integer` | |
| `alwaysQueue` | `%Boolean` | |

**Rules**

- Invariant: `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`.
  The nesting diagram in UI-005 draws this invariant; violating it is a validation error,
  not a warning.
- Before save, the system MUST count and report how many scheduled tasks outside the
  current flow use this category *(FR-017)*.
- A change MUST NOT affect a run already in flight.

---

### GUID registry — `^SentaiRun`

```
^SentaiRun(runGuid)              = $lb(flowId, flowRevision, startedAt, dispatchedBy)
^SentaiRun(runGuid, stepId)      = stepRunGuid
^SentaiRun("idx", stepRunGuid)   = $lb(runGuid, stepId)
```

Written inside the dispatch transaction. The reverse index exists so a GUID found in
`messages.log` resolves to a run and a step in one lookup.

---

## Step types

The registry is data, not code branches. Each entry declares its class, parameter schema,
preconditions, destructive flag and palette category.

| Type | Class | Category | Destructive | Pause |
|---|---|---|---|---|
| `integrity-check` | `%SYS.Task.IntegrityCheck` | verification | no | no |
| `compact-globals` | `%SYS.Task.CompactGlobals` | storage | no | no |
| `defragment-globals` | `%SYS.Task.Defragment` | storage | no | no |
| `switch-journal` | `%SYS.Task.SwitchJournal` | journal | no | no |
| `purge-audit-records` | `%SYS.Task.PurgeAuditDatabase` | purge | **yes** | yes |
| `purge-task-history` | `%SYS.Task.PurgeTaskHistory` | purge | **yes** | yes |
| `custom` | user subclass of `%SYS.Task.Definition` | custom | declared by the subclass | declared |

A custom type that declares itself destructive gets the full three-signal treatment with
no further configuration.

---

## Validation rules, collected

1. Edge set acyclic *(FR-003)*.
2. Every step's `parameters` valid against its type schema.
3. Every referenced namespace exists at schedule time and again at dispatch *(R-006)*.
4. Category ceilings satisfy the nesting invariant.
5. Every destructive step has a typed confirmation recorded before it starts
   *(Constitution I)*.
6. Every StepRun has a GUID before it leaves `queued` *(Constitution III)*.
