# Quickstart — acceptance walkthrough

Feature: `001-flow-orchestrator` · Date: 2026-09-21

Run this against a dev IRIS instance. It is the ten acceptance scenarios from `spec.md`
turned into a sequence you can actually perform, and it is what "done" means for this
feature. Every step names the requirement it proves.

---

## Prerequisites

- IRIS 2024.1+ with namespaces `USER`, `SAMPLES`, `DOCBOOK` and `%SYS`
- An account holding `%Admin_Task:USE`
- The `SENTAI` package compiled into `%SYS`
- The front end served at `/csp/sentai/`
- `DOCBOOK` deliberately mounted **read-only** — the walkthrough needs a step that fails

```bash
# backend
iris session IRIS -U %SYS '##class(SENTAI.Install).Setup()'

# frontend
cd frontend && npm ci && npm run dev
```

---

## 1 · Compose the wave — *FR-001, FR-002*

1. Open `/flows/new`. Confirm the dark theme is active by default *(FR-037)*.
2. From the palette's **VERIFICATION** group, drag `Integrity check` onto the canvas
   three times.
3. Set each one's namespace and database directory to `USER`, `SAMPLES`, `DOCBOOK`.
4. Drag `Purge audit records` from **PURGE**, and `Switch journal` from **JOURNAL**.

✅ Status bar reads `5 steps · 0 joins · 1 destructive`
✅ The purge node carries a hazard band on sight, before any configuration *(FR-011)*

## 2 · Wire the fan-in — *FR-004, scenario 2*

5. Connect the output handle of `#01`, `#02` and `#03` each to the input handle of `#04`.

✅ The three edges render at 2.5 px and converge into **one** diamond junction
✅ `#04`'s input handle is now a diamond, not a square
✅ `#04` shows `join: waits for #01 #02 #03`
✅ Status bar reads `5 steps · 1 join · 1 destructive`

6. Connect `#04` → `#05`.

✅ That edge renders at 1.5 px with a plain arrowhead — visibly different from the join

7. Try to connect `#05` → `#01`.

✅ Rejected, with a message naming the cycle *(FR-003)*

## 3 · Precondition warning — *FR-008, scenario 3*

8. Press **Validate flow**.

✅ `#03` shows an inset warning panel: **Precondition not met**, naming the read-only
mount and what the step needs
✅ Status bar reads `1 precondition not met (#03)`
✅ **Schedule in Task Manager** is still enabled — a warning does not block *(FR-010)*

## 4 · Destructive configuration — *Constitution I, scenario 4*

9. Select `#04`. Inspect the `DESTRUCTIVE STEP` block.

✅ Hazard band, `DESTRUCTIVE` text seal, and a checked "require the database name to be
typed before running" — all three present
✅ The consequence is spelled out in words, including that there is no rollback
✅ Attempt to clear `isDestructive` through the API → rejected; it is derived from the
step type

10. Set `DaysToKeep` to `30`, timeout `20`, WQM category `SENTAI.NIGHT`.

✅ `OUTPUT` shows where the GUID will land: `step04.guid → ^SentaiRun(runId,"04")`

## 5 · Theme parity — *FR-037, UI-007*

11. Switch to **Light**.

✅ Identical structure, identical strings, identical graph
✅ The canvas is now the **lightest** surface; in dark it was the darkest
✅ Selection is a border plus shadow, not a glow
✅ Run the token guard: no light value equals the inverse of its dark counterpart

12. Switch back to **Dark**.

## 6 · Schedule — *FR-014, scenario 5*

13. Press **Schedule in Task Manager**, spec `WEEKLY SAT 03:00`.

✅ Five native `%SYS.Task` rows exist — verify in the **Management Portal**, not only in
SentaiTask *(Constitution V)*
✅ They carry the flow id, revision, step id and join inputs as task properties
✅ The flow appears in `/catalog` with its next run

## 7 · Configure the WQM category — *FR-015…017, scenario 10*

14. Open `/wqm/SENTAI.NIGHT`.

✅ Four nested bars in descending order, values 32 / 16 / 8 / 4
✅ The sentence beneath reads the configuration back against this flow: three parallel
integrity checks asking 4 workers each, 12 total, 8 active

15. Change `MaxActiveWorkers` to `12`.

✅ Diagram and sentence both recompute
✅ The impact notice states how many other scheduled tasks are affected **and** that runs
in flight keep their original ceilings

