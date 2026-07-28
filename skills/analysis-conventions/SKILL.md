---
name: analysis-conventions
description: Generic methodology shared by all code-analysis and verification skills/agents. Anti-hallucination rules, comment handling, speculation classification, precise wording, diagram conventions (mermaid/ASCII), and the human-review checklist format. Load this before producing any analysis document.
---

# Analysis Conventions (shared methodology)

> Applies to every analysis activity (all skills, agents, orchestrators) in this
> plugin. These rules are **project-agnostic** — they describe *how* to analyse,
> never *what* a specific project contains. Project-specific facts (paths, tech
> stack, table prefixes, constant classes, entry-point types) come from the
> project profile card `.analysis-profile.md` (see the `analysis-init` skill).

---

## 1. Anti-hallucination principles

1. **Every conclusion must trace to an actual line of code** — never assume
   "standard" behaviour.
2. **File paths must be confirmed to exist** — never guess file locations.
3. **Class / method names must match the source exactly** — never invent
   signatures.
4. **Table / collection names must be confirmed in the query/mapper layer** —
   include any schema prefix the project uses (see profile card).
5. **Constant values must be confirmed in the constant definition** — never
   assume code values.
6. **External system endpoints must be confirmed in client code or config.**
7. **Anything that cannot be confirmed is marked `⚠️ needs human review`** —
   prefer flagging uncertainty over fabricating.

## 2. Comment handling

- Treat all code comments as **speculation**, not fact (comments may be stale or
  wrong).
- Code behaviour is fact — if/else logic, method calls, DB operations are
  certain.
- When behaviour conflicts with a comment, flag it with ⚠️.

## 3. Human-review threshold

When an item cannot be confirmed, first try to find the answer in the code
(up to 3 attempts). Only after 3 failed attempts list it under the
"⚠️ Items needing human review" section.

### 3a. Conditional behaviour is not an unknown — trace it, don't test it

A behaviour that depends on a **runtime condition** (cache present or not, prior state, a config
flag) is not automatically "needs human/runtime confirmation." If the triggering condition itself
is knowable from code — a lifecycle hook, a stored/cached value's origin, a watcher's `deep`
option, whether a value is mutated in place vs. reassigned/cloned — trace it to a decision, and
document **both outcomes as an explicit branch** (a decision diamond in a flowchart, or a stated
if-condition/else-condition pair in prose), not a single flattened claim. Collapsing a
code-derivable branch into one asserted outcome, discovering it contradicts source, and then
escalating to "needs runtime testing" is a process defect, not a legitimate escalation — the branch
was resolvable the whole time; a human is not needed to describe deterministic control flow.

For stateful/reactive frontend frameworks specifically (Vue/React/similar), before declaring an
object-mutation or reactivity question unresolvable, trace all of:
- **Lifecycle order** — which hook runs first, and does a later hook reassign what an earlier hook
  set up (e.g. a `created()`/`mounted()` branch that replaces a reference established in `data()`)?
- **Reference vs. clone** — is the value a direct object/array reference (mutating it mutates the
  original elsewhere) or a spread/deep copy (mutations stay local)?
- **Watcher/observer granularity** — does a `watch` fire on property mutation, or only on
  reassignment of the whole value (Vue's `deep: true` vs. the default shallow; equivalent
  distinctions in other frameworks)? A shallow watcher silently not firing is a code fact, not a
  runtime unknown.
- **Explicit sync/emit contracts** — does the component actually emit the update event a `.sync`/
  two-way-binding pattern implies, or does it silently rely on shared-reference mutation instead?

Escalate to human review only when, after this trace, the fact still depends on something **not
present in the repository at all** — true business intent, an external system's behaviour, or live
concurrency/timing that cannot be read off a call graph (analysis-conventions §8a's
`business-input` boundary). A question of "which of these two code-visible branches executes" is
answered by describing both branches with their trigger condition, not by asking a human to click
a button and watch.

The same discipline applies when **reconstructing** — not just describing — executable logic (SQL,
pseudocode, boolean expressions) from a business-language summary elsewhere in the docset. A
summary preserves business intent ("excludes student policies") but not the exact operator
placement; `NOT EXISTS(x = y)` and `EXISTS(x <> y)` read as equivalent from a summary but are not
logically equivalent in every data shape. Verify a reconstruction against the literal
predicate/condition-building source (a `Specification`/`Predicate` class, not the doc that
describes its effect) before treating it as accurate. Observed in production: an "equivalent SQL"
section manually added to a report's SA.md reconstructed a `POS_POLICY` exclusion filter as
`NOT EXISTS(SPECIAL_TYPE = 'STUDENT')` from ERD.md's "excludes student policies" summary, when the
source `Specification` class actually builds `EXISTS(SPECIAL_TYPE <> 'STUDENT')` — the two behave
differently for policies with no matching row or with mixed special types across multiple rows.

