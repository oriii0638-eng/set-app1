#!/bin/bash
# בונה ומעלה גרסה חדשה ל-App Store Connect, כולל הרשאות Apple Health.
# שימוש:  cd ~/Documents/set-app1/ios-app && git pull && bash upload-build.sh 2
set -e
cd "$(dirname "$0")"
BUILD="${1:-2}"
ARCH="$HOME/Desktop/Set-build-$BUILD.xcarchive"
OUT="$HOME/Desktop/Set-export-$BUILD"

echo "== סנכרון האתר לאפליקציה =="
npx cap sync ios

echo "== טקסטים של הרשאות ב-Info.plist =="
PL=ios/App/App/Info.plist
add_key() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PL" >/dev/null 2>&1 \
    && /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PL" \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PL"
}
add_key NSHealthShareUsageDescription "קריאת צעדים, משקל ונתוני אימון כדי להציג את ההתקדמות שלך ולתחרות הצעדים"
add_key NSHealthUpdateUsageDescription "רישום משקל ואימונים שתשמור באפליקציה"
add_key NSFaceIDUsageDescription "כניסה מהירה לחשבון"
echo "   ✓ הרשאות נוספו"

cd ios/App
echo "== הגדרות חתימה =="
SETTINGS=$(xcodebuild -project App.xcodeproj -scheme App -configuration Release -showBuildSettings 2>/dev/null || true)
TEAM=$(echo "$SETTINGS" | awk -F' = ' '/ DEVELOPMENT_TEAM =/{print $2; exit}')
ENT=$(echo "$SETTINGS" | awk -F' = ' '/ CODE_SIGN_ENTITLEMENTS =/{print $2; exit}')
[ -n "$TEAM" ] || { echo "לא נמצא Team. ב-Xcode: Signing & Capabilities ← Team, ואז להריץ שוב"; exit 1; }
[ -n "$ENT" ] || ENT="App/App.entitlements"
if [ ! -f "$ENT" ]; then
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$ENT"
fi
/usr/libexec/PlistBuddy -c "Print :com.apple.developer.healthkit" "$ENT" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :com.apple.developer.healthkit bool true" "$ENT"
/usr/libexec/PlistBuddy -c "Print :com.apple.developer.healthkit.access" "$ENT" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :com.apple.developer.healthkit.access array" "$ENT"
echo "   ✓ Team: $TEAM | HealthKit נוסף ל-$ENT"

echo "== בנייה (Archive), Build $BUILD. לוקח כמה דקות =="
rm -rf "$ARCH" "$OUT"
xcodebuild -project App.xcodeproj -scheme App -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_ENTITLEMENTS="$ENT" DEVELOPMENT_TEAM="$TEAM" \
  archive | grep -E "error:|warning: .*entitle|ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$ARCH" ] || { echo "הבנייה נכשלה. לשלוח צילום של השגיאה"; exit 1; }

echo "== העלאה ל-App Store Connect =="
EXP=$(mktemp -t exportopts).plist
cat > "$EXP" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict></plist>
PL
xcodebuild -exportArchive -archivePath "$ARCH" -exportOptionsPlist "$EXP" -exportPath "$OUT" -allowProvisioningUpdates \
  | grep -E "error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)|Progress 100" || true

echo
echo "== סיום =="
echo "אם מופיע EXPORT SUCCEEDED: Build $BUILD עלה. בעוד 10-30 דקות הוא יופיע ב-App Store Connect ← TestFlight."
