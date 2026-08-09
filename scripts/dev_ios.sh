#!/usr/bin/env bash
# Coco 一键本地启动：用户 API + 运营后台 + iOS 26 模拟器上的 Flutter App。
#
# 用法：
#   ./scripts/dev_ios.sh                       # 默认：iOS 26 模拟器 + 本地后端 + admin
#   ./scripts/dev_ios.sh --dual                # 同时起两台模拟器，方便父母/子女双角色联调
#   ./scripts/dev_ios.sh --dual --device "iPhone 17 Pro" --device "iPhone 17"
#   ./scripts/dev_ios.sh --device "iPhone 17"  # 指定模拟器机型（名称或 UDID；可写两次配双端）
#   ./scripts/dev_ios.sh --ios 26              # 指定 iOS 大版本（默认 26）
#   ./scripts/dev_ios.sh --lan                 # 真机调试：后端监听 0.0.0.0，App 用局域网 IP
#   ./scripts/dev_ios.sh --backend-only        # 只起用户 API + admin（不启 App）
#   ./scripts/dev_ios.sh --app-only            # 只起 App（后端已在别处运行）
#   ./scripts/dev_ios.sh --no-admin            # 不起运营后台
#   ./scripts/dev_ios.sh --reuse-backend       # 端口上已有健康服务时复用，不重启
#   ./scripts/dev_ios.sh --list                # 列出候选模拟器后退出

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

IOS_MAJOR="26"
DEVICE_QUERY=""
DEVICE_QUERY_2=""
API_BASE=""
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
# 运营后台固定默认 8001，与用户 API 分端口。
ADMIN_PORT="8001"
FLUTTER_MODE="debug"
RUN_BACKEND=1
RUN_ADMIN=1
RUN_APP=1
# 默认停掉已占用端口的后端再拉起，避免代码更新后仍复用旧进程。
REUSE_BACKEND=0
KEEP_BACKEND=0
USE_LAN=0
LIST_ONLY=0
# 双模拟器：各跑一份 App，本地数据隔离，可同时登录父母端与子女端。
DUAL=0

# 本次脚本是否亲自拉起了服务，决定退出时是否回收进程。
BACKEND_STARTED_BY_US=0
BACKEND_PID=""
ADMIN_STARTED_BY_US=0
ADMIN_PID=""

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
      # 可写两次 --device：第一次父母端机型，第二次子女端机型。
      --device|-d)
        local value="${2:?--device 需要一个机型名称或 UDID}"
        if [[ -z "${DEVICE_QUERY}" ]]; then
          DEVICE_QUERY="${value}"
        elif [[ -z "${DEVICE_QUERY_2}" ]]; then
          DEVICE_QUERY_2="${value}"
          DUAL=1
        else
          die "--device 最多指定两台模拟器。" "双端用法：--dual 或 --device A --device B"
        fi
        shift 2
        ;;
      --device2)
        DEVICE_QUERY_2="${2:?--device2 需要一个机型名称或 UDID}"
        DUAL=1
        shift 2
        ;;
      --dual|--both-roles) DUAL=1; shift ;;
      --ios) IOS_MAJOR="${2:?--ios 需要一个大版本号，如 26}"; shift 2 ;;
      --api-base) API_BASE="${2:?--api-base 需要一个 URL}"; shift 2 ;;
      --port) BACKEND_PORT="${2:?--port 需要一个端口}"; shift 2 ;;
      --lan) USE_LAN=1; shift ;;
      --release) FLUTTER_MODE="release"; shift ;;
      --profile) FLUTTER_MODE="profile"; shift ;;
      --backend-only) RUN_APP=0; KEEP_BACKEND=1; shift ;;
      --app-only) RUN_BACKEND=0; RUN_ADMIN=0; shift ;;
      --no-admin) RUN_ADMIN=0; shift ;;
      --admin-port) ADMIN_PORT="${2:?--admin-port 需要一个端口}"; shift 2 ;;
      # --restart-backend：历史兼容；重启已是默认行为
      --restart-backend) REUSE_BACKEND=0; shift ;;
      --reuse-backend) REUSE_BACKEND=1; shift ;;
      --keep-backend) KEEP_BACKEND=1; shift ;;
      --list) LIST_ONLY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1" "运行 ./scripts/dev_ios.sh --help 查看用法。" ;;
    esac
  done

  # 不起用户 API 时也不起 admin（除非以后单独加 --admin-only）。
  if (( ! RUN_BACKEND )); then
    RUN_ADMIN=0
  fi
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

