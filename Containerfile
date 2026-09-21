# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=docker.io/library/ubuntu@sha256:496754492fb28b4d3049432f2ca787449331e23fb14f0dd3fffea86bf5a93eb4

FROM ${BASE_IMAGE} AS build

ARG ROCM_VERSION=10.0.0
ARG ROCM_FAMILY=gfx103X-all
ARG ROCM_URL=https://stable.repo.amd.com/rocm/core/tarball/therock-dist-linux-gfx103X-all-10.0.0.tar.gz
ARG ROCM_SHA256=1913cf553193a5642bc0894807e68dd206724b377b779101add8e62844c2e20c
ARG LLAMA_CPP_COMMIT=b29c606e28a01b1bc8c1351026a0fa6e616bf6c4

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libcurl4-openssl-dev \
        libelf1 \
        libnuma1 \
        libssl-dev \
        libunwind8 \
        ninja-build \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --retry 3 --output /tmp/rocm.tar.gz "${ROCM_URL}" \
    && echo "${ROCM_SHA256}  /tmp/rocm.tar.gz" | sha256sum --check --strict \
    && mkdir -p "/opt/rocm-${ROCM_VERSION}" \
    && tar -xzf /tmp/rocm.tar.gz -C "/opt/rocm-${ROCM_VERSION}" \
    && rm /tmp/rocm.tar.gz \
    && ln -s "/opt/rocm-${ROCM_VERSION}" /opt/rocm \
    && test -x /opt/rocm/bin/hipcc \
    && test -x /opt/rocm/bin/rocminfo

ENV ROCM_PATH=/opt/rocm \
    PATH=/opt/rocm/bin:/opt/rocm/llvm/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/rocm/lib

WORKDIR /src/llama.cpp
RUN git init \
    && git remote add origin https://github.com/ggml-org/llama.cpp.git \
    && git fetch --depth=1 origin "${LLAMA_CPP_COMMIT}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${LLAMA_CPP_COMMIT}"

RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_HIP_COMPILER=/opt/rocm/llvm/bin/clang++ \
        -DCMAKE_HIP_ARCHITECTURES=gfx1031 \
        -DGPU_TARGETS=gfx1031 \
        -DGGML_HIP=ON \
        -DGGML_HIP_NO_VMM=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_NATIVE=OFF \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DLLAMA_BUILD_IS_DEV=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_APP=OFF \
        -DLLAMA_BUILD_SERVER=ON \
        -DLLAMA_BUILD_TOOLS=ON \
    && cmake --build build --parallel "$(nproc)" \
        --target llama-cli llama-server llama-bench

# Create the runtime payload in the build stage. Keep ROCm shared libraries and
# rocBLAS kernels, but omit its compiler, headers, static libraries, package
# metadata, and unrelated MIOpen model data.
RUN mkdir -p /opt/rocm-runtime/bin \
    && cp -a /opt/rocm/bin/rocminfo /opt/rocm-runtime/bin/ \
    && cp -a /opt/rocm/.info /opt/rocm/etc /opt/rocm/lib /opt/rocm/libexec /opt/rocm/share /opt/rocm-runtime/ \
    && rm -rf \
        /opt/rocm-runtime/lib/cmake \
        /opt/rocm-runtime/share/cmake \
        /opt/rocm-runtime/share/miopen \
    && find /opt/rocm-runtime/lib/llvm -mindepth 1 -maxdepth 1 ! -name lib -exec rm -rf '{}' + \
    && find /opt/rocm-runtime/lib/llvm/lib -mindepth 1 -maxdepth 1 \
        ! -name 'libLLVM.so*' ! -name 'libclang-cpp.so*' -exec rm -rf '{}' + \
    && find /opt/rocm-runtime/lib -type f -name '*.a' -delete \
    && find /opt/rocm-runtime/lib/rocblas/library -type f -name '*gfx*' ! -name '*gfx1031*' -delete \
    && test -f /opt/rocm-runtime/lib/libamdhip64.so \
    && test -d /opt/rocm-runtime/lib/rocblas/library

ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS runtime

ARG ROCM_VERSION=10.0.0
ARG ROCM_FAMILY=gfx103X-all
ARG LLAMA_CPP_COMMIT=b29c606e28a01b1bc8c1351026a0fa6e616bf6c4
ARG IMAGE_VERSION=dev
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="llama.cpp ROCm for gfx1031" \
      org.opencontainers.image.description="llama.cpp with TheRock ROCm userspace, compiled specifically for AMD gfx1031" \
      org.opencontainers.image.source="https://github.com/crispywaffles666/llama-cpp-rocm-gfx1031" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="MIT" \
      io.github.crispywaffles666.rocm.version="${ROCM_VERSION}" \
      io.github.crispywaffles666.rocm.family="${ROCM_FAMILY}" \
      io.github.crispywaffles666.llama-cpp.commit="${LLAMA_CPP_COMMIT}" \
      io.github.crispywaffles666.gpu.target="gfx1031"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        kmod \
        libcurl4t64 \
        libdrm-amdgpu1 \
        libdrm2 \
        libelf1t64 \
        libgomp1 \
        libncurses6 \
        libnuma1 \
        libssl3t64 \
        libunwind8 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 65532 llama \
    && useradd --uid 65532 --gid 65532 --create-home --shell /usr/sbin/nologin llama \
    && mkdir -p /models /cache/huggingface \
    && chown -R llama:llama /models /cache /home/llama

COPY --from=build /opt/rocm-runtime /opt/rocm-10.0.0
COPY --from=build /src/llama.cpp/build/bin /opt/llama/bin

ENV ROCM_PATH=/opt/rocm \
    PATH=/opt/llama/bin:/opt/rocm/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/llama/bin:/opt/rocm/lib:/opt/rocm/lib/llvm/lib \
    HF_HOME=/cache/huggingface \
    LLAMA_CACHE=/cache/huggingface/hub

RUN ln -s /opt/rocm-10.0.0 /opt/rocm \
    && test -x /opt/llama/bin/llama-cli \
    && test -x /opt/llama/bin/llama-server \
    && test -x /opt/llama/bin/llama-bench \
    && ! ldd /opt/llama/bin/llama-cli | grep -q 'not found' \
    && ! ldd /opt/llama/bin/llama-server | grep -q 'not found' \
    && ! ldd /opt/llama/bin/libggml-hip.so | grep -q 'not found' \
    && ! ldd /opt/rocm/bin/rocminfo | grep -q 'not found'

USER llama
WORKDIR /models
EXPOSE 8080
CMD ["/opt/llama/bin/llama-server", "--host", "0.0.0.0", "--port", "8080"]
