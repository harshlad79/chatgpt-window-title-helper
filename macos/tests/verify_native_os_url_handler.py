#!/usr/bin/env python3
"""Read-only, version-pinned macOS ChatGPT URL-handler audit.

Inspects Info.plist and three installed ASAR modules; never opens a URL,
creates a window, invokes IPC, reads chat content, or changes app state.
"""
import hashlib
import json
import plistlib
import struct
from pathlib import Path

APP = Path("/Applications/ChatGPT.app")
MODULES = ("bootstrap-CoL4UX0u.js", "desktop-open-path-queue-tez0sDbS.js", "main-0FVbxCQU.js")
EXPECTED_SHA_PREFIX = {
    "desktop-open-path-queue-tez0sDbS.js": "5699e72f3d3c1db5",
    "main-0FVbxCQU.js": "fad45aa7d81de6fe",
}

def read_modules():
    asar = APP / "Contents/Resources/app.asar"
    with asar.open("rb") as handle:
        header = struct.unpack("<4I", handle.read(16))
        if header[0] != 4 or not 0 < header[3] < 30000000:
            raise ValueError("unexpected ASAR header")
        index = json.loads(handle.read(header[3]).decode("utf-8"))
        files = index["files"][".vite"]["files"]["build"]["files"]
        output = {}
        for name in MODULES:
            entry = files[name]
            handle.seek(8 + header[1] + int(entry["offset"]))
            data = handle.read(int(entry["size"]))
            if len(data) != int(entry["size"]):
                raise ValueError("truncated module " + name)
            output[name] = data
        return output

def main():
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    modules = read_modules()
    bootstrap, queue, mainjs = (modules[name] for name in MODULES)
    schemes = {s for t in info.get("CFBundleURLTypes", []) for s in t.get("CFBundleURLSchemes", [])}
    checks = {
        "bundle registers codex/http/https": {"codex", "http", "https"}.issubset(schemes),
        "queue module version pinned": hashlib.sha256(queue).hexdigest().startswith(EXPECTED_SHA_PREFIX[MODULES[1]]),
        "main module version pinned": hashlib.sha256(mainjs).hexdigest().startswith(EXPECTED_SHA_PREFIX[MODULES[2]]),
        "deep-link parser dN": b"function dN(e){let t;try{t=new URL(e)}" in bootstrap,
        "deep-link browser handoff delegation": b"let r=u.l(t);if(r!=null)return r" in bootstrap,
        "browser handoff only queue l": b"e.pathname!==`/browser/handoff`" in queue,
        "share fallback not chat c": b"function mN(e){let[t,n,r,i]=Z(e)" in bootstrap and b"if(t!==`share`" in bootstrap,
        "generic HTTP fallback jN": b"function jN(e){if(e.trim()!==e)" in bootstrap,
        "open-url falls back to HTTP queue": b"let r=jN(e);r&&(C(r)" in bootstrap,
        "HTTP queue uses primary window": b"let i=n??await r();i&&h.at(-1)===t" in bootstrap and b"await f?.(i,t.urlString)" in bootstrap,
        "main callback targets browser panel": b"openHttpUrl:(e,t)=>{h.windowManager.sendMessageToWebContents(e.webContents" in mainjs and b"toggle-browser-panel" in mainjs and b"initiator:`os_open`" in mainjs,
    }
    for name, passed in checks.items():
        print(("PASS" if passed else "FAIL") + " " + name)
    print("ASSERTIONS", sum(checks.values()), "/", len(checks))
    for name in MODULES:
        print("MODULE_SHA256_PREFIX", name, hashlib.sha256(modules[name]).hexdigest()[:16])
    if not all(checks.values()):
        raise AssertionError("installed URL-handler implementation changed; re-audit required")
    print("HTTPS_CHAT_C_URL_NATIVE_NEW_WINDOW=NOT_PROVEN")
    print("GENERIC_HTTPS_OPEN_URL=PRIMARY_WINDOW_BROWSER_PANEL_STATIC_PATH")
    print("LIVE_E2E=NOT_EXECUTED")

if __name__ == "__main__":
    main()