# ---------- 后端 / 运营后台 ----------

# 从 .env 里取键值，缺省时回落到给定默认值。
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

# 单独开会话跑命令：避免脚本进程组被收掉时子服务跟着死。
# 用法：run_detached <工作目录> <日志文件> <pid 文件> <命令...>
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
      ok "后端已在 http://127.0.0.1:${BACKEND_PORT} 运行，按 --reuse-backend 复用"
      return 0
    fi
    die "端口 ${BACKEND_PORT} 被别的进程占用，且不是 Coco 后端。" "换端口：--port 8002，或先停掉占用进程。"
  fi

  # 默认：有进程占着就先停，再按当前代码重新启动。
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
  # --backend-only / --keep-backend 依赖独立会话，脚本退出后服务仍可继续跑。
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
      # uv run 是父进程，uvicorn 是它的子进程；父进程退出后补一刀，避免端口被占住。
      local leftover
      leftover="$(port_listener_pid "${BACKEND_PORT}")"
      [[ -n "${leftover}" ]] && kill "${leftover}" 2>/dev/null || true
      rm -f "${BACKEND_PID_FILE}"
    fi
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

# 按名称或 UDID 在设备列表中查找一台；exclude_udid 用于双端避开已选中的那台。
find_simulator_by_query() {
  local query="$1" exclude_udid="${2-}" devices name udid state
  devices="$(list_simulators)"
  while IFS=$'\t' read -r name udid state; do
    [[ -n "${udid}" ]] || continue
    [[ -n "${exclude_udid}" && "${udid}" == "${exclude_udid}" ]] && continue
    if [[ "${name}" == "${query}" || "${udid}" == "${query}" ]]; then
      printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
      return 0
    fi
  done <<<"${devices}"
  return 1
}

# 自动挑选一台 iPhone；顺序：已启动的 > 优先机型 > 第一台 iPhone。
pick_auto_simulator() {
  local exclude_udid="${1-}" devices name udid state preferred
  devices="$(list_simulators)"

  while IFS=$'\t' read -r name udid state; do
    [[ -n "${udid}" ]] || continue
    [[ -n "${exclude_udid}" && "${udid}" == "${exclude_udid}" ]] && continue
    if [[ "${state}" == "Booted" && "${name}" == iPhone* ]]; then
      printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
      return 0
    fi
  done <<<"${devices}"

  for preferred in "${PREFERRED_DEVICES[@]}"; do
    while IFS=$'\t' read -r name udid state; do
      [[ -n "${udid}" ]] || continue
      [[ -n "${exclude_udid}" && "${udid}" == "${exclude_udid}" ]] && continue
      if [[ "${name}" == "${preferred}" ]]; then
        printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
        return 0
      fi
    done <<<"${devices}"
  done

  while IFS=$'\t' read -r name udid state; do
    [[ -n "${udid}" ]] || continue
    [[ -n "${exclude_udid}" && "${udid}" == "${exclude_udid}" ]] && continue
    if [[ "${name}" == iPhone* ]]; then
      printf '%s\t%s\t%s\n' "${name}" "${udid}" "${state}"
      return 0
    fi
  done <<<"${devices}"

  return 1
}

