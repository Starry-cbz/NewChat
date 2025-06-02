# 第一阶段：后端构建（使用官方 Go 镜像）
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS backend
WORKDIR /backend
COPY . .

# 设置 Go 环境变量
ARG TARGETARCH
ARG TARGETOS
ENV GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=1

# 安装交叉编译工具链（仅 ARM64 需要）
RUN apk add --no-cache gcc musl-dev linux-headers wget tar && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        wget -q -O /tmp/cross.tgz https://musl.cc/aarch64-linux-musl-cross.tgz && \
        tar -xf /tmp/cross.tgz -C /usr/local && \
        rm /tmp/cross.tgz; \
    fi

# 构建后端
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        CC=/usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc \
        go build -o chat -ldflags="-extldflags=-static" .; \
    else \
        go build -o chat .; \
    fi

# 第二阶段：前端构建
FROM node:18 AS frontend
WORKDIR /app
COPY ./app .
RUN npm install -g pnpm && \
    pnpm install && \
    pnpm run build && \
    rm -rf node_modules src

# 第三阶段：最终镜像
FROM alpine
RUN apk upgrade --no-cache && \
    apk add --no-cache ca-certificates tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

WORKDIR /
COPY --from=backend /backend/chat /chat
COPY --from=backend /backend/config.example.yaml /config.example.yaml
COPY --from=backend /backend/utils/templates /utils/templates
COPY --from=backend /backend/addition/article/template.docx /addition/article/template.docx
COPY --from=frontend /app/dist /app/dist

VOLUME ["/config", "/logs", "/storage"]
EXPOSE 8094
CMD ["./chat"]
