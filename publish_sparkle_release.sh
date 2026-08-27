#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  publish_sparkle_release.sh --version <version> --artifact <app-or-zip> [options]

Required:
  --version <value>               Release version/tag suffix
  --artifact <path>               Signed .app bundle or prebuilt .zip

Optional:
  --app-name <value>              Asset prefix and release title base
  --repo-owner <value>            GitHub owner/org; falls back to origin remote
  --repo-name <value>             GitHub repo name; falls back to origin remote
  --release-notes <path>          HTML file copied into the docs site
  --github-release-notes <path>   Markdown/plain-text file used for the GitHub release body
  --docs-dir <path>               Docs output directory (default: ./docs)
  --releases-dir <path>           Archive output directory (default: ./release-artifacts)
  --tag-prefix <value>            Git tag prefix (default: v)
  --release-title <value>         GitHub release title (default: "<app-name> <version>")
  --channel <stable|beta>         Release channel (default: stable)
  --download-url-base <url>       Override asset base URL
  --pages-base-url <url>          Override GitHub Pages base URL
  --working-dir <path>            Repository root for git/gh operations (default: cwd)
  --skip-appcast-commit           Update appcast locally but do not git commit/push it
  --upload-only                   Upload the artifact to GitHub Releases without regenerating the appcast

Notes:
  - Sparkle's generate_appcast must be available, or SPARKLE_GENERATE_APPCAST must be set.
  - If generate_appcast requires an explicit key file, set SPARKLE_PRIVATE_KEY_PATH.
EOF
}

VERSION=""
ARTIFACT=""
APP_NAME=""
RELEASE_NOTES_PATH=""
GITHUB_RELEASE_NOTES_PATH=""
REPO_OWNER=""
REPO_NAME=""
DOCS_DIR=""
RELEASES_DIR=""
TAG_PREFIX="v"
RELEASE_TITLE=""
CHANNEL="${SHIPHOOK_RELEASE_CHANNEL:-stable}"
DOWNLOAD_URL_BASE=""
PAGES_BASE_URL=""
WORKING_DIR="$(pwd)"
SKIP_APPCAST_COMMIT=0
UPLOAD_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --artifact)
      ARTIFACT="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --github-release-notes)
      GITHUB_RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --repo-owner)
      REPO_OWNER="$2"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="$2"
      shift 2
      ;;
    --docs-dir)
      DOCS_DIR="$2"
      shift 2
      ;;
    --releases-dir)
      RELEASES_DIR="$2"
      shift 2
      ;;
    --tag-prefix)
      TAG_PREFIX="$2"
      shift 2
      ;;
    --release-title)
      RELEASE_TITLE="$2"
      shift 2
      ;;
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    --download-url-base)
      DOWNLOAD_URL_BASE="$2"
      shift 2
      ;;
    --pages-base-url)
      PAGES_BASE_URL="$2"
      shift 2
      ;;
    --working-dir)
      WORKING_DIR="$2"
      shift 2
      ;;
    --skip-appcast-commit)
      SKIP_APPCAST_COMMIT=1
      shift
      ;;
    --upload-only)
      UPLOAD_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$ARTIFACT" ]]; then
  usage
  exit 1
fi

if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "beta" ]]; then
  echo "Unsupported channel: $CHANNEL" >&2
  exit 1
fi

resolve_path() {
  local input="$1"
  if [[ -z "$input" ]]; then
    return 0
  fi
  python3 - <<'PY' "$input"
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

ARTIFACT="$(resolve_path "$ARTIFACT")"
WORKING_DIR="$(resolve_path "$WORKING_DIR")"
DOCS_DIR="${DOCS_DIR:-$WORKING_DIR/docs}"
RELEASES_DIR="${RELEASES_DIR:-$WORKING_DIR/release-artifacts}"
DOCS_DIR="$(resolve_path "$DOCS_DIR")"
RELEASES_DIR="$(resolve_path "$RELEASES_DIR")"
APPCAST_DIR="$DOCS_DIR"
if [[ "$CHANNEL" == "beta" ]]; then
  APPCAST_DIR="$DOCS_DIR/beta"
fi
APPCAST_PATH="$APPCAST_DIR/appcast.xml"

if [[ ! -e "$ARTIFACT" ]]; then
  echo "Artifact not found: $ARTIFACT" >&2
  exit 1
fi

if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  RELEASE_NOTES_PATH="$(resolve_path "$RELEASE_NOTES_PATH")"
  if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
    echo "Release notes not found: $RELEASE_NOTES_PATH" >&2
    exit 1
  fi
fi

if [[ -n "$GITHUB_RELEASE_NOTES_PATH" ]]; then
  GITHUB_RELEASE_NOTES_PATH="$(resolve_path "$GITHUB_RELEASE_NOTES_PATH")"
  if [[ ! -f "$GITHUB_RELEASE_NOTES_PATH" ]]; then
    echo "GitHub release notes not found: $GITHUB_RELEASE_NOTES_PATH" >&2
    exit 1
  fi
fi

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    printf '%s\n' "$SPARKLE_GENERATE_APPCAST"
    return 0
  fi

  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [[ -d "$derived_data" ]]; then
    find "$derived_data" -type f \
      \( -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -o -path '*/SourcePackages/checkouts/Sparkle/generate_appcast' \) \
      2>/dev/null | head -n 1
    return 0
  fi

  return 1
}

