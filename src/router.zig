/// Client-side routing for Ripple applications.
///
/// Provides hash-based routing with route matching, parameters,
/// and navigation APIs.
///
/// Example:
/// ```zig
/// const router = try Router.init(allocator, &[_]Route{
///     Route.init("/", homeView),
///     Route.init("/users/:id", userView),
///     Route.init("/about", aboutView),
/// });
/// defer router.deinit();
/// ```
const std = @import("std");
const core = @import("core.zig");
const component = @import("component.zig");
const builtin = @import("builtin");
const history_mod = @import("router/history.zig");
pub const manifest = @import("router/manifest.zig");
pub const history = history_mod;

const is_wasm = builtin.target.cpu.arch.isWasm();

pub const RouteLoaderFn = *const fn (std.mem.Allocator) anyerror!Route;

/// Route represents a single route configuration.
/// RouteParams holds path and query parameters.
pub const RouteParams = struct {
    path_params: std.StringHashMap([]const u8),
    query_params: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RouteParams {
        return .{
            .path_params = std.StringHashMap([]const u8).init(allocator),
            .query_params = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RouteParams) void {
        var it = self.path_params.iterator();
        while (it.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
            self.allocator.free(@constCast(entry.value_ptr.*));
        }
        self.path_params.deinit();

        var qit = self.query_params.iterator();
        while (qit.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
            self.allocator.free(@constCast(entry.value_ptr.*));
        }
        self.query_params.deinit();
    }

    pub fn getPathParam(self: RouteParams, name: []const u8) ?[]const u8 {
        return self.path_params.get(name);
    }

    pub fn getQueryParam(self: RouteParams, name: []const u8) ?[]const u8 {
        return self.query_params.get(name);
    }
};

pub const GuardPhase = enum { before_each, before_enter };

pub const GuardDecision = union(enum) {
    allow,
    redirect: []const u8,
    reject: []const u8,
};

pub const GuardContext = struct {
    allocator: std.mem.Allocator,
    from: []const u8,
    to: []const u8,
    params: ?*const RouteParams,
    route: ?*const Route,
};

pub const GuardHandler = *const fn (GuardContext, ?*anyopaque) anyerror!GuardDecision;

/// RouteGuard represents middleware hooks at various navigation phases.
pub const RouteGuard = struct {
    name: []const u8,
    phase: GuardPhase,
    handler: GuardHandler,
    user_data: ?*anyopaque = null,

    pub fn init(name: []const u8, handler: GuardHandler) RouteGuard {
        return .{
            .name = name,
            .phase = .before_enter,
            .handler = handler,
            .user_data = null,
        };
    }

    pub fn beforeEach(name: []const u8, handler: GuardHandler) RouteGuard {
        return .{
            .name = name,
            .phase = .before_each,
            .handler = handler,
            .user_data = null,
        };
    }

    pub fn withUserData(self: RouteGuard, data: ?*anyopaque) RouteGuard {
        var copy = self;
        copy.user_data = data;
        return copy;
    }
};

pub const Route = struct {
    path: []const u8,
    view_fn: *const fn (RouteParams, std.mem.Allocator) anyerror!component.View,
    guards: []const RouteGuard = &.{},

    pub fn init(
        path: []const u8,
        view_fn: *const fn (RouteParams, std.mem.Allocator) anyerror!component.View,
    ) Route {
        return .{
            .path = path,
            .view_fn = view_fn,
        };
    }

    /// Add route guards (middleware).
    pub fn withGuards(self: Route, guards: []const RouteGuard) Route {
        return .{
            .path = self.path,
            .view_fn = self.view_fn,
            .guards = guards,
        };
    }
};

/// RouteMatch represents a matched route with parameters.
pub const RouteMatch = struct {
    route: *const Route,
    params: RouteParams,

    pub fn deinit(self: *RouteMatch) void {
        self.params.deinit();
    }
};

/// Router manages application routes and navigation.
pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: std.ArrayList(Route),
    lazy_loaders: std.ArrayList(LazyLoader),
    before_each_guards: std.ArrayList(RouteGuard),
    current_path: core.SignalPair([]const u8),
    current_match: ?RouteMatch,
    history: history_mod.HistoryManager,
    fallback_view: ?*const fn (std.mem.Allocator) anyerror!component.View,

    pub fn init(
        allocator: std.mem.Allocator,
        routes: []const Route,
    ) !Router {
        const path_signal = try core.createSignal([]const u8, allocator, "/");

        var route_list = std.ArrayList(Route).init(allocator);
        errdefer route_list.deinit();
        for (routes) |route| {
            try route_list.append(route);
        }

        var history_mgr = history_mod.HistoryManager.init(allocator);
        errdefer history_mgr.deinit();

        return .{
            .allocator = allocator,
            .routes = route_list,
            .lazy_loaders = std.ArrayList(LazyLoader).init(allocator),
            .before_each_guards = std.ArrayList(RouteGuard).init(allocator),
            .current_path = path_signal,
            .current_match = null,
            .history = history_mgr,
            .fallback_view = null,
        };
    }

    pub fn deinit(self: *Router) void {
        self.current_path.dispose();
        if (self.current_match) |*match| {
            match.deinit();
        }
        self.routes.deinit();
        for (self.lazy_loaders.items) |loader| {
            self.allocator.free(loader.pattern);
        }
        self.lazy_loaders.deinit();
        self.before_each_guards.deinit();
        self.history.deinit();
    }

    /// Set a fallback view for 404 Not Found.
    pub fn setFallback(
        self: *Router,
        fallback: *const fn (std.mem.Allocator) anyerror!component.View,
    ) void {
        self.fallback_view = fallback;
    }

    /// Navigate to a new path.
    pub fn navigate(self: *Router, path: []const u8) !void {
        const previous_path = self.current_path.read.peek();
        try self.ensureLazyRoute(path);

        var pending_match = try self.matchRoute(path);

        const match_ptr: ?*RouteMatch = blk: {
            if (pending_match) |*m| break :blk m;
            break :blk null;
        };

        const decision = try self.runGuardPipeline(previous_path, path, match_ptr);

        switch (decision) {
            .allow => {
                try self.history.captureCurrent(previous_path);

                if (is_wasm) {
                    updateLocationHash(path);
                }

                try self.current_path.write.set(path);
                self.history.restoreForPath(path);

                if (self.current_match) |*match| {
                    match.deinit();
                }

                self.current_match = pending_match;
                pending_match = null;
            },
            .redirect => |target| {
                if (pending_match) |*match| match.deinit();
                if (std.mem.eql(u8, target, path)) return;
                return self.navigate(target);
            },
            .reject => |_| {
                if (pending_match) |*match| match.deinit();
            },
        }

        if (pending_match) |*match| match.deinit();
    }

    /// Inform the router about the latest viewport scroll offsets.
    pub fn updateScrollPosition(self: *Router, position: history_mod.ScrollPosition) void {
        self.history.updateScroll(position);
    }

    /// Returns the last scroll offsets restored or recorded by the router.
    pub fn currentScrollPosition(self: *Router) history_mod.ScrollPosition {
        return self.history.currentScroll();
    }

    /// Get the current path signal for reactive updates.
    pub fn pathSignal(self: Router) core.ReadSignal([]const u8) {
        return self.current_path.read;
    }

    /// Match a route against the current path.
    fn matchRoute(self: *Router, path: []const u8) !?RouteMatch {
        for (self.routes.items) |*route| {
            if (try self.matches(route, path)) |params| {
                return RouteMatch{
                    .route = route,
                    .params = params,
                };
            }
        }
        return null;
    }

    pub fn registerLazyRoute(self: *Router, pattern: []const u8, loader: RouteLoaderFn) !void {
        const pattern_copy = try self.allocator.dupe(u8, pattern);
        errdefer self.allocator.free(pattern_copy);
        try self.lazy_loaders.append(.{
            .pattern = pattern_copy,
            .loader = loader,
            .loaded = false,
        });
    }

    pub fn registerGuard(self: *Router, guard: RouteGuard) !void {
        switch (guard.phase) {
            .before_each => try self.before_each_guards.append(guard),
            .before_enter => return error.InvalidGuardPhase,
        }
    }

    fn ensureLazyRoute(self: *Router, path: []const u8) !void {
        for (self.lazy_loaders.items) |*lazy| {
            if (lazy.loaded) continue;
            if (!patternMatches(lazy.pattern, path)) continue;

            const route = try lazy.loader(self.allocator);
            try self.routes.append(route);
            lazy.loaded = true;
        }
    }

    fn runGuardPipeline(
        self: *Router,
        from_path: []const u8,
        to_path: []const u8,
        match: ?*RouteMatch,
    ) !GuardDecision {
        const context = GuardContext{
            .allocator = self.allocator,
            .from = from_path,
            .to = to_path,
            .params = if (match) |m| &m.params else null,
            .route = if (match) |m| m.route else null,
        };

        for (self.before_each_guards.items) |guard| {
            if (guard.phase != .before_each) continue;
            const decision = try guard.handler(context, guard.user_data);
            switch (decision) {
                .allow => continue,
                else => return decision,
            }
        }

        if (match) |route_match| {
            for (route_match.route.guards) |guard| {
                if (guard.phase != .before_enter) continue;
                const decision = try guard.handler(context, guard.user_data);
                switch (decision) {
                    .allow => continue,
                    else => return decision,
                }
            }
        }

        return .allow;
    }

    /// Check if a route matches the path and extract parameters.
    fn matches(self: *Router, route: *const Route, path: []const u8) !?RouteParams {
        var params = RouteParams.init(self.allocator);
        var keep_params = false;
        defer if (!keep_params) params.deinit();

        // Split path and route pattern into segments
        var path_parts = std.mem.splitScalar(u8, path, '/');
        var route_parts = std.mem.splitScalar(u8, route.path, '/');

        while (true) {
            const path_segment = path_parts.next();
            const route_segment = route_parts.next();

            if (path_segment == null and route_segment == null) {
                keep_params = true;
                return params; // Perfect match
            }

            if (path_segment == null or route_segment == null) {
                return null; // Length mismatch
            }

            // Check for parameter (starts with :)
            if (route_segment.?.len > 0 and route_segment.?[0] == ':') {
                const param_name = route_segment.?[1..];
                const param_value = path_segment.?;
                try params.path_params.put(
                    try self.allocator.dupe(u8, param_name),
                    try self.allocator.dupe(u8, param_value),
                );
                continue;
            }

            // Exact match required
            if (!std.mem.eql(u8, path_segment.?, route_segment.?)) {
                return null;
            }
        }
    }

    /// Get the current view based on the matched route.
    pub fn currentView(self: *Router) !?component.View {
        if (self.current_match) |match| {
            return try match.route.view_fn(match.params, self.allocator);
        }

        if (self.fallback_view) |fallback| {
            return try fallback(self.allocator);
        }

        return null;
    }
};

