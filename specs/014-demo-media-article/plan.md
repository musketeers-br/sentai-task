# Implementation Plan: Demo Media and Community Article

**Branch**: `feat/spec014` (feature dir `014-demo-media-article`) | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (5 clarifications, 14 FRs, 5 SCs). Tooling and documentation only:
no product code, no API change, so there is **no `contracts/` directory**. The recording reuses
Playwright (already a dev dependency) in its own project with video on. The conversion to GIF and
MP4 runs `ffmpeg` in a throw-away Docker container, so nothing new is installed (FR-006).

## Summary

1. **Recorder (US1).** `frontend/media/showcase.media.ts`, run by
   `frontend/playwright.media.config.ts` (1280×720, `deviceScaleFactor: 1`, `video: 'on'`,
   `slowMo: 150`). It signs in, opens or creates the showcase flow through the API (same definition
   as spec 011, checked against the shared fixture), and plays the scenes of
   [data-model §1](data-model.md). A caption overlay is injected by the recorder, never by the
   product. At each scene it records a marker with the time. It asserts that the run completed, and
   that the page text never contains the session's tokens or the typed passwords. Any failure
   throws, and the wrapper script then writes nothing.
2. **Stills (US1-6).** A second test in the same project takes 1440×900 @2× screenshots of six
   screens in both themes, with the existing `tests/theming.ts` helper.
3. **Conversion.** `scripts/media/make-media.sh` runs the recorder into a temporary directory, then
   `docker run --rm jrottenberg/ffmpeg:7-alpine` to produce `sentai-run.mp4` (H.264, 1280×720),
   `sentai-run.gif` (960 px, 12 fps, two-pass palette) and `sentai-run-small.gif` (640 px, 8 fps).
   It applies a uniform speed factor so the GIF lasts at most 30 s; when the factor exceeds 1.5 the
   captions carry "time-lapse ×N", because the recorder renders them after reading the expected
   factor from an environment variable on a second pass ([R-2](research.md)). It checks the size
   limits, then moves the results into `assets/media/` with a `manifest.json`.
4. **Articles (US2, US3, US5).** `docs/articles/en/…md`, `docs/articles/pt-br/…md`,
   `docs/articles/video-script.md` (EN and PT scenes) and `docs/articles/publish-checklist.md`.
   `scripts/media/check-articles.mjs` (Node, from the frontend toolchain) checks links, word count,
   the required sections, and forbidden content (credentials, private addresses, the words
   "password:" or "token:" followed by a value).
5. **Channels (US4).** The README top picture becomes `assets/media/sentai-run.gif` (with `alt`
   text); the "Try it" block gains the video link once published. Open Exchange and community
   publishing follow the checklist (team actions).

## Technical Context

**Language/Version**: TypeScript (Playwright 1.63) for the recorder; POSIX shell and Node 20 for
the scripts; Markdown for the articles.

**Primary Dependencies**: `@playwright/test` (existing); `jrottenberg/ffmpeg:7-alpine` Docker image,
pulled on first use.

**Storage**: `assets/media/` (committed: GIFs, stills, manifest; `*.mp4` gitignored because it is
uploaded to the video platform).

**Testing**: the recorder is itself an end-to-end check (it fails unless the run completes, and
checks secrecy on each scene); `check-articles.mjs` has a vitest suite on fixtures (good and bad
articles); `make-media.sh` checks sizes and durations with `ffprobe` (same image).

**Target Platform**: the team's machine (Windows + Docker Desktop + Git Bash) and Linux.

**Project Type**: tooling and documentation.

**Performance Goals**: SC-001: < 5 min per run (the showcase takes about 20–60 s; conversion
under 1 min).

**Constraints**: the default e2e suite must not pick up the media test (separate config and
`testDir: 'media'`); no secrets in frames (recorder assertion + manual frame review); facts only
from merged work (FR-008).

**Scale/Scope**: 1 recorder (~250 lines), 2 scripts, 1 checker (+ tests), 4 documents, README edit.