16. Change `MaxWorkers` to `4` (below `MaxActiveWorkers`).

✅ Validation **error**, not a warning; save is blocked

17. Restore, save.

## 8 · Dispatch and watch — *FR-018…027, scenarios 6 and 7*

18. Press **Dispatch now**.

✅ A typed-confirmation prompt appears for `#04` and names the affected database
✅ Type it; the run log records who confirmed, and when *(FR-013)*
✅ The call returns a run GUID **synchronously**
✅ Query `^SentaiRun` — every step already has a GUID and a `TimeQueued`, before anything
started *(Constitution III, R-004)*

19. Land on `/runs/[guid]`.

✅ Wave progress bar: one segment per step, plus `2 completed · 1 failed · 1 running ·
1 queued`-style counts as the run proceeds
✅ `#01` and `#02` reach `completed` with durations
✅ `#03` reaches `failed`, showing its `FailureReason` **verbatim** — an `ERROR #5002
<PROTECT>` string, not a paraphrase *(FR-022)*
✅ The edge from `#03` renders dashed in the failure token
✅ Because an input failed, the **JOIN POLICY** panel is visible and states the policy in
force *(FR-025)*
✅ `#04` runs, showing elapsed time, progress with literal counts, its GUID, and per-step
*Pause* and *Cancel*
✅ The state key `STATES — SHAPE BEFORE COLOUR` is permanently visible, not a tooltip
✅ State reaches the screen within 2 s of the change *(NFR-001)*

20. Press *Cancel* on `#04` only.

✅ `#04` → `cancelled`; `#05` is unaffected and stays `queued` *(scenario 7)*
✅ The wave is not cancelled

21. Grayscale the window (macOS: Display filters, or a browser extension).

✅ All six state shapes remain mutually distinguishable *(Constitution II)*

## 9 · Run history — *FR-032…036, scenario 8*

22. Open `/runs/[guid]/history`.

✅ One bar per step, all on one shared axis
✅ Each bar splits into a hatched `TimeQueued → TimeStarted` and a solid
`TimeStarted → TimeFinished`
✅ `#01`, `#02`, `#03` start at the same x — parallelism is visible without reading
numbers
✅ A vertical rule with a diamond marks when the join resolved — the same diamond the
canvas uses
✅ `TOTAL DURATION` and `SUM OF STEPS` are both shown and differ; neither is collapsed
into a percentage *(Constitution VIII)*
✅ The 41-second failure's label sits outside its bar, untruncated

## 10 · Catalog — *FR-028…031, scenario 9*

23. Open `/catalog`.

✅ Tasks SentaiTask did **not** create are listed too *(FR-028)*
✅ Every row carries both a state shape (column 1) and the state word (column 6)
✅ Destructive tasks carry their `DESTRUCTIVE` chip inline
✅ Numeric columns align digit under digit *(Constitution VII)*

24. Type `integrity`, pick namespace `USER`.

✅ Filters in under 150 ms *(NFR-003)*

25. Select a row.

✅ The detail pane opens **without** clearing search or namespace *(FR-030)*
✅ The full run GUID is shown unabbreviated, and is selectable
✅ `PRIVILEGE` reads `%Admin_Task:USE`

26. Press *View run history* → lands on the timeline for that run.

## 11 · Degradation — *NFR-006*

27. Stop the IRIS instance while `/runs/[guid]` is open.

✅ The UI switches to read-only with an explicit banner
✅ It does **not** keep showing the last state as if it were live

---

## Non-functional sweep

| Check | Target | How |
|---|---|---|
| Canvas performance | ≥30 fps at 200 nodes | Generate a 200-node flow; record a pan in DevTools |
| Catalog filter | <150 ms over 5 000 rows | Seed 5 000 tasks; measure keystroke → paint |
| Live latency | <2 s | Timestamp a state change server-side; compare to paint |
| Keyboard | Every control reachable, visible focus ring | Tab the whole of each screen, in both themes |
| Contrast | ≥4.5:1 (≥3:1 at ≥24 px) | Automated pass over every text node, both themes |
| Both-theme visual | Structure + strings + shapes | `npm run test:visual` |

---

## Definition of done

Every ✅ above passes, in both themes, with the constitution check in `plan.md` still
reading PASS on all eight principles.
