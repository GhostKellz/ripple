const std = @import("std");
const builtin = @import("builtin");

const is_wasm = builtin.target.cpu.arch.isWasm();

/// ScrollPosition stores the viewport scroll offsets for restoration.
pub const ScrollPosition = struct {
    x: i32 = 0,
    y: i32 = 0,
};

/// HistoryManager tracks route visits and associated scroll positions.
pub const HistoryManager = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(ScrollPosition),
    current_scroll: ScrollPosition = .{},

    pub fn init(allocator: std.mem.Allocator) HistoryManager {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(ScrollPosition).init(allocator),
            .current_scroll = .{},
        };
    }

    pub fn deinit(self: *HistoryManager) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
        }
        self.entries.deinit();
    }

    /// Returns the last known scroll position for the active document.
    pub fn currentScroll(self: HistoryManager) ScrollPosition {
        return self.current_scroll;
    }

    /// Updates the in-memory scroll cache. Hosts should call this whenever the
    /// viewport scroll changes (e.g. from `scroll` events).
    pub fn updateScroll(self: *HistoryManager, position: ScrollPosition) void {
        self.current_scroll = position;
    }

    /// Reads the scroll offsets from the runtime host when available (WASM).
    pub fn refreshFromHost(self: *HistoryManager) void {
        if (!is_wasm) return;
        var x: i32 = 0;
        var y: i32 = 0;
        Host.ripple_router_get_scroll(&x, &y);
        self.current_scroll = .{ .x = x, .y = y };
    }

    /// Persists the current scroll position for the provided path.
    pub fn captureCurrent(self: *HistoryManager, path: []const u8) !void {
        self.refreshFromHost();
        try self.store(path, self.current_scroll);
    }

    fn store(self: *HistoryManager, path: []const u8, position: ScrollPosition) !void {
        if (self.entries.getEntry(path)) |entry| {
            entry.value_ptr.* = position;
            return;
        }

        const dup = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(dup);
        try self.entries.put(dup, position);
    }

    /// Fetches the stored scroll position for a path. Defaults to the top.
    pub fn lookup(self: *HistoryManager, path: []const u8) ScrollPosition {
        if (self.entries.get(path)) |position| return position;
        return .{};
    }

    /// Applies the stored scroll position to the runtime host (or cache).
    pub fn applyScroll(self: *HistoryManager, position: ScrollPosition) void {
        if (is_wasm) {
            Host.ripple_router_set_scroll(position.x, position.y);
        }
        self.current_scroll = position;
    }

    /// Restores the scroll position for a path, falling back to the top.
    pub fn restoreForPath(self: *HistoryManager, path: []const u8) void {
        const position = self.lookup(path);
        self.applyScroll(position);
    }

    /// Removes all stored scroll entries. Useful for hot reload scenarios.
    pub fn clear(self: *HistoryManager) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
        }
        self.entries.clearRetainingCapacity();
    }
};

const Host = if (is_wasm) struct {
    extern "env" fn ripple_router_get_scroll(x: *i32, y: *i32) void;
    extern "env" fn ripple_router_set_scroll(x: i32, y: i32) void;
} else struct {};

const testing = std.testing;

test "history captures and restores scroll positions" {
    var history = HistoryManager.init(testing.allocator);
    defer history.deinit();

    history.updateScroll(.{ .x = 0, .y = 120 });
    try history.captureCurrent("/");
    history.updateScroll(.{ .x = 0, .y = 0 });

    history.restoreForPath("/");

    const restored = history.currentScroll();
    try testing.expectEqual(@as(i32, 0), restored.x);
    try testing.expectEqual(@as(i32, 120), restored.y);
}

test "history defaults to top when path unseen" {
    var history = HistoryManager.init(testing.allocator);
    defer history.deinit();

    history.updateScroll(.{ .x = 3, .y = 4 });
    history.restoreForPath("/missing");

    const restored = history.currentScroll();
    try testing.expectEqual(@as(i32, 0), restored.x);
    try testing.expectEqual(@as(i32, 0), restored.y);
}
