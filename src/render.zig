const std = @import("std");
const dom = @import("dom.zig");
const template = @import("template.zig");

pub const RenderError = template.TemplateError || error{ InvalidMarkup, StackUnderflow, MissingNode, UnexpectedNode, HydrationMismatch };

pub const ElementOp = struct {
    tag: []const u8,
    hydration_id: u32,
};

pub const RenderOp = union(enum) {
    open_element: ElementOp,
    close_element: []const u8,
    self_element: ElementOp,
    text: []const u8,
    dynamic_text: usize,
    island_start: []const u8,
    island_end: []const u8,
    portal_start: []const u8,
    portal_end: void,
    suspense_start: []const u8,
    suspense_fallback: void,
    suspense_end: void,
};

pub const EventBinding = struct {
    hydration_id: u32,
    event_name: []const u8,
    handler: dom.EventHandler,
    options: dom.EventListenerOptions = .{},
};

const whitespace_chars = &[_]u8{ ' ', '\n', '\r', '\t' };

pub const RenderProgram = struct {
    ops: []RenderOp,
    allocator: std.mem.Allocator,
    max_hydration_id: u32,

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.ops);
        self.ops = &.{};
    }

    pub fn dynamicSlotCount(self: @This()) usize {
        var count: usize = 0;
        for (self.ops) |op| {
            if (op == .dynamic_text) count += 1;
        }
        return count;
    }

    pub fn hydrationCapacity(self: @This()) usize {
        return @as(usize, self.max_hydration_id) + 1;
    }
};

const ParseState = struct {
    ops: *std.ArrayListUnmanaged(RenderOp),
    tag_stack: *std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,
    hydration_counter: *u32,

    fn nextHydrationId(self: *@This()) u32 {
        const id = self.hydration_counter.*;
        self.hydration_counter.* += 1;
        return id;
    }
};

fn isTagNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == ':';
}

fn trimWhitespace(slice: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = slice.len;
    while (start < end and std.ascii.isWhitespace(slice[start])) : (start += 1) {}
    while (end > start and std.ascii.isWhitespace(slice[end - 1])) : (end -= 1) {}
    return slice[start..end];
}

fn skipWhitespace(slice: []const u8, index: *usize) void {
    while (index.* < slice.len and std.ascii.isWhitespace(slice[index.*])) : (index.* += 1) {}
}

fn parseTagClose(slice: []const u8, start: usize) RenderError!struct {
    name: []const u8,
    end: usize,
} {
    var idx = start + 2;
    skipWhitespace(slice, &idx);
    const name_start = idx;
    while (idx < slice.len and isTagNameChar(slice[idx])) : (idx += 1) {}
    const name_end = idx;
    if (name_start == name_end) return RenderError.InvalidMarkup;
    skipWhitespace(slice, &idx);
    if (idx >= slice.len or slice[idx] != '>') return RenderError.InvalidMarkup;
    return .{ .name = slice[name_start..name_end], .end = idx + 1 };
}

fn findTagEnd(slice: []const u8, start: usize) RenderError!struct {
    end: usize,
    self_closing: bool,
} {
    var idx = start;
    var in_quote: ?u8 = null;
    while (idx < slice.len) : (idx += 1) {
        const ch = slice[idx];
        if (in_quote) |quote| {
            if (ch == quote) in_quote = null;
            continue;
        }
        if (ch == '"' or ch == '\'') {
            in_quote = ch;
            continue;
        }
        if (ch == '>') {
            var back = idx;
            while (back > start and std.ascii.isWhitespace(slice[back - 1])) : (back -= 1) {}
            const self_closing = back > start and slice[back - 1] == '/';
            return .{ .end = idx + 1, .self_closing = self_closing };
        }
    }
    return RenderError.InvalidMarkup;
}

