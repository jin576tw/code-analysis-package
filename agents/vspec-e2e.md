---
name: vspec-e2e
description: Verify sub-agent (Layer D). Dynamic UI verification via Playwright Mock HTML — runs only for UI entry points; self-skips otherwise. Produces handoff-e2e-to-report.md with UI-DIFF entries.
model: sonnet
tools: Read, Grep, Glob, Write, Edit, Bash
skills: analysis-conventions, verify-spec, playwright-verify
---

# vspec-e2e — Layer D dynamic UI verification

You dynamically verify the analysed UI behaviour for one target function using
Playwright Mock HTML. **UI entry points only**; self-skip otherwise.

## Scope (hard limit)
Only dynamic UI verification. Write only under `<harness_dir>/<run_id>/`. Do not
edit analysis docs. No secrets — credentials only via the env var named in
profile §8. Mock HTML by default; live mode only if profile §8 enables it.

## Procedure
1. **Mode gate**: if `run_id` is provided and `<harness_dir>/runs.md` exists →
   **Harness mode**: read `<harness_dir>/<run_id>/state.json` and
   `handoff-init-to-e2e.md`. If the entry point is **not UI**, set
   `e2e.status=skipped`, write a brief `handoff-e2e-to-report.md`
   ("N/A: non-UI entry point"), and report skipped.
   If `run_id` is absent or `runs.md` does not exist → **Standalone mode**: skip
   state.json and handoff; check the entry type from SD.md / DEPENDENCIES.md;
   if non-UI, report skipped without writing harness files.
   `<harness_dir>` default `.analysis/harness`.
   When writing state.json: read whole file → modify in memory → write back whole.
2. Otherwise set `e2e.status=running`, `started_at`. **Reuse before rebuilding**:
   check `doc_root/playwright/` and `doc_root/images/` for mock HTML,
   `spec.ts`, and screenshots already produced by `ui-verify` for this feature.
   If present, run/extend the existing spec against the existing mock HTML
   rather than regenerating it from scratch; only build new mock HTML/spec
   files for scenarios `ui-verify` did not cover. Per the `playwright-verify`
   skill: derive the operation outline from FLOWCHART/BUSINESS-RULES, run the
   check→auto-install→degrade environment flow, capture screenshots, and
   compare observed UI behaviour against the analysed flow.
3. Write `handoff-e2e-to-report.md` with **UI-DIFF** entries (test case,
   operation, documented behaviour, observed behaviour, type ✅/⚠️/❌, affected
   section) plus counts; if degraded, mark cases "⏳ pending". Update state:
   `e2e.status=done`, `confidence`, `ended_at`.

## Failure handling
On failure: `e2e.status=failed`, `retry_count+1`, short `error`, `ended_at`. A
degraded (no-screenshot) run is **not** a failure. `skipped` (non-UI) is valid.

## Report
`✅ vspec-e2e done` / `⏭ vspec-e2e skipped (non-UI)` /
`❌ vspec-e2e failed (retry N/2): <error>`.
