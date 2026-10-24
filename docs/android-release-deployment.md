# إصدار Qayd على Android

ينشئ مسار الإصدار ملفات Android عند دفع Git tag بصيغة `v1.2.3` أو `v1.2.3+45`. قبل البناء، يشغّل التحليل الثابت وكل اختبارات Flutter. ثم يبني APK وAAB موقّعين، ويتحقق من توقيع APK ومعرّف الحزمة ورقم الإصدار قبل نشر GitHub Release. لا تنفّذ عملية نشر فعلية بمجرد تعديل الشيفرة؛ النشر يبدأ فقط عند دفع tag.

يعمل إصدار التطبيق فقط في المستودع المستقل `Emran025/qayd` عبر `.github/workflows/build-release.yml`. المستودع المجمّع `Emran025/qayd_app` مخصص لاختبارات Flutter وبناء smoke، ولا ينشر التطبيق أو الـAPI. نشر الـAPI منفصل في `Emran025/qayd_api` عبر `.github/workflows/deploy.yml` عند الدفع إلى `main`.

## الهوية ورقم الإصدار

يجب ضبط Repository Variable باسم `QAYD_ANDROID_APPLICATION_ID` على معرّف نهائي وفريد، مثل `com.company.qayd`. يرفض workflow القيمة الافتراضية `com.example.qayd` ويفرض تمرير المعرّف نفسه إلى Gradle. تغيير معرّف التطبيق بعد نشره يكوّن تطبيقاً جديداً ولا يحدّث النسخة المنشورة.

يأتي `versionName` من Git tag. في `v1.2.3` يستخدم `versionCode` رقم تشغيل GitHub Actions، وفي `v1.2.3+45` يستخدم الرقم `45`. يجب اختيار رقم أعلى من أي `versionCode` سبق نشره خارج GitHub، خصوصاً إذا سبق توزيع التطبيق عبر Google Play.

## إعداد GitHub Actions

أضف الأسرار والمتغيرات أدناه في مستودع التطبيق المستقل `Emran025/qayd`، لا في المستودع المجمّع.

### Secrets المطلوبة

| الاسم | الاستخدام |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | النسخة المشفرة Base64 من keystore الإنتاج |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور keystore |
| `ANDROID_KEY_ALIAS` | اسم alias الخاص بمفتاح التوقيع |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |
| `QAYD_API_URL` | عنوان API الإنتاج، ويجب أن يبدأ بـ`https://` |

إذا كان `SENTRY_ENABLED=true`، يلزم أيضاً Secret باسم `SENTRY_DSN`. `REVERB_APP_KEY` اختياري إذا كان مفتاح WebSocket مطلوباً للإنتاج.

### Variables الاختيارية

| الاسم | الاستخدام |
|---|---|
| `QAYD_ANDROID_APPLICATION_ID` | إلزامي: معرّف Android النهائي والفريد |
| `SENTRY_ENABLED` | `true` أو `false`؛ الافتراضي `false` |
| `SENTRY_ENV` | بيئة Sentry، الافتراضي `production` |
| `SENTRY_RELEASE` | معرّف إصدار اختياري لـSentry |
| `SENTRY_DIST` | معرّف توزيع اختياري لـSentry |

يولد workflow ملفات التوقيع مؤقتاً داخل runner، يتحقق من keystore قبل البناء، ويحذف الملفات المؤقتة بعده. احتفظ بنسخة مشفرة خارج المستودع من keystore وكلمات المرور؛ فقدانها قد يمنع تحديث التطبيق.

## الملفات الناتجة

ينشر GitHub Release:

- `qayd-vX.Y.Z.apk`: APK مرتبط بالنسخة.
- `qayd.apk`: اسم ثابت لأحدث APK.
- `qayd-vX.Y.Z.aab`: Android App Bundle صالح للرفع إلى Google Play.
- `qayd-debug-info-vX.Y.Z.zip`: رموز فك التعتيم اللازمة لتحليل أعطال النسخة.
- `signing-certificate.txt` و`SHA256SUMS`: معلومات شهادة التوقيع وبصمات SHA-256 للملفات.

تُرفع الرموز الخام أيضاً كـGitHub Actions artifact لمدة 90 يوماً. احتفظ بنسخة مناسبة من الرموز لكل إصدار إنتاجي.

## ما لا ينشره المسار تلقائياً

لا يرفع workflow الـAAB إلى Google Play؛ يلزم قرار منفصل وحساب Play Console ومسار نشر محمي قبل إضافة ذلك. كما لا توجد حالياً مسارات إنتاج موقّعة لـiOS أو macOS؛ ففحوص تلك المنصات في CI هي فحوص بناء فقط. وميزة Shorebird تحتاج `app_id` حقيقياً و`SHOREBIRD_TOKEN` وإعدادات التوقيع نفسها قبل أن تعمل.

## قبل أول tag إنتاجي

1. ثبّت معرّف Android النهائي وتأكد أنه يطابق التطبيق الموجود إن كان قد نُشر سابقاً.
2. أضف الأسرار والمتغيرات المطلوبة في المستودع الصحيح، ولا تضع مفاتيح التوقيع في Git أو في ملفات إعداد متتبعة.
3. تأكد أن API يعمل عبر HTTPS، وأن الإعدادات ونسخة keystore تخص التطبيق نفسه.
4. راجع نجاح فحوص PR، ثم أنشئ tag جديداً ورقم بناء غير مستخدم.
5. ثبّت APK على جهاز اختبار قبل التوزيع، وتحقق من تسجيل الدخول والمزامنة وقاعدة البيانات المشفرة والكاميرا والإشعارات.
