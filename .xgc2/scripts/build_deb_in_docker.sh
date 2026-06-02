#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

UBUNTU_VERSION="${UBUNTU_VERSION:-20.04}"
DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:${UBUNTU_VERSION}}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/.work/docker-${UBUNTU_VERSION}}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/debs}"
INSTALL_CHECK="${INSTALL_CHECK:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ubuntu-version)
      UBUNTU_VERSION="$2"
      DOCKER_IMAGE="ubuntu:${UBUNTU_VERSION}"
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
  20.04)
    APT_REPO_DISTRIBUTION="focal"
    ;;
  24.04)
    APT_REPO_DISTRIBUTION="noble"
    ;;
  *)
    echo "unsupported Ubuntu version: ${UBUNTU_VERSION}" >&2
    exit 1
    ;;
esac

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

docker pull "${DOCKER_IMAGE}"
docker run --rm \
  -e DEBIAN_FRONTEND=noninteractive \
  -e INSTALL_CHECK="${INSTALL_CHECK}" \
  -e APT_REPO_DISTRIBUTION="${APT_REPO_DISTRIBUTION}" \
  -v "${REPO_ROOT}:/workspace/mavlink-router:ro" \
  -v "${WORK_DIR}:/workspace/work" \
  -v "${OUTPUT_DIR}:/workspace/out" \
  "${DOCKER_IMAGE}" \
  bash -lc '
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      dpkg-dev \
      fakeroot \
      file \
      git \
      libgtest-dev \
      libsystemd-dev \
      ninja-build \
      pkg-config \
      python3-pip \
      python3-setuptools \
      rsync \
      systemd

    python3 -m pip install --no-cache-dir --break-system-packages "meson==1.3.2" ||
      python3 -m pip install --no-cache-dir "meson==1.3.2"

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
      --distro "${APT_REPO_DISTRIBUTION}"

    if [[ "${INSTALL_CHECK}" == "true" ]]; then
      apt-get install -y /workspace/out/xgc2-mavlink-router_*.deb
      /workspace/mavlink-router/.xgc2/scripts/check_installed_package.sh
    fi
  '

echo "Debian package output:"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.deb" -print | sort
