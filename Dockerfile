# Dockerfile for filed - a concurrent file-based job queue
# https://git.sr.ht/~marcc/filed

FROM golang:1.24-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git sqlite-dev gcc musl-dev

# Clone and build filed
WORKDIR /src
ENV GOBIN=/usr/local/bin
COPY fix-mtime.patch /tmp/fix-mtime.patch
RUN git clone https://git.sr.ht/~marcc/filed . && \
    git checkout d2f777f1 && \
    git apply /tmp/fix-mtime.patch && \
    go install && \
    go install cmd/filed-launch.go

# Runtime image
FROM ghcr.io/diagraphics/s6-overlay-dist:latest AS s6-overlay
FROM alpine:3.19

ENV PATH="/usr/local/bin:${PATH}"

# Install runtime dependencies
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk add --no-cache \
        dufs \
        fuse3 \
        sqlite-libs \
        ca-certificates && \
    ln -s /usr/bin/fusermount3 /usr/bin/fusermount

# Copy the binary from builder
COPY --from=s6-overlay / /
COPY --from=builder /usr/local/bin /usr/local/bin
COPY ./rootfs/ /

# Create mount point directory
RUN mkdir -p /var/filed

# Enable FUSE for non-root (though we run privileged)
RUN echo "user_allow_other" >> /etc/fuse.conf

ENTRYPOINT ["/init"]
