const std = @import("std");

pub const EffectCallback = *const fn (*EffectContext) anyerror!void;

threadlocal var current_effect: ?*EffectContext = null;

const scheduler_allocator = std.heap.page_allocator;

const ContextEntry = struct {
    key: u64,
    ptr: *anyopaque,
};

threadlocal var context_stack = std.ArrayListUnmanaged(ContextEntry){};

fn contextKey(comptime T: type) u64 {
    const name = @typeName(T);
    return std.hash.Wyhash.hash(0, name);
}

fn contextAllocator() std.mem.Allocator {
    return scheduler_allocator;
}

const ErrorBoundaryState = struct {
    handler: *const fn (anyerror) void,
    prev: ?*ErrorBoundaryState,
};

threadlocal var error_boundary_head: ?*ErrorBoundaryState = null;

const Scheduler = struct {
    queue: std.ArrayListUnmanaged(*EffectContext) = .{},
    depth: usize = 0,
    is_flushing: bool = false,

    fn begin(self: *Scheduler) void {
        self.depth += 1;
    }

    fn end(self: *Scheduler) !void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
        if (self.depth == 0) try self.flush();
    }

    fn abort(self: *Scheduler) void {
        if (self.depth > 0) self.depth -= 1;
        if (self.depth == 0 and !self.is_flushing) {
            self.queue.items.len = 0;
        }
    }

    fn enqueue(self: *Scheduler, effect: *EffectContext) !void {
        if (effect.disposed) return;
        for (self.queue.items) |existing| {
            if (existing == effect) return;
        }
        try self.queue.append(scheduler_allocator, effect);
    }

    fn flushIfIdle(self: *Scheduler) !void {
        if (self.depth == 0 and !self.is_flushing) try self.flush();
    }

    fn flush(self: *Scheduler) !void {
        if (self.is_flushing or self.depth != 0) return;
        self.is_flushing = true;
        defer self.is_flushing = false;

        var index: usize = 0;
        while (index < self.queue.items.len) : (index += 1) {
            const effect = self.queue.items[index];
            if (!effect.disposed) {
                try effect.trigger();
            }
        }
        self.queue.items.len = 0;
    }

    fn remove(self: *Scheduler, effect: *EffectContext) void {
        var idx: usize = 0;
        while (idx < self.queue.items.len) {
            if (self.queue.items[idx] == effect) {
                _ = self.queue.swapRemove(idx);
            } else {
                idx += 1;
            }
        }
    }
};

threadlocal var scheduler_state = Scheduler{};

fn getScheduler() *Scheduler {
    return &scheduler_state;
}

pub const BatchGuard = struct {
    scheduler: *Scheduler,
    active: bool = true,

    pub fn commit(self: *@This()) !void {
        if (!self.active) return;
        self.active = false;
        try self.scheduler.end();
    }

    pub fn abort(self: *@This()) void {
        if (!self.active) return;
        self.active = false;
        self.scheduler.abort();
    }

    pub fn deinit(self: *@This()) void {
        self.abort();
    }
};

pub fn beginBatch() BatchGuard {
    const scheduler = getScheduler();
    scheduler.begin();
    return .{ .scheduler = scheduler };
}

pub fn batch(function: anytype) !void {
    const info = @typeInfo(@TypeOf(function));
    comptime {
        if (info != .Fn or info.Fn.params.len != 0) {
            @compileError("batch expects a zero-argument function");
        }
    }

    var guard = beginBatch();
    errdefer guard.abort();

    const RetType = info.Fn.return_type orelse void;
    const ret_info = @typeInfo(RetType);
    comptime switch (ret_info) {
        .ErrorUnion => {},
        .Void => {},
        .NoReturn => {},
        else => @compileError("batch expects a function that returns void or !void"),
    };

    switch (ret_info) {
        .ErrorUnion => _ = try function(),
        .Void => function(),
        .NoReturn => function(),
        else => unreachable,
    }

    try guard.commit();
}

pub fn flushPending() !void {
    try getScheduler().flush();
}

fn dispatchEffectError(err: anyerror) bool {
    const node = error_boundary_head;
    if (node) |ctx| {
        ctx.handler(err);
        return true;
    }
    return false;
}

pub const ErrorBoundaryToken = struct {
    state: *ErrorBoundaryState,
};

pub const ErrorBoundaryGuard = struct {
    token: ErrorBoundaryToken,
    active: bool = true,

    pub fn deinit(self: *@This()) void {
        if (!self.active) return;
        popErrorBoundary(self.token);
        self.active = false;
    }
};

