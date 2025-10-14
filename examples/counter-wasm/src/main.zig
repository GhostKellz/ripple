const std = @import("std");
const ripple = @import("ripple");

// Global allocator for WASM - use FixedBufferAllocator for freestanding
var memory_buffer: [1024 * 1024]u8 = undefined; // 1MB buffer
var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
const allocator = fba.allocator();

// Counter state
var counter_signal: ?ripple.SignalPair(i32) = null;
var counter_effect: ?ripple.EffectHandle = null;

/// Initialize the counter application
export fn init() void {
    // Create counter signal starting at 0
    counter_signal = ripple.createSignal(i32, allocator, 0) catch {
        return;
    };

    // Create effect to update DOM
    const Context = struct {
        read: ripple.ReadSignal(i32),
    };
    var ctx = Context{ .read = counter_signal.?.read };

    counter_effect = ripple.createEffect(allocator, struct {
        fn updateDisplay(effect_ctx: *ripple.EffectContext) anyerror!void {
            const data = effect_ctx.userData(Context).?;
            const value = try data.read.get();

            // Format the count as a string
            var buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{}", .{value}) catch "error";

            // Update DOM via host callback
            updateCountDisplay(text.ptr, text.len);
        }
    }.updateDisplay, &ctx) catch {
        return;
    };
}

/// Increment the counter
export fn increment() void {
    if (counter_signal) |*signal| {
        const current = signal.read.get() catch 0;
        signal.write.set(current + 1) catch {};
    }
}

/// Decrement the counter
export fn decrement() void {
    if (counter_signal) |*signal| {
        const current = signal.read.get() catch 0;
        signal.write.set(current - 1) catch {};
    }
}

/// Reset the counter
export fn reset() void {
    if (counter_signal) |*signal| {
        signal.write.set(0) catch {};
    }
}

/// Cleanup resources
export fn deinit() void {
    if (counter_effect) |*effect| {
        effect.dispose();
    }
    if (counter_signal) |*signal| {
        signal.dispose();
    }
    // FixedBufferAllocator doesn't need deinit
}

// Host callback (imported from JavaScript)
extern "env" fn updateCountDisplay(ptr: [*]const u8, len: usize) void;

// Provide panic handler for WASM
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    @trap();
}
