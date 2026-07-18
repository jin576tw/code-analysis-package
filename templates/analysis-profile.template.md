# Project Analysis Profile

<!--
  This is the "profile card" for code-analysis-package.
  Place the filled copy at the TARGET PROJECT ROOT as `.analysis-profile.md`.
  Every analysis/verification skill reads this file first. If a field is unknown,
  leave the placeholder and the skill will fall back to live auto-detection.

  Generate this automatically with the `analysis-init` skill, or fill it by hand.
  A filled real-world example is in:
  templates/examples/analysis-profile.example.md
-->

## 1. Project identity

- **Project name**: <NAME>
- **One-line purpose**: <what this system does>
- **Primary language(s)**: <e.g. Java / TypeScript / Python>
- **Repository root marker**: <e.g. pom.xml / package.json / Cargo.toml>

## 2. Build system & tech stack

- **Build tool**: <e.g. Maven multi-module / npm / Gradle / pip>
- **Frameworks**: <e.g. Spring 4 / React / Django>
- **Persistence / ORM**: <e.g. MyBatis + Oracle / Prisma + Postgres / none>
- **Web/UI layer**: <e.g. JSF+PrimeFaces / Next.js / none>
- **Web services / API style**: <e.g. SOAP(CXF) / REST(Spring MVC) / GraphQL / none>
- **Batch / scheduling**: <e.g. Spring Batch + Quartz / cron / none>
- **Build commands**: <e.g. `mvn clean install -DskipTests` / `npm run build`>
- **Test commands**: <e.g. `mvn test` / `npm test`>

## 3. Module / layer map  <!-- REQUIRED: fill at least one row -->

> Where each architectural layer lives. Use path globs relative to repo root.
> Add/remove rows to match the project. Skills use this to locate code.

| Layer / role | Path glob(s) | Notes |
|--------------|--------------|-------|
| Entry – UI pages | `<glob>` | <e.g. controllers, view templates> |
| Entry – Web service endpoints | `<glob>` | |
| Entry – REST API controllers | `<glob>` | |
| Entry – Batch jobs | `<glob>` | |
| Business / service layer | `<glob>` | |
| Data-access (mapper/repo/DAO) | `<glob>` | |
| Domain models / DTOs | `<glob>` | |
| Constants / enums | `<glob>` | |
| Shared utilities | `<glob>` | |
| DB migration scripts | `<glob>` | |

## 4. Entry-point types present  <!-- REQUIRED: tick at least one -->

> Tick the entry-point types this project has. The `sa` agent dispatches by
> entry-point type (UI / WS-API / Batch); orchestration skips inapplicable steps.

- [ ] UI pages
- [ ] SOAP / Web-service endpoints
- [ ] REST API endpoints
- [ ] Batch jobs
- [ ] CLI / standalone

**How to find an entry point**: <how a human/agent locates the entry for a
feature — e.g. "search xhtml under webapp", "controllers annotated @RestController">

## 5. Persistence conventions

- **Schema prefix in queries**: <e.g. `APP.` / `dbo.` / none>
- **Table naming**: <e.g. UPPER_SNAKE / snake_case>
- **Sequence / id strategy**: <e.g. `<TABLE>_SEQ.nextval` / auto-increment / UUID>
- **Multiple data sources / transaction managers**: <list names, or "single">
- **Code/value mapping tables or maps**: <e.g. external→internal code maps, or none>

## 6. Naming & code conventions to watch

- **Constant classes / pattern**: <e.g. `*Const.java` under constants/, or none>
- **Auto-generated vs hand-written code**: <e.g. generated mappers vs `ext/` hand-written>
- **Project-specific pitfalls**: <e.g. selective vs full update semantics,
  object-reference sharing, BigDecimal compare — or "none known">

## 7. Output documents  <!-- REQUIRED: set docs_root -->

