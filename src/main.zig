const std = @import("std");
const ripple = @import("ripple");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var counter = try ripple.createSignal(i32, allocator, 0);
    defer counter.dispose();

    const EffectData = struct {
        read: ripple.ReadSignal(i32),
    };
    var data = EffectData{ .read = counter.read };

    var effect = try ripple.createEffect(allocator, struct {
        fn run(ctx: *ripple.EffectContext) anyerror!void {
            const payload = ctx.userData(EffectData).?;
            const value = try payload.read.get();
            std.debug.print("count = {}\n", .{value});
        }
    }.run, &data);
    defer effect.dispose();

    try counter.write.set(1);
    try counter.write.set(2);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
