#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../aperture/config.json"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/../.env}"
APERTURE_HOST="${APERTURE_HOST:-ai.bun-bull.ts.net}"
APERTURE_URL="http://${APERTURE_HOST}/api/config"
KUBE_CONTEXT="${KUBE_CONTEXT:-orbstack}"
LITELLM_NAMESPACE="${LITELLM_NAMESPACE:-lllm}"
LITELLM_SECRET_NAME="${LITELLM_SECRET_NAME:-litellm-secrets}"

if [ -z "${LITELLM_API_KEY:-}" ] && [ -f "$ENV_FILE" ]; then
    LITELLM_API_KEY=$(sed -n 's/^LITELLM_API_KEY=//p' "$ENV_FILE" | tail -n 1)
fi

if [ -z "${KIMI_API_KEY:-}" ] && [ -f "$ENV_FILE" ]; then
    KIMI_API_KEY=$(sed -n 's/^KIMI_API_KEY=//p' "$ENV_FILE" | tail -n 1)
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ -f "$ENV_FILE" ]; then
    DEEPSEEK_API_KEY=$(sed -n 's/^DEEPSEEK_API_KEY=//p' "$ENV_FILE" | tail -n 1)
fi

if [ -z "${LITELLM_API_KEY:-}" ]; then
    LITELLM_API_KEY=$(kubectl --context "$KUBE_CONTEXT" get secret "$LITELLM_SECRET_NAME" \
        -n "$LITELLM_NAMESPACE" -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
fi

if [ -z "$LITELLM_API_KEY" ]; then
    echo "Error: LiteLLM API key is empty"
    exit 1
fi

export LITELLM_API_KEY
export KIMI_API_KEY
export DEEPSEEK_API_KEY

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config not found at $CONFIG_FILE"
    exit 1
fi

echo "Validating config..."
if python3 -c "import json; json.load(open('$CONFIG_FILE'))"; then
    echo "Valid JSON"
else
    echo "Invalid JSON"
    exit 1
fi

echo "Fetching current hash..."
CURRENT_HASH=$(curl -s "$APERTURE_URL" | python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")
echo "Current hash: $CURRENT_HASH"

echo "Applying config to Aperture ($APERTURE_URL)..."
PAYLOAD=$(python3 -c "
import json
import os

config = json.load(open('$CONFIG_FILE'))
config['providers']['LiteLLM']['apikey'] = os.environ['LITELLM_API_KEY']
if os.environ.get('KIMI_API_KEY'):
    config['providers']['KiMi-Cloud-Anthropic']['apikey'] = os.environ['KIMI_API_KEY']
    config['providers']['KiMi-Cloud-OpenAI']['apikey'] = os.environ['KIMI_API_KEY']
if os.environ.get('DEEPSEEK_API_KEY'):
    config['providers']['DeepSeek-Cloud-Anthropic']['apikey'] = os.environ['DEEPSEEK_API_KEY']
    config['providers']['DeepSeek-Cloud-OpenAI']['apikey'] = os.environ['DEEPSEEK_API_KEY']
print(json.dumps({'hash': '$CURRENT_HASH', 'config': json.dumps(config, indent=4)}))
")
RESPONSE=$(echo "$PAYLOAD" | curl -s -w "\n%{http_code}" -X PUT "$APERTURE_URL" -d @- -H "Content-Type: application/json")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "Success: config applied"
else
    echo "Error (HTTP $HTTP_CODE): $BODY"
    echo "Warning: Aperture config was not updated."
    exit 1
fi
