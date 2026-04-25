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

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       ca-certificates \
       curl \
       gawk \
       iproute2 \
       iptables \
       iputils-ping \
       procps \
       wireguard-tools \
       wireguard-go \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/warp/shims /etc/wireproxy /etc/wireguard /etc/warp /var/lib/warp

COPY --from=downloader /tmp/wgcf /usr/local/bin/wgcf
COPY --from=downloader /tmp/wireproxy /usr/local/bin/wireproxy
COPY docker/warp.sh /opt/warp/warp.sh
COPY docker/shims/systemctl /opt/warp/shims/systemctl
COPY docker/shims/journalctl /opt/warp/shims/journalctl
COPY docker/shims/systemd-detect-virt /opt/warp/shims/systemd-detect-virt
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/wgcf /usr/local/bin/wireproxy /opt/warp/warp.sh \
    /opt/warp/shims/systemctl /opt/warp/shims/journalctl /opt/warp/shims/systemd-detect-virt \
    /usr/local/bin/entrypoint.sh

ENV PATH="/opt/warp/shims:${PATH}" \
    STATE_DIR=/var/lib/warp \
    WIREPROXY_CONFIG=/etc/wireproxy/config.conf \
    WARP_MODE=d \
    WARP_SCRIPT_SOURCE=local \
    WARP_SCRIPT_LOCAL_PATH=/opt/warp/warp.sh \
    ENABLE_HTTP_PROXY=true \
    ENABLE_SOCKS5_PROXY=true \
    HTTP_BIND_ADDR=0.0.0.0 \
    SOCKS5_BIND_ADDR=0.0.0.0 \
    HTTP_PROXY_PORT=8080 \
    SOCKS5_PROXY_PORT=1080

VOLUME ["/var/lib/warp"]

EXPOSE 8080 1080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