pub fn pushErrorBoundary(handler: *const fn (anyerror) void) !ErrorBoundaryToken {
    const state = try scheduler_allocator.create(ErrorBoundaryState);
    state.* = .{ .handler = handler, .prev = error_boundary_head };
    error_boundary_head = state;
    return .{ .state = state };
}

pub fn popErrorBoundary(token: ErrorBoundaryToken) void {
    error_boundary_head = token.state.prev;
    scheduler_allocator.destroy(token.state);
}

pub fn beginErrorBoundary(handler: *const fn (anyerror) void) !ErrorBoundaryGuard {
    return .{ .token = try pushErrorBoundary(handler) };
}

pub const SchedulerSnapshot = struct {
    queued: usize,
    depth: usize,
    is_flushing: bool,
};

pub fn snapshotScheduler() SchedulerSnapshot {
    const scheduler = getScheduler();
    return .{
        .queued = scheduler.queue.items.len,
        .depth = scheduler.depth,
        .is_flushing = scheduler.is_flushing,
    };
}

pub fn hasPendingWork() bool {
    const scheduler = getScheduler();
    return scheduler.queue.items.len != 0;
}

pub const ContextGuard = struct {
    index: usize,
    active: bool = true,

    pub fn release(self: *@This()) void {
        if (!self.active) return;
        std.debug.assert(context_stack.items.len != 0);
        std.debug.assert(self.index == context_stack.items.len - 1);
        context_stack.items.len -= 1;
        self.active = false;
    }
};

pub const ContextValueGuard = struct {
    guard: ContextGuard,
    allocator: std.mem.Allocator,
    ptr: *anyopaque,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,
    active: bool = true,

    pub fn release(self: *@This()) void {
        if (!self.active) return;
        self.guard.release();
        self.destroy_fn(self.allocator, self.ptr);
        self.active = false;
    }
};

pub fn pushContext(comptime T: type, ptr: *T) !ContextGuard {
    const entry = ContextEntry{ .key = contextKey(T), .ptr = ptr };
    try context_stack.append(contextAllocator(), entry);
    return .{ .index = context_stack.items.len - 1 };
}

pub fn withContext(comptime T: type, allocator: std.mem.Allocator, value: T) !ContextValueGuard {
    const ptr = try allocator.create(T);
    ptr.* = value;
    const guard = try pushContext(T, ptr);
    const Destroyer = struct {
        fn destroy(alloc: std.mem.Allocator, opaque_ptr: *anyopaque) void {
            const typed = @as(*T, @ptrFromInt(@intFromPtr(opaque_ptr)));
            alloc.destroy(typed);
        }
    };
    return .{
        .guard = guard,
        .allocator = allocator,
        .ptr = ptr,
        .destroy_fn = Destroyer.destroy,
    };
}

pub fn useContext(comptime T: type) ?*T {
    const key = contextKey(T);
    var i = context_stack.items.len;
    while (i > 0) {
        i -= 1;
        const entry = context_stack.items[i];
        if (entry.key == key) {
            return @as(*T, @ptrFromInt(@intFromPtr(entry.ptr)));
        }
    }
    return null;
}

const Subscription = struct {
    context_addr: usize,
    remove_fn: *const fn (usize, *EffectContext) void,
};

const SignalSubscriptionList = std.ArrayListUnmanaged(*EffectContext);

