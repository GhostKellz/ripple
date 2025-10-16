const std = @import("std");
const core = @import("core.zig");
const component = @import("component.zig");
const dom = @import("dom.zig");
const zsync = @import("zsync");

pub const ValidationOutcome = struct {
    valid: bool = true,
    message: ?[]const u8 = null,
};

pub const AsyncValidation = struct {
    future: *zsync.Future(ValidationOutcome),
};

pub const ValidationResult = union(enum) {
    immediate: ValidationOutcome,
    future: AsyncValidation,
};

pub const ValidationAdapter = struct {
    validateField: *const fn ([]const u8, []const u8, std.mem.Allocator, ?*anyopaque) anyerror!ValidationResult,
    deinitContext: ?*const fn (std.mem.Allocator, ?*anyopaque) void = null,
    context: ?*anyopaque = null,

    pub fn validate(self: ValidationAdapter, field: []const u8, value: []const u8, allocator: std.mem.Allocator) !ValidationResult {
        return self.validateField(field, value, allocator, self.context);
    }

    fn scheduleAsyncValidation(self: *FormStore, field: *FieldState, pending: AsyncValidation) !void {
        self.pending_async.ensureTotalCapacity(self.pending_async.items.len + 1) catch |err| {
            pending.future.cancel();
            pending.future.deinit();
            return err;
        };

        const was_valid = field.valid_state;
        if (was_valid) {
            self.invalid_count += 1;
        }
        field.valid_state = false;
        try field.valid_signal.write.set(false);

        try field.setErrorMessage(self.allocator, &[_]u8{});
        try field.error_signal.write.set(field.error_message);

        if (!field.validating_state) {
            field.validating_state = true;
            self.validating_count += 1;
        }
        try field.validating_signal.write.set(true);

        self.pending_async.appendAssumeCapacity(.{ .field_name = field.name, .future = pending.future });

        try self.validating_signal.write.set(self.validating_count > 0);
        try self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0);
    }

    fn cancelPendingValidation(self: *FormStore, field: *FieldState) void {
        var i: usize = 0;
        while (i < self.pending_async.items.len) {
            const entry = self.pending_async.items[i];
            if (std.mem.eql(u8, entry.field_name, field.name)) {
                const pending = self.pending_async.swapRemove(i);
                pending.future.cancel();
                pending.future.deinit();

                if (field.validating_state) {
                    field.validating_state = false;
                    if (self.validating_count > 0) self.validating_count -= 1;
                    field.validating_signal.write.set(false) catch {};
                    self.validating_signal.write.set(self.validating_count > 0) catch {};
                    self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0) catch {};
                }
                return;
            }
            i += 1;
        }
    }

    fn finishAsyncValidation(self: *FormStore, field: *FieldState, outcome: ValidationOutcome) !void {
        if (field.validating_state) {
            field.validating_state = false;
            if (self.validating_count > 0) self.validating_count -= 1;
            try field.validating_signal.write.set(false);
        }
        try self.applyValidationOutcome(field, outcome);
        try self.validating_signal.write.set(self.validating_count > 0);
    }

    fn applyValidationOutcome(self: *FormStore, field: *FieldState, outcome: ValidationOutcome) !void {
        const prev_valid = field.valid_state;
        try field.setErrorMessage(self.allocator, outcome.message orelse &[_]u8{});
        field.valid_state = outcome.valid;

        if (prev_valid != field.valid_state) {
            if (field.valid_state) {
                if (self.invalid_count > 0) self.invalid_count -= 1;
            } else {
                self.invalid_count += 1;
            }
        }

        try field.valid_signal.write.set(field.valid_state);
        try field.error_signal.write.set(field.error_message);
        try self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0);
    }

    fn processAsyncValidations(self: *FormStore) !void {
        var i: usize = 0;
        while (i < self.pending_async.items.len) {
            const entry = self.pending_async.items[i];
            switch (entry.future.poll()) {
                .pending => {
                    i += 1;
                },
                .cancelled => {
                    const pending = self.pending_async.swapRemove(i);
                    pending.future.deinit();
                    if (self.fields.getPtr(pending.field_name)) |field| {
                        if (field.validating_state) {
                            field.validating_state = false;
                            if (self.validating_count > 0) self.validating_count -= 1;
                            try field.validating_signal.write.set(false);
                        }
                        try self.applyValidationOutcome(field, .{ .valid = false, .message = VALIDATION_CANCELLED_MSG });
                    } else {
                        if (self.validating_count > 0) self.validating_count -= 1;
                    }
                    try self.validating_signal.write.set(self.validating_count > 0);
                    try self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0);
                },
                .ready => {
                    const pending = self.pending_async.swapRemove(i);
                    const outcome = pending.future.await() catch |err| ValidationOutcome{
                        .valid = false,
                        .message = @errorName(err),
                    };
                    pending.future.deinit();

                    if (self.fields.getPtr(pending.field_name)) |field| {
                        try self.finishAsyncValidation(field, outcome);
                    } else {
                        if (self.validating_count > 0) self.validating_count -= 1;
                        try self.validating_signal.write.set(self.validating_count > 0);
                        try self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0);
                    }
                },
            }
        }
    }

    pub fn deinit(self: *ValidationAdapter, allocator: std.mem.Allocator) void {
        if (self.deinitContext) |deinit_fn| {
            deinit_fn(allocator, self.context);
        }
        self.* = ValidationAdapter{
            .validateField = struct {
                fn noop(_: []const u8, _: []const u8, _: std.mem.Allocator, _: ?*anyopaque) anyerror!ValidationResult {
                    return ValidationResult{ .immediate = ValidationOutcome{} };
                }
            }.noop,
            .deinitContext = null,
            .context = null,
        };
    }
};

pub const ZSchemaMinLengthRule = struct {
    field: []const u8,
    min: usize,
    message: []const u8 = "Value is too short",
};

