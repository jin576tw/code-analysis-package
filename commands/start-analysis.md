---
description: Run the code-analysis pipeline with per-stage quality-score gates (mechanically decided by the orchestrator, not by quality-score) and final verify-report.md validation for a feature or entry-point. Supports two analysis profiles — full (9.0 gate + repair loop) and fast (structural gate, precision recovered by the end-of-run verify). Reads .analysis-profile.md; run /analysis-init first if not present.
argument-hint: <FeatureOrEntryPoint> [--fast | --full]
---

# /start-analysis

**Target**: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user for the feature name or entry-point before continuing.

## Analysis profile

Both profiles produce the **same document set and run the same stages** — including `ui-verify`
and the full Layer 5 verify phase. They differ in exactly two things:

| | `--full` (default) | `--fast` |
|---|---|---|
| Per-stage gate | `score_10 >= 9.0`, repair + rescore on miss (cap 1 for Layer 2, 2 elsewhere) | structural gate only (4 contradiction flags false + Completeness ≥ 3.0 + score ≥ 6.0), **no repair loop** |
| Layer 2 model (`deps`/`vars`/`erd`/`funcs`) | strongest available model (dispatch override) | agent default (cheap fast model) |
| Output status | deliverable | **draft — must not be used as a delivery basis** |

Fast recovers citation precision in bulk from the end-of-run `vspec-static` → `vspec-report` →
`vspec-patch` sweep instead of grinding each stage. Its documents carry an `analysis_profile: fast`
banner and can be upgraded later with `--full`, which re-scores them at 9.0 and tops up or
regenerates as needed (see the orchestration skill's Upgrade run).

**If neither flag is given, ask the user which profile to run** — `--fast` is a deliberate,
risk-bearing downgrade and must never be chosen implicitly.

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

**Human-review-queue rollup**: if `<docs_root>/_pending/human-review-queue.md` exists, count rows
with `status == open`. If any, print `⚠️ N item(s) pending human review (M blocking — undecided
gap-report worksheet rows — see _pending/human-review-queue.md)` before anything else, where M is
the subset belonging to runs currently `stopped-needs-human`.

Scan `<harness_dir>/*/state.json` for incomplete runs (any stage status ∉ {done, skipped, deferred}; `running` = session-interrupted, treat as pending; `blocked` = session-limit hit, treat as pending). Runs whose top-level `status == "verify-deferred"` are **not** incomplete runs — they were intentionally paused before the vspec phase and do not trigger the resume prompt; print one summary line instead: `ℹ️ N run(s) awaiting verify (see verify-backlog.md)`. Runs whose top-level `status == "stopped-needs-human"` also skip the generic resume/new/abandon prompt — go straight to the §5d.1 worksheet check: any gap-report row with an empty Decision cell blocks resume outright (report which rows, do not proceed); once all rows are decided, resume normally (❌ rows first route back to the producing worker). For any other incomplete run found, ask: resume / new / abandon.
- **resume**: re-dispatch pending/running/blocked stages in DAG order (reset to pending; do not increment retry_count).
  **Before re-dispatching, check each `done` stage for an un-scored repair**: if
  `repair_applied_at` is non-null and later than the stage's `ended_at` of its last scoring round,
  a repair was written to disk but never re-scored (the classic session-interrupted state). Such a
  stage needs `quality-score` re-run, **not** another repair — re-dispatching the worker would
  redo work already on disk. Never diagnose this by comparing document file mtimes; that is what
  this field exists to replace.
- **new**: fresh run_id.
- **abandon**: mark non-{done,skipped} stages failed, status=partial, archive summary.md, continue with new run.

**7-day cleanup**: after handling incomplete runs, move summary.md to `_archive/<year>/`, delete state/handoff/log files, remove runs.md row for runs older than 7 days with status ∈ {done, failed, partial, verify-deferred} (for `verify-deferred`, keep the corresponding `verify-backlog.md` row).

**User-requested verify deferral**: if the user asks to postpone the vspec/auto-verify phase for a run that has otherwise completed through `sa`, mark the pending vspec stages `status = "deferred"`, set the run's top-level `status = "verify-deferred"`, and still write `summary.md` and the `runs.md` row (status=`verify-deferred`, `ended` filled in). Add the run to `verify-backlog.md` with reason "user-deferred".

### 1.6 Analysis profile selection (before harness init)

Resolve `analysis_profile` (`full` | `fast`) from the arguments: `--fast` → fast; `--full` → full;
**no signal → stop and ask the user**, showing the trade-off table above. Write the result into
`state.json` at run level (§4). An existing `state.json` without the field (schema ≤1.3) means
`full`.

### 2. Mode & profile detection

Mode and profile are orthogonal — mode says *why* you are analysing, profile says *how strictly
each stage is gated*. Any mode may run under either profile.

- **A** — reverse-analysis ("analyse X") → full pipeline.
- **B** — linked-update ("X changed") → ask for explicit change list, filter via impact matrix.
- **C** — cross-feature overview → produce `_global/<feature>-overview/` (path per profile card).

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

### 3.0.5 Scope card (Layer 0.5 — scoping, not analysis)

Before dispatching `deps`, produce `<doc_root>/SCOPE.md` — a short, **regenerable** artefact
answering "what is this run about, and what does it touch" *before* the DAG starts, rather than
letting scope drift get discovered document by document. This is a deliberately **cheap, directed
scan** — three specific lookups, not a project-wide relation index (that would duplicate `deps`'
job and is out of scope here):

1. **Target**: entry point + its position in the project's navigation/menu source (same source
   used for `<MODULE>/<FEATURE>` in §3).
