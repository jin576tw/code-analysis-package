---
name: analysis-orchestration
description: The full code-documentation pipeline. Describes the document set, the layered DAG, SA dispatch rules, output-path determination, the two analysis profiles (full / fast) with their separate quality-gate derivations and convergence circuit breaker, and the three run modes (reverse-analysis / linked-update / cross-feature overview) with the change-impact matrix. Used by the start-analysis orchestrator agent.
---

# Analysis Orchestration

End-to-end pipeline that produces up to 10 analysis documents for a feature.

> **Read the profile card first** (`${CLAUDE_PROJECT_DIR}/.analysis-profile.md`)
> for the module/layer map, entry-point types, output path (§7) and harness dir
> (§10). If absent, run `analysis-init` first (or auto-detect). **Load skill
> `analysis-conventions`.**

## Analysis profile (`full` | `fast`)

Every run carries an `analysis_profile`, stored at run level in `state.json`. It is
**orthogonal to the run mode** (A/B/C) — mode says *why* you are analysing, profile says *how
strictly each stage is gated*. Any mode can run under either profile.

**What is identical between the two profiles** — everything except the two rows marked below:

| | `full` | `fast` |
|---|---|---|
| Document set | all 10 | **same** |
| DAG and stage order | full DAG | **same** |
| `ui-verify` (Layer 3.5) | runs | **runs — never skipped** |
| Layer 5 auto-verify (e2e/static/report/patch) | runs | **runs — never skipped** |
| Entry-point confirmation hard gate | enforced | **enforced** |
| **Per-stage gate** | `score_10 >= 9.0` + repair loop | **structural gate, no repair loop** |
| **Layer 2 model** (`deps`/`vars`/`erd`/`funcs`) | strongest available model | cheapest capable model |

A fast run produces the same artefacts; it simply does not grind each stage to citation-level
precision before moving on. Precision is instead recovered in bulk by the end-of-run
spec-vs-code verify (`vspec-static` → `vspec-report` → `vspec-patch`).

**Why the end-of-run verify can substitute for per-stage repair**: `quality-score` samples ≥8
claims per round and fixes what the sample caught — repeat rounds keep surfacing fresh instances
of the same defect class in unsampled locations, so scores can oscillate for many rounds without
converging. `vspec-static` in direct-claims mode extracts **every** verifiable claim from SD.md
and its sibling docs and checks each against source, and `vspec-patch` writes the corrections
back in one batch under the existing patch-first rule (`diff_rate > 0` always patches).
Systematic sweep + batch fix beats sampling + one-at-a-time fix.

> Because the whole quality argument rests on it, **a fast run's Layer 5 phase must not be
> skipped**, not even on user request. If the user wants to defer verify, they want a full run.

**Why `ui-verify` is never dropped from fast**: it is the only *constructive* check in the
pipeline — every other check reads the document and compares it to source, whereas `ui-verify`
requires the screen to be **built**, and a state you never noticed is a state you cannot mock.
That makes it the primary defence against omission-class defects, which the structural flags
provably cannot catch (see the Fast-profile gate derivation below). It is also the
highest-bandwidth artefact for a reader trying to understand a feature quickly, and its token
cost is that of an ordinary stage (screenshots are Playwright output, not model output).

**Layer 2 model selection**: `deps`/`vars`/`erd`/`funcs` are the pipeline's catalogue stages and
are commonly configured to a cheap fast model. That is appropriate under `fast`, whose structural
gate such a model can clear — but under `full` a weak model can make `score_10 >= 9.0`
effectively **unreachable**, turning the repair loop into a guaranteed spin. Under `full`,
dispatch these four with an explicit model override to the strongest model available for the
project rather than relying on the agent's frontmatter default. Do not edit the agents'
frontmatter to achieve this; override at dispatch so standalone invocation is unaffected.

**Choosing the profile** — `fast` is a deliberate, risk-bearing downgrade and must never be
selected implicitly:
- explicit signal in the request (`--fast` / `--full`) → use it
- no signal → **stop and ask the user**, presenting the cost/quality trade-off. Do not guess.

**Marking**: every document a fast run produces carries the provenance banner defined in
`analysis-conventions` §12, containing the literal string `analysis_profile: fast`. The banner
lives in the document body — not only in `state.json` — because harness state is deleted by the
7-day cleanup while the documents live on in the docs repo.

**Downgrade protection**: before a fast run writes a stage's document, check whether a document
already exists at that path *without* a fast banner. If so, mark the stage `skipped` with
`error: "downgrade-protected: full-profile doc exists"` and tell the user a full analysis is
already available. A fast run must never overwrite full-profile work.

