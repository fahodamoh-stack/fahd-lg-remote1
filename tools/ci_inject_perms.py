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

# permission_handler_android requires compileSdk 37+, while
# `flutter create` still generates 36. Bump it.
GRADLE = pathlib.Path("android/app/build.gradle.kts")
if not GRADLE.exists():
    print(f"build file not found: {GRADLE}")
    sys.exit(1)

g = GRADLE.read_text(encoding="utf-8")
if "compileSdk = 37" in g:
    print("compileSdk already 37")
elif "compileSdk = flutter.compileSdkVersion" in g:
    g = g.replace(
        "compileSdk = flutter.compileSdkVersion", "compileSdk = 37", 1
    )
    GRADLE.write_text(g, encoding="utf-8")
    print("compileSdk bumped to 37")
else:
    print("compileSdk line not recognized, leaving as-is")
    print([line for line in g.splitlines() if "compileSdk" in line])
