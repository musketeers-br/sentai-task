# API delta: step-type search (spec 017)

Base: `specs/011-semantic-step-search/contracts/api-delta.md`. The route, the query parameter, the
status codes and both response shapes are **unchanged**.

## `GET /csp/sentai/api/v1/catalog/step-types/search?q=…`

One value is added to the closed list of `reason`:

```json
{ "available": false, "reason": "warming" }
```

| `reason` | Meaning | New? |
|---|---|---|
| `not-configured` | No provider row | — |
| `unreachable` | The configured HTTP provider did not answer | — |
| `slow` | The provider answered too late for the keystroke budget | — |
| `incompatible` | The provider's vector width differs from the stored corpus | — |
| **`warming`** | The in-process provider is still loading its model; a later search will rank | **yes** |
| `error` | Anything else | — |

- Still HTTP **200**, still no `matches` on an unavailable answer (spec 011 FR-024, FR-025).
- The canvas treats `warming` like every other unavailable reason: today's palette, no error shown.
- Consumers that do not know `warming` must treat an unknown reason as `error` (the canvas already
  does, in `frontend/src/lib/api/wire.ts`); this feature adds it to that list so it is kept by name.
