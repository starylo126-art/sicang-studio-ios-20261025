#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Studio.xcodeproj -scheme Studio -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p dist/Payload
ditto build/Build/Products/Release-iphoneos/Studio.app dist/Payload/Studio.app
(cd dist && /usr/bin/zip -q -r PrivateWardrobe-unsigned.ipa Payload)
echo "Unsigned IPA: dist/PrivateWardrobe-unsigned.ipa"
