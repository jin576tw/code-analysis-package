---
name: playwright-verify
description: Risk-based browser verification for code analysis. Use for UI behavior involving JavaScript, AJAX, browser downloads, layout/responsive rendering, dialogs, timers, or other runtime-only behavior; skip when static evidence is sufficient or UI is not applicable. Mock output is simulation, never runtime evidence. Producing one illustrative Mock screenshot per screen for SA documentation is a separate, always-on step, decoupled from this risk classification.
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

Skipping browser execution for `static_pass` means skipping *runtime verification* only — it is
not license to skip producing a screenshot for the SA document. See "Illustrative screenshot" below;
that step runs regardless of which of these four classifications applies (except `not_applicable`,
which has no screen to shoot).

## Evidence levels

Live Playwright observations may be `runtime-confirmed`. Static source tracing is `static`. Mock
HTML, Mock services, generated data, and screenshots of those assets are `simulation`; label them
prominently and never use them to clear a runtime-required finding.

## Illustrative screenshot (always-on, decoupled from risk classification, 2026-08-31)

For every screen/dialog/tab object that is not `not_applicable` (i.e. a real UI surface exists),
produce at least one Mock screenshot for SA §3.1 embedding — independent of whether the risk
classification itself required Mock/Playwright to resolve a runtime claim. A `static_pass` target
still needs this: the risk decision and the documentation screenshot answer two different
questions ("do we need to observe running behavior to confirm a claim" vs. "can a reader see what
this screen looks like"), and skipping the first must never silently skip the second. Mark every
such image `simulation`; it never upgrades a `static_pass` classification and is never cited as
proof of runtime behavior. Omit only when no renderable markup/template exists to build a Mock
render from at all, and record why.

## Execution

Use the shared root Playwright installation. Never install per feature. Read credentials only from
the profile-named environment variable. Capture the minimum scenarios needed for each runtime
claim and write expected/observed results with screenshots. If the environment or browser setup
fails and the claim is material, return `blocked_runtime_evidence`; do not downgrade it to a Mock
pass.

Static spec-vs-code verification is separate and may continue for claims that do not depend on a
browser.
