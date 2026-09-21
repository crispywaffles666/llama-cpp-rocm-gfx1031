#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s <sha256:digest> <version> <output>\n' "$0" >&2
    exit 2
fi

digest="$1"
version="$2"
output="$3"

[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    printf 'Invalid image digest: %s\n' "${digest}" >&2
    exit 1
}
[[ "${version}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf 'Invalid release version: %s\n' "${version}" >&2
    exit 1
}

image="ghcr.io/crispywaffles666/llama-cpp-rocm-gfx1031@${digest}"
mkdir -p "$(dirname "${output}")"
sed \
    -e "s|@@IMAGE_REF@@|${image}|g" \
    -e "s|@@RELEASE_VERSION@@|${version}|g" \
    bin/llama-rocm.in > "${output}"
chmod 0755 "${output}"
