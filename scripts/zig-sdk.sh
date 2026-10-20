#!/usr/bin/env bash
# Prints an SDK path the pinned Zig (0.15.2) can link, for use as SDKROOT.
# macOS 26.4+ SDKs list only arm64e-macos in their .tbd stubs, and Zig 0.15.2 looks
# for arm64-macos (ziglang/zig#31658, fixed in Zig 0.16+). When the SDK has no
# arm64-macos, this clones it (APFS copy-on-write) and adds arm64-macos next to
# every arm64e-macos. The Xcode install is never modified.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
srcroot="${SRCROOT:-$(cd "${script_dir}/.." && pwd)}"

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
sdk="$(DEVELOPER_DIR="${developer_dir}" xcrun --sdk macosx --show-sdk-path)"
sdk="$(cd "${sdk}" && pwd -P)"

if grep -q 'arm64-macos' "${sdk}/usr/lib/libSystem.tbd"; then
  printf '%s\n' "${sdk}"
  exit 0
fi

patched_root="${srcroot}/.build/zig-sdk"
patched_sdk="${patched_root}/MacOSX.sdk"
stamp_path="${patched_root}/stamp"
stamp="$(printf '%s\n' "${sdk}" | cat - "${sdk}/usr/lib/libSystem.tbd" "${sdk}/SDKSettings.json" | shasum -a 256 | awk '{print $1}')"

if [ -f "${stamp_path}" ] && [ -d "${patched_sdk}" ] && [ "$(cat "${stamp_path}")" = "${stamp}" ]; then
  printf '%s\n' "${patched_sdk}"
  exit 0
fi

tmp_root="${srcroot}/.build/zig-sdk.tmp.$$"
trap 'rm -rf "${tmp_root}"' EXIT
mkdir -p "${tmp_root}"
cp -cR "${sdk}" "${tmp_root}/MacOSX.sdk"
find "${tmp_root}/MacOSX.sdk/usr/lib" -type f -name '*.tbd' -exec chmod u+w {} +
find "${tmp_root}/MacOSX.sdk/usr/lib" -type f -name '*.tbd' -exec sed -i '' 's/arm64e-macos\([], ]\)/arm64-macos, arm64e-macos\1/g' {} +
printf '%s\n' "${stamp}" > "${tmp_root}/stamp"

rm -rf "${patched_root}"
mv "${tmp_root}" "${patched_root}"
trap - EXIT
printf '%s\n' "${patched_sdk}"
