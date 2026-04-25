# WARP Proxy Docker

这个镜像在容器启动时会自动执行 `warp.sh`，等价于：

- 双栈全局：`bash <(curl -fsSL git.io/warp.sh) d`
- IPv4 全局：`bash <(curl -fsSL git.io/warp.sh) 4`
- IPv6 全局：`bash <(curl -fsSL git.io/warp.sh) 6`

WARP 启动后，容器会同时提供：

- HTTP 代理（默认 `8080`）
- SOCKS5 代理（默认 `1080`）

镜像地址：
`ghcr.io/clockclock1/warp-proxy-docker:latest`

## 快速部署

```bash
mkdir -p ./warp-data

docker run -d --name warp-proxy \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  -p 8080:8080 \
  -p 1080:1080 \
  -e WARP_MODE=d \
  -v $(pwd)/warp-data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```

查看日志：

```bash
docker logs -f warp-proxy
```

## Docker Compose

```yaml
services:
  warp-proxy:
    image: ghcr.io/clockclock1/warp-proxy-docker:latest
    container_name: warp-proxy
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      WARP_MODE: "d"
      ENABLE_HTTP_PROXY: "true"
      ENABLE_SOCKS5_PROXY: "true"
      HTTP_PROXY_PORT: "8080"
      SOCKS5_PROXY_PORT: "1080"
    volumes:
      - ./warp-data:/var/lib/warp
    ports:
      - "8080:8080"
      - "1080:1080"
```

启动：

```bash
docker compose up -d
```

## 使用代理

- HTTP：`http://<服务器IP>:8080`
- SOCKS5：`socks5://<服务器IP>:1080`

测试命令：

```bash
curl -x http://127.0.0.1:8080 https://www.cloudflare.com/cdn-cgi/trace
curl --socks5-hostname 127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

## 关键参数

- `WARP_MODE`：`d` / `4` / `6`（默认 `d`）
- `WARP_SCRIPT_SOURCE`：`local` 或 `remote`（默认 `local`）
- `ENABLE_HTTP_PROXY`：是否开启 HTTP 代理（默认 `true`）
- `ENABLE_SOCKS5_PROXY`：是否开启 SOCKS5 代理（默认 `true`）
- `HTTP_PROXY_PORT`：HTTP 端口（默认 `8080`）
- `SOCKS5_PROXY_PORT`：SOCKS5 端口（默认 `1080`）
- `HTTP_USERNAME` / `HTTP_PASSWORD`：HTTP 认证（可选）
- `SOCKS5_USERNAME` / `SOCKS5_PASSWORD`：SOCKS5 认证（可选）

## 更新镜像

```bash
docker pull ghcr.io/clockclock1/warp-proxy-docker:latest
docker rm -f warp-proxy
docker compose up -d
```