2. **Directed relation scan** (bounded, no full-repo sweep):
   - Endpoints/calls the target entry point itself makes (grep the entry file(s) only).
   - Whether those endpoints/tables are **already referenced by an existing analysed doc** under
     `<docs_root>` (compare against existing docs only — do not grep the whole source tree for
     this step).
   - Sibling entries at the same navigation level (from the same menu/route source as step 1).
3. **Scope boundary**: an explicit list — what this run will analyse in full vs. what it will only
   cross-reference (cross-feature citation, not expansion). Tag every relation found in step 2 with
   a **visibility grade** (see `analysis-conventions` — code-derived / inferred / business-input).
   Anything outside what code can show (business-process sequencing, cross-service timing,
   workflow-engine definitions) is tagged `business-input — pending` rather than guessed at.

**Stop and ask the user to confirm the scope** (include/exclude adjustments) before proceeding to
§4 run-state init. SCOPE.md is not scored by `quality-score` (it is a scoping convention, not an
analysis deliverable) and may be regenerated freely as the menu/doc set changes. Its cross-feature
list feeds `deps`' upstream-tracking step (dependency-analysis skill §4) instead of leaving that
judgment to `deps` alone.

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

`run_id = <timestamp>-<feature>`. Create `<harness_dir>/<run_id>/state.json` (all stages pending, including vspec-* and vspec-patch; `re_analysis_count=0`, `diff_rate=null`). Write `analysis_profile` from §1.6 (template is schema **1.4**). Resolve `verify_round`: read `<doc_root>/verify-report.md` frontmatter field `verify_round`; if absent, read legacy `<doc_root>/SD-review.md` as fallback only; default 0 if neither file exists. This run's round = prior + 1. Resolve `threshold`: round 1 → 0.20, round 2 → 0.15, round ≥3 → 0.10. Write `verify_round`, `threshold`, `patch_mode="pipeline"` into state.json. Write `handoff-init-to-deps.md`. Use templates from `${CLAUDE_PLUGIN_ROOT}/templates/harness/`. Always: read whole file → modify in memory → write back whole.

**doc_root portability**: store `doc_root` in `state.json` as a **relative path** (relative to repo root) — not an absolute path. Resolve to absolute only when constructing the actual filesystem path for writing a file.

### 4b. runs.md gate

**Must complete before dispatching any worker.**

