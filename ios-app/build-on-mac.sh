#!/bin/bash
# סקריפט חד-פעמי למאק: בונה את פרויקט ה-iOS ופותח את Xcode.
# שימוש:  cd set-app1/ios-app && bash build-on-mac.sh
set -e
cd "$(dirname "$0")"

echo "== בדיקות מקדימות =="
[ "$(uname)" = "Darwin" ] || { echo "הסקריפט הזה רץ רק על מק"; exit 1; }
command -v node >/dev/null || { echo "חסר Node. להתקין: brew install node"; exit 1; }
command -v xcodebuild >/dev/null || { echo "חסר Xcode. להתקין מה-App Store ולהריץ אותו פעם אחת"; exit 1; }
xcode-select -p >/dev/null 2>&1 || xcode-select --install || true

echo "== התקנת חבילות (כולל תשלומי Apple) =="
npm install

if [ ! -d ios ]; then
  echo "== יצירת פרויקט iOS =="
  npx cap add ios
else
  echo "== תיקיית ios כבר קיימת, מדלג על היצירה =="
fi

echo "== אייקון ומסך פתיחה =="
npm run assets || echo "(לא הצליח ליצור נכסים, אפשר להמשיך ולהוסיף ידנית ב-Xcode)"

echo "== סנכרון =="
npx cap sync ios

cat <<'MSG'

== מוכן. עכשיו ב-Xcode (ייפתח עוד רגע) ==
1. לחץ על הפרויקט App בצד שמאל, ואז Targets > App.
2. Signing & Capabilities:
   - Team: בחר את חשבון המפתח שלך.
   - Bundle Identifier: com.setapp.workout
   - לחץ "+ Capability" והוסף "In-App Purchase".
3. הרץ על סימולטור (Play) ואחר כך על אייפון אמיתי.
4. לבדיקת תשלום: ב-App Store Connect צור Sandbox Tester, והתחבר איתו
   בהגדרות האייפון > App Store > Sandbox Account. לא מחייב כסף.
MSG

npx cap open ios
