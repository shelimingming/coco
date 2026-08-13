#!/usr/bin/env bash
# Coco 虚机增量部署：本机构建 Web（可选）→ rsync → 远端 uv sync / 迁移 → 重启 coco。
#
# 用法：
#   ./scripts/deploy_vm.sh                     # 默认：前后端都更新
#   ./scripts/deploy_vm.sh --backend-only      # 只更新后端
#   ./scripts/deploy_vm.sh --web-only          # 只构建并同步 Flutter Web
#   ./scripts/deploy_vm.sh --host 1.2.3.4      # 指定虚机
#   ./scripts/deploy_vm.sh --user root         # SSH 用户（默认 root）
#   ./scripts/deploy_vm.sh --skip-migrate      # 跳过 alembic
#   ./scripts/deploy_vm.sh --skip-sync-deps    # 跳过 uv sync（无依赖变更时）
#
# 环境变量（可选）：
#   COCO_DEPLOY_HOST / COCO_DEPLOY_USER / COCO_DEPLOY_SSH_OPTS
#
# 前提：已能 ssh 登录虚机；远端已按无 Docker 方式装好 /opt/coco 与 coco.service。
# 同源部署：Web 使用空 COCO_API_BASE_URL。

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
FRONTEND_DIR="${ROOT_DIR}/frontend"

DEPLOY_HOST="${COCO_DEPLOY_HOST:-106.13.135.10}"
DEPLOY_USER="${COCO_DEPLOY_USER:-root}"
# 虚机对外端口（systemd 已监听 80）
DEPLOY_PORT="${COCO_DEPLOY_PORT:-80}"
SSH_OPTS="${COCO_DEPLOY_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
REMOTE_ROOT="/opt/coco"

DEPLOY_BACKEND=1
DEPLOY_WEB=1
SKIP_MIGRATE=0
SKIP_SYNC_DEPS=0

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
    --host) DEPLOY_HOST="${2:?--host 需要主机}"; shift 2 ;;
    --user) DEPLOY_USER="${2:?--user 需要用户名}"; shift 2 ;;
    --backend-only) DEPLOY_BACKEND=1; DEPLOY_WEB=0; shift ;;
    --web-only) DEPLOY_BACKEND=0; DEPLOY_WEB=1; shift ;;
    --skip-migrate) SKIP_MIGRATE=1; shift ;;
    --skip-sync-deps) SKIP_SYNC_DEPS=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "未知参数：$1" "用 --help 查看用法。" ;;
    esac
  done
}

ssh_cmd() {
  # shellcheck disable=SC2086
  ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"
}

rsync_to() {
  local src="$1" dest="$2"
  shift 2
  # shellcheck disable=SC2086
  rsync -az --delete "$@" -e "ssh ${SSH_OPTS}" "${src}" "${DEPLOY_USER}@${DEPLOY_HOST}:${dest}"
}

need_cmds() {
  command -v rsync >/dev/null || die "需要 rsync。"
  command -v ssh >/dev/null || die "需要 ssh。"
  if (( DEPLOY_WEB )); then
    command -v flutter >/dev/null || die "需要 flutter（本机构建 Web）。"
  fi
}

build_web() {
  info "本机构建 Flutter Web（同源空 API）"
  (
    cd "${FRONTEND_DIR}"
    flutter pub get
    # 一体同源：浏览器请求当前域名的 /v1
    flutter build web --release --dart-define=COCO_API_BASE_URL=
  ) || die "flutter build web 失败。"
  [[ -f "${FRONTEND_DIR}/build/web/index.html" ]] || die "缺少 build/web/index.html。"
  ok "Web 构建完成"
}

sync_web() {
  info "同步 Web → ${REMOTE_ROOT}/web/"
  rsync_to "${FRONTEND_DIR}/build/web/" "${REMOTE_ROOT}/web/"
  ok "Web 已同步"
}

sync_backend() {
  info "同步后端 → ${REMOTE_ROOT}/backend/"
  # 不覆盖远端 .env / .venv
  rsync_to "${BACKEND_DIR}/src/" "${REMOTE_ROOT}/backend/src/"
  rsync_to "${BACKEND_DIR}/alembic/" "${REMOTE_ROOT}/backend/alembic/"
  rsync_to "${BACKEND_DIR}/alembic.ini" "${REMOTE_ROOT}/backend/alembic.ini"
  rsync_to "${BACKEND_DIR}/pyproject.toml" "${REMOTE_ROOT}/backend/pyproject.toml"
  rsync_to "${BACKEND_DIR}/uv.lock" "${REMOTE_ROOT}/backend/uv.lock"
  rsync_to "${BACKEND_DIR}/README.md" "${REMOTE_ROOT}/backend/README.md"
  ok "后端已同步"
}

remote_backend_apply() {
  info "远端：依赖 / 迁移 / 重启"
  local remote_script
  remote_script="$(
    cat <<EOF
set -Eeuo pipefail
export PATH="/root/.local/bin:\$PATH"
cd ${REMOTE_ROOT}/backend
ln -sfn ${REMOTE_ROOT}/.env .env
EOF
  )"
  if (( ! SKIP_SYNC_DEPS )); then
    remote_script+=$'\n'"uv sync --frozen --no-dev --python 3.12"
  else
    remote_script+=$'\n'"echo 'skip uv sync'"
  fi
  if (( ! SKIP_MIGRATE )); then
    remote_script+=$'\n'"uv run --python 3.12 alembic upgrade head"
  else
    remote_script+=$'\n'"echo 'skip alembic'"
  fi
  remote_script+=$'\n'"systemctl restart coco"
  remote_script+=$'\n'"sleep 2"
  remote_script+=$'\n'"systemctl is-active coco"
  # 应用本机监听 8000（Nginx 反代 80/443）；勿打外网端口以免 301
  remote_script+=$'\n'"curl -fsS http://127.0.0.1:8000/health"
  remote_script+=$'\n'"echo"

  ssh_cmd "bash -s" <<<"${remote_script}" || die "远端应用失败。" "查看：ssh ${DEPLOY_USER}@${DEPLOY_HOST} 'journalctl -u coco -n 50 --no-pager'"
  ok "后端已应用并重启"
}

remote_restart_only() {
  info "远端重启 coco（刷新静态资源）"
  ssh_cmd "systemctl restart coco && sleep 1 && systemctl is-active coco" \
    || die "重启失败。"
  ok "已重启"
}

health_hint() {
  if [[ "${DEPLOY_PORT}" == "80" ]]; then
    dim "健康检查：http://${DEPLOY_HOST}/health"
    dim "页面：http://${DEPLOY_HOST}/ （需安全组放行 80）"
  else
    dim "健康检查：http://${DEPLOY_HOST}:${DEPLOY_PORT}/health"
    dim "页面：http://${DEPLOY_HOST}:${DEPLOY_PORT}/ （需安全组放行 ${DEPLOY_PORT}）"
  fi
}

main() {
  parse_args "$@"
  need_cmds

  info "目标 ${DEPLOY_USER}@${DEPLOY_HOST} → ${REMOTE_ROOT}"
  ssh_cmd "test -d ${REMOTE_ROOT}/backend && test -d ${REMOTE_ROOT}/web" \
    || die "远端尚未初始化。" "先完成首次无 Docker 部署后再用本脚本增量更新。"

  if (( DEPLOY_WEB )); then
    build_web
    sync_web
  fi

  if (( DEPLOY_BACKEND )); then
    sync_backend
    remote_backend_apply
  elif (( DEPLOY_WEB )); then
    remote_restart_only
  fi

  ok "部署完成"
  health_hint
}

main "$@"
