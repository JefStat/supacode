#!/usr/bin/env bash
# Prints a directory to prepend to PATH so the pinned Zig (0.15.2) can link the macOS SDK.
# Prints nothing when the SDK needs no help.
# macOS 26.4+ SDKs list only arm64e-macos in their .tbd stubs, and Zig 0.15.2 looks
# for arm64-macos (ziglang/zig#31658, fixed in Zig 0.16+). This clones the SDK (APFS
# copy-on-write), adds arm64-macos next to every arm64e-macos, and writes an xcrun
# shim that answers `--sdk macosx --show-sdk-path` with the clone. Zig ignores SDKROOT,
# so the shim is the only hook. The Xcode install is never modified.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
srcroot="${SRCROOT:-$(cd "${script_dir}/.." && pwd)}"

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
sdk="$(DEVELOPER_DIR="${developer_dir}" xcrun --sdk macosx --show-sdk-path)"
sdk="$(cd "${sdk}" && pwd -P)"

# Only the top-level targets list (first lines) matters. Later export blocks may list arm64-macos.
if head -5 "${sdk}/usr/lib/libSystem.tbd" | grep -q 'arm64-macos'; then
  exit 0
fi

patched_root="${srcroot}/.build/zig-sdk"
patched_sdk="${patched_root}/MacOSX.sdk"
shim_dir="${patched_root}/bin"
stamp_path="${patched_root}/stamp"
stamp="$(printf '%s\n' "${sdk}" | cat - "${sdk}/usr/lib/libSystem.tbd" "${sdk}/SDKSettings.json" "${BASH_SOURCE[0]}" | shasum -a 256 | awk '{print $1}')"

if [ -f "${stamp_path}" ] && [ -d "${patched_sdk}" ] && [ -x "${shim_dir}/xcrun" ] && [ "$(cat "${stamp_path}")" = "${stamp}" ]; then
  printf '%s\n' "${shim_dir}"
  exit 0
fi

tmp_root="${srcroot}/.build/zig-sdk.tmp.$$"
trap 'rm -rf "${tmp_root}"' EXIT
mkdir -p "${tmp_root}/bin"
cp -cR "${sdk}" "${tmp_root}/MacOSX.sdk"
find "${tmp_root}/MacOSX.sdk/usr/lib" -type f -name '*.tbd' -exec chmod u+w {} +
find "${tmp_root}/MacOSX.sdk/usr/lib" -type f -name '*.tbd' -exec sed -i '' 's/arm64e-macos\([], ]\)/arm64-macos, arm64e-macos\1/g' {} +
# SDK 27 math.h takes `__need_infinity_nan` from float.h under modules. Zig's clang 20 float.h lacks it.
sed -i '' \
  -e 's/^#   if defined(__has_feature) \&\& __has_feature(modules) \&\& defined(__has_include) \&\& __has_include(<float.h>)$/#   if 0/' \
  -e 's/^#if !defined(__GNUC__) || !defined(__has_feature) || !__has_feature(modules) || !defined(__has_include) || !__has_include(<float.h>)$/#if 1/' \
  "${tmp_root}/MacOSX.sdk/usr/include/math.h"
# ghostty runs xcodebuild with an empty environment, so it needs DEVELOPER_DIR from the shim.
cat > "${tmp_root}/bin/xcodebuild" <<EOF
#!/bin/bash
export DEVELOPER_DIR="${developer_dir}"
exec /usr/bin/xcodebuild "\$@"
EOF
chmod +x "${tmp_root}/bin/xcodebuild"
cat > "${tmp_root}/bin/xcrun" <<EOF
#!/bin/bash
case " \$* " in
  *" --show-sdk-path "*) case " \$* " in *" --sdk macosx "*|*" -sdk macosx "*) echo "${patched_sdk}"; exit 0 ;; esac ;;
esac
exec /usr/bin/xcrun "\$@"
EOF
chmod +x "${tmp_root}/bin/xcrun"
# Xcode 27 libtool drops archive members that are not 8-byte aligned, and Zig 0.15.2 writes them that way.
# Passing the extracted .o files keeps every member.
cat > "${tmp_root}/bin/libtool" <<'EOF'
#!/bin/bash
export DEVELOPER_DIR="__DEVELOPER_DIR__"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
args=()
count=0
previous=""
for arg in "$@"; do
  if [ "${previous}" != "-o" ] && [[ "${arg}" == *.a ]] && [ -f "${arg}" ]; then
    count=$((count + 1))
    mkdir "${tmp}/${count}"
    archive="$(cd "$(dirname "${arg}")" && pwd)/$(basename "${arg}")"
    (cd "${tmp}/${count}" && /usr/bin/ar -x "${archive}" && chmod u+rw ./*.o)
    for object in "${tmp}/${count}"/*.o; do
      args+=("${object}")
    done
  else
    args+=("${arg}")
  fi
  previous="${arg}"
done
/usr/bin/libtool "${args[@]}"
EOF
sed -i '' "s|__DEVELOPER_DIR__|${developer_dir}|" "${tmp_root}/bin/libtool"
chmod +x "${tmp_root}/bin/libtool"
printf '%s\n' "${stamp}" > "${tmp_root}/stamp"

rm -rf "${patched_root}"
mv "${tmp_root}" "${patched_root}"
trap - EXIT
printf '%s\n' "${shim_dir}"
