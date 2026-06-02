#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT=""
OUTPUT_DIR=""
VERSION="${PACKAGE_VERSION:-3.0.0-1}"
DISTRO="${PACKAGE_DISTRO:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --distro)
      DISTRO="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${INSTALL_ROOT}" || -z "${OUTPUT_DIR}" ]]; then
  echo "--install-root and --output-dir are required" >&2
  exit 1
fi

if [[ -n "${DISTRO}" && "${VERSION}" != *"+${DISTRO}" ]]; then
  VERSION="${VERSION}+${DISTRO}"
fi

ARCH="$(dpkg --print-architecture)"
PACKAGE="xgc2-mavlink-router"
BUILD_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}/${PACKAGE}_"*.deb

pkg_root="${BUILD_DIR}/${PACKAGE}"
mkdir -p "${pkg_root}/DEBIAN" "${pkg_root}/usr/share/doc/${PACKAGE}"

for path in \
  /usr/bin/mavlink-routerd \
  /lib/systemd/system/mavlink-router.service \
  /usr/lib/systemd/system/mavlink-router.service; do
  if [[ -e "${INSTALL_ROOT}${path}" ]]; then
    mkdir -p "${pkg_root}$(dirname "${path}")"
    cp -a "${INSTALL_ROOT}${path}" "${pkg_root}${path}"
  fi
done

if [[ ! -x "${pkg_root}/usr/bin/mavlink-routerd" ]]; then
  echo "missing installed /usr/bin/mavlink-routerd" >&2
  exit 1
fi

if [[ ! -f "${pkg_root}/lib/systemd/system/mavlink-router.service" &&
      ! -f "${pkg_root}/usr/lib/systemd/system/mavlink-router.service" ]]; then
  echo "missing installed mavlink-router.service" >&2
  exit 1
fi

find "${pkg_root}" -type d -exec chmod 0755 {} +
find "${pkg_root}" -type f -exec chmod 0644 {} +
chmod 0755 "${pkg_root}/usr/bin/mavlink-routerd"

cat > "${pkg_root}/DEBIAN/control" <<EOF
Package: ${PACKAGE}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: XGC2 <apt@example.com>
Depends: libc6, libgcc-s1, libstdc++6, systemd
Provides: mavlink-router
Conflicts: mavlink-router
Description: XGC2 MAVLink router daemon
 Native Debian package for the XGC2 fork of mavlink-router.
 It installs mavlink-routerd into /usr/bin and a systemd service unit.
EOF

cat > "${pkg_root}/usr/share/doc/${PACKAGE}/README" <<EOF
XGC2 MAVLink Router

Installed command:
  mavlink-routerd

Systemd unit:
  mavlink-router.service
EOF

if [[ -n "${DISTRO}" ]]; then
  printf 'Built for Ubuntu distribution: %s\n' "${DISTRO}" > "${pkg_root}/usr/share/doc/${PACKAGE}/distribution"
fi

find "${pkg_root}/DEBIAN" "${pkg_root}/usr/share/doc/${PACKAGE}" -type f -exec chmod 0644 {} +
chmod 0755 "${pkg_root}/DEBIAN"
fakeroot dpkg-deb --build "${pkg_root}" "${OUTPUT_DIR}/${PACKAGE}_${VERSION}_${ARCH}.deb" >/dev/null
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "${PACKAGE}_*.deb" -print | sort
