//! Ripple: reactive WebAssembly-first runtime for Zig.
const std = @import("std");
const core = @import("core.zig");
const dom = @import("dom.zig");
const template = @import("template.zig");
const render = @import("render.zig");
const component = @import("component.zig");
const control_flow = @import("control_flow.zig");
const router = @import("router.zig");
const form = @import("form.zig");

pub const EffectCallback = core.EffectCallback;
pub const EffectContext = core.EffectContext;
pub const EffectHandle = core.EffectHandle;
pub const SignalPair = core.SignalPair;
pub const ReadSignal = core.ReadSignal;
pub const WriteSignal = core.WriteSignal;
pub const MemoHandle = core.MemoHandle;
pub const BatchGuard = core.BatchGuard;
pub const ResourceStatus = core.ResourceStatus;
pub const ResourceState = core.ResourceState;
pub const ResourceHandle = core.ResourceHandle;
pub const SuspenseHandle = core.SuspenseHandle;
pub const ContextGuard = core.ContextGuard;
pub const ContextValueGuard = core.ContextValueGuard;
pub const ErrorBoundaryGuard = core.ErrorBoundaryGuard;
pub const ErrorBoundaryToken = core.ErrorBoundaryToken;
pub const TemplatePlan = template.TemplatePlan;
pub const TemplateError = template.TemplateError;
pub const RenderOp = render.RenderOp;
pub const RenderProgram = render.RenderProgram;
pub const RenderError = render.RenderError;
pub const MountResult = render.MountResult;
pub const RenderEventBinding = render.EventBinding;
pub const FormStore = form.FormStore;
pub const FormStoreOptions = form.FormStoreOptions;
pub const FieldConfig = form.FieldConfig;
pub const FieldView = form.FieldView;
pub const FormSnapshot = form.FormSnapshot;
pub const FormValidationOutcome = form.ValidationOutcome;
pub const FormAsyncValidation = form.AsyncValidation;
pub const FormValidationResult = form.ValidationResult;
pub const FormValidationAdapter = form.ValidationAdapter;
pub const FormValidationBatchGuard = form.FormStore.ValidationBatchGuard;
pub const FormValidationDebouncer = form.FormStore.ValidationDebouncer;
pub const FormValidationThrottler = form.FormStore.ValidationThrottler;
pub const FormCrossFieldValidationConfig = form.FormStore.CrossFieldValidationConfig;
pub const FormSchemaValidationConfig = form.SchemaValidationConfig;
pub const FormSchemaFieldConfig = form.SchemaFieldConfig;
pub const FormSchemaRule = form.SchemaRule;
pub const FormSchemaCustomRule = form.SchemaCustomRule;
pub const FormSchemaCrossFieldRule = form.SchemaCrossFieldRule;
pub const FormSchemaCrossFieldCustom = form.SchemaCrossFieldCustom;
pub const FormSchemaMatchFieldRule = form.SchemaMatchFieldRule;
pub const FormErrorSummary = form.ErrorSummary;
pub const FormErrorSummaryItem = form.ErrorSummaryItem;
pub const ZSchemaMinLengthRule = form.ZSchemaMinLengthRule;
pub const createZSchemaMinLengthAdapter = form.createZSchemaMinLengthAdapter;
pub const FormSerializedField = form.SerializedField;
pub const FormSerializedForm = form.SerializedForm;
pub const FormSubmitOptions = form.FormSubmitOptions;
pub const FormSubmitBinding = form.FormSubmitBinding;
pub const FormTextBinding = form.TextBinding;
pub const FormSelectBinding = form.SelectBinding;
pub const FormCheckboxBinding = form.CheckboxBinding;
pub const FormAriaInvalidBinding = form.AriaInvalidBinding;
pub const bindTextInput = form.bindTextInput;
pub const bindSelect = form.bindSelect;
pub const bindCheckbox = form.bindCheckbox;
pub const bindAriaInvalid = form.bindAriaInvalid;
pub const bindFormSubmit = form.bindFormSubmit;

const TestHydrationDom = struct {
    const Self = @This();
    const NodeType = DomHydrationNodeType;

    pub const Attr = struct {
        name: []const u8,
        value: []const u8,
    };

    pub const Node = struct {
        node_type: NodeType,
        tag: []const u8 = &.{},
        text: []const u8 = &.{},
        comment: []const u8 = &.{},
        first_child: ?u32 = null,
        next_sibling: ?u32 = null,
        attrs: []const Attr = &.{},
    };

    allocator: std.mem.Allocator,
    nodes: std.AutoArrayHashMap(u32, Node),

    fn init(alloc: std.mem.Allocator) Self {
        return .{ .allocator = alloc, .nodes = std.AutoArrayHashMap(u32, Node).init(alloc) };
    }

    fn deinit(self: *Self) void {
        self.nodes.deinit();
    }

    fn put(self: *Self, id: u32, node: Node) void {
        self.nodes.put(id, node) catch unreachable;
    }

    fn get(self: *Self, id: u32) *const Node {
        return self.nodes.getPtr(id) orelse unreachable;
    }

    fn cast(ctx_ptr: ?*anyopaque) *Self {
        const ptr = ctx_ptr orelse unreachable;
        return @as(*Self, @ptrFromInt(@intFromPtr(ptr)));
    }

    fn firstChild(ctx_ptr: ?*anyopaque, parent: u32) ?u32 {
        return Self.cast(ctx_ptr).get(parent).first_child;
    }

    fn nextSibling(ctx_ptr: ?*anyopaque, node: u32) ?u32 {
        return Self.cast(ctx_ptr).get(node).next_sibling;
    }

    fn nodeType(ctx_ptr: ?*anyopaque, node: u32) DomHydrationNodeType {
        return Self.cast(ctx_ptr).get(node).node_type;
    }

    fn tagName(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
        const record = Self.cast(ctx_ptr).get(node);
        std.debug.assert(record.node_type == .element);
        return record.tag;
    }

    fn textValue(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
        const record = Self.cast(ctx_ptr).get(node);
        std.debug.assert(record.node_type == .text);
        return record.text;
    }

    fn attrValue(ctx_ptr: ?*anyopaque, node: u32, name: []const u8) ?[]const u8 {
        const record = Self.cast(ctx_ptr).get(node);
        std.debug.assert(record.node_type == .element);
        for (record.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, name)) return attr.value;
        }
        return null;
    }

    fn commentValue(ctx_ptr: ?*anyopaque, node: u32) []const u8 {
        const record = Self.cast(ctx_ptr).get(node);
        std.debug.assert(record.node_type == .comment);
        return record.comment;
    }
};

