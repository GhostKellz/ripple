/// Ripple core reactive runtime.
///
/// Contract (MVP):
/// - `createSignal` returns a pair of read/write handles that own the signal lifetime.
/// - `createEffect` registers a reactive computation that automatically tracks
///   the signals it reads and re-runs when any of them change.
/// - `createMemo` builds upon `createEffect` to cache derived values with lazy
///   evaluation semantics.
/// - All runtime state must be allocator-backed but avoid hidden global
///   allocations beyond thread-local bookkeeping to keep WASM-friendly.
/// - Effects run synchronously for now; a microtask scheduler hook will follow
///   in later milestones.
///
/// This module purposefully keeps the API small while we iterate on the
/// ergonomics. Names and signatures are inspired by Leptos and Solid, but use
/// Zig naming conventions and error handling.
const signals = @import("core/signal.zig");

pub const EffectCallback = signals.EffectCallback;
pub const EffectContext = signals.EffectContext;
pub const EffectHandle = signals.EffectHandle;
pub const SignalPair = signals.SignalPair;
pub const ReadSignal = signals.ReadSignal;
pub const WriteSignal = signals.WriteSignal;
pub const MemoHandle = signals.MemoHandle;
pub const BatchGuard = signals.BatchGuard;
pub const ResourceStatus = signals.ResourceStatus;
pub const ResourceState = signals.ResourceState;
pub const ResourceHandle = signals.ResourceHandle;
pub const SuspenseHandle = signals.SuspenseHandle;
pub const ContextGuard = signals.ContextGuard;
pub const ContextValueGuard = signals.ContextValueGuard;
pub const ErrorBoundaryGuard = signals.ErrorBoundaryGuard;
pub const ErrorBoundaryToken = signals.ErrorBoundaryToken;

pub const createSignal = signals.createSignal;
pub const createEffect = signals.createEffect;
pub const createMemo = signals.createMemo;
pub const beginBatch = signals.beginBatch;
pub const batch = signals.batch;
pub const flushPending = signals.flushPending;
pub const createResource = signals.createResource;
pub const createSuspenseBoundary = signals.createSuspenseBoundary;
pub const pushContext = signals.pushContext;
pub const withContext = signals.withContext;
pub const useContext = signals.useContext;
pub const pushErrorBoundary = signals.pushErrorBoundary;
pub const popErrorBoundary = signals.popErrorBoundary;
pub const beginErrorBoundary = signals.beginErrorBoundary;
