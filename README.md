# docker-zhian_edge_ai_sdk

指安人脸照片转特征值算法服务的 Docker 包装镜像。

## BE3V120 / ZF-BP3-X 适配结论

指安提供的 `BE3V120.tar` 不是普通源码包，而是一个 Docker/OCI 镜像归档；归档内镜像标签为：

```text
faceedge01/zhian_edge_ai_sdk:BE3V120
```

新镜像结构和旧版 `bp3V203` 不同：

- 新 API 文件：`/workspace/doorlock_api.py`
- 新启动脚本：`/workspace/run.sh`
- 新算法程序目录：`/home/XM650V200_AFDR_plus_genFeatByPic/`
- API 版本参数：`V1` / `V2`，其中 `V2` 是 vendor API 的默认值
- 数据目录：`/data1`，软链接到算法目录下的 `In`

因此不要再把旧项目里的 `doorapiserver.py` 复制到 `/workspace/apiservice/doorapiserver.py`。那会覆盖/绕开 BE3V120 的新 API 和新算法入口，导致 ZF-BP3-X 支持丢失。

本项目现在采用最小改动方式：保留 vendor 的 `doorlock_api.py`，只替换容器启动脚本并增加一个 `api_app.py` 兼容包装层，用于保留旧镜像的 `/` 健康响应。

保留/优化点：

- API 错误码：使用 BE3V120 自带的 `FAIL_CODE_MAP` 和日志解析。
- 临时文件清理：保留 BE3V120 自带的请求前/请求后清理逻辑，并补回旧镜像的 `/workspace/apiservice/auto-del-3-days-ago-image.sh` 自动清理脚本；默认清理 `/data1`、`/workspace/tmp`、`/workspace/apiservice/imagedata` 中超过 3 天的图片/特征/日志临时文件。
- 并发安全：`api_app.py` 只包装 vendor API，不覆盖算法入口；每个请求使用唯一临时图片/特征文件名，并禁用 vendor 的请求级全局清理，避免并发请求互删 `/data1` 文件。
- 子进程队列：默认 `FEATURE_PROCESS_CONCURRENCY=1`，用跨 gunicorn worker 的文件锁串行执行特征提取子进程；如现场压测确认算法二进制并发稳定，可显式调大。
- Docker 日志：`gunicorn` access/error log 输出到 stdout/stderr。
- 启动优化：不再每次容器启动时 `pip install`，直接使用镜像内已安装的 `gunicorn/gevent`。

## 本地构建

本仓库的 `Dockerfile` 默认从已经上传到 GHCR 的原版 BE3V120 base 镜像构建：

```text
ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120
```

确认 base 镜像可拉取：

```bash
docker pull ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120
```

构建优化镜像：

```bash
docker build \
  --platform linux/amd64 \
  -t ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120 \
  .
```

或者用 Compose：

```bash
IMAGE_NAME=ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120 docker compose build
```

如果要改用本地 `BE3V120.tar` 加载出的镜像做 base，可以显式覆盖：

```bash
docker load -i BE3V120.tar

docker build \
  --platform linux/amd64 \
  --build-arg BASE_IMAGE=faceedge01/zhian_edge_ai_sdk:BE3V120 \
  -t ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120 \
  .
```

## 并发和子进程队列

新版 vendor `doorlock_api.py` 的原始实现不适合直接开 4 个 gunicorn worker 并发处理同一批 `/data1` 文件：它会在请求开始时删除除当前图片外的图片/特征文件，并且输出特征文件名由图片名决定，多个 worker 同时处理同名图片时会互相覆盖。

本镜像在 `api_app.py` 中做最小包装：

1. 本地图片请求会先复制成每个请求唯一的临时文件名；远程下载也使用唯一文件名。
2. 请求完成后只删除本请求前缀的临时图片和特征文件，不再执行 vendor 的请求级全局清理。
3. `auto-del-3-days-ago-image.sh` 继续作为按时间的兜底清理。
4. 特征提取子进程默认通过跨 worker 文件锁排队执行。

相关环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `FEATURE_PROCESS_CONCURRENCY` | `1` | 同一容器内允许同时运行多少个特征提取子进程；`1` 表示排队串行，`2/4` 表示允许并发，`0`/`unlimited` 表示不加跨进程锁 |
| `FEATURE_PROCESS_LOCK_DIR` | `/workspace/tmp/feature-locks` | 子进程并发槽位锁文件目录 |

实测 vendor 算法二进制在“不同唯一输入文件名”下 4 个子进程并行可以成功生成特征，但 vendor Python API 自身通过 `threading.Lock()` 暗示单进程内是串行设计，而且该锁不跨 gunicorn worker。因此生产默认采用 `FEATURE_PROCESS_CONCURRENCY=1` 保守排队；如果现场要提高吞吐，建议先用真实流量压测后再调到 `2` 或 `4`。

