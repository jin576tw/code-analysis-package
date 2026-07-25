# Human Review Queue

> Cross-run rollup of everything a `start-analysis` run flagged as needing a human decision:
> `failed_structural` (gap-report worksheet, see `.claude/commands/start-analysis.md` §5d.1),
> `tech_debt_accepted` (§5d.2 — informational, not blocking), and `accepted_risk` (§5d.3). Lives
> under `<docs_root>/_pending/` so it survives the harness directory's 7-day cleanup — the docs
> repo is where this needs to persist. Newest on top.
>
> `status` enum: `open | resolved`. A row moves to `resolved` only when its source gap-report
> worksheet row (or `resume_decision`) has every item decided.

## Queue

| run_id | doc | stage | gate | score | open questions (link to worksheet) | recommended action | status | date |
|--------|-----|-------|------|-------|-------------------------------------|---------------------|--------|------|
