#!/usr/bin/env bash
# Ensure we are running under bash even if invoked via 'sh'
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

# ----------------------------------------
# API Seeder / Discovery Script
# - Discovers an OpenAPI/Swagger schema
# - Enumerates endpoints and exercises them
# - Intentionally SKIPS DELETEs unless SIMULATE_DELETE=1
# - Safe mode (SAFE_ONLY=1) hits only GET endpoints
#
# Env vars:
#   S=<base url>                e.g. http://host[:port][/api]
#   API_USER=<username>         default: morty
#   API_PASS=<password>         default: morty
#   SAFE_ONLY=1                 only GETs
#   SIMULATE_DELETE=1           include DELETEs in a safe "dry run" way
#   SLEEP=<seconds>             delay between requests, e.g. 0.2
#
# Deps: bash, curl, jq, (yq if schema is YAML)
# ----------------------------------------

API_USER="${API_USER:-morty}"
API_PASS="${API_PASS:-morty}"
SLEEP="${SLEEP:-}"
SAFE_ONLY="${SAFE_ONLY:-}"
SIMULATE_DELETE="${SIMULATE_DELETE:-}"

# Accept base URL as arg or env S
BASE="${1:-${S:-}}"
if [[ -z "$BASE" ]]; then
  echo "Usage: S=<base_url> $0    or    $0 <base_url>" >&2
  exit 1
fi

# Normalize: add http:// if missing
if [[ ! "$BASE" =~ ^https?:// ]]; then
  BASE="http://${BASE}"
fi

echo "[*] Base URL: $BASE"

# Try to find an OpenAPI/Swagger schema
SCHEMA_PATHS=(
  "/openapi3.yml"
  "/openapi.yaml"
  "/openapi.json"
  "/swagger.json"
)

SCHEMA_URL=""
for p in "${SCHEMA_PATHS[@]}"; do
  url="$BASE$p"
  if curl -sSfL --max-time 5 "$url" >/dev/null 2>&1; then
    SCHEMA_URL="$url"
    break
  fi
done

if [[ -z "$SCHEMA_URL" ]]; then
  echo "[!] Could not find OpenAPI/Swagger schema under $BASE (tried: ${SCHEMA_PATHS[*]})" >&2
  exit 1
fi

echo "[*] Found schema at: $SCHEMA_URL"

# Download schema to tmp; convert YAML -> JSON if needed
TMPDIR="$(mktemp -d)"
# Use explicit path for rm to avoid PATH issues
RM="/bin/rm"
cleanup() { "$RM" -rf "$TMPDIR" || true; }
trap cleanup EXIT

RAW_SCHEMA="$TMPDIR/schema.raw"
JSON_SCHEMA="$TMPDIR/schema.json"

curl -sSfL "$SCHEMA_URL" -o "$RAW_SCHEMA"

# Tool bootstrap: ensure jq works; for YAML, ensure yq works. If not, fetch static binaries locally.
JQ_BIN="jq"
YQ_BIN="yq"

ensure_jq() {
  if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
    JQ_BIN="jq"; return 0
  fi
  local arch
  arch="$(uname -m || echo x86_64)"
  local url=""
  case "$arch" in
    x86_64|amd64) url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" ;;
    aarch64|arm64) url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-aarch64" ;;
  esac
  if [[ -n "$url" ]]; then
    curl -fsSL "$url" -o "$TMPDIR/jq" && chmod +x "$TMPDIR/jq" && JQ_BIN="$TMPDIR/jq" && return 0
  fi
  return 1
}

ensure_yq() {
  if command -v yq >/dev/null 2>&1 && yq --version >/dev/null 2>&1; then
    YQ_BIN="yq"; return 0
  fi
  local arch
  arch="$(uname -m || echo x86_64)"
  local url=""
  case "$arch" in
    x86_64|amd64) url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" ;;
    aarch64|arm64) url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64" ;;
    armv7l) url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm" ;;
  esac
  if [[ -n "$url" ]]; then
    curl -fsSL "$url" -o "$TMPDIR/yq" && chmod +x "$TMPDIR/yq" && YQ_BIN="$TMPDIR/yq" && return 0
  fi
  return 1
}

# Heuristic: if starts with {, assume JSON; otherwise try yq
if head -c 1 "$RAW_SCHEMA" | grep -q '{'; then
  cp "$RAW_SCHEMA" "$JSON_SCHEMA"
else
  if ! ensure_yq; then
    echo "[!] 'yq' is required to convert YAML to JSON and could not be installed automatically." >&2
    exit 1
  fi
  "$YQ_BIN" -o=json '.' "$RAW_SCHEMA" > "$JSON_SCHEMA"
fi

ensure_jq || { echo "[!] 'jq' is required and could not be installed automatically." >&2; exit 1; }

# Optional login to get token (specific to VAmPI, harmless elsewhere if 404)
TOKEN=""
LOGIN_URL="$BASE/users/v1/login"
LOGIN_BODY=$("$JQ_BIN" -n --arg u "$API_USER" --arg p "$API_PASS" '{username:$u, password:$p}')
if curl -sS --max-time 5 -H 'Content-Type: application/json' -o "$TMPDIR/login.body" -w '%{http_code}' \
  -X POST "$LOGIN_URL" --data "$LOGIN_BODY" | grep -qE '^(200|201)$'; then
  TOKEN="$("$JQ_BIN" -r '.token // empty' "$TMPDIR/login.body" || true)"
fi

if [[ -n "$TOKEN" ]]; then
  echo "[*] Using token: yes"
else
  echo "[*] Using token: no"
fi

# Decide which HTTP methods to include
if [[ -n "$SAFE_ONLY" ]]; then
  INCLUDE_METHODS='["get"]'
