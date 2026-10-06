"""CI helper: inject local-network permissions into the generated
AndroidManifest.xml. Run after `flutter create` in GitHub Actions."""
import pathlib
import sys

MANIFEST = pathlib.Path("android/app/src/main/AndroidManifest.xml")

PERMS = (
    '<uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>\n'
    '    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    "    "
)

if not MANIFEST.exists():
    print(f"manifest not found: {MANIFEST}")
    sys.exit(1)

text = MANIFEST.read_text(encoding="utf-8")
if "ACCESS_WIFI_STATE" in text:
    print("permissions already present")
else:
    text = text.replace("<application", PERMS + "<application", 1)
    MANIFEST.write_text(text, encoding="utf-8")
    print("permissions injected")
