const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");

const StringHashMap = std.StringHashMap;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const is_wasm = builtin.target.cpu.arch.isWasm();

pub const SetTextFn = *const fn (?*anyopaque, u32, []const u8) void;
pub const SetAttrFn = *const fn (?*anyopaque, u32, []const u8, []const u8) void;
pub const CreateElementFn = *const fn (?*anyopaque, []const u8) u32;
pub const CreateTextFn = *const fn (?*anyopaque, []const u8) u32;
pub const AppendChildFn = *const fn (?*anyopaque, u32, u32) void;
pub const RegisterEventFn = *const fn (?*anyopaque, []const u8) void;
pub const ResolvePortalFn = *const fn (?*anyopaque, []const u8) u32;

pub const HydrationNodeType = enum {
    element,
    text,
    comment,
    other,
};

pub const HydrationFirstChildFn = *const fn (?*anyopaque, u32) ?u32;
pub const HydrationNextSiblingFn = *const fn (?*anyopaque, u32) ?u32;
pub const HydrationNodeTypeFn = *const fn (?*anyopaque, u32) HydrationNodeType;
pub const HydrationTagNameFn = *const fn (?*anyopaque, u32) []const u8;
pub const HydrationTextFn = *const fn (?*anyopaque, u32) []const u8;
pub const HydrationAttrFn = *const fn (?*anyopaque, u32, []const u8) ?[]const u8;
pub const HydrationCommentFn = *const fn (?*anyopaque, u32) []const u8;

pub const HostCallbacks = struct {
    set_text: SetTextFn,
    create_element: CreateElementFn,
    create_text: CreateTextFn,
    append_child: AppendChildFn,
    set_attribute: SetAttrFn,
    register_event: RegisterEventFn,
    resolve_portal: ResolvePortalFn,
    context: ?*anyopaque = null,

    pub fn init() HostCallbacks {
        return .{
            .set_text = defaultSetText,
            .create_element = defaultCreateElement,
            .create_text = defaultCreateText,
            .append_child = defaultAppendChild,
            .set_attribute = defaultSetAttribute,
            .register_event = defaultRegisterEvent,
            .resolve_portal = defaultResolvePortal,
            .context = null,
        };
    }
};

threadlocal var host_callbacks: HostCallbacks = HostCallbacks.init();
threadlocal var next_node_id: u32 = 1;

pub const HydrationCallbacks = struct {
    first_child: HydrationFirstChildFn,
    next_sibling: HydrationNextSiblingFn,
    node_type: HydrationNodeTypeFn,
    tag_name: HydrationTagNameFn,
    text_content: HydrationTextFn,
    get_attribute: HydrationAttrFn,
    comment_text: HydrationCommentFn,
    context: ?*anyopaque = null,

    pub fn init() HydrationCallbacks {
        return .{
            .first_child = defaultFirstChild,
            .next_sibling = defaultNextSibling,
            .node_type = defaultNodeType,
            .tag_name = defaultTagName,
            .text_content = defaultTextContent,
            .get_attribute = defaultGetAttribute,
            .comment_text = defaultCommentText,
            .context = null,
        };
    }
};

threadlocal var hydration_callbacks: HydrationCallbacks = HydrationCallbacks.init();

pub fn setHostCallbacks(callbacks: HostCallbacks) void {
    host_callbacks = callbacks;
}

pub fn resetHostCallbacks() void {
    host_callbacks = HostCallbacks.init();
    next_node_id = 1;
}

pub fn setHydrationCallbacks(callbacks: HydrationCallbacks) void {
    hydration_callbacks = callbacks;
}

pub fn resetHydrationCallbacks() void {
    hydration_callbacks = HydrationCallbacks.init();
}

const Host = if (is_wasm) struct {
    extern "env" fn ripple_dom_set_text(node_id: u32, ptr: [*]const u8, len: usize) void;
    extern "env" fn ripple_dom_create_element(ptr: [*]const u8, len: usize) u32;
    extern "env" fn ripple_dom_create_text(ptr: [*]const u8, len: usize) u32;
    extern "env" fn ripple_dom_append_child(parent_id: u32, child_id: u32) void;
    extern "env" fn ripple_dom_set_attribute(node_id: u32, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) void;
    extern "env" fn ripple_dom_resolve_portal(ptr: [*]const u8, len: usize) u32;
} else struct {};