pub const createSignal = core.createSignal;
pub const createEffect = core.createEffect;
pub const createMemo = core.createMemo;
pub const createResource = core.createResource;
pub const createSuspenseBoundary = core.createSuspenseBoundary;
pub const beginBatch = core.beginBatch;
pub const batch = core.batch;
pub const flushPending = core.flushPending;
pub const pushContext = core.pushContext;
pub const withContext = core.withContext;
pub const useContext = core.useContext;
pub const pushErrorBoundary = core.pushErrorBoundary;
pub const popErrorBoundary = core.popErrorBoundary;
pub const beginErrorBoundary = core.beginErrorBoundary;
pub const compileTemplate = template.compileTemplate;
pub const renderTemplate = template.render;
pub const buildRenderProgram = render.buildRenderProgram;
pub const mountRenderProgram = render.mountRenderProgram;
pub const hydrateRenderProgram = render.hydrateRenderProgram;
pub const DomHostCallbacks = dom.HostCallbacks;
pub const DomSetTextFn = dom.SetTextFn;
pub const DomCreateElementFn = dom.CreateElementFn;
pub const DomCreateTextFn = dom.CreateTextFn;
pub const DomAppendChildFn = dom.AppendChildFn;
pub const DomSetAttrFn = dom.SetAttrFn;
pub const DomEventCallback = dom.EventCallback;
pub const DomEventHandler = dom.EventHandler;
pub const DomEventListenerOptions = dom.EventListenerOptions;
pub const DomEventDetail = dom.EventDetail;
pub const DomDispatchOptions = dom.DispatchOptions;
pub const DomSyntheticEvent = dom.SyntheticEvent;
pub const DomHydrationNodeType = dom.HydrationNodeType;
pub const DomHydrationCallbacks = dom.HydrationCallbacks;
pub const setDomHostCallbacks = dom.setHostCallbacks;
pub const resetDomHostCallbacks = dom.resetHostCallbacks;
pub const setDomHydrationCallbacks = dom.setHydrationCallbacks;
pub const resetDomHydrationCallbacks = dom.resetHydrationCallbacks;
pub const addDomEventListener = dom.addDelegatedEventListener;
pub const removeDomEventListener = dom.removeDelegatedEventListener;
pub const dispatchDomEvent = dom.dispatchEvent;
pub const resetDomEventDelegation = dom.resetEventDelegation;
pub const bindText = dom.bindText;
pub const hostCreateElement = dom.hostCreateElement;
pub const hostCreateText = dom.hostCreateText;
pub const hostAppendChild = dom.hostAppendChild;
pub const hostSetAttribute = dom.hostSetAttribute;
pub const hostSetText = dom.hostSetText;
pub const View = component.View;
pub const ViewBuilder = component.ViewBuilder;
pub const Props = component.Props;
pub const ComponentScope = component.ComponentScope;
pub const createComponent = component.createComponent;
pub const Show = control_flow.Show;
pub const For = control_flow.For;
pub const ForOptions = control_flow.ForOptions;
pub const Switch = control_flow.Switch;
pub const Match = control_flow.Match;
pub const Router = router.Router;
pub const Route = router.Route;
pub const RouteParams = router.RouteParams;
pub const RouteMatch = router.RouteMatch;
pub const RouteGuard = router.RouteGuard;
pub const Link = router.Link;

test "effects react to signal updates" {
    const allocator = std.testing.allocator;
    var count = try createSignal(i32, allocator, 1);
    defer count.dispose();

    var accumulator: i32 = 0;
    const Context = struct {
        read: ReadSignal(i32),
        acc: *i32,
    };
    var ctx = Context{ .read = count.read, .acc = &accumulator };

    var handle = try createEffect(allocator, struct {
        fn run(effect_ctx: *EffectContext) anyerror!void {
            const data = effect_ctx.userData(Context).?;
            const value = try data.read.get();
            data.acc.* += value;
        }
    }.run, &ctx);
    defer handle.dispose();

    try count.write.set(2);
    try count.write.set(3);

    try std.testing.expectEqual(@as(i32, 6), accumulator);
}

test "memo recomputes for dependencies" {
    const allocator = std.testing.allocator;
    var source = try createSignal(i32, allocator, 10);
    defer source.dispose();

    const MemoData = struct {
        read: ReadSignal(i32),
    };
    var data = MemoData{ .read = source.read };

    var memo = try createMemo(i32, allocator, struct {
        fn compute(_: *EffectContext, payload: ?*anyopaque) anyerror!i32 {
            const memo_ptr = @as(*MemoData, @ptrFromInt(@intFromPtr(payload.?)));
            const value = try memo_ptr.read.get();
            return value * value;
        }
    }.compute, &data);
    defer memo.dispose();

    try std.testing.expectEqual(@as(i32, 100), try memo.get());

    try source.write.set(5);
    try std.testing.expectEqual(@as(i32, 25), try memo.get());
}

test "batch coalesces effect flush" {
    const allocator = std.testing.allocator;
    var counter = try createSignal(i32, allocator, 0);
    defer counter.dispose();

    var run_count: usize = 0;
    const Ctx = struct {
        read: ReadSignal(i32),
        runs: *usize,
    };
    var ctx = Ctx{ .read = counter.read, .runs = &run_count };

    var effect = try createEffect(allocator, struct {
        fn track(effect_ctx: *EffectContext) anyerror!void {
            const data = effect_ctx.userData(Ctx).?;
            _ = try data.read.get();
            data.runs.* += 1;
        }
    }.track, &ctx);
    defer effect.dispose();

    try std.testing.expectEqual(@as(usize, 1), run_count);

    try counter.write.set(1);
    try std.testing.expectEqual(@as(usize, 2), run_count);

    var guard = beginBatch();
    defer guard.deinit();
    try counter.write.set(2);
    try counter.write.set(3);
    try guard.commit();

    try std.testing.expectEqual(@as(usize, 3), run_count);
    try std.testing.expectEqual(@as(i32, 3), try counter.read.get());
}

