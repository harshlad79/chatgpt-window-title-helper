# macOS native-title hooking feasibility smoke test

Date: 2026-10-16 KST. Target: the original ChatGPT Dock right-click **window list** native caption, not ChatGPT's internal conversation title.

## Scope

Owner requested a minimal implementation test after discussing injection/hooking. All execution used TheCompany-Dev on MacMini2. The hook was tested only in a disposable, independently-built Cocoa test process. No ChatGPT binary, signing, process memory, title or TCC settings were modified; no signals were sent to ChatGPT. The existing safe passive TitleHelper was left running. The original NativeTitleSync remains disabled and unchanged.

## Experiment A: disposable ordinary Cocoa app

Build a tiny unsandboxed Cocoa app that creates an NSWindow and calls setTitle with "Original Window Label". Build a separate dynamic library using Objective-C runtime method_setImplementation to interpose NSWindow.setTitle and replace that exact test title with "Injected Window Label". Launch the test app with DYLD_INSERT_LIBRARIES pointing only to the test dylib.

Observed:
- Baseline: OWNER_WINDOW_TITLE=Original Window Label.
- Injected: TEST_HOOK_LOADED=YES and OWNER_WINDOW_TITLE=Injected Window Label.
- Result: a same-process AppKit title interception works if a process permits loading the test dylib at startup. This does not establish an ability to inject a library into a **running**, protected third-party process.

## Experiment B: same Cocoa executable with Hardened Runtime

Make a separate copy and ad-hoc sign using codesign --sign - --options runtime. Verified CodeDirectory flags=0x10002(adhoc,runtime).

Observed:
- Without injection: OWNER_WINDOW_TITLE=Original Window Label.
- With the same DYLD_INSERT_LIBRARIES: OWNER_WINDOW_TITLE=Original Window Label, no TEST_HOOK_LOADED marker, exit=0.
- Result: the exact same startup-injection method is ignored/blocked for the hardened **test executable**. This comparison only tests the runtime-protected sample, not all possible injection vectors.

## Experiment C: signed installed ChatGPT, read-only access test

ChatGPT 26.1007.71326 / bundle identifier com.openai.codex:
- CodeDirectory flags=0x10000(runtime), signed by OpenAI Developer ID team 2DC432GLL2.
- App entitlements have NO get-task-allow, allow-dyld-environment-variables, or disable-library-validation.
- On the existing user-owned ChatGPT PID 80584, task_for_pid(mach_task_self(), PID, &port) returned kern_return=5, "(os/kern) failure", with no task port acquired. This was a read-only capability test: no task memory access or write attempted.
- csrutil status: System Integrity Protection enabled.
- ChatGPT remained running, original signed app untouched.

## Conclusion and boundaries

- The Objective-C hook works in an unprotected app, not in the similarly hardened synthetic app.
- No demonstrated authorized injection path exists for the **running signed ChatGPT** with current permissions; the task-port attempt also failed.
- Therefore do not deploy DYLD_INSERT_LIBRARIES, force re-sign ChatGPT, disable SIP, alter TCC, send SIGUSR1, or modify official app binaries as part of this helper.
- A working path for changing the native Dock window-list caption has **not** been established. Do not confuse hook success on a disposable process with successful deployment in ChatGPT.
- Continue to preserve the existing AX conversation-title detection, with all legacy native-writing calls compiled out. If a supported in-process extension/automation API is discovered in future, validate it independently before re-enabling native caption changes.

Local scratch test code and binaries reside only under /tmp/title-hook-smoke.sQOkgB7j on MacMini2; they are not included as production code.
