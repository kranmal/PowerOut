#!/bin/bash
# Builds PowerOut.app and packages it as dist/PowerOut.dmg and dist/PowerOut.zip
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

rm -rf dist && mkdir -p dist/dmg
cp -R build/PowerOut.app dist/dmg/
ln -s /Applications dist/dmg/Applications

hdiutil create -quiet -volname "PowerOut" -srcfolder dist/dmg -ov -format UDZO dist/PowerOut.dmg
ditto -c -k --keepParent build/PowerOut.app dist/PowerOut.zip
rm -rf dist/dmg

echo "Created:"
ls -lh dist/PowerOut.dmg dist/PowerOut.zip