fn parseTagOpen(slice: []const u8, start: usize) RenderError!struct {
    name: []const u8,
    end: usize,
    self_closing: bool,
} {
    var idx = start + 1;
    skipWhitespace(slice, &idx);
    const name_start = idx;
    while (idx < slice.len and isTagNameChar(slice[idx])) : (idx += 1) {}
    const name_end = idx;
    if (name_start == name_end) return RenderError.InvalidMarkup;
    const tag_end = try findTagEnd(slice, idx);
    return .{
        .name = slice[name_start..name_end],
        .end = tag_end.end,
        .self_closing = tag_end.self_closing,
    };
}

fn appendOp(state: *ParseState, op: RenderOp) !void {
    try state.ops.append(state.allocator, op);
}

fn pushTag(state: *ParseState, name: []const u8) !void {
    try state.tag_stack.append(state.allocator, name);
}

fn popTag(state: *ParseState, expected: []const u8) RenderError!void {
    if (state.tag_stack.items.len == 0) return RenderError.StackUnderflow;
    const top_index = state.tag_stack.items.len - 1;
    const actual = state.tag_stack.items[top_index];
    if (!std.mem.eql(u8, actual, expected)) return RenderError.InvalidMarkup;
    state.tag_stack.items.len = top_index;
}

fn parseComment(slice: []const u8, start: usize) RenderError!struct {
    content: []const u8,
    end: usize,
} {
    var idx = start + 4; // skip "<!--"
    while (idx + 2 < slice.len) : (idx += 1) {
        if (slice[idx] == '-' and slice[idx + 1] == '-' and slice[idx + 2] == '>') {
            return .{ .content = slice[(start + 4)..idx], .end = idx + 3 };
        }
    }
    return RenderError.InvalidMarkup;
}

fn parseStaticPart(state: *ParseState, slice: []const u8) RenderError!void {
    var idx: usize = 0;
    while (idx < slice.len) {
        if (slice[idx] == '<') {
            if (idx + 3 < slice.len and std.mem.startsWith(u8, slice[idx..], "<!--")) {
                const parsed = try parseComment(slice, idx);
                const trimmed = trimWhitespace(parsed.content);
                if (trimmed.len != 0) {
                    if (std.mem.startsWith(u8, trimmed, "island:")) {
                        const name = trimWhitespace(trimmed["island:".len..]);
                        try appendOp(state, .{ .island_start = name });
                    } else if (std.mem.eql(u8, trimmed, "/island")) {
                        try appendOp(state, .{ .island_end = trimmed });
                    } else if (std.mem.startsWith(u8, trimmed, "portal:")) {
                        const target = trimWhitespace(trimmed["portal:".len..]);
                        try appendOp(state, .{ .portal_start = target });
                    } else if (std.mem.eql(u8, trimmed, "/portal")) {
                        try appendOp(state, .{ .portal_end = {} });
                    } else if (std.mem.startsWith(u8, trimmed, "suspense:")) {
                        const payload = trimWhitespace(trimmed["suspense:".len..]);
                        if (std.mem.startsWith(u8, payload, "start")) {
                            const name = trimWhitespace(payload["start".len..]);
                            try appendOp(state, .{ .suspense_start = name });
                        } else if (std.mem.startsWith(u8, payload, "fallback")) {
                            try appendOp(state, .{ .suspense_fallback = {} });
                        }
                    } else if (std.mem.eql(u8, trimmed, "/suspense")) {
                        try appendOp(state, .{ .suspense_end = {} });
                    }
                }
                idx = parsed.end;
                continue;
            }

            if (idx + 1 < slice.len and slice[idx + 1] == '/') {
                const parsed = try parseTagClose(slice, idx);
                try appendOp(state, .{ .close_element = parsed.name });
                try popTag(state, parsed.name);
                idx = parsed.end;
                continue;
            } else {
                const parsed = try parseTagOpen(slice, idx);
                if (parsed.self_closing) {
                    const op: ElementOp = .{ .tag = parsed.name, .hydration_id = state.nextHydrationId() };
                    try appendOp(state, .{ .self_element = op });
                } else {
                    const op: ElementOp = .{ .tag = parsed.name, .hydration_id = state.nextHydrationId() };
                    try appendOp(state, .{ .open_element = op });
                    try pushTag(state, parsed.name);
                }
                idx = parsed.end;
                continue;
            }
        }

        const text_start = idx;
        while (idx < slice.len and slice[idx] != '<') : (idx += 1) {}
        const text_slice = slice[text_start..idx];
        if (text_slice.len != 0) {
            try appendOp(state, .{ .text = text_slice });
        }
    }
}

