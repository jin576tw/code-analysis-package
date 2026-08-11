# Fast output contract

The package owns the contract schema, collector vocabulary, evidence integrity, and review gate.
The consuming project owns the target document and its required evidence. Start from
`templates/fast-output-contract.template.json`; keep the contract outside the plugin when it is
project-specific.

## Contract fields

- `contract_schema`: currently `1`.
- `contract_id`: stable project-owned identifier.
- `target_document.path`: run-relative output path; never hard-code a domain document name in the
  package.
- `target_document.role`: project-defined purpose.
- `target_document.required_sections[]`: exact stable section IDs the Maker must cover.
- `evidence_requirements[]`: project-defined requirements with unique `id`, `description`,
  `required`, `allowed_not_applicable`, `collectors[]`, and `target_sections[]`.

Allowed core collector IDs are `dependencies`, `symbols_data`, `data_model`, `functions`,
`execution_flow`, `business_rules`, `ui_behavior`, `api_contract`, and `system_design`. They map to
the package's existing analysis skills. Fast executes only collectors requested by the contract
and records `materialized_document=false`; Full remains responsible for materialized layer docs.

Every covered requirement must contain at least one evidence item with a source path and stable
locator. `not_applicable` is valid only when the contract explicitly allows it and the evidence
records why. Separate observed AS-IS facts, approved requirements, and proposed design. Never turn
an inference into an approved fact.
