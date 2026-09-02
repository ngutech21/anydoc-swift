FROM swift:6.2.4-amazonlinux2@sha256:cf1e50d44fbb470cb8b7ab481a76b49b8a58fa4fdc1b6995a3582849453e64f9

ARG TARGETARCH
ARG RUSTUP_VERSION=1.28.2

RUN yum -y install \
    file-5.11-36.amzn2.0.1 \
    zip-3.0-11.amzn2.0.3 \
  && yum clean all \
  && rm -rf /var/cache/yum

RUN case "$TARGETARCH" in \
      amd64) \
        rust_target="x86_64-unknown-linux-gnu"; \
        rustup_sha256="20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c" \
        ;; \
      arm64) \
        rust_target="aarch64-unknown-linux-gnu"; \
        rustup_sha256="e3853c5a252fca15252d07cb23a1bdd9377a8c6f3efa01531109281ae47f841c" \
        ;; \
      *) \
        echo "unsupported Docker architecture: $TARGETARCH" >&2; \
        exit 1 \
        ;; \
    esac \
  && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/rustup-init \
    "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${rust_target}/rustup-init" \
  && echo "${rustup_sha256}  /tmp/rustup-init" | sha256sum --check --strict \
  && chmod +x /tmp/rustup-init \
  && /tmp/rustup-init -y --profile minimal --default-toolchain 1.94.1 \
    --component clippy --component rustfmt --component llvm-tools-preview \
  && rm /tmp/rustup-init

ENV PATH="/root/.cargo/bin:${PATH}"

RUN swift --version \
  && rustc --version \
  && cargo --version
