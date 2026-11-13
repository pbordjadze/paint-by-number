#!/usr/bin/env bash
# Runs a Swift toolchain command for the package inside the swift:6.2 Docker image.
#   tools/swift.sh build -c release
#   tools/swift.sh test
# Extra mounts: set PBN_MOUNT=/host/dir to expose it at the same path in the container.
# Environment: PBN_ENV="NAME OTHER" passes those variables in (a probe test's inputs).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! docker info >/dev/null 2>&1; then
  (dockerd >/tmp/dockerd.log 2>&1 &)
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
MOUNTS=(-v "$ROOT:$ROOT")
if [[ -n "${PBN_MOUNT:-}" ]]; then MOUNTS+=(-v "$PBN_MOUNT:$PBN_MOUNT"); fi
ENVS=()
for name in ${PBN_ENV:-}; do ENVS+=(-e "$name"); done
exec docker run --rm "${MOUNTS[@]}" "${ENVS[@]}" -w "$ROOT" swift:6.2-noble swift "$@"
