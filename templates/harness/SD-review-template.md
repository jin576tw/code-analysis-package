# <FUNCTION_NAME> — SD Review (SD-review)

> Review date: YYYY-MM-DD
> Subject: `<docs_root>/<MODULE>/<FEATURE>/<PAGE>/<FUNCTION_NAME>/SD.md`
> Compared against: actual code (<key source files>)
> Method: three-layer comparison (mock(A) ↔ real code(B) ↔ SD(C)); UI entry
> points also get dynamic E2E verification.
> Produced by: verify-spec mini-orchestrator (vspec-mock → vspec-static → vspec-report)

---

## §1 Summary stats

| Metric | Value |
|--------|-------|
| Total reviewed items | N |
| ✅ Correct | N (X%) |
| ⚠️ Omission (code has it, SD doesn't) | N (X%) |
| ❌ Wrong (SD contradicts code) | N (X%) |
| **diff_rate (omission + wrong)** | **N items, X%** |
| E2E UI diffs (UI entry points only) | N / N/A (non-UI) |

> Formula: `diff_rate = (❌ wrong + ⚠️ omission) / total reviewed items`.
> Mode B (linked-update): denominator is only items in the re-analysed stages.
> When diff_rate > 10%, the orchestrator asks whether to re-enter start-analysis.

---

## §2 Difference detail

### ❌ Wrong (SD contradicts code)

#### D-XX: <title>
- **SD location**: §N.N <section>
- **SD says**: <SD's text>
- **Real code** (`<File>` line N):
  ```
  <key snippet>
  ```
- **Difference**: <why SD contradicts code>
- **Impact**: <which SD sections>

### ⚠️ Omission (code has it, SD doesn't)

#### D-XX: <title>
- **SD location**: <related section or "not mentioned">
- **Real code** (`<File>` line N):
  ```
  <key snippet>
  ```
- **Difference**: <behaviour present in code but absent from SD>
- **Impact**: <which SD sections>

---

## §3 Confirmed correct

| # | SD location | Confirmed content | Code evidence |
|---|-------------|-------------------|---------------|
| C-01 | §N.N | <content> | <File> line N |

---

## §4 UI behaviour (E2E) differences

> UI entry points only. Otherwise: **N/A (entry point is <WS/REST/Batch>)**

| # | Test case | Operation | Documented | Observed | Type | Section |
|---|-----------|-----------|-----------|----------|------|---------|
| E-01 | <TC> | <op> | <doc> | <observed> | ❌/⚠️ | §N.N |

---

## §5 Recommended fixes

> Read-only review; it does not edit existing docs. When diff_rate > 10% the
> orchestrator offers to re-enter start-analysis (code is the source of truth).

| Priority | Diff id | Fix action | Affected SD section |
|----------|---------|------------|---------------------|
| High | D-XX | <action> | §N.N |

---

## §6 Overall assessment

<3-5 sentences: core architecture correctness; where differences cluster
(architecture / signatures / implementation detail); the most notable risk.>

---

*Produced by verify-spec three-layer comparison (mock + static code + SD).*
*Static comparison does not cover: real external-system behaviour, runtime data,*
*environment-specific config. E2E UI verification (if run) uses Mock HTML by*
*default and does not connect to a live environment.*
