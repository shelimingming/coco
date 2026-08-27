#!/usr/bin/env bash
# Coco Web 本地启动：用户 API + Chrome 上的 Flutter Web。
#
# 用法：
#   ./scripts/dev_web.sh                  # 默认：本地后端 + Chrome
#   ./scripts/dev_web.sh --app-only       # 只起 Web（后端已在别处运行）
#   ./scripts/dev_web.sh --backend-only   # 只起用户 API
#   ./scripts/dev_web.sh --reuse-backend  # 端口上已有健康服务时复用
#   ./scripts/dev_web.sh --api-base URL   # 指定 API 根地址
#   ./scripts/dev_web.sh --release        # release 模式
#   ./scripts/dev_web.sh --rebuild-web    # 强制重新 flutter build web（8000 邀请链接用）

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
FRONTEND_DIR="${ROOT_DIR}/frontend"
RUNTIME_DIR="${ROOT_DIR}/.dev"
BACKEND_LOG="${RUNTIME_DIR}/backend.log"
BACKEND_PID_FILE="${RUNTIME_DIR}/backend.pid"

API_BASE=""
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
FLUTTER_MODE="debug"
RUN_BACKEND=1
RUN_APP=1
REUSE_BACKEND=0
KEEP_BACKEND=0
REBUILD_WEB=0

BACKEND_STARTED_BY_US=0
BACKEND_PID=""

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""
fi

info() { printf '%s\n' "${C_INFO}▸${C_RESET} $*"; }
ok() { printf '%s\n' "${C_OK}✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_WARN}!${C_RESET} $*" >&2; }
dim() { printf '%s\n' "${C_DIM}  $*${C_RESET}"; }

die() {
  printf '%s\n' "${C_ERR}✗ $1${C_RESET}" >&2
  if [[ $# -gt 1 ]]; then
    printf '%s\n' "  ${2}" >&2
  fi
  exit 1
}

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api-base) API_BASE="${2:?--api-base 需要一个 URL}"; shift 2 ;;
      --port) BACKEND_PORT="${2:?--port 需要一个端口}"; shift 2 ;;
      --release) FLUTTER_MODE="release"; shift ;;
      --backend-only) RUN_APP=0; shift ;;
      --app-only) RUN_BACKEND=0; shift ;;
      --reuse-backend) REUSE_BACKEND=1; shift ;;
      --rebuild-web) REBUILD_WEB=1; shift ;;
      --keep-backend) KEEP_BACKEND=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1" "用 --help 查看用法。" ;;
    esac
  done
}

env_value() {
  local key="$1" default="$2" file="${BACKEND_DIR}/.env" line
  if [[ -f "${file}" ]]; then
    line="$(grep -E "^${key}=" "${file}" | tail -n 1 || true)"
    if [[ -n "${line}" ]]; then
      printf '%s' "${line#${key}=}"
      return 0
    fi
  fi
  printf '%s' "${default}"
}

ensure_env_file() {
  if [[ ! -f "${BACKEND_DIR}/.env" ]]; then
    [[ -f "${BACKEND_DIR}/.env.example" ]] || die "缺少 backend/.env.example。" "先从仓库拉取完整 backend。"
    cp "${BACKEND_DIR}/.env.example" "${BACKEND_DIR}/.env"
    warn "已从 .env.example 生成 backend/.env，请按需修改密钥后再用于生产。"
  fi
}

check_database() {
  local url host port
  url="$(env_value COCO_DATABASE_URL 'postgresql+asyncpg://coco:coco@127.0.0.1:5432/coco')"
  host="$(printf '%s' "${url}" | sed -E 's|.*@([^:/?]+).*|\1|')"
  port="$(printf '%s' "${url}" | sed -E 's|.*@[^:/?]+:([0-9]+).*|\1|')"
  [[ "${port}" =~ ^[0-9]+$ ]] || port="5432"

  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -h "${host}" -p "${port}" >/dev/null 2>&1 \
      || die "PostgreSQL (${host}:${port}) 连不上。" "启动数据库后重试，例如：brew services start postgresql@16"
  elif ! nc -z "${host}" "${port}" >/dev/null 2>&1; then
    die "PostgreSQL (${host}:${port}) 连不上。" "启动数据库后重试。"
  fi
  ok "数据库可连接（${host}:${port}）"
}

backend_health_ok() {
  curl -fsS --max-time 2 "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1
}