pub fn createZSchemaMinLengthAdapter(
    allocator: std.mem.Allocator,
    rules: []const ZSchemaMinLengthRule,
) !ValidationAdapter {
    const Context = struct {
        allocator: std.mem.Allocator,
        rules: std.StringHashMap(RuleEntry),

        const RuleEntry = struct {
            min: usize,
            message: []u8,
        };

        fn init(alloc: std.mem.Allocator, src_rules: []const ZSchemaMinLengthRule) !*@This() {
            const ctx = try alloc.create(@This());
            errdefer alloc.destroy(ctx);
            ctx.* = .{
                .allocator = alloc,
                .rules = std.StringHashMap(RuleEntry).init(alloc),
            };

            errdefer ctx.deinit();

            for (src_rules) |rule| {
                const key = try alloc.dupe(u8, rule.field);
                errdefer alloc.free(key);

                const message = if (rule.message.len == 0)
                    &[_]u8{}
                else
                    try alloc.dupe(u8, rule.message);
                errdefer if (message.len > 0) alloc.free(@constCast(message));

                const gop = try ctx.rules.getOrPut(key);
                if (gop.found_existing) {
                    const existing = gop.value_ptr.*;
                    if (existing.message.len > 0) alloc.free(existing.message);
                    ctx.allocator.free(@constCast(gop.key_ptr.*));
                }
                gop.key_ptr.* = key;
                gop.value_ptr.* = .{ .min = rule.min, .message = if (message.len == 0) &[_]u8{} else message };
            }

            return ctx;
        }

        fn validate(self: *@This(), field: []const u8, value: []const u8) ValidationOutcome {
            if (self.rules.get(field)) |entry| {
                if (value.len < entry.min) {
                    return .{
                        .valid = false,
                        .message = if (entry.message.len == 0) null else entry.message,
                    };
                }
            }
            return .{};
        }

        fn deinit(self: *@This()) void {
            var it = self.rules.iterator();
            while (it.next()) |entry| {
                self.allocator.free(@constCast(entry.key_ptr.*));
                if (entry.value_ptr.message.len > 0) {
                    self.allocator.free(entry.value_ptr.message);
                }
            }
            self.rules.deinit();
            self.allocator.destroy(self);
        }
    };

    const ctx = try Context.init(allocator, rules);

    const validateFn = struct {
        fn run(field: []const u8, value: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const context = @as(*Context, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            return ValidationResult{ .immediate = context.validate(field, value) };
        }
    }.run;

    const deinitFn = struct {
        fn run(_unused_allocator: std.mem.Allocator, ctx_ptr: ?*anyopaque) void {
            _ = _unused_allocator;
            const context = @as(*Context, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            context.deinit();
        }
    }.run;

    return ValidationAdapter{
        .validateField = validateFn,
        .deinitContext = deinitFn,
        .context = ctx,
    };
}

pub const FormStoreOptions = struct {
    validation: ?ValidationAdapter = null,
};

pub const FieldConfig = struct {
    name: []const u8,
    initial: []const u8,
};

pub const FormSnapshot = struct {
    dirty: bool,
    touched: bool,
    valid: bool,
    validating: bool,
};

pub const FieldView = struct {
    name: []const u8,
    initial: []const u8,
    value: core.ReadSignal([]const u8),
    dirty: core.ReadSignal(bool),
    touched: core.ReadSignal(bool),
    validating: core.ReadSignal(bool),
    valid: core.ReadSignal(bool),
    error_message: core.ReadSignal([]const u8),
};

pub const SerializedField = struct {
    name: []const u8,
    value: []const u8,
    dirty: bool,
    touched: bool,
    valid: bool,
    validating: bool,
    error_message: []const u8,
};

pub const SerializedForm = struct {
    allocator: std.mem.Allocator,
    fields: []SerializedField,

    pub fn values(self: SerializedForm) []const SerializedField {
        return self.fields;
    }

    pub fn len(self: SerializedForm) usize {
        return self.fields.len;
    }

    pub fn deinit(self: *SerializedForm) void {
        for (self.fields) |field| {
            self.allocator.free(@constCast(field.name));
            self.allocator.free(@constCast(field.value));
            if (field.error_message.len > 0) {
                self.allocator.free(@constCast(field.error_message));
            }
        }
        self.allocator.free(@constCast(self.fields));
        self.fields = &.{};
    }
};

pub const FormSubmitOptions = struct {
    prevent_submit_on_invalid: bool = true,
    on_valid: ?*const fn (*FormStore, ?*anyopaque) anyerror!void = null,
    on_invalid: ?*const fn (*FormStore, ?*anyopaque) anyerror!void = null,
    user_data: ?*anyopaque = null,
};

pub const FormSubmitBinding = struct {
    on_submit: component.View.EventHandler,
    allocator: std.mem.Allocator,
    context: *FormSubmitContext,

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self.context);
        self.context = undefined;
    }
};

const PendingValidation = struct {
    field_name: []const u8,
    future: *zsync.Future(ValidationOutcome),
};

