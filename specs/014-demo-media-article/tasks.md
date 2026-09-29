# Tasks: Demo Media and Community Article

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [quickstart.md](quickstart.md). No `contracts/`: no product or API
change.

**Tests**: the recorder is a self-checking end-to-end run (completion and secrecy assertions);
`check-articles.mjs` has a vitest suite; `make-media.sh` checks size and duration. Each is written
and seen failing first.

**Hard rules**: no password, token, secret or personal data in any frame, still or article; the
default e2e suite must not run the media project (`npx playwright test` still reports the same
count); articles claim only merged work; publishing and Open Exchange edits are team actions, confirmed before doing them.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [ ] T001 Add `assets/media/*.mp4` and `assets/media/review-*.png` to `.gitignore`; create `frontend/playwright.media.config.ts` (testDir `media`, 1280×720, `deviceScaleFactor: 1`, `video: 'on'`, `slowMo: 150`, workers 1); confirm that `npx playwright test --list` (default config) lists no media test.

---

## Phase 2: User Story 1 — Recorder, stills, conversion (P1)

- [ ] T002 [US1] Write `frontend/media/showcase.media.ts` first as a failing skeleton that asserts the run reached `completed` and the secrecy rule (plan D-3) and saves nothing else; run it against the dev stack with a stopped target: it fails with "target unavailable" (FR-004).
- [ ] T003 [US1] Implement the scenes of data-model §1 with `media/captions.ts` (plan D-1, D-2, D-4), the adaptation for specs 012/013 (feature detection through `GET /catalog/step-types` and the presence of the *Runs* tab), and the stills test (six screens × two themes, data-model §3). Run it three times in a row (SC-001).
- [ ] T004 [US1] Write `scripts/media/make-media.sh` (plan summary 3): temp dir, recorder, measure, optional second pass with `SENTAI_MEDIA_TIMELAPSE`, ffmpeg conversions, `ffprobe` checks (≤ 30 s / ≤ 8 MB, small ≤ 3 MB, mp4 ≤ 90 s), move to `assets/media/`, `manifest.json`. First run it on a 2-minute dummy WebM and see the checks refuse it; then on the real recording. Record sizes in `specs/014-demo-media-article/evidence/README.md` (research R-2).
- [ ] T005 [US1] Frame review of the GIF at 1 fps and of all stills (quickstart 1); note the result in the evidence README (SC-002).

**Checkpoint**: media can be regenerated with one command.

---

## Phase 3: User Story 2 — English article (P1)

- [ ] T006 [P] [US2] `scripts/media/check-articles.test.mjs` (vitest over fixtures: too short, missing section, relative link, broken link served by a local stub, forbidden credential pattern, private IP, `after` marker with `status: ready`) → fails; then implement `scripts/media/check-articles.mjs` (plan D-6).
- [ ] T007 [US2] Draft `docs/articles/en/sentaitask-orchestration.md` (plan D-5): sections, the GIF from `raw.githubusercontent.com`, absolute links to README anchors and specs, test counts from the latest evidence, contest name and voting dates, `<!-- after 012/013 merge -->` markers where those features appear. The checker passes with `status: draft`.
- [ ] T008 [US2] After 011–013 merge: remove the markers, refresh the numbers, set `status: ready`, and run the checker. A second team member reviews the claims against the merged README (checklist item).

---

## Phase 4: User Story 3 and 5 — Portuguese article, narration script (P2/P3)

- [ ] T009 [P] [US3] `docs/articles/pt-br/sentaitask-orquestracao.md`, adapted, same sections, media and links, plus a link to the English article (a placeholder until it is published, which the checker refuses at `status: ready`). The checker passes with `status: draft`.
- [ ] T010 [P] [US5] `docs/articles/video-script.md`: one row per scene of data-model §1 with start time, caption, EN narration, PT narration; the total fits the final video length.

---

## Phase 5: User Story 4 — Channels (P2)

- [ ] T011 [US4] README: replace `assets/sentai-run.png` (spec 011) with `assets/media/sentai-run.gif` in place, with an `alt` text describing the flow; run spec 011's `acceptance.sh --readme` (links and order still pass).
- [ ] T012 [US4] `docs/articles/publish-checklist.md` (quickstart 3), including "confirm the contest rules allow it" and "confirm with the user before any outward-facing action".
- [ ] T013 [US4] Team actions, each confirmed with the user first: upload the video; publish EN (target 2026-09-30) and PT (target 2026-10-01); paste the URLs into the README "Try it" block, both front matters and the Open Exchange description. Record the URLs and dates in the evidence README (SC-005).
- [ ] T014 On 2026-10-04 the team records the Open Exchange page views (SC-004) in the evidence README.

## Dependencies

- T001 → T002 → T003 → T004 → T005.
- T006 → T007 → T008; T008 waits for specs 011–013 to be merged.
- T009 and T010 can start after T007. T011 needs T004 and spec 011's README. T013 needs T005, T008,
  T009 and T011.
