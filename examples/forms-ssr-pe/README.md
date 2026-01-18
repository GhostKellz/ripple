# Forms SSR + Progressive Enhancement Demo

This example mirrors the guidance in `docs/design/forms-ssr-demo.md` by pairing Ripple's form store with the new schema, accessibility, and async helpers. The project is split into two halves:

- `src/main.zig` – a CLI walkthrough that simulates an SSR render, an initial invalid submission, an async username check, and a corrected submission.
- `public/index.html` – sample HTML scaffolding showing the progressive enhancement hooks (`role="alert"`, `aria-invalid`, data attributes) that the WASM side hydrates.

## Running the walkthrough

```sh
zig build run
```

The program prints three stages:

1. **Initial SSR render** – no validation errors and `aria-invalid[email] = false`.
2. **Invalid submission** – email/password/confirm fail immediately; username queues an async server check, and focusing the first invalid field chooses `email`.
3. **After async response & fixes** – the async rule resolves (`Username already taken`), then the user corrects all fields and the store reports no remaining errors.

Feel free to tweak the `setValue` calls or the async username rule to experiment with different validation outcomes. The code is intentionally small so you can port the same patterns into a real HTTP handler + WASM hydration flow.
