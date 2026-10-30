#!/usr/bin/env python3
"""Read-only static audit of the installed macOS ChatGPT Electron route guard.

Version-specific: ASAR module names and minified symbols are pinned to the
2026-10-30 MacMini2 installation. A future app update must be re-audited.
This does NOT execute ChatGPT JS, inject IPC, open windows, or prove E2E.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


MODULES = (
    "main-0FVbxCQU.js",
    "src-CTNXdakG.js",
    "desktop-open-path-queue-tez0sDbS.js",
)


def load_modules(asar: Path):
    with asar.open("rb") as f:
        header = struct.unpack("<4I", f.read(16))
        if header[0] != 4 or not 0 < header[3] < 30_000_000:
            raise ValueError("unexpected ASAR header")
        index = json.loads(f.read(header[3]).decode("utf-8"))
        files = index["files"][".vite"]["files"]["build"]["files"]
        output = {}
        for name in MODULES:
            entry = files[name]
            f.seek(8 + header[1] + int(entry["offset"]))
            data = f.read(int(entry["size"]))
            if len(data) != int(entry["size"]):
                raise ValueError("truncated ASAR entry: " + name)
            output[name] = data
        return output


def verify(modules):
    main, src, queue = (modules[name] for name in MODULES)
    at = src.find(b"function sn(")
    validator = src[at:at + 600] if at >= 0 else b""
    checks = {
        "main imports route module": b'i=require("./src-CTNXdakG.js")' in main[:1500],
        "main imports handoff module": b'm=require("./desktop-open-path-queue-tez0sDbS.js")' in main[:1500],
        "guard is three-way OR": b"function Z7(e){return i.ao(e)||Y_t(e)||m.f(e)!=null}" in main,
        "i.ao resolves to sn": b'Object.defineProperty(exports,"ao",{enumerable:!0,get:function(){return sn}})' in src,
        "sn recognizes space": b"e===`/space`" in validator,
        "sn recognizes local and remote": b"ln(e,Mt)" in validator and b"ln(e,It)" in validator,
        "sn has no /c route": b"/c/" not in validator,
        "m.f resolves to s": b'Object.defineProperty(exports,"f",{enumerable:!0,get:function(){return s}})' in queue,
        "s only parses browser handoff": b"function s(e){let t=`\${i}?`;" in queue and b'i=`/browser/handoff`' in queue,
        "Y_t recognizes o/dots": b"function Y_t(e){let t=/^\\/(?:o|dots)\\/" in main,
    }
    for name, ok in checks.items():
        print(("PASS" if ok else "FAIL") + " " + name)
    print("STATIC_ASSERTIONS", sum(checks.values()), "/", len(checks))
    for name in MODULES:
        print("MODULE_SHA256_PREFIX", name, hashlib.sha256(modules[name]).hexdigest()[:16])
    if not all(checks.values()):
        raise AssertionError("Static route evidence changed; re-audit required")
    print("CHATGPT_C_UUID_VIA_OPEN_IN_NEW_WINDOW=STATICALLY_REJECTED")
    print("NATIVE_WINDOW_E2E=NOT_EXECUTED")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asar", default="/Applications/ChatGPT.app/Contents/Resources/app.asar")
    args = parser.parse_args()
    verify(load_modules(Path(args.asar)))


if __name__ == "__main__":
    main()