pub const EffectContext = struct {
    allocator: std.mem.Allocator,
    callback: EffectCallback,
    user_data_addr: ?usize,
    subscriptions: std.ArrayListUnmanaged(Subscription) = .{},
    is_running: bool = false,
    needs_rerun: bool = false,
    disposed: bool = false,

    pub fn setUserData(self: *EffectContext, ptr: ?*anyopaque) void {
        self.user_data_addr = if (ptr) |p| @intFromPtr(p) else null;
    }

    pub fn userData(self: *EffectContext, comptime T: type) ?*T {
        return if (self.user_data_addr) |addr| @as(?*T, @ptrFromInt(addr)) else null;
    }

    fn addSubscription(self: *EffectContext, sub: Subscription) !void {
        if (self.disposed) return;
        for (self.subscriptions.items) |existing| {
            if (existing.context_addr == sub.context_addr and existing.remove_fn == sub.remove_fn) {
                return;
            }
        }
        try self.subscriptions.append(self.allocator, sub);
    }

    fn unsubscribeAll(self: *EffectContext) void {
        for (self.subscriptions.items) |sub| {
            sub.remove_fn(sub.context_addr, self);
        }
        self.subscriptions.clearRetainingCapacity();
    }

    fn runOnce(self: *EffectContext) !void {
        if (self.disposed) return;
        self.unsubscribeAll();
        self.is_running = true;
        defer self.is_running = false;

        const prev = current_effect;
        current_effect = self;
        defer current_effect = prev;

        if (self.callback(self)) |_| {} else |err| {
            if (!dispatchEffectError(err)) {
                return err;
            }
        }
    }

    fn runLoop(self: *EffectContext) !void {
        if (self.disposed) return;
        self.needs_rerun = false;
        while (true) {
            try self.runOnce();
            if (!self.needs_rerun or self.disposed) break;
            self.needs_rerun = false;
        }
    }

    fn trigger(self: *EffectContext) !void {
        if (self.disposed) return;
        if (self.is_running) {
            self.needs_rerun = true;
            return;
        }
        try self.runLoop();
    }

    fn dispose(self: *EffectContext) void {
        if (self.disposed) return;
        self.disposed = true;
        self.unsubscribeAll();
        self.subscriptions.deinit(self.allocator);
        getScheduler().remove(self);
    }
};

pub const EffectHandle = struct {
    effect: *EffectContext,

    pub fn trigger(self: *EffectHandle) !void {
        try self.effect.trigger();
    }

    pub fn dispose(self: *EffectHandle) void {
        self.effect.dispose();
        self.effect.allocator.destroy(self.effect);
        self.effect = undefined;
    }

    pub fn userData(self: *EffectHandle, comptime T: type) ?*T {
        return self.effect.userData(T);
    }
};

const SignalBase = struct {
    context_addr: usize,
    remove_fn: *const fn (usize, *EffectContext) void,
};

fn SignalStorage(comptime T: type) type {
    return struct {
        const Self = @This();

        base: SignalBase,
        allocator: std.mem.Allocator,
        subscribers: SignalSubscriptionList = .{},
        value: T,

        fn init(allocator: std.mem.Allocator, initial: T) Self {
            return .{
                .base = .{
                    .context_addr = 0,
                    .remove_fn = removeSubscriberOpaque,
                },
                .allocator = allocator,
                .value = initial,
            };
        }

        fn attach(self: *Self) void {
            self.base.context_addr = @intFromPtr(self);
        }

        fn register(self: *Self, effect: *EffectContext) !void {
            if (effect.disposed) return;

            var duplicate = false;
            for (self.subscribers.items) |existing| {
                if (existing == effect) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                try self.subscribers.append(self.allocator, effect);
            }

            try effect.addSubscription(.{
                .context_addr = self.base.context_addr,
                .remove_fn = removeSubscriberOpaque,
            });
        }

        fn notify(self: *Self) !void {
            const scheduler = getScheduler();
            for (self.subscribers.items) |subscriber| {
                try scheduler.enqueue(subscriber);
            }
            try scheduler.flushIfIdle();
        }

        fn removeSubscriber(self: *Self, effect: *EffectContext) void {
            var idx: usize = 0;
            while (idx < self.subscribers.items.len) : (idx += 1) {
                if (self.subscribers.items[idx] == effect) {
                    _ = self.subscribers.swapRemove(idx);
                    break;
                }
            }
        }

        fn removeSubscriberOpaque(context_addr: usize, effect: *EffectContext) void {
            const storage = @as(*Self, @ptrFromInt(context_addr));
            storage.removeSubscriber(effect);
        }

        fn deinit(self: *Self) void {
            self.subscribers.deinit(self.allocator);
        }
    };
}

pub fn ReadSignal(comptime T: type) type {
    return struct {
        storage: *SignalStorage(T),

        pub fn get(self: *@This()) !T {
            if (current_effect) |effect| {
                try self.storage.register(effect);
            }
            return self.storage.value;
        }

        pub fn peek(self: *@This()) T {
            return self.storage.value;
        }

        pub fn subscriberCount(self: *@This()) usize {
            return self.storage.subscribers.items.len;
        }
    };
}