pub const FormStore = struct {
    allocator: std.mem.Allocator,
    fields: std.StringHashMap(FieldState),
    dirty_count: usize,
    touched_count: usize,
    invalid_count: usize,
    validating_count: usize,
    dirty_signal: core.SignalPair(bool),
    touched_signal: core.SignalPair(bool),
    valid_signal: core.SignalPair(bool),
    validating_signal: core.SignalPair(bool),
    validation_adapter: ?ValidationAdapter,
    pending_async: std.ArrayList(PendingValidation),
    processing_async: bool,
    validation_batch_depth: usize,
    batched_validations: std.ArrayList(*FieldState),

    pub fn init(allocator: std.mem.Allocator, options: FormStoreOptions) !FormStore {
        return .{
            .allocator = allocator,
            .fields = std.StringHashMap(FieldState).init(allocator),
            .dirty_count = 0,
            .touched_count = 0,
            .invalid_count = 0,
            .validating_count = 0,
            .dirty_signal = try core.createSignal(bool, allocator, false),
            .touched_signal = try core.createSignal(bool, allocator, false),
            .valid_signal = try core.createSignal(bool, allocator, true),
            .validating_signal = try core.createSignal(bool, allocator, false),
            .validation_adapter = options.validation,
            .pending_async = std.ArrayList(PendingValidation).init(allocator),
            .processing_async = false,
            .validation_batch_depth = 0,
            .batched_validations = std.ArrayList(*FieldState).init(allocator),
        };
    }

    pub fn deinit(self: *FormStore) void {
        for (self.pending_async.items) |pending| {
            pending.future.cancel();
            pending.future.deinit();
        }
        self.pending_async.deinit();
        self.batched_validations.deinit();
        var it = self.fields.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.fields.deinit();
        self.dirty_signal.dispose();
        self.touched_signal.dispose();
        self.valid_signal.dispose();
        self.validating_signal.dispose();
        if (self.validation_adapter) |*adapter| {
            adapter.deinit(self.allocator);
        }
    }

    pub fn registerField(self: *FormStore, config: FieldConfig) !void {
        try self.tickAsyncValidations();
        if (self.fields.get(config.name) != null) return error.DuplicateField;

        var field = try FieldState.init(self.allocator, config);
        errdefer field.deinit(self.allocator);

        try self.fields.put(field.name, field);
        const stored = self.fields.getPtr(field.name) orelse unreachable;
        try self.applyValidation(stored);
    }

    pub fn setValue(self: *FormStore, name: []const u8, value: []const u8) !void {
        try self.tickAsyncValidations();
        const field = self.fields.getPtr(name) orelse return error.UnknownField;

        if (std.mem.eql(u8, field.current, value)) {
            return;
        }

        const prev_dirty = field.dirty_state;
        const copy = try self.allocator.dupe(u8, value);
        self.allocator.free(field.current);
        field.current = copy;
        try field.value_signal.write.set(field.current);

        const new_dirty = !std.mem.eql(u8, field.current, field.initial);
        if (new_dirty != prev_dirty) {
            if (new_dirty) {
                self.dirty_count += 1;
            } else if (self.dirty_count > 0) {
                self.dirty_count -= 1;
            }
            field.dirty_state = new_dirty;
            try field.dirty_signal.write.set(new_dirty);
            try self.dirty_signal.write.set(self.dirty_count > 0);
        } else {
            try field.dirty_signal.write.set(new_dirty);
        }

        if (!field.touched_state) {
            field.touched_state = true;
            self.touched_count += 1;
            try field.touched_signal.write.set(true);
            try self.touched_signal.write.set(true);
        } else {
            try field.touched_signal.write.set(true);
        }

        try self.applyValidation(field);
    }

    pub fn markTouched(self: *FormStore, name: []const u8) !void {
        try self.tickAsyncValidations();
        const field = self.fields.getPtr(name) orelse return error.UnknownField;
        if (field.touched_state) return;

        field.touched_state = true;
        self.touched_count += 1;
        try field.touched_signal.write.set(true);
        try self.touched_signal.write.set(true);

        try self.applyValidation(field);
    }

    pub fn resetField(self: *FormStore, name: []const u8) !void {
        try self.tickAsyncValidations();
        const field = self.fields.getPtr(name) orelse return error.UnknownField;

        if (!std.mem.eql(u8, field.current, field.initial)) {
            const copy = try self.allocator.dupe(u8, field.initial);
            self.allocator.free(field.current);
            field.current = copy;
            try field.value_signal.write.set(field.current);
        } else {
            try field.value_signal.write.set(field.current);
        }

        if (field.dirty_state) {
            if (self.dirty_count > 0) self.dirty_count -= 1;
            field.dirty_state = false;
            try field.dirty_signal.write.set(false);
            try self.dirty_signal.write.set(self.dirty_count > 0);
        } else {
            try field.dirty_signal.write.set(false);
        }

        if (field.touched_state) {
            if (self.touched_count > 0) self.touched_count -= 1;
            field.touched_state = false;
            try field.touched_signal.write.set(false);
            try self.touched_signal.write.set(self.touched_count > 0);
        } else {
            try field.touched_signal.write.set(false);
        }

        try self.applyValidation(field);
    }

    pub fn reset(self: *FormStore) !void {
        try self.tickAsyncValidations();
        var it = self.fields.iterator();
        while (it.next()) |entry| {
            try self.resetField(entry.key_ptr.*);
        }
    }

    pub fn fieldView(self: *FormStore, name: []const u8) ?FieldView {
        const field = self.fields.getPtr(name) orelse return null;

        return FieldView{
            .name = field.name,
            .initial = field.initial,
            .value = field.value_signal.read,
            .dirty = field.dirty_signal.read,
            .touched = field.touched_signal.read,
            .validating = field.validating_signal.read,
            .valid = field.valid_signal.read,
            .error_message = field.error_signal.read,
        };
    }

    pub fn markAllTouched(self: *FormStore) !void {
        try self.tickAsyncValidations();
        var it = self.fields.iterator();
        while (it.next()) |entry| {
            const field = entry.value_ptr;
            if (!field.touched_state) {
                field.touched_state = true;
                self.touched_count += 1;
            }
            try field.touched_signal.write.set(true);
            try self.applyValidation(field);
        }
        try self.touched_signal.write.set(self.touched_count > 0);
    }

    pub fn validateAll(self: *FormStore) !void {
        try self.tickAsyncValidations();
        var it = self.fields.iterator();
        while (it.next()) |entry| {
            try self.applyValidation(entry.value_ptr);
        }
    }

    pub fn serialize(self: *FormStore, allocator: std.mem.Allocator) !SerializedForm {
        try self.tickAsyncValidations();

        var list = std.ArrayList(SerializedField).init(allocator);
        errdefer {
            for (list.items) |field| {
                allocator.free(@constCast(field.name));
                allocator.free(@constCast(field.value));
                if (field.error_message.len > 0) {
                    allocator.free(@constCast(field.error_message));
                }
            }
            list.deinit();
        }

        var it = self.fields.iterator();
        while (it.next()) |entry| {
            const field = entry.value_ptr;
            const name_copy = try allocator.dupe(u8, field.name);
            errdefer allocator.free(name_copy);

            const value_copy = try allocator.dupe(u8, field.current);
            errdefer allocator.free(value_copy);

            var error_copy: []const u8 = &[_]u8{};
            if (field.error_message.len != 0) {
                const dup = try allocator.dupe(u8, field.error_message);
                errdefer allocator.free(dup);
                error_copy = dup;
            }

            try list.append(.{
                .name = name_copy,
                .value = value_copy,
                .dirty = field.dirty_state,
                .touched = field.touched_state,
                .valid = field.valid_state,
                .validating = field.validating_state,
                .error_message = error_copy,
            });
        }

        const owned = try list.toOwnedSlice();
        return SerializedForm{ .allocator = allocator, .fields = owned };
    }

    pub fn tickAsyncValidations(self: *FormStore) !void {
        if (self.processing_async) return;
        self.processing_async = true;
        defer self.processing_async = false;
        try self.processAsyncValidations();
    }

    pub fn dirtySignal(self: *FormStore) core.ReadSignal(bool) {
        return self.dirty_signal.read;
    }

    pub fn touchedSignal(self: *FormStore) core.ReadSignal(bool) {
        return self.touched_signal.read;
    }

    pub fn validSignal(self: *FormStore) core.ReadSignal(bool) {
        return self.valid_signal.read;
    }

    pub fn validatingSignal(self: *FormStore) core.ReadSignal(bool) {
        return self.validating_signal.read;
    }

    pub fn beginValidationBatch(self: *FormStore) ValidationBatchGuard {
        self.validation_batch_depth += 1;
        return ValidationBatchGuard{ .store = self, .active = true };
    }

    pub fn withValidationBatch(
        self: *FormStore,
        callback: *const fn (*FormStore, ?*anyopaque) anyerror!void,
        context: ?*anyopaque,
    ) !void {
        var guard = self.beginValidationBatch();
        defer guard.deinit();
        try callback(self, context);
        try guard.finish();
    }

    fn endValidationBatch(self: *FormStore) !void {
        std.debug.assert(self.validation_batch_depth > 0);
        self.validation_batch_depth -= 1;
        if (self.validation_batch_depth == 0) {
            try self.flushBatchedValidations();
        }
    }

    fn flushBatchedValidations(self: *FormStore) !void {
        var i: usize = 0;
        while (i < self.batched_validations.items.len) : (i += 1) {
            const field = self.batched_validations.items[i];
            try self.performValidation(field);
        }
        self.batched_validations.clearRetainingCapacity();
    }

    pub const ValidationBatchGuard = struct {
        store: *FormStore,
        active: bool,

        pub fn finish(self: *@This()) !void {
            if (!self.active) return;
            self.active = false;
            try self.store.endValidationBatch();
        }

        pub fn deinit(self: *@This()) void {
            if (!self.active) return;
            self.active = false;
            self.store.endValidationBatch() catch {};
        }
    };

    const TimeFn = *const fn () i128;

    fn defaultTimeSource() i128 {
        return std.time.nanoTimestamp();
    }

    pub const ValidationDebouncer = struct {
        store: *FormStore,
        delay_ns: u64,
        clock: TimeFn,
        guard: ValidationBatchGuard,
        deadline: i128,
        active: bool,

        pub fn init(store: *FormStore, delay_ns: u64, clock: ?TimeFn) ValidationDebouncer {
            return .{
                .store = store,
                .delay_ns = delay_ns,
                .clock = clock orelse defaultTimeSource,
                .guard = undefined,
                .deadline = 0,
                .active = false,
            };
        }

        fn ensureGuard(self: *@This()) void {
            if (!self.active) {
                self.guard = self.store.beginValidationBatch();
                self.active = true;
            }
        }

        pub fn touch(self: *@This()) void {
            self.ensureGuard();
            const delay = @as(i128, @intCast(self.delay_ns));
            self.deadline = self.clock() + delay;
        }

        pub fn tick(self: *@This()) !void {
            if (!self.active) return;
            if (self.clock() >= self.deadline) {
                defer self.active = false;
                try self.guard.finish();
            }
        }

        pub fn cancel(self: *@This()) void {
            if (!self.active) return;
            self.guard.deinit();
            self.active = false;
        }

        pub fn isActive(self: ValidationDebouncer) bool {
            return self.active;
        }
    };

    pub const ValidationThrottler = struct {
        store: *FormStore,
        interval_ns: u64,
        clock: TimeFn,
        guard: ValidationBatchGuard,
        has_guard: bool,
        cooldown_until: i128,
        flush_at: i128,

        pub fn init(store: *FormStore, interval_ns: u64, clock: ?TimeFn) ValidationThrottler {
            return .{
                .store = store,
                .interval_ns = interval_ns,
                .clock = clock orelse defaultTimeSource,
                .guard = undefined,
                .has_guard = false,
                .cooldown_until = std.math.minInt(i128),
                .flush_at = std.math.minInt(i128),
            };
        }

        fn interval(self: ValidationThrottler) i128 {
            return @as(i128, @intCast(self.interval_ns));
        }

        pub fn touch(self: *@This()) void {
            const now = self.clock();
            if (now >= self.cooldown_until) {
                if (self.has_guard) {
                    self.guard.deinit();
                    self.has_guard = false;
                }
                self.cooldown_until = now + self.interval();
                self.flush_at = self.cooldown_until;
                return;
            }

            if (!self.has_guard) {
                self.guard = self.store.beginValidationBatch();
                self.has_guard = true;
                self.flush_at = self.cooldown_until;
            }
        }

        pub fn tick(self: *@This()) !void {
            if (!self.has_guard) {
                const now = self.clock();
                if (now >= self.cooldown_until) {
                    self.cooldown_until = now;
                }
                return;
            }

            if (self.clock() >= self.flush_at) {
                try self.guard.finish();
                self.has_guard = false;
                const now = self.clock();
                self.cooldown_until = now + self.interval();
                self.flush_at = self.cooldown_until;
            }
        }

        pub fn cancel(self: *@This()) void {
            if (!self.has_guard) return;
            self.guard.deinit();
            self.has_guard = false;
        }

        pub fn isGuardActive(self: ValidationThrottler) bool {
            return self.has_guard;
        }
    };

    pub fn snapshot(self: *FormStore) FormSnapshot {
        return .{
            .dirty = self.dirty_count > 0,
            .touched = self.touched_count > 0,
            .valid = self.invalid_count == 0 and self.validating_count == 0,
            .validating = self.validating_count > 0,
        };
    }

    fn applyValidation(self: *FormStore, field: *FieldState) !void {
        if (self.validation_batch_depth > 0) {
            if (!field.pending_validation) {
                field.pending_validation = true;
                self.batched_validations.append(field) catch |err| {
                    field.pending_validation = false;
                    return err;
                };
            }
            return;
        }

        try self.performValidation(field);
    }

    fn performValidation(self: *FormStore, field: *FieldState) !void {
        field.pending_validation = false;

        if (self.validation_adapter) |adapter| {
            self.cancelPendingValidation(field);
            const result = try adapter.validate(field.name, field.current, self.allocator);
            switch (result) {
                .immediate => |outcome| {
                    try self.applyValidationOutcome(field, outcome);
                },
                .future => |pending| {
                    try self.scheduleAsyncValidation(field, pending);
                },
            }
        } else {
            if (!field.valid_state or field.error_message.len != 0) {
                if (!field.valid_state and self.invalid_count > 0) {
                    self.invalid_count -= 1;
                }
                field.valid_state = true;
                try field.setErrorMessage(self.allocator, &[_]u8{});
                try field.valid_signal.write.set(true);
                try field.error_signal.write.set(field.error_message);
                try self.valid_signal.write.set(self.invalid_count == 0 and self.validating_count == 0);
            }
        }
    }
};