# 选设备的顺序：用户指定 > 已启动的 > 优先机型 > 第一台 iPhone。
resolve_simulator() {
  local devices query="${1-}" exclude_udid="${2-}" selected
  devices="$(list_simulators)"
  [[ -n "${devices}" ]] || die "没有找到 iOS ${IOS_MAJOR} 的模拟器。" "在 Xcode → Settings → Components 里安装 iOS ${IOS_MAJOR} 运行时，或用 --ios 指定已装版本。"

  if [[ -n "${query}" ]]; then
    selected="$(find_simulator_by_query "${query}" "${exclude_udid}")" || \
      die "iOS ${IOS_MAJOR} 下没有名为「${query}」的模拟器。" "用 --list 查看可选机型。"
    printf '%s\n' "${selected}"
    return 0
  fi

  selected="$(pick_auto_simulator "${exclude_udid}")" || \
    die "iOS ${IOS_MAJOR} 下没有可用的 iPhone 模拟器。" "用 --list 查看，或在 Xcode 里新建一台设备。"
  printf '%s\n' "${selected}"
}

# 双端各选一台，保证 UDID 不同；默认优先机型前两名（如 17 Pro + 17）。
resolve_dual_simulators() {
  local first second name1 udid1 state1 name2 udid2 state2
  first="$(resolve_simulator "${DEVICE_QUERY}")" || exit 1
  IFS=$'\t' read -r name1 udid1 state1 <<<"${first}"

  second="$(resolve_simulator "${DEVICE_QUERY_2}" "${udid1}")" || exit 1
  IFS=$'\t' read -r name2 udid2 state2 <<<"${second}"

  if [[ "${udid1}" == "${udid2}" ]]; then
    die "双端需要两台不同的模拟器，当前只解析到同一台。" "用 --list 查看，并指定：--device A --device B"
  fi

  printf '%s\n' "${first}"
  printf '%s\n' "${second}"
}

