# ChatGPT Window Title Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable .NET 8 WinForms tray app that tracks each ChatGPT HWND, reads its current conversation title through UI Automation, and displays it in an overlay and optionally in Alt+Tab.

**Architecture:** A single-instance WinForms host owns discovery, per-HWND state, UIA title reading, polling/event refresh, overlay windows, and window-title writing. Components communicate through a per-window state record keyed by HWND; all external UIA/Win32 failures are isolated per window.

**Tech Stack:** C#, .NET 8, WinForms, Windows UI Automation (`UIAutomationClient`/`UIAutomationTypes`), Win32 P/Invoke, System.Text.Json, x64 self-contained single-file publish.

**Spec:** `docs/superpowers/specs/2026-09-10-chatgpt-window-title-helper-design.md`

## Global Constraints

- Target Windows and .NET 8; use WinForms, not WPF/Electron/WebView.
- Identify windows by HWND, never by PID or mutable window title.
- Use `AriaProperties contains "current=page"` and the matching element `Name` as the primary title source.
- No DOM modification, injection, OCR, image recognition, mouse/keyboard automation, or sidebar automation.
- UIA events are preferred; fallback polling is `1000ms`.
- Window-title reapplication interval is `2000ms`, and unchanged titles must not be rewritten.
- Overlay is non-activating, click-through, absent from Alt+Tab and the taskbar.
- Default settings: overlay ON, Alt+Tab title ON.
- Persist settings as UTF-8 JSON under `%LocalAppData%\\ChatGPTWindowTitleHelper\\settings.json`.

---

### Task 1: Create solution and testable domain contracts

**Files:**
- Create: `ChatGPTWindowTitleHelper.sln`
- Create: `src/ChatGPTWindowTitleHelper/ChatGPTWindowTitleHelper.csproj`
- Create: `src/ChatGPTWindowTitleHelper/Domain/TrackedWindow.cs`
- Create: `src/ChatGPTWindowTitleHelper/Domain/AppSettings.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/ChatGPTWindowTitleHelper.Tests.csproj`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Domain/TrackedWindowTests.cs`

**Interfaces:**
- `TrackedWindow`: immutable HWND identity plus mutable last-known title, original title, and active state.
- `AppSettings`: `ShowConversationTitle` and `ChangeAltTabTitle`, both defaulting to `true`.

- [ ] **Step 1:** Create the solution, WinForms project, and test project targeting `net8.0-windows` with `EnableWindowsTargeting` and nullable enabled.
- [ ] **Step 2:** Write tests proving distinct HWND values produce distinct tracked records and settings defaults are both true.
- [ ] **Step 3:** Run `dotnet test tests/ChatGPTWindowTitleHelper.Tests/ChatGPTWindowTitleHelper.Tests.csproj`; verify the new tests fail because contracts do not exist.
- [ ] **Step 4:** Implement the records and default settings.
- [ ] **Step 5:** Run the focused tests and verify PASS.
- [ ] **Step 6:** Commit with `git add ChatGPTWindowTitleHelper.sln src tests && git commit -m "build: scaffold window title helper"`.

### Task 2: Implement ChatGPT top-level HWND discovery

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Interop/User32.cs`
- Create: `src/ChatGPTWindowTitleHelper/Windows/ChatGptWindowDiscovery.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Windows/ChatGptWindowDiscoveryTests.cs`

**Interfaces:**
- `IChatGptWindowDiscovery.GetWindows() -> IReadOnlyList<IntPtr>`.
- `ChatGptWindowDiscovery` enumerates top-level windows, maps HWND to PID, checks process name `ChatGPT`, excludes known helper windows, and returns unique HWNDs.

- [ ] **Step 1:** Add a test seam around `EnumWindows`, PID lookup, class-name lookup, visibility, and process-name lookup; test that four HWNDs sharing one PID remain four results and helper classes are excluded.
- [ ] **Step 2:** Run the focused tests and verify failure.
- [ ] **Step 3:** Implement safe P/Invoke wrappers and discovery filtering. Do not use `MainWindowHandle`.
- [ ] **Step 4:** Run tests and a manual diagnostic against the four observed HWNDs (`0xC0896`, `0x64133A`, `0xF197C`, `0x10560`).
- [ ] **Step 5:** Commit with `git add src tests && git commit -m "feat: discover ChatGPT windows by HWND"`.

