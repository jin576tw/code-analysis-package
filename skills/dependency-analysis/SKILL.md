---
name: dependency-analysis
description: Layer 1 analysis. Maps the dependencies of a target function/feature (which services, data-access, models, constants, external systems, jobs it touches) and produces DEPENDENCIES.md. Use when you need to know what a class/function calls and what data it reads/writes.
---

# Dependency Analysis (Layer 1)

Produces `DEPENDENCIES.md` for a target `<FUNCTION_NAME>`.

> **Read the profile card first.** Load `${CLAUDE_PROJECT_DIR}/.analysis-profile.md`
> for the module/layer map, tech stack, persistence conventions (schema prefix,
> id strategy), constant-class patterns and output path. If the card is missing,
> auto-detect from build files (`pom.xml`/`package.json`/etc.) and directory
> scan, then recommend running `/analysis-init`.
> **Also load skill `analysis-conventions`** (anti-hallucination, wording,
> diagram, human-review format).

## Output location

Write to the docs root + path convention from profile card §7. Default:
`${CLAUDE_PROJECT_DIR}/.analysis/docs/<MODULE>/<FEATURE>/<PAGE>/<FUNCTION_NAME>/DEPENDENCIES.md`

## What to analyse

Use the profile card's **module/layer map** to locate each layer; the labels
below are generic roles, not specific paths.

### 1. Code dependencies
- **Business/service layer**: injected services and data-access components
  (e.g. `@Autowired`/constructor injection, imports, DI registrations).
- **Data-access (mapper/repository/DAO)**: the SQL/query definitions each maps to.
- **Query/mapper definitions**: result mappings, shared SQL fragments, includes
  referencing other namespaces.
- **Domain models / DTOs**: entities/value objects passed around.
- **Hand-written vs generated data-access**: when the project distinguishes them
  (profile §6), confirm custom result-mapping references resolve correctly.
- **UI controllers**: view-model/controller methods bound to UI events, and the
  services they call.
- **View templates**: includes/compositions and expression bindings to
  controller methods.
- **Constant classes / enums**: per profile §6 pattern — note value mappings.
- **Utilities**: shared helper classes.

### 2. Data dependencies
- **Tables/collections**: confirmed in the query/mapper layer (include the
  schema prefix from profile §5 if any).
- **Sequences / id strategy**: per profile §5.
- **Views**: if a query targets a view rather than a table.
- **Cross-schema / cross-source access**: note when a query joins across schemas
  or uses a different data source / transaction manager (profile §5).
- **Transaction boundaries**: record each transactional method's propagation and
  which transaction manager / data source it uses.
- **Value/code mapping**: external→internal code conversions (profile §5/§6).

### 3. System dependencies
- **Service clients**: calls to external systems (SOAP/REST clients).
- **APIs**: REST/SOAP endpoints exposed or consumed.
- **Batch jobs**: job → step → reader/processor/writer chains (load the
  `batch-analysis` skill for batch entry points).
- **Scheduling**: timer/cron/quartz-triggered jobs.
- **Session/cache**: external session or cache stores.
- **File transfer / reporting / messaging**: SFTP/FTP, report generation, SMS/email.

### 4. Upstream data dependencies (reverse tracking)

> Goal: find "who provides the data this function reads", especially config and
> status-control tables/collections. These upstream sources define this
> function's behavioural preconditions (active periods, switches, thresholds).

#### 4.1 Trigger conditions (track only if ALL hold)
For each data source the function accesses:
1. ✅ this function only **reads** it (no write).
2. ✅ it is **not** in the exclusion list (§4.3).
3. ✅ its data **controls this function's behaviour** (used in if/else, a
   disabled/visible condition, or a flow branch).

#### 4.2 Tracking method (no depth limit, but annotate the depth)
- **Level 1 — same-feature scan (always, cheap)**: from the profile's
  module/layer map (and any UI page map), find sibling entry points in the same
  feature; scan their controllers' injected dependencies; if one writes
  (INSERT/UPDATE) the same source, record it as an upstream provider (depth 1).
- **Level 2 — config-source reverse search (conditional, capped)**: if level 1
  found nothing and the source meets §4.1, grep for all usages of that
  data-access component; **cap at 5 users** (beyond that, just list them);
  confirm each user's operation type; record only those that INSERT/UPDATE
  (depth 2).
