const std = @import("std");
const ripple = @import("ripple");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌊 Ripple Dashboard Example\n", .{});
    std.debug.print("============================\n\n", .{});

    // Demo 1: Counter with reactive updates
    try demoCounter(allocator);

    // Demo 2: Resource loading with suspense
    try demoResource(allocator);

    // Demo 3: Nested islands
    try demoIslands(allocator);
}

fn demoCounter(allocator: std.mem.Allocator) !void {
    std.debug.print("Demo 1: Reactive Counter\n", .{});
    std.debug.print("------------------------\n", .{});

    var counter = try ripple.createSignal(i32, allocator, 0);
    defer counter.dispose();

    const Context = struct {
        read: ripple.ReadSignal(i32),
    };
    var ctx = Context{ .read = counter.read };

    var effect = try ripple.createEffect(allocator, struct {
        fn run(scope: *ripple.EffectContext) anyerror!void {
            const data = scope.userData(Context).?;
            const value = try data.read.get();
            std.debug.print("  Counter value: {}\n", .{value});
        }
    }.run, &ctx);
    defer effect.dispose();

    try counter.write.set(1);
    try counter.write.set(2);
    try counter.write.set(3);

    std.debug.print("\n", .{});
}

fn demoResource(allocator: std.mem.Allocator) !void {
    std.debug.print("Demo 2: Async Resource Loading\n", .{});
    std.debug.print("-------------------------------\n", .{});

    var user_id = try ripple.createSignal(u32, allocator, 1);
    defer user_id.dispose();

    var resource = try ripple.createResource(u32, []const u8, allocator, user_id.read, struct {
        fn fetchUser(id: u32) anyerror![]const u8 {
            std.debug.print("  Fetching user {}...\n", .{id});
            if (id == 1) return "Alice";
            if (id == 2) return "Bob";
            return error.NotFound;
        }
    }.fetchUser);
    defer resource.dispose();

    try ripple.flushPending();

    var state_signal = resource.read();
    const state = try state_signal.get();

    switch (state.status) {
        .ready => std.debug.print("  User loaded: {s}\n", .{state.value.?}),
        .loading => std.debug.print("  Loading...\n", .{}),
        .failed => std.debug.print("  Error: {s}\n", .{state.error_message.?}),
    }

    try user_id.write.set(2);
    try ripple.flushPending();

    const state2 = try state_signal.get();
    if (state2.status == .ready) {
        std.debug.print("  User loaded: {s}\n", .{state2.value.?});
    }

    std.debug.print("\n", .{});
}

fn demoIslands(allocator: std.mem.Allocator) !void {
    std.debug.print("Demo 3: Islands Architecture\n", .{});
    std.debug.print("----------------------------\n", .{});

    const template = ripple.compileTemplate(
        \\<!-- island:counter -->
        \\<div>Count: {{value}}</div>
        \\<!-- /island -->
    );

    var program = try ripple.buildRenderProgram(allocator, template);
    defer program.deinit();

    std.debug.print("  Template compiled with {} ops\n", .{program.ops.len});
    std.debug.print("  Dynamic slots: {}\n", .{program.dynamicSlotCount()});

    const MockHost = struct {
        fn createElement(_: ?*anyopaque, tag: []const u8) u32 {
            std.debug.print("    createElement: <{s}>\n", .{tag});
            return 1;
        }
        fn createText(_: ?*anyopaque, value: []const u8) u32 {
            std.debug.print("    createText: '{s}'\n", .{value});
            return 2;
        }
        fn appendChild(_: ?*anyopaque, parent: u32, child: u32) void {
            std.debug.print("    appendChild: {} -> {}\n", .{ child, parent });
        }
        fn setText(_: ?*anyopaque, _: u32, _: []const u8) void {}
        fn setAttr(_: ?*anyopaque, _: u32, _: []const u8, _: []const u8) void {}
        fn registerEvent(_: ?*anyopaque, _: []const u8) void {}
        fn resolvePortal(_: ?*anyopaque, _: []const u8) u32 {
            return 0;
        }
    };

    ripple.setDomHostCallbacks(.{
        .create_element = MockHost.createElement,
        .create_text = MockHost.createText,
        .append_child = MockHost.appendChild,
        .set_text = MockHost.setText,
        .set_attribute = MockHost.setAttr,
        .register_event = MockHost.registerEvent,
        .resolve_portal = MockHost.resolvePortal,
    });
    defer ripple.resetDomHostCallbacks();

    const values = [_][]const u8{"42"};
    var mount = try ripple.mountRenderProgram(allocator, program, 0, &values);
    defer mount.deinit();

    std.debug.print("  Mounted {} islands\n", .{mount.islands.len});
    if (mount.islands.len > 0) {
        std.debug.print("    Island '{s}' on node {}\n", .{ mount.islands[0].name, mount.islands[0].parent });
    }

    std.debug.print("\n", .{});
}
