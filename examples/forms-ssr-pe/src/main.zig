const std = @import("std");
const ripple = @import("ripple");
const zsync = @import("zsync");

const AsyncUsernameRule = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(Pending),

    const Pending = struct {
        future: *zsync.Future(ripple.FormValidationOutcome),
        value: []u8,
    };

    fn create(allocator: std.mem.Allocator) !*@This() {
        const ctx = try allocator.create(@This());
        ctx.* = .{
            .allocator = allocator,
            .pending = std.ArrayList(Pending).init(allocator),
        };
        return ctx;
    }

    fn destroy(self: *@This()) void {
        while (self.pending.popOrNull()) |entry| {
            entry.future.cancel();
            entry.future.deinit();
            self.allocator.free(entry.value);
        }
        self.pending.deinit();
        self.allocator.destroy(self);
    }

    fn flush(self: *@This()) void {
        while (self.pending.popOrNull()) |entry| {
            const taken = std.mem.eql(u8, entry.value, "taken");
            const outcome = ripple.FormValidationOutcome{
                .valid = !taken,
                .message = if (taken) "Username already taken" else null,
            };
            entry.future.resolve(outcome);
            self.allocator.free(entry.value);
        }
    }

    fn validate(_: []const u8, value: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ripple.FormValidationResult {
        const ctx = @as(*AsyncUsernameRule, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
        if (value.len == 0) {
            return .{ .immediate = ripple.FormValidationOutcome{} };
        }

        const future = try zsync.Future(ripple.FormValidationOutcome).init(ctx.allocator);
        const copy = try ctx.allocator.dupe(u8, value);
        errdefer ctx.allocator.free(copy);

        try ctx.pending.append(.{ .future = future, .value = copy });
        return .{ .future = ripple.FormAsyncValidation{ .future = future } };
    }

    fn deinitContext(_: std.mem.Allocator, ctx_ptr: ?*anyopaque) void {
        if (ctx_ptr) |ptr| {
            const ctx = @as(*AsyncUsernameRule, @ptrFromInt(@intFromPtr(ptr)));
            ctx.destroy();
        }
    }
};

const FocusPrinter = struct {
    fn run(name: []const u8, _: ?*anyopaque) anyerror!void {
        std.debug.print("  -> focus {s}\n", .{ name });
    }
};

fn printSummary(allocator: std.mem.Allocator, store: *ripple.FormStore, label: []const u8) !void {
    var summary = try store.collectErrorSummary(allocator);
    defer summary.deinit();

    std.debug.print("[{s}]\n", .{ label });
    if (summary.len() == 0) {
        std.debug.print("  ✓ no validation errors\n", .{});
        return;
    }

    var index: usize = 0;
    for (summary.values()) |item| {
        index += 1;
        const message = if (item.message.len == 0) "Pending server response" else item.message;
        std.debug.print("  {d}. {s}: {s}\n", .{ index, item.field, message });
    }
}

fn printAriaInvalid(signal: ripple.ReadSignal([]const u8), field: []const u8) !void {
    const value = try signal.get();
    std.debug.print("  aria-invalid[{s}] = {s}\n", .{ field, value });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var username_ctx = try AsyncUsernameRule.create(allocator);
    var username_ctx_cleanup = true;
    defer if (username_ctx_cleanup) username_ctx.destroy();

    const schema = ripple.FormSchemaValidationConfig{
        .fields = &.{
            .{
                .field = "email",
                .rules = &.{ ripple.FormSchemaRule{ .email = .{ .message = "Enter a valid email" } } },
            },
            .{
                .field = "password",
                .rules = &.{
                    ripple.FormSchemaRule{ .minLength = .{ .min = 6, .message = "Password too short" } },
                    ripple.FormSchemaRule{ .maxLength = .{ .max = 64 } },
                },
            },
            .{ .field = "confirm", .rules = &.{} },
            .{
                .field = "username",
                .rules = &.{ ripple.FormSchemaRule{ .custom = .{
                    .validate = AsyncUsernameRule.validate,
                    .context = @as(?*anyopaque, @ptrCast(username_ctx)),
                    .deinitContext = AsyncUsernameRule.deinitContext,
                } } },
            },
        },
        .cross_fields = &.{
            ripple.FormSchemaCrossFieldRule{ .matchField = .{
                .field = "confirm",
                .other_field = "password",
                .message = "Passwords must match",
            } },
        },
    };

    var store = try ripple.FormStore.init(allocator, .{ .schema = schema });
    defer store.deinit();
    username_ctx_cleanup = false;

    try store.registerField(.{ .name = "email", .initial = "" });
    try store.registerField(.{ .name = "password", .initial = "" });
    try store.registerField(.{ .name = "confirm", .initial = "" });
    try store.registerField(.{ .name = "username", .initial = "" });

    const email_view = store.fieldView("email") orelse unreachable;
    var email_aria = try ripple.bindAriaInvalid(allocator, email_view);
    defer email_aria.deinit();

    std.debug.print("== Initial SSR render ==\n", .{});
    try printSummary(allocator, &store, "Initial summary");
    try printAriaInvalid(email_aria.value, "email");

    std.debug.print("\n== Simulate invalid submission ==\n", .{});
    try store.setValue("email", "invalid");
    try store.setValue("password", "123");
    try store.setValue("confirm", "456");
    try store.setValue("username", "taken");
    try store.tickAsyncValidations();

    try printSummary(allocator, &store, "Before async response");
    try printAriaInvalid(email_aria.value, "email");
    _ = try store.focusFirstInvalidField(FocusPrinter.run, null);

    username_ctx.flush();
    try store.tickAsyncValidations();

    try printSummary(allocator, &store, "After async response");

    std.debug.print("\n== Apply fixes ==\n", .{});
    try store.setValue("email", "user@example.com");
    try store.setValue("password", "topsecret");
    try store.setValue("confirm", "topsecret");
    try store.setValue("username", "available");
    try store.tickAsyncValidations();

    username_ctx.flush();
    try store.tickAsyncValidations();

    try printSummary(allocator, &store, "Ready to submit");
    try printAriaInvalid(email_aria.value, "email");
    const focused = try store.focusFirstInvalidField(FocusPrinter.run, null);
    std.debug.print("  -> focus needed? {s}\n", .{ if (focused) "yes" else "no" });
}
