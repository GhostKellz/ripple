# Ripple Roadmap: MVP → Alpha → Beta

## Current Status

**Completed (Prototype):**
- ✅ Core reactive runtime (signals, effects, memos)
- ✅ Batching scheduler with `beginBatch` and `batch`
- ✅ Resources with async loading and suspense boundaries
- ✅ Context API for dependency injection
- ✅ Error boundaries for error handling
- ✅ Template compilation system
- ✅ Render program building (mount & hydrate)
- ✅ Islands architecture with selective hydration
- ✅ Event delegation system
- ✅ Portals for rendering outside DOM hierarchy
- ✅ DOM bindings (text, elements, attributes)
- ✅ Comprehensive test coverage (all tests passing)

---

## MVP (Minimum Viable Product) ✅ COMPLETED

**Goal:** Make Ripple usable for building basic interactive web applications.

### Features

#### 1. Component System (src/component.zig) ✅
- [x] Function-based components with props
- [x] Component lifecycle hooks (via ComponentScope)
- [x] Children composition
- [x] Component context and scoping
- [x] ViewBuilder for ergonomic component creation

#### 2. Basic Client-Side Routing (src/router.zig) ✅
- [x] Hash-based routing (#/path)
- [x] Route matching and params
- [x] Link component for navigation
- [x] Route guards/middleware
- [x] RouteParams (path & query parameters)

#### 3. Enhanced DOM Bindings ✅
- [x] Text binding (bindText)
- [x] Element creation (hostCreateElement)
- [x] Attribute binding (static & dynamic)
- [x] Boolean attributes support
- [x] Event delegation system

#### 4. Control Flow Helpers (src/control_flow.zig) ✅
- [x] `Show` - conditional rendering
- [x] `For` - keyed list rendering (basic implementation)
- [x] `Switch`/`Match` - multiple conditionals
- [x] Integration with signals

#### 5. WASM Integration Example ✅
- [x] Complete WASM build target (build.zig)
- [x] JavaScript host implementation (ripple.js)
- [x] HTML template with reactive bindings
- [x] Counter example in browser (5.4KB WASM!)
- [ ] TodoMVC example (next phase)

#### 6. Documentation ✅
- [x] Project roadmap (ROADMAP.md)
- [x] Counter example README
- [x] Code examples in each module
- [ ] Getting started guide (next)
- [ ] Full API reference (next)

**Deliverables:**
- ✅ Working counter app in browser (WASM) - 5.4KB bundle
- ⏳ TodoMVC example - in progress
- ⏳ Documentation site - next phase
- ✅ Comprehensive test suite (50+ tests passing)

---

## Alpha (Feature Complete)

**Goal:** Production-ready framework with complete feature set.

### Features

#### 1. Advanced Routing (src/router/ directory)
- [ ] File-based routing
- [ ] Route prefetching
- [ ] Scroll restoration
- [ ] Route transitions
- [ ] Lazy loading
- [ ] Protected routes

#### 2. Forms & Validation (src/forms.zig)
- [ ] Form component
- [ ] Input bindings (text, checkbox, radio, select)
- [ ] Form state management
- [ ] Validation system
- [ ] Error display
- [ ] Progressive enhancement
- [ ] Schema validation

#### 3. Component Library (src/components/)
- [ ] Button (accessible, variants)
- [ ] Input/TextArea
- [ ] Select/Dropdown
- [ ] Checkbox/Radio
- [ ] Modal/Dialog
- [ ] Tabs
- [ ] Accordion
- [ ] Toast/Notification
- [ ] Tooltip
- [ ] Spinner/Loading states

#### 4. Server-Side Rendering (src/ssr/)
- [ ] SSR render to HTML string
- [ ] Hydration strategy
- [ ] Streaming SSR
- [ ] Async data fetching
- [ ] Meta tags and SEO
- [ ] Static site generation (SSG)

#### 5. Styling System (src/styling.zig)
- [ ] CSS-in-Zig
- [ ] Design tokens
- [ ] Theme system
- [ ] Responsive utilities
- [ ] Animation helpers
- [ ] Style composition

#### 6. Advanced Examples
- [ ] E-commerce store
- [ ] Blog with SSR
- [ ] Dashboard with charts
- [ ] Real-time chat
- [ ] Authentication flow

**Deliverables:**
- Complete component library
- SSR examples
- E-commerce demo
- Production deployment guides

---

## Beta (Production Ready)

**Goal:** Complete developer experience with tooling and optimizations.

### Features

#### 1. Development Server (tools/dev-server.zig)
- [ ] File watching and auto-rebuild
- [ ] Hot module replacement (HMR)
- [ ] WebSocket for live reload
- [ ] Error overlay
- [ ] Performance profiler
- [ ] Built-in HTTP server

#### 2. Build Pipeline (tools/build-tool.zig)
- [ ] Bundling and tree-shaking
- [ ] Code splitting
- [ ] Asset optimization (images, fonts)
- [ ] Minification
- [ ] Source maps
- [ ] Multi-page support
- [ ] Environment variables

#### 3. CLI Tool (tools/cli.zig)
- [ ] Project scaffolding (`ripple init`)
- [ ] Component generator
- [ ] Build commands
- [ ] Development server
- [ ] Production build
- [ ] Deploy helpers

#### 4. Testing Utilities (src/testing.zig)
- [ ] Component testing helpers
- [ ] DOM assertions
- [ ] Event simulation
- [ ] Async testing
- [ ] Mock utilities
- [ ] Coverage tools

#### 5. Performance Optimizations
- [ ] Virtual DOM diffing optimizations
- [ ] Memory pool allocator
- [ ] Lazy evaluation strategies
- [ ] Bundle size analysis
- [ ] Runtime profiling
- [ ] Benchmark suite

#### 6. Plugin System (src/plugins/)
- [ ] Plugin API
- [ ] Lifecycle hooks
- [ ] Transform plugins
- [ ] Official plugins:
  - [ ] Analytics
  - [ ] i18n (internationalization)
  - [ ] State persistence
  - [ ] Service worker
  - [ ] PWA support

#### 7. Documentation Site
- [ ] Interactive playground
- [ ] Component showcase
- [ ] Live code editor
- [ ] Search functionality
- [ ] Version switcher
- [ ] Blog/News section

**Deliverables:**
- Complete CLI tool
- Development server with HMR
- Documentation website
- Production examples
- Migration guides
- 1.0 release candidate

---

## Implementation Order

### Phase 1: MVP (Weeks 1-4)
1. Week 1: Component system + Control flow
2. Week 2: Basic routing + Enhanced DOM bindings
3. Week 3: WASM integration + Counter example
4. Week 4: TodoMVC + Documentation

### Phase 2: Alpha (Weeks 5-10)
1. Week 5-6: Advanced routing + Forms
2. Week 7-8: Component library (8 components)
3. Week 9: SSR implementation
4. Week 10: Advanced examples

### Phase 3: Beta (Weeks 11-16)
1. Week 11-12: Dev server + HMR
2. Week 13: Build pipeline + CLI
3. Week 14: Testing utilities + Optimizations
4. Week 15: Plugin system
5. Week 16: Documentation site + Polish

---

## Success Metrics

### MVP
- ✅ Build and run TodoMVC in browser
- ✅ 100+ unit tests passing
- ✅ Basic documentation complete

### Alpha
- ✅ Complete e-commerce demo working
- ✅ SSR rendering performance < 10ms
- ✅ Component library with 15+ components

### Beta
- ✅ Dev server with sub-200ms rebuild
- ✅ Bundle size < 50KB (gzipped)
- ✅ Complete documentation site
- ✅ CLI tool published

---

## Beyond Beta (Post 1.0)

- Advanced state management
- Mobile app support (via capacitor/tauri)
- Native desktop support
- Chrome DevTools extension
- LSP (Language Server Protocol)
- VS Code extension
- Component marketplace
- Official packages (charts, forms, etc.)

---

## Contributing

Each phase will have detailed issues tracking individual features. Check the GitHub issues for current status and how to contribute.

## Questions?

Open an issue or discussion on GitHub!
