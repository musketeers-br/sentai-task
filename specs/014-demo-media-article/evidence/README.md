# Spec 014 — Evidence

## Media (T002–T005, 2026-09-29)

`bash scripts/media/make-media.sh` on the dev stack with `iris-target` up, specs 011–013 in place
(the recorder found `security-posture-report` and filmed *Showcase + security (media)*: the spec
011 showcase plus a security posture report on each server in the fan-in).

| File | Size | Duration | Setting |
|---|---|---|---|
| `assets/media/sentai-run.gif` | 5.88 MB (≤ 8 MB) | 28.0 s (≤ 30 s) | 800 px, 8 fps, time-lapse ×3.08 (captioned) |
| `assets/media/sentai-run-small.gif` | 2.08 MB (≤ 3 MB) | 28.0 s | 560 px, 6 fps |
| `assets/media/sentai-run.mp4` (git-ignored, for the video platform) | 2.9 MB | 85.2 s (≤ 90 s) | 1280×720 H.264 |
| `assets/media/stills/*.png` | 12 files | — | 6 screens × dark/light, 1440×900 |

Research R-2 measured: 960 px at 12 and 10 fps gave 10 MB, so the script steps down width and
frame rate until each variant fits its budget; the first recording ran 111 s, so the second pass
renders the time-lapse caption (factor > 1.5).

Findings while building the recorder (fixed in the scripts):
- Playwright only picks `*.spec.ts`/`*.test.ts` by default; the media config declares
  `testMatch: '**/*.media.ts'`, and the default e2e suite still lists no media test.
- On Git Bash, `/tmp` paths handed to Node and Docker resolved to `C:\tmp`; the script passes the
  native path (`cygpath -m`).
- The validation scene waited for a text that never appears, wasting ~8 s of the GIF; it now waits
  for the *Validate flow* button to be enabled again.

**SC-002 frame review.** A 1-fps mosaic of the GIF and all 12 stills were reviewed: no password,
token or secret in any frame (the *Run now* dialog shows masked fields only; the recorder also
asserts on every scene that neither the kept sign-in token nor a password of 8+ characters is on
screen).

## Articles (T006–T010)

- Checker: `node --test scripts/media/articles.test.mjs` → **10/10**.
- `node --use-system-ca scripts/media/check-articles.mjs docs/articles/en/*.md docs/articles/pt-br/*.md`:
  EN 1,216 words, PT 1,273 words, all sections, no forbidden content; the only failing links are
  the GIF and the spec 011 evidence on `master`, which exist once specs 011–014 are merged.
  (`--use-system-ca`: Node alone cannot verify the Ideas portal's certificate chain.)
- Both articles are `status: draft` with `<!-- after … -->` markers on the parts that depend on
  merges; the checker refuses `status: ready` while any marker remains.

## Team actions still open (T008, T013, T014)

Merge 011–014; remove the markers, set `status: ready`, second reader; upload the video; publish
EN, then PT with its link to EN; update the README *Try it* block and the Open Exchange page;
record the URLs, dates and, on 2026-10-04, the page views here. See
[`docs/articles/publish-checklist.md`](../../../docs/articles/publish-checklist.md).