## 4. Analysis focus

- **Ignore comments, focus on data flow** — concentrate on actual logic and how
  data is passed.
- **Avoid vague preconditions** — every described scenario must state *how that
  state is reached*: concrete page/screen names, operation steps, system
  responses.

## 5. Reasoning trail

- For Layer 3+ documents, every non-obvious conclusion must carry a reasoning
  note (source of inference, code location, confidence).
- For special control flows (independent/new transactions, cross transaction
  manager, conditional rollback, etc.) explain *how the behaviour was derived
  from the code*.

## 6. Flow-first principle

- Layer 3 (Flowchart) must confirm the real execution flow from code **before**
  deriving business rules. Never start from assumptions.
- When analysis reaches a related module, decide whether to go deeper per the
  dependency-analysis skill's trigger conditions (no depth limit, but annotate
  the level).

## 7. Precise wording

| Term | Precise meaning | Forbidden vague use |
|------|-----------------|---------------------|
| simultaneously / 同時 | executed sequentially within one operation (not parallel); user perceives one action | must not imply parallel execution |
| afterwards / 之後 | previous step completed (system responded), then user takes next step | must not be used for continuous processing of one button click |
| immediately / 立即 | completed within the response to one button click; no waiting / re-operation | must not be used for scheduled / batch scenarios |
| finally / 最終 | state after all processing done and data permanently persisted | must not be used for intermediate states |
| triggered / 觸發 | deferred or asynchronous execution driven by an event/condition | must not be used for a direct button-click response |
| automatically / 自動 | runs by itself per a condition, no user intervention | must not be used for operations needing user confirmation |

## 8. Speculation source classification

| Source type | Description | Confidence |
|-------------|-------------|-----------|
| Code logic | derived directly from if/else, switch, method calls | High |
| Variable naming | inferred from variable/method names | Medium |
| Code comments | inferred from `//` or `/* */` | Low (treat as speculation) |
| Constant naming | inferred from constant names | Medium |
| Context inference | inferred from call chains / data flow | Medium |
| Unconfirmable | cannot be derived from code at all | Very low (list for human review) |

## 8a. Relation visibility grading

Code can mechanically prove **call relationships** (page → endpoint → service → table) and
**shared resources** (the same endpoint/table used by other features). It cannot show **business-
process sequencing** (workflow stage order, cross-service timing, human approval steps) — that
lives in status-code semantics, external specs, or a workflow engine's own definitions, not in the
call graph. Treat this as a hard boundary, not a gap to paper over with inference: when a document
lists a cross-feature relation (in `DEPENDENCIES.md` §12-equivalent cross-feature entries, or in a
Scope Card), grade it explicitly so a reader never mistakes "not documented" for "does not exist":

| Grade | Meaning | Maps to §8 confidence |
|-------|---------|------------------------|
| `code-derived` | call relationship or shared endpoint/table, directly provable from source | High |
| `inferred` | relation suggested by naming/context, not a direct call | Medium |
| `business-input` | process ordering, cross-service timing, workflow-engine definitions — **code cannot show this**; must be confirmed from a spec or a domain expert, never guessed | requires human confirmation; do not assign a confidence level in place of confirming it |

A `business-input` item is not a failure to analyse deeply enough — it is outside what static
analysis of this codebase can determine. Tag it `business-input — pending` and stop; do not
speculate a process order from table/status-code naming and present it as if it were code-derived.

---

## 9. Audience tone (for output documents)

### SA documents (readers: business units, PM, QA)
- ✅ Conversational, like explaining the feature to a colleague.
- ✅ From the screen-operation angle: user does X → system does Y → screen shows Z.
- ✅ Given-When-Then scenarios concrete enough for QA to write test cases.
- ❌ No technical jargon (mapper, transaction propagation, etc.).
- ❌ No code-level detail (class names, method signatures).

### SD documents (readers: developers)
- ✅ Keep technical detail (method decomposition, I/O specs, exception paths).
- ✅ Annotate the entry point location (full path UI → Service → data layer).
- ✅ Focus on the "why" of design decisions.
- ❌ Do not translate code line-by-line.
- ❌ Do not list every getter/setter call.

### API-CONTRACT documents (readers: external integration developers)
- ✅ Each API self-contained; list **all** fields (including inherited common fields).
- ✅ Every field has type, required flag, validation rule, description.
- ❌ No "same as above" / "see above" shortcuts.
- ❌ Do not omit fields inherited from a parent class.

---

## 10. Diagram conventions

### Primary format: mermaid

| Scenario | mermaid type | Notes |
|----------|--------------|-------|
| Main flow / branching | `flowchart TD` | diamond decisions, rectangle steps |
| Method-call sequence | `sequenceDiagram` | cross-system / cross-layer calls |
| State transitions | `stateDiagram-v2` | status machines |
| Transaction boundary | `flowchart TD` + subgraph | frame the Tx scope with subgraph |
| Batch step flow | `flowchart TD` | step chaining + failure branches |

