/// Control flow primitives for Ripple components.
///
/// Provides Show, For, and Switch helpers for conditional rendering
/// and list iteration with fine-grained reactivity.
const std = @import("std");
const core = @import("core.zig");
const component = @import("component.zig");

/// Show conditionally renders children based on a condition signal.
///
/// Example:
/// ```zig
/// const show_signal = try createSignal(bool, allocator, true);
/// const view = Show.init(allocator, show_signal.read, .{
///     .then = try builder.text("Visible!"),
///     .otherwise = try builder.text("Hidden"),
/// });
/// ```
pub const Show = struct {
    allocator: std.mem.Allocator,
    condition: core.ReadSignal(bool),
    then_view: ?component.View,
    else_view: ?component.View,

    pub const Options = struct {
        then: component.View,
        otherwise: ?component.View = null,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        condition: core.ReadSignal(bool),
        options: Options,
    ) Show {
        return .{
            .allocator = allocator,
            .condition = condition,
            .then_view = options.then,
            .else_view = options.otherwise,
        };
    }

    /// Get the current view based on condition.
    pub fn view(self: Show) !?component.View {
        const show = try self.condition.get();
        if (show) {
            return self.then_view;
        } else {
            return self.else_view;
        }
    }

    pub fn deinit(self: *Show) void {
        _ = self;
        // Views are managed by component lifecycle
    }
};

/// Key function for list items
pub const KeyFn = fn (usize, *const anyopaque) []const u8;

/// For renders a list of items with keyed reconciliation.
///
/// Example:
/// ```zig
/// const items = try createSignal([]const Item, allocator, &initial_items);
/// const for_view = For.init(allocator, items.read, .{
///     .key_fn = myKeyFn,
///     .view_fn = myViewFn,
/// });
/// ```
pub const For = struct {
    allocator: std.mem.Allocator,
    items_signal: *const anyopaque, // Type-erased signal
    key_fn: ?KeyFn,
    fallback: ?component.View,

    pub fn Options(comptime T: type) type {
        return struct {
            key_fn: ?fn (T) []const u8 = null,
            each: fn (T, std.mem.Allocator) anyerror!component.View,
            fallback: ?component.View = null,
        };
    }

    pub fn init(
        comptime T: type,
        allocator: std.mem.Allocator,
        items: core.ReadSignal([]const T),
        options: Options(T),
    ) !For {
        _ = items;
        _ = options;
        return .{
            .allocator = allocator,
            .items_signal = undefined, // TODO: Store type-erased signal
            .key_fn = null,
            .fallback = null,
        };
    }
};

pub const ForOptions = struct {
    fallback: ?component.View = null,
};

/// Switch renders the first matching case.
///
/// Example:
/// ```zig
/// const state = try createSignal(State, allocator, .loading);
/// const switch_view = Switch.init(allocator, &[_]Match{
///     Match.init(.loading, try builder.text("Loading...")),
///     Match.init(.success, try builder.text("Success!")),
///     Match.init(.error, try builder.text("Error occurred")),
/// });
/// ```
pub const Switch = struct {
    allocator: std.mem.Allocator,
    matches: []const Match,
    fallback: ?component.View,

    pub fn init(
        allocator: std.mem.Allocator,
        matches: []const Match,
        fallback: ?component.View,
    ) Switch {
        return .{
            .allocator = allocator,
            .matches = matches,
            .fallback = fallback,
        };
    }

    /// Evaluate the switch and return the first matching view.
    pub fn view(self: Switch, comptime T: type, value: T) ?component.View {
        for (self.matches) |match| {
            if (match.matches(T, value)) {
                return match.view;
            }
        }
        return self.fallback;
    }
};

/// Match represents a case in a Switch statement.
pub const Match = struct {
    matcher: *const fn (*const anyopaque) bool,
    view: component.View,
    match_value: *const anyopaque,

    pub fn init(comptime T: type, value: T, view: component.View) Match {
        const Storage = struct {
            var stored_value: T = undefined;
        };
        Storage.stored_value = value;

        return .{
            .matcher = struct {
                fn matches(ptr: *const anyopaque) bool {
                    const v = @as(*const T, @ptrCast(@alignCast(ptr))).*;
                    return std.mem.eql(u8, @tagName(v), @tagName(Storage.stored_value));
                }
            }.matches,
            .view = view,
            .match_value = &Storage.stored_value,
        };
    }

    pub fn matches(self: Match, comptime T: type, value: T) bool {
        return self.matcher(@as(*const anyopaque, @ptrCast(&value)));
    }
};

test "Show conditionally renders views" {
    const allocator = std.testing.allocator;
    var condition = try core.createSignal(bool, allocator, true);
    defer condition.dispose();

    const builder = component.ViewBuilder.init(allocator);
    const then_text = try builder.text("Shown");
    defer allocator.free(then_text.text.value);

    const else_text = try builder.text("Hidden");
    defer allocator.free(else_text.text.value);

    var show = Show.init(allocator, condition.read, .{
        .then = then_text,
        .otherwise = else_text,
    });
    defer show.deinit();

    const view1 = try show.view();
    try std.testing.expect(view1 != null);
    try std.testing.expectEqualStrings("Shown", view1.?.text.value);

    try condition.write.set(false);

    const view2 = try show.view();
    try std.testing.expect(view2 != null);
    try std.testing.expectEqualStrings("Hidden", view2.?.text.value);
}

test "Switch evaluates matches" {
    const State = enum { loading, success, error_state };

    const allocator = std.testing.allocator;
    const builder = component.ViewBuilder.init(allocator);

    const loading_view = try builder.text("Loading...");
    defer allocator.free(loading_view.text.value);

    const success_view = try builder.text("Success!");
    defer allocator.free(success_view.text.value);

    const error_view = try builder.text("Error");
    defer allocator.free(error_view.text.value);

    const matches = [_]Match{
        Match.init(State, State.loading, loading_view),
        Match.init(State, State.success, success_view),
        Match.init(State, State.error_state, error_view),
    };

    const switch_view = Switch.init(allocator, &matches, null);

    const result1 = switch_view.view(State, State.loading);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("Loading...", result1.?.text.value);

    const result2 = switch_view.view(State, State.success);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("Success!", result2.?.text.value);
}