### Task 3: Implement UI Automation conversation title reader

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Automation/IConversationTitleReader.cs`
- Create: `src/ChatGPTWindowTitleHelper/Automation/UiaConversationTitleReader.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Automation/ConversationTitleReaderTests.cs`

**Interfaces:**
- `IConversationTitleReader.TryReadTitle(IntPtr hwnd, out string title) -> bool`.
- `UiaConversationTitleReader` obtains the UIA root from HWND, searches for an element whose `AriaProperties` contains `current=page`, and returns its `Name` only when non-empty.

- [ ] **Step 1:** Add a fake UIA tree provider and tests for matching `current=page`, ignoring non-current conversations, empty names, and temporary provider exceptions.
- [ ] **Step 2:** Run focused tests and verify failure.
- [ ] **Step 3:** Implement UIA condition composition and bounded descendant search; catch COM/UIA exceptions per call.
- [ ] **Step 4:** Run tests and a manual check against all four user-provided HWNDs, recording only success/failure and titles locally.
- [ ] **Step 5:** Commit with `git add src tests && git commit -m "feat: read current ChatGPT conversation title"`.

### Task 4: Add per-window refresh and title caching

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Windows/WindowTracker.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Windows/WindowTrackerTests.cs`

**Interfaces:**
- `WindowTracker.Refresh(IReadOnlyList<IntPtr>)` maintains HWND-keyed state.
- `WindowTracker.TryApplyReadTitle(IntPtr hwnd)` updates only on a non-empty successful read.
- Failed reads preserve the last valid title; first failure exposes `ChatGPT`.

- [ ] **Step 1:** Write tests for add/remove windows, title caching, no-op unchanged titles, and process restart with new HWNDs.
- [ ] **Step 2:** Run focused tests and verify failure.
- [ ] **Step 3:** Implement the tracker with injected discovery and title reader.
- [ ] **Step 4:** Run tests and verify PASS.
- [ ] **Step 5:** Commit with `git add src tests && git commit -m "feat: track ChatGPT windows independently"`.

### Task 5: Implement overlay window

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Overlay/TitleOverlayForm.cs`
- Create: `src/ChatGPTWindowTitleHelper/Overlay/OverlayManager.cs`
- Modify: `src/ChatGPTWindowTitleHelper/Interop/User32.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Overlay/OverlayGeometryTests.cs`

**Interfaces:**
- `OverlayManager.SetTitle(IntPtr hwnd, string title)`.
- `OverlayManager.Reposition(IntPtr hwnd)`.
- `OverlayManager.Remove(IntPtr hwnd)`.

- [ ] **Step 1:** Write geometry tests for normal, maximized, minimized, DPI-scaled, and multi-monitor rectangles using injected window metrics.
- [ ] **Step 2:** Run focused tests and verify failure.
- [ ] **Step 3:** Implement a borderless, transparent, non-activating tool window with `WS_EX_NOACTIVATE`, `WS_EX_TRANSPARENT`, and owner/visibility settings that exclude it from Alt+Tab/taskbar.
- [ ] **Step 4:** Read `SPI_GETNONCLIENTMETRICS` for the system caption font; use system font fallback and one-line ellipsis rendering.
- [ ] **Step 5:** Wire move/resize/DPI/state refresh and remove overlays when the target HWND is invalid.
- [ ] **Step 6:** Run unit tests and manual click-through/focus/Alt+Tab checks.
- [ ] **Step 7:** Commit with `git add src tests && git commit -m "feat: add click-through title overlays"`.

### Task 6: Implement Alt+Tab window-title writer and restoration

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Windows/WindowTitleWriter.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Windows/WindowTitleWriterTests.cs`

