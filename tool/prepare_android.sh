#!/usr/bin/env bash
# Generates the Android project files (if missing) and adds the GPS
# permissions SectionDraw needs. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --platforms=android --org in.dsc --project-name sectiondraw .
fi

# flutter create adds a counter-app widget test that does not apply here.
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "ACCESS_FINE_LOCATION" "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <application#' "$MANIFEST"
fi
sed -i 's/android:label="sectiondraw"/android:label="SectionDraw"/' "$MANIFEST"

echo "---- AndroidManifest permissions/label ----"
grep -n -E "uses-permission|android:label" "$MANIFEST"
