# llama.cpp ROCm for gfx1031

A rootless Podman application container for running current llama.cpp builds on
AMD `gfx1031` GPUs, particularly the Radeon RX 6700/6750 XT. The host provides
the `amdgpu` kernel driver and GPU devices; the container provides TheRock ROCm
userspace and llama.cpp.

This project does **not** modify Bazzite, install ROCm on the host, use DKMS, or
require an OS image rebase.

## What is pinned

- Ubuntu 24.04 base image by OCI digest.
- TheRock ROCm 10.0.0 `gfx103X-all` archive by SHA-256.
- llama.cpp v0.4.1 commit `b29c606e28a01b1bc8c1351026a0fa6e616bf6c4`.
- HIP compilation target `gfx1031`; no GPU target override is used at runtime.

The release workflow publishes `linux/amd64` images to
`ghcr.io/crispywaffles666/llama-cpp-rocm-gfx1031`, attaches BuildKit SBOM and
provenance records, and signs the image digest using GitHub OIDC and Cosign.

## Host prerequisites

You need Podman, an AMDGPU kernel with KFD enabled, and permission to use the GPU
device nodes:

```bash
test -r /dev/kfd && test -w /dev/kfd
test -r /dev/dri/renderD128 && test -w /dev/dri/renderD128
```

On Fedora/Bazzite, insufficient access normally means the user is missing the
`render` or `video` supplementary group. Log out and back in after changing
group membership. No ROCm RPMs are required on the host.

## Install the launcher

Choose a release, download both the launcher and checksum file, verify them, and
install the launcher as your user:

```bash
version=v0.1.0
base="https://github.com/crispywaffles666/llama-cpp-rocm-gfx1031/releases/download/${version}"
curl -fLO "${base}/llama-rocm"
curl -fLO "${base}/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS
install -Dm755 llama-rocm "$HOME/.local/bin/llama-rocm"
```

Every released launcher contains the immutable digest of its matching image.
The source template uses the mutable `edge` tag only when run directly from a
checkout.

## Use it

```bash
llama-rocm rocminfo
llama-rocm version
llama-rocm cli -m /models/model.gguf -p 'Explain immutable Linux images.'
llama-rocm bench -m /models/model.gguf -ngl 20
llama-rocm server -m /models/model.gguf -ngl 20
```

Models placed in `$HOME/.local/share/llama/models` appear read-only at
`/models` inside the container. Override that location with
`LLAMA_MODELS_DIR`. Hugging Face downloads persist under
`${HF_HOME:-$HOME/.cache/huggingface}`.

The server is published on `127.0.0.1:8080`. Set `LLAMA_ROCM_PORT` to change the
host port, or explicitly set `LLAMA_ROCM_BIND_ADDRESS=0.0.0.0` to expose it to
the LAN. Authentication should be configured before exposing the server.

### Qwen3.8-27B Q8_0 starting profile

The official Q8_0 GGUF is 28,595,763,648 bytes, so it cannot fit completely in
a roughly 12 GiB GPU. Start with one slot, an 8K context, quantized KV cache, and
partial GPU offload:

```bash
llama-rocm server \
  -hf ggml-org/Qwen3.8-27B-GGUF:Q8_0 \
  -ngl 20 \
  -c 8192 \
  -fa on \
  -ctk q8_0 \
  -ctv q8_0 \
  -np 1
```

Increase `-ngl` gradually while watching VRAM usage. The model plus runtime
overhead also puts meaningful pressure on a 32 GiB host, so avoid vision
`mmproj`, MTP, large contexts, and multiple slots during the first test.

To download the file separately instead, place `Qwen3.8-27B-Q8_0.gguf` in the
host model directory and pass `-m /models/Qwen3.8-27B-Q8_0.gguf`.

## Troubleshooting

- Run `llama-rocm rocminfo`; it must report a `gfx1031` agent.
- Device permission errors should be fixed with `render`/`video` group access,
  not by running the container as root.
- The launcher disables SELinux container labeling for this rootless process so
  it can access GPU devices without relabeling them. It still drops all Linux
  capabilities and enables `no-new-privileges`.
- AMD's recommended unconfined seccomp setting is used for ROCm. Models are
  mounted read-only; only the Hugging Face cache is writable.
- `LLAMA_ROCM_IMAGE` can point to a locally built tag for testing. Released
  launchers should use their embedded digest during normal operation.

## Local development

The ROCm input is 2.48 GB compressed and approximately 9.1 GiB unpacked. Allow
substantial disk space for a first build:

```bash
podman build --format docker --file Containerfile --tag localhost/llama-rocm:gfx1031 .
LLAMA_ROCM_IMAGE=localhost/llama-rocm:gfx1031 ./bin/llama-rocm.in version
./scripts/test.sh
```

The runtime stage removes the compiler, headers, static libraries, unrelated
MIOpen data, and rocBLAS kernels for GPU targets other than `gfx1031`.

## Verify a release image

Use the digest in the release's `IMAGE.txt`:

```bash
cosign verify \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp='^https://github.com/crispywaffles666/llama-cpp-rocm-gfx1031/.github/workflows/publish.yml@refs/tags/v' \
  "$(cat IMAGE.txt)"
```

See [THIRD_PARTY.md](THIRD_PARTY.md) for upstream components and redistribution
notes.
