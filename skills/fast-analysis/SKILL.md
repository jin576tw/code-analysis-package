---
name: fast-analysis
description: Produce one project-output-contract-driven code-analysis document by reusing the package's core collectors without materializing their individual documents, then run an independent review. Use only for start-analysis --fast runs with a contract; do not generate the Full profile's nine-document DAG or treat legacy Fast artifacts as delivery-ready.
---

# Fast analysis

Build the requested target document directly from a project-supplied output contract. Work backward
from its required sections and evidence requirements. Reuse the same dependency, symbol/data,
data-model, function, execution-flow, business-rule, UI-behavior, API-contract, and system-design
analysis methods used by Full, but keep their results inside the run-local evidence graph. Do not
materialize the Full profile's individual documents.

## Contract

- Set `analysis_profile: fast`, `fast_schema: 3`, and `artifact_class: fast-v3`.
- Require an external contract following `references/output-contract.md`; never infer project
  deliverable sections or evidence IDs in the package.
- Use `templates/fast-evidence.template.json` and `templates/fast-review.template.json`.
- Fingerprint the exact contract and copy its `contract_id` into the evidence artifact.
- Keep `delivery_ready=false` until the independent reviewer returns `PASS` for the exact target
  document, evidence, and contract fingerprints with `diff_rate <= 0.10`.
- Classify schema 2 as `fast-v2-legacy` and earlier/missing schemas as `fast-legacy`; never upgrade
  delivery status by relabelling. Re-run the v3 Maker and Reviewer with a project contract.

## Maker and Reviewer

Dispatch `fast-analysis-maker`, then `fast-analysis-reviewer`. They must be separate agents and
write disjoint artifacts. If review fails, dispatch the Maker once with the complete findings,
then run a complete Reviewer pass again. A second failure blocks the run; do not patch further.

The Maker writes only the contract-named target document and evidence graph. The Reviewer never
edits Maker artifacts and writes only the review result.

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

Run `scripts/Test-FastAnalysisContract.ps1` against the evidence, review, and exact output
contract. Complete only when it returns `valid=true`, `classification=fast-v3`, and
`delivery_ready=true`.
