const std = @import("std");

pub const Entry = struct {
    /// Route path in router syntax (e.g. "/blog/:id").
    route_path: []u8,
    /// Relative file path from the routes root (e.g. "blog/[id].zig").
    file_path: []u8,
};

pub const Manifest = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,

    pub fn deinit(self: *Manifest) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.route_path);
            self.allocator.free(entry.file_path);
        }
        self.allocator.free(self.entries);
        self.entries = &.{};
    }
};

pub const Options = struct {
    /// Optional list of file extensions to include. Defaults to `.zig` only.
    extensions: []const []const u8 = &.{".zig"},
    /// Optional predicate to skip files. When provided, returning true will skip.
    skipFile: ?*const fn ([]const u8) bool = null,
};

pub fn generateManifest(
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    options: Options,
) !Manifest {
    var entries = std.ArrayListUnmanaged(Entry){};
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.route_path);
            allocator.free(entry.file_path);
        }
        entries.deinit(allocator);
    }

    try walkDirectory(allocator, root_dir, "", options, &entries);

    std.sort.block(Entry, entries.items, {}, struct {
        fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, lhs.route_path, rhs.route_path);
        }
    }.lessThan);

    return Manifest{
        .allocator = allocator,
        .entries = try entries.toOwnedSlice(allocator),
    };
}

fn walkDirectory(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    current_rel: []const u8,
    options: Options,
    entries: *std.ArrayListUnmanaged(Entry),
) !void {
    var it = dir.iterate();
    while (try it.next()) |item| {
        if (item.kind == .directory) {
            const sub_rel = try joinPath(allocator, current_rel, item.name);
            defer allocator.free(sub_rel);

            var child_dir = try dir.openDir(item.name, .{ .iterate = true });
            defer child_dir.close();

            try walkDirectory(allocator, child_dir, sub_rel, options, entries);
            continue;
        }

        if (item.kind != .file) continue;
        if (!hasAllowedExtension(item.name, options.extensions)) continue;
        if (options.skipFile) |skip_fn| {
            if (skip_fn(item.name)) continue;
        }

        const route_path = try buildRoutePath(allocator, current_rel, item.name);
        if (route_path.len == 0) continue;

        const file_rel = try relativeFilePath(allocator, current_rel, item.name);

        try entries.append(allocator, .{
            .route_path = route_path,
            .file_path = file_rel,
        });
    }
}

fn hasAllowedExtension(name: []const u8, extensions: []const []const u8) bool {
    for (extensions) |ext| {
        if (std.mem.endsWith(u8, name, ext)) return true;
    }
    return false;
}

fn joinPath(allocator: std.mem.Allocator, base: []const u8, segment: []const u8) ![]u8 {
    if (base.len == 0) return allocator.dupe(u8, segment);
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    try list.appendSlice(base);
    try list.append('/');
    try list.appendSlice(segment);
    return list.toOwnedSlice();
}

fn relativeFilePath(allocator: std.mem.Allocator, rel_dir: []const u8, name: []const u8) ![]u8 {
    if (rel_dir.len == 0) return allocator.dupe(u8, name);
    return joinPath(allocator, rel_dir, name);
}

fn buildRoutePath(
    allocator: std.mem.Allocator,
    rel_dir: []const u8,
    file_name: []const u8,
) ![]u8 {
    const segment = segmentFromFileName(file_name) orelse return &.{};

    var builder = std.ArrayList(u8).init(allocator);
    defer builder.deinit();

    var wrote_segment = false;

    if (rel_dir.len != 0) {
        var splitter = std.mem.splitScalar(u8, rel_dir, '/');
        while (splitter.next()) |part| {
            if (part.len == 0) continue;
            if (wrote_segment) try builder.append('/');
            if (!wrote_segment) {
                try builder.append('/');
                wrote_segment = true;
            }
            try writeSegment(&builder, part);
        }
    }

    if (segment.len != 0) {
        if (wrote_segment) try builder.append('/');
        if (!wrote_segment) {
            try builder.append('/');
            wrote_segment = true;
        }
        try writeSegment(&builder, segment);
    }

    if (!wrote_segment) {
        try builder.append('/');
    }

    return builder.toOwnedSlice();
}

fn segmentFromFileName(name: []const u8) ?[]const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    const base = name[0..dot];
    if (std.mem.eql(u8, base, "index")) return "";
    return base;
}

fn writeSegment(builder: *std.ArrayList(u8), name: []const u8) !void {
    const len = name.len;
    if (len >= 5 and name[0] == '[' and name[1] == '.' and name[2] == '.' and name[3] == '.' and name[len - 1] == ']') {
        try builder.append('*');
        try builder.appendSlice(name[4..(len - 1)]);
        return;
    }

    if (len >= 2 and name[0] == '[' and name[len - 1] == ']') {
        try builder.append(':');
        try builder.appendSlice(name[1..(len - 1)]);
        return;
    }

    try builder.appendSlice(name);
}

const testing = std.testing;

test "generate manifest from nested routes" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var root = tmp.dir;
    try root.makeDir("routes");
    var routes_dir = try root.openDir("routes", .{ .iterate = true });
    defer routes_dir.close();

    try writeFile(routes_dir, "index.zig");
    try writeFile(routes_dir, "about.zig");
    try routes_dir.makeDir("blog");
    var blog_dir = try routes_dir.openDir("blog", .{ .iterate = true });
    defer blog_dir.close();
    try writeFile(blog_dir, "index.zig");
    try writeFile(blog_dir, "[id].zig");

    var manifest = try generateManifest(testing.allocator, routes_dir, .{});
    defer manifest.deinit();

    try testing.expectEqual(@as(usize, 4), manifest.entries.len);

    try testing.expectStringsEqual("/", manifest.entries[0].route_path);
    try testing.expectStringsEqual("index.zig", manifest.entries[0].file_path);

    try testing.expectStringsEqual("/about", manifest.entries[1].route_path);
    try testing.expectStringsEqual("about.zig", manifest.entries[1].file_path);

    try testing.expectStringsEqual("/blog", manifest.entries[2].route_path);
    try testing.expectStringsEqual("blog/index.zig", manifest.entries[2].file_path);

    try testing.expectStringsEqual("/blog/:id", manifest.entries[3].route_path);
    try testing.expectStringsEqual("blog/[id].zig", manifest.entries[3].file_path);
}

fn writeFile(dir: std.fs.Dir, name: []const u8) !void {
    var file = try dir.createFile(name, .{});
    defer file.close();
    try file.writeAll("// route placeholder\n");
}
