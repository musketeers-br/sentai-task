# Data Model Delta — 004 Backend Hardening

No persistent class changes. No flow-document schema change. The deltas are one catalog field,
two error codes, and one invariant semantic.

## Step-type catalog entry (`sentai.registry.StepType` XData)

| Field | Type | Change |
|---|---|---|
| `type` | string | — |
| `class` | string | — |
| `category` | string | — |
| `destructive` | boolean | — |
| `pausable` | boolean | — |
| **`available`** | boolean | **new** — `true` only for `integrity-check` |

| type | available | destructive | pausable |
|---|---|---|---|
| integrity-check | **true** | false | false |
| compact-globals | false | false | false |
| defragment-globals | false | false | false |
| switch-journal | false | false | false |
| purge-audit-records | false | true | true |
| purge-task-history | false | true | true |
| custom | false | false | false |

Derived: the only available type is neither destructive nor pausable (spec "Consequences of D-1", amended).

## Validation error codes (existing `{stepId, code, message}` shape)

| Code | Emitted by | When | Blocks |
|---|---|---|---|
| `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` | `Validate()` | step type known and `available = false` | validate (reported), dispatch (422), schedule (422) |
| `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` | `RerunStep` | rerun of a StepRun whose step type is unavailable | rerun (409, code in `detail`) |
| `CATEGORY_NOT_FOUND` | `Validate()` with a credential | effective category not in the platform list (or list unreadable) | validate, dispatch, schedule |

Effective category = `step.wqmCategory` if non-empty, else `flow.defaultCategory`.
One error per step; `stepId` is always the step's id (never `""`).

Rule order inside the per-step loop (existing rules unchanged):

1. `CUSTOM_CLASS_REQUIRED`
2. `UNKNOWN_STEP_TYPE` **else** `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` **and** per-type parameter schema
3. `NAMESPACE_NOT_FOUND`
4. **`CATEGORY_NOT_FOUND`** (new; skipped with no credential)
5. `WQM_INVARIANT_VIOLATED`
6. `PRECONDITION_READ_ONLY` (warning)

## WQM nesting invariant (`sentai.model.Category.SatisfiesInvariant`)

`defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`, where `maxWorkers = 0` and
`maxTotalWorkers = 0` mean ∞. Comparison `x ≤ y`: true if `y = ∞`; false if `x = ∞` and `y` finite;
numeric otherwise.

| default | maxActive | maxWorkers | maxTotal | Before | After |
|---|---|---|---|---|---|
| 1 | 3 | 0 | 0 | ✗ | ✓ (built-in `Utility`, evidence 10a) |
| 2 | 4 | 8 | 0 | ✗ | ✓ |
| 1 | 2 | 0 | 5 | ✗ | ✗ (∞ ≤ 5) |
| 1 | 2 | 3 | 2 | ✗ | ✗ (unchanged) |
| 0 | 0 | 0 | 0 | ✓ | ✓ |