const FieldState = struct {
    name: []u8,
    initial: []u8,
    current: []u8,
    dirty_state: bool,
    touched_state: bool,
    valid_state: bool,
    validating_state: bool,
    pending_validation: bool,
    error_message: []u8,
    value_signal: core.SignalPair([]const u8),
    dirty_signal: core.SignalPair(bool),
    touched_signal: core.SignalPair(bool),
    valid_signal: core.SignalPair(bool),
    validating_signal: core.SignalPair(bool),
    error_signal: core.SignalPair([]const u8),

    fn init(allocator: std.mem.Allocator, config: FieldConfig) !FieldState {
        const name_copy = try allocator.dupe(u8, config.name);
        errdefer allocator.free(name_copy);

        const initial_copy = try allocator.dupe(u8, config.initial);
        errdefer allocator.free(initial_copy);

        const current_copy = try allocator.dupe(u8, config.initial);
        errdefer allocator.free(current_copy);

        var value_signal = try core.createSignal([]const u8, allocator, current_copy);
        errdefer value_signal.dispose();

        var dirty_signal = try core.createSignal(bool, allocator, false);
        errdefer dirty_signal.dispose();

        var touched_signal = try core.createSignal(bool, allocator, false);
        errdefer touched_signal.dispose();

        var valid_signal = try core.createSignal(bool, allocator, true);
        errdefer valid_signal.dispose();

        var validating_signal = try core.createSignal(bool, allocator, false);
        errdefer validating_signal.dispose();

        var error_signal = try core.createSignal([]const u8, allocator, &[_]u8{});
        errdefer error_signal.dispose();

        return .{
            .name = name_copy,
            .initial = initial_copy,
            .current = current_copy,
            .dirty_state = false,
            .touched_state = false,
            .valid_state = true,
            .validating_state = false,
            .pending_validation = false,
            .error_message = &[_]u8{},
            .value_signal = value_signal,
            .dirty_signal = dirty_signal,
            .touched_signal = touched_signal,
            .valid_signal = valid_signal,
            .validating_signal = validating_signal,
            .error_signal = error_signal,
        };
    }

    fn deinit(self: *FieldState, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.initial);
        allocator.free(self.current);
        if (self.error_message.len > 0) {
            allocator.free(self.error_message);
        }
        self.value_signal.dispose();
        self.dirty_signal.dispose();
        self.touched_signal.dispose();
        self.valid_signal.dispose();
        self.validating_signal.dispose();
        self.error_signal.dispose();
    }

    fn setErrorMessage(self: *FieldState, allocator: std.mem.Allocator, message: []const u8) !void {
        if (self.error_message.len > 0) {
            allocator.free(self.error_message);
        }
        if (message.len == 0) {
            self.error_message = &[_]u8{};
        } else {
            self.error_message = try allocator.dupe(u8, message);
        }
    }
};

const FieldContext = struct {
    store: *FormStore,
    field_name: []const u8,
};

const CheckboxMemoContext = struct {
    value: core.ReadSignal([]const u8),
};

const FormSubmitContext = struct {
    store: *FormStore,
    options: FormSubmitOptions,
};

fn makeFieldContext(allocator: std.mem.Allocator, store: *FormStore, field_name: []const u8) !*FieldContext {
    const ctx = try allocator.create(FieldContext);
    ctx.* = .{ .store = store, .field_name = field_name };
    return ctx;
}

fn ctxPtr(ptr: *FieldContext) ?*anyopaque {
    return @as(?*anyopaque, @ptrFromInt(@intFromPtr(ptr)));
}

fn submitCtxPtr(ptr: *FormSubmitContext) ?*anyopaque {
    return @as(?*anyopaque, @ptrFromInt(@intFromPtr(ptr)));
}

fn normalizeTextPayload(ev: *dom.SyntheticEvent) []const u8 {
    return ev.payload() orelse "";
}

fn normalizeSelectPayload(ev: *dom.SyntheticEvent) []const u8 {
    return ev.payload() orelse "";
}

const TRUE_STR = "true";
const FALSE_STR = "false";
const CHECKED_ATTR = "checked";
const EMPTY_ATTR = "";
const VALIDATION_CANCELLED_MSG = "Validation cancelled";

