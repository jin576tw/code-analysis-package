# Analysis Harness Runs

> Index of all `start-analysis` runs. Newest on top. One row per run.
> `status` enum: `running | done | failed | partial | verify-deferred | stopped-needs-human`.
> `profile` enum: `full | fast`.
>
> **Reading `quality_min`**: for `profile=fast` rows a value below 9.0 is expected and **does not
> mean the run failed** — fast runs gate on structural correctness (`fast_pass`), not on the 9.0
> precision threshold, and rely on the end-of-run spec-vs-code verify for citation accuracy.
> Judge fast rows by `diff_rate` instead. A row whose gate is `accepted_risk` or `tech_debt_accepted`
> is **not** `passed`: `accepted_risk` means a human explicitly accepted a sub-threshold result (see
> that run's `resume_decision`); `tech_debt_accepted` means full profile auto-continued past a pure
> precision gap (no structural risk) — see `_pending/human-review-queue.md`.
>
> `status = stopped-needs-human` means the run halted at a gap-report worksheet with at least one
> undecided row (see `.claude/commands/start-analysis.md` §5d.1) — distinct from `partial` (a
> session-interrupted, resumable-without-a-decision state).

## Runs

| run_id | feature | entry_type | mode | profile | started | status | re_analysis_count | last_stage | diff_rate | verify_round | quality_min | failed_quality | docs | ended |
|--------|---------|------------|------|---------|---------|--------|-------------------|------------|-----------|--------------|-------------|----------------|------|-------|
