# Coco 一体镜像：Flutter Web 静态站 + FastAPI 用户 API
#
# 构建 / 运行（无需 compose）：
#   docker build -t coco:latest .
#   docker run --rm -p 8000:8000 --env-file docker.env \
#     --add-host=host.docker.internal:host-gateway coco:latest
# 同源部署时 Web 使用空 COCO_API_BASE_URL，请求走当前域名的 /v1、/health

# ---------- 阶段 1：安装 Flutter SDK（与本地 3.44.x 对齐）----------
FROM debian:bookworm-slim AS flutter_sdk

ARG FLUTTER_VERSION=3.44.8
ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_HOME=/opt/flutter \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH \
    PUB_CACHE=/opt/pub-cache

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
  && rm -rf /var/lib/apt/lists/* \
  && git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
  && flutter config --no-analytics --enable-web \
  && flutter precache --web

# ---------- 阶段 2：构建 Flutter Web ----------
FROM flutter_sdk AS flutter_build

WORKDIR /app/frontend
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get

COPY frontend/ ./
# 空字符串 = 与 API 同源（推荐一体部署）；也可构建时传入公网 API 地址
ARG COCO_API_BASE_URL=
RUN flutter build web --release --pwa-strategy=none \
  --dart-define=COCO_API_BASE_URL=${COCO_API_BASE_URL}

# ---------- 阶段 3：Python 运行时 ----------
FROM python:3.12-slim-bookworm AS runtime

COPY --from=ghcr.io/astral-sh/uv:0.8.4 /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    # 一体镜像默认托管 Web 产物
    COCO_WEB_STATIC_DIR=/app/web

WORKDIR /app/backend

# 先同步依赖，利用层缓存
COPY backend/pyproject.toml backend/uv.lock backend/README.md ./
COPY backend/src ./src
RUN uv sync --frozen --no-dev

COPY backend/alembic.ini ./
COPY backend/alembic ./alembic
COPY scripts/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

COPY --from=flutter_build /app/frontend/build/web /app/web

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"

ENTRYPOINT ["/app/docker-entrypoint.sh"]
