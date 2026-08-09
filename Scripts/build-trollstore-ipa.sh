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
  done < <(grep -Ei 'error:|fatal error:' "${log_path}" || true)

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

run_and_capture xcodegen xcodegen generate --spec "${project_root}/project.yml" --project "${project_root}" || exit $?

xcodebuild_args=(
  -project "${project_root}/MockLocation.xcodeproj"
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

rm -rf "${package_root}" "${ipa_path}"
mkdir -p "${package_root}/Payload"
cp -R "${app_path}" "${package_root}/Payload/"

(
  cd "${package_root}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${ipa_path}"
)

echo "Created ${ipa_path}"
