#!/usr/bin/env bash
# Installs the anyport CLI for the deploy action and puts it on the job's PATH.
#
# Binaries come from the public anyport-labs/anyport-helm repo, whose CLI releases are tagged
# cli/vX.Y.Z beside the chart releases tagged vX.Y.Z; every archive is checked against the
# release's checksums.txt before it is unpacked.
set -euo pipefail

REPO="anyport-labs/anyport-helm"

fail() {
  echo "::error::$*"
  exit 1
}

case "${RUNNER_OS:-}" in
  Linux) os=linux ;;
  macOS) os=darwin ;;
  *) fail "the Anyport deploy action runs on Linux and macOS runners, not ${RUNNER_OS:-this one}" ;;
esac
case "${RUNNER_ARCH:-}" in
  X64) arch=amd64 ;;
  ARM64) arch=arm64 ;;
  *) fail "no anyport CLI build for runner architecture ${RUNNER_ARCH:-unknown}" ;;
esac

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Unauthenticated API calls share a 60-an-hour limit per runner IP. github.token is only sent to
# github.com itself: on GitHub Enterprise Server it is a credential for a different host.
api() {
  local auth=()
  if [ -n "${GITHUB_API_TOKEN:-}" ] && [ "${GITHUB_SERVER_URL:-}" = "https://github.com" ]; then
    auth=(-H "Authorization: Bearer ${GITHUB_API_TOKEN}")
  fi
  # The guarded expansion is for macOS's bash 3.2, where an empty array trips set -u.
  curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} "$1"
}

version="${ANYPORT_CLI_VERSION:-latest}"
if [ "$version" = "latest" ]; then
  # Not /releases/latest: in this repo that is usually a chart. Prereleases are left out, and
  # tags are ranked by version rather than list order.
  version=$(
    api "https://api.github.com/repos/${REPO}/releases?per_page=50" \
      | sed -n 's/.*"tag_name": *"cli\/\(v[0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' \
      | sort -V | tail -n 1
  ) || true
  [ -n "$version" ] || fail "could not find the latest anyport CLI release; set cli-version, e.g. v0.0.15"
fi

bare="${version#v}"
[[ "$bare" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
  || fail "cli-version must look like v0.0.15 or latest, got '${ANYPORT_CLI_VERSION}'"

bin_dir="${RUNNER_TEMP}/anyport-cli/${bare}/bin"
if [ ! -x "${bin_dir}/anyport" ]; then
  base="https://github.com/${REPO}/releases/download/cli/v${bare}"
  archive="anyport_${bare}_${os}_${arch}.tar.gz"
  work=$(mktemp -d "${RUNNER_TEMP}/anyport-cli.XXXXXX")
  trap 'rm -rf "$work"' EXIT

  echo "Downloading anyport ${bare} (${os}/${arch})"
  curl -fsSL --retry 3 -o "${work}/${archive}" "${base}/${archive}" \
    || fail "no anyport CLI ${bare} build for ${os}/${arch}: ${base}/${archive}"
  curl -fsSL --retry 3 -o "${work}/checksums.txt" "${base}/checksums.txt" \
    || fail "could not fetch checksums.txt for anyport CLI ${bare}"

  expected=$(awk -v f="$archive" '$2 == f {print $1}' "${work}/checksums.txt")
  [ -n "$expected" ] || fail "checksums.txt for anyport CLI ${bare} does not list ${archive}"
  actual=$(sha256 "${work}/${archive}")
  [ "$actual" = "$expected" ] || fail "checksum mismatch for ${archive}; refusing to install it"

  tar -xzf "${work}/${archive}" -C "$work" anyport
  mkdir -p "$bin_dir"
  install -m 0755 "${work}/anyport" "${bin_dir}/anyport"
fi

echo "$bin_dir" >> "$GITHUB_PATH"
echo "version=${bare}" >> "$GITHUB_OUTPUT"
"${bin_dir}/anyport" version
