/// Component system for Ripple.
///
/// Components are functions that accept props and return a View.
/// They encapsulate reactive state, effects, and DOM structure.
///
/// Example:
/// ```zig
/// const Counter = struct {
///     initial: i32 = 0,
///
///     pub fn view(self: @This(), allocator: std.mem.Allocator) !View {
///         var count = try core.createSignal(i32, allocator, self.initial);
///         // ... render logic
///     }
/// };
/// ```
const std = @import("std");
const core = @import("core.zig");
const render = @import("render.zig");
const dom = @import("dom.zig");

/// View represents a renderable component tree.
pub const View = union(enum) {
    element: Element,
    text: Text,
    fragment: Fragment,
    dynamic: Dynamic,
    component: Component,

    pub const Element = struct {
        tag: []const u8,
        attrs: []const Attribute,
        children: []const View,
        event_handlers: []const EventHandler,
    };

    pub const Text = struct {
        value: []const u8,
    };

    pub const Fragment = struct {
        children: []const View,
    };

    pub const Dynamic = struct {
        signal: core.ReadSignal([]const u8),
    };

    pub const Component = struct {
        name: []const u8,
        render_fn: *const fn (std.mem.Allocator) anyerror!View,
    };

    pub const Attribute = struct {
        name: []const u8,
        value: union(enum) {
            static: []const u8,
            dynamic: core.ReadSignal([]const u8),
            boolean: bool,
        },
    };

    pub const EventHandler = struct {
        event_name: []const u8,
        handler: dom.EventHandler,
    };
};

/// Props is a convenience type for component properties.
pub fn Props(comptime T: type) type {
    return struct {
        data: T,
        allocator: std.mem.Allocator,
        children: []const View = &.{},

        pub fn init(allocator: std.mem.Allocator, data: T) @This() {
            return .{
                .data = data,
                .allocator = allocator,
            };
        }
    };
}

/// ViewBuilder helps construct Views ergonomically.
pub const ViewBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ViewBuilder {
        return .{ .allocator = allocator };
    }

    /// Create an element view.
    pub fn element(
        self: ViewBuilder,
        tag: []const u8,
        attrs: []const View.Attribute,
        children: []const View,
    ) !View {
        return View{
            .element = .{
                .tag = try self.allocator.dupe(u8, tag),
                .attrs = try self.allocator.dupe(View.Attribute, attrs),
                .children = try self.allocator.dupe(View, children),
                .event_handlers = &.{},
            },
        };
    }

    /// Create a text view.
    pub fn text(self: ViewBuilder, value: []const u8) !View {
        return View{
            .text = .{
                .value = try self.allocator.dupe(u8, value),
            },
        };
    }

    /// Create a dynamic text view bound to a signal.
    pub fn dynamic(self: ViewBuilder, signal: core.ReadSignal([]const u8)) View {
        _ = self;
        return View{
            .dynamic = .{
                .signal = signal,
            },
        };
    }

    /// Create a fragment (multiple children without wrapper).
    pub fn fragment(self: ViewBuilder, children: []const View) !View {
        return View{
            .fragment = .{
                .children = try self.allocator.dupe(View, children),
            },
        };
    }

    /// Helper to create an attribute.
    pub fn attr(self: ViewBuilder, name: []const u8, value: []const u8) !View.Attribute {
        return View.Attribute{
            .name = try self.allocator.dupe(u8, name),
            .value = .{ .static = try self.allocator.dupe(u8, value) },
        };
    }

    /// Helper to create a dynamic attribute bound to a signal.
    pub fn attrDynamic(
        self: ViewBuilder,
        name: []const u8,
        signal: core.ReadSignal([]const u8),
    ) !View.Attribute {
        return View.Attribute{
            .name = try self.allocator.dupe(u8, name),
            .value = .{ .dynamic = signal },
        };
    }

    /// Helper to create a boolean attribute.
    pub fn attrBool(self: ViewBuilder, name: []const u8, value: bool) !View.Attribute {
        return View.Attribute{
            .name = try self.allocator.dupe(u8, name),
            .value = .{ .boolean = value },
        };
    }
};