const LazyLoader = struct {
    pattern: []u8,
    loader: RouteLoaderFn,
    loaded: bool,
};

fn patternMatches(pattern: []const u8, path: []const u8) bool {
    var pat_iter = std.mem.splitScalar(u8, pattern, '/');
    var path_iter = std.mem.splitScalar(u8, path, '/');

    while (true) {
        const pat_seg = nextSegment(&pat_iter);
        const path_seg = nextSegment(&path_iter);

        if (pat_seg == null and path_seg == null) return true;
        if (pat_seg == null) return false;
        if (path_seg == null) {
            const seg = pat_seg.?;
            return seg.len != 0 and seg[0] == '*';
        }

        const seg = pat_seg.?;
        if (seg.len != 0 and seg[0] == '*') return true;
        if (seg.len != 0 and seg[0] == ':') continue;
        if (!std.mem.eql(u8, seg, path_seg.?)) return false;
    }
}

fn nextSegment(iter: *std.mem.SplitIterator(u8)) ?[]const u8 {
    while (iter.next()) |segment| {
        if (segment.len == 0) continue;
        return segment;
    }
    return null;
}

// WASM host functions for browser navigation
const Host = if (is_wasm) struct {
    extern "env" fn ripple_router_get_hash(ptr: *[*]const u8, len: *usize) void;
    extern "env" fn ripple_router_set_hash(ptr: [*]const u8, len: usize) void;
} else struct {};

