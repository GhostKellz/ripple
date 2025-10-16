# Form Store Core

## Objective
Provide a form management layer that tracks field registration, values, meta state (`dirty` / `touched` / `validating`), and validation outcomes using Ripple signals. The store is purely client-side for now and focuses on ergonomics for WASM components, while leaving room for richer submission pipelines.

## Scope
- Field registration with initial value captured at registration time.
- Per-field value, dirty, touched, validating, and valid state exposed via read signals alongside error messages.
- Store-level aggregates (`isDirty`, `isTouched`, `isValid`, `isValidating`) that update whenever individual fields change.
- Reset helpers for fields and entire form to revert to initial values while re-running validation.
- Pluggable validation adapters (initially a zschema-style min-length adapter) that normalise schema engines into a shared interface.

## API Surface (first pass)
```zig
const ripple = @import("root.zig");

var adapter = try ripple.createZSchemaMinLengthAdapter(allocator, &[_]ripple.ZSchemaMinLengthRule{
	.{ .field = "password", .min = 8, .message = "Password too short" },
});
errdefer adapter.deinit(allocator);

var store = try ripple.FormStore.init(allocator, .{ .validation = adapter });
defer store.deinit();

try store.registerField(.{ .name = "email", .initial = "" });
try store.registerField(.{ .name = "password", .initial = "short" });

var form_binding = try ripple.bindFormSubmit(allocator, &store, .{});
defer form_binding.deinit();

const password = store.fieldView("password") orelse unreachable;
const is_dirty = try store.dirtySignal().get();
const is_valid = try store.validSignal().get();
const is_validating = try store.validatingSignal().get();
const password_validating = try password.validating.get();
const password_error = try password.error_message.get();
```

### Types
- `FormStoreOptions` — `.{ .validation = ?ValidationAdapter }` allowing callers to inject schema adapters.
- `FieldConfig` — `{ name: []const u8, initial: []const u8 }` remains unchanged.
- `FieldView` — stable reference exposing read signals for `value`, `dirty`, `touched`, `validating`, `valid`, and `error_message` plus the initial value.
- `FormSnapshot` — `{ dirty: bool, touched: bool, validating: bool, valid: bool }` convenience struct mirroring aggregate signals.
- `SerializedField` — disposable entries containing `value`, `dirty`, `touched`, `validating`, `valid`, and `error_message` metadata.
- `ValidationAdapter` — trait object with `validate(field, value)` and optional context destructor.
- `ValidationResult` — union between immediate `ValidationOutcome` responses and async futures for deferred checks.
- `AsyncValidation` — wrapper around `zsync.Future(ValidationOutcome)` used to represent in-flight checks.
- `ValidationBatchGuard` — RAII helper returned by `FormStore.beginValidationBatch()` to coalesce repeated validations within a critical section.
- `ValidationDebouncer` — controller that postpones validation flushes until a configurable delay elapses.
- `ValidationThrottler` — controller that enforces a minimum interval between validation flushes.
- `ZSchemaMinLengthRule` — helper rule used by the bundled min-length adapter prototype.

### Errors
- `error.DuplicateField`
- `error.UnknownField`

## State Management
- Internally use `std.StringHashMap(FieldState)` keyed by field name.
- `FieldState` holds duplicated slices for `name`, `initial`, and `current` plus signal pairs for value, dirty, touched, validating, valid, and error text. Boolean mirrors (`dirty_state`, `touched_state`, `validating_state`, `valid_state`) support efficient aggregate counting while the `error_message` buffer mirrors the latest adapter result.
- Aggregates maintain `dirty_count` / `touched_count` / `invalid_count` / `validating_count`, updating corresponding signals without rescanning all fields.

