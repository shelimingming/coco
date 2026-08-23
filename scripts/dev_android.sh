#!/usr/bin/env bash
# Coco 一键本地启动：用户 API + 运营后台 + Android 模拟器 / USB 真机上的 Flutter App。
#
# 用法：
#   ./scripts/dev_android.sh                       # 默认：已连接 Android + 本地后端 + admin
#   ./scripts/dev_android.sh --usb                 # USB 真机：后端 0.0.0.0 + App 走局域网 IP
#   ./scripts/dev_android.sh --lan                 # 真机/局域网：后端 0.0.0.0；App 用 Mac 局域网 IP
#   ./scripts/dev_android.sh --device <id|name>    # 指定设备（flutter devices 中的 id 或名称）
#   ./scripts/dev_android.sh --list                # 列出已连接 Android 设备后退出
#   ./scripts/dev_android.sh --backend-only        # 只起用户 API + admin（不启 App）
#   ./scripts/dev_android.sh --app-only            # 只起 App（后端已在别处运行）
#   ./scripts/dev_android.sh --no-admin            # 不起运营后台
#   ./scripts/dev_android.sh --reuse-backend       # 端口上已有健康服务时复用，不重启
#
# 说明：国内真机不依赖 GMS；开发明文 HTTP 由 android/app/src/debug 开启。

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
ADMIN_DIR="${ROOT_DIR}/admin"
FRONTEND_DIR="${ROOT_DIR}/frontend"
RUNTIME_DIR="${ROOT_DIR}/.dev"
BACKEND_LOG="${RUNTIME_DIR}/backend.log"
BACKEND_PID_FILE="${RUNTIME_DIR}/backend.pid"
ADMIN_LOG="${RUNTIME_DIR}/admin.log"
ADMIN_PID_FILE="${RUNTIME_DIR}/admin.pid"

DEVICE_QUERY=""
API_BASE=""
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
ADMIN_PORT="8001"
FLUTTER_MODE="debug"
RUN_BACKEND=1
RUN_ADMIN=1
RUN_APP=1
REUSE_BACKEND=0
KEEP_BACKEND=0
USE_LAN=0
USE_USB=0
LIST_ONLY=0

BACKEND_STARTED_BY_US=0
BACKEND_PID=""
ADMIN_STARTED_BY_US=0
ADMIN_PID=""

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
      --device|-d)
        DEVICE_QUERY="${2:?--device 需要一个设备名称或 id}"
        shift 2
        ;;
      --api-base) API_BASE="${2:?--api-base 需要一个 URL}"; shift 2 ;;
      --port) BACKEND_PORT="${2:?--port 需要一个端口}"; shift 2 ;;
      --lan) USE_LAN=1; shift ;;
      --usb|--device-usb)
        USE_USB=1
        USE_LAN=1
        shift
        ;;
      --release) FLUTTER_MODE="release"; shift ;;
      --profile) FLUTTER_MODE="profile"; shift ;;
      --backend-only) RUN_APP=0; KEEP_BACKEND=1; shift ;;
      --app-only) RUN_BACKEND=0; RUN_ADMIN=0; shift ;;
      --no-admin) RUN_ADMIN=0; shift ;;
      --admin-port) ADMIN_PORT="${2:?--admin-port 需要一个端口}"; shift 2 ;;
      --reuse-backend) REUSE_BACKEND=1; shift ;;
      --keep-backend) KEEP_BACKEND=1; shift ;;
      --list) LIST_ONLY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1" "运行 ./scripts/dev_android.sh --help 查看用法。" ;;
    esac
  done

  if (( ! RUN_BACKEND )); then
    RUN_ADMIN=0
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1。" "$2"
}

preflight() {
  require_cmd curl "请检查 PATH。"
  if (( RUN_BACKEND )); then
    require_cmd uv "安装方式：brew install uv"
  fi
  if (( RUN_APP )) || (( LIST_ONLY )); then
    require_cmd flutter "安装 Flutter 并把 flutter/bin 加入 PATH。"
  fi
  mkdir -p "${RUNTIME_DIR}"
}

# ---------- 后端 / 运营后台（与 dev_ios.sh 对齐） ----------

env_value() {
  local key="$1" fallback="${2-}" file="${3:-${BACKEND_DIR}/.env}" line
  [[ -f "${file}" ]] || { printf '%s' "${fallback}"; return; }
  line="$(grep -E "^${key}=" "${file}" | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    printf '%s' "${fallback}"
  else
    printf '%s' "${line#*=}"
  fi
}

ensure_env_file() {
  if [[ ! -f "${BACKEND_DIR}/.env" ]]; then
    [[ -f "${BACKEND_DIR}/.env.example" ]] || die "缺少 backend/.env 与 backend/.env.example。" "无法确定数据库与密钥配置。"
    cp "${BACKEND_DIR}/.env.example" "${BACKEND_DIR}/.env"
    ok "已从 .env.example 生成 backend/.env（本地开发默认值）"
  fi
}

