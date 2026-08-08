#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${project_root}/.build/trollstore"
ipa_path="${project_root}/MockLocation.ipa"

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

xcodegen generate --spec "${project_root}/project.yml" --project "${project_root}"

xcodebuild \
  -project "${project_root}/MockLocation.xcodeproj" \
  -scheme MockLocation \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "${build_root}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

app_path="${build_root}/Build/Products/Release-iphoneos/MockLocation.app"
package_root="${build_root}/package"

test -d "${app_path}" || {
  echo "The app bundle was not produced." >&2
  exit 1
}

rm -rf "${package_root}" "${ipa_path}"
mkdir -p "${package_root}/Payload"
cp -R "${app_path}" "${package_root}/Payload/"

(
  cd "${package_root}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${ipa_path}"
)

echo "Created ${ipa_path}"