fn isTruthy(value: []const u8) bool {
    if (std.mem.eql(u8, value, TRUE_STR)) return true;
    if (std.mem.eql(u8, value, "1")) return true;
    if (std.mem.eql(u8, value, "on")) return true;
    if (std.mem.eql(u8, value, "yes")) return true;
    return false;
}

fn determineCheckboxNext(value_payload: ?[]const u8, current_value: []const u8) []const u8 {
    if (value_payload) |payload| {
        if (isTruthy(payload)) return TRUE_STR;
        if (std.mem.eql(u8, payload, FALSE_STR)) return FALSE_STR;
        if (std.mem.eql(u8, payload, "0")) return FALSE_STR;
        if (std.mem.eql(u8, payload, "off")) return FALSE_STR;
        if (std.mem.eql(u8, payload, "no")) return FALSE_STR;
    }
    return if (isTruthy(current_value)) FALSE_STR else TRUE_STR;
}

fn handleSetValue(ev: *dom.SyntheticEvent, ctx_ptr: ?*anyopaque) void {
    const ctx = @as(*FieldContext, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
    const payload = normalizeTextPayload(ev);
    ctx.store.setValue(ctx.field_name, payload) catch unreachable;
}

fn handleSelectSetValue(ev: *dom.SyntheticEvent, ctx_ptr: ?*anyopaque) void {
    const ctx = @as(*FieldContext, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
    const payload = normalizeSelectPayload(ev);
    ctx.store.setValue(ctx.field_name, payload) catch unreachable;
}

fn handleCheckboxSetValue(ev: *dom.SyntheticEvent, ctx_ptr: ?*anyopaque) void {
    const ctx = @as(*FieldContext, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
    const current = ctx.store.fieldView(ctx.field_name) orelse return;
    const payload = ev.payload();
    const next = determineCheckboxNext(payload, current.value.peek());
    ctx.store.setValue(ctx.field_name, next) catch unreachable;
}

fn handleMarkTouched(ev: *dom.SyntheticEvent, ctx_ptr: ?*anyopaque) void {
    _ = ev;
    const ctx = @as(*FieldContext, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
    ctx.store.markTouched(ctx.field_name) catch unreachable;
}

fn handleFormSubmit(ev: *dom.SyntheticEvent, ctx_ptr: ?*anyopaque) void {
    const ctx = @as(*FormSubmitContext, @ptrFromInt(@intFromPtr(ctx_ptr.?)));
    ctx.store.markAllTouched() catch unreachable;
    ctx.store.validateAll() catch unreachable;
    ctx.store.tickAsyncValidations() catch unreachable;

    const snapshot = ctx.store.snapshot();
    if (!snapshot.valid and ctx.options.prevent_submit_on_invalid) {
        ev.preventDefault();
    }

    if (snapshot.valid) {
        if (ctx.options.on_valid) |callback| {
            callback(ctx.store, ctx.options.user_data) catch unreachable;
        }
    } else {
        if (ctx.options.on_invalid) |callback| {
            callback(ctx.store, ctx.options.user_data) catch unreachable;
        }
    }
}

fn computeCheckedAttr(_: *core.EffectContext, user_data: ?*anyopaque) anyerror![]const u8 {
    const ctx = @as(*CheckboxMemoContext, @ptrFromInt(@intFromPtr(user_data.?)));
    const value = try ctx.value.get();
    if (isTruthy(value)) {
        return CHECKED_ATTR;
    }
    return EMPTY_ATTR;
}

pub const TextBinding = struct {
    field: FieldView,
    on_input: component.View.EventHandler,
    on_blur: component.View.EventHandler,
    allocator: std.mem.Allocator,
    context: *FieldContext,

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self.context);
        self.context = undefined;
    }
};

pub fn bindTextInput(allocator: std.mem.Allocator, store: *FormStore, name: []const u8) !TextBinding {
    const view = store.fieldView(name) orelse return error.UnknownField;
    const ctx = try makeFieldContext(allocator, store, view.name);
    const context_ptr = ctxPtr(ctx);

    return TextBinding{
        .field = view,
        .on_input = component.View.EventHandler{
            .event_name = "input",
            .handler = .{ .callback = handleSetValue, .context = context_ptr },
        },
        .on_blur = component.View.EventHandler{
            .event_name = "blur",
            .handler = .{ .callback = handleMarkTouched, .context = context_ptr },
        },
        .allocator = allocator,
        .context = ctx,
    };
}

pub const SelectBinding = struct {
    field: FieldView,
    on_change: component.View.EventHandler,
    on_blur: component.View.EventHandler,
    allocator: std.mem.Allocator,
    context: *FieldContext,

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self.context);
        self.context = undefined;
    }
};

pub fn bindSelect(allocator: std.mem.Allocator, store: *FormStore, name: []const u8) !SelectBinding {
    const view = store.fieldView(name) orelse return error.UnknownField;
    const ctx = try makeFieldContext(allocator, store, view.name);
    const context_ptr = ctxPtr(ctx);

    return SelectBinding{
        .field = view,
        .on_change = component.View.EventHandler{
            .event_name = "change",
            .handler = .{ .callback = handleSelectSetValue, .context = context_ptr },
        },
        .on_blur = component.View.EventHandler{
            .event_name = "blur",
            .handler = .{ .callback = handleMarkTouched, .context = context_ptr },
        },
        .allocator = allocator,
        .context = ctx,
    };
}

pub const CheckboxBinding = struct {
    field: FieldView,
    checked_attr: core.ReadSignal([]const u8),
    on_change: component.View.EventHandler,
    on_blur: component.View.EventHandler,
    allocator: std.mem.Allocator,
    context: *FieldContext,
    memo: core.MemoHandle([]const u8),
    memo_ctx: *CheckboxMemoContext,

    pub fn deinit(self: *@This()) void {
        self.memo.dispose();
        self.allocator.destroy(self.memo_ctx);
        self.allocator.destroy(self.context);
        self.memo_ctx = undefined;
        self.context = undefined;
    }
};

pub fn bindCheckbox(allocator: std.mem.Allocator, store: *FormStore, name: []const u8) !CheckboxBinding {
    const view = store.fieldView(name) orelse return error.UnknownField;
    const ctx = try makeFieldContext(allocator, store, view.name);
    const context_ptr = ctxPtr(ctx);

    const memo_ctx = try allocator.create(CheckboxMemoContext);
    memo_ctx.* = .{ .value = view.value };
    const memo = try core.createMemo([]const u8, allocator, computeCheckedAttr, memo_ctx);

    return CheckboxBinding{
        .field = view,
        .checked_attr = memo.read,
        .on_change = component.View.EventHandler{
            .event_name = "change",
            .handler = .{ .callback = handleCheckboxSetValue, .context = context_ptr },
        },
        .on_blur = component.View.EventHandler{
            .event_name = "blur",
            .handler = .{ .callback = handleMarkTouched, .context = context_ptr },
        },
        .allocator = allocator,
        .context = ctx,
        .memo = memo,
        .memo_ctx = memo_ctx,
    };
}

pub fn bindFormSubmit(allocator: std.mem.Allocator, store: *FormStore, options: FormSubmitOptions) !FormSubmitBinding {
    const ctx = try allocator.create(FormSubmitContext);
    ctx.* = .{ .store = store, .options = options };
    const context_ptr = submitCtxPtr(ctx);

    return FormSubmitBinding{
        .on_submit = component.View.EventHandler{
            .event_name = "submit",
            .handler = .{ .callback = handleFormSubmit, .context = context_ptr },
        },
        .allocator = allocator,
        .context = ctx,
    };
}