test "dom text binding updates host" {
    const allocator = std.testing.allocator;
    var text = try createSignal([]const u8, allocator, "hello");
    defer text.dispose();

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    var call_count: usize = 0;
    var last_node: u32 = 0;

    const HostState = struct {
        call_count: *usize,
        buffer: *std.ArrayListUnmanaged(u8),
        node: *u32,
        allocator: std.mem.Allocator,
    };

    var state = HostState{ .call_count = &call_count, .buffer = &buffer, .node = &last_node, .allocator = allocator };

    var callbacks = DomHostCallbacks.init();
    callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&state)));
    callbacks.set_text = struct {
        fn update(ctx_ptr: ?*anyopaque, node_id: u32, value: []const u8) void {
            const ctx = ctx_ptr orelse return;
            const st = @as(*HostState, @ptrFromInt(@intFromPtr(ctx)));
            st.call_count.* += 1;
            st.node.* = node_id;
            st.buffer.clearRetainingCapacity();
            st.buffer.appendSlice(st.allocator, value) catch unreachable;
        }
    }.update;
    setDomHostCallbacks(callbacks);
    defer resetDomHostCallbacks();

    var binding = try bindText(allocator, 1, text.read);
    defer binding.dispose();

    try std.testing.expectEqual(@as(usize, 1), call_count);
    try std.testing.expectEqual(@as(u32, 1), last_node);
    try std.testing.expect(std.mem.eql(u8, buffer.items, "hello"));

    try text.write.set("world");
    try std.testing.expectEqual(@as(usize, 2), call_count);
    try std.testing.expect(std.mem.eql(u8, buffer.items, "world"));
}

test "resource updates state for success and failure" {
    const allocator = std.testing.allocator;
    var source = try createSignal(u32, allocator, 2);
    defer source.dispose();

    var resource = try createResource(u32, u32, allocator, source.read, struct {
        fn fetch(value: u32) anyerror!u32 {
            if (value % 2 == 1) return error.Odd;
            return value * 2;
        }
    }.fetch);
    defer resource.dispose();

    try flushPending();

    var state_signal = resource.read();

    const first_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.ready, first_state.status);
    try std.testing.expectEqual(@as(u32, 4), first_state.value.?);
    try std.testing.expect(first_state.error_message == null);

    try source.write.set(3);
    try flushPending();

    const failed_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.failed, failed_state.status);
    try std.testing.expectEqualStrings("Odd", failed_state.error_message.?);
    try std.testing.expect(failed_state.value == null);

    try source.write.set(4);
    try flushPending();

    const final_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.ready, final_state.status);
    try std.testing.expectEqual(@as(u32, 8), final_state.value.?);
    try std.testing.expect(final_state.error_message == null);
}

test "suspense boundary tracks pending resources" {
    const allocator = std.testing.allocator;
    var toggle = try createSignal(bool, allocator, false);
    defer toggle.dispose();

    var boundary = try createSuspenseBoundary(allocator);
    defer boundary.dispose();

    var ctx_guard = try boundary.enter();
    defer ctx_guard.release();

    var pending_events = std.ArrayListUnmanaged(usize){};
    defer pending_events.deinit(allocator);

    const PendingCtx = struct {
        read: ReadSignal(usize),
        log: *std.ArrayListUnmanaged(usize),
        allocator: std.mem.Allocator,
    };

    var pending_ctx = PendingCtx{
        .read = boundary.pendingSignal(),
        .log = &pending_events,
        .allocator = allocator,
    };

    var pending_effect = try createEffect(allocator, struct {
        fn run(effect_ctx: *EffectContext) anyerror!void {
            const payload = effect_ctx.userData(PendingCtx).?;
            const count = try payload.read.get();
            try payload.log.append(payload.allocator, count);
        }
    }.run, &pending_ctx);
    defer pending_effect.dispose();

    var resource = try createResource(bool, usize, allocator, toggle.read, struct {
        fn fetch(flag: bool) anyerror!usize {
            if (flag) return error.FetchFailed;
            return 7;
        }
    }.fetch);
    defer resource.dispose();

    var state_signal = resource.read();

    try flushPending();

    try std.testing.expect(pending_events.items.len >= 3);
    try std.testing.expectEqual(@as(usize, 0), pending_events.items[0]);
    try std.testing.expect(std.mem.indexOfScalar(usize, pending_events.items, 1) != null);
    try std.testing.expectEqual(@as(usize, 0), pending_events.items[pending_events.items.len - 1]);

    const initial_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.ready, initial_state.status);
    try std.testing.expectEqual(@as(usize, 7), initial_state.value.?);

    const ready_events_len = pending_events.items.len;
    try toggle.write.set(true);
    try flushPending();

    try std.testing.expect(pending_events.items.len >= ready_events_len + 1);
    try std.testing.expectEqual(@as(usize, 0), pending_events.items[pending_events.items.len - 1]);

    const failed_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.failed, failed_state.status);
    try std.testing.expectEqualStrings("FetchFailed", failed_state.error_message.?);

    const failed_events_len = pending_events.items.len;
    try toggle.write.set(false);
    try flushPending();

    const final_state = try state_signal.get();
    try std.testing.expectEqual(ResourceStatus.ready, final_state.status);
    try std.testing.expectEqual(@as(usize, 7), final_state.value.?);
    try std.testing.expect(pending_events.items.len >= failed_events_len + 1);
    try std.testing.expectEqual(@as(usize, 0), pending_events.items[pending_events.items.len - 1]);
}

test "template compile splits static and dynamic segments" {
    const plan = compileTemplate("<div class=\"greeting\">Hello {{ name }}! {{title}}</div>");

    try std.testing.expectEqual(@as(usize, 2), plan.placeholderCount());
    try std.testing.expectEqual(@as(usize, 3), plan.static_parts.len);
    try std.testing.expectEqualSlices(u8, "<div class=\"greeting\">Hello ", plan.static_parts[0]);
    try std.testing.expectEqualSlices(u8, "! ", plan.static_parts[1]);
    try std.testing.expectEqualSlices(u8, "</div>", plan.static_parts[2]);
    try std.testing.expectEqualSlices(u8, "name", plan.placeholders[0]);
    try std.testing.expectEqualSlices(u8, "title", plan.placeholders[1]);
}

