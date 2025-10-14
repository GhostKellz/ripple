// Ripple WASM Host - JavaScript integration for Ripple framework

class RippleHost {
    constructor() {
        this.wasm = null;
        this.memory = null;
        this.decoder = new TextDecoder();
        this.encoder = new TextEncoder();
    }

    // Import object for WASM module
    getImports() {
        return {
            env: {
                // Update counter display in the DOM
                updateCountDisplay: (ptr, len) => {
                    const text = this.readString(ptr, len);
                    const display = document.getElementById('counter-display');
                    if (display) {
                        display.textContent = text;
                        // Add animation
                        display.style.transform = 'scale(1.1)';
                        setTimeout(() => {
                            display.style.transform = 'scale(1)';
                        }, 100);
                    }
                },

                // DOM manipulation functions (for future use)
                ripple_dom_set_text: (nodeId, ptr, len) => {
                    const text = this.readString(ptr, len);
                    console.log(`[DOM] Set text on node ${nodeId}: ${text}`);
                },

                ripple_dom_create_element: (ptr, len) => {
                    const tag = this.readString(ptr, len);
                    console.log(`[DOM] Create element: ${tag}`);
                    return 1; // Return dummy node ID
                },

                ripple_dom_create_text: (ptr, len) => {
                    const value = this.readString(ptr, len);
                    console.log(`[DOM] Create text: ${value}`);
                    return 2; // Return dummy node ID
                },

                ripple_dom_append_child: (parent, child) => {
                    console.log(`[DOM] Append ${child} to ${parent}`);
                },

                ripple_dom_set_attribute: (nodeId, namePtr, nameLen, valuePtr, valueLen) => {
                    const name = this.readString(namePtr, nameLen);
                    const value = this.readString(valuePtr, valueLen);
                    console.log(`[DOM] Set attribute ${name}="${value}" on node ${nodeId}`);
                },

                // Router functions (for future use)
                ripple_router_get_hash: (ptrPtr, lenPtr) => {
                    const hash = window.location.hash.slice(1) || '/';
                    console.log(`[Router] Get hash: ${hash}`);
                    // Would need to write to WASM memory
                },

                ripple_router_set_hash: (ptr, len) => {
                    const path = this.readString(ptr, len);
                    console.log(`[Router] Set hash: ${path}`);
                    window.location.hash = path;
                },
            }
        };
    }

    // Read a string from WASM memory
    readString(ptr, len) {
        if (!this.memory) {
            throw new Error('WASM memory not initialized');
        }
        const bytes = new Uint8Array(this.memory.buffer, ptr, len);
        return this.decoder.decode(bytes);
    }

    // Write a string to WASM memory (for future use)
    writeString(str) {
        const bytes = this.encoder.encode(str);
        // Would need to allocate memory in WASM
        return { ptr: 0, len: bytes.length };
    }

    // Load and initialize the WASM module
    async load(wasmPath) {
        try {
            const response = await fetch(wasmPath);
            const wasmBytes = await response.arrayBuffer();

            const result = await WebAssembly.instantiate(wasmBytes, this.getImports());

            this.wasm = result.instance.exports;
            this.memory = this.wasm.memory;

            console.log('✓ WASM module loaded successfully');
            return true;
        } catch (error) {
            console.error('Failed to load WASM module:', error);
            throw error;
        }
    }

    // Initialize the Ripple application
    init() {
        if (!this.wasm || !this.wasm.init) {
            throw new Error('WASM module not loaded or init function not found');
        }
        this.wasm.init();
        console.log('✓ Ripple application initialized');
    }

    // Call exported WASM functions
    call(funcName, ...args) {
        if (!this.wasm || !this.wasm[funcName]) {
            throw new Error(`Function ${funcName} not found in WASM module`);
        }
        return this.wasm[funcName](...args);
    }

    // Cleanup
    deinit() {
        if (this.wasm && this.wasm.deinit) {
            this.wasm.deinit();
            console.log('✓ Ripple application cleaned up');
        }
    }
}

// Initialize the application
(async function() {
    const host = new RippleHost();
    const statusEl = document.getElementById('status');

    try {
        // Load WASM module
        await host.load('counter.wasm');

        // Initialize Ripple app
        host.init();

        // Set up button handlers
        const btnIncrement = document.getElementById('btn-increment');
        const btnDecrement = document.getElementById('btn-decrement');
        const btnReset = document.getElementById('btn-reset');

        btnIncrement.disabled = false;
        btnDecrement.disabled = false;
        btnReset.disabled = false;

        btnIncrement.addEventListener('click', () => host.call('increment'));
        btnDecrement.addEventListener('click', () => host.call('decrement'));
        btnReset.addEventListener('click', () => host.call('reset'));

        // Update status
        statusEl.textContent = '✓ Ready! Click the buttons to try it out.';
        statusEl.className = 'status success';

        console.log('✓ Counter app ready!');

        // Cleanup on page unload
        window.addEventListener('beforeunload', () => host.deinit());

    } catch (error) {
        console.error('Initialization failed:', error);
        statusEl.textContent = `✗ Error: ${error.message}`;
        statusEl.className = 'status error';
    }
})();
