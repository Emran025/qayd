# Shorebird OTA لتطبيق Qayd

يستخدم Qayd Shorebird كتطبيق واحد. ملف `shorebird.yaml` يحتوي حالياً على قيمة placeholder، لذلك Shorebird غير مهيأ ولا تصدر مسارات CI أي patch أو release حتى يوضع `app_id` الحقيقي الذي ينشئه Shorebird. لا يجوز اختلاق هذا المعرّف أو استخدام معرّف تطبيق آخر. قيمة `app_id` تعريف عام وليست سراً.

تطبيق Qayd مضبوط على `auto_update: false` حتى يعرض حالة التحديث للمستخدم ويطلب منه إعادة فتح التطبيق بدلاً من تنزيل تحديث صامت أثناء عمليات حساسة.

## أين يعمل workflow؟

يعمل `.github/workflows/shorebird.yml` في المستودع المستقل `Emran025/qayd` فقط عند تغييرات Flutter على فرع `main`. المستودع المجمّع `Emran025/qayd_app` مخصص للاختبارات ولا ينشر التطبيق أو يطلق OTA. أما الـAPI فينشر بشكل مستقل من `Emran025/qayd_api`.

في المستودع المستقل، تغييرات Dart فقط مرشحة لـ`shorebird patch android --release-version latest`، أما تغييرات Android أو الأصول أو الاعتماديات أو `shorebird.yaml` فتتطلب `shorebird release android`. خيار التشغيل اليدوي `force_release` يفرض المسار الأصلي عند الحاجة. هذه الأوامر تسجل baseline أو patch لدى Shorebird؛ لا ترفع AAB إلى Google Play. مسار GitHub Release المنفصل يبني APK وAAB عند دفع tag.

## الإعداد المطلوب قبل تشغيله

1. أنشئ تطبيق Shorebird باسم Qayd من حساب مخوّل، ثم ضع `app_id` الناتج في `shorebird.yaml`.
2. أضف GitHub Secret باسم `SHOREBIRD_TOKEN`.
3. أضف أسرار `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, و`QAYD_API_URL` إلى مستودع `qayd`.
4. أضف Repository Variable باسم `QAYD_ANDROID_APPLICATION_ID` نفسه المستخدم في GitHub Android Release. يجب أن يكون معرّفاً نهائياً وفريداً، لا `com.example.qayd`.
5. إذا فُعّل Sentry بمتغير `SENTRY_ENABLED=true`، أضف `SENTRY_DSN` كـSecret.
6. أنشئ baseline Shorebird أصلياً أولاً؛ لا يمكن إرسال patch إلى `latest` قبل وجود release مطابق للتطبيق ومعرّف الحزمة والتوقيع.

استخدم keystore الإنتاج نفسه لكل إصدار وpatch؛ لا تنشئ مفتاح توقيع جديداً لكل تحديث. لا تُرسل `SHOREBIRD_TOKEN` أو ملفات keystore أو كلمات المرور في Git أو في محادثة.

## التحديث داخل التطبيق

يفحص `AppUpdateCubit` الحالة بعد ظهور واجهة Qayd المسجلة الدخول ولا يحجب splash أو فتح قاعدة البيانات. إذا توفر patch يعرض التطبيق Banner مترجماً، ويتيح تنزيله، ثم يوضح أن إغلاق التطبيق وإعادة فتحه مطلوبان لتفعيله. إذا لم يكن التطبيق مبنياً بواسطة Shorebird أو لم يكن المحرك متاحاً على المنصة، تكون الحالة `unavailable` ولا تمنع تشغيل التطبيق.

## مراجع

- [Shorebird Initialize](https://docs.shorebird.dev/code-push/initialize/)
- [Shorebird GitHub Integration](https://docs.shorebird.dev/code-push/ci/github/)
- [Shorebird Create a Patch](https://docs.shorebird.dev/code-push/patch/)
- [Shorebird Create a Release](https://docs.shorebird.dev/code-push/release/)
- [shorebird_code_push API](https://pub.dev/documentation/shorebird_code_push/latest/)
