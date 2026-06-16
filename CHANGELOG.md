# Changelog

All notable changes to this plugin are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [0.1.1] - 2026-06-16

### Fixed
- **ui-verify standalone mode**: clarified that the worker runs without a
  `run_id` (no harness files) — inputs read from the docs dir, output is only
  UI-VERIFY.md — to avoid orchestration-gate stalls when invoked directly.
- **playwright-verify install strategy**: switched from per-feature
  `npm init`/`node_modules` to a single Playwright install at the analysis root
  (shared `package.json` + root `playwright.config.ts` with
  `testMatch: **/playwright/verify-mock.spec.ts`). Each feature ships only
  `verify-mock.spec.ts`; screenshots go to its adjacent `images/`. Eliminates
  duplicate node_modules and root/feature config conflicts.

## [0.1.0] - 2026-06-12

Initial release. A cross-project code analysis + spec-verification toolkit,
decoupled from any single project via a per-project profile card.

### Added
- **Manifest & marketplace**: `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, MIT `LICENSE`.
- **Decoupling foundation**:
  - `analysis-conventions` skill (anti-hallucination rules, precise wording,
    diagram conventions, human-review-checklist format).
  - `analysis-init` skill (explores the project + interviews the user → writes
    `.analysis-profile.md`); defines the read-profile-else-auto-detect contract.
  - `templates/analysis-profile.template.md` (blank profile card) +
    `templates/examples/analysis-profile.example.md` (filled reference example).
- **Analysis skills (Layers 1–4)**: dependency-analysis, variable-list, erd,
  function-list, flowchart, business-rules, playwright-verify, sd, api-contract,
  batch-analysis, sa, sa-api, sa-batch.
- **Orchestration**: `analysis-orchestration` skill (document set, DAG, SA
  dispatch, run modes A/B/C with change-impact matrix) + `start-analysis`
  orchestrator agent (native subagent dispatch via the Task tool).
- **Verification**: `verify-spec` skill + 5 agents (verify-spec orchestrator,
  vspec-mock, vspec-static, vspec-e2e, vspec-report); three-layer comparison
  (mock ↔ real code ↔ SD) → `SD-review.md` with a `diff_rate`.
- **Worker agents**: deps, vars, erd, funcs, flow, rules, ui-verify, sd,
  api-contract, sa (each runs standalone or under the orchestrator).
- **Utility**: `md-to-pdf` skill + `templates/pdf-style.css` (CJK-friendly).
- **Harness templates**: run-state (`state.json`, `verify-state.json`), handoff
  templates, `runs.md` index, `SD-review-template.md`.
- **Tooling**: `scripts/validate-plugin.ps1` (manifest / frontmatter / skill
  references / no project-specific hardcoding).

### Notes
- 18 skills, 16 agents.
- The orchestration model uses native Claude subagents; prior bespoke
  keyboard-shortcut / crew features are intentionally not carried over.