port_listener_pid() {
  local port="$1"
  # lsof 无监听时退出码为 1；pipefail 下不能让整段脚本被 set -e 直接杀掉
  lsof -nP -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

stop_port_listener() {
  local port="$1" label="$2" pid
  pid="$(port_listener_pid "${port}")"
  [[ -n "${pid}" ]] || return 0
  info "结束占用 ${port} 端口的${label} (pid ${pid})"
  kill "${pid}" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "${pid}" 2>/dev/null || return 0
    sleep 0.3
  done
  kill -9 "${pid}" 2>/dev/null || true
  sleep 0.5
}

start_detached() {
  local cwd="$1" log_file="$2" pid_file="$3"
  shift 3
  local detach=()
  mkdir -p "$(dirname "${log_file}")" "$(dirname "${pid_file}")"
  if command -v setsid >/dev/null 2>&1; then
    detach=(setsid)
  elif command -v perl >/dev/null 2>&1; then
    detach=(perl -e 'use POSIX; POSIX::setsid(); exec @ARGV or die $!;' --)
  fi
  (
    cd "${cwd}"
    "${detach[@]}" "$@" >>"${log_file}" 2>&1 &
    printf '%s' "$!" >"${pid_file}"
  )
}

ensure_web_build() {
  # 邀请短链 /i/{code} 302 到 8000/index.html，本地必须把 Flutter Web 构建产物挂到 API 同端口
  local need_build=0
  if [[ ! -f "${FRONTEND_DIR}/build/web/index.html" ]]; then
    need_build=1
  elif (( REBUILD_WEB )); then
    need_build=1
  fi
  if (( need_build )); then
    info "构建 Flutter Web（邀请链接 / 8000/index.html 走 build 产物，非 Chrome 热重载）"
    (cd "${FRONTEND_DIR}" && flutter build web --dart-define=COCO_API_BASE_URL="${API_BASE}") \
      || die "flutter build web 失败。" "检查 Flutter 环境或网络。"
  fi
  export COCO_WEB_STATIC_DIR="${FRONTEND_DIR}/build/web"
}

start_backend() {
  ensure_env_file
  check_database
  ensure_web_build

  info "同步后端依赖（uv sync）"
  (cd "${BACKEND_DIR}" && uv sync --quiet) || die "uv sync 失败。" "手动执行：cd backend && uv sync"

  # 与 dev_ios.sh 对齐：Web 启动也要先把表结构升到当前代码，否则登录/调度会 500
  info "执行数据库迁移（alembic upgrade head）"
  (cd "${BACKEND_DIR}" && uv run alembic upgrade head) \
    || die "数据库迁移失败。" "确认 backend/.env 中的 COCO_DATABASE_URL 指向可写的 coco 库。"

  if (( REUSE_BACKEND )) && [[ -n "$(port_listener_pid "${BACKEND_PORT}")" ]]; then
    if backend_health_ok; then
      ok "后端已在 http://127.0.0.1:${BACKEND_PORT} 运行，按 --reuse-backend 复用"
      return 0
    fi
  fi

  stop_port_listener "${BACKEND_PORT}" "用户 API"
  mkdir -p "${RUNTIME_DIR}"
  : >"${BACKEND_LOG}"

  info "启动用户 API → http://${BACKEND_HOST}:${BACKEND_PORT}"
  # Web 与本机 Chrome 走 loopback；CORS 开发可用 *（见 backend/.env）
  start_detached "${BACKEND_DIR}" "${BACKEND_LOG}" "${BACKEND_PID_FILE}" \
    uv run uvicorn coco.main:app --host "${BACKEND_HOST}" --port "${BACKEND_PORT}" --reload

  BACKEND_PID="$(cat "${BACKEND_PID_FILE}")"
  BACKEND_STARTED_BY_US=1

  for _ in {1..40}; do
    if backend_health_ok; then
      ok "后端就绪（pid ${BACKEND_PID}）"
      return 0
    fi
    sleep 0.5
  done
  die "后端 20 秒内没有通过 /health。" "查看日志：${BACKEND_LOG}"
}

cleanup() {
  if (( BACKEND_STARTED_BY_US )) && (( ! KEEP_BACKEND )) && [[ -n "${BACKEND_PID}" ]]; then
    info "停止本次拉起的后端 (pid ${BACKEND_PID})"
    kill "${BACKEND_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

resolve_api_base() {
  if [[ -n "${API_BASE}" ]]; then
    return 0
  fi
  API_BASE="http://127.0.0.1:${BACKEND_PORT}"
}

run_web_app() {
  info "拉取 Flutter 依赖（flutter pub get）"
  (cd "${FRONTEND_DIR}" && flutter pub get) || die "flutter pub get 失败。" "检查网络或 pubspec.yaml。"

  ok "在 Chrome 上运行 Web（${FLUTTER_MODE}，API=${API_BASE}）"
  dim "麦克风需 localhost/HTTPS；开发验证码见 backend/.env 的 COCO_DEV_SMS_CODE（默认 246810）。"
  dim "邀请链接走 http://127.0.0.1:${BACKEND_PORT}/i/…（build/web 静态包；改 UI 后执行 ./scripts/dev_web.sh --rebuild-web --backend-only 或 flutter build web）"
  dim "双端同屏演示：在地址栏改开 /presentation.html（长辈 / 子女左右对照）。"
  dim "按 q 退出，r 热重载。"
  cd "${FRONTEND_DIR}"
  flutter run \
    -d chrome \
    "--${FLUTTER_MODE}" \
    --dart-define=COCO_API_BASE_URL="${API_BASE}"
}

main() {
  parse_args "$@"
  mkdir -p "${RUNTIME_DIR}"
  resolve_api_base

  if (( RUN_BACKEND )); then
    start_backend
  elif ! backend_health_ok; then
    warn "未检测到 http://127.0.0.1:${BACKEND_PORT}/health；若 API 在别处，请用 --api-base。"
  fi

  if (( RUN_APP )); then
    run_web_app
  else
    ok "仅后端模式：API=${API_BASE}"
    dim "日志：${BACKEND_LOG}"
    if (( BACKEND_STARTED_BY_US )); then
      KEEP_BACKEND=1
      wait "${BACKEND_PID}" || true
    fi
  fi
}

main "$@"
