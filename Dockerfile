# syntax=docker/dockerfile:1.7
FROM alpine:3.20 AS downloader

ARG TARGETARCH
ARG WGCF_VERSION=2.2.30
ARG WIREPROXY_VERSION=1.1.2

RUN apk add --no-cache ca-certificates curl tar

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) arch="amd64" ;; \
      arm64) arch="arm64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/wgcf "https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_${arch}"; \
    chmod +x /tmp/wgcf; \
    curl -fsSL -o /tmp/wireproxy.tar.gz "https://github.com/windtf/wireproxy/releases/download/v${WIREPROXY_VERSION}/wireproxy_linux_${arch}.tar.gz"; \
    tar -xzf /tmp/wireproxy.tar.gz -C /tmp wireproxy; \
    chmod +x /tmp/wireproxy

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata su-exec

RUN addgroup -S warp \
    && adduser -S -D -H -h /var/lib/warp -s /sbin/nologin -G warp warp \
    && mkdir -p /var/lib/warp /etc/wireproxy \
    && chown -R warp:warp /var/lib/warp /etc/wireproxy

COPY --from=downloader /tmp/wgcf /usr/local/bin/wgcf
COPY --from=downloader /tmp/wireproxy /usr/local/bin/wireproxy
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

ENV STATE_DIR=/var/lib/warp \
    WIREPROXY_CONFIG=/etc/wireproxy/config.conf \
    ENABLE_HTTP_PROXY=true \
    ENABLE_SOCKS5_PROXY=true \
    WGCF_RETRIES=0 \
    WGCF_RETRY_DELAY=5 \
    HTTP_BIND_ADDR=0.0.0.0 \
    SOCKS5_BIND_ADDR=0.0.0.0 \
    HTTP_PROXY_PORT=8080 \
    SOCKS5_PROXY_PORT=1080

VOLUME ["/var/lib/warp"]

EXPOSE 8080 1080

USER root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
