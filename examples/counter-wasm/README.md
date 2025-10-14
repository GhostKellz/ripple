# Ripple Counter - WASM Example

A reactive counter application built with Ripple, demonstrating WebAssembly integration with fine-grained reactivity.

## Features

- **Reactive Signals**: Counter state managed with Ripple's signal system
- **WebAssembly**: Compiled to WASM for optimal performance (only 5.4KB!)
- **DOM Integration**: Automatic DOM updates via reactive effects
- **Beautiful UI**: Modern, responsive design with smooth animations

## Building

From the project root:

```bash
zig build wasm -Doptimize=ReleaseSmall
```

This will generate:
- `zig-out/www/counter.wasm` - The compiled WASM module
- HTML and JavaScript files are automatically copied

## Running

You need to serve the files from a web server (WASM requires proper MIME types):

### Option 1: Using Python

```bash
cd zig-out/www
python3 -m http.server 8000
```

Then open http://localhost:8000

### Option 2: Using Node.js

```bash
cd zig-out/www
npx serve
```

### Option 3: Using any static file server

Just serve the `zig-out/www/` directory.

## How It Works

### Zig Side (WASM)

```zig
// Create a reactive signal
var counter_signal = try ripple.createSignal(i32, allocator, 0);

// Create an effect that updates the DOM
var effect = try ripple.createEffect(allocator, updateDisplay, &ctx);

// Export functions for JavaScript to call
export fn increment() void { ... }
export fn decrement() void { ... }
export fn reset() void { ... }
```

### JavaScript Side (Host)

```javascript
// Load the WASM module with host bindings
const host = new RippleHost();
await host.load('counter.wasm');
host.init();

// Wire up button clicks
button.addEventListener('click', () => host.call('increment'));
```

## Architecture

```
┌──────────────────┐
│   JavaScript     │  Browser environment
│   (ripple.js)    │  - Loads WASM module
│                  │  - Provides DOM bindings
└────────┬─────────┘
         │ WebAssembly
         │ Interface
┌────────▼─────────┐
│   WASM Module    │  Ripple reactive runtime
│   (counter.wasm) │  - Signal management
│                  │  - Effect tracking
│                  │  - State updates
└──────────────────┘
```

## Code Structure

```
examples/counter-wasm/
├── src/
│   └── main.zig        # Ripple WASM application
├── www/
│   ├── index.html      # HTML template
│   └── ripple.js       # JavaScript host bindings
└── README.md           # This file
```

## Browser Compatibility

Works in all modern browsers with WebAssembly support:
- Chrome/Edge 57+
- Firefox 52+
- Safari 11+

## Performance

- **Bundle Size**: 5.4 KB (WASM)
- **Load Time**: < 50ms on typical connections
- **Reactivity**: Zero-overhead reactive updates
- **Memory**: Fixed 1MB allocation (configurable)

## Next Steps

This example demonstrates the basics. Check out more advanced examples:
- TodoMVC - Full application with routing
- Dashboard - Data visualization with charts
- E-commerce - Complex state management

## License

MIT
