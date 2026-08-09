#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${project_root}/.build/trollstore"
ipa_path="${project_root}/MockLocation.ipa"

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

mkdir -p "${build_root}"

emit_build_diagnostics() {
  local log_path="$1"
  local diagnostic
  local emitted=0

  while IFS= read -r diagnostic; do
    diagnostic="${diagnostic//'%'/'%25'}"
    diagnostic="${diagnostic//$'\r'/'%0D'}"
    printf '::error title=Build diagnostic::%s\n' "${diagnostic}"
    emitted=$((emitted + 1))
    if [[ "${emitted}" -ge 30 ]]; then
      break
    fi
  done < <(grep -Ei 'error:|fatal error:|reason:|unable to read|does not exist|malformed|invalid' "${log_path}" || true)

  if [[ "${emitted}" -eq 0 ]]; then
    printf '%s\n' '::error title=Build failed::No compiler error line was found; inspect the final xcodebuild output.'
  fi
}

run_and_capture() {
  local name="$1"
  local log_path="${build_root}/${name}.log"
  local command_status
  shift

  set +e
  "$@" 2>&1 | tee "${log_path}"
  command_status=${PIPESTATUS[0]}
  set -e

  if [[ "${command_status}" -ne 0 ]]; then
    echo "::group::${name} diagnostics"
    emit_build_diagnostics "${log_path}"
    tail -n 120 "${log_path}"
    echo '::endgroup::'
    return "${command_status}"
  fi
}

(
  cd "${project_root}"
  run_and_capture xcodegen xcodegen generate --spec project.yml
) || exit $?

project_path=""
while IFS= read -r candidate; do
  project_path="${candidate%/project.pbxproj}"
  break
done < <(find "${project_root}" -type f -name project.pbxproj -print)

if [[ -z "${project_path}" ]]; then
  echo "::error title=XcodeGen output::No project.pbxproj was generated under ${project_root}." >&2
  find "${project_root}" -type d -name '*.xcodeproj' -print >&2 || true
  exit 1
fi
echo "::notice title=XcodeGen output::Using generated project ${project_path}"

xcodebuild_args=(
  -project "${project_path}"
  -scheme MockLocation
  -configuration Release
  -sdk iphoneos
  -derivedDataPath "${build_root}"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
  build
)
run_and_capture xcodebuild xcodebuild "${xcodebuild_args[@]}" || exit $?

app_path="${build_root}/Build/Products/Release-iphoneos/MockLocation.app"
package_root="${build_root}/package"

test -d "${app_path}" || {
  echo "The app bundle was not produced." >&2
  exit 1
}

bundle_executable() {
  local bundle_path="$1"
  local bundle_name="$2"
  local info_path="${bundle_path}/Info.plist"
  local executable

  if [[ ! -f "${info_path}" ]]; then
    echo "The ${bundle_name} bundle has no Info.plist." >&2
    return 1
  fi

  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${info_path}" 2>/dev/null || true)"
  if [[ -z "${executable}" ]]; then
    echo "The ${bundle_name} bundle has no CFBundleExecutable value." >&2
    return 1
  fi
  if [[ ! -f "${bundle_path}/${executable}" || ! -x "${bundle_path}/${executable}" ]]; then
    echo "The ${bundle_name} executable is missing or not executable: ${bundle_path}/${executable}" >&2
    return 1
  fi

  printf '%s\n' "${executable}"
}

main_executable="$(bundle_executable "${app_path}" "main app")"
extension_path="${app_path}/PlugIns/MockLocationShare.appex"
extension_executable="$(bundle_executable "${extension_path}" "share extension")"

rm -rf "${package_root}" "${ipa_path}"
mkdir -p "${package_root}/Payload"
cp -R "${app_path}" "${package_root}/Payload/"

(
  cd "${package_root}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${ipa_path}"
)

assert_ipa_entry() {
  local entry="$1"

  if ! unzip -Z1 "${ipa_path}" | grep -Fx "${entry}" >/dev/null; then
    echo "The IPA is missing ${entry}." >&2
    exit 1
  fi
}

assert_ipa_entry "Payload/MockLocation.app/${main_executable}"
assert_ipa_entry "Payload/MockLocation.app/PlugIns/MockLocationShare.appex/${extension_executable}"

echo "Created ${ipa_path}"