## §11 Dual-pass override (profile card §11 present)

When the profile card contains a **§11** section defining a dual-pass protocol,
execute the full 10-document pipeline **twice** instead of once:

**Pass 1 — frontend tier** (parameters from §11):
- Scope: frontend entry points (e.g. `adp-gi-ui/pages/**`) + components/mixins/store
- SA skill: `sa` (UI general)
- Output path: append `/frontend/` subdirectory to the §7 path convention
- Do NOT produce API-CONTRACT

**Pass 2 — backend tier**:
- Entry point: API endpoints discovered at Pass 1 exit boundary
- Scope: backend service (e.g. `adp-policy/`)
- SA skill: `sa-api`
- Output path: append `/backend/` subdirectory to the §7 path convention
- MUST produce API-CONTRACT

Execution order: complete Pass 1 fully before starting Pass 2.
Pass 1 endpoint list (from `this.$axios.$get/$post('...')` calls) is Pass 2's entry input.

If §11 is absent in the profile card, use the standard single-pass pipeline below.

## Document set (max 10)

| # | Document | Skill | Layer | Applies |
|---|----------|-------|-------|---------|
| ① | DEPENDENCIES.md | dependency-analysis | 1 | all |
| ② | VARIABLE-LIST.md | variable-list | 2 | all |
| ③ | ERD.md | erd | 2 | all |
| ④ | FUNCTION-LIST.md | function-list | 2 | all |
| ⑤ | FLOWCHART.md | flowchart | 3 | all |
| ⑥ | BUSINESS-RULES.md | business-rules | 3 | all |
| ⑤.5 | UI-VERIFY.md + images/ | playwright-verify | 3.5 | UI entry points |
| ⑦ | SD.md | sd | 4a | all |
| ⑧a | API-CONTRACT.md | api-contract | 4b | WS/API only |
| ⑧b | SA.md | sa / sa-api / sa-batch | 4b | all (dispatch) |

## SA dispatch rules
| Entry-point type | SA skill |
|------------------|----------|
| Web-service / REST endpoint | sa-api |
| UI page / UI-triggered batch | sa |
| Pure batch (no UI) | sa-batch |

## Output-path determination
`<docs_root>/<MODULE>/<FEATURE>/[<PAGE>/][<SUB_PAGE>/].../<tier>/<TYPE>.md`

**PATH DERIVATION — must mirror actual UI/entry structure, never invented,
never flattened with a separator:**
1. `<MODULE>` = the top-level menu/module name; `<FEATURE>` = the sub-menu or
   screen title — both read from the project's actual navigation/routing
   source (layout/menu config, route definitions, or controller mapping).
2. Each further drill-in level (Tab, sub-Tab, drill-in page) becomes its **own
   nested folder**, one per actual UI level, in real navigation order. **Do
   not** flatten multiple levels into one folder name with a separator (e.g.
   `Parent-Child` is wrong; `Parent/Child/` is correct).
3. The path has as many nested levels as the UI actually has — not a fixed
   count. `<tier>` (`frontend`/`backend`) is always the last segment, never
   omitted.
4. When the leaf level equals the FEATURE itself (no further drill-in), merge
   into one level; do not add an empty extra sub-dir.

Cross-feature overviews go under `<docs_root>/_global/<feature>-overview/` (the profile card's
"Cross-feature overview location" field is authoritative if it differs).

## Layered DAG
```
Layer 0:   entry confirmation (hard gate — ticket screenshot or user confirmation)
              ↓
Layer 1:   deps  (Batch entry: run batch-analysis first)
              ↓
Layer 2:   vars ‖ erd ‖ funcs   (parallel; depend on ①; scored in ONE batched quality-score call)
              ↓
Layer 3:   flow → rules          (depend on ①②③④)
              ↓
Layer 3.5: ui-verify             (UI entry points only; depends on ⑤⑥)
              ↓
Layer 4a:  sd                    (depends on ①④⑤)
              ↓
Layer 4b:  api-contract (WS/API only) → sa   (depend on ⑦⑤⑥)
              ↓
Layer 5:   auto-verify — vspec-e2e ‖ (vspec-mock, default skipped) → vspec-static (direct-claims by default) → vspec-report → vspec-patch
```

## Quality gate

After every document-producing stage (including `ui-verify`, `api-contract`,
and `sa` — no stage is exempt), run `quality-score` before allowing downstream
stages to proceed. **`quality-score` does not decide the gate** — it only
reports `score_10`, dimension breakdown, an accuracy spot-check, a
defect-first candidate list, and structural flags. The orchestrator derives
the gate mechanically:

