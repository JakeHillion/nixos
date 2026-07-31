#!/usr/bin/env bash
# Refresh pkgs/unifi-os-server-image/source.json to the current UniFi OS Server
# release. The download URL carries a per-release token so it cannot be
# templated from the version alone; Renovate bumps the version and then runs
# this task to resolve the matching URL and checksum from the firmware API.
set -euo pipefail

api='https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~unifi-os-server&filter=eq~~platform~~linux-x64&filter=eq~~channel~~release'

json=$(curl -fsS "$api")

version=$(jq -er '._embedded.firmware[0].version | ltrimstr("v")' <<<"$json")
url=$(jq -er '._embedded.firmware[0]._links.data.href' <<<"$json")
sha256=$(jq -er '._embedded.firmware[0].sha256_checksum' <<<"$json")

jq -n \
  --arg version "$version" \
  --arg url "$url" \
  --arg sha256 "$sha256" \
  '{version: $version, url: $url, sha256: $sha256}' \
  >pkgs/unifi-os-server-image/source.json