- **Level 3+ — recursive (annotate depth, no hard cap)**: if a provider itself
  reads other control sources meeting §4.1, keep tracking, annotate `[depth N]`,
  keep the 5-user cap per level, and mark `⚠️ circular dependency` if a cycle
  forms (A→B→A) and stop.

#### 4.3 Reverse-tracking exclusion list
Skip system-wide shared sources that nearly every feature reads (reverse
tracking is meaningless). Take the concrete list from the profile card if it
defines one; otherwise treat these **roles** as excluded:
code/lookup tables, global system config, users/roles/permissions, menus, HR
master data, message templates, report config, audit/login/click tracking.

#### 4.4 Result recording
Record providers in the "Upstream data sources" section of `DEPENDENCIES.md`.

## Output format

### Dependency summary
| Dependency type | Count | Importance | Examples |
|-----------------|-------|-----------|----------|
| Service | n | high/med/low | … |
| Data-access (generated) | n | … | … |
| Data-access (hand-written) | n | … | … |
| Tables/collections | n | … | … |
| UI controller | n | … | … |
| View/page | n | … | … |
| External system | n | … | … |
| Constants/enum | n | … | … |
| Batch job | n | … | … |

### Detailed dependency matrix
| Source | Depends on | Type | File location | Usage context |
|--------|-----------|------|---------------|---------------|

### Dependency tree
```
<FUNCTION_NAME> (description)
├── UI layer            ├── controller / view
├── Service layer       ├── business logic / called services
├── Data-access layer   ├── mappers/repos + tables (with schema prefix)
├── External systems    ├── service clients / report / SMS / email
└── Batch jobs          └── job chain
```

### Value-conversion table
| Source value | Internal value | Meaning | Defined at |
|--------------|----------------|---------|-----------|

### Upstream data sources
| Source | This fn op | Controls what | Upstream provider | Provider op | Provider page/job | Depth |
|--------|-----------|---------------|-------------------|-------------|-------------------|-------|

> Omit this section if reverse tracking found no providers.

### Items needing human review
Append the "⚠️ Items needing human review" section (format in
`analysis-conventions` §11). For DEPENDENCIES focus on: external system real
endpoints/SLA, actual config/property values, cross-system file-exchange specs.

## Steps
1. Replace `<FUNCTION_NAME>` with the real name.
2. From the entry point (per profile entry-point type), trace inward.
3. Find injected services / data-access.
4. Record transaction annotations and boundaries.
5. Trace queries to confirm tables/collections.
6. Confirm hand-written data-access result-mapping references.
7. Confirm constant/value-mapping completeness.
8. Record external system calls.
9. Check for an associated batch job.
10. Run upstream data-dependency tracking (§4) and record providers.

## Self-check
- [ ] All injected dependencies recorded.
- [ ] All queries mapped to tables/collections.
- [ ] Hand-written data-access result-mapping references confirmed.
- [ ] UI expression bindings traced to controller methods.
- [ ] Transaction propagation / manager recorded.
- [ ] Value-conversion maps confirmed complete (all branches covered, fallback?).
- [ ] External endpoints recorded.
- [ ] Table/collection names confirmed in queries (with schema prefix).
- [ ] Id/sequence strategy confirmed; cross-schema access annotated.
- [ ] Write semantics confirmed where the framework distinguishes full vs partial
      writes (e.g. full-row vs non-null-only insert/update).
- [ ] Object-reference sharing side effects considered.
- [ ] Upstream tracking: read-only sources listed, exclusions applied, providers
      confirmed, depth annotated, no uncaught cycles.
- [ ] Every dependency traces to real code; paths/class/table names confirmed; no
      assumptions about "standard" dependencies.

## Common framework pitfalls (apply those relevant to the project's stack)
- Full-write vs partial-write data-access calls (non-null-only) → unintended
  null overwrite.
- New/independent transaction propagation commits survive an outer rollback.
- Cross transaction-manager / cross-data-source operations are not one transaction.
- Shared object references mutated by another method.
- Mixing external raw codes vs internally-converted codes.
- UI component bound value not matching the backend constant type.