ensure_admin_env_file() {
  if [[ ! -f "${ADMIN_DIR}/.env" ]]; then
    [[ -f "${ADMIN_DIR}/.env.example" ]] || die "缺少 admin/.env 与 admin/.env.example。" "无法确定管理后台账号配置。"
    cp "${ADMIN_DIR}/.env.example" "${ADMIN_DIR}/.env"
    ok "已从 .env.example 生成 admin/.env（本地开发默认值）"
  fi
}

run_detached() {
  local cwd="$1" log_file="$2" pid_file="$3"
  shift 3
  local -a detach=(nohup)
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

backend_listens_lan() {
  lsof -nP -iTCP:"${BACKEND_PORT}" -sTCP:LISTEN 2>/dev/null \
    | grep -qE "\*:${BACKEND_PORT}|0\.0\.0\.0:${BACKEND_PORT}|\[::\]:${BACKEND_PORT}"
}

admin_health_ok() {
  curl -fsS --max-time 2 "http://127.0.0.1:${ADMIN_PORT}/health" >/dev/null 2>&1
}

port_listener_pid() {
  local port="$1"
  lsof -nP -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null | head -n 1
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

start_backend() {
  ensure_env_file
  check_database

  if (( RUN_ADMIN )) && [[ "${BACKEND_PORT}" == "${ADMIN_PORT}" ]]; then
    die "用户 API 与运营后台不能共用端口 ${BACKEND_PORT}。" "换后端：--port 8002；或换后台：--admin-port 8002。"
  fi

  if (( REUSE_BACKEND )) && [[ -n "$(port_listener_pid "${BACKEND_PORT}")" ]]; then
    if backend_health_ok; then
      if (( USE_LAN )) && ! backend_listens_lan; then
        warn "已有后端只监听 127.0.0.1，真机连不上，将重启为 0.0.0.0"
      else
        ok "后端已在 http://127.0.0.1:${BACKEND_PORT} 运行，按 --reuse-backend 复用"
        return 0
      fi
    else
      die "端口 ${BACKEND_PORT} 被别的进程占用，且不是 Coco 后端。" "换端口：--port 8002，或先停掉占用进程。"
    fi
  fi

  if [[ -n "$(port_listener_pid "${BACKEND_PORT}")" ]]; then
    if backend_health_ok; then
      info "检测到已有后端，将停掉并按当前代码重启"
    else
      warn "端口 ${BACKEND_PORT} 已被占用且健康检查失败，将尝试停掉后重启"
    fi
    stop_port_listener "${BACKEND_PORT}" "后端"
  fi

  info "同步后端依赖（uv sync）"
  (cd "${BACKEND_DIR}" && uv sync --quiet) || die "uv sync 失败。" "查看上面的输出，或手动执行 cd backend && uv sync"

  info "执行数据库迁移（alembic upgrade head）"
  (cd "${BACKEND_DIR}" && uv run alembic upgrade head) \
    || die "数据库迁移失败，代码未改动、数据也未变更。" "确认 backend/.env 中的 COCO_DATABASE_URL 指向可写的 coco 库。"

  local bind_host="127.0.0.1"
  (( USE_LAN )) && bind_host="0.0.0.0"

  info "启动后端 uvicorn（${bind_host}:${BACKEND_PORT}）"
  : >"${BACKEND_LOG}"
  run_detached "${BACKEND_DIR}" "${BACKEND_LOG}" "${BACKEND_PID_FILE}" \
    uv run uvicorn coco.main:app --host "${bind_host}" --port "${BACKEND_PORT}"
  BACKEND_PID="$(cat "${BACKEND_PID_FILE}")"
  BACKEND_STARTED_BY_US=1

  for _ in {1..60}; do
    if backend_health_ok; then
      ok "后端就绪：http://127.0.0.1:${BACKEND_PORT}/docs"
      dim "日志：${BACKEND_LOG}"
      return 0
    fi
    if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
      tail -n 20 "${BACKEND_LOG}" >&2 || true
      die "后端启动即退出，App 未启动、数据未受影响。" "完整日志见 ${BACKEND_LOG}"
    fi
    sleep 0.5
  done
  die "后端 30 秒内没有通过健康检查。" "查看 ${BACKEND_LOG} 后重试。"
}

start_admin() {
  ensure_admin_env_file

  if (( REUSE_BACKEND )) && [[ -n "$(port_listener_pid "${ADMIN_PORT}")" ]]; then
    if admin_health_ok; then
      ok "运营后台已在 http://127.0.0.1:${ADMIN_PORT}/admin 运行，按 --reuse-backend 复用"
      return 0
    fi
    die "端口 ${ADMIN_PORT} 被别的进程占用，且不是 Coco Admin。" "换端口：--admin-port 8002，或先停掉占用进程。"
  fi

  if [[ -n "$(port_listener_pid "${ADMIN_PORT}")" ]]; then
    if admin_health_ok; then
      info "检测到已有运营后台，将停掉并按当前代码重启"
    else
      warn "端口 ${ADMIN_PORT} 已被占用且健康检查失败，将尝试停掉后重启"
    fi
    stop_port_listener "${ADMIN_PORT}" "运营后台"
  fi

  info "同步运营后台依赖（uv sync）"
  (cd "${ADMIN_DIR}" && uv sync --quiet) || die "admin uv sync 失败。" "手动执行：cd admin && uv sync"

  local bind_host="127.0.0.1"
  (( USE_LAN )) && bind_host="0.0.0.0"

  info "启动运营后台 uvicorn（${bind_host}:${ADMIN_PORT}）"
  : >"${ADMIN_LOG}"
  run_detached "${ADMIN_DIR}" "${ADMIN_LOG}" "${ADMIN_PID_FILE}" \
    uv run uvicorn coco_admin.main:app --host "${bind_host}" --port "${ADMIN_PORT}"
  ADMIN_PID="$(cat "${ADMIN_PID_FILE}")"
  ADMIN_STARTED_BY_US=1

  for _ in {1..60}; do
    if admin_health_ok; then
      ok "运营后台就绪：http://127.0.0.1:${ADMIN_PORT}/admin"
      dim "日志：${ADMIN_LOG}"
      return 0
    fi
    if ! kill -0 "${ADMIN_PID}" 2>/dev/null; then
      tail -n 20 "${ADMIN_LOG}" >&2 || true
      die "运营后台启动即退出，数据未受影响。" "完整日志见 ${ADMIN_LOG}"
    fi
    sleep 0.5
  done
  die "运营后台 30 秒内没有通过健康检查。" "查看 ${ADMIN_LOG} 后重试。"
}

cleanup() {
  if (( ! KEEP_BACKEND )); then
    if (( ADMIN_STARTED_BY_US )) && [[ -n "${ADMIN_PID}" ]]; then
      if kill -0 "${ADMIN_PID}" 2>/dev/null; then
        info "关闭运营后台 (pid ${ADMIN_PID})"
        kill "${ADMIN_PID}" 2>/dev/null || true
      fi
      local admin_leftover
      admin_leftover="$(port_listener_pid "${ADMIN_PORT}")"
      [[ -n "${admin_leftover}" ]] && kill "${admin_leftover}" 2>/dev/null || true
      rm -f "${ADMIN_PID_FILE}"
    fi
    if (( BACKEND_STARTED_BY_US )) && [[ -n "${BACKEND_PID}" ]]; then
      if kill -0 "${BACKEND_PID}" 2>/dev/null; then
        info "关闭后端 (pid ${BACKEND_PID})"
        kill "${BACKEND_PID}" 2>/dev/null || true
        sleep 1
      fi
      local leftover
      leftover="$(port_listener_pid "${BACKEND_PORT}")"
      [[ -n "${leftover}" ]] && kill "${leftover}" 2>/dev/null || true
      rm -f "${BACKEND_PID_FILE}"
    fi
  fi
}

# ---------- Android 设备 ----------

# 输出已连接 Android：名称<TAB>设备 ID
list_android_devices() {
  local json
  json="$(cd "${FRONTEND_DIR}" && flutter devices --machine 2>/dev/null)" || true
  [[ -n "${json}" ]] || return 0
  python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in devices:
    platform = str(d.get("targetPlatform") or d.get("platformType") or "").lower()
    if "android" not in platform:
        continue
    name = d.get("name") or ""
    device_id = d.get("id") or ""
    if name and device_id:
        print(f"{name}\t{device_id}")
' <<<"${json}"
}

resolve_android_device() {
  local query="${1-}" devices name device_id
  devices="$(list_android_devices)"
  [[ -n "${devices}" ]] || die "没有检测到 Android 设备。" \
    "请开启 USB 调试并连接真机，或启动模拟器；再用 --list 确认。Android Studio → Device Manager 可创建 AVD。"

  if [[ -n "${query}" ]]; then
    while IFS=$'\t' read -r name device_id; do
      [[ -n "${device_id}" ]] || continue
      if [[ "${name}" == "${query}" || "${device_id}" == "${query}" ]]; then
        printf '%s\t%s\n' "${name}" "${device_id}"
        return 0
      fi
    done <<<"${devices}"
    die "没有名为「${query}」的 Android 设备。" "用 --list 查看；或省略 --device 自动选第一台。"
  fi

  IFS=$'\t' read -r name device_id <<<"$(printf '%s\n' "${devices}" | sed -n '1p')"
  [[ -n "${name}" && -n "${device_id}" ]] || die "解析 Android 设备失败。" "请重插数据线或重启模拟器后重试。"
  printf '%s\t%s\n' "${name}" "${device_id}"
}

lan_ip() {
  local ip iface
  for iface in en0 en1; do
    ip="$(ipconfig getifaddr "${iface}" 2>/dev/null || true)"
    [[ -n "${ip}" ]] && { printf '%s' "${ip}"; return 0; }
  done
  return 1
}

resolve_api_base() {
  if [[ -n "${API_BASE}" ]]; then
    return 0
  fi
  if (( USE_LAN )); then
    local ip
    ip="$(lan_ip)" || die "拿不到局域网 IP。" "手动指定：--api-base http://<你的Mac IP>:${BACKEND_PORT}"
    API_BASE="http://${ip}:${BACKEND_PORT}"
  else
    # 模拟器默认走 10.0.2.2 访问宿主机；真机请用 --lan / --usb
    API_BASE="http://10.0.2.2:${BACKEND_PORT}"
  fi
}

ensure_flutter_deps() {
  info "拉取 Flutter 依赖（flutter pub get）"
  (cd "${FRONTEND_DIR}" && flutter pub get) || die "flutter pub get 失败。" "检查网络或 pubspec.yaml。"
}

run_app() {
  local device_id="$1" name="$2"
  ensure_flutter_deps

  # 真机不能用 10.0.2.2；若用户没加 --lan 但选了真机，强制改局域网
  if [[ "${API_BASE}" == *"10.0.2.2"* ]] && [[ "${device_id}" != emulator-* ]]; then
    warn "当前目标像是真机，将改用局域网 API（等同 --lan）"
    USE_LAN=1
    API_BASE=""
    resolve_api_base
    if (( RUN_BACKEND )) && backend_health_ok && ! backend_listens_lan; then
      die "真机需要后端监听 0.0.0.0。" \
        "去掉 --app-only 让脚本重启后端，或手动：uvicorn --host 0.0.0.0 --port ${BACKEND_PORT}"
    fi
  fi

  ok "在 ${name} 上运行 App（${FLUTTER_MODE}，API=${API_BASE}）"
  dim "开发验证码见 backend/.env 的 COCO_DEV_SMS_CODE（默认 246810）。"
  dim "首次构建会下载 Gradle 依赖，耗时较久；按 q 退出，r 热重载。"
  cd "${FRONTEND_DIR}"
  flutter run \
    -d "${device_id}" \
    "--${FLUTTER_MODE}" \
    --dart-define=COCO_API_BASE_URL="${API_BASE}"
}

# ---------- 主流程 ----------

main() {
  parse_args "$@"
  preflight

  if (( LIST_ONLY )); then
    local devices name device_id
    info "已连接的 Android 设备："
    devices="$(list_android_devices)"
    if [[ -n "${devices}" ]]; then
      while IFS=$'\t' read -r name device_id; do
        printf '  %-28s %s\n' "${name}" "${device_id}"
      done <<<"${devices}"
    else
      dim "（无）请连接开启 USB 调试的真机，或启动 Android 模拟器"
    fi
    exit 0
  fi

  trap cleanup EXIT INT TERM

  if (( RUN_BACKEND )); then
    start_backend
    if (( RUN_ADMIN )); then
      start_admin
    fi
  else
    backend_health_ok || warn "后端 http://127.0.0.1:${BACKEND_PORT} 没有响应，App 登录会失败。"
    if (( USE_LAN )) && backend_health_ok && ! backend_listens_lan; then
      die "当前后端只监听 127.0.0.1，真机连不上。" \
        "去掉 --app-only 让脚本重启后端，或手动：uvicorn --host 0.0.0.0 --port ${BACKEND_PORT}"
    fi
  fi

  if (( ! RUN_APP )); then
    ok "服务已启动，脚本退出后仍保持运行。"
    dim "用户 API：http://127.0.0.1:${BACKEND_PORT}/docs  PID=$(cat "${BACKEND_PID_FILE}" 2>/dev/null || echo '?')"
    if (( RUN_ADMIN )) || admin_health_ok; then
      dim "运营后台：http://127.0.0.1:${ADMIN_PORT}/admin  PID=$(cat "${ADMIN_PID_FILE}" 2>/dev/null || echo '?')"
    fi
    dim "停止：kill \$(cat ${BACKEND_PID_FILE}) \$(cat ${ADMIN_PID_FILE} 2>/dev/null)"
    exit 0
  fi

  resolve_api_base

  local selected name device_id
  selected="$(resolve_android_device "${DEVICE_QUERY}")" || exit 1
  IFS=$'\t' read -r name device_id <<<"${selected}"
  ok "目标设备：${name}（${device_id}）"
  run_app "${device_id}" "${name}"
}

main "$@"
