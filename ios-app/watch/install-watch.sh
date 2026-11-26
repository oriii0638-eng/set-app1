#!/bin/bash
# מעתיק את קוד אפליקציית השעון לתוך פרויקט ה-Xcode, אחרי שה-Target נוצר ב-Xcode (ראו WATCH_README.md).
# שימוש:  cd ~/Documents/set-app1/ios-app && git pull && bash watch/install-watch.sh
set -e
cd "$(dirname "$0")/.."
D="ios/App/SetWatch Watch App"
PBX="ios/App/App.xcodeproj/project.pbxproj"
[ -d "$D" ] || { echo "לא נמצאה התיקייה \"$D\". קודם ליצור ב-Xcode Target בשם SetWatch (שלב 2 בהוראות)."; exit 1; }

echo "== מעתיק את קבצי השעון =="
cp watch/SetWatch/*.swift "$D/"
rm -f "$D/ContentView.swift"
echo "   ✓ $(ls watch/SetWatch/*.swift | wc -l | tr -d ' ') קבצים"

echo "== אייקון לשעון =="
IC="$D/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$IC"
sips -z 1024 1024 assets/icon-only.png --out "$IC/icon-1024.png" >/dev/null
cat > "$IC/Contents.json" <<'JSON'
{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"watchos","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
JSON
echo "   ✓ אייקון"

echo "== הרשאות Health וגרסת watchOS =="
SH="קריאת דופק וקלוריות בזמן האימון כדי להציג אותם על השעון"
UP="שמירת אימון הכוח שביצעת בשעון ב-Apple Health"
grep -q "INFOPLIST_KEY_NSHealthShareUsageDescription" "$PBX" || \
  perl -0pi -e 's/(\n(\s*)INFOPLIST_KEY_WKCompanionAppBundleIdentifier = [^;]+;)/$1\n$2INFOPLIST_KEY_NSHealthShareUsageDescription = "'"$SH"'";\n$2INFOPLIST_KEY_NSHealthUpdateUsageDescription = "'"$UP"'";/g' "$PBX"
perl -pi -e 's/INFOPLIST_KEY_CFBundleDisplayName = [^;]+;/INFOPLIST_KEY_CFBundleDisplayName = "סט";/g' "$PBX"
perl -pi -e 's/WATCHOS_DEPLOYMENT_TARGET = [0-9.]+;/WATCHOS_DEPLOYMENT_TARGET = 10.0;/g' "$PBX"
grep -q "INFOPLIST_KEY_NSHealthShareUsageDescription" "$PBX" && echo "   ✓ הרשאות Health" || echo "   ! לא נמצא Target של שעון בפרויקט. לבדוק שלב 2"

if ! grep -q "PBXFileSystemSynchronizedRootGroup" "$PBX"; then
  echo
  echo "שים לב: הפרויקט בפורמט ישן, אז Xcode לא יוסיף את הקבצים לבד."
  echo "ב-Xcode: גרור את הקבצים מהתיקייה \"$D\" (Api, AppState, Views, WorkoutManager) לקבוצה SetWatch Watch App, וסמן את ה-Target של השעון."
fi
echo
echo "== סיום. ב-Xcode: בחר את הסכמה \"SetWatch Watch App\" ושעון, ולחץ ▶ כדי לבדוק =="