1. If `<harness_dir>/runs.md` does not exist → create it from `${CLAUDE_PLUGIN_ROOT}/templates/harness/runs.md`.
2. Append run row (run_id, feature, entry_type, mode, **profile**, started ISO, status=running, re_analysis_count=0, last_stage=—, diff_rate=—, verify_round=N, quality_min=—, failed_quality=—, docs=0/N, ended=—).
3. Immediately read back `runs.md`; verify the row with this run_id is present and status=running.
   - ✅ `[GATE] runs.md verified — starting DAG` → continue.
   - ❌ `[GATE] ⚠️ runs.md write failed: <reason> — harness tracking degraded` → continue (best-effort).

### 5. DAG dispatch (via Task)

Dispatch in dependency order, passing `run_id`, `doc_root`, entry point, `analysis_profile` and the relevant handoff path to each worker:
1. `deps`
2. `vars`, `erd`, `funcs` — parallel (single batch of Task calls)
3. `flow` → `rules`
4. `ui-verify` — UI entry points only (else mark skipped)
5. `sd`
6. `api-contract` — WS/API only (else skipped) → `sa`

**The DAG is identical under both profiles** — fast runs every stage including `ui-verify` and the
whole Layer 5 phase. There is no fast-mode skip list.

**Model dispatch by profile**: for `deps`/`vars`/`erd`/`funcs`, pass an explicit `model` override
to the strongest model available under `full`; pass no override under `fast` (their frontmatter
default is the cheap fast model). Rationale: those four are catalogue stages commonly configured
to a cheap model, and a weak model can make `score_10 >= 9.0` effectively unreachable — turning
the full-profile repair loop into a guaranteed spin. Do not edit the agents' frontmatter to
achieve this; override at dispatch so standalone invocation is unaffected.

**Always pass `analysis_profile` in the worker prompt** — workers use it to decide whether to
write the fast provenance banner (`analysis-conventions` §12). Omitting it produces unmarked fast
documents, the worst failure mode of this design.

**Downgrade protection (fast runs only)**: before dispatching a stage whose target document
already exists, grep its first 15 lines for `analysis_profile: fast`. If the file exists
**without** that marker it is full-profile work — mark the stage `skipped` with
`error: "downgrade-protected: full-profile doc exists"` and tell the user. Never overwrite
full-profile output with fast output.

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
decide mechanically. **Which derivation applies is determined by `analysis_profile`.**

#### 5a. Full-profile gate derivation

A stage lands in exactly one of three buckets: **passed** (clears 9.0), **auto-continue with
recorded tech debt** (a pure precision gap, no wrong-direction risk), or **hard-stop for a human**
(a wrong-direction or coverage risk). Which bucket applies is mechanical, not a per-run judgment
call — this replaces ad-hoc "the flags are all false so let's just continue" decisions made in the
moment, which leave no durable record.

1. **Validity check**: `quality/<stage>-score.md` must exist and
   `quality_score` must be a float in `[0, 10]`. If missing/invalid →
   re-dispatch `quality-score` once; if still invalid → `quality_gate =
   failed_local`, stop that branch, report.
2. **Hard-stop — contradiction-type risk**: any of `entry_point_wrong`,
   `api_boundary_wrong`, `data_table_wrong`, `main_flow_wrong` is `true` → `quality_gate =
   failed_structural`. These are wrong-direction risks; full profile does not push through them.
   Go to **§5d.1 gap-report worksheet** (mandatory) before stopping.
3. **Hard-stop — coverage risk**: `structural_flags.completeness_lt_4 == true` or `quality_score <
   6.0` → `quality_gate = failed_structural`. A real coverage hole or sanity-floor failure is an
   omission risk, not mere imprecision — it does not qualify for the tech-debt bucket below. Go to
   **§5d.1 gap-report worksheet** (mandatory) before stopping.