const testing = std.testing;

fn expectBoolSignal(signal: core.ReadSignal(bool), expected: bool) !void {
    const value = try signal.get();
    try testing.expect(value == expected);
}

fn expectStringSignal(signal: core.ReadSignal([]const u8), expected: []const u8) !void {
    const value = try signal.get();
    try testing.expectEqualStrings(expected, value);
}

test "registering a field exposes initial state" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "email", .initial = "" });

    const snapshot = store.snapshot();
    try testing.expect(!snapshot.dirty);
    try testing.expect(!snapshot.touched);
    try testing.expect(snapshot.valid);
    try testing.expect(!snapshot.validating);
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(store.validatingSignal(), false);

    const view = store.fieldView("email") orelse return error.TestUnexpectedResult;
    try expectStringSignal(view.value, "");
    try expectBoolSignal(view.dirty, false);
    try expectBoolSignal(view.touched, false);
    try expectBoolSignal(view.validating, false);
    try expectBoolSignal(view.valid, true);
    try expectStringSignal(view.error_message, "");
}

test "updating value marks field dirty and touched" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "email", .initial = "" });

    try store.setValue("email", "user@example.com");

    const view = store.fieldView("email") orelse return error.TestUnexpectedResult;
    try expectStringSignal(view.value, "user@example.com");
    try expectBoolSignal(view.dirty, true);
    try expectBoolSignal(view.touched, true);
    try expectBoolSignal(view.validating, false);

    const dirty = try store.dirtySignal().get();
    try testing.expect(dirty);

    const touched = try store.touchedSignal().get();
    try testing.expect(touched);
}

test "resetting field clears dirty and touched state" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "name", .initial = "Jane" });
    try store.setValue("name", "Janet");
    try store.resetField("name");

    const view = store.fieldView("name") orelse return error.TestUnexpectedResult;
    try expectStringSignal(view.value, "Jane");
    try expectBoolSignal(view.dirty, false);
    try expectBoolSignal(view.touched, false);
    try expectBoolSignal(view.validating, false);

    const snapshot = store.snapshot();
    try testing.expect(!snapshot.dirty);
    try testing.expect(!snapshot.touched);
    try testing.expect(snapshot.valid);
    try testing.expect(!snapshot.validating);
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(store.validatingSignal(), false);
}

test "validation adapter enforces min length" {
    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "password", .min = 8, .message = "Password too short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "password", .initial = "short" });

    var view = store.fieldView("password") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(view.valid, false);
    try expectBoolSignal(view.validating, false);
    try expectStringSignal(view.error_message, "Password too short");
    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(store.validatingSignal(), false);
    var snapshot = store.snapshot();
    try testing.expect(!snapshot.valid);
    try testing.expect(!snapshot.validating);

    try store.setValue("password", "longenough");

    view = store.fieldView("password") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(view.valid, true);
    try expectBoolSignal(view.validating, false);
    try expectStringSignal(view.error_message, "");
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(store.validatingSignal(), false);
    snapshot = store.snapshot();
    try testing.expect(snapshot.valid);
    try testing.expect(!snapshot.validating);
}

test "form valid signal tracks multiple fields" {
    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "first", .min = 3, .message = "too short" },
        .{ .field = "second", .min = 2, .message = "also short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "first", .initial = "" });
    try store.registerField(.{ .name = "second", .initial = "" });

    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(store.validatingSignal(), false);
    var snapshot = store.snapshot();
    try testing.expect(!snapshot.valid);
    try testing.expect(!snapshot.validating);

    try store.setValue("first", "abc");
    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(store.validatingSignal(), false);

    try store.setValue("second", "ok");
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(store.validatingSignal(), false);
    snapshot = store.snapshot();
    try testing.expect(snapshot.valid);
    try testing.expect(!snapshot.validating);

    const second_view = store.fieldView("second") orelse return error.TestUnexpectedResult;
    try expectStringSignal(second_view.error_message, "");
    try expectBoolSignal(second_view.validating, false);
}

test "store reset applies to all fields" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "email", .initial = "" });
    try store.registerField(.{ .name = "password", .initial = "" });

    try store.setValue("email", "user@example.com");
    try store.markTouched("password");

    try store.reset();

    const email = store.fieldView("email") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(email.dirty, false);
    try expectBoolSignal(email.touched, false);
    try expectBoolSignal(email.validating, false);

    const password = store.fieldView("password") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(password.dirty, false);
    try expectBoolSignal(password.touched, false);
    try expectBoolSignal(password.validating, false);

    const snapshot = store.snapshot();
    try testing.expect(!snapshot.dirty);
    try testing.expect(!snapshot.touched);
    try testing.expect(snapshot.valid);
    try testing.expect(!snapshot.validating);
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(store.validatingSignal(), false);
}

fn makeEvent(event_type: []const u8, payload: ?[]const u8) dom.SyntheticEvent {
    return .{
        .event_type = event_type,
        .target = 0,
        .current_target = 0,
        .bubbles = true,
        .detail_payload = payload,
        .detail_data = null,
    };
}

test "text binding updates value and touched state" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "email", .initial = "" });

    var binding = try bindTextInput(testing.allocator, &store, "email");
    defer binding.deinit();

    var input_event = makeEvent("input", "user@example.com");
    binding.on_input.handler.callback(&input_event, binding.on_input.handler.context);

    try expectStringSignal(binding.field.value, "user@example.com");
    try expectBoolSignal(binding.field.dirty, true);
    try expectBoolSignal(binding.field.touched, true);
    try expectBoolSignal(binding.field.validating, false);

    const form_dirty = try store.dirtySignal().get();
    try testing.expect(form_dirty);
}

test "text binding blur marks touched without change" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "username", .initial = "" });

    var binding = try bindTextInput(testing.allocator, &store, "username");
    defer binding.deinit();

    var blur_event = makeEvent("blur", null);
    binding.on_blur.handler.callback(&blur_event, binding.on_blur.handler.context);

    try expectBoolSignal(binding.field.touched, true);
    try expectBoolSignal(binding.field.dirty, false);
    try expectBoolSignal(binding.field.validating, false);
    const snapshot = store.snapshot();
    try testing.expect(snapshot.touched);
    try testing.expect(!snapshot.dirty);
    try testing.expect(!snapshot.validating);
}

test "select binding updates value via change event" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "country", .initial = "" });

    var binding = try bindSelect(testing.allocator, &store, "country");
    defer binding.deinit();

    var change_event = makeEvent("change", "ca");
    binding.on_change.handler.callback(&change_event, binding.on_change.handler.context);

    try expectStringSignal(binding.field.value, "ca");
    try expectBoolSignal(binding.field.dirty, true);
    try expectBoolSignal(binding.field.touched, true);
}

test "checkbox binding toggles value and checked attribute" {
    var store = try FormStore.init(testing.allocator, .{});
    defer store.deinit();

    try store.registerField(.{ .name = "newsletter", .initial = FALSE_STR });

    var binding = try bindCheckbox(testing.allocator, &store, "newsletter");
    defer binding.deinit();

    // initial state should be unchecked
    const initial_checked = try binding.memo.get();
    try testing.expectEqualStrings(EMPTY_ATTR, initial_checked);

    var change_event = makeEvent("change", TRUE_STR);
    binding.on_change.handler.callback(&change_event, binding.on_change.handler.context);

    try expectBoolSignal(binding.field.dirty, true);
    try expectBoolSignal(binding.field.touched, true);
    const after_checked = try binding.memo.get();
    try testing.expectEqualStrings(CHECKED_ATTR, after_checked);

    var toggle_event = makeEvent("change", null);
    binding.on_change.handler.callback(&toggle_event, binding.on_change.handler.context);
    const final_checked = try binding.memo.get();
    try testing.expectEqualStrings(EMPTY_ATTR, final_checked);
}

