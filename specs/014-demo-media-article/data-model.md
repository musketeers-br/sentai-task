# Data Model: Demo Media and Community Article

## 1. Scenes (recorder and narration script)

| # | Scene | Caption (EN) | Approx. real time |
|---|---|---|---|
| 1 | Canvas with the showcase flow (fit view) | "A maintenance flow: checks on two servers, one join" | 4 s |
| 2 | *Validate flow* → no errors | "Validated against the live instance" | 3 s |
| 3 | *Run now* → password dialog (masked) → dispatch | "Run now: the platform authorizes every call" | 5 s |
| 4 | Steps queued → running in parallel; target step shows "on iris-target" | "3 checks in parallel, 2 servers" | 10–40 s |
| 5 | Join releases the final step; run completed | "Join: all must succeed, then the report" | 5 s |
| 6 | Open a report result (security findings if 013 is merged, else database sizes) | "Every step keeps its result" | 5 s |
| 7 | Run log panel (if 012 is merged) | "The run tells its own story" | 3 s |
| 8 | *Runs* screen (if 012 is merged), else *Targets* screen | "History of every run" / "Servers it can reach" | 4 s |

Scenes 6–8 adapt to what is merged (catalog and screen detection).

## 2. Media manifest (`assets/media/manifest.json`)

```json
{ "recordedAt": "2026-09-30T12:00:00Z", "commit": "<sha>", "moduleVersion": "<module.xml version>",
  "timelapse": 1.0,
  "files": { "gif": {"path": "sentai-run.gif", "bytes": 0, "seconds": 0},
             "gifSmall": {"path": "sentai-run-small.gif", "bytes": 0, "seconds": 0},
             "stills": ["stills/showcase-run-dark.png", "…"] } }
```

## 3. Stills

`assets/media/stills/<screen>-<theme>.png`, where `screen` is one of `showcase-run`, `palette`,
`report-result`, `run-history`, `targets`, `catalog`, and `theme` is `dark` or `light`
(12 files).

## 4. Article front matter (comment block at the top, not published)

```markdown
<!-- lang: en | target: community.intersystems.com | status: draft|ready | published: <url> -->
```

The checker reads `status`. `ready` requires no `<!-- after … -->` markers.