### Fallback: ASCII

Use ASCII when mermaid cannot express clearly:
- complex nested transaction boundaries (multi-layer subgraph hard to read)
- data-flow diagrams (multi-column field mapping clearer as ASCII tables)
- precise side-by-side comparison
- layered architecture diagrams (multi-level nested component relations)

### mermaid authoring rules

1. **Node IDs** in English (e.g. `validate01`); display text may be any language.
2. **Decision nodes** use `{}` diamonds.
3. **Process nodes** use `[]` rectangles.
4. **Start/end** use `([])` rounded.
5. **subgraph titles** annotate transaction info (e.g. `subgraph Tx-A [NEW TX, dataSourceX]`).
6. **Risk annotation** add ⚠️ inside node text.
7. **External systems** use `[/ExternalName/]` parallelograms or annotate in participants.

### ASCII symbols

| Symbol | Use |
|--------|-----|
| `┌─┐│└─┘` | rectangle frames (steps, components) |
| `▼ → ←` | flow arrows |
| `├── └──` | tree structure |
| `⚠️` | risk annotation |
| `[Y] [N]` | conditional branches |
| `───────` | separator |

---

## 11. Human-review checklist format

Per §3, when AI cannot confirm a conclusion after 3 attempts, list it. Append
this section to the end of every analysis document:

```markdown
---

## ⚠️ Items needing human review

| # | Item | Speculation | Source | Confidence | Impact |
|---|------|-------------|--------|-----------|--------|
| 1 | (what needs confirming) | (current guess) | code comment / naming / context | low / med / high | which section/conclusion it affects |

> How to confirm: a domain expert reviews the "Speculation" column and fills in
> ✅ confirmed / ❌ corrected to "...". After confirmation, notify the AI to
> regenerate the affected sections.
```

Field definitions:

| Field | Meaning |
|-------|---------|
| # | running number |
| Item | the question to confirm |
| Speculation | the AI's current guess |
| Source | source type from §8 |
| Confidence | high / med / low per §8 |
| Impact | which sections change if corrected |

Confidence mapping (per §8):
- **High**: derived directly from if/else, switch, method calls.
- **Medium**: from variable/constant naming or context inference.
- **Low**: inferred from code comments (comments are speculation).

---

## 12. Fast-profile document banner

When the orchestrator dispatches you with `analysis_profile=fast`, you **must** write a
provenance banner into every document you produce. The banner is what tells a future reader —
and a future full-profile run — that this document has not been through the per-stage precision
loop. It is written by **you** (the worker), not by the orchestrator: the orchestrator is
forbidden from editing files under `<docs_root>` directly.

**Placement**: immediately after the `> **Entry Point**:` line, before any other content.

**Verbatim template** (fill every `<...>` from the values passed in your dispatch prompt; leave a
placeholder only if the value genuinely is not yet known at write time):

```markdown
> 🚀 **FAST-MODE 產出（架構認知用草稿，非交付級分析）**
> `analysis_profile: fast` | run_id: <run_id> | generated: <YYYY-MM-DD>
> 本文件通過「結構正確性」gate（四項矛盾型 structural_flags 全 false、Completeness ≥ 3.0），
> **未經** per-stage `score_10 >= 9.0` 精確度迴圈。行號 / 欄位級引用僅由結尾一次
> spec-vs-code verify 批次校正，可能仍有偏移。
> 產出範圍與完整模式相同（含 ui-verify 與 Layer 5 verify），差異僅在未做逐階段精度修補。
> ⛔ 不得作為交付依據。補全指令：`/start-analysis <功能> --full`
```

**Rules**:

1. `analysis_profile: fast` must appear **verbatim** — it is the machine-readable marker that
   `start-analysis` greps for when deciding whether a later full run may reuse this document.
2. Do **not** write the banner when dispatched with `analysis_profile=full` (or with no profile
   given — absence means `full`).
3. When a full-profile run upgrades a fast document and it clears the 9.0 gate, the banner is
   **rewritten** to `analysis_profile: full` rather than deleted, so the upgrade remains visible
   in the document's own history.
4. **§13-equivalent confidence tightening**: in a fast-profile document, any bug candidate or
   static inference must be labelled at confidence **低（靜態推論，待 stack trace）** at most.
   Fast output is less verified than full output, so the labelling obligation is stricter, not
   looser. Never write `已確認` / `confirmed` / `HIGH confidence` in a fast document.
5. The banner states the profile, not a quality verdict — do not editorialise it, soften it, or
   omit the ⛔ line. A reader who skips the banner is exactly the failure mode it exists to
   prevent.
