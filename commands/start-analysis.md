---
description: Run output-contract-driven fast analysis or the full nine-document reverse-analysis DAG. Fast produces one integrated SA-first document with independent review; Full preserves the established layered workflow. Playwright is risk-based in both profiles.
argument-hint: <FeatureOrEntryPoint> [--fast | --full]
---

# /start-analysis

Target: `$ARGUMENTS`

Require one feature or confirmed entry point and exactly one profile flag. If the target is absent,
ask for it. If the profile flag is absent, ask; never infer Fast from time pressure.

Read `.analysis-profile.md`, `analysis-orchestration`, and `analysis-conventions`. Validate the
profile's relative paths, entry type, module mapping, docs root, and harness root. Preserve the
existing entry-confirmation and SCOPE human gates for both profiles.

## `--fast`: output-contract-driven SA-first run

Load `fast-analysis`. Set `analysis_profile=fast`, `fast_schema=2`, and
`artifact_class=fast-v2`. Classify any pre-v2 fast artifact as `fast-legacy`; it is never
delivery-ready and cannot be upgraded by changing metadata.

Create a run from the harness templates, but dispatch only:

1. `fast-analysis-maker` — write one integrated target document plus `fast-evidence.json` by
   working backward from the target document's required sections and six evidence groups.
2. UI risk gate — use `Get-UiRiskDecision.ps1`. Static evidence may close server-rendered UI.
   JavaScript, AJAX, browser download, layout, and other runtime behavior require Playwright when
   an environment is available. Material runtime behavior without an environment is
   `blocked_runtime_evidence`. Mock is simulation only.
3. `fast-analysis-reviewer` — independently review the complete document and evidence; write only
   `fast-review.json` for the exact fingerprints.
4. If review fails, dispatch the Maker once with all findings, then run a new complete Reviewer
   pass. A second failure blocks the run.
5. Run `Test-FastAnalysisContract.ps1`. Complete only when all target sections and evidence groups
   are covered, Reviewer verdict is PASS for current fingerprints, UI risk is closed, and
   `diff_rate <= 0.10`.

Fast must not create or advertise the nine full-profile AS-IS documents as intermediate
deliverables. Set `delivery_ready=true` only after the final contract validator passes.

## `--full`: established nine-document DAG

Run the Full workflow in `analysis-orchestration` without SA-first restructuring:

`deps -> (vars || erd || funcs) -> flow -> rules -> ui-verify -> sd -> api-contract -> sa`

Keep all existing Full quality-score gates, repair caps, gap-report worksheets, state recovery,
verification, and summary behavior. The only policy change is risk-based Playwright:

- `not_applicable` for non-UI;
- `static_pass` when static code evidence fully supports the relevant UI claims;
- `playwright_required` for JavaScript/AJAX/download/layout/runtime behavior when runnable;
- `blocked_runtime_evidence` when material runtime behavior cannot be confirmed.

Static spec-vs-code verification remains required by the Full policy. Playwright and Mock are not
synonyms: Mock can demonstrate a simulation but cannot prove live runtime behavior.

## Completion summary

Write the run summary and runs index atomically. Include profile, `fast_schema`/artifact class when
Fast, UI risk decision, Maker attempts, Reviewer fingerprint and verdict, `diff_rate`, and
`delivery_ready`. Never mark a waiting, blocked, stale-review, or legacy-fast run complete.
