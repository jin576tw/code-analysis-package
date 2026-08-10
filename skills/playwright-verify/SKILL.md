---
name: playwright-verify
description: Risk-based browser verification for code analysis. Use for UI behavior involving JavaScript, AJAX, browser downloads, layout/responsive rendering, dialogs, timers, or other runtime-only behavior; skip when static evidence is sufficient or UI is not applicable. Mock output is simulation, never runtime evidence.
---

# Playwright verification

Classify first:

- `not_applicable`: non-UI target; skip.
- `static_pass`: deterministic server-rendered behavior is fully supported by source citations;
  record the citations and skip browser execution.
- `playwright_required`: a browser/runtime signal exists and a runnable environment is available;
  run Playwright against that environment.
- `blocked_runtime_evidence`: material runtime behavior needs confirmation but no runnable
  environment exists; stop rather than fabricate proof.

Runtime signals include JavaScript, AJAX/partial updates, client validation, browser downloads,
dialogs, layout/responsive behavior, timers, WebSockets, and browser APIs.

## Evidence levels

Live Playwright observations may be `runtime-confirmed`. Static source tracing is `static`. Mock
HTML, Mock services, generated data, and screenshots of those assets are `simulation`; label them
prominently and never use them to clear a runtime-required finding.

## Execution

Use the shared root Playwright installation. Never install per feature. Read credentials only from
the profile-named environment variable. Capture the minimum scenarios needed for each runtime
claim and write expected/observed results with screenshots. If the environment or browser setup
fails and the claim is material, return `blocked_runtime_evidence`; do not downgrade it to a Mock
pass.

Static spec-vs-code verification is separate and may continue for claims that do not depend on a
browser.