## Signal Contracts
- `FormStore.valueSignal(name)` returns `core.ReadSignal([]const u8)`.
- `dirtySignal`, `touchedSignal`, `validSignal`, and `validatingSignal` surfaced via dedicated getters.
- `FieldView` exposes `value`, `dirty`, `touched`, `validating`, `valid`, and `error_message` read signals for ergonomic bindings.
- Resets update signals and counts to keep downstream effects consistent.
- Utility helpers: `markAllTouched()` flips every field into the touched state (useful before submit), `validateAll()` re-runs adapters over the current values, `tickAsyncValidations()` drains resolved futures, and `serialize()` returns a disposable snapshot (`SerializedForm`) of field values/errors for logging or analytics.
- `beginValidationBatch()` defers adapter invocations until the guard completes, coalescing multiple value writes into a single validation pass per field.
- `withValidationBatch()` offers a convenience wrapper around the guard for callers who prefer higher-order helpers over manual RAII.
- Debounce/throttle controllers expose `touch()`/`tick()` methods so hosts can wire in their own scheduling primitives while still benefiting from batched validation.

## Validation Adapters
- `ValidationAdapter` wraps schema engines behind a shared interface that receives `(field, value, allocator, context)` and returns a `ValidationResult`.
- Async results surface via `zsync.Future(ValidationOutcome)` futures; pending work flips the affected field (and aggregates) into a validating state until resolved or cancelled.
- When a new async validation is scheduled for the same field, the previous future is cancelled, a `"Validation cancelled"` message is surfaced, and the store keeps the field in a validating state until the replacement future resolves.
- Validation batches let callers delay adapter invocations across a critical section, ensuring only the latest value for each field is validated when the guard completes.
- Debounce and throttle controllers build on batching, trading immediate validation for time-based coalescing. Both rely on periodic `tick()` calls (e.g., from an event loop) to flush pending guards once their timers expire.

## Progressive Enhancement
- `bindFormSubmit` wires native `<form>` submit events to the store. It marks all fields as touched, re-runs validation, and (by default) prevents submission when the form is invalid.
- `FormSubmitOptions` exposes hooks for `on_valid` / `on_invalid` callbacks (receiving the `FormStore`) and toggles `prevent_submit_on_invalid` when you want the browser submit to proceed regardless of errors.
- `SerializedForm` + `SerializedField` provide a disposable snapshot of the current field values, meta flags (including `validating`), and error text—perfect for analytics, logging, or progressive-enhancement fallbacks. Remember to call `serialized.deinit()` when done.
- Typical native fallback flow:
	1. Call `bindFormSubmit` and spread the returned `.on_submit` handler onto your `<form>` element.
	2. Inside `on_invalid`, focus the first invalid field or surface errors inline; the default handler has already prevented the submit.
	3. Inside `on_valid`, optionally call `store.serialize()` to collect data for an async submit while still allowing the browser POST to continue.

## Edge Cases
- Registering a field twice yields `DuplicateField`.
- Reading or mutating an unknown field yields `UnknownField`.
- Resetting a field to its initial value clears dirty/touched state and re-runs validation so error messages reflect the reset data.
- Slice values are duplicated; callers retain ownership of provided buffers.

## Future Considerations
- Async validation ergonomics (debounce, throttle, timeout policies) layered on top of the adapter trait.
- Batched error summaries and field grouping helpers for complex forms.
- Nested/array field support.
- Serializer for progressive enhancement fallback.
- Context provider for automatic store injection into child components.

## Input Binding Helpers
The initial binding helpers live alongside the store to wire common controls without hand-writing DOM glue:

- `bindTextInput` — connects `input`/`blur` events, keeping the `value` attribute in sync with the field signal.
- `bindSelect` — listens to `change`/`blur` events for `<select>` elements.
- `bindCheckbox` — normalises truthy payloads, exposes a memoised `checked` attribute signal, and toggles when no payload is supplied.

Each helper allocates a small context per binding and returns event handlers plus the underlying `FieldView` signals for attribute creation.
Call `binding.deinit()` when the component is torn down to release the context allocations. The store continues to own field memory and signals.

This spike targets the foundational store and signal plumbing so later work can layer validations and transport hooks.
