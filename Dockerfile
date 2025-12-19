# Dockerfile for filed - a concurrent file-based job queue
# https://git.sr.ht/~marcc/filed
# Supports Alpine (default) and Debian via VARIANT build arg

ARG VARIANT=debian
ARG DUFS_VERSION=0.45.0

# =============================================================================
# Builder stages - compile filed
# =============================================================================
FROM golang:1.24-alpine AS builder-alpine
RUN apk add --no-cache git sqlite-dev gcc musl-dev

FROM golang:1.24-bookworm AS builder-debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libsqlite3-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

FROM builder-${VARIANT} AS builder
WORKDIR /src
ENV GOBIN=/usr/local/bin
COPY fix-mtime.patch /tmp/fix-mtime.patch
RUN git clone https://git.sr.ht/~marcc/filed . && \
    git checkout d2f777f1 && \
    git apply /tmp/fix-mtime.patch && \
    go install && \
    go install cmd/filed-launch.go

# =============================================================================
# Dufs builder stages - compile dufs
# =============================================================================
FROM rust:1-alpine AS dufs-builder-alpine
ARG DUFS_VERSION=0.45.0
RUN apk add --no-cache musl-dev
RUN cargo install dufs@${DUFS_VERSION} --root /usr/local

FROM rust:1-bookworm AS dufs-builder-debian
ARG DUFS_VERSION=0.45.0
RUN cargo install dufs@${DUFS_VERSION} --root /usr/local

FROM dufs-builder-${VARIANT} AS dufs-builder

# =============================================================================
# Runtime base stages
# =============================================================================
FROM alpine:3.19 AS runtime-alpine
RUN apk add --no-cache \
    fuse3 \
    sqlite-libs \
    ca-certificates && \
    ln -s /usr/bin/fusermount3 /usr/bin/fusermount

FROM debian:bookworm-slim AS runtime-debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    fuse3 \
    libsqlite3-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Final stage - assemble runtime image
# =============================================================================
FROM ghcr.io/diagraphics/s6-overlay-dist:latest AS s6-overlay

FROM runtime-${VARIANT} AS final
ENV PATH="/usr/local/bin:${PATH}"
COPY --from=s6-overlay / /
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=dufs-builder /usr/local/bin/dufs /usr/local/bin/dufs
COPY ./rootfs/ /
RUN mkdir -p /var/filed && \
    echo "user_allow_other" >> /etc/fuse.conf
ENTRYPOINT ["/init"]