4. Else if `quality_score >= 9.0` → `quality_gate = passed`, continue.
5. Else (`quality_score < 9.0`, all four contradiction-type flags `false`, `completeness_lt_4 ==
   false`, `quality_score >= 6.0`) → `quality_gate = repairing`: build a same-stage repair prompt
   from `repair_actions`, re-dispatch the same worker, then re-run `quality-score`. Repair attempt
   cap: **1** for Layer 2 (vars/erd/funcs), **2** for all other stages.
   - Re-score reaches `>= 9.0` → `passed`.
   - Cap exhausted and `quality_score` is still in `[6.0, 9.0)` with every flag still `false` →
     **`quality_gate = tech_debt_accepted`** (§5d.2): this is a pure citation/precision gap with no
     structural risk — record it and **continue to downstream stages automatically**, no
     per-run question. The end-of-run Layer 5 verify sweep (§5.5) is the designated backstop for
     this bucket.
   - Cap exhausted and any flag flipped `true` during repair, or `quality_score` fell below `6.0`
     → `failed_structural` (rule 2/3 applies retroactively — repair must not silently mask a
     structural regression it introduced).

#### 5b. Fast-profile gate derivation

Same scorecard, same agent — only your reading of it changes. **No repair loop**:

1. Validity check exactly as in 5a rule 1.
2. Any of the four **contradiction-type** flags true — `entry_point_wrong`,
   `api_boundary_wrong`, `data_table_wrong`, `main_flow_wrong` → a real wrong-direction risk.
   Allow **1** repair attempt; still true → `failed_structural`, `pending_human = true`, stop.
3. Else if `score_breakdown.completeness < 3.0` → `failed_structural` (genuine coverage hole, not
   brevity). Read the **raw Completeness dimension**, not the `completeness_lt_4` boolean.
4. Else if `quality_score < 6.0` → `failed_structural` (sanity floor).
5. Else → `quality_gate = fast_pass`, continue. **Do not compare against 9.0 and do not repair.**

`affects_gt_2_docs` is warning-only under fast — record it, do not block.

#### 5c. Convergence circuit breaker (both profiles)

Independently of the repair caps above, stop and escalate when cumulative `score_attempts >= 4`
(**counting every scoring round regardless of who produced the fix** — worker auto-repair, your
re-dispatches, and manual human edits alike), or when `score_10` has not improved across **2
consecutive** rounds. Offer exactly three options — accept the risk (→ `accepted_risk`) / change
strategy (full regeneration, different model, narrower scope) / abandon. **Never silently start
another round**: non-monotonic scores mean the strategy is wrong, not that one more round lands it.

#### 5d. Human-in-the-loop bookkeeping

##### 5d.1 Gap-report worksheet — mandatory before any `failed_structural` / hard-stop

A hard-stop must never be "just stop and wait" — it must hand the human a **row-by-row worksheet**
they can act on, and that worksheet's completion is itself the resume precondition, not a courtesy
document.

- `quality-score` writes `<harness_dir>/<run_id>/quality/<stage>-gap-report.md` containing a
  structured table (not prose alone):

  | # | Open question | Why it can't be auto-resolved (flag/evidence) | What a human needs to supply | Downstream docs affected | Decision (✅ confirmed / ❌ corrected to …) |

- **If the gap report exists without this table** → treat `quality-score` as incomplete for this
  stage: re-dispatch it once to produce the table; still missing → do not resume this stage.
- **If the table exists but any row's Decision cell is empty** → the run stays
  `stopped-needs-human`; **do not resume downstream stages**. On resume, check every row: all
  filled (✅/❌) → continue (❌ rows first route back to the producing worker to regenerate the
  affected section); any empty → refuse resume and report which rows are still open.
- Append one row per open item to `<docs_root>/_pending/human-review-queue.md` (create from
  `${CLAUDE_PLUGIN_ROOT}/templates/human-review-queue.md` if absent): `run_id | doc | stage | gate
  | score | open questions (link to the gap-report worksheet) | recommended action | status |
  date`. This is the durable, cross-run rollup; the gap report is the per-run working surface.
- Set run-level `pending_human = true` and top-level `status = "stopped-needs-human"` (distinct
  from `partial`/`paused`/`verify-deferred` — this state means "stopped, worksheet pending", not
  "half-run").

##### 5d.2 `tech_debt_accepted`

