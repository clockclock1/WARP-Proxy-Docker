# WARP Proxy Docker

基于 Cloudflare WARP + `wireproxy` 的代理容器镜像。  
容器启动后自动注册/生成 WARP 配置，并对外提供：

- HTTP 代理（默认 `8080`）
- SOCKS5 代理（默认 `1080`）

镜像地址：
`ghcr.io/clockclock1/warp-proxy-docker:latest`

## 功能特性

- 自动初始化 WARP 账户与配置（首次启动）
- 支持 HTTP / SOCKS5 双代理
- 支持端口、认证、重试参数配置
- 支持 Docker 与 Docker Compose 部署
- 配置持久化到挂载目录

## 快速开始（Docker）

```bash
mkdir -p ./warp-data

docker run -d --name warp-proxy \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 1080:1080 \
  -v $(pwd)/warp-data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```

查看运行日志：

```bash
docker logs -f warp-proxy
```

## 使用 Docker Compose

```yaml
services:
  warp-proxy:
    image: ghcr.io/clockclock1/warp-proxy-docker:latest
    container_name: warp-proxy
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "1080:1080"
    volumes:
      - ./warp-data:/var/lib/warp
```

启动：

```bash
docker compose up -d
```

## 代理使用方式

- HTTP：`http://<服务器IP>:8080`
- SOCKS5：`socks5://<服务器IP>:1080`

测试命令：

```bash
curl -x http://127.0.0.1:8080 https://www.cloudflare.com/cdn-cgi/trace
curl --socks5-hostname 127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

## 配置项（环境变量）

- `WARP_LICENSE_KEY`：可选，设置后尝试启用 WARP+
- `ENABLE_HTTP_PROXY`：`true/false`，默认 `true`
- `ENABLE_SOCKS5_PROXY`：`true/false`，默认 `true`
- `HTTP_PROXY_PORT`：默认 `8080`
- `SOCKS5_PROXY_PORT`：默认 `1080`
- `HTTP_USERNAME` / `HTTP_PASSWORD`：HTTP 代理认证
- `SOCKS5_USERNAME` / `SOCKS5_PASSWORD`：SOCKS5 代理认证
- `WGCF_RETRIES`：`wgcf` 重试次数，默认 `0`（无限重试）
- `WGCF_RETRY_DELAY`：重试间隔秒数，默认 `5`

带参数启动示例：

```bash
docker run -d --name warp-proxy \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 1080:1080 \
  -e ENABLE_HTTP_PROXY=true \
  -e ENABLE_SOCKS5_PROXY=true \
  -e WGCF_RETRIES=0 \
  -e WGCF_RETRY_DELAY=8 \
  -v $(pwd)/warp-data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```

## 更新镜像

```bash
docker pull ghcr.io/clockclock1/warp-proxy-docker:latest
docker rm -f warp-proxy
docker run -d --name warp-proxy \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 1080:1080 \
  -v $(pwd)/warp-data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```

## 常见问题

1. 出现 `permission denied`  
请检查挂载目录权限，或改用 Docker volume 挂载。

2. 出现 `TLS handshake timeout`  
通常是服务器到 `api.cloudflareclient.com` 的网络连通性问题，可先在宿主机测试：

```bash
curl -4 -m 20 -sv https://api.cloudflareclient.com/v0a1922/reg -o /dev/null
```