## Constitution Check

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | No product code. The recorder drives the product through its UI and public API only. | ✅ |
| **II Closed Capability Set** | The caption overlay is injected by the test tool into its own browser session, never shipped. No product operation is added. | ✅ |
| **III Delegated Authorization** | The recording signs in like an operator; nothing bypasses the platform. | ✅ |
| **IV Errors as Values** | The scripts exit non-zero with a message on any failed check; no partial media is written. | ✅ |
| **V Verifiable Increments** | Four increments (recorder + stills; conversion; English article + checker; Portuguese article + script + README), each with its automated check. | ✅ |
| **VI Technology Agnosticism** | Tools only in this plan. | ✅ |
| Reproducibility | One command; its only prerequisites are Docker and the frontend toolchain, which the repository already requires. | ✅ |
| YAGNI | No video editor, no music, no automated publishing. | ✅ |

## Decisions

- **D-1 Scenes** (data-model §1): 8 scenes, about 45 s of real time before speed-up.
- **D-2 Showcase source.** The recorder reads the definition from the fixture
  `tests/sentai/unittest/fixtures/showcase-flow.json`, which spec 011 creates for
  `Demo.ShowcaseDefinition()`. If spec 013 is merged (the catalog lists `security-posture-report`),
  the recorder adds, in its own code, one security posture report on each server to the fan-in and
  saves the result as a separate flow, `Showcase + security (media)`. The spec 011 fixture and
  seed stay unchanged.
- **D-3 Passwords.** The recorder types passwords only into `type=password` fields and reads them
  from `SENTAI_MEDIA_PASSWORD` (default `SYS` for the local stack). The secrecy assertion checks
  `document.body.innerText` and every `input` value except password inputs.
- **D-4 Captions.** A fixed `<div id="media-caption">` injected with `page.addInitScript`,
  positioned bottom-left, with the product's font and colours read from CSS variables; the text per
  scene comes from `media/captions.ts` (English).
- **D-5 Article structure** (spec US2-1). Title: "SentaiTask: orchestrating InterSystems IRIS
  maintenance as flows, not lists". Slug files: `docs/articles/en/sentaitask-orchestration.md` and
  `docs/articles/pt-br/sentaitask-orquestracao.md`. Each claim links to a README anchor or a spec
  folder on GitHub (absolute URLs, so they work when pasted).
- **D-6 Checker rules.** Words 900–1,600 (excluding code and link URLs); the required `##`
  sections; every `http(s)` link answers 2xx/3xx (GET with a 10 s timeout, retry once); relative
  links are refused (pasted articles need absolute ones); forbidden regexes: private IPv4 ranges,
  `(?i)(password|senha|token)\s*[:=]\s*\S+`, `_SYSTEM`/`SYS` pairs, e-mail addresses other than the
  team's public contact if any.
- **D-7 Order of work.** The recorder and stills can be built now against the current product;
  the final recording and the article's final text wait for specs 011–013 to merge (the spec's
  honesty rule). The English article is drafted in parallel with sections marked `<!-- after 013
  merge -->`, and the checker refuses those markers at publication time.

## Increments

| # | Story | Check first | Then |
|---|---|---|---|
| 1 | US1 recorder + stills | the recorder run fails (no file) | recorder, captions, stills |
| 2 | US1 conversion | `make-media.sh` size/duration checks fail on a dummy input | ffmpeg steps, manifest |
| 3 | US2 article EN | `check-articles` vitest (fixtures) + run on the draft fails | checker, article |
| 4 | US3/US5/US4 | checker on PT; README link check (spec 011 `acceptance.sh --readme`) | PT article, script, README, checklist |

## Project Structure

```text
specs/014-demo-media-article/
├── plan.md  research.md  data-model.md  quickstart.md  analysis.md  tasks.md
└── checklists/requirements.md

frontend/playwright.media.config.ts       # new
frontend/media/showcase.media.ts          # new (recording + stills)
frontend/media/captions.ts                # new
scripts/media/make-media.sh               # new
scripts/media/check-articles.mjs (+ test) # new
assets/media/                             # generated: gifs, stills, manifest.json
docs/articles/en/sentaitask-orchestration.md
docs/articles/pt-br/sentaitask-orquestracao.md
docs/articles/video-script.md
docs/articles/publish-checklist.md
README.md                                 # top picture, video link
.gitignore                                # assets/media/*.mp4
```

## Complexity Tracking

No violations.
