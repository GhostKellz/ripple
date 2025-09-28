<div align="center">
  <img src="assets/icons/ripple-logo.png" alt="Ripple Logo" width="200" />
</div>

# Ripple

[![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-F7A41D?style=flat-square&logo=zig)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-FF6600?style=flat-square)](https://ziglang.org/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-654FF0?style=flat-square&logo=webassembly&logoColor=white)](https://webassembly.org/)
[![Reactive UI](https://img.shields.io/badge/Reactive-UI-00D8FF?style=flat-square)](https://github.com/)

Reactive, WASM-first web UI framework for Zig. Bringing Leptos/Yew-style ergonomics with Zig's comptime power, zero C dependencies, and exceptional developer experience.

## ✨ Features

- 🚀 **WASM-First**: Built from the ground up for WebAssembly
- ⚡ **Reactive**: Fine-grained reactivity with signals and effects
- 🔧 **Zero C Dependencies**: Pure Zig implementation
- 🎯 **Leptos/Yew Inspired**: Familiar ergonomics for web developers
- 🛠️ **Comptime Powered**: Leverage Zig's compile-time capabilities
- 🏝️ **Islands Architecture**: Server-side rendering with selective hydration
- 🧠 **Batched Scheduler**: Microtask queue with `beginBatch` and `batch`
- 🪄 **DOM Bindings (Alpha)**: `bindText` host bridge for WASM environments

## 🎯 Goals

- Full WebAssembly support with optimal performance
- Leptos/Yew-style reactivity and component model
- Exceptional developer experience with hot module reloading
- Server-side rendering with islands architecture
- Zero runtime dependencies beyond the browser

## 🚧 Status

Ripple is in early development. The first milestone ships a prototype reactive core—signals, effects, derived memos, and a microtask scheduler—plus an alpha DOM text binding ready for WASM hosts. Next up: template compilation and a full hydration pipeline.

## 🚀 Quickstart

Ripple exposes its core runtime from `@import("ripple")`. Here's a tiny counter you can run with `zig build run`:

```zig
const std = @import("std");
const ripple = @import("ripple");

pub fn main() !void {
  var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
  defer arena.deinit();
  const allocator = arena.allocator();

  var counter = try ripple.createSignal(i32, allocator, 0);
  defer counter.dispose();

  const Context = struct { read: ripple.ReadSignal(i32) };
  var ctx = Context{ .read = counter.read };

  var effect = try ripple.createEffect(allocator, struct {
    fn run(scope: *ripple.EffectContext) anyerror!void {
      const data = scope.userData(Context).?;
      const value = try data.read.get();
      std.debug.print("count = {}\n", .{value});
    }
  }.run, &ctx);
  defer effect.dispose();

  try counter.write.set(1);
  try counter.write.set(2);
}
```

The counter logs `0`, `1`, and `2`—demonstrating dependency tracking, synchronous flushing, and allocator-backed cleanup.

## 🧵 Batching updates

Batch reactive writes and flush once at the end of the transaction:

```zig
var guard = ripple.beginBatch();
defer guard.deinit();
try counter.write.set(41);
try counter.write.set(42);
try guard.commit();
```

Use `ripple.batch` if you prefer a helper around a no-argument function.

## 🌐 DOM bindings

`ripple.bindText` wires a signal to a DOM node id. On WASM targets we expect the host to export `ripple_dom_set_text(node_id, ptr, len)`; on native/test builds we fall back to `std.debug.print` and injectable callbacks.

```zig
var text = try ripple.createSignal([]const u8, allocator, "hello");
var binding = try ripple.bindText(allocator, 1, text.read);
defer binding.dispose();

try text.write.set("world");
```

For integration tests or native targets, override the host callback:

```zig
const Callbacks = ripple.DomHostCallbacks;
ripple.setDomHostCallbacks(.{
  .set_text = myFn,
  .context = myCtx,
});
```

## 📋 Roadmap

- **Core Runtime**: Signals, effects, and reactive scheduler
- **DOM & Rendering**: Template compiler and hydration system
- **Routing**: File-based and programmatic routing
- **Forms & Validation**: Progressive enhancement with schema validation
- **Components**: Headless, accessible component primitives
- **Styling**: Design tokens and theming system
- **Tooling**: Development server with HMR and build pipeline

## 🛠️ Installation

Add Ripple to your Zig project:

```bash
zig fetch --save https://github.com/ghostkellz/ripple/archive/refs/head/main.tar.gz
```

## 🛠️ Building

```bash
zig build
```

## 🧪 Testing

```bash
zig build test
```

## 📄 License

Licensed under the [MIT License](LICENSE).
