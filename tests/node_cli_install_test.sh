#!/usr/bin/env sh
# Verify the Node.js Agent CLI installers with a mocked mise command.

set -eu

ROOT_DIR=$(cd "$(dirname "${0}")/.." && pwd)
TEST_DIR=$(mktemp -d)
SYSTEM_PATH="${PATH}"

cleanup() {
    rm -rf "${TEST_DIR}"
}

trap cleanup EXIT HUP INT TERM

mkdir -p "${TEST_DIR}/bin"
TEST_COMMAND_LOG="${TEST_DIR}/commands.log"
export TEST_COMMAND_LOG

cat >"${TEST_DIR}/bin/mise" <<'EOF'
#!/usr/bin/env sh

if [ "${1:-}" != exec ] || [ "${2:-}" != -- ]; then
    exit 2
fi
shift 2

case "${1:-}" in
    sh)
        if [ "${MOCK_EXISTING:-false}" = true ]; then
            exit 0
        fi
        exit 1
        ;;
    npm)
        printf '%s\n' "${*}" >>"${TEST_COMMAND_LOG}"
        if [ "${MOCK_NPM_FAIL:-false}" = true ]; then
            exit 1
        fi
        exit 0
        ;;
    codex)
        printf '%s\n' "${*}" >>"${TEST_COMMAND_LOG}"
        if [ "${2:-}" = login ]; then
            cat >/dev/null
            exit 0
        fi
        if [ "${MOCK_VERIFY:-true}" = true ]; then
            printf '%s version 1.0.0\n' "${1}"
            exit 0
        fi
        exit 1
        ;;
    claude)
        if [ "${MOCK_VERIFY:-true}" = true ]; then
            printf '%s version 1.0.0\n' "${1}"
            exit 0
        fi
        exit 1
        ;;
    *)
        exit 2
        ;;
esac
EOF
chmod 755 "${TEST_DIR}/bin/mise"

PATH="${TEST_DIR}/bin:${SYSTEM_PATH}"
export PATH

: >"${TEST_COMMAND_LOG}"
MOCK_EXISTING=false MOCK_VERIFY=true sh "${ROOT_DIR}/scripts/install/codex.sh"
grep -F -- \
    'npm install --global --registry https://registry.npmmirror.com @openai/codex' \
    "${TEST_COMMAND_LOG}"

: >"${TEST_COMMAND_LOG}"
MOCK_EXISTING=false MOCK_VERIFY=true sh "${ROOT_DIR}/scripts/install/claude_code.sh"
grep -F -- \
    'npm install --global --registry https://registry.npmmirror.com @anthropic-ai/claude-code' \
    "${TEST_COMMAND_LOG}"

: >"${TEST_COMMAND_LOG}"
NPM_REGISTRY=https://npm.example.test/ \
    MOCK_EXISTING=false MOCK_VERIFY=true \
    sh "${ROOT_DIR}/scripts/install/codex.sh"
grep -F -- \
    'npm install --global --registry https://npm.example.test @openai/codex' \
    "${TEST_COMMAND_LOG}"

CODEX_HOME="${TEST_DIR}/codex-home"
mkdir -p "${CODEX_HOME}/.codex"
printf '%s\n' '[model_providers.custom]' 'name = "custom"' \
    >"${CODEX_HOME}/.codex/config.toml"
: >"${TEST_COMMAND_LOG}"
HOME="${CODEX_HOME}" \
    CODEX_BASE_URL=https://codex.example.test/v1 \
    CODEX_TOKEN=codex-test-token \
    MOCK_EXISTING=true MOCK_VERIFY=true \
    sh "${ROOT_DIR}/scripts/install/codex.sh"
grep -F -- 'codex login --with-api-key' "${TEST_COMMAND_LOG}"
grep -F -- 'openai_base_url = "https://codex.example.test/v1"' \
    "${CODEX_HOME}/.codex/config.toml"
head -n 1 "${CODEX_HOME}/.codex/config.toml" | \
    grep -Fx -- 'openai_base_url = "https://codex.example.test/v1"'
