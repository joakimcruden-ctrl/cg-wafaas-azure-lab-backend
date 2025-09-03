#!/usr/bin/env bash
# Ensure we are running under bash even if invoked via 'sh'
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"

set -euo pipefail

BASE="${1:-${S:-}}"
if [[ -z "$BASE" ]]; then
  echo "Usage: $0 <base-url>   e.g. $0 https://<sub>.ccsm-e.se"
  exit 1
fi

# If no scheme provided, default to http://
if ! [[ "$BASE" =~ ^https?:// ]]; then
  BASE="http://$BASE"
fi

# Optional creds for VAmPI (defaults work in the demo image)
API_USER="${API_USER:-morty}"
API_PASS="${API_PASS:-morty}"

# Tuning knobs
SAFE_ONLY="${SAFE_ONLY:-0}"     # 1 = GET only, skip POST/PUT/PATCH
SLEEP="${SLEEP:-0}"             # seconds to sleep between requests (e.g., 0.15)

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "[*] Base URL: $BASE"

# 1) Try to fetch an OpenAPI/Swagger spec from common endpoints
#    Try both at the base and under /api (for path-based routing setups)
schema_url=""
for prefix in "" "/api"; do
  for c in "/openapi3.yml" "/openapi.yaml" "/openapi.json" "/swagger.json"; do
    url="${BASE%/}${prefix}${c}"
    if curl -sSf -m 5 "$url" -o "$workdir/schema.raw" 2>/dev/null; then
      schema_url="$url"
      break 2
    fi
  done
done

if [[ -z "$schema_url" ]]; then
  echo "[!] Could not auto-find an OpenAPI schema at $BASE."
  echo "    Tip: copy it from the container (docker cp ...) and host it temporarily; then re-run."
  exit 2
fi

echo "[*] Found schema at: $schema_url"

# 2) Normalize to JSON (requires yq if YAML)
if [[ "$schema_url" == *.yml || "$schema_url" == *.yaml ]]; then
  if ! command -v yq >/dev/null 2>&1; then
    echo "[!] yq is required to convert YAML schema to JSON. Please install yq and re-run."
    exit 3
  fi
  yq -o=json '.' "$workdir/schema.raw" > "$workdir/schema.json"
else
  # assume JSON already
  cp "$workdir/schema.raw" "$workdir/schema.json"
fi

# 3) Get an auth token (if login exists); otherwise continue unauthenticated
TOKEN=""
if curl -s -m 5 -o /dev/null -w "%{http_code}" "$BASE/users/v1/login" | grep -qE '200|401|404'; then
  TOKEN="$(curl -s -X POST "$BASE/users/v1/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$API_USER\",\"password\":\"$API_PASS\"}" | jq -r '.token // empty' || true)"
fi
AUTH=()
[[ -n "$TOKEN" ]] && AUTH=(-H "Authorization: Bearer $TOKEN")

echo "[*] Using token: $([[ -n "$TOKEN" ]] && echo 'yes' || echo 'no')"

# 4) Iterate paths & methods from the spec
#    We’ll do GET/POST/PUT/PATCH. (Skip DELETE by default to avoid destructive ops.)
paths_and_methods=$(jq -r '
  .paths
  | to_entries[]
  | . as $p
  | ($p.value | keys[] | ascii_downcase)
  | select(IN("get","post","put","patch"))
  | [$p.key, .]
  | @tsv
' "$workdir/schema.json")

if [[ -z "$paths_and_methods" ]]; then
  echo "[!] No usable paths/methods found in schema."
  exit 4
fi

# Helper: fill any {param} with a friendly value
fill_params() {
  echo "$1" | sed 's/{[^}]*}/seed/g'
}

# Helper: choose a sample JSON body for POST/PUT/PATCH
sample_body() {
  local p="$1"
  if [[ "$p" == *"/users/v1/login"* ]]; then
    printf '{"username":"%s","password":"%s"}' "$API_USER" "$API_PASS"
  elif [[ "$p" == *"/users/v1/register"* ]]; then
    printf '{"username":"seed-%s","password":"Lab123!"}' "$RANDOM"
  elif [[ "$p" == *"/books"* ]]; then
    printf '{"title":"Seed","author":"Lab","isbn":"SEED-%s"}' "$RANDOM"
  else
    printf '{"ping":"seed"}'
  fi
}

echo "[*] Hitting endpoints (this seeds API Discovery on WAF)..."
logdir="api-seed-$(date +%F-%H%M%S)"
mkdir -p "$logdir"

ua=(-H 'User-Agent: lab-seeder/1.0' -H 'X-Lab-Seed: true')

while IFS=$'\t' read -r path method; do
  [[ -z "$path" ]] && continue
  m=$(echo "$method" | tr '[:lower:]' '[:upper:]')
  filled=$(fill_params "$path")
  url="$BASE$filled"

  # skip mutating methods if SAFE_ONLY=1
  if [[ "$SAFE_ONLY" = "1" && "$m" != "GET" ]]; then
    continue
  fi

  if [[ "$m" == "GET" ]]; then
    echo "GET  $url"
    curl -s -o "$logdir/$(echo "$m$filled" | tr '/{} ' '_').body" -w "%{http_code} %{time_total}\n" "${ua[@]}" "${AUTH[@]}" "$url" \
      | tee "$logdir/$(echo "$m$filled" | tr '/{} ' '_').code" || true

  elif [[ "$m" == "POST" || "$m" == "PUT" || "$m" == "PATCH" ]]; then
    data=$(sample_body "$filled")
    echo "$m $url"
    curl -s -o "$logdir/$(echo "$m$filled" | tr '/{} ' '_').body" -w "%{http_code} %{time_total}\n" \
      -X "$m" -H 'Content-Type: application/json' "${ua[@]}" "${AUTH[@]}" -d "$data" "$url" \
      | tee "$logdir/$(echo "$m$filled" | tr '/{} ' '_').code" || true
  fi

  # optional pacing
  if [[ "$SLEEP" != "0" ]]; then
    sleep "$SLEEP"
  fi
done <<< "$paths_and_methods"

echo "[*] Done. Logs in: $logdir (one .body and one .code per request)"
