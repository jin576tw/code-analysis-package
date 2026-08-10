---
name: fast-analysis
description: Produce one output-contract-driven, SA-first code-analysis document with a compact evidence matrix and independent review. Use only for start-analysis --fast runs; do not generate the full profile's nine-document DAG or treat legacy fast artifacts as delivery-ready.
---

# Fast analysis

Build the requested target document directly from the output contract. Work backward from the
sections the final SA or integrated analysis must contain; collect only evidence needed to support
those sections. Do not create DEPENDENCIES, VARIABLE-LIST, ERD, FUNCTION-LIST, FLOWCHART,
BUSINESS-RULES, SD, API-CONTRACT, and AS-IS SA as separate deliverables.

## Contract

- Set `analysis_profile: fast`, `fast_schema: 2`, and `artifact_class: fast-v2`.
- Use `templates/fast-evidence.template.json` and `templates/fast-review.template.json`.
- Require the six evidence groups defined in `references/output-contract.md`.
- Keep `delivery_ready=false` until the independent reviewer returns `PASS` for the exact Maker
  and evidence fingerprints with `diff_rate <= 0.10`.
- Classify any earlier fast artifact without `fast_schema: 2` as `fast-legacy`; never upgrade its
  delivery status by relabelling it. Re-run the v2 Maker and Reviewer.

## Maker and Reviewer

Dispatch `fast-analysis-maker`, then `fast-analysis-reviewer`. They must be separate agents and
write disjoint artifacts. If review fails, dispatch the Maker once with the complete findings,
then run a complete Reviewer pass again. A second failure blocks the run; do not patch further.

The Maker writes only the integrated document and evidence matrix. The Reviewer never edits Maker
artifacts and writes only the review result.

## UI risk gate

Run `scripts/Get-UiRiskDecision.ps1` before the Maker closes evidence:

- `static_pass`: server-rendered behavior is fully supported by static source evidence.
- `playwright_required`: JavaScript, AJAX, browser download, layout, or other browser/runtime
  behavior exists and a runnable environment is available.
- `not_applicable`: target is not a UI.
- `blocked_runtime_evidence`: material runtime behavior needs confirmation but no usable runtime
  environment exists.

Mock output is `simulation` only. It may illustrate a scenario but must never set
`runtime_confirmed=true`, satisfy a required live-runtime finding, or clear
`blocked_runtime_evidence`.

## Completion

Run `scripts/Test-FastAnalysisContract.ps1` against the evidence and review. Complete only when it
returns `valid=true`, `classification=fast-v2`, and `delivery_ready=true`.
