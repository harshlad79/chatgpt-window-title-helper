#!/usr/bin/env python3
"""Version-pinned, read-only audit of ChatGPT conversation menu href wiring.

No app launch, AX interaction, IPC, clipboard, conversation data, or writes.
This is static evidence only: AXURL exposure and native new-window behavior
require separate, user-facing live E2E verification.
"""
import hashlib
import json
import struct
from pathlib import Path

ASAR = Path("/Applications/ChatGPT.app/Contents/Resources/app.asar")
ASSET = "app-primary-7d7313419f84.js"
EXPECTED_SHA256 = "745529956e303674c268a6871e6f5aad49eca7ef5af899952bf0379d829821b6"


def read_asset():
    with ASAR.open("rb") as handle:
        header = struct.unpack("<4I", handle.read(16))
        if header[0] != 4 or header[1] <= 0 or header[3] > 30_000_000:
            raise ValueError("unexpected ASAR header")
        index = json.loads(handle.read(header[3]).decode("utf-8"))
        entry = index["files"]["webview"]["files"]["assets"]["files"][ASSET]
        handle.seek(8 + header[1] + int(entry["offset"]))
        data = handle.read(int(entry["size"]))
        if len(data) != int(entry["size"]):
            raise ValueError("truncated asset")
        return data


def section(source, start, end):
    if source.count(start) != 1:
        raise AssertionError("missing or ambiguous static section")
    return source.split(start, 1)[1].split(end, 1)[0]


def main():
    data = read_asset()
    src = data.decode("utf-8")
    menu = section(src, "function yer(e,t){", "var ber,xer;")
    builder = section(src, "function ver(e,t){", "function yer(e,t){")
    wrapper = section(src, "function Xq(e,t){", "function Zq(")
    checks = {
        "installed asset SHA256 pinned": hashlib.sha256(data).hexdigest() == EXPECTED_SHA256,
        "menu requires conversationId": "if(t.conversationId==null)return" in menu,
        "menu constructs canonical conversation href": "https://chatgpt.com/c/${encodeURIComponent(t.conversationId)}" in menu,
        "open-in-chatgpt action carries href": "id:`open-in-chatgpt`" in menu and "href:s" in menu,
        "menu click uses browser bridge": "onClick:e=>oS({event:e,href:s,initiator:`open_in_browser_bridge`})" in menu,
        "menu select uses browser bridge": "onSelect:()=>Zw({href:s,initiator:`open_in_browser_bridge`})" in menu,
        "menu action mapped through Xq": ".map(t=>Xq(e,t))" in builder,
        "Xq retains source action properties": "return{...t,accelerator:" in wrapper,
        "single open-in-chatgpt item": menu.count("id:`open-in-chatgpt`") == 1,
        "menu does not invoke native new-window IPC": "open-in-new-window" not in menu,
    }
    for name, passed in checks.items():
        print(("PASS" if passed else "FAIL"), name)
    print("ASSERTIONS", sum(checks.values()), "/", len(checks))
    if not all(checks.values()):
        raise AssertionError("installed ChatGPT menu contract changed")
    print("MENU_HREF_BUILT_FROM_CONVERSATION_ID=STATIC_VERIFIED")
    print("AXURL_EXPOSED=NOT_VERIFIED")
    print("NATIVE_NEW_WINDOW=NOT_VERIFIED")
    print("LIVE_E2E=NOT_EXECUTED")


if __name__ == "__main__":
    main()
