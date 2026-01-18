# Validations & Schemas

Ripple's form store now ships with a declarative schema layer that mirrors popular libraries like Zod while still embracing the store's async validation primitives. This guide walks through the core pieces and how to compose them with `FormStore`.

## Quick Start

```zig
const ripple = @import("ripple");

const schema = ripple.FormSchemaValidationConfig{
    .fields = &.{
        .{
            .field = "email",
            .rules = &.{
                ripple.FormSchemaRule{ .email = .{ .message = "Please enter a valid email" } },
            },
        },
        .{
            .field = "password",
            .rules = &.{
                ripple.FormSchemaRule{ .minLength = .{ .min = 8, .message = "Too short" } },
                ripple.FormSchemaRule{ .maxLength = .{ .max = 64 } }, // uses default copy
            },
        },
        .{ .field = "confirm", .rules = &.{} },
    },
    .cross_fields = &.{
        ripple.FormSchemaCrossFieldRule{ .matchField = .{
            .field = "confirm",
            .other_field = "password",
            .message = "Passwords must match",
        } },
    },
};

var store = try ripple.FormStore.init(allocator, .{ .schema = schema });
try store.registerField(.{ .name = "email", .initial = "" });
try store.registerField(.{ .name = "password", .initial = "" });
try store.registerField(.{ .name = "confirm", .initial = "" });
```

## Built-in Rules

`FormSchemaRule` exposes three built-in variants:

- `.minLength` and `.maxLength` operate on byte length and accept optional `message` overrides.
- `.email` runs a lightweight email heuristic; leave `message` empty to use the default copy.
- `.custom` accepts a fully user-defined validator returning `FormValidationResult` for sync or async checks.

Custom rules are ideal when bridging existing server validation. For example:

```zig
const std = @import("std");

const UsernameRule = struct {
    fn validate(_: []const u8, value: []const u8, allocator: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ripple.FormValidationResult {
        _ = allocator;
        const blacklist = @as([]const []const u8, @ptrCast(ctx_ptr.?));
        for (blacklist) |entry| {
            if (std.mem.eql(u8, entry, value)) {
                return .{ .immediate = .{ .valid = false, .message = "Username unavailable" } };
            }
        }
        return .{ .immediate = .{} };
    }
};

const usernames = [_][]const u8{ "admin", "root" };
const schema = ripple.FormSchemaValidationConfig{
    .fields = &.{
        .{
            .field = "username",
            .rules = &.{
                ripple.FormSchemaRule{ .custom = .{
                    .validate = UsernameRule.validate,
                    .context = @constCast(&usernames),
                } },
            },
        },
    },
};
```

Async checks simply return `.future`; the store handles cancellation and state transitions automatically.

## Cross-field Rules

Use `FormSchemaCrossFieldRule.matchField` when a field must mirror another (e.g. password confirmation). For more control, fall back to `.custom` which accepts the same callback shape as `registerCrossFieldValidation`.

```zig
const std = @import("std");

const CompareRule = struct {
    fn validate(store: *ripple.FormStore, field: []const u8, _: ?*anyopaque) anyerror!ripple.FormValidationOutcome {
        const lhs = store.fieldValue(field) orelse return .{};
        const rhs = store.fieldValue("billing_postcode") orelse return .{};
        if (!std.mem.eql(u8, lhs, rhs)) {
            return .{ .valid = false, .message = "Postcodes must align" };
        }
        return .{};
    }
};

const schema = ripple.FormSchemaValidationConfig{
    .fields = &.{ .{ .field = "shipping_postcode", .rules = &.{} } },
    .cross_fields = &.{
        ripple.FormSchemaCrossFieldRule{ .custom = .{
            .field = "shipping_postcode",
            .dependencies = &.{ "billing_postcode" },
            .validate = CompareRule.validate,
        } },
    },
};
```

Cross-field rules run after every dependent change, so complex scenarios (e.g. tri-field comparisons) are supported by expanding `dependencies` and reading values via `fieldValue()` or `fieldView()`.

## Accessibility Pass

Schemas integrate seamlessly with the new accessibility helpers:

- Call `collectErrorSummary()` to produce an ordered snapshot of invalid fields.
- Feed the result into `buildErrorSummaryView()` for a ready-to-render `<div role="alert">` block.
- Wire `bindAriaInvalid()` alongside existing input bindings to keep `aria-invalid` synchronised.
- Use `focusFirstInvalidField()` after failed submissions to relocate focus.

These helpers lean on registration order, making it easy to preserve SSR markup and hydrate progressively.

## Error Handling

A few guard rails protect schema usage:

- Passing both `.validation` and `.schema` raises `error.ConflictingValidationAdapters`.
- Declaring the same field twice in `.fields` triggers `error.DuplicateSchemaField`.
- Custom rule contexts receive their `deinitContext` hooks when the store is dropped; embed allocators there if you need specialised cleanup.

With these pieces you can keep client and server validation logic aligned while still embracing Ripple's async, batched validation pipeline.
