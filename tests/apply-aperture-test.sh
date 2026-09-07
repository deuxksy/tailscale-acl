#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${TMPDIR:-/tmp}/sylph-apply-aperture-test"
TEST_BIN="${TEST_ROOT}/bin"
CAPTURE_FILE="${TEST_ROOT}/payload.json"
URL_FILE="${TEST_ROOT}/urls.txt"
ENV_FILE_PATH="${TEST_ROOT}/.env"
MISSING_ENV_FILE="${TEST_ROOT}/missing-${PPID}.env"

mkdir -p "$TEST_BIN"

cat > "${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
    case "$argument" in
        http://*) printf '%s\n' "$argument" >> "${TEST_URL_FILE:-/dev/null}" ;;
    esac
done

if [[ " $* " == *" -X PUT "* ]]; then
    tee "$TEST_CAPTURE_FILE"
    printf '\n200'
else
    printf '{"hash":"test-hash"}'
fi
EOF
chmod +x "${TEST_BIN}/curl"

cat > "${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${TEST_EMPTY_SECRET:-}" = "1" ]; then
    exit 0
fi

printf 'dGVzdC1rdWJlcm5ldGVzLWtleQ=='
EOF
chmod +x "${TEST_BIN}/kubectl"

TEST_CAPTURE_FILE="$CAPTURE_FILE" \
LITELLM_API_KEY="test-litellm-key" \
PATH="${TEST_BIN}:${PATH}" \
APERTURE_HOST="test-aperture" \
bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

python3 - "$CAPTURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    payload = json.load(file)

config = json.loads(payload["config"])
actual = config["providers"]["LiteLLM"]["apikey"]
assert actual == "test-litellm-key", f"expected injected API key, got {actual!r}"
PY

echo "PASS: injects LITELLM_API_KEY into Aperture payload"

: > "$CAPTURE_FILE"

env -u LITELLM_API_KEY \
    ENV_FILE="$MISSING_ENV_FILE" \
    TEST_CAPTURE_FILE="$CAPTURE_FILE" \
    PATH="${TEST_BIN}:${PATH}" \
    APERTURE_HOST="test-aperture" \
    bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

python3 - "$CAPTURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    payload = json.load(file)

config = json.loads(payload["config"])
actual = config["providers"]["LiteLLM"]["apikey"]
assert actual == "test-kubernetes-key", f"expected Kubernetes API key, got {actual!r}"
PY

echo "PASS: reads LiteLLM API key from Kubernetes Secret"

: > "$CAPTURE_FILE"

set +e
OUTPUT=$(env -u LITELLM_API_KEY \
    ENV_FILE="$MISSING_ENV_FILE" \
    TEST_EMPTY_SECRET="1" \
    TEST_CAPTURE_FILE="$CAPTURE_FILE" \
    PATH="${TEST_BIN}:${PATH}" \
    APERTURE_HOST="test-aperture" \
    bash "${REPO_ROOT}/scripts/apply-aperture.sh" 2>&1)
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "FAIL: expected empty LiteLLM API key to stop before PUT"
    exit 1
fi

if [[ "$OUTPUT" != *"LiteLLM API key is empty"* ]]; then
    echo "FAIL: missing empty API key error"
    exit 1
fi

if [ -s "$CAPTURE_FILE" ]; then
    echo "FAIL: PUT payload was sent with an empty API key"
    exit 1
fi

echo "PASS: rejects empty LiteLLM API key before PUT"

: > "$CAPTURE_FILE"
: > "$URL_FILE"

env -u APERTURE_HOST \
    TEST_CAPTURE_FILE="$CAPTURE_FILE" \
    TEST_URL_FILE="$URL_FILE" \
    LITELLM_API_KEY="test-litellm-key" \
    PATH="${TEST_BIN}:${PATH}" \
    bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

if ! grep -qx 'http://ai.bun-bull.ts.net/api/config' "$URL_FILE"; then
    echo "FAIL: expected default Aperture FQDN"
    exit 1
fi

echo "PASS: uses Aperture FQDN by default"

printf 'LITELLM_API_KEY=test-env-file-key\nKIMI_API_KEY=test-env-kimi-key\nDEEPSEEK_API_KEY=test-env-deepseek-key\n' > "$ENV_FILE_PATH"
: > "$CAPTURE_FILE"

env -u LITELLM_API_KEY \
    ENV_FILE="$ENV_FILE_PATH" \
    TEST_CAPTURE_FILE="$CAPTURE_FILE" \
    PATH="${TEST_BIN}:${PATH}" \
    APERTURE_HOST="test-aperture" \
    bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

python3 - "$CAPTURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    payload = json.load(file)

config = json.loads(payload["config"])
actual = config["providers"]["LiteLLM"]["apikey"]
assert actual == "test-env-file-key", f"expected .env API key, got {actual!r}"
assert config["providers"]["KiMi-Cloud-Anthropic"]["apikey"] == "test-env-kimi-key"
assert config["providers"]["KiMi-Cloud-OpenAI"]["apikey"] == "test-env-kimi-key"
assert config["providers"]["DeepSeek-Cloud-Anthropic"]["apikey"] == "test-env-deepseek-key"
assert config["providers"]["DeepSeek-Cloud-OpenAI"]["apikey"] == "test-env-deepseek-key"
PY

echo "PASS: reads provider API keys from .env"

: > "$CAPTURE_FILE"

TEST_CAPTURE_FILE="$CAPTURE_FILE" \
LITELLM_API_KEY="test-litellm-key" \
KIMI_API_KEY="test-kimi-key" \
PATH="${TEST_BIN}:${PATH}" \
APERTURE_HOST="test-aperture" \
bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

python3 - "$CAPTURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    payload = json.load(file)

providers = json.loads(payload["config"])["providers"]
assert providers["KiMi-Cloud-Anthropic"]["apikey"] == "test-kimi-key"
assert providers["KiMi-Cloud-OpenAI"]["apikey"] == "test-kimi-key"
PY

echo "PASS: injects KIMI_API_KEY into both Kimi providers"

: > "$CAPTURE_FILE"

TEST_CAPTURE_FILE="$CAPTURE_FILE" \
LITELLM_API_KEY="test-litellm-key" \
DEEPSEEK_API_KEY="test-deepseek-key" \
PATH="${TEST_BIN}:${PATH}" \
APERTURE_HOST="test-aperture" \
bash "${REPO_ROOT}/scripts/apply-aperture.sh" >/dev/null

python3 - "$CAPTURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    payload = json.load(file)

providers = json.loads(payload["config"])["providers"]
assert providers["DeepSeek-Cloud-Anthropic"]["apikey"] == "test-deepseek-key"
assert providers["DeepSeek-Cloud-OpenAI"]["apikey"] == "test-deepseek-key"
PY

echo "PASS: injects DEEPSEEK_API_KEY into both DeepSeek providers"