test "template render concatenates static and dynamic content" {
    const allocator = std.testing.allocator;
    const plan = compileTemplate("Hello {{ name }}!");
    const rendered = try renderTemplate(plan, allocator, &[_][]const u8{"Ripple"});
    defer allocator.free(rendered);

    try std.testing.expectEqualSlices(u8, "Hello Ripple!", rendered);

    const err = renderTemplate(plan, allocator, &[_][]const u8{});
    try std.testing.expectError(TemplateError.MismatchedValues, err);
}

test "render program interleaves static and dynamic ops" {
    const allocator = std.testing.allocator;
    const plan = compileTemplate("<span>Hello {{name}}</span>");
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 4), program.ops.len);
    try std.testing.expectEqual(@as(usize, 1), program.dynamicSlotCount());

    switch (program.ops[0]) {
        .open_element => |info| {
            try std.testing.expectEqualSlices(u8, "span", info.tag);
            try std.testing.expectEqual(@as(u32, 1), info.hydration_id);
        },
        else => return error.TestUnexpectedResult,
    }

    switch (program.ops[1]) {
        .text => |text| try std.testing.expectEqualSlices(u8, "Hello ", text),
        else => return error.TestUnexpectedResult,
    }

    switch (program.ops[2]) {
        .dynamic_text => |idx| try std.testing.expectEqual(@as(usize, 0), idx),
        else => return error.TestUnexpectedResult,
    }

    switch (program.ops[3]) {
        .close_element => |tag| try std.testing.expectEqualSlices(u8, "span", tag),
        else => return error.TestUnexpectedResult,
    }
}

test "mount render program uses host callbacks" {
    const allocator = std.testing.allocator;

    const MockHost = struct {
        const Self = @This();

        const Event = union(enum) {
            create_element: struct { id: u32, tag: []const u8 },
            create_text: struct { id: u32, value: []const u8 },
            append_child: struct { parent: u32, child: u32 },
            set_text: struct { node: u32, value: []const u8 },
            set_attr: struct { node: u32, name: []const u8, value: []const u8 },
        };

        allocator: std.mem.Allocator,
        events: std.ArrayListUnmanaged(Event) = .{},
        next_id: u32 = 100,

        fn deinit(self: *Self) void {
            self.events.deinit(self.allocator);
        }

        fn push(self: *Self, event: Event) void {
            self.events.append(self.allocator, event) catch unreachable;
        }

        fn cast(ctx: ?*anyopaque) *Self {
            const ptr = ctx orelse unreachable;
            return @as(*Self, @ptrFromInt(@intFromPtr(ptr)));
        }

        fn createElement(ctx: ?*anyopaque, tag: []const u8) u32 {
            const self = Self.cast(ctx);
            const id = self.next_id;
            self.next_id += 1;
            self.push(.{ .create_element = .{ .id = id, .tag = tag } });
            return id;
        }

        fn createText(ctx: ?*anyopaque, value: []const u8) u32 {
            const self = Self.cast(ctx);
            const id = self.next_id;
            self.next_id += 1;
            self.push(.{ .create_text = .{ .id = id, .value = value } });
            return id;
        }

        fn appendChild(ctx: ?*anyopaque, parent: u32, child: u32) void {
            const self = Self.cast(ctx);
            self.push(.{ .append_child = .{ .parent = parent, .child = child } });
        }

        fn setText(ctx: ?*anyopaque, node: u32, value: []const u8) void {
            const self = Self.cast(ctx);
            self.push(.{ .set_text = .{ .node = node, .value = value } });
        }

        fn setAttr(ctx: ?*anyopaque, node: u32, name: []const u8, value: []const u8) void {
            const self = Self.cast(ctx);
            self.push(.{ .set_attr = .{ .node = node, .name = name, .value = value } });
        }

        fn registerEvent(ctx: ?*anyopaque, _: []const u8) void {
            _ = ctx;
        }

        fn resolvePortal(ctx: ?*anyopaque, _: []const u8) u32 {
            _ = ctx;
            return 0;
        }
    };

    const host_ptr = try allocator.create(MockHost);
    host_ptr.* = .{ .allocator = allocator };
    defer {
        resetDomHostCallbacks();
        host_ptr.deinit();
        allocator.destroy(host_ptr);
    }

    setDomHostCallbacks(.{
        .set_text = MockHost.setText,
        .create_element = MockHost.createElement,
        .create_text = MockHost.createText,
        .append_child = MockHost.appendChild,
        .set_attribute = MockHost.setAttr,
        .register_event = MockHost.registerEvent,
        .resolve_portal = MockHost.resolvePortal,
        .context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(host_ptr))),
    });

    const plan = compileTemplate("<!--island:hero--><div>Hello {{name}}</div><!--/island-->");
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    var mount = try mountRenderProgram(allocator, program, 1, &[_][]const u8{"Ripple"});
    defer mount.deinit();

    try std.testing.expectEqual(@as(usize, 1), mount.dynamic_nodes.len);
    try std.testing.expectEqual(@as(usize, 1), mount.islands.len);
    const island = mount.islands[0];
    try std.testing.expectEqualSlices(u8, "hero", island.name);
    try std.testing.expectEqual(@as(u32, 1), island.parent);
    try std.testing.expectEqual(@as(usize, 0), island.start_dynamic);
    try std.testing.expectEqual(@as(usize, 1), island.end_dynamic);

    const events = host_ptr.events.items;
    try std.testing.expectEqual(@as(usize, 7), events.len);

    const e0 = events[0];
    switch (e0) {
        .create_element => |info| {
            try std.testing.expectEqual(@as(u32, 100), info.id);
            try std.testing.expectEqualSlices(u8, "div", info.tag);
        },
        else => return error.TestUnexpectedResult,
    }

    const e1 = events[1];
    switch (e1) {
        .append_child => |info| {
            try std.testing.expectEqual(@as(u32, 1), info.parent);
            try std.testing.expectEqual(@as(u32, 100), info.child);
        },
        else => return error.TestUnexpectedResult,
    }

    const e2 = events[2];
    switch (e2) {
        .set_attr => |info| {
            try std.testing.expectEqual(@as(u32, 100), info.node);
            try std.testing.expectEqualSlices(u8, "data-hid", info.name);
            try std.testing.expectEqualSlices(u8, "1", info.value);
        },
        else => return error.TestUnexpectedResult,
    }

    const e3 = events[3];
    switch (e3) {
        .create_text => |info| {
            try std.testing.expectEqual(@as(u32, 101), info.id);
            try std.testing.expectEqualSlices(u8, "Hello ", info.value);
        },
        else => return error.TestUnexpectedResult,
    }

    const e4 = events[4];
    switch (e4) {
        .append_child => |info| {
            try std.testing.expectEqual(@as(u32, 100), info.parent);
            try std.testing.expectEqual(@as(u32, 101), info.child);
        },
        else => return error.TestUnexpectedResult,
    }

    const e5 = events[5];
    switch (e5) {
        .create_text => |info| {
            try std.testing.expectEqual(@as(u32, 102), info.id);
            try std.testing.expectEqualSlices(u8, "Ripple", info.value);
        },
        else => return error.TestUnexpectedResult,
    }

    const e6 = events[6];
    switch (e6) {
        .append_child => |info| {
            try std.testing.expectEqual(@as(u32, 100), info.parent);
            try std.testing.expectEqual(@as(u32, 102), info.child);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(u32, 102), mount.dynamic_nodes[0]);
}

