#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

UBUNTU_VERSION="${UBUNTU_VERSION:-20.04}"
DOCKER_IMAGE="${DOCKER_IMAGE:-}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/.work/docker-${UBUNTU_VERSION}}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/debs}"
INSTALL_CHECK="${INSTALL_CHECK:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ubuntu-version)
      UBUNTU_VERSION="$2"
      shift 2
      ;;
    --image)
      DOCKER_IMAGE="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-install-check)
      INSTALL_CHECK=false
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "${UBUNTU_VERSION}" in
  20.04) PACKAGE_DISTRIBUTION="focal" ;;
  22.04) PACKAGE_DISTRIBUTION="jammy" ;;
  24.04) PACKAGE_DISTRIBUTION="noble" ;;
  *)
    echo "unsupported Ubuntu version: ${UBUNTU_VERSION}" >&2
    exit 1
    ;;
esac
if [[ -z "${DOCKER_IMAGE}" ]]; then
  DOCKER_IMAGE="ghcr.io/xgc-team/xgc2-images/xgc2-build-${PACKAGE_DISTRIBUTION}-dev:1.0.0"
fi

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

docker pull "${DOCKER_IMAGE}"
docker run --rm --network none \
  -e DEBIAN_FRONTEND=noninteractive \
  -e INSTALL_CHECK="${INSTALL_CHECK}" \
  -e PACKAGE_DISTRIBUTION="${PACKAGE_DISTRIBUTION}" \
  -v "${REPO_ROOT}:/workspace/mavlink-router:ro" \
  -v "${WORK_DIR}:/workspace/work" \
  -v "${OUTPUT_DIR}:/workspace/out" \
  "${DOCKER_IMAGE}" \
  bash -lc '
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    for pkg in \
      build-essential ca-certificates dpkg-dev fakeroot file git \
      libgtest-dev libsystemd-dev ninja-build pkg-config rsync
    do
      if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
        echo "image is missing ${pkg}; use xgc2-build-*-dev" >&2
        exit 1
      fi
    done
    meson --version

    rm -rf /workspace/work/src /workspace/work/build /workspace/work/install-root
    mkdir -p /workspace/work/src
    rsync -a --delete /workspace/mavlink-router/ /workspace/work/src/

    cd /workspace/work/src
    meson setup \
      --buildtype=release \
      --prefix=/usr \
      -Dsystemdsystemunitdir=/lib/systemd/system \
      /workspace/work/build \
      .
    meson compile -C /workspace/work/build
    meson test -C /workspace/work/build --print-errorlogs

    DESTDIR=/workspace/work/install-root meson install -C /workspace/work/build

    /workspace/mavlink-router/.xgc2/scripts/package_deb.sh \
      --install-root /workspace/work/install-root \
      --output-dir /workspace/out \
      --distro "${PACKAGE_DISTRIBUTION}"

    if [[ "${INSTALL_CHECK}" == "true" ]]; then
      dpkg -i /workspace/out/xgc2-mavlink-router_*.deb
      /workspace/mavlink-router/.xgc2/scripts/check_installed_package.sh
    fi
  '

echo "Debian package output:"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.deb" -print | sort
