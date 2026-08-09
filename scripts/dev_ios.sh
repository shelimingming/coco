#!/usr/bin/env bash
# Coco 一键本地启动：后端 (FastAPI) + iOS 26 模拟器上的 Flutter App。
#
# 用法：
#   ./scripts/dev_ios.sh                       # 默认：iOS 26 模拟器 + 本地后端
#   ./scripts/dev_ios.sh --device "iPhone 17"  # 指定模拟器机型（名称或 UDID）
#   ./scripts/dev_ios.sh --ios 26              # 指定 iOS 大版本（默认 26）
#   ./scripts/dev_ios.sh --lan                 # 真机调试：后端监听 0.0.0.0，App 用局域网 IP
#   ./scripts/dev_ios.sh --backend-only        # 只起后端
#   ./scripts/dev_ios.sh --app-only            # 只起 App（后端已在别处运行）
#   ./scripts/dev_ios.sh --list                # 列出候选模拟器后退出

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
FRONTEND_DIR="${ROOT_DIR}/frontend"
RUNTIME_DIR="${ROOT_DIR}/.dev"
BACKEND_LOG="${RUNTIME_DIR}/backend.log"
BACKEND_PID_FILE="${RUNTIME_DIR}/backend.pid"

IOS_MAJOR="26"
DEVICE_QUERY=""
API_BASE=""
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
FLUTTER_MODE="debug"
RUN_BACKEND=1
RUN_APP=1
RESTART_BACKEND=0
KEEP_BACKEND=0
USE_LAN=0
LIST_ONLY=0

# 本次脚本是否亲自拉起了后端，决定退出时是否回收进程。
BACKEND_STARTED_BY_US=0
BACKEND_PID=""

# 机型优先级：iOS 26 上优先用 17 Pro，其次退到别的 iPhone。
PREFERRED_DEVICES=("iPhone 17 Pro" "iPhone 17" "iPhone 17 Pro Max" "iPhone Air" "iPhone 16 Pro")

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""
fi

info() { printf '%s\n' "${C_INFO}▸${C_RESET} $*"; }
ok() { printf '%s\n' "${C_OK}✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_WARN}!${C_RESET} $*" >&2; }
dim() { printf '%s\n' "${C_DIM}  $*${C_RESET}"; }

# 错误文案统一说清楚：发生了什么、现在能做什么。
die() {
  printf '%s\n' "${C_ERR}✗ $1${C_RESET}" >&2
  if [[ $# -gt 1 ]]; then
    printf '%s\n' "  ${2}" >&2
  fi
  exit 1
}

# 帮助文本直接复用文件头的注释块，避免两处维护。
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device|-d) DEVICE_QUERY="${2:?--device 需要一个机型名称或 UDID}"; shift 2 ;;
      --ios) IOS_MAJOR="${2:?--ios 需要一个大版本号，如 26}"; shift 2 ;;
      --api-base) API_BASE="${2:?--api-base 需要一个 URL}"; shift 2 ;;
      --port) BACKEND_PORT="${2:?--port 需要一个端口}"; shift 2 ;;
      --lan) USE_LAN=1; shift ;;
      --release) FLUTTER_MODE="release"; shift ;;
      --profile) FLUTTER_MODE="profile"; shift ;;
      --backend-only) RUN_APP=0; KEEP_BACKEND=1; shift ;;
      --app-only) RUN_BACKEND=0; shift ;;
      --restart-backend) RESTART_BACKEND=1; shift ;;
      --keep-backend) KEEP_BACKEND=1; shift ;;
      --list) LIST_ONLY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1" "运行 ./scripts/dev_ios.sh --help 查看用法。" ;;
    esac
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1。" "$2"
}

preflight() {
  [[ "$(uname -s)" == "Darwin" ]] || die "本脚本只能在 macOS 上运行。" "iOS 构建依赖 Xcode。"
  require_cmd xcrun "请安装 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app"
  require_cmd curl "macOS 自带 curl，请检查 PATH。"
  if (( RUN_BACKEND )); then
    require_cmd uv "安装方式：brew install uv"
  fi
  if (( RUN_APP )); then
    require_cmd flutter "安装 Flutter 并把 flutter/bin 加入 PATH。"
    command -v pod >/dev/null 2>&1 || warn "未找到 CocoaPods，首次 iOS 构建可能失败。安装：sudo gem install cocoapods"
  fi
  mkdir -p "${RUNTIME_DIR}"
}