else
  if [[ -n "$SIMULATE_DELETE" ]]; then
    INCLUDE_METHODS='["get","post","put","patch","delete"]'
  else
    INCLUDE_METHODS='["get","post","put","patch"]'
  fi
fi

# Output directory
TS="$(date +%F-%H%M%S)"
OUTDIR="api-seed-${TS}"
mkdir -p "$OUTDIR"

# Helper: sleep if requested
maybe_sleep() {
  if [[ -n "$SLEEP" ]]; then
    # shellcheck disable=SC2004
    sleep ${SLEEP}
  fi
}

# Helper: make a filesystem-safe slug for filenames
slugify() {
  local s="$1"
  s="${s//:/%3A}"
  s="${s//\//_}"
  s="${s//\?/_}"
  s="${s//&/_}"
  s="${s//=/~}"
  echo "$s"
}

# Helper: replace {pathParams} with a value
replace_params() {
  local path="$1"
  local value="$2"
  # Replace any {param} occurrences with provided value
  echo "$path" | sed -E 's/\{[^}]+\}/'"$value"'/g'
}

# Helper: build a sample body based on path
build_body() {
  local path="$1"
  case "$path" in
    /users/v1/login)
      "$JQ_BIN" -n --arg u "$API_USER" --arg p "$API_PASS" '{username:$u, password:$p}'
      ;;
    /users/v1/register)
      local uname="user_$RANDOM"
      "$JQ_BIN" -n --arg u "$uname" '{username:$u, password:"Lab123!"}'
      ;;
    /books/v1)
      local isbn="978-$RANDOM"
      "$JQ_BIN" -n --arg t "Seed Book" --arg a "Seed Author" --arg i "$isbn" \
        '{title:$t, author:$a, isbn:$i}'
      ;;
    *)
      "$JQ_BIN" -n '{ping:"seed"}'
      ;;
  esac
}

echo "[*] Hitting endpoints (this seeds API Discovery on WAF)..."

# Iterate over paths & methods in OpenAPI
# Produces lines: "<method>\t<path>"
"$JQ_BIN" -r --argjson include "$INCLUDE_METHODS" '
  .paths
  | to_entries[]
  | {p: .key, ops: (.value | to_entries[])}
  | .ops
  | map(select(.key as $k | $include | index($k)))
  | .[]
  | "\(.key)\t\(.value.operationId // "")\t\(.value.summary // "")\t" + (input_filename | .) # dummy to keep jq happy
' "$JSON_SCHEMA" >/dev/null 2>&1 || true
# The above was a no-op guard for weird specs; we’ll do a simpler extraction:

while IFS=$'\t' read -r METHOD PATH; do
  : # placeholder; we are going to fill with a more robust jq below
done < /dev/null

# Robust extraction: one line per method+path
mapfile -t LINES < <("$JQ_BIN" -r --argjson include "$INCLUDE_METHODS" '
  .paths
  | to_entries[]
  | . as $pathEntry
  | $pathEntry.value
  | to_entries[]
  | select(.key as $k | $include | index($k))
  | "\(.key)\t" + ($pathEntry.key)
' "$JSON_SCHEMA")

for line in "${LINES[@]}"; do
  METHOD="$(cut -f1 <<<"$line")"
  PATH_SPEC="$(cut -f2 <<<"$line")"

  # Path param replacement:
  # - For DELETE (simulation) -> sentinel that shouldn't exist
  # - Otherwise -> generic "seed"
  if [[ "$METHOD" == "delete" ]]; then
    PATH_FILLED="$(replace_params "$PATH_SPEC" "__seed_does_not_exist__")"
  else
    PATH_FILLED="$(replace_params "$PATH_SPEC" "seed")"
  fi

  # Build URL
  URL="$BASE$PATH_FILLED"

  # For DELETE simulation: add dry_run=1 query param & header
  EXTRA_HEADERS=(
    -H "User-Agent: lab-seeder/1.0"
    -H "X-Lab-Seed: true"
  )
  if [[ -n "$TOKEN" ]]; then
    EXTRA_HEADERS+=(-H "Authorization: Bearer $TOKEN")
  fi

  BODY_ARGS=()
  if [[ "$METHOD" == "post" || "$METHOD" == "put" || "$METHOD" == "patch" ]]; then
    BODY_JSON="$(build_body "$PATH_SPEC")"
    BODY_ARGS=(-H "Content-Type: application/json" --data "$BODY_JSON")
  fi

  if [[ "$METHOD" == "delete" ]]; then
    EXTRA_HEADERS+=(-H "X-Lab-Dry-Run: true")
    if [[ "$URL" == *"?"* ]]; then
      URL="${URL}&dry_run=1"
    else
      URL="${URL}?dry_run=1"
    fi
  fi

  # Output filenames
  FN_METHOD="$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')"
  FN_PATH="$(slugify "$PATH_FILLED")"
  BODY_FILE="$OUTDIR/${FN_METHOD}_${FN_PATH}.body"
  CODE_FILE="$OUTDIR/${FN_METHOD}_${FN_PATH}.code"

  # Print to console
  printf "%-4s %s\n" "$FN_METHOD" "$URL"

  # Perform request
  # shellcheck disable=SC2086
  curl -sS -o "$BODY_FILE" -w "%{http_code} %{time_total}\n" -X "$FN_METHOD" "$URL" "${EXTRA_HEADERS[@]}" ${BODY_ARGS[@]+"${BODY_ARGS[@]}"} | tee "$CODE_FILE"

  maybe_sleep
done

echo "[*] Done. Logs in: $OUTDIR (one .body and one .code per request)"
