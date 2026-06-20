---
description: Run the full code-analysis pipeline (deps → vars/erd/funcs → flow → rules → sd → sa → verify) for a feature or entry-point. Reads .analysis-profile.md; run /analysis-init first if not present.
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

Read `${CLAUDE_PROJECT_DIR}/.analysis-profile.md`. Validate: (a) non-placeholder `docs_root`, (b) at least one filled module/layer row, (c) at least one checked entry-point type. If any field is blank or placeholder, stop:
`❌ Profile incomplete — <field(s)> not set. Run /analysis-init to regenerate the profile card.`

Scan `<harness_dir>/*/state.json` for incomplete runs (any stage status ∉ {done, skipped}; `running` = session-interrupted, treat as pending; `blocked` = session-limit hit, treat as pending). If found, ask: resume / new / abandon.
- **resume**: re-dispatch pending/running/blocked stages in DAG order (reset to pending; do not increment retry_count).
- **new**: fresh run_id.
- **abandon**: mark non-{done,skipped} stages failed, status=partial, archive summary.md, continue with new run.

**7-day cleanup**: after handling incomplete runs, move summary.md to `_archive/<year>/`, delete state/handoff/log files, remove runs.md row for runs older than 7 days with status ∈ {done, failed, partial}.

### 2. Mode detection

- **A** — reverse-analysis ("analyse X") → full pipeline.
- **B** — linked-update ("X changed") → ask for explicit change list, filter via impact matrix.
- **C** — cross-feature overview → produce `_global/<feature>-<entry>-overview/`.

### 3. Path & entry type

Determine MODULE/FEATURE/PAGE and entry-point type from the profile module/layer map. Add `batch-analysis` as first stage if batch entry type (else skipped). Ensure `deps` invokes the `batch-analysis` skill as part of its analysis.

### 4. Run-state init

`run_id = <timestamp>-<feature>`. Create `<harness_dir>/<run_id>/state.json` (all stages pending, including vspec-*; `re_analysis_count=0`, `diff_rate=null`). Write `handoff-init-to-deps.md`. Use templates from `${CLAUDE_PLUGIN_ROOT}/templates/harness/`. Always: read whole file → modify in memory → write back whole.

### 4b. runs.md gate

**Must complete before dispatching any worker.**

1. If `<harness_dir>/runs.md` does not exist → create it from `${CLAUDE_PLUGIN_ROOT}/templates/harness/runs.md`.
2. Append run row (run_id, feature, entry_type, mode, started ISO, status=running, re_analysis_count=0, last_stage=—, diff_rate=—, docs=0/N, ended=—).
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

### 5.5. Auto-verify phase

Runs immediately after `sa` completes:
7. `vspec-mock` ‖ `vspec-e2e` — parallel (vspec-e2e self-skips for non-UI). Pass: run_id, doc_root, entry_point, entry_type.
8. `vspec-static` — after both done/skipped.
9. `vspec-report` — after static done; writes SD-review.md, sets diff_rate + sd_review_path in state.json.

Same retry rule (≤2) applies to each vspec worker.

### 5.6. diff_rate gate (runs once)

Read `diff_rate` from state.json after vspec-report completes.

- **≤ 0.10** → proceed to Step 6.
- **> 0.10 and `re_analysis_count == 0`**:
  a. Parse SD-review §5 (recommended fixes) to build a change list.
  b. Apply the analysis-orchestration impact matrix.
  c. ≤3 stages affected → mode B; >3 stages → mode A.
  d. Set `re_analysis_count = 1` in state.json.
  e. Re-run affected stages (reset to pending, normal DAG order and retry rules).
  f. Re-run full auto-verify phase (§5.5) on the updated SD.md.
  g. Proceed to Step 6 with updated diff_rate.
- **> 0.10 and `re_analysis_count == 1`**: Report "⚠️ diff_rate still X.X% after one re-analysis cycle. Manual review of SD-review.md is required." → proceed to Step 6.

### 6. Summary

Write `<harness_dir>/<run_id>/summary.md`: stage list with status/doc paths/confidence/pending-review totals, low-confidence stages (⚠️ prefix), spec quality block (diff_rate ✅/⚠️, SD-review path, re-analysis decision). If re-analysis was performed, append this block verbatim:

```
⚠️ 決策執行一致性：本次執行了自動重分析，請 grep skills/ 與 agents/ 確認
無舊做法或硬編碼殘留，避免「決策寫了但 prompt 未更新」的執行脫節。
```

Update runs.md row (status, re_analysis_count, last_stage, diff_rate, docs N/total, ended ISO). Read whole → modify row in memory → write back whole.

Do **not** write session-level files outside `<harness_dir>` / `<docs_root>`.