# ---------- 后端 ----------

# 从 .env 里取键值，缺省时回落到给定默认值。
env_value() {
  local key="$1" fallback="${2-}" file="${BACKEND_DIR}/.env" line
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

check_database() {
  local url host port
  url="$(env_value COCO_DATABASE_URL 'postgresql+asyncpg://coco:coco@127.0.0.1:5432/coco')"
  # 从 URL 中抠出 host:port，只做连通性预检，凭据由后端自己校验。
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
  lsof -nP -tiTCP:"${BACKEND_PORT}" -sTCP:LISTEN 2>/dev/null | head -n 1
}

stop_existing_backend() {
  local pid
  pid="$(port_listener_pid)"
  [[ -n "${pid}" ]] || return 0
  info "结束占用 ${BACKEND_PORT} 端口的进程 (pid ${pid})"
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

  if (( RESTART_BACKEND )); then
    stop_existing_backend
  elif [[ -n "$(port_listener_pid)" ]]; then
    if backend_health_ok; then
      ok "后端已在 http://127.0.0.1:${BACKEND_PORT} 运行，复用它（要重启加 --restart-backend）"
      return 0
    fi
    die "端口 ${BACKEND_PORT} 被别的进程占用，且不是 Coco 后端。" "换端口：--port 8001，或先停掉占用进程。"
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
  # 单独开一个会话（setsid 或 perl 兜底），否则脚本所在进程组被整体收掉时后端会跟着死，
  # --backend-only / --keep-backend 的“留着继续跑”就不成立。
  local detach=(nohup)
  if command -v setsid >/dev/null 2>&1; then
    detach=(setsid)
  elif command -v perl >/dev/null 2>&1; then
    detach=(perl -e 'use POSIX; POSIX::setsid(); exec @ARGV or die $!;' --)
  fi
  (
    cd "${BACKEND_DIR}"
    "${detach[@]}" uv run uvicorn coco.main:app --host "${bind_host}" --port "${BACKEND_PORT}" \
      >>"${BACKEND_LOG}" 2>&1 &
    printf '%s' "$!" >"${BACKEND_PID_FILE}"
  )
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

cleanup() {
  if (( BACKEND_STARTED_BY_US )) && (( ! KEEP_BACKEND )) && [[ -n "${BACKEND_PID}" ]]; then
    if kill -0 "${BACKEND_PID}" 2>/dev/null; then
      info "关闭后端 (pid ${BACKEND_PID})"
      kill "${BACKEND_PID}" 2>/dev/null || true
      sleep 1
    fi
    # uv run 是父进程，uvicorn 是它的子进程；父进程退出后补一刀，避免端口被占住。
    local leftover
    leftover="$(port_listener_pid)"
    [[ -n "${leftover}" ]] && kill "${leftover}" 2>/dev/null || true
    rm -f "${BACKEND_PID_FILE}"
  fi
}

# ---------- 模拟器 ----------

# 输出该 iOS 大版本下所有可用设备：名称<TAB>UDID<TAB>状态
list_simulators() {
  xcrun simctl list devices available | awk -v major="${IOS_MAJOR}" '
    /^-- / {
      in_section = 0
      if (match($0, /iOS [0-9]+/)) {
        v = substr($0, RSTART + 4, RLENGTH - 4)
        in_section = (v == major)
      }
      next
    }
    in_section && match($0, /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) {
      udid = substr($0, RSTART, RLENGTH)
      name = substr($0, 1, RSTART - 2)
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      rest = substr($0, RSTART + RLENGTH)
      state = "Unknown"
      if (match(rest, /\((Booted|Shutdown|Booting|Shutting Down)\)/)) {
        state = substr(rest, RSTART + 1, RLENGTH - 2)
      }
      printf "%s\t%s\t%s\n", name, udid, state
    }
  '
}

# 选设备的顺序：用户指定 > 已启动的 > 优先机型 > 第一台 iPhone。
resolve_simulator() {
  local devices name udid state
  devices="$(list_simulators)"
  [[ -n "${devices}" ]] || die "没有找到 iOS ${IOS_MAJOR} 的模拟器。" "在 Xcode → Settings → Components 里安装 iOS ${IOS_MAJOR} 运行时，或用 --ios 指定已装版本。"

  if [[ -n "${DEVICE_QUERY}" ]]; then
    while IFS=$'\t' read -r name udid state; do
      if [[ "${name}" == "${DEVICE_QUERY}" || "${udid}" == "${DEVICE_QUERY}" ]]; then
        printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
        return 0
      fi
    done <<<"${devices}"
    die "iOS ${IOS_MAJOR} 下没有名为「${DEVICE_QUERY}」的模拟器。" "用 --list 查看可选机型。"
  fi

  while IFS=$'\t' read -r name udid state; do
    if [[ "${state}" == "Booted" && "${name}" == iPhone* ]]; then
      printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
      return 0
    fi
  done <<<"${devices}"

  local preferred
  for preferred in "${PREFERRED_DEVICES[@]}"; do
    while IFS=$'\t' read -r name udid state; do
      if [[ "${name}" == "${preferred}" ]]; then
        printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
        return 0
      fi
    done <<<"${devices}"
  done

  while IFS=$'\t' read -r name udid state; do
    if [[ "${name}" == iPhone* ]]; then
      printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
      return 0
    fi
  done <<<"${devices}"

  die "iOS ${IOS_MAJOR} 下没有可用的 iPhone 模拟器。" "用 --list 查看，或在 Xcode 里新建一台设备。"
}

boot_simulator() {
  local udid="$1" name="$2" state="$3"
  if [[ "${state}" != "Booted" ]]; then
    info "启动模拟器 ${name}"
    xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  fi
  open -a Simulator --args -CurrentDeviceUDID "${udid}" >/dev/null 2>&1 || open -a Simulator || true

  for _ in {1..60}; do
    if xcrun simctl list devices | grep -q "${udid}.*Booted"; then
      ok "模拟器就绪：${name}（iOS ${IOS_MAJOR}）"
      return 0
    fi
    sleep 1
  done
  die "模拟器 ${name} 60 秒内没有启动完成。" "手动打开 Simulator 后重试，或换一台机型：--device \"iPhone 17\""
}

# ---------- 前端 ----------

lan_ip() {
  local ip
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
    # 模拟器与 Mac 共享 loopback，127.0.0.1 可直连。
    API_BASE="http://127.0.0.1:${BACKEND_PORT}"
  fi
}

run_app() {
  local udid="$1" name="$2"
  info "拉取 Flutter 依赖（flutter pub get）"
  (cd "${FRONTEND_DIR}" && flutter pub get) || die "flutter pub get 失败。" "检查网络或 pubspec.yaml。"

  ok "在 ${name} 上运行 App（${FLUTTER_MODE}，API=${API_BASE}）"
  dim "首次构建会执行 pod install，耗时较久；按 q 退出，r 热重载。"
  cd "${FRONTEND_DIR}"
  flutter run \
    -d "${udid}" \
    "--${FLUTTER_MODE}" \
    --dart-define=COCO_API_BASE_URL="${API_BASE}"
}

# ---------- 主流程 ----------

main() {
  parse_args "$@"
  preflight

  if (( LIST_ONLY )); then
    info "iOS ${IOS_MAJOR} 可用模拟器："
    list_simulators | while IFS=$'\t' read -r name udid state; do
      printf '  %-22s %s  (%s)\n' "${name}" "${udid}" "${state}"
    done
    exit 0
  fi

  trap cleanup EXIT INT TERM

  if (( RUN_BACKEND )); then
    start_backend
  else
    backend_health_ok || warn "后端 http://127.0.0.1:${BACKEND_PORT} 没有响应，App 登录会失败。"
  fi

  if (( ! RUN_APP )); then
    ok "后端已启动，脚本退出后仍保持运行。停止：kill \$(cat ${BACKEND_PID_FILE})"
    exit 0
  fi

  # 先取回结果再解析：resolve_simulator 里的 die 只能结束子 shell，这里要显式判空。
  local selected name udid state
  selected="$(resolve_simulator)" || exit 1
  [[ -n "${selected}" ]] || exit 1
  IFS=$'\t' read -r name udid state <<<"${selected}"

  boot_simulator "${udid}" "${name}" "${state}"
  resolve_api_base
  run_app "${udid}" "${name}"
}

main "$@"
