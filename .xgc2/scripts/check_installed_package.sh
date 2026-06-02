#!/usr/bin/env bash
set -euo pipefail

dpkg -s xgc2-mavlink-router >/dev/null
command -v mavlink-routerd >/dev/null
mavlink-routerd --version
test -f /lib/systemd/system/mavlink-router.service
