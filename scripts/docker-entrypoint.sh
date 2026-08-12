#!/usr/bin/env bash
# Docker 容器入口：迁移后启动 uvicorn（托管 API + Flutter Web）
set -Eeuo pipefail

cd /app/backend

echo "▸ alembic upgrade head"
uv run alembic upgrade head

echo "▸ uvicorn coco.main:app (0.0.0.0:8000)"
exec uv run uvicorn coco.main:app --host 0.0.0.0 --port 8000
