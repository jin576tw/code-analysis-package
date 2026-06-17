---
name: verify-spec
description: Spec-vs-code verification. Checks an analysis SD.md against the real code via three-layer comparison (mock ↔ real code ↔ SD) plus optional dynamic UI verification, converging into SD-review.md with a diff_rate. Runs automatically as the final phase of start-analysis (after sa); also manually triggerable as a standalone verify-spec orchestrator.
---

# Verify Spec (SD ↔ code verification)

Verifies an analysed feature's `SD.md` against the actual code and produces
`SD-review.md` with a quantified `diff_rate`. Read-only with respect to existing
analysis docs — it reports differences, it does not silently edit them.

> **Invocation modes**:
> - **Automatic**: `start-analysis` runs this pipeline immediately after `sa` completes (§5.5–5.6 in the orchestrator). No separate trigger needed.
> - **Manual (standalone)**: invoke `verify-spec` directly when you want to re-verify an existing SD.md without re-running the full analysis pipeline.

> **Read the profile card** for the module/layer map and output path; auto-detect
> if absent. **Load skill `analysis-conventions`.** Requires an existing `SD.md`
> for the target function.

## Pipeline (mini-orchestrator)
```
init → [ mock ‖ e2e ] → static → report → diff_rate threshold post-processing
```
- **mock**: read SD.md and generate a code mock skeleton **faithful to the SD**
  (including any errors the SD describes) into the run's `mock/` dir. This makes
  the SD's claims executable/comparable. → handoff-mock-to-static.
- **e2e** (UI entry points only): dynamic UI verification via Playwright Mock
  HTML; otherwise skipped. → handoff-e2e-to-report (UI-DIFF entries).
- **static**: three-layer comparison — mock (A, = what SD says) ↔ real code (B)
  ↔ SD text (C). Each reviewed item is ✅ correct / ⚠️ omission (code has it, SD
  doesn't) / ❌ wrong (SD contradicts code). → handoff-static-to-report
  (STATIC-DIFF entries).
- **report**: converge STATIC-DIFF + UI-DIFF into `SD-review.md`; compute
  `diff_rate = (❌ wrong + ⚠️ omission) / total reviewed items`.

## diff_rate post-processing
- `diff_rate ≤ 0.10` → deliver the report only.
- `diff_rate > 0.10` → list the top differences and ask the user whether to
  re-enter `start-analysis` to regenerate docs (mode B for localised diffs,
  mode A if widespread). Code is the source of truth.

## SD-review.md structure
Use `${CLAUDE_PLUGIN_ROOT}/templates/harness/SD-review-template.md`:
§1 summary stats (totals, ✅/⚠️/❌ counts, **diff_rate**, E2E diffs or N/A),
§2 difference detail (❌ wrong / ⚠️ omission, each with SD location, SD text,
real-code snippet+line, explanation, impact), §3 confirmed-correct table,
§4 UI behaviour (E2E) differences (UI entry points only), §5 recommended fixes
(priority / diff-id / action / affected SD section), §6 overall assessment.

## Scope notes
- Static comparison does not cover: real external-system call behaviour, runtime
  data, environment-specific config.
- E2E UI verification (if run) uses Mock HTML by default — no live environment
  unless the profile §8 explicitly enables it.

## Self-check
- [ ] SD.md located for the target function.
- [ ] mock skeleton faithful to SD (errors included, not silently fixed).
- [ ] static comparison classifies every item ✅/⚠️/❌ with code evidence.
- [ ] e2e run only for UI entry points (else N/A).
- [ ] diff_rate computed by the formula; report does not edit existing docs.
- [ ] post-processing offers re-entry into start-analysis when diff_rate > 10%.
