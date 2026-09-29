# API delta: Area Report Steps

No new route. Additive values only.

## `GET /catalog/step-types`

- Four new entries (data-model §1).
- `executor` may now be `"platform-read"`: "reads the management API of the instance the step runs
  on and reports; no platform job".
- `category` may now be `"security"` or `"monitoring"`.
- `remoteCapable` is `true` for `platform-read` types.

`openapi.yaml`: the `StepTypeInfo` schema's `executor` enum gains `platform-read`, and the
`category` enum gains `security` and `monitoring`.

## `GET /runs/{guid}` → `steps[].result`

Already returned since spec 005 (`{}` when none). For the new types, it is the report of
plan D-4. Unchanged shape for the other types.

## Validation codes

No new code. The existing `PARAM_*` codes apply to the new schemas, and
`STEP_TYPE_NOT_REMOTE_CAPABLE` no longer applies to these types.
