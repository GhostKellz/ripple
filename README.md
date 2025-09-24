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

## 🎯 Goals

- Full WebAssembly support with optimal performance
- Leptos/Yew-style reactivity and component model
- Exceptional developer experience with hot module reloading
- Server-side rendering with islands architecture
- Zero runtime dependencies beyond the browser

## 🚧 Status

Ripple is currently in early development. This is a ground-up implementation of a reactive web framework targeting WebAssembly through Zig.

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

## 📄 License

Licensed under the [MIT License](LICENSE).
