#!/usr/bin/env sh
# Verify daemon.json merge behavior without touching system Docker settings.

set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
PYTHON_COMMAND=${PYTHON_COMMAND:-python3}

cleanup() {
    rm -rf "${TEST_DIR}"
}

trap cleanup EXIT HUP INT TERM

if ! command -v "${PYTHON_COMMAND}" >/dev/null 2>&1; then
    printf '%s\n' "Python command not found: ${PYTHON_COMMAND}" >&2
    exit 1
fi
export PYTHON_COMMAND

mkdir -p "${TEST_DIR}/bin"

tee "${TEST_DIR}/bin/docker" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

tee "${TEST_DIR}/bin/service" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

tee "${TEST_DIR}/bin/python3" > /dev/null <<'EOF'
#!/usr/bin/env sh
exec "${PYTHON_COMMAND}" "$@"
EOF

chmod 755 "${TEST_DIR}/bin/docker" "${TEST_DIR}/bin/service" "${TEST_DIR}/bin/python3"
PATH="${TEST_DIR}/bin:${PATH}"
export PATH

(
    DOCKER_REGION=cn
    DOCKER_DAEMON_JSON="${TEST_DIR}/daemon.json"
    DOCKER_CONFIG_BACKUP="${TEST_DIR}/daemon.json.bak"
    . "${ROOT_DIR}/lib/docker_daemon.sh"
    configure_docker_daemon
)

"${PYTHON_COMMAND}" - "${TEST_DIR}/daemon.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)

assert config["log-driver"] == "json-file"
assert config["registry-mirrors"] == [
    "https://docker.1ms.run",
    "https://dockerproxy.net",
    "https://proxy.vvvv.ee",
    "https://dockerproxy.link",
]
PY

printf '%s' '{"debug":true,"log-opts":{"extra":"keep"},"registry-mirrors":["https://existing.example.com"]}' > "${TEST_DIR}/daemon.json"

(
    unset DOCKER_REGISTRY_MIRROR
    DOCKER_REGION=global
    DOCKER_DAEMON_JSON="${TEST_DIR}/daemon.json"
    DOCKER_CONFIG_BACKUP="${TEST_DIR}/daemon.json.bak"
    . "${ROOT_DIR}/lib/docker_daemon.sh"
    configure_docker_daemon
)

"${PYTHON_COMMAND}" - "${TEST_DIR}/daemon.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)

assert config["debug"] is True
assert config["log-opts"]["extra"] == "keep"
assert config["registry-mirrors"] == ["https://existing.example.com"]
PY

(
    DOCKER_REGION=cn
    DOCKER_REGISTRY_MIRROR=none
    DOCKER_DAEMON_JSON="${TEST_DIR}/daemon.json"
    DOCKER_CONFIG_BACKUP="${TEST_DIR}/daemon.json.bak"
    . "${ROOT_DIR}/lib/docker_daemon.sh"
    configure_docker_daemon
)

"${PYTHON_COMMAND}" - "${TEST_DIR}/daemon.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)

assert "registry-mirrors" not in config
PY

printf '%s' '{invalid json' > "${TEST_DIR}/invalid.json"
if (
    DOCKER_REGION=cn
    DOCKER_DAEMON_JSON="${TEST_DIR}/invalid.json"
    DOCKER_CONFIG_BACKUP="${TEST_DIR}/invalid.json.bak"
    . "${ROOT_DIR}/lib/docker_daemon.sh"
    configure_docker_daemon
); then
    printf '%s\n' 'Invalid daemon.json unexpectedly accepted' >&2
    exit 1
fi

[ "$(cat "${TEST_DIR}/invalid.json")" = '{invalid json' ]
[ ! -e "${TEST_DIR}/invalid.json.bak" ]

printf '%s\n' 'Docker daemon configuration tests passed'
