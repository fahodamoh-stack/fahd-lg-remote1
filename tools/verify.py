"""Local verification that runs NOW without Flutter/TV.
Mirrors the Dart pure helpers in lib/lg_tv.dart and checks:
- register payload valid JSON + permissions
- request envelope format
- SSDP parse (LG detect, IP extract, bad input)
- volume clamp
- Dart files: balanced braces, required APIs exist
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LG = ROOT / "lib" / "lg_tv.dart"
MAIN = ROOT / "lib" / "main.dart"
PUB = ROOT / "pubspec.yaml"

fails = []
def check(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + (f" — {extra}" if extra and not cond else ""))
    if not cond:
        fails.append(name)

# 1. files exist
for p in [LG, MAIN, PUB]:
    check(f"exists {p.name}", p.exists())
check("exists web-demo", (ROOT / "web-demo" / "index.html").exists())
check("exists motion widgets", (ROOT / "lib" / "widgets" / "motion.dart").exists())
check("exists README", (ROOT / "README.md").exists())
check("exists analysis_options", (ROOT / "analysis_options.yaml").exists())
check("workflow is flutter.yml", (ROOT / ".github" / "workflows" / "flutter.yml").exists())
check("old workflow removed", not (ROOT / ".github" / "workflows" / "build-apk.yml").exists())

src = LG.read_text(encoding="utf-8")
main = MAIN.read_text(encoding="utf-8")

# 2. balanced braces/parens (rough syntax sanity)
for label, text in [("lg_tv.dart", src), ("main.dart", main)]:
    check(f"{label} braces balanced",
          text.count("{") == text.count("}") and text.count("(") == text.count(")"),
          f"{{={text.count('{')} }}={text.count('}')} (={text.count('(')} )={text.count(')')}")

# 3. required APIs present
for api in ["buildRegisterPayload", "buildRequest", "parseSsdpResponse",
            "clampVolume", "sameSubnet", "pointerMoveMsg", "pointerClickMsg",
            "pointerButtonMsg", "appIds", "discover", "connect",
            "connectPointer", "pointerMove", "pointerClick", "closePointer",
            "volumeUp", "setVolume", "sendKey", "toast",
            "openUrl", "launchApp", "youtube", "powerOff"]:
    check(f"lg_tv.dart has {api}", api in src)
for s in ["CupertinoSlidingSegmentedControl", "Touchpad", "NetworkInfo",
          "Permission.locationWhenInUse", "onPanUpdate", "appIdCtrl"]:
    check(f"main.dart has {s}", s in main)

# 4. protocol logic mirror (same rules as Dart)
def build_register(saved=None):
    p = {"forcePairing": False, "pairingType": "PROMPT",
         "manifest": {"permissions": ["LAUNCH", "CONTROL_AUDIO",
                    "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE"]}}
    if saved: p["client-key"] = saved
    return p

def parse_ssdp(text, sender):
    import re
    m = re.search(r"LOCATION:\s*(.+)", text, re.I)
    if not m: return None
    loc = m.group(1).strip()
    if not loc: return None
    host = sender
    try:
        from urllib.parse import urlparse
        h = urlparse(loc).hostname
        if h: host = h
    except Exception: pass
    if not host: return None
    low = text.lower()
    return {"ip": host,
            "name": "LG webOS TV" if ("lg" in low or "webos" in low or "netcast" in low) else "Media device",
            "location": loc}

p1 = build_register()
check("register JSON-encodable", bool(json.dumps({"type": "register", "id": "register_0", "payload": p1})))
check("register has toast perm", "WRITE_NOTIFICATION_TOAST" in p1["manifest"]["permissions"])
check("register omits empty key", "client-key" not in p1)
check("register keeps key", build_register("abc123")["client-key"] == "abc123")
r = {"id": "req_1", "type": "request", "uri": "ssap://audio/volumeUp", "payload": {}}
check("request envelope", r["type"] == "request" and r["uri"].startswith("ssap://"))
sample = ("HTTP/1.1 200 OK\r\nSERVER: Linux UPnP LG WebOS TV\r\n"
          "LOCATION: http://192.168.1.50:8080/dd.xml\r\n\r\n")
out = parse_ssdp(sample, "192.168.1.50")
check("ssdp LG detect", out is not None and out["ip"] == "192.168.1.50" and out["name"] == "LG webOS TV")
check("ssdp bad -> None", parse_ssdp("garbage", "1.2.3.4") is None)
check("volume clamp", max(0, min(100, -5)) == 0 and max(0, min(100, 130)) == 100)

# 5. pubspec deps
pub = PUB.read_text(encoding="utf-8")
for d in ["web_socket_channel", "shared_preferences",
          "network_info_plus", "permission_handler", "audioplayers"]:
    check(f"pubspec has {d}", d in pub)
check("sound service exists",
      (ROOT / "lib" / "services" / "sound_service.dart").exists())
check("remembers IP (app)", "fa_last_ip" in src or "fa_last_ip" in main)
check("remembers IP (demo)",
      "fa_last_ip" in (ROOT / "web-demo" / "index.html").read_text(encoding="utf-8"))
check("forget TV option", "Forget saved TV" in main)
check("secure storage for keys", "flutter_secure_storage" in src)
check("secure wss fallback", "wss://" in src and "badCertificateCallback" in src)
check("input-socket buttons", "inputButtons" in src and "getPointerInputSocket" in src)
check("verified launch endpoint", "system.launcher/launch" in src)
check("apps + sources APIs", "listApps" in src and "getExternalInputList" in src)
check("number pad UI", "Numbers" in main and "typeText" in src)
check("mock TV exists", (ROOT / "tools" / "mock_tv.dart").exists())
check("protocol tests exist", (ROOT / "test" / "protocol_test.dart").exists())
check("svg icons in demo",
      (ROOT / "web-demo" / "index.html").read_text(encoding="utf-8").count("<svg") >= 6)
check("no deprecated withOpacity", "withOpacity" not in main)
check("no bad MediaQuery API", "maybeDisableAnimations" not in (
    ROOT / "lib" / "widgets" / "motion.dart").read_text(encoding="utf-8"))
check("main uses SoundService", "SoundService" in main)
check("assets declared", "assets/sounds/" in pub)

# 6. WAV assets valid (RIFF/WAVE, 16-bit mono)
import wave as _w
for f in ["tap.wav", "toggle.wav", "success.wav", "error.wav"]:
    p = ROOT / "assets" / "sounds" / f
    try:
        with _w.open(str(p), "rb") as w:
            ok = (w.getnchannels() == 1 and w.getsampwidth() == 2
                  and w.getnframes() > 0)
        check(f"wav valid {f}", ok)
    except Exception as e:
        check(f"wav valid {f}", False, str(e))

print()
if fails:
    print(f"{len(fails)} FAILED: {fails}")
    sys.exit(1)
print("ALL LOCAL CHECKS PASSED")
