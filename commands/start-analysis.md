---
description: Run project-contract-driven fast analysis or the full nine-document reverse-analysis DAG. Fast reuses core collectors without materializing their individual documents; Full preserves the established layered workflow. Playwright is risk-based in both profiles.
argument-hint: <FeatureOrEntryPoint> [--fast --output-contract <path> | --full] | --resume <run_id>
---

# /start-analysis

Target: `$ARGUMENTS`

If invoked as `--resume <run_id>`, locate that exact run below the profile's harness root and run
`scripts/Resume-AnalysisHandover.ps1`. Reject the resume unless its revision and
`resume_state_sha256` match both `state.json` and `next-session.json`. Read every returned
`read_paths` item, dispatch only the returned `pending_stages`, and never reset or rerun a completed
stage. `--resume` is Full-only; a Fast run must reject it because Fast remains one session.

Require one feature or confirmed entry point and exactly one profile flag. If the target is absent,
ask for it. If the profile flag is absent, ask; never infer Fast from time pressure.

Read `.analysis-profile.md`, `analysis-orchestration`, and `analysis-conventions`. Validate the
profile's relative paths, entry type, module mapping, docs root, and harness root. Preserve the
existing entry-confirmation and SCOPE human gates for both profiles.

## `--fast`: project output-contract run

Require `--output-contract <path>` or the profile's Fast output-contract path. Load
`fast-analysis`. Set `analysis_profile=fast`, `fast_schema=3`, and `artifact_class=fast-v3`.
Classify schema 2 as `fast-v2-legacy` and any earlier/missing schema as `fast-legacy`; neither is
delivery-ready and neither can be upgraded by changing metadata.

Create a run from the harness templates, but dispatch only:

1. `fast-analysis-maker` — read the project contract, select the existing core collectors needed
   by each evidence requirement, and write the contract-named target document plus
   `fast-evidence.json`. Collector results are evidence views, not separate deliverables.
2. UI risk gate — use `Get-UiRiskDecision.ps1`. Static evidence may close server-rendered UI.
   JavaScript, AJAX, browser download, layout, and other runtime behavior require Playwright when
   an environment is available. Material runtime behavior without an environment is
   `blocked_runtime_evidence`. Mock is simulation only.
3. `fast-analysis-reviewer` — independently review the complete document, evidence, contract, and
   literal sources; write only `fast-review.json` for the exact fingerprints.
4. If review fails, dispatch the Maker once with all findings, then run a new complete Reviewer
   pass. A second failure blocks the run.
5. Run `Test-FastAnalysisContract.ps1` with the exact output contract. Complete only when all
   required target sections and project-defined evidence requirements are covered, the selected
   core collectors are recorded, Reviewer verdict is PASS for current document/evidence/contract
   fingerprints, UI risk is closed, and `diff_rate <= 0.10`.

Fast must not create or advertise the nine full-profile AS-IS documents as intermediate
deliverables. Set `delivery_ready=true` only after the final contract validator passes.

## `--full`: established nine-document DAG

Run the Full workflow in `analysis-orchestration` without Fast restructuring:

`deps -> (vars || erd || funcs) -> flow -> rules -> ui-verify -> sd -> api-contract -> sa`

Keep all existing Full quality-score gates, repair caps, gap-report worksheets, state recovery,
verification, and summary behavior. The only policy change is risk-based Playwright:

- `not_applicable` for non-UI;
- `static_pass` when static code evidence fully supports the relevant UI claims;
- `playwright_required` for JavaScript/AJAX/download/layout/runtime behavior when runnable;
- `blocked_runtime_evidence` when material runtime behavior cannot be confirmed.

Static spec-vs-code verification remains required by the Full policy. Playwright and Mock are not
synonyms: Mock can demonstrate a simulation but cannot prove live runtime behavior.

### Full session checkpoints

Full is a deterministic multi-session workflow. A normal invocation owns entry confirmation and
the confirmed `scope` unit only. Each resume owns exactly one subsequent unit:

`scope -> deps -> layer2(vars/erd/funcs) -> flow -> rules -> ui-verify -> sd -> api-contract -> sa -> verify-evidence -> report-patch-finalize`

For every document unit, finish its quality repair and rescore loop in that same session. After a
unit and its gate are terminal, run `scripts/New-AnalysisHandover.ps1` with the completed and next
unit. It atomically writes `state.json`, `next-session.json`, and `next-session.md`; print the resume
command and stop. Do not dispatch the next unit in the current session. The final
`report-patch-finalize` unit writes the summary/runs index and completes without another handover.

If `api-contract` is not applicable, record its existing skipped status/gate and still close that
unit deterministically before handing over to `sa`. Quality repair/rescore never crosses a
checkpoint. Session/quota interruption before a terminal gate keeps the same unit resumable and
does not advance the checkpoint revision.

## Completion summary

Write the run summary and runs index atomically. Include profile, `fast_schema`/artifact class and
output-contract fingerprint when Fast, UI risk decision, Maker attempts, Reviewer fingerprint and
verdict, `diff_rate`, and `delivery_ready`. Never mark a waiting, blocked, stale-review, or
legacy-fast run complete.
