# Forms: SSR + Progressive Enhancement Demo

This walkthrough pairs the new form schema APIs with Ripple's accessibility helpers to illustrate a full server-render + progressive-enhancement loop.

## Scenario

1. **Server render** – The server registers a `FormStore` with a `FormSchemaValidationConfig`, runs `collectErrorSummary()`, and renders an HTML form with:
   - Inline errors rendered via `buildErrorSummaryView()` when validation fails.
   - Inputs marked up with `aria-invalid` based on `form.fieldView(...)` state.
2. **Client hydrate** – The WASM client imports the same schema, replays field registration, and wires DOM events via `bindTextInput`, `bindCheckbox`, etc. `bindAriaInvalid` keeps ARIA state aligned post-hydration.
3. **Roundtrip** – On submit, the client defers to `bindFormSubmit()`, focuses the first invalid field via `focusFirstInvalidField()`, and optionally serialises for an async fetch. The server reuses the schema to validate and responds with updated HTML, preserving progressive enhancement.

## Key Pieces

```zig
const std = @import("std");
const ripple = @import("ripple");

fn renderForm(allocator: std.mem.Allocator, store: *ripple.FormStore) ![]const u8 {
    var summary = try store.collectErrorSummary(allocator);
    defer summary.deinit();

    const summary_view = try store.buildErrorSummaryView(allocator, "Please fix the highlighted fields");
    // render(summary_view, ...) using your templating pipeline...
    // return the final HTML string
}

fn hydrateForm(allocator: std.mem.Allocator, store: *ripple.FormStore) !void {
    var email = try ripple.bindTextInput(allocator, store, "email");
    var password = try ripple.bindTextInput(allocator, store, "password");
    var confirm = try ripple.bindTextInput(allocator, store, "confirm");
    var email_aria = try ripple.bindAriaInvalid(allocator, email.field);
    defer {
        email.deinit();
        password.deinit();
        confirm.deinit();
        email_aria.deinit();
    }

    var submit = try ripple.bindFormSubmit(allocator, store, .{ .on_invalid = struct {
        fn onInvalid(store: *ripple.FormStore, _: ?*anyopaque) anyerror!void {
            _ = try store.focusFirstInvalidField(struct {
                fn focus(name: []const u8, _: ?*anyopaque) anyerror!void {
                    focusFieldByName(name); // host-provided JS bridge
                }
            }.focus, null);
        }
    }.onInvalid });
    defer submit.deinit();
}
extern fn focusFieldByName(ptr: [*]const u8, len: usize) void;
```

> **Host glue:** expose a small JavaScript helper that maps field names to DOM nodes (`focusFieldByName` above) and forwards DOM events into the WASM bindings.

## Demo Project

The `examples/forms-ssr-pe/` workspace contains:

- `build.zig` / `src/main.zig` – a tiny CLI that renders server HTML and simulates a client hydration pass.
- `public/index.html` – initial SSR markup showing the error summary scaffolding.
- `README.md` – instructions for running the demo and wiring the JS bridge for focus + async validation roundtrips.

Use it as a blueprint for real projects or as a regression fixture while evolving the form APIs.