fn nextNodeId() u32 {
    defer next_node_id += 1;
    return next_node_id;
}

fn defaultSetText(ctx_ptr: ?*anyopaque, node_id: u32, value: []const u8) void {
    _ = ctx_ptr;
    if (is_wasm) {
        Host.ripple_dom_set_text(node_id, value.ptr, value.len);
    } else {
        std.debug.print("[dom] node {} <= {s}\n", .{ node_id, value });
    }
}

fn defaultCreateElement(ctx_ptr: ?*anyopaque, tag: []const u8) u32 {
    _ = ctx_ptr;
    if (is_wasm) {
        return Host.ripple_dom_create_element(tag.ptr, tag.len);
    }
    const id = nextNodeId();
    std.debug.print("[dom] create <{s}> -> {}\n", .{ tag, id });
    return id;
}

fn defaultCreateText(ctx_ptr: ?*anyopaque, value: []const u8) u32 {
    _ = ctx_ptr;
    if (is_wasm) {
        return Host.ripple_dom_create_text(value.ptr, value.len);
    }
    const id = nextNodeId();
    std.debug.print("[dom] text {} <= {s}\n", .{ id, value });
    return id;
}

fn defaultAppendChild(ctx_ptr: ?*anyopaque, parent: u32, child: u32) void {
    _ = ctx_ptr;
    if (is_wasm) {
        Host.ripple_dom_append_child(parent, child);
    } else {
        std.debug.print("[dom] append {} -> {}\n", .{ child, parent });
    }
}

fn defaultSetAttribute(ctx_ptr: ?*anyopaque, node_id: u32, name: []const u8, value: []const u8) void {
    _ = ctx_ptr;
    if (is_wasm) {
        Host.ripple_dom_set_attribute(node_id, name.ptr, name.len, value.ptr, value.len);
    } else {
        std.debug.print("[dom] attr {} {s}={s}\n", .{ node_id, name, value });
    }
}

fn defaultRegisterEvent(ctx_ptr: ?*anyopaque, event_name: []const u8) void {
    _ = ctx_ptr;
    if (!is_wasm) {
        std.debug.print("[dom] register event {s}\n", .{event_name});
    }
}

fn defaultResolvePortal(ctx_ptr: ?*anyopaque, target: []const u8) u32 {
    _ = ctx_ptr;
    if (is_wasm) {
        return Host.ripple_dom_resolve_portal(target.ptr, target.len);
    } else {
        std.debug.print("[dom] resolve portal {s} (noop)\n", .{target});
        return 0;
    }
}

fn hydrationPanic(comptime what: []const u8) noreturn {
    @panic(what);
}

fn defaultFirstChild(ctx_ptr: ?*anyopaque, parent: u32) ?u32 {
    _ = ctx_ptr;
    _ = parent;
    hydrationPanic("Hydration first_child callback not configured");
}

fn defaultNextSibling(ctx_ptr: ?*anyopaque, node: u32) ?u32 {
    _ = ctx_ptr;
    _ = node;
    hydrationPanic("Hydration next_sibling callback not configured");
}

fn defaultNodeType(ctx_ptr: ?*anyopaque, node: u32) HydrationNodeType {
    _ = ctx_ptr;
    _ = node;
    hydrationPanic("Hydration node_type callback not configured");
}

fn defaultTagName(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
    _ = ctx_ptr;
    _ = node;
    hydrationPanic("Hydration tag_name callback not configured");
}

fn defaultTextContent(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
    _ = ctx_ptr;
    _ = node;
    hydrationPanic("Hydration text_content callback not configured");
}

fn defaultGetAttribute(ctx_ptr: ?*anyopaque, node: u32, name: []const u8) ?[]const u8 {
    _ = ctx_ptr;
    _ = node;
    _ = name;
    hydrationPanic("Hydration get_attribute callback not configured");
}

fn defaultCommentText(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
    _ = ctx_ptr;
    _ = node;
    hydrationPanic("Hydration comment_text callback not configured");
}

pub fn hostSetText(node_id: u32, value: []const u8) void {
    host_callbacks.set_text(host_callbacks.context, node_id, value);
}

pub fn hostCreateElement(tag: []const u8) u32 {
    return host_callbacks.create_element(host_callbacks.context, tag);
}

pub fn hostCreateText(value: []const u8) u32 {
    return host_callbacks.create_text(host_callbacks.context, value);
}