pub fn WriteSignal(comptime T: type) type {
    return struct {
        storage: *SignalStorage(T),

        pub fn set(self: *@This(), new_value: T) !void {
            self.storage.value = new_value;
            try self.storage.notify();
        }

        pub fn update(self: *@This(), callback: *const fn (T) anyerror!T) !void {
            const next = try callback(self.storage.value);
            try self.set(next);
        }

        pub fn dispose(self: *@This()) void {
            self.storage.deinit();
            self.storage.allocator.destroy(self.storage);
            self.storage = undefined;
        }
    };
}

pub fn SignalPair(comptime T: type) type {
    return struct {
        read: ReadSignal(T),
        write: WriteSignal(T),

        pub fn dispose(self: *@This()) void {
            self.write.dispose();
            self.read.storage = undefined;
        }
    };
}

pub fn createSignal(comptime T: type, allocator: std.mem.Allocator, initial: T) !SignalPair(T) {
    const Storage = SignalStorage(T);
    const storage = try allocator.create(Storage);
    storage.* = Storage.init(allocator, initial);
    storage.attach();
    return .{
        .read = .{ .storage = storage },
        .write = .{ .storage = storage },
    };
}

pub fn createEffect(allocator: std.mem.Allocator, callback: EffectCallback, user_data: ?*anyopaque) !EffectHandle {
    const effect = try allocator.create(EffectContext);
    effect.* = .{
        .allocator = allocator,
        .callback = callback,
        .user_data_addr = if (user_data) |ptr| @intFromPtr(ptr) else null,
    };
    var handle = EffectHandle{ .effect = effect };
    try handle.trigger();
    return handle;
}

const SuspenseState = struct {
    write: WriteSignal(usize),
    count: usize = 0,

    fn increment(self: *@This()) !void {
        self.count += 1;
        try self.write.set(self.count);
    }

    fn decrement(self: *@This()) !void {
        if (self.count == 0) return;
        self.count -= 1;
        try self.write.set(self.count);
    }
};

const SuspenseContext = struct {
    state: *SuspenseState,
};

pub const SuspenseHandle = struct {
    counter: SignalPair(usize),
    allocator: std.mem.Allocator,
    state: *SuspenseState,

    pub fn pendingSignal(self: *@This()) ReadSignal(usize) {
        return self.counter.read;
    }

    pub fn pendingCount(self: *@This()) usize {
        return self.counter.read.peek();
    }

    pub fn isPending(self: *@This()) bool {
        return self.pendingCount() != 0;
    }

    pub fn enter(self: *@This()) !ContextValueGuard {
        return withContext(SuspenseContext, self.allocator, .{ .state = self.state });
    }

    pub fn dispose(self: *@This()) void {
        self.counter.dispose();
        self.counter = undefined;
        self.allocator.destroy(self.state);
        self.state = undefined;
    }
};

fn suspenseIncrement(state: *SuspenseState) !void {
    try state.increment();
}

fn suspenseDecrement(state: *SuspenseState) !void {
    try state.decrement();
}

pub fn createSuspenseBoundary(allocator: std.mem.Allocator) !SuspenseHandle {
    const counter = try createSignal(usize, allocator, 0);
    const state = try allocator.create(SuspenseState);
    state.* = .{ .write = counter.write };
    return .{
        .counter = counter,
        .allocator = allocator,
        .state = state,
    };
}

pub const ResourceStatus = enum {
    idle,
    pending,
    ready,
    failed,
};

pub fn ResourceState(comptime T: type) type {
    return struct {
        status: ResourceStatus = .idle,
        value: ?T = null,
        error_message: ?[]const u8 = null,
    };
}

fn makeIdleState(comptime T: type) ResourceState(T) {
    return .{ .status = .idle, .value = null, .error_message = null };
}

fn makePendingState(comptime T: type) ResourceState(T) {
    return .{ .status = .pending, .value = null, .error_message = null };
}

fn makeReadyState(comptime T: type, value: T) ResourceState(T) {
    return .{ .status = .ready, .value = value, .error_message = null };
}

fn makeFailedState(comptime T: type, message: []const u8) ResourceState(T) {
    return .{ .status = .failed, .value = null, .error_message = message };
}

fn ResourceContext(comptime Source: type, comptime T: type) type {
    return struct {
        source: ReadSignal(Source),
        fetcher: *const fn (Source) anyerror!T,
        state_write: WriteSignal(ResourceState(T)),
        suspense: ?*SuspenseState,
        suspense_registered: bool = false,

        fn markPending(self: *@This()) !void {
            if (self.suspense) |state| {
                if (!self.suspense_registered) {
                    self.suspense_registered = true;
                    try suspenseIncrement(state);
                }
            }
        }

        fn markSettled(self: *@This()) !void {
            if (self.suspense) |state| {
                if (self.suspense_registered) {
                    self.suspense_registered = false;
                    try suspenseDecrement(state);
                }
            }
        }
    };
}