test "delegated events support preventDefault and once" {
    const allocator = std.testing.allocator;

    resetDomEventDelegation();
    defer resetDomEventDelegation();

    var register_count: usize = 0;

    const Host = struct {
        fn register(ctx_ptr: ?*anyopaque, _: []const u8) void {
            const ctx = ctx_ptr orelse unreachable;
            const counter = @as(*usize, @ptrFromInt(@intFromPtr(ctx)));
            counter.* += 1;
        }
    };

    var callbacks = DomHostCallbacks.init();
    callbacks.register_event = Host.register;
    callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&register_count)));
    setDomHostCallbacks(callbacks);
    defer resetDomHostCallbacks();

    const CallRecord = struct {
        node: u32,
        prevented: bool,
    };

    var calls = std.ArrayListUnmanaged(CallRecord){};
    defer calls.deinit(allocator);

    var target_payload_ok = false;
    var parent_saw_prevented = false;

    const TargetCtx = struct {
        log: *std.ArrayListUnmanaged(CallRecord),
        allocator: std.mem.Allocator,
        payload_ok: *bool,
    };

    const ParentCtx = struct {
        log: *std.ArrayListUnmanaged(CallRecord),
        allocator: std.mem.Allocator,
        saw_prevented: *bool,
    };

    var target_ctx = TargetCtx{ .log = &calls, .allocator = allocator, .payload_ok = &target_payload_ok };
    var parent_ctx = ParentCtx{ .log = &calls, .allocator = allocator, .saw_prevented = &parent_saw_prevented };

    const TargetHandler = struct {
        fn handle(ev: *DomSyntheticEvent, ctx_ptr: ?*anyopaque) void {
            const ctx = @as(*TargetCtx, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.log.append(ctx.allocator, .{ .node = ev.current_target, .prevented = ev.isDefaultPrevented() }) catch unreachable;
            if (ev.payload()) |payload| {
                ctx.payload_ok.* = std.mem.eql(u8, payload, "ping");
            }
            ev.preventDefault();
        }
    };

    const ParentHandler = struct {
        fn handle(ev: *DomSyntheticEvent, ctx_ptr: ?*anyopaque) void {
            const ctx = @as(*ParentCtx, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.log.append(ctx.allocator, .{ .node = ev.current_target, .prevented = ev.isDefaultPrevented() }) catch unreachable;
            if (ev.isDefaultPrevented()) ctx.saw_prevented.* = true;
            ev.stopPropagation();
        }
    };

    try addDomEventListener(2, "click", .{
        .callback = TargetHandler.handle,
        .context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&target_ctx))),
    }, .{});

    try addDomEventListener(1, "click", .{
        .callback = ParentHandler.handle,
        .context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&parent_ctx))),
    }, .{ .once = true });

    const path = [_]u32{ 2, 1, 0 };
    const prevented = dispatchDomEvent("click", 2, .{ .path = path[0..], .detail = .{ .payload = "ping" } });
    try std.testing.expect(prevented);

    try std.testing.expectEqual(@as(usize, 2), calls.items.len);
    try std.testing.expectEqual(@as(u32, 2), calls.items[0].node);
    try std.testing.expect(!calls.items[0].prevented);
    try std.testing.expectEqual(@as(u32, 1), calls.items[1].node);
    try std.testing.expect(calls.items[1].prevented);
    try std.testing.expect(target_payload_ok);
    try std.testing.expect(parent_saw_prevented);
    try std.testing.expectEqual(@as(usize, 1), register_count);

    calls.clearRetainingCapacity();

    const prevented_again = dispatchDomEvent("click", 2, .{ .path = path[0..], .detail = .{ .payload = "ping" } });
    try std.testing.expect(prevented_again);
    try std.testing.expectEqual(@as(usize, 1), calls.items.len);
    try std.testing.expectEqual(@as(u32, 2), calls.items[0].node);
    try std.testing.expect(!calls.items[0].prevented);

    const no_bubble = dispatchDomEvent("click", 2, .{ .path = path[0..], .bubbles = false, .detail = .{ .payload = "ping" } });
    try std.testing.expect(no_bubble);
    try std.testing.expectEqual(@as(usize, 2), calls.items.len);
    try std.testing.expectEqual(@as(u32, 2), calls.items[1].node);
}

