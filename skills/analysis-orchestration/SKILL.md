---
name: analysis-orchestration
description: The full code-documentation pipeline. Describes the document set, the layered DAG, SA dispatch rules, output-path determination, and the three run modes (reverse-analysis / linked-update / cross-feature overview) with the change-impact matrix. Used by the start-analysis orchestrator agent.
---

# Analysis Orchestration

End-to-end pipeline that produces up to 10 analysis documents for a feature.

> **Read the profile card first** (`${CLAUDE_PROJECT_DIR}/.analysis-profile.md`)
> for the module/layer map, entry-point types, output path (§7) and harness dir
> (§10). If absent, run `analysis-init` first (or auto-detect). **Load skill
> `analysis-conventions`.**

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

Cross-feature overviews go under `<docs_root>/_global/<feature>-<entry>-overview/`.

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

**Gate derivation (orchestrator-owned, mechanical — not a judgment call)**:
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

## Quality/diff calibration

After `vspec-report` produces `diff_rate`, the orchestrator adds a calibration
table to `summary.md` mapping each stage's `quality_score` against the diff
items attributable to it. A stage scoring `>= 9.0` while contributing
`diff_rate > 0.15` is a calibration warning — it means the gate passed but the
document diverged from code more than expected, and the anchor rubric for that
stage should be reviewed.

## Execution steps
- **Step 0 — entry confirmation**: confirm the entry point from a ticket
  screenshot or the user before proceeding (hard gate; see the orchestrator's
  Step 3.0).
- **Step 1 — path & entry type**: determine MODULE/FEATURE/PAGE and entry-point
  type. For a batch entry point, run `batch-analysis` first.
- **Step 2 — scan existing docs**: check which of the 10 already exist.
- **Step 3 — completeness**: existing docs → check against the skill's self-check;
  incomplete → top up; complete → reuse as input.
- **Step 4 — produce missing docs in layer order** (per the DAG).
- **Step 4.5 — quality gate**: after each produced doc, run `quality-score`
  (batched for Layer 2), derive the gate mechanically, and stop on
  `failed_local`, `failed_structural`, or `pending_human`.
- **Step 5 — summary**: output a run summary including quality_score,
  quality_gate, score_attempts, spot_check, structural_flags, the calibration
  table, and gap-report links.

## Run modes
| Mode | Trigger | Behaviour |
|------|---------|-----------|
| **A** Reverse-analysis | "analyse X" / "full run X" | produce the full set |
| **B** Linked-update | "X changed Y" / "sync X" | ask for a change list, filter affected stages via the impact matrix; mark unaffected stages skipped |
| **C** Cross-feature overview | "X module overview" | produce `_global/<feature>-<entry>-overview/` docs |

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
