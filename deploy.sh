#!/usr/bin/env bash
# Deploys one image to one Anyport app for the deploy action.
#
# Every input arrives as an environment variable rather than being interpolated into the
# workflow script, so no input value can inject shell.
set -euo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

bool() {
  case "$2" in
    true | false) ;;
    *) fail "$1 must be true or false, got '$2'" ;;
  esac
}

[ -n "${ANYPORT_TOKEN:-}" ] \
  || fail "token is empty: create one with \`anyport token create\` and pass it from a repository secret"
echo "::add-mask::${ANYPORT_TOKEN}"
# A session token belongs to a person, expires, and carries no organization.
[[ "$ANYPORT_TOKEN" == apt_* ]] \
  || fail "token must be an Anyport service token (apt_…); create one with \`anyport token create\`"

[ -n "${INPUT_PROJECT:-}" ] || fail "project is required"
[ -n "${INPUT_APP:-}" ] || fail "app is required"
[ -n "${INPUT_IMAGE:-}" ] || fail "image is required"
bool publish "${INPUT_PUBLISH:-true}"
bool wait "${INPUT_WAIT:-true}"

if [ -n "${INPUT_ENDPOINT:-}" ]; then
  export ANYPORT_ENDPOINT="$INPUT_ENDPOINT"
fi
# An empty config home, so a self-hosted runner's own login, organization or default project
# cannot leak into the deploy.
ANYPORT_CONFIG_HOME=$(mktemp -d "${RUNNER_TEMP:-/tmp}/anyport-config.XXXXXX")
export ANYPORT_CONFIG_HOME
trap 'rm -rf "$ANYPORT_CONFIG_HOME"' EXIT

scope=(--project "$INPUT_PROJECT")
if [ -n "${INPUT_CLUSTER:-}" ]; then
  scope+=(--cluster "$INPUT_CLUSTER")
fi

args=(app deploy "$INPUT_APP" --image "$INPUT_IMAGE" "${scope[@]}")
if [ "${INPUT_PUBLISH:-true}" = "false" ]; then
  args+=(--no-publish)
elif [ "${INPUT_WAIT:-true}" = "true" ]; then
  args+=(--wait --wait-timeout "${INPUT_WAIT_TIMEOUT:-5m}")
fi

anyport "${args[@]}"

# The URL is a convenience for `environment.url`; a deploy that succeeded never fails over it.
url=""
if [ "${INPUT_PUBLISH:-true}" = "true" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "::notice::jq is not installed, so the url output is empty"
  elif detail=$(anyport app get "$INPUT_APP" "${scope[@]}" --json 2>/dev/null); then
    url=$(jq -r '(.urls // [])[0] // ""' <<<"$detail")
  else
    echo "::warning::deployed, but could not read the app's URL"
  fi
fi
echo "url=${url}" >> "$GITHUB_OUTPUT"

{
  if [ "${INPUT_PUBLISH:-true}" = "true" ]; then
    echo "### Deployed \`${INPUT_APP}\` to Anyport"
  else
    echo "### Saved a draft of \`${INPUT_APP}\` on Anyport"
  fi
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Project | \`${INPUT_PROJECT}\` |"
  echo "| Image | \`${INPUT_IMAGE}\` |"
  if [ -n "$url" ]; then
    echo "| URL | ${url} |"
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
