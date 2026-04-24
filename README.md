# WARP 代理 Docker 镜像

该镜像会在容器内自动通过 `wgcf` 注册 Cloudflare WARP，并启动 `wireproxy` 对外提供：

- HTTP 代理（默认 `:8080`）
- SOCKS5 代理（默认 `:1080`）

其他应用通过这两个代理端口转发的流量，会走 WARP 网络出口。

## GitHub Actions 自动发布到 GHCR

工作流文件：`.github/workflows/docker-publish.yml`

触发条件：

- 推送到 `main`
- 推送匹配 `v*` 的 tag
- 手动触发 `workflow_dispatch`

发布标签示例：

- `ghcr.io/clockclock1/warp-proxy-docker:latest`（默认分支）
- `ghcr.io/clockclock1/warp-proxy-docker:<tag>`
- `ghcr.io/clockclock1/warp-proxy-docker:sha-xxxx`

## 本地构建

```bash
docker build -t warp-proxy:local .
```

## 运行容器

```bash
docker run -d --name warp-proxy \
  -p 8080:8080 \
  -p 1080:1080 \
  -e WARP_LICENSE_KEY= \
  -v $(pwd)/data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```

首次启动会自动生成并持久化：

- `/var/lib/warp/wgcf-account.toml`
- `/var/lib/warp/wgcf-profile.conf`

## Docker Compose

可直接使用项目内的 `docker-compose.yml`，默认镜像已经是：
`ghcr.io/clockclock1/warp-proxy-docker:latest`

## 环境变量

- `WARP_LICENSE_KEY`：可选，WARP+ 许可证
- `ENABLE_HTTP_PROXY`：`true` 或 `false`
- `ENABLE_SOCKS5_PROXY`：`true` 或 `false`
- `HTTP_BIND_ADDR`：默认 `0.0.0.0`
- `SOCKS5_BIND_ADDR`：默认 `0.0.0.0`
- `HTTP_PROXY_PORT`：默认 `8080`
- `SOCKS5_PROXY_PORT`：默认 `1080`
- `HTTP_USERNAME` / `HTTP_PASSWORD`：可选，HTTP 代理认证
- `SOCKS5_USERNAME` / `SOCKS5_PASSWORD`：可选，SOCKS5 代理认证
- `FORCE_REGENERATE_PROFILE`：设为 `true` 时强制重建 `wgcf-profile.conf`
- `WGCF_RETRIES`：`wgcf` 网络相关操作重试次数，默认 `5`
- `WGCF_RETRY_DELAY`：每次重试间隔秒数，默认 `5`

## 代理快速测试

HTTP：

```bash
curl -x http://127.0.0.1:8080 https://www.cloudflare.com/cdn-cgi/trace
```

SOCKS5：

```bash
curl --socks5-hostname 127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

## 常见问题

如果日志出现 `open wgcf-account.toml: permission denied`，通常是挂载目录权限不足。  
当前镜像已内置自动修复权限逻辑（启动时先修正目录权限，再以 `warp` 用户运行）。  
请更新镜像后重建容器：

```bash
docker pull ghcr.io/clockclock1/warp-proxy-docker:latest
docker rm -f warp-proxy
docker run -d --name warp-proxy \
  -p 8080:8080 \
  -p 1080:1080 \
  -e WARP_LICENSE_KEY= \
  -e WGCF_RETRIES=10 \
  -e WGCF_RETRY_DELAY=8 \
  -v $(pwd)/data:/var/lib/warp \
  ghcr.io/clockclock1/warp-proxy-docker:latest
```
