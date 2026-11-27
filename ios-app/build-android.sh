#!/bin/bash
# בונה את אפליקציית האנדרואיד של סט על המק.
# שימוש:
#   bash build-android.sh emu        מריץ באמולטור (טלפון אנדרואיד וירטואלי) לבדיקה
#   bash build-android.sh 1          בונה קובץ AAB חתום להעלאה ל-Google Play (המספר = versionCode, עולה בכל העלאה)
#   bash build-android.sh 2 1.1      אפשר לתת גם שם גרסה (ברירת מחדל 1.0)
set -e
cd "$(dirname "$0")"
MODE="${1:-emu}"
VNAME="${2:-1.0}"
KS="$HOME/set-upload-key.jks"

echo "== בדיקות מקדימות =="
[ "$(uname)" = "Darwin" ] || { echo "הסקריפט הזה רץ רק על מק"; exit 1; }
command -v node >/dev/null || { echo "חסר Node. להתקין: brew install node"; exit 1; }
AS="/Applications/Android Studio.app"
[ -d "$AS" ] || { echo "חסר Android Studio. להוריד מ-https://developer.android.com/studio , להתקין ולפתוח פעם אחת (Next עד הסוף)"; exit 1; }
export JAVA_HOME="${JAVA_HOME:-$AS/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
[ -d "$ANDROID_HOME" ] || { echo "לא נמצא Android SDK ב-$ANDROID_HOME. לפתוח את Android Studio פעם אחת ולהשלים את ההתקנה"; exit 1; }
java -version 2>&1 | head -1

echo "== התקנת חבילות =="
npm install

if [ ! -d android ]; then
  echo "== יצירת פרויקט אנדרואיד =="
  npx cap add android
fi

echo "== אייקון ומסך פתיחה =="
npx capacitor-assets generate --android --iconBackgroundColor '#0A0A0A' --iconBackgroundColorDark '#0A0A0A' --splashBackgroundColor '#000000' --splashBackgroundColorDark '#000000' || echo "(האייקונים לא נוצרו, ממשיכים)"

echo "== סנכרון =="
npx cap sync android

# התראות: רק אם הורד קובץ google-services.json מ-Firebase ושמור כאן (ios-app/google-services.json)
if [ -f google-services.json ]; then
  cp google-services.json android/app/google-services.json
  node -e "const f='android/app/src/main/assets/capacitor.config.json',c=JSON.parse(require('fs').readFileSync(f));c.android=c.android||{};c.android.appendUserAgent='SetAnd/1 SetFCM/1';require('fs').writeFileSync(f,JSON.stringify(c,null,2))"
  echo "   ✓ התראות (Firebase) מופעלות"
fi

echo "== הרשאות =="
MF=android/app/src/main/AndroidManifest.xml
add_perm() { grep -q "$1" "$MF" || sed -i '' "s#<application#<uses-permission android:name=\"$1\" />\\
    <application#" "$MF"; }
add_perm android.permission.CAMERA
add_perm android.permission.VIBRATE
add_perm android.permission.POST_NOTIFICATIONS
add_perm com.android.vending.BILLING
grep -q 'android.hardware.camera' "$MF" || sed -i '' 's#<application#<uses-feature android:name="android.hardware.camera" android:required="false" />\
    <application#' "$MF"
echo "   ✓"

if [ "$MODE" = "emu" ]; then
  echo "== הרצה באמולטור =="
  echo "אם אין אמולטור: ב-Android Studio ← More Actions ← Virtual Device Manager ← Create device ← Pixel 8 ← Next ← Finish"
  npx cap run android
  exit 0
fi

VCODE="$MODE"
[[ "$VCODE" =~ ^[0-9]+$ ]] || { echo "צריך מספר גרסה, למשל: bash build-android.sh 1"; exit 1; }
echo "== גרסה $VNAME ($VCODE) =="
GR=android/app/build.gradle
sed -i '' -E "s/versionCode [0-9]+/versionCode $VCODE/; s/versionName \"[^\"]*\"/versionName \"$VNAME\"/" "$GR"
grep -E "versionCode|versionName" "$GR"

if [ ! -f "$KS" ]; then
  echo "== יצירת מפתח העלאה (פעם אחת בלבד) =="
  echo "תתבקש לבחור סיסמה. לשמור אותה במקום בטוח, יחד עם גיבוי של הקובץ $KS"
  echo "בלי הקובץ והסיסמה אי אפשר להעלות עדכונים (אפשר לבקש מגוגל איפוס, אבל זה לוקח זמן)."
  keytool -genkeypair -v -keystore "$KS" -alias upload -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Ori Levy, L=Eilat, C=IL"
fi

echo "== בנייה =="
cd android
./gradlew --no-daemon bundleRelease
cd ..
OUT="$HOME/Desktop/Set-android-$VCODE.aab"
echo "== חתימה (הקלד את סיסמת המפתח) =="
jarsigner -sigalg SHA256withRSA -digestalg SHA-256 -keystore "$KS" -signedjar "$OUT" android/app/build/outputs/bundle/release/app-release.aab upload
echo ""
echo "✓ מוכן: $OUT"
echo "להעלות ב-Google Play Console ← האפליקציה ← Test and release ← Testing ← Closed testing ← Create new release ← Upload"
