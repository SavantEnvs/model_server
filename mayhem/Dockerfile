# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form, PREFERRED) — builds ON TOP of the org C/C++ base
# image (ghcr.io/savantenvs/base). The base already provides debian + clang/llvm +
# libFuzzer/afl++ + the identities + the build-contract ENV, so this only adds the
# per-commit build (built on top of the prebuilt base, rather than building the toolchain in-image).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

# The org base, pinned to a fixed DATE-tagged base (YYYYMMDD; shared by all integrations
# minted against it). Use the current dated tag; pin by digest in production: ...base@sha256:<digest>.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an
# empty value breaks clang ("must be a non-negative decimal integer") both here and for
# any in-image rebuild. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default.
# To change it for a build (e.g. ASan-only, or add MSan): --build-arg SANITIZER_FLAGS="...".
# Declare it WITHOUT a default (no '='): an undefaulted ARG lets the base ENV flow through to
# build.sh when not passed, and an explicit --build-arg overrides it. (An empty default — `=` —
# would instead shadow the base ENV and silently wipe the sanitizers.)
ARG SANITIZER_FLAGS
# Coverage (optional, off by default): instrument the TEST build to measure how much of the project
# the suite exercises — --build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping".
# Empty by default (no effect on the normal oracle build); build.sh appends it to the test build only.
ARG COVERAGE_FLAGS=
# Build parallelism (optional). build.sh falls back to nproc when unset: --build-arg MAYHEM_JOBS=8
ARG MAYHEM_JOBS=

# Extra apt packages: libabsl-dev (absl::Status in src/tokenize), libssl-dev (MD5 in src/filesystem/filesystem.hpp, used by schema.cpp) and
# ocl-icd-libopencl1 (libopenvino_genai.so links libOpenCL.so.1), googletest/googlemock, to build upstream's own unit tests (src/test/*) as the oracle.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends libgtest-dev libgmock-dev libssl-dev ocl-icd-libopencl1 libabsl-dev \
 && rm -rf /var/lib/apt/lists/*

# Header-only dependencies, pinned to the exact archives + sha256 upstream's Bazel WORKSPACE uses
# (rapidjson, spdlog, fmt, stb, dr_libs, minitrace: only its header, which src/profiler.hpp includes; MTR_ENABLED
# stays undefined, as upstream builds it, so the profiling macros are no-ops). Read-only sources under /opt/toolchains/deps (SPEC 6.2 item 19).
RUN set -eux; fetch() { \
      d="/opt/toolchains/deps/$1"; mkdir -p "$d/src"; \
      curl -fsSL -o /tmp/dep.tgz "$2"; echo "$3  /tmp/dep.tgz" | sha256sum -c -; \
      tar -xzf /tmp/dep.tgz --strip-components=1 -C "$d/src"; rm -f /tmp/dep.tgz; chmod -R a+rX "$d"; }; \
    fetch rapidjson-973dc9c0 https://github.com/Tencent/rapidjson/archive/973dc9c06dcd3d035ebd039cfb9ea457721ec213.tar.gz d0c9e52823d493206eb721d38cb3a669ca0212360862bd15a3c2f7d35ea7c6f7; \
    fetch spdlog-1.15.3 https://github.com/gabime/spdlog/archive/refs/tags/v1.15.3.tar.gz 15a04e69c222eb6c01094b5c7ff8a249b36bb22788d72519646fb85feb267e67; \
    fetch fmt-11.2.0 https://github.com/fmtlib/fmt/archive/refs/tags/11.2.0.tar.gz bc23066d87ab3168f27cef3e97d545fa63314f5c79df5ea444d41d56f962c6af; \
    fetch stb-5c205738 https://github.com/nothings/stb/archive/5c205738c191bcb0abc65c4febfa9bd25ff35234.tar.gz cfeab9f800961882d6d22ddf36e965523b33002f4f937de08321304c9ba72af3; \
    fetch minitrace-020f42b1 https://github.com/hrydgard/minitrace/archive/020f42b189e8d6ad50e4d8f45d69edee0a6b3f23.tar.gz 314bcab4dc069c61f2eb813c9bd649efb2bd1fd75f91205a269a4c5abcd3d66b; \
    fetch dr_libs-47a4f08e https://github.com/mackron/dr_libs/archive/47a4f08e777faddf59a8955c4ea84f69f41020d5.tar.gz 9f451ba81a65ffa06c14113b13cf257ac70a9193a37782f9a934e5240c371772; \
    # MediaPipe at upstream's WORKSPACE commit: only the header-only status/error ports that
    # src/tokenize/tokenize_parser.hpp includes (mediapipe/framework/port/canonical_errors.h).
    d=/opt/toolchains/deps/mediapipe-2bce9dd1; mkdir -p "$d/src"; \
    curl -fsSL -o /tmp/mp.tgz https://codeload.github.com/google-ai-edge/mediapipe/tar.gz/2bce9dd15fa45f267c9e5f77086997c984a9f107; \
    echo "c8b4a4a69994146854cd4cd6a8ab4d2fca144c07ba92287efcee1549a7b81870  /tmp/mp.tgz" | sha256sum -c -; \
    tar -xzf /tmp/mp.tgz --strip-components=1 -C "$d/src" --wildcards '*/mediapipe/framework/port/*' '*/mediapipe/framework/deps/*' '*/LICENSE'; \
    rm -f /tmp/mp.tgz; chmod -R a+rX "$d"