test "markAllTouched flags fields and revalidates" {
    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "username", .min = 3, .message = "too short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "username", .initial = "" });

    try store.markAllTouched();

    const view = store.fieldView("username") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(view.touched, true);
    try expectBoolSignal(store.touchedSignal(), true);
    try expectBoolSignal(view.valid, false);
    try expectBoolSignal(view.validating, false);
    try expectBoolSignal(store.validatingSignal(), false);
}

test "serialize produces field snapshot" {
    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "password", .min = 8, .message = "too short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "email", .initial = "" });
    try store.registerField(.{ .name = "password", .initial = "short" });
    try store.setValue("email", "user@example.com");

    var serialized = try store.serialize(testing.allocator);
    defer serialized.deinit();

    try testing.expectEqual(@as(usize, 2), serialized.len());

    var email_found = false;
    var password_found = false;
    for (serialized.values()) |field| {
        if (std.mem.eql(u8, field.name, "email")) {
            email_found = true;
            try testing.expect(std.mem.eql(u8, field.value, "user@example.com"));
            try testing.expect(field.dirty);
            try testing.expect(!field.touched);
            try testing.expect(field.valid);
            try testing.expect(!field.validating);
        } else if (std.mem.eql(u8, field.name, "password")) {
            password_found = true;
            try testing.expect(std.mem.eql(u8, field.value, "short"));
            try testing.expect(!field.dirty);
            try testing.expect(!field.valid);
            try testing.expect(field.error_message.len > 0);
            try testing.expect(!field.validating);
        }
    }

    try testing.expect(email_found and password_found);
}

