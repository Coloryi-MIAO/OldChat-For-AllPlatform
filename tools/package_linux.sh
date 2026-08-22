#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
arch="${1:-x64}"
out="${2:-build/packages}"
package_version="1.4.8-beta.5+6"
case "$arch" in
  x64) flutter_arch=x64; deb_arch=amd64; rpm_arch=x86_64 ;;
  *) echo 'Usage: tools/package_linux.sh x64 [output-directory]' >&2; exit 2 ;;
esac
command -v dpkg-deb >/dev/null 2>&1 || { echo 'dpkg-deb is required.' >&2; exit 2; }
command -v rpmbuild >/dev/null 2>&1 || { echo 'rpmbuild is required.' >&2; exit 2; }
if ! command -v appimagetool >/dev/null 2>&1; then
  echo 'appimagetool is required to build the AppImage.' >&2
  exit 2
fi
flutter build linux --release
bundle="build/linux/${flutter_arch}/release/bundle"
[[ -d "$bundle" ]] || { echo "Flutter did not produce $bundle" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/DEBIAN" "$staging/opt/oldchatforallplatform"
cp -a "$bundle/." "$staging/opt/oldchatforallplatform/"
cat > "$staging/DEBIAN/control" <<CONTROL
Package: oldchatforallplatform
Version: 1.4.8~beta.5+6
Section: net
Priority: optional
Architecture: $deb_arch
Maintainer: Coloryi-MIAO
Description: OldChat For AllPlatform cross-platform chat client
CONTROL
dpkg-deb --build "$staging" "$out/OldChatForAllPlatformlinuxx64.deb"
rpmroot="$staging/rpm"
mkdir -p "$rpmroot/BUILD" "$rpmroot/RPMS/$rpm_arch" "$rpmroot/SOURCES" "$rpmroot/SPECS" "$rpmroot/SRPMS"
cp -a "$bundle" "$rpmroot/SOURCES/oldchatforallplatform"
cat > "$rpmroot/SPECS/oldchatforallplatform.spec" <<SPEC
Name: oldchatforallplatform
Version: 1.4.8
Release: 5.beta.6
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
find "$rpmroot/RPMS" -type f -name '*.rpm' -exec cp {} "$out/OldChatForAllPlatformlinuxx64.rpm" \;
appdir="$staging/OldChatForAllPlatform.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications"
cp -a "$bundle/." "$appdir/usr/bin/"
cat > "$appdir/AppRun" <<'APP_RUN'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec "$here/usr/bin/OldChatForAllPlatform" "$@"
APP_RUN
chmod +x "$appdir/AppRun"
cat > "$appdir/oldchatforallplatform.desktop" <<DESKTOP
[Desktop Entry]
Name=OldChat For AllPlatform
Comment=Cross platform chat client
Exec=OldChatForAllPlatform
Icon=oldchatforallplatform
Type=Application
Categories=Network;Chat;
DESKTOP
cp "$appdir/oldchatforallplatform.desktop" "$appdir/usr/share/applications/"
if [[ -f "$root/assets/app_icon.png" ]]; then cp "$root/assets/app_icon.png" "$appdir/oldchatforallplatform.png"; fi
ARCH=x86_64 appimagetool "$appdir" "$out/OldChatForAllPlatformlinuxx64.AppImage"
cp -a "$bundle" "$out/OldChatForAllPlatformlinuxx64bundle"
printf 'Linux packages: %s\n' "$out"
