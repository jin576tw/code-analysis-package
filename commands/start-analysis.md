---
description: Run the full code-analysis pipeline with per-stage quality-score gates (mechanically decided by the orchestrator, not by quality-score) and final verify-report.md validation for a feature or entry-point. Reads .analysis-profile.md; run /analysis-init first if not present.
argument-hint: <FeatureOrEntryPoint>
---

# /start-analysis

**Target**: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user for the feature name or entry-point before continuing.

## Orchestration

You are the pipeline orchestrator running in the main conversation context.
You **do not analyse yourself** — each layer's content is produced by its worker agent (dispatched via the Task tool). You handle: profile check, path & mode determination, run-state setup, DAG dispatch, retry (max 2), progress reporting, and a final run summary.

Apply the full orchestration logic from the **analysis-orchestration** skill and follow the steps below exactly.

### 1. Profile & startup

Read `${CLAUDE_PROJECT_DIR}/.analysis-profile.md`. Validate:
(a) non-placeholder `docs_root`,
(b) at least one filled module/layer row,
(c) at least one checked entry-point type,
(d) no absolute paths (no `C:\`, `/home/`, `C:/`, `D:\`, `/Users/` etc.) — if found, stop:
`❌ Profile contains absolute paths — please use relative paths only (relative to repo root). Run /analysis-init to regenerate.`

If any field is blank or placeholder, stop:
`❌ Profile incomplete — <field(s)> not set. Run /analysis-init to regenerate the profile card.`

Scan `<harness_dir>/*/state.json` for incomplete runs (any stage status ∉ {done, skipped, deferred}; `running` = session-interrupted, treat as pending; `blocked` = session-limit hit, treat as pending). Runs whose top-level `status == "verify-deferred"` are **not** incomplete runs — they were intentionally paused before the vspec phase and do not trigger the resume prompt; print one summary line instead: `ℹ️ N run(s) awaiting verify (see verify-backlog.md)`. For any other incomplete run found, ask: resume / new / abandon.
- **resume**: re-dispatch pending/running/blocked stages in DAG order (reset to pending; do not increment retry_count).
- **new**: fresh run_id.
- **abandon**: mark non-{done,skipped} stages failed, status=partial, archive summary.md, continue with new run.

**7-day cleanup**: after handling incomplete runs, move summary.md to `_archive/<year>/`, delete state/handoff/log files, remove runs.md row for runs older than 7 days with status ∈ {done, failed, partial, verify-deferred} (for `verify-deferred`, keep the corresponding `verify-backlog.md` row).

**User-requested verify deferral**: if the user asks to postpone the vspec/auto-verify phase for a run that has otherwise completed through `sa`, mark the pending vspec stages `status = "deferred"`, set the run's top-level `status = "verify-deferred"`, and still write `summary.md` and the `runs.md` row (status=`verify-deferred`, `ended` filled in). Add the run to `verify-backlog.md` with reason "user-deferred".

### 2. Mode detection

- **A** — reverse-analysis ("analyse X") → full pipeline.
- **B** — linked-update ("X changed") → ask for explicit change list, filter via impact matrix.
- **C** — cross-feature overview → produce `_global/<feature>-<entry>-overview/`.

### 3.0 Entry confirmation (hard gate)

Before dispatching `deps`, confirm the entry point is real, not just inferred
from a ticket title or summary:
- **Ticket-sourced analysis** (Jira or any issue tracker): fetch the ticket's
  attachments/screenshots, read them, and match the screenshot's query fields +
  button labels against the candidate page/entry — do not trust the ticket
  title/summary alone (summaries have pointed at the wrong page before).
- **Non-ticket sources**: confirm the entry point with the user directly.
- Once confirmed, write run-level `entry_confirmed: true` and
  `entry_evidence: <one-line description of what confirmed it>` into
  `state.json`.
- If the entry point cannot be confirmed and the user has not explicitly waived
  confirmation, **do not dispatch `deps`** — stop and ask.

### 3. Path & entry type

Determine MODULE/FEATURE/PAGE and entry-point type from the profile module/layer map. Add `batch-analysis` as first stage if batch entry type (else skipped). Ensure `deps` invokes the `batch-analysis` skill as part of its analysis.

**doc_root formula** (must be followed strictly):
```
doc_root = <docs_root>/<MODULE>/<FEATURE>/[<PAGE>/][<SUB_PAGE>/].../<tier>
```

**Path derivation rules (must mirror the actual UI/entry structure — never
invent names, never flatten multiple levels with a separator)**:

1. `<MODULE>` = the top-level menu/module name, and `<FEATURE>` = the sub-menu
   or screen title — both read from the project's actual navigation/routing
   source (e.g. a layout/menu config file, route definitions, or controller
   mapping), never invented.
2. Each further drill-in level (Tab, sub-Tab, drill-in page) becomes its **own
   nested folder** — one folder per actual UI level, in the order the user
   actually navigates. **Do not flatten multiple levels into one folder name
   with a separator** (e.g. `Parent-Child` is wrong; `Parent/Child/` is correct).
3. The path has as many nested levels as the UI actually has — not a fixed
   count. `<tier>` (`frontend`/`backend`) is always the last segment and is
   never omitted.
4. If the drill-in structure is unclear from the entry file alone, confirm it
   from a screenshot or the screen's SA.md before naming folders; if still
   unconfirmed, stop and ask the user rather than guessing a name.

Example (generic — substitute the project's real menu/tab names):
- A page reached via `Top Menu → Sub Screen → Tab → Sub-Tab` →
  `<docs_root>/Top Menu/Sub Screen/Tab/Sub-Tab/<tier>/`
- ❌ Wrong: `<docs_root>/<MODULE>/<FEATURE>/<tier>` (drops the intermediate levels)
- ❌ Wrong: `<docs_root>/<MODULE>/<FEATURE>/Tab-Sub-Tab/<tier>` (flattens two
  real levels into one hyphenated name)
- ❌ Wrong: inventing a folder name not traceable to an actual menu/tab/page title
- ✅ Correct: one nested folder per actual navigation level, each named from
  the menu/tab/page title itself

### 4. Run-state init

`run_id = <timestamp>-<feature>`. Create `<harness_dir>/<run_id>/state.json` (all stages pending, including vspec-* and vspec-patch; `re_analysis_count=0`, `diff_rate=null`). Resolve `verify_round`: read `<doc_root>/verify-report.md` frontmatter field `verify_round`; if absent, read legacy `<doc_root>/SD-review.md` as fallback only; default 0 if neither file exists. This run's round = prior + 1. Resolve `threshold`: round 1 → 0.20, round 2 → 0.15, round ≥3 → 0.10. Write `verify_round`, `threshold`, `patch_mode="pipeline"` into state.json. Write `handoff-init-to-deps.md`. Use templates from `${CLAUDE_PLUGIN_ROOT}/templates/harness/`. Always: read whole file → modify in memory → write back whole.

**doc_root portability**: store `doc_root` in `state.json` as a **relative path** (relative to repo root) — not an absolute path. Resolve to absolute only when constructing the actual filesystem path for writing a file.

### 4b. runs.md gate

**Must complete before dispatching any worker.**

1. If `<harness_dir>/runs.md` does not exist → create it from `${CLAUDE_PLUGIN_ROOT}/templates/harness/runs.md`.
2. Append run row (run_id, feature, entry_type, mode, started ISO, status=running, re_analysis_count=0, last_stage=—, diff_rate=—, verify_round=N, quality_min=—, failed_quality=—, docs=0/N, ended=—).
3. Immediately read back `runs.md`; verify the row with this run_id is present and status=running.
   - ✅ `[GATE] runs.md verified — starting DAG` → continue.
   - ❌ `[GATE] ⚠️ runs.md write failed: <reason> — harness tracking degraded` → continue (best-effort).

### 5. DAG dispatch (via Task)

Dispatch in dependency order, passing `run_id`, `doc_root`, entry point and the relevant handoff path to each worker:
1. `deps`
2. `vars`, `erd`, `funcs` — parallel (single batch of Task calls)
3. `flow` → `rules`
4. `ui-verify` — UI entry points only (else mark skipped)
5. `sd`
6. `api-contract` — WS/API only (else skipped) → `sa`

After each worker: read state.json stage.
- If the Task result text contains "session limit" or "resets" (platform quota hit):
  set stage `status=blocked` in state.json (**do NOT increment retry_count** — blocked ≠
  logical failure). Pause DAG and report:
  `⏸ DAG paused — subagent session limit. Stage <name> blocked. Resume with /start-analysis after reset.`
- On `status=failed` and retry_count < 2: re-dispatch.
- On second failure: stop that branch and report.
- On `status=blocked`: do not retry automatically; wait for human to resume.
Track low-confidence stages (confidence == "low") for summary.

**Every** document-producing stage — including `ui-verify`, `api-contract`, and
`sa` — must go through `quality-score` and a gate decision before any
downstream stage (including the vspec/auto-verify phase) may run. A stage with
`quality_score == null` and no gate decision is an invalid state; do not let
the pipeline proceed past it.

**Layer 2 batch scoring**: once `vars`, `erd`, and `funcs` are all `done`,
dispatch `quality-score` **once** for the batch (pass all three doc paths).
`quality-score` returns three independent scorecards/state updates — apply the
gate decision below to each of the three independently (a repair on `vars`
does not require repairing `erd`/`funcs`).

**Gate decision (orchestrator-owned; quality-score has no say in the gate)**:
after `quality-score` returns for a stage, read `quality_score`,
`score_breakdown`, `structural_flags`, `score_attempts` from `state.json` and
decide mechanically:
1. **Validity check**: `quality/<stage>-score.md` must exist and
   `quality_score` must be a float in `[0, 10]`. If missing/invalid →
   re-dispatch `quality-score` once; if still invalid → `quality_gate =
   failed_local`, stop that branch, report.
2. If any `structural_flags` entry is `true`, or `quality_score < 8.0`, or
   `structural_flags.completeness_lt_4 == true` → `quality_gate =
   failed_structural`. Write/confirm the gap report, set `pending_human =
   true`, stop affected downstream stages, and ask for human confirmation.
3. Else if `quality_score >= 9.0` → `quality_gate = passed`, continue.
4. Else (`8.0 <= quality_score < 9.0`) → `quality_gate = repairing`: build a
   same-stage repair prompt from `repair_actions`, re-dispatch the same worker,
   then re-run `quality-score`. Repair attempt cap: **1** for Layer 2
   (vars/erd/funcs), **2** for all other stages. If the cap is exhausted and
   `quality_score` is still `< 9.0` → `quality_gate = failed_local`; stop that
   branch and ask the user to choose: accept the risk and continue / repair
   manually / abandon.

Write the decided `quality_gate` value into the stage's `state.json` entry
yourself (quality-score does not write this field).

### 5.5. Auto-verify phase

Runs immediately after `sa` completes and passes its gate.

**Verify policy gate**: read profile's `verify_policy` field if present (default
`always`).
- Mode A, `verify_round == 1`, or `verify_policy == always` → run the full
  verify phase below.
- Mode B, or every stage's Accuracy dimension scored `5.0` in this run, **and**
  `verify_policy == risk-based` → the auto-verify phase may be skipped. If
  skipped: append a row to `<harness_dir>/verify-backlog.md` (create from
  `${CLAUDE_PLUGIN_ROOT}/templates/harness/verify-backlog.md` if absent) with
  `run_id`, `doc_root`, skip reason, date; proceed straight to Step 6 and note
  the skip in summary.md.

**Steps** (mock defaults to skipped — static runs in direct-claims mode):
7. `vspec-mock` — **default: skipped**. Only dispatch it if the profile
   explicitly requests the legacy three-layer mock comparison, or the user
   asks for it. When skipped, set stage status `skipped` with
   `error: "default-skip: static runs in direct-claims mode"`.
   ‖ `vspec-e2e` (parallel with the mock decision) — self-skips for non-UI.
   Before dispatching, check whether `doc_root/playwright/` and
   `doc_root/images/` already contain mock HTML/spec/screenshots from
   `ui-verify`; pass their paths so `vspec-e2e` reuses them instead of
   rebuilding. Pass: run_id, doc_root, entry_point, entry_type.
8. `vspec-static` — after `vspec-mock` done/skipped and `vspec-e2e` done/skipped.
   Runs in **direct-claims mode** when `vspec-mock` was skipped: extract
   verifiable claims directly from SD.md + sibling docs and classify each
   against real code (no mock skeleton needed). Falls back to the legacy
   three-layer mock comparison only if a mock skeleton exists.
9. `vspec-report` — after static done; writes verify-report.md, sets diff_rate + verify_report_path in state.json, and a calibration block (see 5.6a).
10. `vspec-patch` — after report done; **pipeline mode** (auto-applies). Pass: run_id, doc_root. Skip if diff_rate == 0. Retry ≤2.

Same retry rule (≤2) applies to each vspec worker.

### 5.6a. Quality/diff calibration

After `vspec-report` completes, read its calibration block (per-stage
`quality_score` vs. this run's diff item count) and add a "Calibration" table
to `summary.md`: stage / quality_score / diff items attributable to that
stage. If any stage scored `quality_score >= 9.0` and its `diff_rate`
contribution is `> 0.15`, append:
`⚠️ Quality/diff calibration warning: <stage> passed the gate (score=X) but
still diverged from code more than expected (diff contribution > 15%) —
consider tightening that stage's anchor rubric.`

### 5.6. diff_rate post-patch assessment

Read `diff_rate` and `threshold` from state.json after vspec-patch completes.

- **diff_rate == 0** → proceed to Step 6.
- **diff_rate > 0 and `diff_rate ≤ threshold`** → proceed to Step 6. Patches applied; within acceptable range for verify_round N.
- **diff_rate > threshold** → record advisory in summary.md and runs.md row:
  `⚠️ diff_rate X.X% > threshold Y.Y% (verify_round N). Patches applied. Recommend human review of verify-report.md; consider manual re-analysis if structural issues suspected.`
  Proceed to Step 6. **Do not auto-trigger re-analysis.**

> `re_analysis_count` is retained for opt-in tracking; it is no longer incremented automatically.

### 6. Summary

Write `<harness_dir>/<run_id>/summary.md`: stage list with status/doc paths/confidence/pending-review totals, `quality_score / quality_gate / score_attempts / spot_check(passed/sampled) / structural_flags`, low-confidence stages (⚠️ prefix), gap-report links, the quality/diff calibration table (§5.6a), spec quality block (diff_rate ✅/⚠️, verify-report path, verify_round, threshold, patch summary: N patched / M deferred / patch_plan_path). If `diff_rate > threshold`, include the advisory note. If the run status is `verify-deferred`, state that clearly with a pointer to `verify-backlog.md`. Always append this block verbatim:

```
⚠️ 決策執行一致性：請 grep skills/ 與 agents/ 確認
無舊做法或硬編碼殘留，避免「決策寫了但 prompt 未更新」的執行脫節。
```

Update runs.md row (status, re_analysis_count, last_stage, diff_rate, quality_min, failed_quality, docs N/total, ended ISO). Read whole → modify row in memory → write back whole.

Do **not** write session-level files outside `<harness_dir>` / `<docs_root>`.