Terminal gate value for the auto-continue bucket in §5a rule 5: a pure precision/citation gap with
every structural flag `false`, repair cap exhausted, still below 9.0. **Not** a synonym for
`passed`, and — unlike §5d.1 — **does not block downstream stages**. Append one row to
`_pending/human-review-queue.md` with status `open` (the debt is real and should surface in the
rollup) but do not set `pending_human = true` for this reason alone.

##### 5d.3 `accepted_risk`

Terminal gate value meaning "a human saw a sub-threshold result — typically via the §5c circuit
breaker — and explicitly chose to proceed" — **not** `passed` and **not** the same as
`tech_debt_accepted` (which is an automatic, no-question-asked classification; `accepted_risk`
always follows a human decision point). Writing it requires also writing `resume_decision` (who
decided, on what evidence, what residual risk), and both `summary.md` and the `runs.md` row must
display it distinctly. Also append a row to `_pending/human-review-queue.md`.

Write the decided `quality_gate` value into the stage's `state.json` entry
yourself (quality-score does not write this field — if you find that key already present in a
scorecard write-back, treat it as a worker bug, overwrite it with your own derivation, and note it
in the summary).

**Whenever you dispatch a repair** (full-profile `repairing`, or the single fast-profile
structural retry): the moment the repair worker reports done and before you re-run
`quality-score`, write `repair_applied_at = <ISO-8601 now>` into that stage. This is the marker
that makes an interrupted run recoverable — if the session dies between the repair and the
re-score, resume can tell "already repaired, needs scoring" from "needs repairing" by comparing
timestamps, instead of inspecting document file mtimes.

### 5.5. Auto-verify phase

Runs immediately after `sa` completes and passes its gate.

**Verify policy gate**: read profile's `verify_policy` field if present (default
`always`).
- **`analysis_profile == fast` → always run the full verify phase; it is not skippable and not
  deferrable, not even on explicit user request.** Fast's entire precision argument is that this
  end-of-run systematic sweep substitutes for the per-stage repair loop; skipping it leaves the
  documents with neither safeguard. If the user asks to defer, offer a full run instead. This rule
  overrides both `verify_policy` and the deferral path.
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

Write `<harness_dir>/<run_id>/summary.md`: **`analysis_profile`**, `SCOPE.md` path, stage list with status/doc paths/confidence/pending-review totals, `quality_score / quality_gate / score_attempts / spot_check(passed/sampled) / structural_flags`, low-confidence stages (⚠️ prefix), gap-report links, any `tech_debt_accepted` stages (flagged distinctly from `passed`), the quality/diff calibration table (§5.6a), spec quality block (diff_rate ✅/⚠️, verify-report path, verify_round, threshold, patch summary: N patched / M deferred / patch_plan_path). If `diff_rate > threshold`, include the advisory note. If the run status is `verify-deferred`, state that clearly with a pointer to `verify-backlog.md`. If the run status is `stopped-needs-human`, state that clearly with the count of undecided worksheet rows and a pointer to the gap report + `_pending/human-review-queue.md`.

**Fast-run summary additions**: state `profile=fast` prominently at the top together with a line
declaring the output draft-grade and not a delivery basis; list each stage's `fast_pass` verdict
**alongside its real `score_10` / `completeness` / `spot_check`** (never hide the numbers behind
the verdict); print the upgrade command `/start-analysis <feature> --full`; report the end-of-run
`diff_rate` against the round-1 threshold as the run's primary quality evidence; and if this
`doc_root` has now accumulated ≥2 fast runs with no full run, warn that the feature's architecture
understanding has never been precision-verified.

Always append this block verbatim:

```
⚠️ 決策執行一致性：請 grep skills/ 與 agents/ 確認
無舊做法或硬編碼殘留，避免「決策寫了但 prompt 未更新」的執行脫節。
```

Update runs.md row (status, **profile**, re_analysis_count, last_stage, diff_rate, quality_min, failed_quality, docs N/total, ended ISO). Read whole → modify row in memory → write back whole.

Do **not** write session-level files outside `<harness_dir>` / `<docs_root>`.