pub fn buildRenderProgram(
    allocator: std.mem.Allocator,
    plan: template.TemplatePlan,
) RenderError!RenderProgram {
    var ops_list = std.ArrayListUnmanaged(RenderOp){};
    errdefer ops_list.deinit(allocator);

    var tag_stack = std.ArrayListUnmanaged([]const u8){};
    defer tag_stack.deinit(allocator);

    var hydration_counter: u32 = 1;
    var state = ParseState{
        .ops = &ops_list,
        .tag_stack = &tag_stack,
        .allocator = allocator,
        .hydration_counter = &hydration_counter,
    };

    var placeholder_index: usize = 0;
    for (plan.static_parts) |part| {
        try parseStaticPart(&state, part);
        if (placeholder_index < plan.placeholderCount()) {
            try appendOp(&state, .{ .dynamic_text = placeholder_index });
            placeholder_index += 1;
        }
    }

    if (state.tag_stack.items.len != 0) return RenderError.InvalidMarkup;

    return RenderProgram{
        .ops = try ops_list.toOwnedSlice(allocator),
        .allocator = allocator,
        .max_hydration_id = if (hydration_counter == 0) 0 else hydration_counter - 1,
    };
}

pub const MountResult = struct {
    pub const Island = struct {
        name: []u8,
        parent: u32,
        start_dynamic: usize,
        end_dynamic: usize,
    };

    pub const Portal = struct {
        target: []u8,
        node: u32,
        start_dynamic: usize,
        end_dynamic: usize,
    };

    pub const SuspenseBoundary = struct {
        name: []u8,
        main_start_dynamic: usize,
        main_end_dynamic: usize,
        fallback_start_dynamic: usize,
        fallback_end_dynamic: usize,
    };

    dynamic_nodes: []u32,
    islands: []Island,
    portals: []Portal,
    suspense: []SuspenseBoundary,
    hydration_nodes: []u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *@This()) void {
        for (self.islands) |island| {
            self.allocator.free(island.name);
        }
        self.allocator.free(self.islands);
        self.islands = &.{};
        for (self.portals) |portal| {
            self.allocator.free(portal.target);
        }
        self.allocator.free(self.portals);
        self.portals = &.{};
        for (self.suspense) |boundary| {
            self.allocator.free(boundary.name);
        }
        self.allocator.free(self.suspense);
        self.suspense = &.{};
        self.allocator.free(self.hydration_nodes);
        self.hydration_nodes = &.{};
        self.allocator.free(self.dynamic_nodes);
        self.dynamic_nodes = &.{};
    }

    pub fn nodeForHydrationId(self: @This(), hydration_id: u32) ?u32 {
        if (hydration_id >= self.hydration_nodes.len) return null;
        const node = self.hydration_nodes[hydration_id];
        return if (node == 0) null else node;
    }

    pub fn bindEvents(self: @This(), bindings: []const EventBinding) RenderError!void {
        for (bindings) |binding| {
            const node_id = self.nodeForHydrationId(binding.hydration_id) orelse return RenderError.MissingNode;
            try dom.addDelegatedEventListener(node_id, binding.event_name, binding.handler, binding.options);
        }
    }
};

