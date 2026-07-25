# Scope Card — <FEATURE>

> Produced at Layer 0.5 (`.claude/commands/start-analysis.md` §3.0.5), before `deps` dispatch.
> A directed, cheap scan — not a project-wide relation index. Regenerate freely as the menu/doc
> set changes; not scored by `quality-score`.

## 1. Target

- **Entry point**: <file/route>
- **Navigation path**: <menu/route source> → <path>

## 2. Relation scan (directed, bounded)

| Relation | Target | Visibility | Source |
|----------|--------|------------|--------|
| calls | <endpoint/table> | code-derived / inferred / business-input | <this entry file, grep evidence> |
| shared-with | <existing analysed doc under docs_root> | code-derived | <doc path> |
| sibling | <same-level menu/route entry> | code-derived | <menu/route source> |

> `business-input — pending` rows: business-process sequencing, cross-service timing, workflow-
> engine (BPM) definitions — code cannot show these; do not guess, tag and move on.

## 3. Scope boundary

**In scope (analysed in full this run)**:
- <item>

**Out of scope (cross-reference only, not expanded)**:
- <item> — see <existing doc path or "pending: not yet analysed">

---

## User confirmation

- [ ] Scope confirmed as-is
- [ ] Scope adjusted: <what changed>

> Confirmed by: <user> on <date>. `deps` is not dispatched until this box is checked.
