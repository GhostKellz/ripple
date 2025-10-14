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

const is_wasm = builtin.target.cpu.arch.isWasm();

/// Route represents a single route configuration.
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

/// RouteGuard is middleware that can prevent navigation.
pub const RouteGuard = struct {
    name: []const u8,
    check_fn: *const fn (RouteParams) bool,

    pub fn init(
        name: []const u8,
        check_fn: *const fn (RouteParams) bool,
    ) RouteGuard {
        return .{
            .name = name,
            .check_fn = check_fn,
        };
    }
};

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
    routes: []const Route,
    current_path: core.SignalPair([]const u8),
    current_match: ?RouteMatch,
    fallback_view: ?*const fn (std.mem.Allocator) anyerror!component.View,

    pub fn init(
        allocator: std.mem.Allocator,
        routes: []const Route,
    ) !Router {
        const path_signal = try core.createSignal([]const u8, allocator, "/");

        return .{
            .allocator = allocator,
            .routes = try allocator.dupe(Route, routes),
            .current_path = path_signal,
            .current_match = null,
            .fallback_view = null,
        };
    }

    pub fn deinit(self: *Router) void {
        self.current_path.dispose();
        if (self.current_match) |*match| {
            match.deinit();
        }
        self.allocator.free(self.routes);
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
        if (is_wasm) {
            // Update browser hash
            updateLocationHash(path);
        }

        try self.current_path.write.set(path);

        // Match the route
        if (self.current_match) |*match| {
            match.deinit();
        }
        self.current_match = try self.matchRoute(path);
    }

    /// Get the current path signal for reactive updates.
    pub fn pathSignal(self: Router) core.ReadSignal([]const u8) {
        return self.current_path.read;
    }

    /// Match a route against the current path.
    fn matchRoute(self: *Router, path: []const u8) !?RouteMatch {
        for (self.routes) |*route| {
            if (try self.matches(route, path)) |params| {
                // Check guards
                var passed = true;
                for (route.guards) |guard| {
                    if (!guard.check_fn(params)) {
                        passed = false;
                        params.deinit();
                        break;
                    }
                }

                if (passed) {
                    return RouteMatch{
                        .route = route,
                        .params = params,
                    };
                }
            }
        }
        return null;
    }

    /// Check if a route matches the path and extract parameters.
    fn matches(self: *Router, route: *const Route, path: []const u8) !?RouteParams {
        var params = RouteParams.init(self.allocator);
        errdefer params.deinit();

        // Split path and route pattern into segments
        var path_parts = std.mem.splitScalar(u8, path, '/');
        var route_parts = std.mem.splitScalar(u8, route.path, '/');

        while (true) {
            const path_segment = path_parts.next();
            const route_segment = route_parts.next();

            if (path_segment == null and route_segment == null) {
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

fn testAuthGuardCheck(_: RouteParams) bool {
    return false; // Always block
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

    const authGuard = RouteGuard.init("auth", testAuthGuardCheck);

    const routes = [_]Route{
        Route.init("/protected", testProtectedView).withGuards(&[_]RouteGuard{authGuard}),
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    try router.navigate("/protected");

    try std.testing.expect(router.current_match == null);
}