test "render mount binds delegated events" {
    const allocator = std.testing.allocator;

    resetDomEventDelegation();
    defer resetDomEventDelegation();

    const MockHost = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        next_id: u32 = 50,
        register_count: usize = 0,

        fn cast(ctx_ptr: ?*anyopaque) *Self {
            const ptr = ctx_ptr orelse unreachable;
            return @as(*Self, @ptrFromInt(@intFromPtr(ptr)));
        }

        fn createElement(ctx_ptr: ?*anyopaque, _: []const u8) u32 {
            const self = Self.cast(ctx_ptr);
            const id = self.next_id;
            self.next_id += 1;
            return id;
        }

        fn createText(ctx_ptr: ?*anyopaque, _: []const u8) u32 {
            const self = Self.cast(ctx_ptr);
            const id = self.next_id;
            self.next_id += 1;
            return id;
        }

        fn appendChild(ctx_ptr: ?*anyopaque, _: u32, _: u32) void {
            _ = ctx_ptr;
        }

        fn setAttr(ctx_ptr: ?*anyopaque, _: u32, _: []const u8, _: []const u8) void {
            _ = ctx_ptr;
        }

        fn registerEvent(ctx_ptr: ?*anyopaque, _: []const u8) void {
            const self = Self.cast(ctx_ptr);
            self.register_count += 1;
        }
    };

    const host = try allocator.create(MockHost);
    host.* = .{ .allocator = allocator };
    defer {
        resetDomHostCallbacks();
        allocator.destroy(host);
    }

    var callbacks = DomHostCallbacks.init();
    callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(host)));
    callbacks.create_element = MockHost.createElement;
    callbacks.create_text = MockHost.createText;
    callbacks.append_child = MockHost.appendChild;
    callbacks.set_attribute = MockHost.setAttr;
    callbacks.register_event = MockHost.registerEvent;
    setDomHostCallbacks(callbacks);

    const plan = compileTemplate("<button>Press {{label}}</button>");
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    const dynamic_values = [1][]const u8{"Go"};
    var mount = try mountRenderProgram(allocator, program, 1, &dynamic_values);
    defer mount.deinit();

    var click_count: usize = 0;
    var payload_ok = false;

    const ClickCtx = struct {
        count: *usize,
        payload_ok: *bool,
    };

    var click_ctx = ClickCtx{ .count = &click_count, .payload_ok = &payload_ok };

    const ClickHandler = struct {
        fn handle(ev: *DomSyntheticEvent, ctx_ptr: ?*anyopaque) void {
            const ctx = @as(*ClickCtx, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.count.* += 1;
            if (ev.payload()) |payload| {
                if (std.mem.eql(u8, payload, "fire")) ctx.payload_ok.* = true;
            }
        }
    };

    try mount.bindEvents(&[_]RenderEventBinding{.{
        .hydration_id = 1,
        .event_name = "click",
        .handler = .{
            .callback = ClickHandler.handle,
            .context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&click_ctx))),
        },
    }});

    try std.testing.expectEqual(@as(usize, 1), host.register_count);

    const button_id = mount.nodeForHydrationId(1) orelse return error.TestUnexpectedResult;
    const path = [_]u32{button_id};

    const prevented = dispatchDomEvent("click", button_id, .{ .path = path[0..], .detail = .{ .payload = "fire" } });
    try std.testing.expect(!prevented);
    try std.testing.expectEqual(@as(usize, 1), click_count);
    try std.testing.expect(payload_ok);

    const prevented_second = dispatchDomEvent("click", button_id, .{ .path = path[0..], .detail = .{ .payload = "fire" } });
    try std.testing.expect(!prevented_second);
    try std.testing.expectEqual(@as(usize, 2), click_count);
}

test "hydrate render program maps existing islands" {
    const allocator = std.testing.allocator;

    const plan = compileTemplate(
        "<div>" ++
            "<!-- island:counter -->" ++
            "<section>Count: {{count}}" ++
            "<!-- island:child --><span>Nested {{value}}</span><!-- /island -->" ++
            "</section>" ++
            "<!-- /island -->" ++
            "<!-- island:greeting --><p>Hello {{name}}</p><!-- /island -->" ++
            "</div>",
    );
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    var dom_state = TestHydrationDom.init(allocator);
    defer dom_state.deinit();

    const attr_div = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "1" }};
    const attr_section = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "2" }};
    const attr_span = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "3" }};
    const attr_p = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "4" }};

    dom_state.put(0, .{ .node_type = .element, .tag = "container", .first_child = 1 });
    dom_state.put(1, .{ .node_type = .element, .tag = "div", .attrs = &attr_div, .first_child = 10 });
    dom_state.put(10, .{ .node_type = .comment, .comment = "island:counter", .next_sibling = 2 });
    dom_state.put(2, .{ .node_type = .element, .tag = "section", .attrs = &attr_section, .first_child = 11, .next_sibling = 17 });
    dom_state.put(11, .{ .node_type = .text, .text = "Count: ", .next_sibling = 12 });
    dom_state.put(12, .{ .node_type = .text, .text = "5", .next_sibling = 13 });
    dom_state.put(13, .{ .node_type = .comment, .comment = "island:child", .next_sibling = 3 });
    dom_state.put(3, .{ .node_type = .element, .tag = "span", .attrs = &attr_span, .first_child = 14, .next_sibling = 16 });
    dom_state.put(14, .{ .node_type = .text, .text = "Nested ", .next_sibling = 15 });
    dom_state.put(15, .{ .node_type = .text, .text = "99", .next_sibling = null });
    dom_state.put(16, .{ .node_type = .comment, .comment = "/island", .next_sibling = null });
    dom_state.put(17, .{ .node_type = .comment, .comment = "/island", .next_sibling = 18 });
    dom_state.put(18, .{ .node_type = .comment, .comment = "island:greeting", .next_sibling = 4 });
    dom_state.put(4, .{ .node_type = .element, .tag = "p", .attrs = &attr_p, .first_child = 19, .next_sibling = 21 });
    dom_state.put(19, .{ .node_type = .text, .text = "Hello ", .next_sibling = 20 });
    dom_state.put(20, .{ .node_type = .text, .text = "SSR", .next_sibling = null });
    dom_state.put(21, .{ .node_type = .comment, .comment = "/island", .next_sibling = null });

    var hydration_callbacks = DomHydrationCallbacks.init();
    hydration_callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&dom_state)));
    hydration_callbacks.first_child = TestHydrationDom.firstChild;
    hydration_callbacks.next_sibling = TestHydrationDom.nextSibling;
    hydration_callbacks.node_type = TestHydrationDom.nodeType;
    hydration_callbacks.tag_name = TestHydrationDom.tagName;
    hydration_callbacks.text_content = TestHydrationDom.textValue;
    hydration_callbacks.get_attribute = TestHydrationDom.attrValue;
    hydration_callbacks.comment_text = TestHydrationDom.commentValue;

    setDomHydrationCallbacks(hydration_callbacks);
    defer resetDomHydrationCallbacks();

    var hydrated = try hydrateRenderProgram(allocator, program, 0);
    defer hydrated.deinit();

    try std.testing.expectEqual(@as(usize, 3), hydrated.dynamic_nodes.len);
    try std.testing.expectEqual(@as(u32, 12), hydrated.dynamic_nodes[0]);
    try std.testing.expectEqual(@as(u32, 15), hydrated.dynamic_nodes[1]);
    try std.testing.expectEqual(@as(u32, 20), hydrated.dynamic_nodes[2]);

    try std.testing.expectEqual(@as(usize, 3), hydrated.islands.len);

    const child = hydrated.islands[0];
    try std.testing.expect(std.mem.eql(u8, child.name, "child"));
    try std.testing.expectEqual(@as(u32, 2), child.parent);
    try std.testing.expectEqual(@as(usize, 1), child.start_dynamic);
    try std.testing.expectEqual(@as(usize, 2), child.end_dynamic);

    const counter = hydrated.islands[1];
    try std.testing.expect(std.mem.eql(u8, counter.name, "counter"));
    try std.testing.expectEqual(@as(u32, 1), counter.parent);
    try std.testing.expectEqual(@as(usize, 0), counter.start_dynamic);
    try std.testing.expectEqual(@as(usize, 2), counter.end_dynamic);

    const greeting = hydrated.islands[2];
    try std.testing.expect(std.mem.eql(u8, greeting.name, "greeting"));
    try std.testing.expectEqual(@as(u32, 1), greeting.parent);
    try std.testing.expectEqual(@as(usize, 2), greeting.start_dynamic);
    try std.testing.expectEqual(@as(usize, 3), greeting.end_dynamic);
}