pub fn hostAppendChild(parent: u32, child: u32) void {
    host_callbacks.append_child(host_callbacks.context, parent, child);
}

pub fn hostSetAttribute(node_id: u32, name: []const u8, value: []const u8) void {
    host_callbacks.set_attribute(host_callbacks.context, node_id, name, value);
}

pub fn hostFirstChild(node_id: u32) ?u32 {
    return hydration_callbacks.first_child(hydration_callbacks.context, node_id);
}

pub fn hostNextSibling(node_id: u32) ?u32 {
    return hydration_callbacks.next_sibling(hydration_callbacks.context, node_id);
}

pub fn hostHydrationNodeType(node_id: u32) HydrationNodeType {
    return hydration_callbacks.node_type(hydration_callbacks.context, node_id);
}

pub fn hostHydrationTag(node_id: u32) []const u8 {
    return hydration_callbacks.tag_name(hydration_callbacks.context, node_id);
}

pub fn hostHydrationText(node_id: u32) []const u8 {
    return hydration_callbacks.text_content(hydration_callbacks.context, node_id);
}

pub fn hostHydrationAttribute(node_id: u32, name: []const u8) ?[]const u8 {
    return hydration_callbacks.get_attribute(hydration_callbacks.context, node_id, name);
}

pub fn hostHydrationComment(node_id: u32) []const u8 {
    return hydration_callbacks.comment_text(hydration_callbacks.context, node_id);
}

pub fn hostResolvePortal(target: []const u8) u32 {
    return host_callbacks.resolve_portal(host_callbacks.context, target);
}

pub const EventCallback = *const fn (*SyntheticEvent, ?*anyopaque) void;

pub const EventHandler = struct {
    callback: EventCallback,
    context: ?*anyopaque = null,
};

pub const EventListenerOptions = struct {
    once: bool = false,
};

pub const EventDetail = struct {
    payload: ?[]const u8 = null,
    data_ptr: ?*anyopaque = null,
};

pub const DispatchOptions = struct {
    path: []const u32 = &.{},
    detail: EventDetail = .{},
    bubbles: bool = true,
};

pub const SyntheticEvent = struct {
    event_type: []const u8,
    target: u32,
    current_target: u32 = 0,
    bubbles: bool,
    default_prevented: bool = false,
    propagation_stopped: bool = false,
    detail_payload: ?[]const u8 = null,
    detail_data: ?*anyopaque = null,

    pub fn preventDefault(self: *@This()) void {
        self.default_prevented = true;
    }

    pub fn stopPropagation(self: *@This()) void {
        self.propagation_stopped = true;
    }

    pub fn isDefaultPrevented(self: @This()) bool {
        return self.default_prevented;
    }

    pub fn payload(self: @This()) ?[]const u8 {
        return self.detail_payload;
    }

    pub fn data(self: @This()) ?*anyopaque {
        return self.detail_data;
    }
};

const Listener = struct {
    node_id: u32,
    handler: EventHandler,
    once: bool,
};

const EventEntry = struct {
    listeners: ArrayListUnmanaged(Listener) = .{},
    host_registered: bool = false,
};

const EventDelegator = struct {
    allocator: std.mem.Allocator,
    map: StringHashMap(EventEntry),

    fn init(allocator: std.mem.Allocator) EventDelegator {
        return .{ .allocator = allocator, .map = StringHashMap(EventEntry).init(allocator) };
    }

    fn deinit(self: *EventDelegator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
            entry.value_ptr.listeners.deinit(self.allocator);
        }
        self.map.deinit();
    }

    fn ensureEntry(self: *EventDelegator, event_name: []const u8) !*EventEntry {
        const gop = try self.map.getOrPut(event_name);
        if (!gop.found_existing) {
            gop.key_ptr.* = try self.allocator.dupe(u8, event_name);
            gop.value_ptr.* = .{};
        }
        return gop.value_ptr;
    }

    fn getEntry(self: *EventDelegator, event_name: []const u8) ?*EventEntry {
        return self.map.getPtr(event_name);
    }
};

threadlocal var event_gpa_state = GeneralPurposeAllocator(.{}){};
threadlocal var event_delegator: EventDelegator = undefined;
threadlocal var event_delegator_initialized = false;

fn eventAllocator() std.mem.Allocator {
    return event_gpa_state.allocator();
}

fn ensureEventDelegator() void {
    if (event_delegator_initialized) return;
    event_delegator = EventDelegator.init(eventAllocator());
    event_delegator_initialized = true;
}

