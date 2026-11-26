#!/bin/bash
# מוסיף את אפליקציית השעון לפרויקט ה-Xcode, הכול מהטרמינל. אפשר להריץ שוב אחרי כל עדכון של קוד השעון.
# שימוש:  cd ~/Documents/set-app1/ios-app && git pull && bash watch/install-watch.sh
set -e
cd "$(dirname "$0")/.."
[ -d ios/App/App.xcodeproj ] || { echo "לא נמצא ios/App/App.xcodeproj. להריץ קודם: bash build-on-mac.sh"; exit 1; }
D="ios/App/SetWatch Watch App"

echo "== סוגר את Xcode (כדי שלא ידרוס את השינויים) =="
osascript -e 'quit app "Xcode"' 2>/dev/null || true
sleep 2

echo "== כלי לעריכת פרויקט Xcode (פעם ראשונה לוקח כמה דקות) =="
RUBY=""
for r in /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby; do [ -x "$r" ] && RUBY="$r" && break; done
if [ -z "$RUBY" ]; then
  command -v brew >/dev/null || { echo "לא נמצא Homebrew. להתקין מ-https://brew.sh ולהריץ שוב"; exit 1; }
  brew install ruby
  for r in /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby; do [ -x "$r" ] && RUBY="$r" && break; done
fi
"$RUBY" -e 'require "xcodeproj"' 2>/dev/null || "$(dirname "$RUBY")/gem" install xcodeproj --no-document
echo "   ✓ מוכן"

echo "== מעתיק את קבצי השעון =="
mkdir -p "$D/Assets.xcassets/AppIcon.appiconset"
rm -f "$D/ContentView.swift"
cp watch/SetWatch/*.swift watch/SetWatch/Info.plist watch/SetWatch/SetWatch.entitlements "$D/"
echo '{"info":{"author":"xcode","version":1}}' > "$D/Assets.xcassets/Contents.json"
sips -z 1024 1024 assets/icon-only.png --out "$D/Assets.xcassets/AppIcon.appiconset/icon-1024.png" >/dev/null
cat > "$D/Assets.xcassets/AppIcon.appiconset/Contents.json" <<'JSON'
{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"watchos","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
JSON
echo "   ✓ קוד, אייקון, הרשאות Health"

echo "== מוסיף את השעון לפרויקט =="
"$RUBY" watch/add_watch_target.rb

echo
echo "== סיום. פותח את Xcode =="
open ios/App/App.xcodeproj