/// Component lifecycle scope.
pub const ComponentScope = struct {
    allocator: std.mem.Allocator,
    effects: std.ArrayList(core.EffectHandle),
    signals: std.ArrayList(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) ComponentScope {
        return .{
            .allocator = allocator,
            .effects = std.ArrayList(core.EffectHandle).init(allocator),
            .signals = std.ArrayList(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentScope) void {
        for (self.effects.items) |*effect| {
            effect.dispose();
        }
        self.effects.deinit();
        self.signals.deinit();
    }

    /// Register an effect to be cleaned up with the component.
    pub fn trackEffect(self: *ComponentScope, effect: core.EffectHandle) !void {
        try self.effects.append(effect);
    }
};

/// Helper to create a simple functional component.
pub fn createComponent(
    comptime name: []const u8,
    comptime PropsType: type,
    comptime renderFn: fn (Props(PropsType)) anyerror!View,
) type {
    return struct {
        pub const ComponentName = name;
        pub const ComponentProps = PropsType;

        pub fn render(props: Props(PropsType)) !View {
            return try renderFn(props);
        }
    };
}

test "component view builder creates elements" {
    const allocator = std.testing.allocator;
    const builder = ViewBuilder.init(allocator);

    const attrs = [_]View.Attribute{
        try builder.attr("class", "button"),
        try builder.attrBool("disabled", false),
    };

    const children = [_]View{
        try builder.text("Click me"),
    };

    const view = try builder.element("button", &attrs, &children);
    defer {
        allocator.free(view.element.tag);
        allocator.free(view.element.attrs);
        for (view.element.children) |child| {
            allocator.free(child.text.value);
        }
        allocator.free(view.element.children);
    }

    try std.testing.expectEqualStrings("button", view.element.tag);
    try std.testing.expectEqual(@as(usize, 2), view.element.attrs.len);
    try std.testing.expectEqual(@as(usize, 1), view.element.children.len);
}

test "component scope manages lifecycle" {
    const allocator = std.testing.allocator;
    var scope = ComponentScope.init(allocator);
    defer scope.deinit();

    var counter = try core.createSignal(i32, allocator, 0);
    defer counter.dispose();

    const Context = struct {
        read: core.ReadSignal(i32),
    };
    var ctx = Context{ .read = counter.read };

    const effect = try core.createEffect(allocator, struct {
        fn run(effect_ctx: *core.EffectContext) anyerror!void {
            const data = effect_ctx.userData(Context).?;
            _ = try data.read.get();
        }
    }.run, &ctx);

    try scope.trackEffect(effect);
    try std.testing.expectEqual(@as(usize, 1), scope.effects.items.len);
}

test "functional component can be created" {
    const ButtonProps = struct {
        label: []const u8,
        disabled: bool = false,
    };

    const Button = createComponent("Button", ButtonProps, struct {
        fn render(props: Props(ButtonProps)) !View {
            const builder = ViewBuilder.init(props.allocator);
            const attrs = [_]View.Attribute{
                try builder.attrBool("disabled", props.data.disabled),
            };
            const children = [_]View{
                try builder.text(props.data.label),
            };
            return try builder.element("button", &attrs, &children);
        }
    }.render);

    const allocator = std.testing.allocator;
    const props = Props(ButtonProps).init(allocator, .{
        .label = "Submit",
        .disabled = false,
    });

    const view = try Button.render(props);
    defer {
        allocator.free(view.element.tag);
        allocator.free(view.element.attrs);
        for (view.element.children) |child| {
            allocator.free(child.text.value);
        }
        allocator.free(view.element.children);
    }

    try std.testing.expectEqualStrings("button", view.element.tag);
    try std.testing.expectEqualStrings("Submit", view.element.children[0].text.value);
}