boot_simulator() {
  local udid="$1" name="$2" state="$3"
  if [[ "${state}" != "Booted" ]]; then
    info "启动模拟器 ${name}"
    xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  fi
  # 多开时不要用 -CurrentDeviceUDID 盖掉另一台窗口，只确保 Simulator.app 已打开。
  open -a Simulator >/dev/null 2>&1 || true

  for _ in {1..60}; do
    if xcrun simctl list devices | grep -q "${udid}.*Booted"; then
      # bootstatus 等到 SpringBoard 就绪，避免刚 Booted 就 install 出现 exit -2。
      xcrun simctl bootstatus "${udid}" -b >/dev/null 2>&1 || true
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

BUNDLE_ID="com.coco.app"
SIMULATOR_APP_PATH="${FRONTEND_DIR}/build/ios/iphonesimulator/Runner.app"

ensure_flutter_deps() {
  info "拉取 Flutter 依赖（flutter pub get）"
  (cd "${FRONTEND_DIR}" && flutter pub get) || die "flutter pub get 失败。" "检查网络或 pubspec.yaml。"
}

run_app() {
  local udid="$1" name="$2"
  ensure_flutter_deps

  ok "在 ${name} 上运行 App（${FLUTTER_MODE}，API=${API_BASE}）"
  dim "首次构建会执行 pod install，耗时较久；按 q 退出，r 热重载。"
  cd "${FRONTEND_DIR}"
  flutter run \
    -d "${udid}" \
    "--${FLUTTER_MODE}" \
    --dart-define=COCO_API_BASE_URL="${API_BASE}"
}

# 双端装包：先统一 build，再 simctl install（带重试），比连续两次 flutter run 更稳。
install_app_on_simulator() {
  local udid="$1" name="$2" attempt
  [[ -d "${SIMULATOR_APP_PATH}" ]] || die "找不到构建产物 ${SIMULATOR_APP_PATH}。" "先确认 flutter build 成功。"

  for attempt in 1 2 3 4 5; do
    if xcrun simctl install "${udid}" "${SIMULATOR_APP_PATH}" >/dev/null 2>&1; then
      ok "已安装到 ${name}"
      return 0
    fi
    warn "安装到 ${name} 失败（第 ${attempt}/5 次），等待模拟器稳定后重试…"
    xcrun simctl bootstatus "${udid}" -b >/dev/null 2>&1 || true
    sleep $((attempt * 2))
  done
  die "无法安装到 ${name}，数据未受影响。" "可先重启模拟器：xcrun simctl shutdown ${udid} && xcrun simctl boot ${udid}"
}

launch_app_on_simulator() {
  local udid="$1" name="$2"
  # 已在前台则 terminate 再 launch，保证看到的是本次构建。
  xcrun simctl terminate "${udid}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
  xcrun simctl launch "${udid}" "${BUNDLE_ID}" >/dev/null \
    || die "无法在 ${name} 上启动 ${BUNDLE_ID}。" "手动点开模拟器里的 Coco 图标亦可。"
  ok "已在 ${name} 启动 App"
}

run_dual_apps() {
  local name1="$1" udid1="$2" name2="$3" udid2="$4"
  local build_log="${RUNTIME_DIR}/flutter-build.log"

  ensure_flutter_deps

  ok "双端模式：两台模拟器各跑一份 App（${FLUTTER_MODE}，API=${API_BASE}）"
  dim "建议：模拟器 A 登录父母，模拟器 B 登录子女（本地会话互不影响）。"
  dim "开发验证码见 backend/.env 的 COCO_DEV_SMS_CODE（默认 246810）。"

  # 双端刚 boot 完立刻装包容易 exit -2；再留几秒给 CoreSimulator。
  info "等待双模拟器服务稳定…"
  sleep 3

  info "统一构建 iOS 模拟器包（只编一次，两端共用）"
  dim "日志：${build_log}"
  (
    cd "${FRONTEND_DIR}"
    # debug 默认即可；--debug/--profile/--release 与单端 flutter run 对齐。
    flutter build ios --simulator "--${FLUTTER_MODE}" \
      --dart-define=COCO_API_BASE_URL="${API_BASE}"
  ) >"${build_log}" 2>&1 || {
    tail -n 40 "${build_log}" >&2 || true
    die "flutter build ios 失败，App 未安装、数据未受影响。" "完整日志见 ${build_log}"
  }
  ok "模拟器包构建完成"

  install_app_on_simulator "${udid1}" "${name1}"
  install_app_on_simulator "${udid2}" "${name2}"
  launch_app_on_simulator "${udid1}" "${name1}"
  launch_app_on_simulator "${udid2}" "${name2}"

  ok "双端已启动"
  info "模拟器 A（建议登父母）：${name1}"
  info "模拟器 B（建议登子女）：${name2}"
  dim "若只看到一台窗口：Simulator 菜单 Window → 再选另一台设备。"
  dim "热重载可另开终端：cd frontend && flutter attach -d ${udid1}"
  dim "按 Ctrl+C 结束脚本（模拟器里的 App 可继续用；后端按规则回收）。"

  # 挂起等待，Ctrl+C 走 cleanup。
  while true; do
    sleep 3600
  done
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
    if (( RUN_ADMIN )); then
      start_admin
    fi
  else
    backend_health_ok || warn "后端 http://127.0.0.1:${BACKEND_PORT} 没有响应，App 登录会失败。"
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

  if (( DUAL )); then
    local dual_lines selected_a selected_b
    local name1 udid1 state1 name2 udid2 state2
    # 先取回结果再解析：resolve_* 里的 die 只能结束子 shell，这里要显式判空。
    dual_lines="$(resolve_dual_simulators)" || exit 1
    selected_a="$(printf '%s\n' "${dual_lines}" | sed -n '1p')"
    selected_b="$(printf '%s\n' "${dual_lines}" | sed -n '2p')"
    [[ -n "${selected_a}" && -n "${selected_b}" ]] || exit 1
    IFS=$'\t' read -r name1 udid1 state1 <<<"${selected_a}"
    IFS=$'\t' read -r name2 udid2 state2 <<<"${selected_b}"

    boot_simulator "${udid1}" "${name1}" "${state1}"
    boot_simulator "${udid2}" "${name2}" "${state2}"
    run_dual_apps "${name1}" "${udid1}" "${name2}" "${udid2}"
  else
    local selected name udid state
    selected="$(resolve_simulator "${DEVICE_QUERY}")" || exit 1
    [[ -n "${selected}" ]] || exit 1
    IFS=$'\t' read -r name udid state <<<"${selected}"

    boot_simulator "${udid}" "${name}" "${state}"
    run_app "${udid}" "${name}"
  fi
}

main "$@"
