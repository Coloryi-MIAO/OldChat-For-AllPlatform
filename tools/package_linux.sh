#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
arch="${1:-x64}"
out="${2:-build/packages}"
case "$arch" in
  x64) flutter_arch=x64; deb_arch=amd64; rpm_arch=x86_64 ;;
  arm64) flutter_arch=arm64; deb_arch=arm64; rpm_arch=aarch64 ;;
  *) echo 'Usage: tools/package_linux.sh x64|arm64 [output-directory]' >&2; exit 2 ;;
esac
flutter build linux --release --target-platform "linux-$flutter_arch"
bundle="build/linux/$flutter_arch/release/bundle"
[[ -d "$bundle" ]] || { echo "Flutter did not produce $bundle" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/DEBIAN" "$staging/opt/oldchatforallplatform"
cp -a "$bundle/." "$staging/opt/oldchatforallplatform/"
cat > "$staging/DEBIAN/control" <<CONTROL
Package: oldchatforallplatform
Version: 1.4.7
Section: net
Priority: optional
Architecture: $deb_arch
Maintainer: Coloryi-MIAO
Description: OldChat For AllPlatform cross-platform chat client
CONTROL
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build "$staging" "$out/OldChatForAllPlatformlinux$arch.deb"
fi
if command -v rpmbuild >/dev/null 2>&1; then
  rpmroot="$staging/rpm"
  mkdir -p "$rpmroot/BUILD" "$rpmroot/RPMS/$rpm_arch" "$rpmroot/SOURCES" "$rpmroot/SPECS" "$rpmroot/SRPMS"
  cp -a "$bundle" "$rpmroot/SOURCES/oldchatforallplatform"
  cat > "$rpmroot/SPECS/oldchatforallplatform.spec" <<SPEC
Name: oldchatforallplatform
Version: 1.4.7
Release: 1
Summary: OldChat For AllPlatform cross-platform chat client
License: Proprietary
Packager: Coloryi-MIAO
BuildArch: $rpm_arch

%description
OldChat For AllPlatform cross-platform chat client.

%prep

%build

%install
mkdir -p %{buildroot}/opt/oldchatforallplatform
cp -a %{_sourcedir}/oldchatforallplatform/. %{buildroot}/opt/oldchatforallplatform/

%files
/opt/oldchatforallplatform
SPEC
  rpmbuild --define "_topdir $rpmroot" --target "$rpm_arch" --define "_build_id_links none" -bb "$rpmroot/SPECS/oldchatforallplatform.spec"
  find "$rpmroot/RPMS" -type f -name '*.rpm' -exec cp {} "$out/OldChatForAllPlatformlinux$arch.rpm" \;
else
  echo 'RPM not produced: rpmbuild is not installed.' >&2
fi
cp -a "$bundle" "$out/OldChatForAllPlatformlinux${arch}bundle"
printf 'Linux packages: %s\n' "$out"
