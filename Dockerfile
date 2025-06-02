# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile with reliable cross-compilation support

# ==================== BACKEND BUILD STAGE ====================
FROM --platform=$BUILDPLATFORM golang:1.20-alpine AS backend

WORKDIR /backend
COPY . .

# Set Go proxy for faster downloads
RUN go env -w GOPROXY=https://goproxy.cn,direct

ARG TARGETARCH
ARG TARGETOS
ENV GOOS=$TARGETOS GOARCH=$TARGETARCH GO111MODULE=on CGO_ENABLED=1

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    g++ \
    make \
    linux-headers \
    wget \
    tar \
    xz

# Install ARM64 cross-compilation toolchain from reliable source
RUN if [ "$TARGETARCH" = "arm64" ]; then \
    echo "Installing ARM64 cross-compiler..." && \
    apk add --no-cache aarch64-linux-musl-gcc aarch64-linux-musl-g++ aarch64-linux-musl-binutils && \
    echo "Compiler installed successfully"; \
    fi

# Verify toolchain installation
RUN if [ "$TARGETARCH" = "arm64" ]; then \
    echo "Verifying compiler installation..." && \
    ls -la /usr/local/aarch64-linux-musl-cross/bin && \
    test -f /usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc && \
    echo "Compiler verification passed"; \
    fi

# Build backend with appropriate compiler
RUN if [ "$TARGETARCH" = "arm64" ]; then \
    echo "Building for ARM64..." && \
    CC=aarch64-linux-musl-gcc \
    CXX=aarch64-linux-musl-g++ \
    CGO_ENABLED=1 \
    GOOS=linux \
    GOARCH=arm64 \
    go build -o chat -a -ldflags="-extldflags=-static" .; \
    else \
    echo "Building for native architecture..." && \
    go install && \
    go build .; \
    fi

# ==================== FRONTEND BUILD STAGE ====================
FROM node:18 AS frontend

WORKDIR /app
COPY ./app .

RUN npm install -g pnpm && \
    pnpm install && \
    pnpm run build && \
    rm -rf node_modules src

# ==================== FINAL IMAGE ====================
FROM alpine

# Install runtime dependencies
RUN apk upgrade --no-cache && \
    apk add --no-cache wget ca-certificates tzdata && \
    update-ca-certificates 2>/dev/null || true

# Set timezone to Asia/Shanghai
RUN echo "Asia/Shanghai" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

WORKDIR /

# Copy built artifacts
COPY --from=backend /backend/chat /chat
COPY --from=backend /backend/config.example.yaml /config.example.yaml
COPY --from=backend /backend/utils/templates /utils/templates
COPY --from=backend /backend/addition/article/template.docx /addition/article/template.docx
COPY --from=frontend /app/dist /app/dist

# Create volume mount points
VOLUME ["/config", "/logs", "/storage"]

# Expose application port
EXPOSE 8094

# Set entrypoint
CMD ["./chat"]