**Interfaces:**
- `WindowTitleWriter.Apply(TrackedWindow window, string conversationTitle)`.
- `WindowTitleWriter.Restore(TrackedWindow window)`.

- [ ] **Step 1:** Write tests for `<title> - ChatGPT`, unchanged-title no-op, first-write original-title capture, and restoration.
- [ ] **Step 2:** Run focused tests and verify failure.
- [ ] **Step 3:** Implement `GetWindowText`/`SetWindowText` through injected Win32 functions and guard invalid HWNDs.
- [ ] **Step 4:** Add a `2000ms` scheduler that applies only changed titles.
- [ ] **Step 5:** Run tests and manually inspect Alt+Tab; verify overlay remains functional if the app overwrites Window Text.
- [ ] **Step 6:** Commit with `git add src tests && git commit -m "feat: update ChatGPT Alt-Tab titles"`.

### Task 7: Add settings, tray menu, single instance, and lifecycle orchestration

**Files:**
- Create: `src/ChatGPTWindowTitleHelper/Program.cs`
- Create: `src/ChatGPTWindowTitleHelper/ApplicationContext.cs`
- Create: `src/ChatGPTWindowTitleHelper/Settings/SettingsStore.cs`
- Create: `src/ChatGPTWindowTitleHelper/Tray/TrayMenu.cs`
- Create: `tests/ChatGPTWindowTitleHelper.Tests/Settings/SettingsStoreTests.cs`

**Interfaces:**
- `SettingsStore.Load() -> AppSettings` and `Save(AppSettings settings)`.
- `ApplicationContext` owns timers, discovery, tracker, overlays, title writer, and shutdown cleanup.

- [ ] **Step 1:** Write settings tests for missing, valid UTF-8, invalid, and partially populated JSON.
- [ ] **Step 2:** Run focused tests and verify failure.
- [ ] **Step 3:** Implement AppData path creation, UTF-8 JSON persistence, and default recovery.
- [ ] **Step 4:** Add a named mutex to prevent duplicate app instances.
- [ ] **Step 5:** Add tray menu labels `Status`, `Show Conversation Title`, `Change Alt+Tab Title`, and `Exit`; persist toggles immediately.
- [ ] **Step 6:** Add `1000ms` discovery/title refresh and UIA event subscription with polling fallback; isolate exceptions per HWND.
- [ ] **Step 7:** On exit, remove overlays, restore original window titles, dispose timers, tray icon, and UIA handlers.
- [ ] **Step 8:** Run all tests and manually exercise create/close/reopen/minimize/restore/toggle flows.
- [ ] **Step 9:** Commit with `git add src tests && git commit -m "feat: add tray app lifecycle and settings"`.

### Task 8: Publish and release verification

**Files:**
- Modify: `src/ChatGPTWindowTitleHelper/ChatGPTWindowTitleHelper.csproj`
- Create: `README.md`
- Create: `scripts/publish.ps1`

- [ ] **Step 1:** Configure x64 self-contained single-file publish with trimming disabled unless verified safe for UIA/WinForms.
- [ ] **Step 2:** Run `dotnet test` for the complete test suite.
- [ ] **Step 3:** Run `powershell -ExecutionPolicy Bypass -File scripts/publish.ps1` and verify the EXE exists under `artifacts/publish/win-x64`.
- [ ] **Step 4:** Manually run the portable EXE with four ChatGPT windows and verify all success criteria from the spec.
- [ ] **Step 5:** Document launch, limitations, settings path, and known ChatGPT title overwrite behavior in `README.md`.
- [ ] **Step 6:** Commit with `git add src README.md scripts && git commit -m "build: publish portable ChatGPT title helper"`.

## Plan Self-Review

- Spec coverage: discovery, UIA extraction, caching, events/polling, overlay, typography/DPI, Alt+Tab title, tray settings, lifecycle recovery, Unicode, release build, and exclusions are all assigned above.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: all cross-task interfaces are named and used consistently; HWND identity is `IntPtr` throughout.
- Scope: one application plan; the subsystems share one lifecycle and produce no independently useful product without the host.