## 自动清理脚本

镜像内包含兼容旧路径的清理脚本：

```text
/workspace/apiservice/auto-del-3-days-ago-image.sh
```

`run.sh` 会在启动 gunicorn 前拉起一个后台清理循环，默认立即执行一次，然后每 86400 秒执行一次。可用环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ENABLE_IMAGE_CLEANUP` | `1` | 设为 `0` 可禁用后台清理循环 |
| `IMAGE_RETENTION_DAYS` | `3` | 删除超过多少天的临时文件 |
| `IMAGE_CLEANUP_INTERVAL_SECONDS` | `86400` | 后台清理循环间隔 |
| `IMAGE_CLEANUP_PATHS` | `/data1 /workspace/tmp /workspace/apiservice/imagedata` | 要清理的目录列表 |
| `IMAGE_CLEANUP_EXCLUDE_NAMES` | `guo_fu_cheng.jpg li_ming.jpg liu_de_hua.jpg zhang_xue_you.jpg` | 保留 vendor 内置样例图，避免清理后 README 示例不可用 |

脚本只删除图片、`.bin` 特征、日志和临时文本类文件，不会删除目录内其它任意文件。

## 本地验证

启动：

```bash
docker run --rm -d \
  --platform linux/amd64 \
  --name zhian-be3v120 \
  -p 5000:8008 \
  ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120
```

健康检查：

```bash
curl http://127.0.0.1:5000/
```

使用镜像内置样例图验证特征提取：

```bash
curl 'http://127.0.0.1:5000/predict?image=data1/liu_de_hua.jpg&version=V2'
```

停止：

```bash
docker stop zhian-be3v120
```

> 如果 ZF-BP3-X 固件实际需要 203 平台特征，请把请求参数改为 `version=V1`；BE3V120 的 vendor API 默认是 `V2`。最终以指安给出的“模组固件 ↔ 特征版本”对应关系为准。

## 推送到 GitHub Container Registry（GHCR）

由于 BE3V120 没有发布到 Docker Hub，GitHub Actions 不能直接 `FROM faceedge01/zhian_edge_ai_sdk:BE3V120`。推荐先把 vendor base 镜像推送到 GHCR 的私有 package，再让 Actions 基于这个 base 构建优化镜像。

### 1. 登录 GHCR

需要 GitHub Personal Access Token，至少包含：

- `write:packages`
- `read:packages`
- 如果仓库/Package 是私有的，通常还需要 `repo`

```bash
export GHCR_USER='<your-github-username>'
export GHCR_TOKEN='<your-token>'
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
```

### 2. 推送 BE3V120 base 镜像

```bash
docker tag \
  faceedge01/zhian_edge_ai_sdk:BE3V120 \
  ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120

docker push ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120

# 同时推一个小写 tag，方便人工输入/检索
docker tag \
  faceedge01/zhian_edge_ai_sdk:BE3V120 \
  ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-be3v120
docker push ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-be3v120
```

如果这个 package 是私有的，需要在 GitHub Package 设置里把 `here-link/docker-zhian_edge_ai_sdk` 仓库加入访问权限，否则 Actions 的 `GITHUB_TOKEN` 拉不到 base 镜像。

### 3. 推送优化镜像

本地直接推送：

```bash
docker push ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120

docker tag \
  ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120 \
  ghcr.io/here-link/docker-zhian_edge_ai_sdk:latest

docker push ghcr.io/here-link/docker-zhian_edge_ai_sdk:latest
```

也可以在完成 `docker login ghcr.io` 后直接运行脚本完成“加载 vendor tar → 推送 base → 构建优化镜像 → 推送优化镜像”：

```bash
export GHCR_USER='<your-github-username>'
export GHCR_TOKEN='***'
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

./scripts/push-ghcr.sh
```

或者把本仓库推到 GitHub 后，由 `.github/workflows/docker-publish.yml` 自动构建并推送：

```text
ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120
ghcr.io/here-link/docker-zhian_edge_ai_sdk:latest
```

## 注意事项

- `BE3V120.tar` 是大文件且可能包含指安授权内容，不应提交到 Git；本仓库已在 `.gitignore` 和 `.dockerignore` 忽略 `*.tar`。
- GitHub Actions 依赖 `ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120`。如果只在本机有 `BE3V120.tar`，Actions 构建会失败。
- 当前镜像是 `linux/amd64`。在 Apple Silicon 本机运行时需要 Docker/QEMU 仿真，因此 compose 和示例命令都指定了 `linux/amd64`。