test "async validation resolves outcomes" {
    const AsyncContext = struct {
        allocator: std.mem.Allocator,
        futures: std.ArrayList(*zsync.Future(ValidationOutcome)),

        fn create(allocator: std.mem.Allocator) !*@This() {
            const ctx = try allocator.create(@This());
            errdefer allocator.destroy(ctx);
            ctx.* = .{
                .allocator = allocator,
                .futures = std.ArrayList(*zsync.Future(ValidationOutcome)).init(allocator),
            };
            return ctx;
        }

        fn destroy(self: *@This()) void {
            for (self.futures.items) |future| {
                future.cancel();
                future.deinit();
            }
            self.futures.deinit();
            self.allocator.destroy(self);
        }

        fn validate(_: []const u8, _: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const ctx = @as(*@This(), @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            if (ctx.futures.popOrNull()) |future| {
                return ValidationResult{ .future = AsyncValidation{ .future = future } };
            }
            return ValidationResult{ .immediate = ValidationOutcome{} };
        }

        fn deinitContext(_: std.mem.Allocator, ctx_ptr: ?*anyopaque) void {
            if (ctx_ptr) |ptr| {
                @as(*@This(), @ptrFromInt(@intFromPtr(ptr))).destroy();
            }
        }
    };

    var ctx = try AsyncContext.create(testing.allocator);
    var ctx_cleanup = true;
    defer if (ctx_cleanup) ctx.destroy();

    var store = try FormStore.init(testing.allocator, .{
        .validation = .{
            .validateField = AsyncContext.validate,
            .deinitContext = AsyncContext.deinitContext,
            .context = ctx,
        },
    });
    defer store.deinit();
    ctx_cleanup = false;

    const first_future = try zsync.Future(ValidationOutcome).init(testing.allocator);
    try ctx.futures.append(first_future);

    try store.registerField(.{ .name = "username", .initial = "" });

    const view = store.fieldView("username") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(store.validatingSignal(), true);
    try expectBoolSignal(view.validating, true);
    try expectBoolSignal(view.valid, false);
    try expectStringSignal(view.error_message, "");

    first_future.resolve(.{ .valid = true, .message = null });
    try store.tickAsyncValidations();

    try expectBoolSignal(store.validatingSignal(), false);
    try expectBoolSignal(store.validSignal(), true);
    try expectBoolSignal(view.validating, false);
    try expectBoolSignal(view.valid, true);

    const second_future = try zsync.Future(ValidationOutcome).init(testing.allocator);
    try ctx.futures.append(second_future);

    try store.setValue("username", "taken");
    try expectBoolSignal(store.validatingSignal(), true);
    try expectBoolSignal(view.validating, true);

    second_future.resolve(.{ .valid = false, .message = "Name already used" });
    try store.tickAsyncValidations();

    try expectBoolSignal(store.validatingSignal(), false);
    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(view.validating, false);
    try expectBoolSignal(view.valid, false);
    try expectStringSignal(view.error_message, "Name already used");
}

test "async validation cancellation replaces pending outcome" {
    const AsyncContext = struct {
        allocator: std.mem.Allocator,
        futures: std.ArrayList(*zsync.Future(ValidationOutcome)),

        fn create(allocator: std.mem.Allocator) !*@This() {
            const ctx = try allocator.create(@This());
            errdefer allocator.destroy(ctx);
            ctx.* = .{
                .allocator = allocator,
                .futures = std.ArrayList(*zsync.Future(ValidationOutcome)).init(allocator),
            };
            return ctx;
        }

        fn destroy(self: *@This()) void {
            for (self.futures.items) |future| {
                future.cancel();
                future.deinit();
            }
            self.futures.deinit();
            self.allocator.destroy(self);
        }

        fn validate(_: []const u8, _: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const ctx = @as(*@This(), @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            if (ctx.futures.popOrNull()) |future| {
                return ValidationResult{ .future = AsyncValidation{ .future = future } };
            }
            return ValidationResult{ .immediate = ValidationOutcome{} };
        }

        fn deinitContext(_: std.mem.Allocator, ctx_ptr: ?*anyopaque) void {
            if (ctx_ptr) |ptr| {
                @as(*@This(), @ptrFromInt(@intFromPtr(ptr))).destroy();
            }
        }
    };

    var ctx = try AsyncContext.create(testing.allocator);
    var ctx_cleanup = true;
    defer if (ctx_cleanup) ctx.destroy();

    var store = try FormStore.init(testing.allocator, .{
        .validation = .{
            .validateField = AsyncContext.validate,
            .deinitContext = AsyncContext.deinitContext,
            .context = ctx,
        },
    });
    defer store.deinit();
    ctx_cleanup = false;

    const first_future = try zsync.Future(ValidationOutcome).init(testing.allocator);
    try ctx.futures.append(first_future);

    try store.registerField(.{ .name = "username", .initial = "" });
    try expectBoolSignal(store.validatingSignal(), true);
    const view = store.fieldView("username") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(view.validating, true);
    try testing.expectEqual(@as(usize, 1), store.pending_async.items.len);
    const initial_future_addr = @intFromPtr(store.pending_async.items[0].future);

    const second_future = try zsync.Future(ValidationOutcome).init(testing.allocator);
    try ctx.futures.append(second_future);

    try store.setValue("username", "next");

    try testing.expectEqual(@as(usize, 1), store.pending_async.items.len);
    const active_future_addr = @intFromPtr(store.pending_async.items[0].future);
    try testing.expect(active_future_addr != initial_future_addr);
    try expectBoolSignal(store.validatingSignal(), true);
    try expectBoolSignal(view.validating, true);
    try expectStringSignal(view.error_message, "");

    second_future.resolve(.{ .valid = false, .message = "Still taken" });
    try store.tickAsyncValidations();

    try expectBoolSignal(store.validatingSignal(), false);
    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(view.validating, false);
    try expectBoolSignal(view.valid, false);
    try expectStringSignal(view.error_message, "Still taken");
}

test "validation batches coalesce adapter calls" {
    const CountingContext = struct {
        count: usize = 0,

        fn validate(_: []const u8, _: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const ctx = @as(*@This(), @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.count += 1;
            return ValidationResult{ .immediate = ValidationOutcome{} };
        }
    };

    var ctx = CountingContext{};

    var store = try FormStore.init(testing.allocator, .{
        .validation = .{
            .validateField = CountingContext.validate,
            .deinitContext = null,
            .context = @as(*anyopaque, @ptrCast(&ctx)),
        },
    });
    defer store.deinit();

    try store.registerField(.{ .name = "username", .initial = "" });
    ctx.count = 0;

    var batch = store.beginValidationBatch();
    defer batch.deinit();

    try store.setValue("username", "a");
    try store.setValue("username", "ab");
    try store.setValue("username", "abc");

    try testing.expectEqual(@as(usize, 0), ctx.count);

    try batch.finish();

    try testing.expectEqual(@as(usize, 1), ctx.count);
    try expectStringSignal(store.fieldView("username").?.value, "abc");

    ctx.count = 0;
    try store.setValue("username", "abcd");
    try testing.expectEqual(@as(usize, 1), ctx.count);
}

test "validation debouncer delays until tick" {
    const CountingContext = struct {
        count: usize = 0,

        fn validate(_: []const u8, _: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const ctx = @as(*@This(), @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.count += 1;
            return ValidationResult{ .immediate = ValidationOutcome{} };
        }
    };

    const TestClock = struct {
        var now: i128 = 0;

        fn nowFn() i128 {
            return now;
        }
    };

    var ctx = CountingContext{};

    var store = try FormStore.init(testing.allocator, .{
        .validation = .{
            .validateField = CountingContext.validate,
            .deinitContext = null,
            .context = @as(*anyopaque, @ptrCast(&ctx)),
        },
    });
    defer store.deinit();

    try store.registerField(.{ .name = "username", .initial = "" });
    ctx.count = 0;

    var debouncer = FormStore.ValidationDebouncer.init(&store, 10, TestClock.nowFn);

    TestClock.now = 0;
    debouncer.touch();
    try store.setValue("username", "a");
    try store.setValue("username", "ab");
    try testing.expectEqual(@as(usize, 0), ctx.count);

    TestClock.now = 9;
    try debouncer.tick();
    try testing.expectEqual(@as(usize, 0), ctx.count);

    TestClock.now = 10;
    try debouncer.tick();
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 15;
    debouncer.touch();
    try store.setValue("username", "abc");
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 24;
    try debouncer.tick();
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 25;
    try debouncer.tick();
    try testing.expectEqual(@as(usize, 2), ctx.count);

    debouncer.cancel();
}

test "validation throttler limits validation frequency" {
    const CountingContext = struct {
        count: usize = 0,

        fn validate(_: []const u8, _: []const u8, _: std.mem.Allocator, ctx_ptr: ?*anyopaque) anyerror!ValidationResult {
            const ctx = @as(*@This(), @ptrFromInt(@intFromPtr(ctx_ptr.?)));
            ctx.count += 1;
            return ValidationResult{ .immediate = ValidationOutcome{} };
        }
    };

    const TestClock = struct {
        var now: i128 = 0;

        fn nowFn() i128 {
            return now;
        }
    };

    var ctx = CountingContext{};

    var store = try FormStore.init(testing.allocator, .{
        .validation = .{
            .validateField = CountingContext.validate,
            .deinitContext = null,
            .context = @as(*anyopaque, @ptrCast(&ctx)),
        },
    });
    defer store.deinit();

    try store.registerField(.{ .name = "username", .initial = "" });
    ctx.count = 0;

    var throttler = FormStore.ValidationThrottler.init(&store, 10, TestClock.nowFn);

    TestClock.now = 0;
    throttler.touch();
    try store.setValue("username", "first");
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 5;
    throttler.touch();
    try store.setValue("username", "second");
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 8;
    throttler.touch();
    try store.setValue("username", "third");
    try testing.expectEqual(@as(usize, 1), ctx.count);

    TestClock.now = 10;
    try throttler.tick();
    try testing.expectEqual(@as(usize, 2), ctx.count);

    TestClock.now = 15;
    throttler.touch();
    try store.setValue("username", "fourth");
    try testing.expectEqual(@as(usize, 2), ctx.count);

    TestClock.now = 21;
    try throttler.tick();
    try testing.expectEqual(@as(usize, 3), ctx.count);

    throttler.cancel();
}

test "form submit binding prevents default when invalid" {
    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "password", .min = 8, .message = "too short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "password", .initial = "" });

    var binding = try bindFormSubmit(testing.allocator, &store, .{});
    defer binding.deinit();

    var submit_event = makeEvent("submit", null);
    binding.on_submit.handler.callback(&submit_event, binding.on_submit.handler.context);

    try testing.expect(submit_event.isDefaultPrevented());
    const view = store.fieldView("password") orelse return error.TestUnexpectedResult;
    try expectBoolSignal(view.touched, true);
    try expectBoolSignal(store.validSignal(), false);
    try expectBoolSignal(store.validatingSignal(), false);
}

test "form submit binding triggers callbacks" {
    const Counts = struct {
        valid: usize = 0,
        invalid: usize = 0,
    };

    const Callbacks = struct {
        fn onValid(_: *FormStore, data: ?*anyopaque) anyerror!void {
            const counts = @as(*Counts, @ptrFromInt(@intFromPtr(data.?)));
            counts.valid += 1;
        }

        fn onInvalid(_: *FormStore, data: ?*anyopaque) anyerror!void {
            const counts = @as(*Counts, @ptrFromInt(@intFromPtr(data.?)));
            counts.invalid += 1;
        }
    };

    var adapter = try createZSchemaMinLengthAdapter(testing.allocator, &[_]ZSchemaMinLengthRule{
        .{ .field = "password", .min = 4, .message = "short" },
    });
    errdefer adapter.deinit(testing.allocator);

    var store = try FormStore.init(testing.allocator, .{ .validation = adapter });
    defer store.deinit();

    try store.registerField(.{ .name = "password", .initial = "" });

    var counts = Counts{};
    const data_ptr = @as(?*anyopaque, @ptrFromInt(@intFromPtr(&counts)));

    var binding = try bindFormSubmit(testing.allocator, &store, .{
        .on_valid = Callbacks.onValid,
        .on_invalid = Callbacks.onInvalid,
        .user_data = data_ptr,
    });
    defer binding.deinit();

    var first_event = makeEvent("submit", null);
    binding.on_submit.handler.callback(&first_event, binding.on_submit.handler.context);
    try testing.expect(first_event.isDefaultPrevented());
    try testing.expectEqual(@as(usize, 0), counts.valid);
    try testing.expectEqual(@as(usize, 1), counts.invalid);

    try store.setValue("password", "okay");

    var second_event = makeEvent("submit", null);
    binding.on_submit.handler.callback(&second_event, binding.on_submit.handler.context);
    try testing.expect(!second_event.isDefaultPrevented());
    try testing.expectEqual(@as(usize, 1), counts.valid);
    try testing.expectEqual(@as(usize, 1), counts.invalid);
}
