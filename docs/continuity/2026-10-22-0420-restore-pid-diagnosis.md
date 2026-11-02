# 2026-10-22 04:20 KST — Restore session selection diagnosis

Canonical feature branch HEAD at read: `ebe7af52e7eba7a500ed2a039b6dcce6babb0285`.
This is a diagnostic checkpoint, **not** a deployed fix or a passing full E2E test.

## Confirmed source defect

`WindowSessionHistoryStore.lastSessionTargets()` unconditionally chooses `previousSessionOpen` when nonempty. But `observe(pid:...)` only transfers `lastCompleteOpen` to `previousSessionOpen` **after** the first complete AX census of a newly started ChatGPT process.

Consequently, if persisted `appPID=411`, `lastCompleteOpen=[New]`, `previousSessionOpen=[A,B]`, and the running process is PID 412 with no complete AX census yet, the current function incorrectly targets A,B instead of New. This is a deterministic code-level defect; no live restore was attempted in this checkpoint.

## Proposed minimal patch

- Require the current ChatGPT PID when selecting targets. If `pid != snapshot.appPID` and both PIDs are positive, choose `lastCompleteOpen` (the most recently persisted process). If PIDs match, choose nonempty `previousSessionOpen`, falling back to `lastCompleteOpen`.
- Pass current PID consistently to `lastSessionTargets`, `recoverable`, and `hasPendingRestart` from `ChatGPTTitleHelper.swift`.
- Regression cases: consecutive restart before first complete census; first complete census after restart; same-PID restore; no history; incomplete AX census; duplicate-title limitations.
- Retain existing 12-second shrink grace, 0600 file permissions, original NativeTitleSync, Windows sources, and Draft PR #3 unmerged.

## Runtime and blockers

Read-only TheCompany Dev MCP succeeded: ChatGPT PID 1229; TitleHelper process absent; installed TitleHelper executable dated 2026-10-17 05:32:19 local time. No ChatGPT windows were closed, restarted, or overwritten. One source update attempt was rejected by tool safety checks; therefore no code fix, deployment, or E2E success is claimed.

## Next execution

1. Re-read canonical branch and this note, then apply a narrowly scoped source/test change only through permitted GitHub write actions.
2. Run Swift tests and optimized build in an isolated MacMini2 checkout at the exact GitHub SHA.
3. Verify signed installation and running helper without touching ChatGPT process; reconcile ambiguous deployment receipts read-only before retry.
4. Validate per-window restoration using real AX title/identity plus screenshot; do not depend exclusively on Dock Recent. Record each stage and outcome in CURRENT.md.
