# Router Guard API

## Summary
The guard system introduces a composable hook pipeline that runs before a navigation is committed. Guards can block, redirect, or allow navigation based on runtime state, while keeping the router API allocator-friendly and synchronous by default. The design supports global "before each" policies and per-route checks, enabling authentication workflows and route-specific gating without rebuilding control flow by hand.

## Goals
- Provide a structured lifecycle for navigation guard execution.
- Support both global (router level) and route-scoped guard registration.
- Allow guards to return one of three outcomes: allow, redirect, or reject with a reason.
- Preserve allocator ownership for route parameters while exposing a read-only view to guards.
- Avoid committing navigation side effects (signals, history, scroll) until the guard pipeline succeeds.

## Guard Types & Phases
Guards are declared through the `RouteGuard` struct:

```zig
pub const RouteGuard = struct {
    name: []const u8,
    phase: GuardPhase,
    handler: GuardHandler,
    user_data: ?*anyopaque = null,
};
```

Supported phases:
- `before_each` — registered on the router with `Router.registerGuard` and evaluated for every navigation attempt.
- `before_enter` — attached to individual routes via `Route.withGuards` and executed after global guards pass.

Additional phases (`after_each`, `before_leave`) are intentionally left for future expansion once async use-cases appear.

## Context & Outcome
Each guard receives a `GuardContext` and must return a `GuardDecision`:

```zig
pub const GuardContext = struct {
    allocator: std.mem.Allocator,
    from: []const u8,
    to: []const u8,
    params: ?*const RouteParams,
    route: ?*const Route,
};

pub const GuardDecision = union(enum) {
    allow,
    redirect: []const u8,
    reject: []const u8,
};
```

- `from` / `to` are immutable path slices for the previous/current targets.
- `params` and `route` are populated when a concrete route match exists (null when the router would fallback to 404).
- Guards may rely on `user_data` to capture environment or shared state; the router never assumes ownership of that pointer.

Outcome handling rules:
- `allow` — navigation continues to the next guard or commits if pipeline complete.
- `redirect(path)` — aborts current attempt, deinitializes the pending match, and recursively calls `Router.navigate(path)`.
- `reject(reason)` — aborts navigation, preserving the current route and scroll position. Future UI integrations can surface `reason` to the app shell.

## Execution Order
1. Resolve or lazily load the target route.
2. Build a tentative `RouteMatch` (no guards are run yet) and context snapshot.
3. Evaluate registered `before_each` guards sequentially.
4. If allowed, evaluate the matched route’s `before_enter` guards.
5. On success, capture scroll for the previous path, update the path signal, restore scroll for the new route, and adopt the computed `RouteMatch` as the active match.

Guard handlers are synchronous today; the router surface keeps the door open for async support by using `anyerror!GuardDecision`. Error values will bubble up to the caller, allowing specialized transports to integrate promises/futures later.

## Edge Cases & Guarantees
- Guards run before the path signal is mutated, guaranteeing that reactive subscribers never see intermediate states.
- Redirect loops are capped by a short-circuit: redirecting to the same `to` path is treated as a no-op.
- Route parameter memory is retained only when the guard pipeline succeeds; otherwise, parameters are freed before returning.
- Fallback / 404 navigations still execute global guards with `params == null` so cross-cutting policies (e.g., audit logging) remain consistent.

## Follow-Up Questions
- **Async guards**: Introduce suspension primitives or promise-like helpers for WASM host environments.
- **After hooks**: Evaluate the need for `after_each` once we wire analytics/scroll restoration events.
- **Guard metadata**: Surface rejection reasons on a router signal or event emitter so UI can respond without singletons.

For now, the spike proves the API surface and synchronous execution flow; subsequent iterations can extend phases and async ergonomics based on developer feedback.
