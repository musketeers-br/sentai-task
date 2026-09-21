# Execution-Model Decision

**Feature**: 001-validate-async-job-contract
**Recorded**: 2026-09-20T23:45:18Z

## Decision

delegate parallel execution to the platform

## Rationale

Evidence for Q3: [evidence/06-integrity-check-start.json](evidence/06-integrity-check-start.json) — HTTP 202, Location: `/api/admin/v1/async-result?id=882998815990347262254421`.

Evidence for Q4: [evidence/07c-async-result-settled.json](evidence/07c-async-result-settled.json) — settled State=`Finished`, TimeQueued=`2026-09-20 23:44:56`, TimeStarted=`2026-09-20 23:44:56`, TimeFinished=`2026-09-20 23:45:17`; [evidence/08a-async-result-pause.json](evidence/08a-async-result-pause.json) (HTTP 200), [evidence/08b-async-result-resume.json](evidence/08b-async-result-resume.json) (HTTP 200), [evidence/08c-async-result-cancel.json](evidence/08c-async-result-cancel.json) (HTTP 200).

## Consequence

Q3 and Q4 both closed positively: the platform returns a job identifier for long-running operations (evidence/06-integrity-check-start.json, HTTP 202), and that identifier drives an observable execution state, timings, and cancel/pause/resume transitions (evidence/07c-async-result-settled.json, evidence/08a-async-result-pause.json, evidence/08b-async-result-resume.json, evidence/08c-async-result-cancel.json). The planned product scope stands: the product delegates parallel execution of maintenance operations to the platform's own async-job mechanism rather than building an execution engine inside the product.