fn hostRegisterEvent(event_name: []const u8) void {
    host_callbacks.register_event(host_callbacks.context, event_name);
}

fn findListenerIndex(listeners: []Listener, node_id: u32, handler: EventHandler) ?usize {
    for (listeners, 0..) |listener, idx| {
        if (listener.node_id == node_id and listener.handler.callback == handler.callback and listener.handler.context == handler.context) {
            return idx;
        }
    }
    return null;
}

fn swapRemove(list: *ArrayListUnmanaged(Listener), index: usize) void {
    const last = list.items.len - 1;
    if (index != last) {
        list.items[index] = list.items[last];
    }
    list.items.len -= 1;
}

pub fn addDelegatedEventListener(node_id: u32, event_name: []const u8, handler: EventHandler, options: EventListenerOptions) !void {
    ensureEventDelegator();
    const entry = try event_delegator.ensureEntry(event_name);
    if (!entry.host_registered) {
        hostRegisterEvent(event_name);
        entry.host_registered = true;
    }

    if (findListenerIndex(entry.listeners.items, node_id, handler)) |idx| {
        entry.listeners.items[idx].once = options.once;
        return;
    }

    try entry.listeners.append(event_delegator.allocator, .{
        .node_id = node_id,
        .handler = handler,
        .once = options.once,
    });
}

pub fn removeDelegatedEventListener(node_id: u32, event_name: []const u8, handler: EventHandler) void {
    if (!event_delegator_initialized) return;
    const entry = event_delegator.getEntry(event_name) orelse return;
    if (findListenerIndex(entry.listeners.items, node_id, handler)) |idx| {
        swapRemove(&entry.listeners, idx);
    }
}

pub fn dispatchEvent(event_name: []const u8, target: u32, options: DispatchOptions) bool {
    if (!event_delegator_initialized) return false;
    const entry = event_delegator.getEntry(event_name) orelse return false;

    var event = SyntheticEvent{
        .event_type = event_name,
        .target = target,
        .bubbles = options.bubbles,
        .detail_payload = options.detail.payload,
        .detail_data = options.detail.data_ptr,
    };

    var fallback_path = [_]u32{target};
    const path = if (options.path.len != 0) options.path else fallback_path[0..];
    const limit = if (options.bubbles) path.len else @min(path.len, 1);

    var path_index: usize = 0;
    while (path_index < limit) : (path_index += 1) {
        const node = path[path_index];
        event.current_target = node;

        var i: usize = 0;
        while (i < entry.listeners.items.len) {
            const listener_ptr = &entry.listeners.items[i];
            if (listener_ptr.node_id != node) {
                i += 1;
                continue;
            }

            listener_ptr.handler.callback(&event, listener_ptr.handler.context);

            if (listener_ptr.once) {
                swapRemove(&entry.listeners, i);
                continue;
            }

            if (event.propagation_stopped) break;
            i += 1;
        }

        if (event.propagation_stopped) break;
    }

    return event.default_prevented;
}

pub fn resetEventDelegation() void {
    if (event_delegator_initialized) {
        event_delegator.deinit();
        event_delegator_initialized = false;
    }
    _ = event_gpa_state.deinit();
    event_gpa_state = GeneralPurposeAllocator(.{}){};
}

const TextContext = struct {
    node_id: u32,
    read: core.ReadSignal([]const u8),
};

fn textEffect(effect_ctx: *core.EffectContext) anyerror!void {
    const ctx = effect_ctx.userData(TextContext).?;
    const value = try ctx.read.get();
    hostSetText(ctx.node_id, value);
}

pub const TextBinding = struct {
    effect: core.EffectHandle,
    allocator: std.mem.Allocator,
    context: *TextContext,

    pub fn dispose(self: *@This()) void {
        self.effect.dispose();
        self.allocator.destroy(self.context);
        self.effect = undefined;
        self.context = undefined;
    }
};

pub fn bindText(
    allocator: std.mem.Allocator,
    node_id: u32,
    read: core.ReadSignal([]const u8),
) !TextBinding {
    const ctx = try allocator.create(TextContext);
    ctx.* = .{ .node_id = node_id, .read = read };
    const effect = try core.createEffect(allocator, textEffect, ctx);
    return .{
        .effect = effect,
        .allocator = allocator,
        .context = ctx,
    };
}