Score dimensions and weights:

| Dimension | Weight |
|-----------|--------|
| Accuracy (source fidelity) | 0.30 |
| Completeness | 0.25 |
| Testability | 0.15 |
| Clarity | 0.10 |
| Non-functional | 0.10 |
| Technical constraints | 0.10 |

Each dimension is 0-5, backed by a defect-first search (no dimension may score
5 without documented "no defect found" evidence). Accuracy is derived only from
an ≥8-claim spot-check against source (never scored subjectively). `score_10 =
round(weighted_score_5 * 2, 1)`; pass threshold is `score_10 >= 9.0`.

### Full-profile gate derivation (orchestrator-owned, mechanical — not a judgment call)

1. `quality/<stage>-score.md` missing or `quality_score` not a valid `[0,10]`
   float → re-run `quality-score` once; still invalid → `failed_local`.
2. Any `structural_flags` entry `true`, or `quality_score < 8.0`, or
   `structural_flags.completeness_lt_4` → `failed_structural`: write/confirm
   gap report, set `pending_human=true`, stop downstream, ask for confirmation.
3. `quality_score >= 9.0` → `passed`, continue.
4. `8.0 <= quality_score < 9.0` → `repairing`: repair from `repair_actions`,
   rescore. Repair cap: 1 attempt for Layer 2 stages, 2 for all others. Cap
   exhausted and still `< 9.0` → `failed_local`: stop, ask user to accept risk
   / repair manually / abandon.

### Fast-profile gate derivation

