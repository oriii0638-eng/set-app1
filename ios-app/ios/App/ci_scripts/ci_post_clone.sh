#!/bin/sh
# Xcode Cloud: רץ אחרי שהקוד ירד מ-GitHub ולפני הבנייה.
# מתקין Node, מתקין את חבילות Capacitor ומעתיק את הקוד הנייטיב העדכני (אפליקציה, ווידג'טים ושעון) לפרויקט.
set -e
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
command -v node >/dev/null 2>&1 || brew install node
cd "$CI_PRIMARY_REPOSITORY_PATH/ios-app"
npm ci --no-audit --no-fund
npx cap sync ios

A=ios/App
cp native/App/*.swift "$A/App/"
cp native/Shared/*.swift "$A/Shared/"
cp native/SetWidgets/*.swift "$A/SetWidgets/"
cp watch/SetWatch/*.swift "$A/SetWatch Watch App/"
echo "post-clone ok: node $(node -v), build ${CI_BUILD_NUMBER:-?}"