GENERATE_APPCAST=""
if [[ "$UPLOAD_ONLY" -eq 0 ]]; then
  GENERATE_APPCAST="$(find_generate_appcast)"
  if [[ -z "${GENERATE_APPCAST:-}" || ! -x "$GENERATE_APPCAST" ]]; then
    echo "Could not find Sparkle's generate_appcast tool." >&2
    echo "Set SPARKLE_GENERATE_APPCAST to the full path after Xcode resolves the Sparkle package." >&2
    exit 1
  fi
fi

if [[ -z "$REPO_OWNER" || -z "$REPO_NAME" ]]; then
  REMOTE_URL="$(git -C "$WORKING_DIR" remote get-url origin)"
  if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    REPO_OWNER="${REPO_OWNER:-${BASH_REMATCH[1]}}"
    REPO_NAME="${REPO_NAME:-${BASH_REMATCH[2]}}"
  else
    echo "Could not parse GitHub owner/repo from origin: $REMOTE_URL" >&2
    exit 1
  fi
fi

APP_NAME="${APP_NAME:-$REPO_NAME}"
TAG_SUFFIX=""
if [[ "$CHANNEL" == "beta" ]]; then
  TAG_SUFFIX="-beta"
fi
TAG="${TAG_PREFIX}${VERSION}${TAG_SUFFIX}"
DOWNLOAD_URL_BASE="${DOWNLOAD_URL_BASE:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://${REPO_OWNER}.github.io/${REPO_NAME}}"
CHANNEL_PAGES_BASE_URL="$PAGES_BASE_URL"
if [[ "$CHANNEL" == "beta" ]]; then
  CHANNEL_PAGES_BASE_URL="${PAGES_BASE_URL}/beta"
fi
if [[ "$CHANNEL" == "beta" ]]; then
  RELEASE_TITLE="${RELEASE_TITLE:-${APP_NAME} ${VERSION} Beta}"
else
  RELEASE_TITLE="${RELEASE_TITLE:-${APP_NAME} ${VERSION}}"
fi
RELEASE_NOTES_URL=""

mkdir -p "$APPCAST_DIR" "$RELEASES_DIR"