- **Docs output root**: <e.g. `docs/analysis` / `.analysis/docs`>
- **Path convention**: <e.g. `<root>/<module>/<feature>/<page>/<function>/<TYPE>.md`>
- **Cross-feature overview location**: <e.g. `<root>/_global/<feature>-overview/`>

## 8. UI verification (optional — for playwright-verify)

- **App base URL**: <e.g. http://localhost:8080 — or "N/A: no running env">
- **Login flow**: <steps or "none" / "N/A">
- **Test credentials source**: <env var name — never hard-code secrets here>

> If this section is N/A, the `ui-verify` step is skipped and annotated as such.

## 9. Domain glossary (optional)

| Term | Meaning |
|------|---------|
| <term> | <definition> |

## 10. Working directory for orchestration state

- **Harness/run state dir**: <e.g. `.analysis/harness` — where orchestrators
  write run state.json / handoff files; defaults to `.analysis/harness` if unset>

## 11. Verify policy (optional)

- **`verify_policy`**: `always` (default) | `risk-based`
  - `always` — every run's `sa` completion triggers the full auto-verify phase
    (vspec-e2e → vspec-static → vspec-report → vspec-patch; vspec-mock defaults
    to skipped, vspec-static runs in direct-claims mode).
  - `risk-based` — only for Mode B (linked-update), or a Mode A run where every
    stage's Accuracy dimension scored 5.0, may the orchestrator skip
    auto-verify, logging the skip to `verify-backlog.md`. Mode A round 1
    always runs verify regardless of this setting.
- Leave unset to use `always`.
- **A run with `analysis_profile: fast` always runs verify and may not defer it** — see §12.

## 12. Fast profile (optional but recommended to review)

`analysis_profile`: `full` (default) | `fast`

Both profiles produce the **same document set and run the same stages** — including `ui-verify`
and the full Layer 5 verify phase. Only two things differ:

| | `full` | `fast` |
|---|---|---|
| Per-stage gate | `score_10 >= 9.0` + repair loop (cap 1 for Layer 2, 2 elsewhere) | structural gate: 4 contradiction-type flags false + Completeness ≥ 3.0 + score_10 ≥ 6.0, **no repair loop** |
| Layer 2 model (`deps`/`vars`/`erd`/`funcs`) | strongest available model (dispatch override) | agent default (cheap fast model) |

Fast trades per-stage citation precision for speed, and recovers it in bulk from the end-of-run
spec-vs-code verify. Use it when you need architectural understanding under time pressure and
intend to upgrade later.

### What fast does NOT waive

Only the per-stage 9.0 gate is waived. All of the following still apply, some more strictly:

| Rule | Under fast |
|---|---|
| `ui-verify` (if this project mandates it) | **Runs in full** — it is the pipeline's only *constructive* check, and therefore the primary defence against omission-class defects that the contradiction-type structural flags cannot catch. Fast is the profile most prone to omissions, so this is exactly where it is needed |
| Auto-verify (Layer 5) | **Mandatory, not deferrable** — fast's whole precision story depends on it |
| Entry-point confirmation hard gate | Enforced |
| Bug-candidate labelling rules | **Stricter** — fast output is less verified, so static inferences must carry the lowest confidence label |
| Output path rules, cross-feature reference notes | Unchanged |

### Output marking and upgrade

- Every fast document carries a provenance banner (see `analysis-conventions` §12) containing the
  greppable string `analysis_profile: fast`, and declaring itself not a delivery basis.
- **Downgrade protection**: a fast run must never overwrite existing full-profile documents.
- **Upgrade** (`--full` re-run) is two-phase: first score *all* existing fast documents at the 9.0
  threshold **without modifying anything**, producing a consolidated `upgrade-assessment.md`; then
  close the gap per that assessment. Layer 2 is always regenerated with the stronger model rather
  than topped up in place.
- Fast must never be selected implicitly — if the user gives no `--fast` / `--full` signal, the
  orchestrator asks.