grep -F -- '[model_providers.custom]' "${CODEX_HOME}/.codex/config.toml"
if grep -F -- 'codex-test-token' "${CODEX_HOME}/.codex/config.toml" >/dev/null 2>&1; then
    printf '%s\n' 'Codex API token was written to config.toml' >&2
    exit 1
fi

CLAUDE_HOME="${TEST_DIR}/claude-home"
mkdir -p "${CLAUDE_HOME}"
HOME="${CLAUDE_HOME}" \
    CLAUDE_BASE_URL=https://claude.example.test \
    CLAUDE_TOKEN=claude-test-token \
    MOCK_EXISTING=true MOCK_VERIFY=true \
    sh "${ROOT_DIR}/scripts/install/claude_code.sh"
grep -F -- "export ANTHROPIC_BASE_URL='https://claude.example.test'" \
    "${CLAUDE_HOME}/.config/vpsready/claude_code.env"
grep -F -- "export ANTHROPIC_AUTH_TOKEN='claude-test-token'" \
    "${CLAUDE_HOME}/.config/vpsready/claude_code.env"
[ "$(stat -c '%a' "${CLAUDE_HOME}/.config/vpsready/claude_code.env")" = 600 ]
grep -F -- '. "${HOME}/.config/vpsready/claude_code.env"' \
    "${CLAUDE_HOME}/.profile"
grep -F -- '. "${HOME}/.config/vpsready/claude_code.env"' \
    "${CLAUDE_HOME}/.bashrc"

QUOTED_CLAUDE_HOME="${TEST_DIR}/quoted-claude-home"
mkdir -p "${QUOTED_CLAUDE_HOME}"
HOME="${QUOTED_CLAUDE_HOME}" \
    CLAUDE_BASE_URL=https://claude.example.test \
    CLAUDE_TOKEN="claude-token'quoted" \
    MOCK_EXISTING=true MOCK_VERIFY=true \
    sh "${ROOT_DIR}/scripts/install/claude_code.sh"
(
    . "${QUOTED_CLAUDE_HOME}/.config/vpsready/claude_code.env"
    [ "${ANTHROPIC_AUTH_TOKEN}" = "claude-token'quoted" ]
)

SKIP_CONFIG_HOME="${TEST_DIR}/skip-config-home"
mkdir -p "${SKIP_CONFIG_HOME}"
HOME="${SKIP_CONFIG_HOME}" CODEX_TOKEN=codex-test-token \
    MOCK_EXISTING=true MOCK_VERIFY=true \
    sh "${ROOT_DIR}/scripts/install/codex.sh"
[ ! -e "${SKIP_CONFIG_HOME}/.codex/config.toml" ]

: >"${TEST_COMMAND_LOG}"
MOCK_EXISTING=true MOCK_VERIFY=true sh "${ROOT_DIR}/scripts/install/claude_code.sh"
if grep -F -- 'npm install --global' "${TEST_COMMAND_LOG}" >/dev/null 2>&1; then
    printf '%s\n' 'Claude Code CLI was reinstalled unexpectedly' >&2
    exit 1
fi

: >"${TEST_COMMAND_LOG}"
MOCK_EXISTING=true MOCK_VERIFY=true sh "${ROOT_DIR}/scripts/install/codex.sh"
if grep -F -- 'npm install --global' "${TEST_COMMAND_LOG}" >/dev/null 2>&1; then
    printf '%s\n' 'Codex CLI was reinstalled unexpectedly' >&2
    exit 1
fi

if MOCK_EXISTING=false MOCK_NPM_FAIL=true sh "${ROOT_DIR}/scripts/install/codex.sh"; then
    printf '%s\n' 'Codex CLI npm failure was unexpectedly accepted' >&2
    exit 1
fi

if MOCK_EXISTING=false MOCK_VERIFY=false sh "${ROOT_DIR}/scripts/install/claude_code.sh"; then
    printf '%s\n' 'Claude Code CLI verification failure was unexpectedly accepted' >&2
    exit 1
fi

if NPM_REGISTRY=ftp://npm.example.test sh "${ROOT_DIR}/scripts/install/codex.sh"; then
    printf '%s\n' 'Invalid npm registry was unexpectedly accepted' >&2
    exit 1
fi

printf '%s\n' 'Node.js Agent CLI installer tests passed'
