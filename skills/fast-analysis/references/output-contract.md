# Fast output contract

The Maker must cover these six evidence groups in one integrated target document:

| Evidence group | Required target coverage |
|---|---|
| `scope_uc` | entry, actor, scope boundary, use cases, exclusions |
| `flow_rules` | main/alternate/exception flows, validations, business rules |
| `screen_fields` | screens, fields, controls, sources, display and edit behavior; use evidenced N/A for non-UI |
| `api_contracts` | operations/endpoints, request/response, validation and errors; use evidenced N/A when absent |
| `interactions` | frontend/backend/database/external-system sequence and transaction boundaries |
| `data_model_and_supplementary` | entities/tables/relationships/fields plus codes, formulas, constraints, and evidenced N/A items |

Every evidence item must include a source path and stable locator. Separate observed AS-IS facts,
approved target requirements, and proposed design. Never turn an inference into an approved target
fact.

The integrated document may use project-specific formal headings. Record those headings in
`output_contract.required_sections` and prove every required section in
`coverage.covered_sections`.
