# Alpha Sprint 1 Plan

- **Sprint Window:** 14 Oct 2025 → 27 Oct 2025 (2 weeks)
- **Goal:** Establish the first Alpha-capability slice that proves Ripple can scale beyond the MVP by shipping foundational routing, forms, SSR, and tooling capabilities with production discipline.
- **Theme:** "Path to Premier" – demonstrate that Ripple can compete with Leptos/Yew by tightening DX and shipping a showcase experience.

## Objectives & Success Criteria

| Objective | Success Criteria |
| --- | --- |
| Advanced Router Foundation | File-based route loader, lazy module API, scroll restoration hook, and integration tests passing on desktop/mobile targets |
| Forms & Validation Pipeline | Core form store + binding API lands behind feature flag, schema adapter trait (zschema-compatible) implemented with unit tests |
| SSR + Islands Commerce Demo | High-level architecture doc + repository skeleton with streaming hydration stub merged, smoke test renders home page SSR path |
| Component Primitives | Accessible Dialog + Tabs primitives published with story docs, axe-core lint run locally with zero critical issues |
| CI & Automation | CI pipeline executes linting, `zig build test`, wasm build, and publishes preview artifacts on PR |
| Alpha Playbook | Living document outlining architecture guardrails, coding standards, review checklist, and sprint rituals |

## Sprint Backlog

### 1. Advanced Router Foundation
- [x] **R1.1** Router file-system manifest generator (initial pass)
- [x] **R1.2** Lazy route boundary loader skeleton with caching hooks
- [x] **R1.3** Scroll restoration and history abstraction with regression tests (router history manager + scroll restore tests)
- [x] **R1.4** Navigation guard API design doc + spike implementation ([design notes](../design/router-guards.md), guard pipeline + tests)

### 2. Forms & Validation Pipeline
- [x] **F1.1** Form store core (field registration, dirty/touched tracking) ([design](../design/form-store.md), new `FormStore` module + tests)
- [x] **F1.2** Input binding helpers for text/select/checkbox (bindings API, memoised checkbox attribute, unit tests)
- [x] **F1.3** Validation adapter trait + zschema prototype adapter (per-field error/valid signals, aggregate validity, unit tests)
- [x] **F1.4** Progressive enhancement demo (native `<form>` submit fallback bindings, serialization helpers, docs/tests)

### 3. SSR + Islands Commerce Demo
- **S1.1** Architecture design doc (data flow, streaming stages, error handling)
- **S1.2** Project scaffolding under `examples/commerce-ssr`
- **S1.3** Streaming hydration pipeline stub (server render + suspense boundary)
- **S1.4** Basic catalog page SSR smoke test (CLI run + snapshot)

### 4. Component Primitives
- **C1.1** Accessibility checklist + audit tooling integration (axe-core runner)
- **C1.2** Dialog primitive (focus trap, aria attributes, escape/overlay handling)
- **C1.3** Tabs primitive (roving tabindex, keyboard support, panel linking)
- **C1.4** Storybook-lite playground page with usage samples

### 5. CI & Automation
- **T1.1** GitHub Actions (or Zig-native) workflow running lint + `zig build test`
- **T1.2** Add wasm build step with artifact upload (counter + commerce demo)
- **T1.3** PR comment bot summarizing test results + preview URLs
- **T1.4** Nightly job running hydration regression suite in headless browsers

### 6. Alpha Playbook
- **P1.1** Draft architecture guardrails (module boundaries, async rules)
- **P1.2** Coding standards (naming, error handling, allocator usage)
- **P1.3** Review checklist (tests, docs, perf budget, accessibility)
- **P1.4** Sprint ritual doc (planning, standups, demos, retro template)

## Milestones & Timeline

| Week | Milestone |
| --- | --- |
| Week 1 (Oct 14-20) | Complete router manifest + lazy loader spikes, form store core, SSR design doc, Dialog primitive skeleton, CI workflow bootstrap |
| Week 2 (Oct 21-27) | Finish scroll restoration + guard API, validation adapter, SSR stub + smoke test, Tabs primitive, CI preview pipeline, Alpha playbook published |

## Testing & Quality Gates
- Unit tests for router, form store, validation adapters, and primitives (`zig build test`).
- Integration tests: headless navigation scroll restore, SSR smoke snapshot, progressive enhancement fallback.
- Accessibility: axe-core/pa11y run against Dialog and Tabs stories.
- Performance budget checks for hydration hot paths (<20ms on dev sample).

## Dependencies & Risks
- **Dependencies:** zschema schema adapter availability, CI secret management for preview deployments, headless browser infrastructure.
- **Risks:** Scope creep in SSR demo, accessibility tooling setup delays, lack of dedicated design assets for commerce demo.
- **Mitigations:** Time-box spikes, leverage existing dashboard assets, schedule accessibility reviews mid-sprint.

## Definition of Done
- All backlog items merged to main with passing CI.
- Sprint demo featuring router navigation, forms PE fallback, SSR catalog page, and component stories.
- Alpha playbook merged and referenced from `README.md`/`TODO.md`.
- Retro notes captured with action items for Sprint 2.
