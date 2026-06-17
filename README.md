# code-analysis-package

A cross-project **reverse-engineering toolkit** for Claude Code, packaged as a
plugin. It produces layered analysis documents and verifies them against the
real code — for **any** codebase, not a single project.

It was distilled from a battle-tested analysis/verification toolkit for a large
enterprise codebase and **decoupled** so it works on any project through a
per-project **profile card** (`.analysis-profile.md`).

## How decoupling works

- The plugin ships **only the methodology** ("how to analyse").
- A **profile card** in each project supplies the **facts** (module/layer paths,
  tech stack, schema prefix, constant classes, output path, entry-point types).
- If no profile card exists, skills fall back to live auto-detection
  (reading `pom.xml` / `package.json` / scanning directories).

## Install

```bash
claude plugin marketplace add https://github.com/jin576tw/code-analysis-package
claude plugin install code-analysis-package@code-analysis-package
claude plugin list      # confirm it installed
```

## First-time use in a project

Run the onboarding step once per project. It explores the project, asks a few
questions, and writes `.analysis-profile.md` (the profile card) that every other
tool reads:

```
/analysis-init
```

## Run analysis / verification

```
# Full pipeline (orchestrator dispatches each worker in dependency order)
@start-analysis analyse <FeatureOrEntryPoint>

# A single layer on its own
/dependency-analysis
/erd
/flowchart

# Spec-vs-code verification (produces SD-review.md with a diff_rate)
@verify-spec verify <FeatureName>

# Convert any analysis doc to a styled PDF
/md-to-pdf
```

## What it produces

Layered analysis docs per analysed feature (output path comes from the profile
card §7; default `.analysis/docs/<MODULE>/<FEATURE>/<PAGE>/<FUNCTION>/`):

| Layer | Document | Skill | Applies |
|-------|----------|-------|---------|
| 1 | `DEPENDENCIES.md` | dependency-analysis | all |
| 2 | `VARIABLE-LIST.md` | variable-list | all |
| 2 | `ERD.md` | erd | all |
| 2 | `FUNCTION-LIST.md` | function-list | all |
| 3 | `FLOWCHART.md` | flowchart | all |
| 3 | `BUSINESS-RULES.md` | business-rules | all |
| 3.5 | `UI-VERIFY.md` + images | playwright-verify | UI only |
| 4a | `SD.md` | sd | all |
| 4b | `API-CONTRACT.md` | api-contract | WS/API only |
| 4b | `SA.md` | sa / sa-api / sa-batch | all (dispatch) |
| verify | `SD-review.md` | verify-spec | auto (post-sa) + on demand |

## Pipeline (DAG)

`start-analysis` runs the full pipeline end-to-end, including an automatic
verify phase after `sa`:

```
deps → (vars ‖ erd ‖ funcs) → flow → rules → [ui-verify: UI only]
     → sd → [api-contract: WS/API only] → sa
     → (vspec-mock ‖ vspec-e2e) → vspec-static → vspec-report   ← auto verify
```

`verify-spec` can also be triggered standalone to re-verify an existing
`SD.md` without re-running the full analysis pipeline:

```
verify-spec (standalone): init → (mock ‖ e2e) → static → report → diff_rate
```

**diff_rate gate** — when `diff_rate > 10%`:
- `start-analysis`: automatically applies the impact matrix to select mode B
  (≤3 stages affected) or mode A (full re-run), re-analyses once, then
  re-runs verify to measure the new `diff_rate`.
- `verify-spec` (standalone): lists the top differences and asks whether to
  re-enter `start-analysis` (code is the source of truth).

## Components

- **18 skills**: analysis-init, analysis-conventions, analysis-orchestration,
  dependency-analysis, variable-list, erd, function-list, flowchart,
  business-rules, playwright-verify, sd, api-contract, batch-analysis, sa,
  sa-api, sa-batch, verify-spec, md-to-pdf.
- **16 agents**: deps, vars, erd, funcs, flow, rules, ui-verify, sd,
  api-contract, sa, start-analysis (orchestrator), verify-spec (verify
  orchestrator), vspec-mock, vspec-static, vspec-e2e, vspec-report.
- **templates/**: `analysis-profile.template.md` (blank profile card),
  `examples/analysis-profile.example.md` (filled reference example),
  `harness/` (run-state + handoff + SD-review templates), `pdf-style.css`.

## Profile card

`.analysis-profile.md` records, per project: identity, build system & tech
stack, module/layer map (path globs), entry-point types, persistence
conventions (schema prefix, id strategy, transaction managers), naming/pitfalls,
output docs path, optional UI-verification config, glossary, and the harness
state dir. Start from `templates/analysis-profile.template.md` or run
`/analysis-init`. Never put secrets in the card — record only env-var names.

## Notes & limitations

- Install/usage commands follow the Claude Code CLI; exact UI varies by version.
- The full-pipeline orchestration uses native Claude subagents (the Task tool);
  behaviour differs from any prior bespoke crew runner.
- UI verification uses Mock HTML by default and does not touch a live
  environment unless the profile card §8 explicitly enables it.

## Validate (for contributors)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/validate-plugin.ps1
```
Checks manifest validity, agent/skill frontmatter, skill references, and absence
of project-specific hardcoding outside `templates/examples/`.

## License

MIT — see [LICENSE](LICENSE).