fn updateLocationHash(path: []const u8) void {
    if (is_wasm) {
        Host.ripple_router_set_hash(path.ptr, path.len);
    } else {
        std.debug.print("[router] navigate to {s}\n", .{path});
    }
}

/// Link component for navigation.
pub const Link = struct {
    router: *Router,
    to: []const u8,
    children: []const component.View,

    pub fn init(
        router: *Router,
        to: []const u8,
        children: []const component.View,
    ) Link {
        return .{
            .router = router,
            .to = to,
            .children = children,
        };
    }

    pub fn view(self: Link, allocator: std.mem.Allocator) !component.View {
        const builder = component.ViewBuilder.init(allocator);

        // Create click handler
        const handler = component.View.EventHandler{
            .event_name = "click",
            .handler = .{
                .callback = struct {
                    fn onClick(ev: *@import("dom.zig").SyntheticEvent, ctx: ?*anyopaque) void {
                        ev.preventDefault();
                        const link_ctx = @as(*Link, @ptrFromInt(@intFromPtr(ctx.?)));
                        link_ctx.router.navigate(link_ctx.to) catch unreachable;
                    }
                }.onClick,
                .context = @as(?*anyopaque, @ptrCast(@constCast(&self))),
            },
        };

        const attrs = [_]component.View.Attribute{
            try builder.attr("href", try std.fmt.allocPrint(allocator, "#{s}", .{self.to})),
        };

        return component.View{
            .element = .{
                .tag = try allocator.dupe(u8, "a"),
                .attrs = try allocator.dupe(component.View.Attribute, &attrs),
                .children = try allocator.dupe(component.View, self.children),
                .event_handlers = &[_]component.View.EventHandler{handler},
            },
        };
    }
};

