#!/bin/bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing $ENV_FILE" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${CPPMODEL_USERNAME:?CPPMODEL_USERNAME not set in .env}"
: "${CPPMODEL_PASSWORD:?CPPMODEL_PASSWORD not set in .env}"
# Public client every account uses (see api/workspace-api.yaml); .env may override it.
CPPMODEL_CLIENT_ID="${CPPMODEL_CLIENT_ID:-cppmodel-frontend}"

WORKSPACE_OVERRIDE=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --workspace)
        WORKSPACE_OVERRIDE="$2"
        shift 2
        ;;
    *)
        ARGS+=("$1")
        shift
        ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

DISCOVERY_URL="https://auth.cppmodel.com/realms/CppModel/.well-known/openid-configuration"
TOKEN_ENDPOINT=$(curl -sf "$DISCOVERY_URL" | python3 -c "import json,sys; print(json.load(sys.stdin)['token_endpoint'])")

ACCESS_TOKEN=$(curl -sf -X POST "$TOKEN_ENDPOINT" \
    -d "grant_type=password" \
    --data-urlencode "client_id=$CPPMODEL_CLIENT_ID" \
    --data-urlencode "username=$CPPMODEL_USERNAME" \
    --data-urlencode "password=$CPPMODEL_PASSWORD" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

WORKSPACE=$(python3 -c "
import base64, json, sys

token = sys.argv[1]
override = sys.argv[2]

if override:
    print(override)
    sys.exit(0)

payload_b64 = token.split('.')[1]
padded = payload_b64 + '=' * (-len(payload_b64) % 4)
payload = json.loads(base64.urlsafe_b64decode(padded))
groups = [g.lstrip('/') for g in payload.get('groups', [])]

if len(groups) == 1:
    print(groups[0])
elif len(groups) == 0:
    print('Token has no workspace groups; pass --workspace explicitly.', file=sys.stderr)
    sys.exit(1)
else:
    print('Token belongs to multiple workspaces (' + ', '.join(groups) + '); pass --workspace to pick one.', file=sys.stderr)
    sys.exit(1)
" "$ACCESS_TOKEN" "$WORKSPACE_OVERRIDE")

CPPMODEL_API_BASE="https://$WORKSPACE.cppmodel.com/api"

# --fail-with-body: on an HTTP error, still print the server's {"code","message"} body (e.g.
# "No input data found" for a simulation that has none posted) and exit nonzero.
fetch() {
    curl -s --fail-with-body -H "Authorization: Bearer $ACCESS_TOKEN" "$CPPMODEL_API_BASE$1"
}

url_encode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

case "${1:-}" in
"")
    fetch "/simulations?scope=user" | python3 -m json.tool
    ;;
executions)
    fetch "/simulations/$(url_encode "$2")/executions" | python3 -m json.tool
    ;;
execution)
    fetch "/simulations/$(url_encode "$2")/executions/$(url_encode "$3")" | python3 -m json.tool
    ;;
inputs)
    fetch "/simulations/$(url_encode "$2")/inputs" | python3 -m json.tool
    ;;
set-inputs)
    # Replaces the simulation's whole input/parameter document with the JSON file's contents.
    [ -f "${3:-}" ] || { echo "Usage: set-inputs <simulation name> <inputs.json>" >&2; exit 1; }
    curl -s --fail-with-body -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" --data-binary "@$3" \
        "$CPPMODEL_API_BASE/simulations/$(url_encode "$2")/inputs"
    echo "Inputs saved for '$2'" >&2
    ;;
*)
    fetch "/simulations/$(url_encode "$1")" | python3 -m json.tool
    ;;
esac
