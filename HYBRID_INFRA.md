  🏗️ Integration Architecture: reaper.grim Elite AI Coding Assistant

  🎯 Vision Overview

  You're building a multi-model AI coding assistant that rivals/surpasses Claude Code, with:
  - Multi-provider support through OMEN (Ollama, Claude, OpenAI, Azure, xAI, Bedrock, Vertex AI)
  - MCP protocol for tool/resource communication (rune + glyph)
  - Modern UI with both TUI (phantom) and WASM (ripple) interfaces
  - Pure Zig performance with Rust interop where beneficial
  - Grim editor integration via phantom.grim config framework

  ---
  🔄 Recommended Architecture: Hybrid Approach

  ┌───────────────────────────────────────────────────────────────┐
  │                    reaper.grim (Zig)                         │
  │              AI Coding Assistant for Grim                     │
  ├───────────────────────────────────────────────────────────────┤
  │  UI Layer:                                                    │
  │  • phantom (TUI) - Terminal interface via phantom.grim       │
  │  • ripple (WASM) - Web-based settings/dashboard             │
  │                                                               │
  │  Core Components:                                            │
  │  • zsync - Async runtime                                     │
  │  • flash - CLI framework                                     │
  │  • flare - Config management                                 │
  │  • zlog - Logging                                            │
  │                                                               │
  │  Integration Layers:                                         │
  │  ┌─────────────────────┐  ┌──────────────────────┐         │
  │  │  rune (Zig MCP)     │  │  zrpc (gRPC client)  │         │
  │  │  - Tool calls       │  │  - AI completions    │         │
  │  │  - Resources        │  │  - Streaming         │         │
  │  │  - Prompts          │  │  - Error handling    │         │
  │  └──────────┬──────────┘  └──────────┬───────────┘         │
  └─────────────┼──────────────────────────┼────────────────────┘
                │ MCP JSON-RPC             │ gRPC/Protobuf
                │                          │
                ▼                          ▼
      ┌─────────────────┐         ┌────────────────────┐
      │ glyph (Rust)    │         │ OMEN (Rust)        │
      │ MCP Server      │         │ Provider Gateway   │
      ├─────────────────┤         ├────────────────────┤
      │ • WebSocket     │         │ • Smart routing    │
      │ • HTTP/2        │         │ • Rate limiting    │
      │ • Security      │         │ • Cost tracking    │
      │ • Tool registry │         │ • Caching          │
      └─────────────────┘         │ • Load balancing   │
                                  └──────────┬─────────┘
                                             │
                          ┌──────────────────┼───────────────┐
                          ▼                  ▼               ▼
                      [Ollama]           [Claude]      [OpenAI]
                      [xAI]              [Azure]       [Bedrock]
                                                   [Vertex AI]

  ---
  📋 Integration Strategy: 3 Options

  Option A: Pure Zig with gRPC (Recommended for MVP)

  Why this first?
  - ✅ Fastest to implement
  - ✅ Already have zrpc dependency
  - ✅ OMEN's gRPC endpoint is production-ready
  - ✅ No FFI complexity
  - ✅ Best performance for AI completions (primary use case)

  Implementation:

  // reaper.grim/src/ai_client.zig
  const zrpc = @import("zrpc");
  const zsync = @import("zsync");

  pub const OmenClient = struct {
      grpc_client: *zrpc.Client,
      allocator: std.mem.Allocator,
      
      pub fn init(allocator: std.mem.Allocator, omen_url: []const u8) !*OmenClient {
          const client = try zrpc.Client.init(allocator, .{
              .url = omen_url, // "https://localhost:50051"
              .tls = true,
              .timeout_ms = 30000,
          });

          return &OmenClient{
              .grpc_client = client,
              .allocator = allocator,
          };
      }

      pub fn chatCompletion(
          self: *OmenClient,
          request: ChatCompletionRequest
      ) !ChatCompletionResponse {
          // Call OMEN's gRPC ChatCompletion endpoint
          const response = try self.grpc_client.call(
              "omen.v1.ChatService",
              "ChatCompletion",
              request
          );
          return response;
      }

      pub fn streamChatCompletion(
          self: *OmenClient,
          request: ChatCompletionRequest,
          callback: *const fn(chunk: []const u8) void
      ) !void {
          // Streaming completion via gRPC server streaming
          try self.grpc_client.streamCall(
              "omen.v1.ChatService",
              "StreamChatCompletion",
              request,
              callback
          );
      }
  };

  Pros:
  - Direct communication, no middleware
  - zrpc already in reaper.grim dependencies
  - OMEN handles all provider complexity
  - Supports all OMEN features (routing, caching, billing)

  Cons:
  - No MCP tool calling (yet)
  - Tightly coupled to OMEN API

  ---
  Option B: Zig MCP Client via rune (Recommended for Tool Support)

  Why this for tools?
  - ✅ MCP protocol for standardized tool calling
  - ✅ Pure Zig implementation (rune)
  - ✅ glyph provides enterprise MCP server features
  - ✅ Extensible for future tool integrations

  Implementation:

  // reaper.grim/build.zig.zon
  .{
      .name = "reaper_grim",
      .version = "0.1.0",
      .dependencies = .{
          // Existing dependencies
          .zsync = .{
              .url = "https://github.com/ghostkellz/zsync/archive/main.tar.gz",
              .hash = "zsync-0.5.4-KAuheZ4THQAlN32uBKm76ezT7dPT6rvj4ll56NiA9z9M",
          },
          .zrpc = .{
              .url = "https://github.com/ghostkellz/zrpc/archive/main.tar.gz",
              .hash = "zrpc-0.1.0-b2Xib6X1BwCltazUe_BVVmRTkid4nqVfeknx8RMumZn3",
          },
          .flash = .{
              .url = "https://github.com/ghostkellz/flash/archive/main.tar.gz",
              .hash = "flash-0.3.1-dnj737-SBQDjkdsw5XOgIVxcWN0ZyJaDiXpUaoP7AcZ4",
          },
          .flare = .{
              .url = "https://github.com/ghostkellz/flare/archive/main.tar.gz",
              .hash = "flare-0.1.0-NK4JafGMAQA8xE2ah8YBxO74sOkWrsQYTkWQ64D1PJVg",
          },
          .zlog = .{
              .url = "https://github.com/ghostkellz/zlog/archive/main.tar.gz",
              .hash = "zlog-0.1.0-kS0sWE9cCAC4TsztkA-l0QEYu3eUKXrHnHux5eDvs04J",
          },

          // NEW: Add rune for MCP support
          .rune = .{
              .url = "https://github.com/ghostkellz/rune/archive/main.tar.gz",
              .hash = "12205...", // Run: zig fetch --save <url>
          },

          // NEW: Add phantom for TUI
          .phantom = .{
              .url = "https://github.com/ghostkellz/phantom/archive/main.tar.gz",
              .hash = "12205...",
          },

          // NEW: Add ripple for WASM UI
          .ripple = .{
              .url = "https://github.com/ghostkellz/ripple/archive/main.tar.gz",
              .hash = "12205...",
          },
      },
  }

  // reaper.grim/src/mcp_client.zig
  const rune = @import("rune");
  const zsync = @import("zsync");

  pub const MCPToolClient = struct {
      mcp_client: *rune.Client,
      allocator: std.mem.Allocator,
      
      pub fn init(allocator: std.mem.Allocator, server_url: []const u8) !*MCPToolClient {
          const client = try rune.Client.init(allocator, .{
              .transport = .{ .websocket = server_url },
              .protocol = .mcp,
          });

          return &MCPToolClient{
              .mcp_client = client,
              .allocator = allocator,
          };
      }

      pub fn listTools(self: *MCPToolClient) ![]rune.Tool {
          // List available tools from glyph MCP server
          return try self.mcp_client.send(.{
              .method = "tools/list",
              .params = .{},
          });
      }

      pub fn callTool(
          self: *MCPToolClient,
          tool_name: []const u8,
          arguments: anytype
      ) ![]const u8 {
          // Execute tool via MCP
          const result = try self.mcp_client.send(.{
              .method = "tools/call",
              .params = .{
                  .name = tool_name,
                  .arguments = arguments,
              },
          });
          return result.content;
      }
  };

  Pros:
  - Standardized MCP protocol
  - Pure Zig, no FFI overhead
  - Extensible tool ecosystem
  - glyph provides enterprise features (security, monitoring)

  Cons:
  - Requires running glyph MCP server
  - Two separate connections (MCP + gRPC)

  ---
  Option C: Hybrid Architecture (Production Recommendation)

  Use both Option A + Option B:

  // reaper.grim/src/ai_engine.zig
  const OmenClient = @import("ai_client.zig").OmenClient;
  const MCPToolClient = @import("mcp_client.zig").MCPToolClient;
  const phantom = @import("phantom");
  const zsync = @import("zsync");

  pub const ReaperAI = struct {
      // AI completions via OMEN (fast, direct)
      omen: *OmenClient,
      
      // Tool calling via MCP (standardized, extensible)
      mcp: *MCPToolClient,
      
      // UI components
      tui: *phantom.App,
      
      // Async runtime
      runtime: *zsync.Runtime,
      
      allocator: std.mem.Allocator,
      
      pub fn init(allocator: std.mem.Allocator, config: ReaperConfig) !*ReaperAI {
          const runtime = try zsync.Runtime.init(allocator);
          
          // Connect to OMEN for AI completions
          const omen = try OmenClient.init(
              allocator,
              config.omen_url orelse "https://localhost:50051"
          );

          // Connect to glyph MCP server for tools
          const mcp = try MCPToolClient.init(
              allocator,
              config.mcp_url orelse "ws://localhost:8080/mcp"
          );

          // Initialize phantom TUI
          const tui = try phantom.App.init(allocator, .{
              .title = "👻 Reaper.grim - AI Coding Assistant",
              .tick_rate_ms = 16, // 60 FPS
              .mouse_enabled = true,
          });

          return &ReaperAI{
              .omen = omen,
              .mcp = mcp,
              .tui = tui,
              .runtime = runtime,
              .allocator = allocator,
          };
      }

      pub fn generateCode(
          self: *ReaperAI,
          prompt: []const u8,
          context: CodeContext
      ) ![]const u8 {
          // Step 1: Get available tools from MCP
          const tools = try self.mcp.listTools();

          // Step 2: Send AI request to OMEN with tool definitions
          const request = ChatCompletionRequest{
              .model = context.preferred_model orelse "claude-3-7-sonnet-20250219",
              .messages = &[_]Message{
                  .{ .role = "user", .content = prompt },
              },
              .tools = tools,
              .omen = .{
                  .strategy = "single", // or "race" for speed
                  .providers = context.allowed_providers,
                  .budget_usd = 0.10,
              },
          };

          // Step 3: Stream response and handle tool calls
          var response_buffer = std.ArrayList(u8).init(self.allocator);

          try self.omen.streamChatCompletion(request, struct {
              fn callback(chunk: []const u8) void {
                  // Handle streaming chunks
                  // If tool_call detected, invoke via MCP
                  if (isToolCall(chunk)) {
                      const tool_result = self.mcp.callTool(
                          tool_name,
                          tool_args
                      ) catch unreachable;

                      // Send tool result back to OMEN
                      // ...
                  } else {
                      // Regular text, append to buffer
                      response_buffer.appendSlice(chunk) catch unreachable;
                  }
              }
          }.callback);

          return response_buffer.toOwnedSlice();
      }
  };

  Why this is best for production:

  1. AI Completions → OMEN (gRPC):
    - Low latency, high throughput
    - OMEN's advanced routing (race, speculate_k, parallel_merge)
    - Cost optimization and caching
    - Multi-provider failover
  2. Tool Calling → glyph + rune (MCP):
    - Standardized protocol for tools
    - Security policies (glyph)
    - Extensible tool ecosystem
    - IDE/LSP integration ready
  3. UI → phantom (TUI) + ripple (WASM):
    - phantom: Rich terminal UI in Grim editor
    - ripple: Web dashboard for settings, monitoring, cost tracking
    - Shared state via phantom.grim config

  ---
  🚀 Implementation Roadmap

  Phase 1: Core Integration (Week 1-2)

  1. Add dependencies to reaper.grim:
  cd /data/projects/reaper.grim
  zig fetch --save https://github.com/ghostkellz/rune/archive/main.tar.gz
  zig fetch --save https://github.com/ghostkellz/phantom/archive/main.tar.gz
  zig fetch --save https://github.com/ghostkellz/ripple/archive/main.tar.gz
  2. Create OMEN gRPC client (src/omen_client.zig):
    - Chat completions
    - Streaming support
    - Model listing
    - Health checks
  3. Integrate phantom TUI:
    - Code completion popup
    - Streaming response display
    - Provider selection UI
    - Cost/token tracking widget

  Phase 2: MCP Integration (Week 3-4)

  1. Set up glyph MCP server (Rust):
  cd /data/projects/glyph
  cargo build --release --features server
  ./target/release/glyph-server --port 8080
  2. Create rune MCP client (src/mcp_client.zig):
    - Tool discovery
    - Tool invocation
    - Resource management
  3. Implement tool handlers:
    - File system operations
    - Git operations
    - LSP queries
    - Terminal commands

  Phase 3: Advanced Features (Week 5-6)

  1. ripple WASM dashboard:
    - Settings panel
    - Cost analytics
    - Provider performance graphs
    - Session history
  2. phantom.grim integration:
    - Keybindings for AI features
    - Config for model preferences
    - Custom themes for AI UI
  3. Advanced AI features:
    - Multi-file context gathering
    - Agentic workflows (multi-step reasoning)
    - Code review mode
    - Test generation mode

  ---
  📦 Deployment Architecture

  Development Setup:

  # Terminal 1: Start OMEN gateway
  cd /data/projects/omen
  cargo run --release

  # Terminal 2: Start glyph MCP server
  cd /data/projects/glyph
  cargo run --release --bin glyph-server -- --port 8080

  # Terminal 3: Run reaper.grim
  cd /data/projects/reaper.grim
  zig build run

  Production Setup:

  # Single binary with embedded services
  cd /data/projects/reaper.grim
  zbuild build --release --embed-omen --embed-glyph

  # Or use systemd services
  sudo systemctl start omen-gateway
  sudo systemctl start glyph-mcp
  grim ~/.config/grim/phantom.grim

  ---
  🎯 Competitive Advantages Over Claude Code

  | Feature       | Claude Code     | reaper.grim
      |
  |---------------|-----------------|-------------------------------------------------------------
  ----|
  | Providers     | Claude only     | 7+ providers (Ollama, Claude, GPT, Azure, xAI, Bedrock,
  Vertex) |
  | Editor        | VS Code/Vim     | Grim (native Zig, faster)
      |
  | Routing       | Single provider | Smart routing (race, speculate, parallel)
      |
  | Local AI      | No              | Ollama support (privacy-first)
      |
  | Cost Control  | No              | Budget limits, cost tracking
      |
  | UI            | Terminal only   | TUI + WASM dashboard
      |
  | Language      | TypeScript/Rust | Pure Zig (faster, simpler)
      |
  | Tool Protocol | Custom          | MCP standard (extensible)
      |
  | Offline Mode  | No              | Yes (Ollama + local tools)
      |
  | Performance   | Good            | Exceptional (Zig + GPU rendering)
      |

  ---
  🔧 Next Steps (Immediate Actions)

  1. Add zig fetch dependencies:
  cd /data/projects/reaper.grim
  zig fetch --save https://github.com/ghostkellz/rune/archive/main.tar.gz
  zig fetch --save https://github.com/ghostkellz/phantom/archive/main.tar.gz
  # Update build.zig to import modules
  2. Create OMEN client wrapper:
    - Use existing zrpc dependency
    - Implement ChatCompletion gRPC call
    - Add streaming support
  3. Build phantom TUI integration:
    - Code completion popup widget
    - Streaming text display
    - Provider selection menu
  4. Test end-to-end:
    - OMEN → Ollama (local, fast)
    - OMEN → Claude (quality)
    - OMEN → OpenAI (fallback)

  ---
  💡 Key Insights

  For "best copilot/coding assistant on the planet":

  1. Speed → Use OMEN's race strategy
    - Start 2-3 providers simultaneously
    - Use first good response
    - Cancel slower ones
  2. Quality → Use parallel_merge
    - Get responses from Claude + GPT
    - Merge best parts of each
  3. Privacy → Default to Ollama
    - Keep code local when possible
    - Fallback to cloud only when needed
  4. Cost → Smart routing
    - Use cheap models (Gemini) for simple tasks
    - Use premium (Claude) for complex reasoning
  5. UX → phantom + ripple
    - Rich TUI for coding flow
    - Web dashboard for analytics/settings

  This architecture leverages the best of your entire Ghost ecosystem while staying modular, fast,
   and extensible. Want me to start implementing any specific component?