make_archive_if_needed() {
  local input_path="$1"
  local suffix=""
  if [[ "$CHANNEL" == "beta" ]]; then
    suffix="-beta"
  fi
  local output_path="$RELEASES_DIR/${APP_NAME}-${VERSION}${suffix}.zip"

  if [[ -d "$input_path" && "$input_path" == *.app ]]; then
    echo "Packaging exported app into $(basename "$output_path")..." >&2
    ditto -c -k --sequesterRsrc --keepParent "$input_path" "$output_path"
    printf '%s\n' "$output_path"
    return 0
  fi

  if [[ -f "$input_path" && "$input_path" == *.zip ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi

  echo "Artifact must be a signed .app bundle or a .zip archive: $input_path" >&2
  exit 1
}

ARCHIVE_PATH="$(make_archive_if_needed "$ARTIFACT")"
ASSET_NAME="$(basename "$ARCHIVE_PATH")"
DOWNLOAD_URL="${DOWNLOAD_URL_BASE}/${ASSET_NAME}"

if [[ ! -s "$ARCHIVE_PATH" ]]; then
  echo "Release archive is empty and cannot be uploaded: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ "$ARCHIVE_PATH" == *.zip ]]; then
  APP_INFO_PLIST_PATH="$(unzip -Z1 "$ARCHIVE_PATH" '*.app/Contents/Info.plist' 2>/dev/null | grep -E '^[^/]+\.app/Contents/Info\.plist$' | head -n 1 || true)"
  if [[ -z "${APP_INFO_PLIST_PATH:-}" ]]; then
    echo "Could not find the top-level app Info.plist inside archive: $ARCHIVE_PATH" >&2
    exit 1
  fi

  if ! unzip -p "$ARCHIVE_PATH" "$APP_INFO_PLIST_PATH" >/dev/null 2>&1; then
    echo "Could not inspect Info.plist inside archive: $ARCHIVE_PATH" >&2
    exit 1
  fi

  BUNDLE_VERSION="$(unzip -p "$ARCHIVE_PATH" "$APP_INFO_PLIST_PATH" | plutil -extract CFBundleVersion raw -o - - 2>/dev/null || true)"
  if [[ -z "${BUNDLE_VERSION:-}" ]]; then
    echo "Archive is missing CFBundleVersion. Sparkle requires a numeric build version." >&2
    exit 1
  fi

  if ! [[ "$BUNDLE_VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    echo "CFBundleVersion must be numeric for Sparkle updates. Found: $BUNDLE_VERSION" >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_github_release_notes() {
  local input_path="$1"
  local output_path="$2"

  python3 - <<'PY' "$input_path" "$output_path" "$RELEASE_TITLE"
from html.parser import HTMLParser
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
fallback_title = sys.argv[3]
raw = source.read_text(encoding="utf-8", errors="replace")
lower = raw[:4096].lower()

if "<html" not in lower and "<!doctype" not in lower:
    destination.write_text(raw.strip() + "\n", encoding="utf-8")
    raise SystemExit(0)

class NotesParser(HTMLParser):
    block_tags = {"p", "div", "section", "article", "main", "header", "footer", "li", "br", "h1", "h2", "h3", "h4", "h5", "h6"}

    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip_depth = 0
        self.links = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in {"script", "style", "title"}:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag in self.block_tags:
            self.parts.append("\n")
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in {"script", "style", "title"} and self.skip_depth:
            self.skip_depth -= 1
            return
        if self.skip_depth:
            return
        if tag in self.block_tags:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip_depth:
            self.parts.append(data)

parser = NotesParser()
parser.feed(raw)
text = "".join(parser.parts)
lines = []
for line in text.splitlines():
    collapsed = re.sub(r"\s+", " ", line).strip()
    if collapsed:
        lines.append(collapsed)

body = "\n\n".join(lines).strip()
if not body:
    body = fallback_title
destination.write_text(body + "\n", encoding="utf-8")
PY
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

github_auth_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "$GH_TOKEN" | normalize_github_token
    return 0
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s\n' "$GITHUB_TOKEN" | normalize_github_token
    return 0
  fi
  local gh_bin
  gh_bin="$(find_gh)" || return 0
  "$gh_bin" auth token 2>/dev/null | normalize_github_token || true
}

find_gh() {
  if command -v gh >/dev/null 2>&1; then
    command -v gh
    return 0
  fi
  if [[ -x "/opt/homebrew/bin/gh" ]]; then
    printf '%s\n' "/opt/homebrew/bin/gh"
    return 0
  fi
  if [[ -x "/usr/local/bin/gh" ]]; then
    printf '%s\n' "/usr/local/bin/gh"
    return 0
  fi
  return 1
}

normalize_github_token() {
  python3 -c 'import re, sys
token = sys.stdin.read()
token = token.strip()
token = re.sub(r"^(?i:bearer|token)\s+", "", token)
token = re.sub(r"\s+", "", token)
if len(token) >= 6 and re.fullmatch(r"[-*•●]+", token):
    token = ""
print(token)
'
}

write_github_headers() {
  local token="$1"
  local headers_file="$2"
  {
    printf 'Accept: application/vnd.github+json\n'
    printf 'Authorization: Bearer %s\n' "$token"
    printf 'X-GitHub-Api-Version: 2022-11-28\n'
  } > "$headers_file"
}

github_request() {
  local method="$1"
  local url="$2"
  local headers_file="$3"
  shift 3

  local curl_output
  if ! curl_output="$(curl --fail-with-body --silent --show-error --location \
    --request "$method" \
    --header "@$headers_file" \
    "$@" \
    "$url" 2>&1)"; then
    echo "$curl_output" >&2
    return 1
  fi
  printf '%s' "$curl_output"
}

upload_release_asset() {
  local token
  token="$(github_auth_token)"
  if [[ -z "${token:-}" ]]; then
    echo "Could not resolve a GitHub token for release asset upload." >&2
    exit 1
  fi

  local headers_file
  headers_file="$TMP_DIR/github-upload-headers.txt"
  write_github_headers "$token" "$headers_file"

  local encoded_tag release_json release_id upload_template
  encoded_tag="$(urlencode "$TAG")"
  release_json="$(github_request GET "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${encoded_tag}" "$headers_file")"
  release_id="$(printf '%s' "$release_json" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("id", ""))')"
  upload_template="$(printf '%s' "$release_json" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("upload_url", ""))')"
  if [[ -z "${release_id:-}" || "$release_id" == "null" || -z "${upload_template:-}" ]]; then
    echo "Could not resolve GitHub Release upload URL for ${TAG}." >&2
    exit 1
  fi

  local assets_json
  assets_json="$(github_request GET "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${release_id}/assets?per_page=100" "$headers_file")"
  while IFS= read -r asset_id; do
    [[ -n "$asset_id" ]] || continue
    github_request DELETE "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${asset_id}" "$headers_file" >/dev/null
  done < <(printf '%s' "$assets_json" | python3 -c 'import json, sys
name = sys.argv[1]
for asset in json.load(sys.stdin):
    if asset.get("name") == name:
        print(asset.get("id", ""))
' "$ASSET_NAME")

  local encoded_name upload_base upload_url
  encoded_name="$(urlencode "$ASSET_NAME")"
  upload_base="${upload_template%%\{*}"
  upload_base="${upload_base%%\?*}"
  upload_url="${upload_base}?name=${encoded_name}"

  local upload_connect_timeout upload_max_time upload_limit_rate
  upload_connect_timeout="${SHIPHOOK_GITHUB_UPLOAD_CONNECT_TIMEOUT:-30}"
  upload_max_time="${SHIPHOOK_GITHUB_UPLOAD_MAX_TIME:-1800}"
  upload_limit_rate="${SHIPHOOK_GITHUB_UPLOAD_LIMIT_RATE:-256k}"

  local curl_output
  if ! curl_output="$(curl --fail-with-body --silent --show-error --location \
    --request POST \
    --connect-timeout "$upload_connect_timeout" \
    --max-time "$upload_max_time" \
    --limit-rate "$upload_limit_rate" \
    --header "@$headers_file" \
    --header "Content-Type: application/octet-stream" \
    --data-binary "@$ARCHIVE_PATH" \
    "$upload_url" 2>&1)"; then
    local gh_bin
    if gh_bin="$(find_gh)"; then
      echo "curl upload failed; retrying GitHub asset upload with gh api..." >&2
      local gh_output
      if gh_output="$("$gh_bin" api \
        --method POST \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        --header "Content-Type: application/octet-stream" \
        --input "$ARCHIVE_PATH" \
        "$upload_url" 2>&1)"; then
        return 0
      fi
      echo "$gh_output" >&2
    fi
    echo "$curl_output" >&2
    exit 1
  fi
}

if [[ "$UPLOAD_ONLY" -eq 0 ]]; then
  cp "$ARCHIVE_PATH" "$TMP_DIR/"

  if [[ -n "$RELEASE_NOTES_PATH" ]]; then
    mkdir -p "$APPCAST_DIR/release-notes"
    RELEASE_NOTES_BASENAME="${VERSION}.html"
    cp "$RELEASE_NOTES_PATH" "$APPCAST_DIR/release-notes/$RELEASE_NOTES_BASENAME"
    RELEASE_NOTES_URL="${CHANNEL_PAGES_BASE_URL}/release-notes/${RELEASE_NOTES_BASENAME}"
  fi

  if [[ -z "$GITHUB_RELEASE_NOTES_PATH" && -n "$RELEASE_NOTES_PATH" ]]; then
    GITHUB_RELEASE_NOTES_PATH="$TMP_DIR/github-release-notes.md"
    make_github_release_notes "$RELEASE_NOTES_PATH" "$GITHUB_RELEASE_NOTES_PATH"
  fi

  CMD=("$GENERATE_APPCAST" "$TMP_DIR")
  HELP_TEXT="$("$GENERATE_APPCAST" -h 2>&1 || true)"
  if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
    if grep -q -- '--ed-key-file' <<<"$HELP_TEXT"; then
      CMD+=("--ed-key-file" "$SPARKLE_PRIVATE_KEY_PATH")
    fi
  fi

  if [[ "${SHIPHOOK_SPARKLE_DELTA_UPDATES:-0}" == "1" ]]; then
    if grep -q -- '--generate-deltas' <<<"$HELP_TEXT"; then
      echo "Sparkle delta updates are enabled for this repository."
      CMD+=("--generate-deltas")
    else
      echo "Sparkle delta updates requested, but this generate_appcast does not advertise --generate-deltas. Continuing with a full update."
    fi
  fi

  "${CMD[@]}"

  GENERATED_APPCAST="$(find "$TMP_DIR" -maxdepth 1 -type f -name '*.xml' | head -n 1)"
  if [[ -z "${GENERATED_APPCAST:-}" || ! -f "$GENERATED_APPCAST" ]]; then
    echo "generate_appcast did not produce an XML file in $TMP_DIR" >&2
    exit 1
  fi

  cp "$GENERATED_APPCAST" "$APPCAST_PATH"
  perl -0pi -e 's#url="[^"]*'"$ASSET_NAME"'\"#url="'"$DOWNLOAD_URL"'"#g' "$APPCAST_PATH"

  if [[ -n "$RELEASE_NOTES_URL" ]]; then
    perl -0pi -e 's#sparkle:releaseNotesLink="[^"]*"#sparkle:releaseNotesLink="'"$RELEASE_NOTES_URL"'"#g' "$APPCAST_PATH"
  fi
else
  SKIP_APPCAST_COMMIT=1
  echo "Upload-only mode enabled; skipping appcast generation and commit."
fi

publish_release_if_possible() {
  if [[ "$UPLOAD_ONLY" -eq 1 ]]; then
    echo "Uploading asset to existing GitHub Release ${TAG}..."
    echo "Uploading ${ASSET_NAME} to GitHub Release ${TAG}..."
    upload_release_asset
    return 0
  fi

  local gh_bin
  if ! gh_bin="$(find_gh)"; then
    echo "Skipping GitHub Release publish: gh is not installed."
    return 0
  fi

  if ! "$gh_bin" auth status >/dev/null 2>&1; then
    echo "Skipping GitHub Release publish: gh is not authenticated."
    return 0
  fi

  local notes_args=()
  if [[ -n "$GITHUB_RELEASE_NOTES_PATH" ]]; then
    notes_args=(--notes-file "$GITHUB_RELEASE_NOTES_PATH")
  else
    notes_args=(--notes "$RELEASE_TITLE")
  fi

  if "$gh_bin" release view "$TAG" --repo "${REPO_OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
    echo "Uploading asset to existing GitHub Release ${TAG}..."
  else
    echo "Creating GitHub Release ${TAG}..."
    if [[ "$CHANNEL" == "beta" ]]; then
      "$gh_bin" release create "$TAG" --repo "${REPO_OWNER}/${REPO_NAME}" --title "$RELEASE_TITLE" "${notes_args[@]}" --prerelease
    else
      "$gh_bin" release create "$TAG" --repo "${REPO_OWNER}/${REPO_NAME}" --title "$RELEASE_TITLE" "${notes_args[@]}"
    fi
  fi

  echo "Uploading ${ASSET_NAME} to GitHub Release ${TAG}..."
  upload_release_asset
}

publish_release_if_possible

publish_appcast_commit_if_possible() {
  if [[ "$SKIP_APPCAST_COMMIT" -eq 1 ]]; then
    echo "Skipping appcast git commit/push by request."
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "Skipping appcast git commit/push: git is not installed."
    return 0
  fi

  if ! git -C "$WORKING_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Skipping appcast git commit/push: working directory is not a git repository."
    return 0
  fi

  local files_to_add=("$APPCAST_PATH")
  if [[ -n "$RELEASE_NOTES_PATH" && -n "$RELEASE_NOTES_URL" ]]; then
    files_to_add+=("$APPCAST_DIR/release-notes/${VERSION}.html")
  fi

  git -C "$WORKING_DIR" add -- "${files_to_add[@]}"

  if git -C "$WORKING_DIR" diff --cached --quiet; then
    echo "No appcast documentation changes to commit."
    return 0
  fi

  local current_branch
  current_branch="$(git -C "$WORKING_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
    echo "Skipping appcast git push: repository is not on a branch."
    return 0
  fi

  local channel_prefix=""
  if [[ "$CHANNEL" == "beta" ]]; then
    channel_prefix="beta "
  fi
  local commit_message="chore(shiphook): update ${channel_prefix}appcast for ${APP_NAME} ${VERSION} [shiphook skip]"
  git -C "$WORKING_DIR" commit -m "$commit_message"
  git -C "$WORKING_DIR" push origin "$current_branch"
}

publish_appcast_commit_if_possible

if [[ "$UPLOAD_ONLY" -eq 0 ]]; then
  echo "Updated appcast: $APPCAST_PATH"
fi
echo "Archive: $ARCHIVE_PATH"
echo "Release asset URL: $DOWNLOAD_URL"
echo "Release channel: $CHANNEL"
if [[ -n "$RELEASE_NOTES_URL" ]]; then
  echo "Release notes URL: $RELEASE_NOTES_URL"
fi
