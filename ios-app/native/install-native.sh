#!/bin/bash
# מוסיף לאפליקציית האייפון: התראות מ-Apple, שמירת אימונים ב-Health, אימון פעיל במסך הנעילה, וווידג'ט.
# שימוש:  cd ~/Documents/set-app1/ios-app && git pull && bash native/install-native.sh
set -e
cd "$(dirname "$0")/.."
[ -d ios/App/App.xcodeproj ] || { echo "לא נמצא ios/App/App.xcodeproj. להריץ קודם: bash build-on-mac.sh"; exit 1; }
A=ios/App
PBX=$A/App.xcodeproj/project.pbxproj
[ -n "$NO_QUIT" ] || { osascript -e 'quit app "Xcode"' 2>/dev/null || true; sleep 2; }

RUBY=""
for r in /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby /usr/bin/ruby; do [ -x "$r" ] && RUBY="$r" && break; done
if ! "$RUBY" -e 'require "xcodeproj"' 2>/dev/null; then
  if [ "$RUBY" = /usr/bin/ruby ]; then /usr/bin/gem install --user-install --no-document xcodeproj -v 1.27.0; else "$(dirname "$RUBY")/gem" install --no-document xcodeproj; fi
fi

echo "== קבצים =="
mkdir -p "$A/Shared" "$A/SetWidgets"
cp native/App/*.swift "$A/App/"
cp native/Shared/*.swift "$A/Shared/"
cp native/SetWidgets/* "$A/SetWidgets/"
echo "   ✓ הועתקו"

echo "== מחבר את הפלאגין לאפליקציה =="
SB="$A/App/Base.lproj/Main.storyboard"
perl -pi -e 's/customClass="CAPBridgeViewController" customModule="Capacitor"/customClass="SetBridgeViewController" customModule="App" customModuleProvider="target"/' "$SB"
grep -q SetBridgeViewController "$SB" && echo "   ✓ מסך ראשי" || { echo "   ! לא הצלחתי לעדכן את Main.storyboard"; exit 1; }
AD="$A/App/AppDelegate.swift"
if ! grep -q capacitorDidRegisterForRemoteNotifications "$AD"; then
  perl -0pi -e 's/\n\}\s*$/\n\n    \/\/ התראות מ-Apple: מעביר את הטוקן לפלאגין ההתראות\n    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {\n        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)\n    }\n\n    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {\n        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)\n    }\n}\n/' "$AD"
fi
grep -q capacitorDidRegisterForRemoteNotifications "$AD" && echo "   ✓ התראות ב-AppDelegate"

echo "== הרשאות (Entitlements) ו-Info.plist =="
ENT="$A/App/App.entitlements"
[ -f "$ENT" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$ENT"
grep -q "CODE_SIGN_ENTITLEMENTS = App/App.entitlements" "$PBX" || perl -pi -e 's/^(\s*)(INFOPLIST_FILE = App\/Info\.plist;)/$1CODE_SIGN_ENTITLEMENTS = App\/App.entitlements;\n$1$2/' "$PBX"
PB=/usr/libexec/PlistBuddy
$PB -c "Print :aps-environment" "$ENT" >/dev/null 2>&1 || $PB -c "Add :aps-environment string development" "$ENT"
$PB -c "Print :com.apple.security.application-groups" "$ENT" >/dev/null 2>&1 || { $PB -c "Add :com.apple.security.application-groups array" "$ENT"; $PB -c "Add :com.apple.security.application-groups:0 string group.com.setapp.workout" "$ENT"; }
$PB -c "Print :com.apple.developer.healthkit" "$ENT" >/dev/null 2>&1 || $PB -c "Add :com.apple.developer.healthkit bool true" "$ENT"
$PB -c "Print :com.apple.developer.associated-domains" "$ENT" >/dev/null 2>&1 || { $PB -c "Add :com.apple.developer.associated-domains array" "$ENT"; $PB -c "Add :com.apple.developer.associated-domains:0 string webcredentials:set-app-e0r6.onrender.com" "$ENT"; }
PL="$A/App/Info.plist"
$PB -c "Print :NSSupportsLiveActivities" "$PL" >/dev/null 2>&1 || $PB -c "Add :NSSupportsLiveActivities bool true" "$PL"
$PB -c "Set :NSHealthUpdateUsageDescription שמירת אימוני הכוח שלך ומשקל שתרשום ב-Apple Health" "$PL" 2>/dev/null || true
echo "   ✓ התראות, App Group, HealthKit, מסך נעילה, Face ID (Passkeys)"

echo "== מוסיף לפרויקט =="
"$RUBY" native/add_native.rb
echo "== סיום =="
