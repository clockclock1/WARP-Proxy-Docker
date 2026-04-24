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

- `ghcr.io/<owner>/<repo>:latest`（默认分支）
- `ghcr.io/<owner>/<repo>:<tag>`
- `ghcr.io/<owner>/<repo>:sha-xxxx`

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
  ghcr.io/<owner>/<repo>:latest
```

首次启动会自动生成并持久化：

- `/var/lib/warp/wgcf-account.toml`
- `/var/lib/warp/wgcf-profile.conf`

## Docker Compose

可直接使用项目内的 `docker-compose.yml`，把镜像地址改成你的 GHCR 地址即可。

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

## 代理快速测试

HTTP：

```bash
curl -x http://127.0.0.1:8080 https://www.cloudflare.com/cdn-cgi/trace
```

SOCKS5：

```bash
curl --socks5-hostname 127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```
