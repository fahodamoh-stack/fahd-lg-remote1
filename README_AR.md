# Lumina — LG webOS Remote (Flutter — iOS + Android)

## بيشغل ايه؟
- اكتشاف التلفزيون تلقائي (SSDP) + إدخال IP يدوي → شغال مع أي LG webOS
- Pairing مرة واحدة (التلفزيون يعرض Allow) والمفتاح محفوظ
- ريموت كامل: اتجاهات + OK + Home/Back/Exit + صوت + قنوات + Power Off
- كاست: YouTube link + أي URL مباشر + Play/Pause/Stop + رسالة Toast على الشاشة
- UI غامق Premium مع Gradient وموشن (AnimatedContainer + Tab animation + haptics)

## التشغيل
1. ثبّت Flutter 3.22+ (https://docs.flutter.dev/get-started/install)
2. في نفس الواي فاي بتاع التلفزيون:
```
cd lg_remote
flutter pub get
flutter run
```
3. أول مرة دوس Scan، اختار التلفزيون، واقبل Allow على شاشة التلفزيون.

## ملاحظات أمانة (مهم)
- لازم الموبايل والتلفزيون على نفس الواي فاي. غير كده مستحيل يتربط.
- الـ Screen Mirroring الكامل بتاع النظام (AirPlay/Miracast) ماينفعش يتعمل من أب طرف تالت على iOS — اللي هنا هو ريموت + كاست ميديا، وهو المضمون.
- صور/فيديو من جهازك نفسه: iOS بيمنع سيرفر محلي بسهولة. الحل المضمون: ارفع الملف على لينك مباشر والصقه في Cast. الـ YouTube والروابط المباشرة شغالة 100%.
- بناء نسخة iPhone محتاج Mac + Xcode. نسخة Android تتبني من Windows عادي:
```
flutter build apk --release
```

## صلاحيات لازم تضيفها
### Android — android/app/src/main/AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```
+ في الكود اطلب إذن الموقع (Discovery عبر UDP بيحتاجه أندرويد 12+).

### iOS — ios/Runner/Info.plist
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Find and control your LG TV on local Wi-Fi</string>
<key>NSBonjourServices</key>
<array><string>_http._tcp</string></array>
```

## لو التلفزيون قديم قبل webOS؟
معظم LG من 2014+ webOS وشغال بـ ws://TV:3000. لو Netcast قديم جدا، الـ IP اليدوي + فتح Browser من الأب هو البديل.
