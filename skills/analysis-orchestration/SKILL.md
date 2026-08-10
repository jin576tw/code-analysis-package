---
name: analysis-orchestration
description: Orchestrate code-analysis runs, selecting either the established Full nine-document DAG or the fast_schema 2 output-contract-driven single-document Maker/Reviewer workflow. Enforces state, human gates, quality, UI-risk, review-fingerprint, and delivery-readiness contracts.
---

# Analysis orchestration

Read `.analysis-profile.md`. Reject placeholders, absolute paths, unconfirmed entry points, and an
unconfirmed SCOPE card. Store run paths relative to the repository. Update state, runs index, and
handoffs with whole-file read/modify/atomic-write behavior.

Profile and mode are independent: mode describes why analysis runs; profile selects the output
contract. Require an explicit `--full` or `--fast`.

## Shared gates

1. Confirm the real entry point from source and, for ticket-sourced work, attachments/screenshots.
2. Create `SCOPE.md` from the target, a bounded directed relation scan, and explicit boundaries;
   obtain human confirmation.
3. Initialize state and a runs-index row, then read the row back before dispatch.
4. On resume, validate source/artifact fingerprints. Reset interrupted `running` stages to pending
   without consuming a logical retry.
5. Never author worker-owned analysis in the orchestrator. Editorial changes explicitly named by
   a completed finding are allowed; new technical content returns to its Maker.
6. Treat session/quota limits as blocked, not failed. Never spend a repair attempt on them.

## Fast profile (`fast_schema: 2`)

Load `fast-analysis`. The output contract is one integrated target document, not the Full DAG.
Create only the Maker, UI-risk, Reviewer, and contract-validation stages.

### Evidence-driven Maker

Dispatch `fast-analysis-maker` with required target headings. It walks those headings backward to
the six evidence groups: scope/UC, flow/rules, screen/fields, API, interactions/transactions, and
data model/supplementary specifications. It writes the integrated document and evidence JSON with
`delivery_ready=false`.

Do not dispatch `deps`, `vars`, `erd`, `funcs`, `flow`, `rules`, `sd`, `api-contract`, or the
AS-IS `sa` agent in Fast. Those names may appear as coverage concepts inside the single document,
not as intermediate deliverables.

### Independent review and bounded repair

Dispatch `fast-analysis-reviewer` after Maker output is fingerprinted. PASS requires:

- `fast_schema == 2` and artifact class `fast-v2`;
- all required sections and evidence groups covered or evidenced N/A;
- current Maker and evidence SHA-256 values;
- no material blocked runtime evidence;
- `diff_rate <= 0.10`;
- review `delivery_ready=true` for the exact fingerprints.

On FAIL, send every finding to the Maker in one repair prompt, allow one repair, then run a full
Reviewer pass. Do not perform delta-only review. A second FAIL blocks the run.

An artifact without schema 2 is `fast-legacy`. It remains non-delivery-ready even if old metadata
says otherwise; rerun both v2 roles.

## Full profile

Preserve the established nine-document DAG and its output paths:

1. `deps`
2. `vars`, `erd`, `funcs` in parallel after deps
3. `flow`, then `rules`
4. `ui-verify` for UI risk decisions other than N/A/static pass
5. `sd`
6. `api-contract` for API/WS entries
7. `sa`
8. spec-vs-code static report and patch stages

Every document-producing stage still receives an independent `quality-score` decision. Layer 2
is scored as one batch but decided per document.

### Full quality gate

Use the established mechanical derivation:

1. Missing/invalid score: retry scorer once, then `failed_local`.
2. Any wrong-entry/API/table/main-flow flag, completeness below 4, or score below 6:
   `failed_structural`; require the gap-report worksheet and human decision.
3. Score at least 9: `passed`.
4. Otherwise repair from scorer actions and rescore. Cap one repair for Layer 2 and two elsewhere.
5. If the cap ends at 6–9 with no structural flag, record `tech_debt_accepted` and continue to the
   static verification backstop. If structural risk remains, stop.

Stop the strategy when cumulative scoring reaches four rounds or fails to improve twice. Require a
human choice: accept recorded risk, change strategy, or abandon. An accepted risk is not a pass.

### Full gap worksheet

Before any structural stop, require a table containing question, blocking evidence, required human
input, affected documents, and decision. Roll it into `_pending/human-review-queue.md`. Do not
resume until every decision cell is completed; corrections route to the owning Maker.

## Risk-based Playwright for both profiles

Classify each target with `Get-UiRiskDecision.ps1` or the equivalent four-value contract:

| Decision | Action |
|---|---|
| `not_applicable` | Skip Playwright for non-UI entries. |
| `static_pass` | Record static citations; skip Playwright. |
| `playwright_required` | Run Playwright against a real runnable environment and retain results. |
| `blocked_runtime_evidence` | Stop when the missing runtime fact is material. |

JavaScript, AJAX/partial updates, browser downloads, layout/responsive behavior, dialogs, timers,
and other browser-only behavior are runtime signals. A server-rendered page with deterministic
bindings may static-pass. Mock HTML/spec/screenshots are labelled `simulation`; they may aid design
or test planning but never set runtime-confirmed or clear a runtime blocker.

Static code/spec comparison remains separate from Playwright and may run even when Playwright is
skipped. Do not call a Mock comparison runtime evidence.

## State and summary

The state template carries `fast_schema`, `artifact_class`, `delivery_ready`, `ui_risk_decision`,
Maker attempts, and Reviewer fingerprints. For Full these Fast-only fields are null. For Fast use
schema 2 values and only Fast stages.

Summaries and `runs.md` must report profile, classification, UI decision, diff rate, review status,
and delivery readiness. A Fast run is done only after `Test-FastAnalysisContract.ps1` returns a
valid, delivery-ready `fast-v2` result. Full completion continues to use the established quality
and static verification gates.