pub fn ResourceHandle(comptime Source: type, comptime T: type) type {
    return struct {
        state: SignalPair(ResourceState(T)),
        effect: EffectHandle,
        allocator: std.mem.Allocator,
        context: *ResourceContext(Source, T),

        pub fn read(self: *@This()) ReadSignal(ResourceState(T)) {
            return self.state.read;
        }

        pub fn dispose(self: *@This()) void {
            self.context.markSettled() catch {};
            self.effect.dispose();
            self.effect = undefined;
            self.state.dispose();
            self.state = undefined;
            self.allocator.destroy(self.context);
            self.context = undefined;
        }
    };
}

pub fn createResource(
    comptime Source: type,
    comptime T: type,
    allocator: std.mem.Allocator,
    source: ReadSignal(Source),
    fetcher: *const fn (Source) anyerror!T,
) !ResourceHandle(Source, T) {
    const state = try createSignal(ResourceState(T), allocator, makeIdleState(T));
    const Context = ResourceContext(Source, T);

    const ctx_ptr = try allocator.create(Context);
    const suspense_ctx = useContext(SuspenseContext);
    ctx_ptr.* = .{
        .source = source,
        .fetcher = fetcher,
        .state_write = state.write,
        .suspense = if (suspense_ctx) |s| s.state else null,
    };

    const effect = try createEffect(allocator, struct {
        fn run(effect_ctx: *EffectContext) anyerror!void {
            const ctx = effect_ctx.userData(Context).?;
            const input = ctx.source.get() catch |err| {
                try ctx.state_write.set(makeFailedState(T, @errorName(err)));
                return;
            };

            var settled = false;
            defer if (!settled) ctx.markSettled() catch {};

            try ctx.markPending();
            try ctx.state_write.set(makePendingState(T));

            const value = ctx.fetcher(input) catch |err| {
                try ctx.state_write.set(makeFailedState(T, @errorName(err)));
                try ctx.markSettled();
                settled = true;
                return;
            };

            try ctx.state_write.set(makeReadyState(T, value));
            try ctx.markSettled();
            settled = true;
        }
    }.run, ctx_ptr);

    return ResourceHandle(Source, T){
        .state = state,
        .effect = effect,
        .allocator = allocator,
        .context = ctx_ptr,
    };
}

pub fn createMemo(
    comptime T: type,
    allocator: std.mem.Allocator,
    compute: *const fn (*EffectContext, ?*anyopaque) anyerror!T,
    user_data: ?*anyopaque,
) !MemoHandle(T) {
    const pair = try createSignal(T, allocator, undefinedValue(T));
    const Ctx = MemoContext(T);

    const memo_ctx = try allocator.create(Ctx);
    memo_ctx.* = .{
        .write = pair.write,
        .compute = compute,
        .user_data = user_data,
    };

    const memo_callback = struct {
        fn run(effect: *EffectContext) anyerror!void {
            const ctx_ptr = effect.userData(Ctx).?;
            const next = try ctx_ptr.compute(effect, ctx_ptr.user_data);
            try ctx_ptr.write.set(next);
        }
    }.run;

    const effect_handle = try createEffect(allocator, memo_callback, memo_ctx);

    return .{
        .read = pair.read,
        .write = pair.write,
        .effect = effect_handle,
        .allocator = allocator,
        .context = memo_ctx,
    };
}

pub fn MemoHandle(comptime T: type) type {
    return struct {
        read: ReadSignal(T),
        write: WriteSignal(T),
        effect: EffectHandle,
        allocator: std.mem.Allocator,
        context: *MemoContext(T),

        pub fn get(self: *@This()) !T {
            return self.read.get();
        }

        pub fn dispose(self: *@This()) void {
            self.effect.dispose();
            self.write.dispose();
            self.allocator.destroy(self.context);
            self.read.storage = undefined;
            self.context = undefined;
            self.effect = undefined;
        }
    };
}

fn MemoContext(comptime T: type) type {
    return struct {
        write: WriteSignal(T),
        compute: *const fn (*EffectContext, ?*anyopaque) anyerror!T,
        user_data: ?*anyopaque,
    };
}

fn undefinedValue(comptime T: type) T {
    return @as(T, undefined);
}