pub fn mountRenderProgram(
    allocator: std.mem.Allocator,
    program: RenderProgram,
    parent: u32,
    dynamic_values: []const []const u8,
) RenderError!MountResult {
    if (dynamic_values.len != program.dynamicSlotCount()) {
        return RenderError.MismatchedValues;
    }

    var dynamic_nodes = try allocator.alloc(u32, dynamic_values.len);
    errdefer allocator.free(dynamic_nodes);

    var hydration_nodes = try allocator.alloc(u32, program.hydrationCapacity());
    errdefer allocator.free(hydration_nodes);
    @memset(hydration_nodes, 0);

    var parent_stack = std.ArrayListUnmanaged(u32){};
    defer parent_stack.deinit(allocator);

    var island_results = std.ArrayListUnmanaged(MountResult.Island){};
    errdefer {
        for (island_results.items) |island| allocator.free(island.name);
        island_results.deinit(allocator);
    }

    var portal_results = std.ArrayListUnmanaged(MountResult.Portal){};
    errdefer {
        for (portal_results.items) |portal| allocator.free(portal.target);
        portal_results.deinit(allocator);
    }

    var suspense_results = std.ArrayListUnmanaged(MountResult.SuspenseBoundary){};
    errdefer {
        for (suspense_results.items) |boundary| allocator.free(boundary.name);
        suspense_results.deinit(allocator);
    }

    const IslandFrame = struct {
        name: []u8,
        parent: u32,
        start_dynamic: usize,
    };

    var island_stack = std.ArrayListUnmanaged(IslandFrame){};
    defer {
        for (island_stack.items) |frame| allocator.free(frame.name);
        island_stack.deinit(allocator);
    }

    const PortalFrame = struct {
        target: []const u8,
        node: u32,
        previous_parent: u32,
        start_dynamic: usize,
    };

    var portal_stack = std.ArrayListUnmanaged(PortalFrame){};
    defer portal_stack.deinit(allocator);

    const SuspenseFrame = struct {
        name: []const u8,
        main_start: usize,
        main_end: usize,
        fallback_start: usize,
        has_fallback: bool,
    };

    var suspense_stack = std.ArrayListUnmanaged(SuspenseFrame){};
    defer suspense_stack.deinit(allocator);

    const attr_name = "data-hid";

    var current_parent = parent;
    var dynamic_index: usize = 0;

    for (program.ops) |op| {
        switch (op) {
            .open_element => |info| {
                const node_id = dom.hostCreateElement(info.tag);
                dom.hostAppendChild(current_parent, node_id);
                var buf: [24]u8 = undefined;
                const value = std.fmt.bufPrint(&buf, "{d}", .{info.hydration_id}) catch unreachable;
                dom.hostSetAttribute(node_id, attr_name, value);
                hydration_nodes[info.hydration_id] = node_id;
                try parent_stack.append(allocator, current_parent);
                current_parent = node_id;
            },
            .close_element => {
                if (parent_stack.items.len == 0) return RenderError.StackUnderflow;
                current_parent = parent_stack.items[parent_stack.items.len - 1];
                parent_stack.items.len -= 1;
            },
            .self_element => |info| {
                const node_id = dom.hostCreateElement(info.tag);
                dom.hostAppendChild(current_parent, node_id);
                var buf: [24]u8 = undefined;
                const value = std.fmt.bufPrint(&buf, "{d}", .{info.hydration_id}) catch unreachable;
                dom.hostSetAttribute(node_id, attr_name, value);
                hydration_nodes[info.hydration_id] = node_id;
            },
            .text => |text_value| {
                if (text_value.len == 0) continue;
                const node_id = dom.hostCreateText(text_value);
                dom.hostAppendChild(current_parent, node_id);
            },
            .dynamic_text => |slot| {
                const value = dynamic_values[slot];
                const node_id = dom.hostCreateText(value);
                dom.hostAppendChild(current_parent, node_id);
                dynamic_nodes[dynamic_index] = node_id;
                dynamic_index += 1;
            },
            .island_start => |name_slice| {
                const name_copy = try allocator.dupe(u8, name_slice);
                try island_stack.append(allocator, .{
                    .name = name_copy,
                    .parent = current_parent,
                    .start_dynamic = dynamic_index,
                });
            },
            .island_end => {
                if (island_stack.items.len == 0) return RenderError.StackUnderflow;
                const frame = island_stack.items[island_stack.items.len - 1];
                _ = island_stack.pop();
                try island_results.append(allocator, .{
                    .name = frame.name,
                    .parent = frame.parent,
                    .start_dynamic = frame.start_dynamic,
                    .end_dynamic = dynamic_index,
                });
            },
            .portal_start => |target| {
                const portal_parent = dom.hostResolvePortal(target);
                if (portal_parent == 0) return RenderError.MissingNode;
                try portal_stack.append(allocator, .{
                    .target = target,
                    .node = portal_parent,
                    .previous_parent = current_parent,
                    .start_dynamic = dynamic_index,
                });
                current_parent = portal_parent;
            },
            .portal_end => {
                if (portal_stack.items.len == 0) return RenderError.StackUnderflow;
                const frame = portal_stack.items[portal_stack.items.len - 1];
                portal_stack.items.len -= 1;
                current_parent = frame.previous_parent;
                const target_copy = try allocator.dupe(u8, frame.target);
                try portal_results.append(allocator, .{
                    .target = target_copy,
                    .node = frame.node,
                    .start_dynamic = frame.start_dynamic,
                    .end_dynamic = dynamic_index,
                });
            },
            .suspense_start => |name_slice| {
                try suspense_stack.append(allocator, .{
                    .name = name_slice,
                    .main_start = dynamic_index,
                    .main_end = dynamic_index,
                    .fallback_start = dynamic_index,
                    .has_fallback = false,
                });
            },
            .suspense_fallback => {
                if (suspense_stack.items.len == 0) return RenderError.StackUnderflow;
                var frame = &suspense_stack.items[suspense_stack.items.len - 1];
                frame.main_end = dynamic_index;
                frame.fallback_start = dynamic_index;
                frame.has_fallback = true;
            },
            .suspense_end => {
                if (suspense_stack.items.len == 0) return RenderError.StackUnderflow;
                const frame = suspense_stack.items[suspense_stack.items.len - 1];
                suspense_stack.items.len -= 1;
                const main_end = if (frame.has_fallback) frame.main_end else dynamic_index;
                const fallback_start = if (frame.has_fallback) frame.fallback_start else dynamic_index;
                const fallback_end = dynamic_index;
                const name_copy = try allocator.dupe(u8, frame.name);
                try suspense_results.append(allocator, .{
                    .name = name_copy,
                    .main_start_dynamic = frame.main_start,
                    .main_end_dynamic = main_end,
                    .fallback_start_dynamic = fallback_start,
                    .fallback_end_dynamic = fallback_end,
                });
            },
        }
    }

    if (parent_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (island_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (portal_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (suspense_stack.items.len != 0) return RenderError.InvalidMarkup;

    return MountResult{
        .dynamic_nodes = dynamic_nodes,
        .islands = try island_results.toOwnedSlice(allocator),
        .portals = try portal_results.toOwnedSlice(allocator),
        .suspense = try suspense_results.toOwnedSlice(allocator),
        .hydration_nodes = hydration_nodes,
        .allocator = allocator,
    };
}

fn parseHydrationId(value: []const u8) RenderError!u32 {
    if (value.len == 0) return RenderError.HydrationMismatch;
    const trimmed = std.mem.trim(u8, value, whitespace_chars);
    return std.fmt.parseUnsigned(u32, trimmed, 10) catch return RenderError.HydrationMismatch;
}

pub fn hydrateRenderProgram(
    allocator: std.mem.Allocator,
    program: RenderProgram,
    parent: u32,
) RenderError!MountResult {
    var dynamic_nodes = try allocator.alloc(u32, program.dynamicSlotCount());
    errdefer allocator.free(dynamic_nodes);

    var hydration_nodes = try allocator.alloc(u32, program.hydrationCapacity());
    errdefer allocator.free(hydration_nodes);
    @memset(hydration_nodes, 0);

    const ParentFrame = struct {
        const Self = @This();

        node: u32,
        next_child: ?u32,

        fn init(node_id: u32) Self {
            return .{ .node = node_id, .next_child = dom.hostFirstChild(node_id) };
        }

        fn consumeChild(self: *Self) ?u32 {
            const child = self.next_child orelse return null;
            self.next_child = dom.hostNextSibling(child);
            return child;
        }

        fn nextStructural(self: *Self) RenderError!u32 {
            while (true) {
                const node = self.consumeChild() orelse return RenderError.MissingNode;
                if (dom.hostHydrationNodeType(node) == .comment) continue;
                return node;
            }
        }

        fn consumeMarker(self: *Self, prefix: []const u8, expected: ?[]const u8) RenderError!void {
            if (self.next_child) |child| {
                if (dom.hostHydrationNodeType(child) == .comment) {
                    _ = self.consumeChild() orelse unreachable;
                    const raw = dom.hostHydrationComment(child);
                    const trimmed = std.mem.trim(u8, raw, whitespace_chars);
                    if (!std.mem.startsWith(u8, trimmed, prefix)) {
                        return RenderError.HydrationMismatch;
                    }
                    if (expected) |exp| {
                        const remainder = std.mem.trim(u8, trimmed[prefix.len..], whitespace_chars);
                        if (!std.mem.eql(u8, exp, remainder)) {
                            return RenderError.HydrationMismatch;
                        }
                    }
                }
            }
        }

        fn consumeSuspenseStart(self: *Self, name: []const u8) RenderError!void {
            if (self.next_child) |child| {
                if (dom.hostHydrationNodeType(child) == .comment) {
                    _ = self.consumeChild() orelse unreachable;
                    const raw = dom.hostHydrationComment(child);
                    const trimmed = std.mem.trim(u8, raw, whitespace_chars);
                    if (!std.mem.startsWith(u8, trimmed, "suspense:")) {
                        return RenderError.HydrationMismatch;
                    }
                    const payload = std.mem.trim(u8, trimmed["suspense:".len..], whitespace_chars);
                    if (!std.mem.startsWith(u8, payload, "start")) {
                        return RenderError.HydrationMismatch;
                    }
                    const name_part = std.mem.trim(u8, payload["start".len..], whitespace_chars);
                    if (!std.mem.eql(u8, name, name_part)) {
                        return RenderError.HydrationMismatch;
                    }
                    return;
                }
            }
            return RenderError.HydrationMismatch;
        }
    };

    var parent_stack = std.ArrayListUnmanaged(ParentFrame){};
    defer parent_stack.deinit(allocator);
    try parent_stack.append(allocator, ParentFrame.init(parent));

    var island_results = std.ArrayListUnmanaged(MountResult.Island){};
    errdefer {
        for (island_results.items) |island| allocator.free(island.name);
        island_results.deinit(allocator);
    }

    var portal_results = std.ArrayListUnmanaged(MountResult.Portal){};
    errdefer {
        for (portal_results.items) |portal| allocator.free(portal.target);
        portal_results.deinit(allocator);
    }

    var suspense_results = std.ArrayListUnmanaged(MountResult.SuspenseBoundary){};
    errdefer {
        for (suspense_results.items) |boundary| allocator.free(boundary.name);
        suspense_results.deinit(allocator);
    }

    const IslandFrame = struct {
        name: []u8,
        parent: u32,
        start_dynamic: usize,
    };

    var island_stack = std.ArrayListUnmanaged(IslandFrame){};
    defer {
        for (island_stack.items) |frame| allocator.free(frame.name);
        island_stack.deinit(allocator);
    }

    const PortalFrame = struct {
        target: []const u8,
        node: u32,
        start_dynamic: usize,
        parent_index: usize,
    };

    var portal_stack = std.ArrayListUnmanaged(PortalFrame){};
    defer portal_stack.deinit(allocator);

    const SuspenseFrame = struct {
        name: []const u8,
        main_start: usize,
        main_end: usize,
        fallback_start: usize,
        has_fallback: bool,
    };

    var suspense_stack = std.ArrayListUnmanaged(SuspenseFrame){};
    defer suspense_stack.deinit(allocator);

    var dynamic_index: usize = 0;
    const attr_name = "data-hid";

    for (program.ops) |op| {
        var current_parent = &parent_stack.items[parent_stack.items.len - 1];
        switch (op) {
            .open_element => |info| {
                const node_id = try current_parent.nextStructural();
                if (dom.hostHydrationNodeType(node_id) != .element) return RenderError.UnexpectedNode;
                const tag = dom.hostHydrationTag(node_id);
                if (!std.mem.eql(u8, tag, info.tag)) return RenderError.HydrationMismatch;
                const attr = dom.hostHydrationAttribute(node_id, attr_name) orelse return RenderError.HydrationMismatch;
                const hid = try parseHydrationId(attr);
                if (hid != info.hydration_id) return RenderError.HydrationMismatch;
                hydration_nodes[info.hydration_id] = node_id;
                try parent_stack.append(allocator, ParentFrame.init(node_id));
            },
            .close_element => |expected_tag| {
                if (parent_stack.items.len <= 1) return RenderError.StackUnderflow;
                const frame_index = parent_stack.items.len - 1;
                const frame_node = parent_stack.items[frame_index].node;
                const tag = dom.hostHydrationTag(frame_node);
                if (!std.mem.eql(u8, tag, expected_tag)) return RenderError.HydrationMismatch;
                parent_stack.items.len = frame_index;
            },
            .self_element => |info| {
                const node_id = try current_parent.nextStructural();
                if (dom.hostHydrationNodeType(node_id) != .element) return RenderError.UnexpectedNode;
                const tag = dom.hostHydrationTag(node_id);
                if (!std.mem.eql(u8, tag, info.tag)) return RenderError.HydrationMismatch;
                const attr = dom.hostHydrationAttribute(node_id, attr_name) orelse return RenderError.HydrationMismatch;
                const hid = try parseHydrationId(attr);
                if (hid != info.hydration_id) return RenderError.HydrationMismatch;
                hydration_nodes[info.hydration_id] = node_id;
            },
            .text => |text_value| {
                const node_id = try current_parent.nextStructural();
                if (dom.hostHydrationNodeType(node_id) != .text) return RenderError.UnexpectedNode;
                const actual = dom.hostHydrationText(node_id);
                if (!std.mem.eql(u8, actual, text_value)) return RenderError.HydrationMismatch;
            },
            .dynamic_text => {
                if (dynamic_index >= dynamic_nodes.len) return RenderError.HydrationMismatch;
                const node_id = try current_parent.nextStructural();
                if (dom.hostHydrationNodeType(node_id) != .text) return RenderError.UnexpectedNode;
                dynamic_nodes[dynamic_index] = node_id;
                dynamic_index += 1;
            },
            .island_start => |name_slice| {
                try current_parent.consumeMarker("island:", name_slice);
                const name_copy = try allocator.dupe(u8, name_slice);
                try island_stack.append(allocator, .{
                    .name = name_copy,
                    .parent = current_parent.node,
                    .start_dynamic = dynamic_index,
                });
            },
            .island_end => {
                try current_parent.consumeMarker("/island", null);
                if (island_stack.items.len == 0) return RenderError.StackUnderflow;
                const idx = island_stack.items.len - 1;
                const frame = island_stack.items[idx];
                island_stack.items.len = idx;
                try island_results.append(allocator, .{
                    .name = frame.name,
                    .parent = frame.parent,
                    .start_dynamic = frame.start_dynamic,
                    .end_dynamic = dynamic_index,
                });
            },
            .portal_start => |target| {
                try current_parent.consumeMarker("portal:", target);
                const portal_parent = dom.hostResolvePortal(target);
                if (portal_parent == 0) return RenderError.MissingNode;
                const parent_index = parent_stack.items.len - 1;
                try parent_stack.append(allocator, ParentFrame.init(portal_parent));
                try portal_stack.append(allocator, .{
                    .target = target,
                    .node = portal_parent,
                    .start_dynamic = dynamic_index,
                    .parent_index = parent_index,
                });
            },
            .portal_end => {
                if (portal_stack.items.len == 0) return RenderError.StackUnderflow;
                const frame = portal_stack.items[portal_stack.items.len - 1];
                portal_stack.items.len -= 1;
                if (parent_stack.items.len <= frame.parent_index + 1) return RenderError.InvalidMarkup;
                parent_stack.items.len -= 1; // remove portal frame
                var root_frame = &parent_stack.items[frame.parent_index];
                try root_frame.consumeMarker("/portal", null);
                const target_copy = try allocator.dupe(u8, frame.target);
                try portal_results.append(allocator, .{
                    .target = target_copy,
                    .node = frame.node,
                    .start_dynamic = frame.start_dynamic,
                    .end_dynamic = dynamic_index,
                });
            },
            .suspense_start => |name_slice| {
                try current_parent.consumeSuspenseStart(name_slice);
                try suspense_stack.append(allocator, .{
                    .name = name_slice,
                    .main_start = dynamic_index,
                    .main_end = dynamic_index,
                    .fallback_start = dynamic_index,
                    .has_fallback = false,
                });
            },
            .suspense_fallback => {
                try current_parent.consumeMarker("suspense:", "fallback");
                if (suspense_stack.items.len == 0) return RenderError.StackUnderflow;
                var frame = &suspense_stack.items[suspense_stack.items.len - 1];
                frame.main_end = dynamic_index;
                frame.fallback_start = dynamic_index;
                frame.has_fallback = true;
            },
            .suspense_end => {
                try current_parent.consumeMarker("/suspense", null);
                if (suspense_stack.items.len == 0) return RenderError.StackUnderflow;
                const frame = suspense_stack.items[suspense_stack.items.len - 1];
                suspense_stack.items.len -= 1;
                const main_end = if (frame.has_fallback) frame.main_end else dynamic_index;
                const fallback_start = if (frame.has_fallback) frame.fallback_start else dynamic_index;
                const fallback_end = dynamic_index;
                const name_copy = try allocator.dupe(u8, frame.name);
                try suspense_results.append(allocator, .{
                    .name = name_copy,
                    .main_start_dynamic = frame.main_start,
                    .main_end_dynamic = main_end,
                    .fallback_start_dynamic = fallback_start,
                    .fallback_end_dynamic = fallback_end,
                });
            },
        }
    }

    if (parent_stack.items.len != 1) return RenderError.InvalidMarkup;
    if (island_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (portal_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (suspense_stack.items.len != 0) return RenderError.InvalidMarkup;
    if (dynamic_index != dynamic_nodes.len) return RenderError.HydrationMismatch;

    return MountResult{
        .dynamic_nodes = dynamic_nodes,
        .islands = try island_results.toOwnedSlice(allocator),
        .portals = try portal_results.toOwnedSlice(allocator),
        .suspense = try suspense_results.toOwnedSlice(allocator),
        .hydration_nodes = hydration_nodes,
        .allocator = allocator,
    };
}