// Test helper functions
fn testDummyView(_: RouteParams, alloc: std.mem.Allocator) !component.View {
    const builder = component.ViewBuilder.init(alloc);
    return try builder.text("dummy");
}

fn testHomeView(_: RouteParams, alloc: std.mem.Allocator) !component.View {
    const builder = component.ViewBuilder.init(alloc);
    return try builder.text("Home");
}

fn testProtectedView(_: RouteParams, alloc: std.mem.Allocator) !component.View {
    const builder = component.ViewBuilder.init(alloc);
    return try builder.text("Protected");
}

fn testAuthGuard(_: GuardContext, _: ?*anyopaque) anyerror!GuardDecision {
    return GuardDecision{ .reject = "unauthorized" };
}

fn testRedirectGuard(context: GuardContext, _: ?*anyopaque) anyerror!GuardDecision {
    if (std.mem.eql(u8, context.to, "/private")) {
        return GuardDecision{ .redirect = "/login" };
    }
    return GuardDecision.allow;
}

fn testAllowGuard(_: GuardContext, _: ?*anyopaque) anyerror!GuardDecision {
    return GuardDecision.allow;
}

fn lazyRouteView(_: RouteParams, alloc: std.mem.Allocator) !component.View {
    const builder = component.ViewBuilder.init(alloc);
    return try builder.text("Lazy");
}

var lazy_loader_invocations: usize = 0;

fn loadLazyRoute(_: std.mem.Allocator) anyerror!Route {
    lazy_loader_invocations += 1;
    return Route.init("/lazy", lazyRouteView);
}

test "route matching extracts parameters" {
    const allocator = std.testing.allocator;

    const routes = [_]Route{
        Route.init("/users/:id", testDummyView),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    var match = (try router.matchRoute("/users/123")).?;
    defer match.deinit();

    const id = match.params.getPathParam("id");
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("123", id.?);
}

test "router navigation updates current path" {
    const allocator = std.testing.allocator;

    const routes = [_]Route{
        Route.init("/", testHomeView),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    try router.navigate("/");

    const path = try router.pathSignal().get();
    try std.testing.expectEqualStrings("/", path);
}

test "route guards can block navigation" {
    const allocator = std.testing.allocator;

    const authGuard = RouteGuard.init("auth", testAuthGuard);

    const routes = [_]Route{
        Route.init("/protected", testProtectedView).withGuards(&[_]RouteGuard{authGuard}),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    try router.navigate("/protected");

    try std.testing.expect(router.current_match == null);
    const path = try router.pathSignal().get();
    try std.testing.expectEqualStrings("/", path);
}

test "beforeEach guard can redirect navigation" {
    const allocator = std.testing.allocator;

    const routes = [_]Route{
        Route.init("/", testHomeView),
        Route.init("/login", testHomeView),
        Route.init("/private", testProtectedView),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    try router.registerGuard(RouteGuard.beforeEach("auth-redirect", testRedirectGuard));

    try router.navigate("/private");

    const path = try router.pathSignal().get();
    try std.testing.expectEqualStrings("/login", path);
}

test "lazy route loader registers routes on demand" {
    const allocator = std.testing.allocator;

    lazy_loader_invocations = 0;

    var router = try Router.init(allocator, &[_]Route{});
    defer router.deinit();

    try router.registerLazyRoute("/lazy", loadLazyRoute);

    try router.navigate("/lazy");

    try std.testing.expectEqual(@as(usize, 1), lazy_loader_invocations);
    try std.testing.expect(router.current_match != null);

    try router.navigate("/lazy");
    try std.testing.expectEqual(@as(usize, 1), lazy_loader_invocations);
}

test "router restores scroll positions across navigations" {
    const allocator = std.testing.allocator;

    const routes = [_]Route{
        Route.init("/", testHomeView),
        Route.init("/about", testHomeView),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    router.updateScrollPosition(.{ .x = 0, .y = 180 });
    try router.navigate("/");
    try std.testing.expectEqual(@as(i32, 180), router.currentScrollPosition().y);

    router.updateScrollPosition(.{ .x = 0, .y = 32 });
    try router.navigate("/about");
    try std.testing.expectEqual(@as(i32, 0), router.currentScrollPosition().y);

    router.updateScrollPosition(.{ .x = 0, .y = 64 });
    try router.navigate("/");
    try std.testing.expectEqual(@as(i32, 32), router.currentScrollPosition().y);
}
