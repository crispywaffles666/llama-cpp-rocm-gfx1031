#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n bin/llama-rocm.in scripts/render-launcher.sh scripts/test.sh

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

digest="sha256:$(printf 'a%.0s' {1..64})"
scripts/render-launcher.sh "${digest}" v0.1.0 "${test_root}/llama-rocm"

grep -Fq "ghcr.io/crispywaffles666/llama-cpp-rocm-gfx1031@${digest}" "${test_root}/llama-rocm"
grep -Fq "RELEASE_VERSION='v0.1.0'" "${test_root}/llama-rocm"
if grep -Fq '@@IMAGE_REF@@' "${test_root}/llama-rocm"; then
    printf 'Unrendered image placeholder remains\n' >&2
    exit 1
fi

mkdir -p "${test_root}/models with spaces" "${test_root}/cache" "${test_root}/fake-bin"
cat > "${test_root}/fake-bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod 0755 "${test_root}/fake-bin/podman"

common_env=(
    HOME="${test_root}/home"
    PATH="${test_root}/fake-bin:${PATH}"
    LLAMA_ROCM_PODMAN="${test_root}/fake-bin/podman"
    LLAMA_MODELS_DIR="${test_root}/models with spaces"
    HF_HOME="${test_root}/cache"
    LLAMA_ROCM_SKIP_DEVICE_CHECK=1
)

env "${common_env[@]}" "${test_root}/llama-rocm" cli -m '/models/test.gguf' > "${test_root}/cli.args"
grep -Fxq -- '--pull=missing' "${test_root}/cli.args"
grep -Fxq -- "ghcr.io/crispywaffles666/llama-cpp-rocm-gfx1031@${digest}" "${test_root}/cli.args"
if grep -Fxq -- 'ghcr.io/crispywaffles666/llama-cpp-rocm-gfx1031:edge' "${test_root}/cli.args"; then
    printf 'Rendered launcher unexpectedly selected the mutable edge tag\n' >&2
    exit 1
fi
grep -Fxq -- '--device=/dev/kfd' "${test_root}/cli.args"
grep -Fxq -- '--device=/dev/dri' "${test_root}/cli.args"
grep -Fxq -- '--group-add=keep-groups' "${test_root}/cli.args"
grep -Fxq -- "${test_root}/models with spaces:/models:ro" "${test_root}/cli.args"
grep -Fxq -- '/opt/llama/bin/llama-cli' "${test_root}/cli.args"

env "${common_env[@]}" LLAMA_ROCM_PORT=9090 "${test_root}/llama-rocm" server -m /models/test.gguf > "${test_root}/server.args"
grep -Fxq -- '--publish' "${test_root}/server.args"
grep -Fxq -- '127.0.0.1:9090:8080' "${test_root}/server.args"
grep -Fxq -- '/opt/llama/bin/llama-server' "${test_root}/server.args"

env "${common_env[@]}" "${test_root}/llama-rocm" version > "${test_root}/version.args"
if grep -Fq -- '--device=/dev/kfd' "${test_root}/version.args"; then
    printf 'Version command unexpectedly requested GPU devices\n' >&2
    exit 1
fi

grep -Fq 'ROCM_PATH=/opt/rocm' Containerfile
grep -Fq 'CMAKE_HIP_ARCHITECTURES=gfx1031' Containerfile
grep -Fq 'GGML_HIP=ON' Containerfile
grep -Fq 'GGML_HIP_NO_VMM=ON' Containerfile
if rg -q 'HSA_OVERRIDE_GFX_VERSION' Containerfile bin README.md THIRD_PARTY.md 2>/dev/null; then
    printf 'HSA_OVERRIDE_GFX_VERSION must not be used\n' >&2
    exit 1
fi

printf 'All static and launcher tests passed.\n'
