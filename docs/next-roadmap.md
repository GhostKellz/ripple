# Ripple Roadmap: Toward a Zig-first WASM Experience

## Overview
This roadmap translates the high-level goals into actionable work streams leading to a Yew/Leptos-class developer experience for Ripple. Each track lists near-term milestones (1–3 Sprints) and medium-term outcomes (4–9 Sprints). Suggested sequencing follows the order below, but tracks can progress in parallel with owner availability.

---

## 1. Form Ecosystem Polish
**Goals:** Production-ready form handling, async validation demos, PE integration.

### Sprint-ready tasks
- [x] Ship a `Zod`-style schema adapter prototype (parity with server-side validators).
- [x] Build cross-field validation helpers (dependent fields, form-level schemas).
- [x] Author SSR + progressive enhancement demo (HTML form + async server roundtrip).
- [x] Add accessibility checklist: error summaries, focus management, ARIA patterns.

### Medium-term
- Form analytics hooks (submission outcomes, validation metrics).
- Validation adapter registry with plug-and-play community adapters.
- Cookbook recipes (debounced inputs, optimistic submits, wizard workflows).

---

## 2. Router & Data Loading
**Goals:** Nested layouts, streaming data, SSR-compliant navigation.

### Sprint-ready tasks
- Implement route manifest generator & nested layout runtime.
- Introduce loader/action API with suspense-aware error boundaries.
- Add streaming hydration support & server data prefetch hooks.
- Provide integration tests covering navigation, guard enforcement, scroll restoration.

### Medium-term
- Static site generation (SSG) primitives & incremental rehydration.
- Devtools overlay for routing events and loader timing.
- CLI scaffolds for route modules and guard templates.

---

## 3. Component Library Foundations
**Goals:** Accessible primitives comparable to Radix/Leptos components.

### Sprint-ready tasks
- Deliver Dialog, Menu, Tabs MVP with paired tests & docs.
- Create Storybook-style playground (Ripple playground) with WASM + server rendering.
- Add design tokens + theming integration baseline.

### Medium-term
- Expand set (Popover, Tooltip, Combobox) backed by accessibility audits.
- Publish component packages with tree-shaking examples.
- Performance benchmarking harness against client interactions.

---

## 4. Tooling & Developer Experience
**Goals:** Fast iteration loop, productive CLI, automated quality gates.

### Sprint-ready tasks
- Bootstrap `ripple` CLI: dev server with HMR stubs, config loader, and component scaffolding.
- Integrate wasm bundling pipeline (wasm-opt, asset graph) into `zig build`.
- Establish GitHub Actions workflows (lint, test, wasm smoke).

### Medium-term
- Diagnostics overlay (signals profiler, error boundary inspector).
- Hot reload for component templates + router updates.
- CLI plugin system for community generators.

---

## 5. Documentation & Onboarding
**Goals:** Discoverability, step-by-step adoption, community contributions.

### Sprint-ready tasks
- Launch docs site skeleton (Introduction, Quick Start, SSR guide, Forms guide).
- Convert existing design docs to public docs (Router, Forms, SSR) with diagrams.
- Produce migration primer for Yew/Leptos users moving to Ripple.

### Medium-term
- Interactive tutorials using WASM playground.
- API reference generation (auto from Zig comments) with version switcher.
- Community contribution guidelines & documentation review workflow.

---

## 6. Reference Apps & Demos
**Goals:** Showcase production patterns and best practices.

### Sprint-ready tasks
- Build the streaming commerce demo (SSR + islands, progressive forms).
- Publish smaller samples: counter, todo, dashboard, form wizard.
- Add server adapters (Axum, Actix, Rocket) and deployment stories.

### Medium-term
- Deploy demo gallery with automated deployments per commit.
- Telemetry instrumentation demo (performance + error tracing).
- Showcase interoperability (Zig backend + Rust frontend, etc.).

---

## 7. Performance & Stability
**Goals:** Competitive WASM bundles, reliable runtime, profiling.

### Sprint-ready tasks
- Establish benchmark suite (hydration cost, signal update throughput, validation latency).
- Add profiling hooks and debug overlays for forms/router.
- Memory usage audits for WASM builds (link-time optimization, snapshotting).

### Medium-term
- Adaptive scheduling strategies for signals & validations.
- Integration tests with large datasets (stress tests for router/forms).
- Release cadence for stability updates + regression tracking.

---

## 8. Community & Release Readiness
**Goals:** Open-source governance, release management, adoption support.

### Sprint-ready tasks
- Introduce issue templates, triage policies, and roadmap updates.
- Draft release process (versioning, changelog automation, package publishing).
- Plan announcement assets (blog, talks, sample repos).

### Medium-term
- Community working groups (forms, router, tooling).
- Beta feedback loop (monthly check-ins, priority backlog).
- Long-term support strategy post-1.0.

---

## Suggested Sequence
1. **Forms polish** to stabilize current momentum. ✅
2. **Router/data loading** for parity with existing JS frameworks.
3. **Tooling + docs** to improve contributor velocity.
4. **Component library & demos** once core runtime flows are solid.
5. **Performance & community** as we approach beta.

This roadmap is a living artifact—update it sprintly to reflect completed milestones and shifting priorities.
