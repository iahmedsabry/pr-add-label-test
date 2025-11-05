#!/usr/bin/env bash
set -euo pipefail

# Compute PR change size and add a size/* label accordingly.
# Requirements: bash, curl, jq
# Env:
#   - GITHUB_TOKEN (required)
#   - GITHUB_EVENT_PATH (required)
#   - INPUT_SIZES (optional JSON map: {"0":"XS","20":"S",...})
#   - IGNORED (optional newline-separated globs; lines starting with '!' are inclusions)
#   - GITHUB_API_URL (optional; defaults to https://api.github.com)
#   - DEBUG_ACTION (optional: enable debug logs)

debug() { [[ -n "${DEBUG_ACTION:-}" ]] && echo "[debug] $*" >&2 || true; }
err() { echo "$*" >&2; }
require_env() { local n="$1"; [[ -n "${!n:-}" ]] || { err "Missing required env: $n"; exit 1; }; }

require_env GITHUB_TOKEN
require_env GITHUB_EVENT_PATH

API_BASE="${GITHUB_API_URL:-https://api.github.com}"
event_json="$(cat "$GITHUB_EVENT_PATH")"

# Validate event type
action="$(jq -r '.action // empty' <<<"$event_json")"
if [[ "$action" != "opened" && "$action" != "synchronize" && "$action" != "reopened" ]]; then
  echo "Action will be ignored: ${action:-null}"
  exit 0
fi

owner="$(jq -r '.pull_request.base.repo.owner.login' <<<"$event_json")"
repo="$(jq -r '.pull_request.base.repo.name' <<<"$event_json")"
pr_number="$(jq -r '.pull_request.number' <<<"$event_json")"
[[ -n "$owner" && -n "$repo" && -n "$pr_number" && "$owner" != null && "$repo" != null && "$pr_number" != null ]] || {
  err "Invalid pull_request context in GITHUB_EVENT_PATH"; exit 1; }

# Sizes config
if [[ -n "${INPUT_SIZES:-}" ]]; then
  sizes_json="$INPUT_SIZES"
else
  sizes_json='{"0":"XS","10":"S","30":"M","100":"L","500":"XL","1000":"XXL"}'
fi
debug "Sizes: $sizes_json"

# IGNORED handling (basic globbing; treats ** as *)
normalize_pattern() { local p="$1"; echo "${p//\*\*/\*}"; }
is_ignored_path() {
  local path="$1"
  [[ -z "$path" || "$path" == "/dev/null" ]] && return 0
  local ignore=false
  if [[ -n "${IGNORED:-}" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == !* ]]; then
        local patt; patt="$(normalize_pattern "${line:1}")"
        [[ "$path" == $patt ]] && return 1
      else
        local patt; patt="$(normalize_pattern "$line")"
        if [[ "$ignore" == false && "$path" == $patt ]]; then
          ignore=true
        fi
      fi
    done <<<"$IGNORED"
  fi
  [[ "$ignore" == true ]]
}

# Sum changed lines from PR files
changed_lines=0
per_page=100
page=1
while :; do
  url="${API_BASE}/repos/${owner}/${repo}/pulls/${pr_number}/files?per_page=${per_page}&page=${page}"
  resp="$(curl -sfSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.raw+json" "$url")" || {
    err "Failed to fetch PR files (page $page)"; exit 1; }
  count_page="$(jq 'length' <<<"$resp")"
  [[ "$count_page" -eq 0 ]] && break
  while IFS= read -r row; do
    filename="$(jq -r '.filename' <<<"$row")"
    prev_filename="$(jq -r '.previous_filename // empty' <<<"$row")"
    changes="$(jq -r '.changes' <<<"$row")"
    if is_ignored_path "$prev_filename" && is_ignored_path "$filename"; then
      continue
    fi
    [[ "$changes" =~ ^[0-9]+$ ]] && changed_lines=$((changed_lines + changes)) || true
  done < <(jq -c '.[]' <<<"$resp")
  [[ "$count_page" -lt "$per_page" ]] && break
  page=$((page + 1))
done

echo "Changed lines: $changed_lines"

# Compute size label
size_label=""
mapfile -t thresholds < <(jq -r 'keys[]' <<<"$sizes_json" | sort -n)
for t in "${thresholds[@]}"; do
  if [[ "$changed_lines" -ge "$t" ]]; then
    value="$(jq -r --arg t "$t" '.[$t]' <<<"$sizes_json")"
    size_label="size/${value}"
  fi
done

echo "Matching label: $size_label"
[[ -n "$size_label" ]] || { err "No size label computed"; exit 1; }

# Add label
payload="$(jq -n --arg l "$size_label" '{labels: [$l]}')"
curl -sfSL -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API_BASE}/repos/${owner}/${repo}/issues/${pr_number}/labels" \
  -d "$payload" >/dev/null

echo "Added label: ${size_label}"