test "mount render program tracks portals and suspense boundaries" {
    const allocator = std.testing.allocator;

    const plan = compileTemplate(
        "<!-- portal:#modal -->" ++
            "{{ portal }}" ++
            "<!-- /portal -->" ++
            "<!-- suspense:start main -->" ++
            "<div>Main {{ main }}</div>" ++
            "<!-- suspense:fallback -->" ++
            "<div>Fallback {{ fallback }}</div>" ++
            "<!-- /suspense -->",
    );
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    const MockHost = struct {
        const Self = @This();

        const Append = struct {
            parent: u32,
            child: u32,
        };

        allocator: std.mem.Allocator,
        append_calls: std.ArrayListUnmanaged(Append) = .{},
        next_id: u32 = 500,
        resolve_target: ?[]u8 = null,
        portal_parent: u32 = 9000,

        fn cast(ctx: ?*anyopaque) *Self {
            const ptr = ctx orelse unreachable;
            return @as(*Self, @ptrFromInt(@intFromPtr(ptr)));
        }

        fn deinit(self: *Self) void {
            if (self.resolve_target) |target| self.allocator.free(target);
            self.append_calls.deinit(self.allocator);
        }

        fn createElement(ctx: ?*anyopaque, _: []const u8) u32 {
            const self = Self.cast(ctx);
            const id = self.next_id;
            self.next_id += 1;
            return id;
        }

        fn createText(ctx: ?*anyopaque, _: []const u8) u32 {
            const self = Self.cast(ctx);
            const id = self.next_id;
            self.next_id += 1;
            return id;
        }

        fn appendChild(ctx: ?*anyopaque, parent: u32, child: u32) void {
            const self = Self.cast(ctx);
            self.append_calls.append(self.allocator, .{ .parent = parent, .child = child }) catch unreachable;
        }

        fn setAttr(_: ?*anyopaque, _: u32, _: []const u8, _: []const u8) void {}

        fn setText(_: ?*anyopaque, _: u32, _: []const u8) void {}

        fn registerEvent(_: ?*anyopaque, _: []const u8) void {}

        fn resolvePortal(ctx: ?*anyopaque, target: []const u8) u32 {
            const self = Self.cast(ctx);
            if (self.resolve_target) |old| self.allocator.free(old);
            self.resolve_target = self.allocator.dupe(u8, target) catch unreachable;
            return self.portal_parent;
        }
    };

    var host = try allocator.create(MockHost);
    host.* = .{ .allocator = allocator };
    defer {
        resetDomHostCallbacks();
        host.deinit();
        allocator.destroy(host);
    }

    var callbacks = DomHostCallbacks.init();
    callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(host)));
    callbacks.create_element = MockHost.createElement;
    callbacks.create_text = MockHost.createText;
    callbacks.append_child = MockHost.appendChild;
    callbacks.set_attribute = MockHost.setAttr;
    callbacks.set_text = MockHost.setText;
    callbacks.register_event = MockHost.registerEvent;
    callbacks.resolve_portal = MockHost.resolvePortal;
    setDomHostCallbacks(callbacks);

    const values = [_][]const u8{ "x", "main", "fallback" };

    var mount = try mountRenderProgram(allocator, program, 1, &values);
    defer mount.deinit();

    try std.testing.expect(host.resolve_target != null);
    try std.testing.expect(std.mem.eql(u8, host.resolve_target.?, "#modal"));
    try std.testing.expectEqual(@as(usize, 3), mount.dynamic_nodes.len);

    try std.testing.expectEqual(@as(usize, 1), mount.portals.len);
    const portal = mount.portals[0];
    try std.testing.expect(std.mem.eql(u8, portal.target, "#modal"));
    try std.testing.expectEqual(host.portal_parent, portal.node);
    try std.testing.expectEqual(@as(usize, 0), portal.start_dynamic);
    try std.testing.expectEqual(@as(usize, 1), portal.end_dynamic);

    var found_portal_append = false;
    for (host.append_calls.items) |call| {
        if (call.parent == host.portal_parent) {
            found_portal_append = true;
            break;
        }
    }
    try std.testing.expect(found_portal_append);

    try std.testing.expectEqual(@as(usize, 1), mount.suspense.len);
    const boundary = mount.suspense[0];
    try std.testing.expect(std.mem.eql(u8, boundary.name, "main"));
    try std.testing.expectEqual(@as(usize, 1), boundary.main_start_dynamic);
    try std.testing.expectEqual(@as(usize, 2), boundary.main_end_dynamic);
    try std.testing.expectEqual(@as(usize, 2), boundary.fallback_start_dynamic);
    try std.testing.expectEqual(@as(usize, 3), boundary.fallback_end_dynamic);
}