Same inputs, same `quality-score` agent (its scoring logic is identical under both profiles —
only the orchestrator's reading of the result changes). Fast gates on **structural correctness
plus a coverage floor**, and never enters a repair loop:

1. Validity check as in full-profile rule 1.
2. Any of the four **contradiction-type** flags true — `entry_point_wrong`,
   `api_boundary_wrong`, `data_table_wrong`, `main_flow_wrong` → this is a genuine
   wrong-direction risk, which fast mode does exist to catch. Allow **1** repair attempt; if
   still true → `failed_structural`, stop, hand to human. Fast mode does not push through.
3. `score_breakdown.completeness < 3.0` → `failed_structural` (real coverage hole, not mere
   brevity). Note this reads the **raw Completeness dimension**, not the `completeness_lt_4`
   boolean — 3.0 ("main aspects covered, detail omitted") is the expected shape of fast output,
   so the 4.0-based flag is not the right threshold here.
4. `score_10 < 6.0` → `failed_structural` (sanity floor; a document failing >30% of its
   spot-check is unreliable, not merely imprecise).
5. Otherwise → `quality_gate = fast_pass`, continue. **Do not** compare against 9.0 and **do
   not** repair, however low the score is above the floor.

`affects_gt_2_docs` is a warning only under fast (it measures rework cost, and refusing rework is
what fast mode *is*); record it in the summary without blocking.

> **Why not gate on `structural_flags` alone?** All six flags are *contradiction-type* — they fire
> only when the document asserts X while source says Y. Anything the document simply **failed to
> mention** trips no flag at all. A FLOWCHART that draws "submit → POST /a → toast" perfectly but
> omits that the same handler also calls `/b` has every flag `false` and is still pointing the
> reader the wrong way. Omission risk is therefore carried by two other mechanisms: `ui-verify`'s
> constructive check (primary) and the Completeness floor in rule 3 (secondary).

### Convergence circuit breaker (both profiles)

A gate that can be retried without bound is not a gate. Independently of the per-profile repair
caps above, stop and escalate when either condition holds for a stage:

- cumulative `score_attempts >= 4` — **counting every scoring round regardless of who produced
  the fix**: automatic worker repair, orchestrator-driven repair, and manual human edits all
  count. The cap exists to bound total investment, not to police who did the work.
- `score_10` failed to improve across **2 consecutive** rounds (flat or falling).

On trigger: stop the stage, report the score history, and offer exactly three options — accept
the risk (→ `accepted_risk`, see below) / change strategy (full regeneration, different model,
narrower scope) / abandon. **Do not silently start another round.** Repeated fixing without
monotonic improvement means the strategy is wrong, not that one more round is needed.

### `accepted_risk`

A terminal gate value for "a human looked at a sub-threshold result and chose to proceed". It is
**not** a synonym for `passed`. Whenever it is written:

- `resume_decision` is **mandatory** — who decided, on what score/flag evidence, and what residual
  risk they accepted.
- `summary.md` and the `runs.md` row must show it distinctly, so a later reader cannot mistake the
  stage for having met the threshold.

For Layer 2 (vars/erd/funcs), dispatch `quality-score` **once** in batch mode;
it returns three independent scorecards and state updates, judged
independently — a repair on one does not require repairing the other two.

Structural gaps produce `<stage>-gap-report.md` and stop automatic flow when
the gap affects entry points, API boundaries, data tables, main flow, more
than two documents, or downstream docs already depend on a wrong premise.

## Auto-verify policy & deferral

`verify_policy` (profile, optional field, default `always`): `always` or
`risk-based`.
- `always`: every run's `sa` completion triggers the full auto-verify phase.
- `risk-based`: only for Mode B, or a Mode A run where every stage's Accuracy
  dimension scored 5.0, may the orchestrator skip auto-verify — logging the
  skip to `<harness_dir>/verify-backlog.md`. Mode A round 1 always runs verify
  regardless of policy.

`vspec-mock` defaults to **skipped**; `vspec-static` runs in **direct-claims
mode** (extracts verifiable claims directly from SD.md + sibling docs, no mock
skeleton needed). The legacy three-layer mock comparison is opt-in only.
`vspec-e2e` reuses `ui-verify`'s existing mock HTML/screenshots under
`doc_root/playwright/` and `doc_root/images/` rather than rebuilding them.

**User-requested deferral**: if the user postpones the auto-verify phase for a
run that otherwise completed through `sa`, the run's top-level `status`
becomes `verify-deferred` (not the generic "incomplete run" state) — it does
not trigger the resume prompt on next launch, and is logged in
`verify-backlog.md`.

> **Deferral is not free, and is unavailable to fast runs.** `diff_rate` is the only signal that
> can retrospectively tell you whether the quality scores were calibrated at all — skipping verify
> switches off that feedback loop. Two consequences:
> - Whenever verify is deferred or skipped under **full** profile, `summary.md` must carry a
>   prominent line stating the feature's quality is unverified against code (`diff_rate` unknown),
>   in addition to the `verify-backlog.md` row.
> - Under **fast** profile the phase is **mandatory** — decline the deferral request and explain
>   that fast's entire precision story is the end-of-run batch patch. A user who wants to defer
>   verify wants a full run, not a fast one.

## Quality/diff calibration

After `vspec-report` produces `diff_rate`, the orchestrator adds a calibration
table to `summary.md` mapping each stage's `quality_score` against the diff
items attributable to it. A stage scoring `>= 9.0` while contributing
`diff_rate > 0.15` is a calibration warning — it means the gate passed but the
document diverged from code more than expected, and the anchor rubric for that
stage should be reviewed.

**Cross-profile calibration**: record `analysis_profile` alongside `diff_rate` in the calibration
block, and compare fast runs against the project's full-run history. The design premise of the
fast profile — that one end-of-run systematic verify recovers as much precision as per-stage
repair loops — is falsifiable exactly here. If fast runs consistently land at a materially worse
`diff_rate` than full runs on the same project, the premise is wrong and the fast gate needs
tightening. Treat a fast run above the round-1 threshold (0.20 by default) as evidence worth
reporting, not as routine.

## Execution steps
- **Step 0 — entry confirmation**: confirm the entry point from a ticket
  screenshot or the user before proceeding (hard gate; see the orchestrator's
  Step 3.0).
- **Step 1 — path & entry type**: determine MODULE/FEATURE/PAGE and entry-point
  type. For a batch entry point, run `batch-analysis` first.
- **Step 2 — scan existing docs**: check which of the 10 already exist. For each one found,
  grep its first 15 lines for `analysis_profile: fast`. A hit means the document came from a
  fast run and has **not** been through the precision loop.
- **Step 3 — completeness**: existing docs → check against the skill's self-check;
  incomplete → top up; complete → reuse as input.
  **Exception — fast-marked documents in a full-profile run**: never take the `complete → reuse
  as input` path for them. They have unknown-unknowns (they were never sampled to 9.0), so
  feeding them downstream propagates blind spots. Route them through the upgrade procedure below.
- **Step 4 — produce missing docs in layer order** (per the DAG).
- **Step 4.5 — quality gate**: after each produced doc, run `quality-score`
  (batched for Layer 2), derive the gate mechanically, and stop on
  `failed_local`, `failed_structural`, or `pending_human`.
- **Step 5 — summary**: output a run summary including `analysis_profile`, quality_score,
  quality_gate, score_attempts, spot_check, structural_flags, the calibration
  table, and gap-report links.

### Upgrade run (fast → full)

When a full-profile run starts against a doc_root containing fast-marked documents, do **not**
walk the DAG scoring-and-repairing stage by stage — that way you only learn the true size of the
gap halfway through. Run two distinct phases:

**Phase 1 — assess everything, change nothing.**
Dispatch `quality-score` over *all* existing fast documents (Layer 2 still batched into one
call), scoring at the full 9.0 threshold. **No repairs, no edits in this phase.** Consolidate the
results into `<harness_dir>/<run_id>/upgrade-assessment.md`: per document — `score_10`, the six
dimension breakdown, `structural_flags`, `repair_actions`, and a recommended disposition
(`promote` / `top-up` / `regenerate` / `regenerate-with-stronger-model`). Present the consolidated
gap to the user before spending on Phase 2.

**Phase 2 — close the gap per the assessment.**
- `score_10 >= 9.0` and all flags false → rewrite the banner to `analysis_profile: full`; leave
  content untouched.
- `8.0 <= score_10 < 9.0` → top-up repair → rescore → normal repair loop (circuit breaker still
  applies).
- any contradiction-type flag true → regenerate that stage from scratch.
- **Layer 2 (`vars`/`erd`/`funcs`) is always regenerated with the stronger model**, never merely
  topped-up. Under fast they were produced by the cheap model, whose output may be structurally
  fine yet unable to reach 9.0 — topping up in place just replays that grind. This step is what
  makes the upgrade path viable; do not skip it.
- run the full Layer 5 verify phase.
- once everything clears, rewrite all remaining banners to `analysis_profile: full`.

## Run modes
| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **A** Reverse-analysis | "analyse X" / "full run X" | produce the full set |
| **B** Linked-update | "X changed Y" / "sync X" | ask for a change list, filter affected stages via the impact matrix; mark unaffected stages skipped |
| **C** Cross-feature overview | "X module overview" | produce `_global/<feature>-overview/` docs (path per profile card) |

> Run mode and `analysis_profile` (`full` | `fast`) are **orthogonal** and combine freely — mode
> answers *why* you are analysing, profile answers *how strictly each stage is gated*. There is no
> "fast mode"; there are fast **runs** of mode A, B or C.

### Mode B change-impact matrix
> **Tip**: For localised SD omissions/errors found by `verify-spec`, use `vspec-patch` first — it patches docs directly without re-analysing. Reserve Mode B/A for widespread or structural changes where doc structure itself needs regenerating.

Ask the user for an explicit change list (do **not** auto-diff). Filter stages:

| Change type | ①dep | ②var | ③erd | ④fn | ⑤flow | ⑥rule | ⑦sd | ⑧a | ⑧bSA |
|-------------|:---:|:---:|:---:|:--:|:----:|:----:|:--:|:--:|:----:|
| Controller field add/remove | ● | ● | | | ● | ● | ● | | ● |
| Controller public method change | ● | | | ● | ● | ● | ● | | ● |
| Controller private helper change | | | | ○ | ○ | ○ | ○ | | ○ |
| UI field add/remove/change | | ● | | | ● | ● | ● | | ● |
| Service method change | ● | | | ● | ● | ● | ● | | ● |
| Transaction setting change | | | | ● | ● | ● | ● | | ● |
| Data-access method add/remove | ● | | ● | ● | | ● | ● | | ● |
| Query/SQL change | | ● | ● | | | ● | ● | | ● |
| Table column add/remove | | ● | ● | | | ● | ● | | ● |
| Table add/remove | ● | ● | ● | ● | ● | ● | ● | | ● |
| Constant value change | | ● | | | ○ | ● | ○ | | ● |
| Value-conversion map change | | ● | | | ● | ● | ● | | ● |
| External call add/remove | ● | | ○ | ● | ● | ● | ● | | ● |
| Branch logic change | | | | ● | ● | ● | ● | | ● |
| Validation rule change | | ● | | ● | ● | ● | ● | ● | ● |
| Request/Response field change | | ● | | | | | ● | ● | ● |
| Return-code change | | | | | | ● | | ● | ● |
| Batch: job step add/remove | ● | | | ● | ● | ○ | ● | | ● |
| Batch: tasklet logic change | | | | ● | ● | ● | ● | | ● |
| Batch: chunk reader/writer change | | ○ | ● | ● | ● | ○ | ● | | ● |
| Batch: schedule change | | | | | | | ○ | | ● |
| Batch: job-chain change | ● | | | | ● | ○ | ● | | ● |

● = must update; ○ = check then decide. ⑧a applies to WS/API only. ui-verify is
judged separately (UI entry points only).

## API-CONTRACT applicability
Produce API-CONTRACT.md only for web-service / REST entry points; order is
`⑦ SD → ⑧a API-CONTRACT → ⑧b SA`.