# OpenVINO GenAI runtime (DLDT_PACKAGE_URL_UBUNTU24 in versions.mk). Upstream ships it only as a
# prebuilt package of shared libraries, so it cannot live under /opt/toolchains/deps (no .so there);
# it goes where upstream's own build expects it, /opt/intel/openvino. It stays uninstrumented.
ARG OV_URL=https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.5.0.0rc2/openvino_genai_ubuntu24_2026.5.0.0rc2_x86_64.tar.gz
ARG OV_SHA256=d12fd86f49e8966663f50cc9a316a51127c7ce21f4330d9dc73a412f75f5eca9
RUN set -eux; mkdir -p /opt/intel/openvino; curl -fsSL -o /tmp/ov.tgz "$OV_URL"; \
    echo "$OV_SHA256  /tmp/ov.tgz" | sha256sum -c -; \
    tar -xzf /tmp/ov.tgz --strip-components=1 -C /opt/intel/openvino \
        --exclude='*/python' --exclude='*/samples' --exclude='*/docs'; rm -f /tmp/ov.tgz; \
    chmod -R a+rX /opt/intel/openvino
# Upstream's tests open their fixtures under /ovms/src/test/... (upstream's build container root);
# point that at the in-image source tree.
RUN ln -s /mayhem /ovms
ENV LD_LIBRARY_PATH=/opt/intel/openvino/runtime/lib/intel64:/opt/intel/openvino/runtime/3rdparty/tbb/lib
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem as `mayhem`; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Anything a Dockerfile step materializes into the tree (downloaded fixtures, generated headers,
# vendored deps) MUST be committed or (re)created by build.sh: rlenv's patch grader runs
# `git clean -ffdX` before every graded build, so a gitignored, untracked file is gone by then and
# every honest patch scores zero (SPEC §6.2 item 16; verify-repo.sh checks it).
#
# OPTIONAL compile-cache pre-fill (SPEC §6.2 item 18). Bases minted with /opt/mayhem/ccache/prefill
# run the build under rlenv's pinned ccache, so the patch grader's first (otherwise cold) rebuild is
# warm — this is what keeps large C/C++ targets inside the build time limit. Older bases fall back to
# the plain build; a missing or stale pre-fill only costs a cold cache. Never enable ccache in
# build.sh or via ENV/PATH, and keep the compiler resolving by name (CC=clang) or nothing is cached.
RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

# Run the project's functional tests at build time IF the repo ships them (mayhem/test.sh is
# optional — omit it only when the repo has no tests meaningful for RL). A failing suite fails the
# image build, so the commit image is guaranteed to build AND pass its own tests.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