test "hydrate render program resolves portals and suspense boundaries" {
    const allocator = std.testing.allocator;

    const plan = compileTemplate(
        "<!-- portal:#modal -->" ++
            "{{ portal }}" ++
            "<!-- /portal -->" ++
            "<!-- suspense:start auth -->" ++
            "<div>Main {{ main }}</div>" ++
            "<!-- suspense:fallback -->" ++
            "<div>Fallback {{ fallback }}</div>" ++
            "<!-- /suspense -->",
    );
    var program = try buildRenderProgram(allocator, plan);
    defer program.deinit();

    const Resolver = struct {
        const Self = @This();

        parent: u32,
        last_target: []const u8 = &.{},

        fn cast(ctx: ?*anyopaque) *Self {
            const ptr = ctx orelse unreachable;
            return @as(*Self, @ptrFromInt(@intFromPtr(ptr)));
        }

        fn resolve(ctx: ?*anyopaque, target: []const u8) u32 {
            const self = Self.cast(ctx);
            self.last_target = target;
            return self.parent;
        }
    };

    var resolver = Resolver{ .parent = 7000 };
    var host_callbacks = DomHostCallbacks.init();
    host_callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&resolver)));
    host_callbacks.resolve_portal = Resolver.resolve;
    setDomHostCallbacks(host_callbacks);
    defer resetDomHostCallbacks();

    var dom_state = TestHydrationDom.init(allocator);
    defer dom_state.deinit();

    const attr_main = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "1" }};
    const attr_fallback = [_]TestHydrationDom.Attr{.{ .name = "data-hid", .value = "2" }};

    dom_state.put(0, .{ .node_type = .element, .tag = "container", .first_child = 10 });
    dom_state.put(10, .{ .node_type = .comment, .comment = "portal:#modal", .next_sibling = 11 });
    dom_state.put(11, .{ .node_type = .comment, .comment = "/portal", .next_sibling = 12 });
    dom_state.put(12, .{ .node_type = .comment, .comment = "suspense:start auth", .next_sibling = 13 });
    dom_state.put(13, .{ .node_type = .element, .tag = "div", .attrs = &attr_main, .first_child = 14, .next_sibling = 17 });
    dom_state.put(14, .{ .node_type = .text, .text = "Main ", .next_sibling = 15 });
    dom_state.put(15, .{ .node_type = .text, .text = "SSR", .next_sibling = null });
    dom_state.put(17, .{ .node_type = .comment, .comment = "suspense:fallback", .next_sibling = 18 });
    dom_state.put(18, .{ .node_type = .element, .tag = "div", .attrs = &attr_fallback, .first_child = 19, .next_sibling = 21 });
    dom_state.put(19, .{ .node_type = .text, .text = "Fallback ", .next_sibling = 20 });
    dom_state.put(20, .{ .node_type = .text, .text = "Idle", .next_sibling = null });
    dom_state.put(21, .{ .node_type = .comment, .comment = "/suspense", .next_sibling = null });

    dom_state.put(resolver.parent, .{ .node_type = .element, .tag = "portal-root", .first_child = 30 });
    dom_state.put(30, .{ .node_type = .text, .text = "Portal SSR", .next_sibling = null });

    var hydration_callbacks = DomHydrationCallbacks.init();
    hydration_callbacks.context = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&dom_state)));
    hydration_callbacks.first_child = TestHydrationDom.firstChild;
    hydration_callbacks.next_sibling = TestHydrationDom.nextSibling;
    hydration_callbacks.node_type = TestHydrationDom.nodeType;
    hydration_callbacks.tag_name = TestHydrationDom.tagName;
    hydration_callbacks.text_content = TestHydrationDom.textValue;
    hydration_callbacks.get_attribute = TestHydrationDom.attrValue;
    hydration_callbacks.comment_text = TestHydrationDom.commentValue;
    setDomHydrationCallbacks(hydration_callbacks);
    defer resetDomHydrationCallbacks();

    var hydrated = try hydrateRenderProgram(allocator, program, 0);
    defer hydrated.deinit();

    try std.testing.expect(std.mem.eql(u8, resolver.last_target, "#modal"));

    try std.testing.expectEqual(@as(usize, 3), hydrated.dynamic_nodes.len);
    try std.testing.expectEqual(@as(u32, 30), hydrated.dynamic_nodes[0]);
    try std.testing.expectEqual(@as(u32, 15), hydrated.dynamic_nodes[1]);
    try std.testing.expectEqual(@as(u32, 20), hydrated.dynamic_nodes[2]);

    try std.testing.expectEqual(@as(usize, 1), hydrated.portals.len);
    const portal = hydrated.portals[0];
    try std.testing.expect(std.mem.eql(u8, portal.target, "#modal"));
    try std.testing.expectEqual(resolver.parent, portal.node);
    try std.testing.expectEqual(@as(usize, 0), portal.start_dynamic);
    try std.testing.expectEqual(@as(usize, 1), portal.end_dynamic);

    try std.testing.expectEqual(@as(usize, 1), hydrated.suspense.len);
    const boundary = hydrated.suspense[0];
    try std.testing.expect(std.mem.eql(u8, boundary.name, "auth"));
    try std.testing.expectEqual(@as(usize, 1), boundary.main_start_dynamic);
    try std.testing.expectEqual(@as(usize, 2), boundary.main_end_dynamic);
    try std.testing.expectEqual(@as(usize, 2), boundary.fallback_start_dynamic);
    try std.testing.expectEqual(@as(usize, 3), boundary.fallback_end_dynamic);
}
