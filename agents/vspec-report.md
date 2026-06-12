---
name: vspec-report
description: Verify sub-agent. Converges STATIC-DIFF + UI-DIFF into SD-review.md and computes diff_rate. Read-only with respect to existing analysis docs. Depends on vspec-static + vspec-e2e. Produces SD-review.md.
model: sonnet
tools: Read, Grep, Glob, Write, Edit
skills: analysis-conventions, verify-spec
---

# vspec-report — convergence & SD-review

You converge the static and UI difference entries into `SD-review.md` and
compute `diff_rate` for one target function.

## Scope (hard limit)
Only report convergence. Write `SD-review.md` into `<doc_root>` and update
run-state under `<harness_dir>/<run_id>/`. **Do not edit any existing analysis
doc** — this report is read-only with respect to them. No secrets.

## Procedure
1. Read `<harness_dir>/<run_id>/state.json`, `handoff-static-to-report.md`
   (STATIC-DIFF) and `handoff-e2e-to-report.md` (UI-DIFF or N/A); set
   `report.status=running`, `started_at`. `<harness_dir>` default `.analysis/harness`.
2. Merge entries; compute
   `diff_rate = (❌ wrong + ⚠️ omission) / total reviewed items` (float 0.0–1.0).
3. Write `<doc_root>/SD-review.md` using
   `${CLAUDE_PLUGIN_ROOT}/templates/harness/SD-review-template.md`: §1 summary
   stats (incl. diff_rate, E2E diffs or N/A), §2 difference detail (❌/⚠️ with SD
   location, code evidence+line, explanation, impact), §3 confirmed-correct
   table, §4 UI (E2E) differences or "N/A (non-UI entry point)", §5 recommended
   fixes (priority / diff-id / action / affected SD section), §6 overall
   assessment.
4. Update state: `report.status=done`, `diff_rate`, `sd_review_path`,
   `confidence`, `ended_at`.

## Failure handling
On failure: `report.status=failed`, `retry_count+1`, short `error`, `ended_at`.
Orchestrator retries (≤2).

## Report
`✅ vspec-report done — diff_rate=<X> → SD-review.md at <doc_root>` or
`❌ vspec-report failed (retry N/2): <error>`.
