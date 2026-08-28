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
#   COCO_DEPLOY_HOST / COCO_DEPLOY_USER / COCO_DEPLOY_SSH_OPTS / COCO_DEPLOY_IDENTITY
#   COCO_DEPLOY_PASSWORD                       # 密码登录（优先读 scripts/coco-vm.credentials）
#   SKIP_SMOKE=1                               # 部署完成后跳过生产门禁
#
# 本地凭据文件（gitignore）：scripts/coco-vm.credentials
# 前提：已能 ssh 登录虚机；远端已跑过 ./scripts/setup_vm.sh（或等价首次装机）。
# 同源部署：Web 使用空 COCO_API_BASE_URL。

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
FRONTEND_DIR="${ROOT_DIR}/frontend"

# 本地凭据：主机 / 用户 / 密码（勿提交）
CREDENTIALS_FILE="${SCRIPT_DIR}/coco-vm.credentials"
if [[ -f "${CREDENTIALS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CREDENTIALS_FILE}"
fi

DEPLOY_HOST="${COCO_DEPLOY_HOST:-106.13.110.85}"
DEPLOY_USER="${COCO_DEPLOY_USER:-root}"
DEPLOY_PASSWORD="${COCO_DEPLOY_PASSWORD:-}"
# 虚机对外端口（Nginx 监听 80，反代本机 8000）
DEPLOY_PORT="${COCO_DEPLOY_PORT:-80}"
DEFAULT_IDENTITY="${SCRIPT_DIR}/coco-vm.key"
DEPLOY_IDENTITY="${COCO_DEPLOY_IDENTITY:-}"
# 有密码时优先密码登录，避免失效私钥拖垮握手
if [[ -z "${DEPLOY_PASSWORD}" ]]; then
  if [[ -z "${DEPLOY_IDENTITY}" && -f "${DEFAULT_IDENTITY}" ]]; then
    DEPLOY_IDENTITY="${DEFAULT_IDENTITY}"
  fi
fi
SSH_OPTS="${COCO_DEPLOY_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
if [[ -n "${DEPLOY_PASSWORD}" ]]; then
  SSH_OPTS="${SSH_OPTS} -o PreferredAuthentications=password -o PubkeyAuthentication=no"
elif [[ -n "${DEPLOY_IDENTITY}" ]]; then
  SSH_OPTS="${SSH_OPTS} -i ${DEPLOY_IDENTITY}"
fi
REMOTE_ROOT="/opt/coco"
# 1=使用 sshpass -e；0=直接 ssh（密码走 SSH_ASKPASS 或密钥）
USE_SSHPASS=0

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
    --identity)
      DEPLOY_IDENTITY="${2:?--identity 需要私钥路径}"
      SSH_OPTS="${COCO_DEPLOY_SSH_OPTS:--o StrictHostKeyChecking=accept-new} -i ${DEPLOY_IDENTITY}"
      shift 2
      ;;
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
  if (( USE_SSHPASS )); then
    sshpass -e ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"
  else
    ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"
  fi
}

rsync_to() {
  local src="$1" dest="$2" remote_shell
  shift 2
  if (( USE_SSHPASS )); then
    remote_shell="sshpass -e ssh ${SSH_OPTS}"
  else
    remote_shell="ssh ${SSH_OPTS}"
  fi
  # shellcheck disable=SC2086
  rsync -az --delete "$@" -e "${remote_shell}" "${src}" "${DEPLOY_USER}@${DEPLOY_HOST}:${dest}"
}

need_cmds() {
  command -v rsync >/dev/null || die "需要 rsync。"
  command -v ssh >/dev/null || die "需要 ssh。"
  if [[ -n "${DEPLOY_PASSWORD}" ]]; then
    export SSHPASS="${DEPLOY_PASSWORD}"
    if command -v sshpass >/dev/null; then
      USE_SSHPASS=1
    else
      # macOS 无 sshpass 时用 SSH_ASKPASS 喂密码
      local askpass
      askpass="$(mktemp "${TMPDIR:-/tmp}/coco-askpass.XXXXXX")"
      cat >"${askpass}" <<'EOF'
#!/bin/sh
echo "$SSHPASS"
EOF
      chmod 700 "${askpass}"
      export SSH_ASKPASS="${askpass}"
      export SSH_ASKPASS_REQUIRE=force
      export DISPLAY="${DISPLAY:-:0}"
      trap 'rm -f "${SSH_ASKPASS:-}"' EXIT
      USE_SSHPASS=0
    fi
  fi
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
    # none：不注册离线 Service Worker，避免发版后仍拦截成旧资源
    flutter build web --release --pwa-strategy=none --dart-define=COCO_API_BASE_URL=
  ) || die "flutter build web 失败。"
  [[ -f "${FRONTEND_DIR}/build/web/index.html" ]] || die "缺少 build/web/index.html。"
  stamp_web_cache_bust
  ok "Web 构建完成"
}

stamp_web_cache_bust() {
  # 构建产物带提交号，旧浏览器缓存的无 hash JS 不会挡住新包
  local ver index presentation sw_src sw_dst
  ver="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || date +%s)"
  index="${FRONTEND_DIR}/build/web/index.html"
  presentation="${FRONTEND_DIR}/build/web/presentation.html"
  python3 - "${index}" "${presentation}" "${ver}" <<'PY'
from pathlib import Path
import sys

index, presentation, ver = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if index.is_file():
    text = index.read_text()
    text = text.replace('src="flutter_bootstrap.js"', f'src="flutter_bootstrap.js?v={ver}"')
    index.write_text(text)
if presentation.is_file():
    text = presentation.read_text()
    text = text.replace(
        'src="./index.html?presentation_slot=parent"',
        f'src="./index.html?presentation_slot=parent&v={ver}"',
    )
    text = text.replace(
        'src="./index.html?presentation_slot=child"',
        f'src="./index.html?presentation_slot=child&v={ver}"',
    )
    presentation.write_text(text)
PY
  sw_src="${FRONTEND_DIR}/web/flutter_service_worker.js"
  sw_dst="${FRONTEND_DIR}/build/web/flutter_service_worker.js"
  # Flutter --pwa-strategy=none 可能不拷贝该文件；旧客户端仍会请求，必须部署卸载脚本
  if [[ -f "${sw_src}" ]]; then
    cp "${sw_src}" "${sw_dst}"
  fi
}

sync_web() {
  info "同步 Web → ${REMOTE_ROOT}/web/"
  rsync_to "${FRONTEND_DIR}/build/web/" "${REMOTE_ROOT}/web/"
  ok "Web 已同步"
}

sync_nginx() {
  local conf="${SCRIPT_DIR}/Nginx/coco.conf"
  [[ -f "${conf}" ]] || return 0
  info "同步 Nginx 配置"
  rsync_to "${conf}" "/etc/nginx/conf.d/coco.conf"
  # 用 nginx -s reload：部分虚机 systemctl reload 会因 PrivateTmp 命名空间失败（status 226）
  ssh_cmd "nginx -t && nginx -s reload" || die "Nginx 配置无效。"
  ok "Nginx 已重载"
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

remote_ensure_invite_env() {
  # 邀请链接拼进分享文案，必须是公网 HTTPS 域名
  info "远端：校验邀请短链域名 COCO_PUBLIC_BASE_URL"
  ssh_cmd "bash -s" <<'EOF'
set -Eeuo pipefail
ENV_FILE=/opt/coco/.env
PUBLIC=https://coco.xyfit.top
if grep -q '^COCO_PUBLIC_BASE_URL=' "$ENV_FILE" 2>/dev/null; then
  sed -i "s|^COCO_PUBLIC_BASE_URL=.*|COCO_PUBLIC_BASE_URL=${PUBLIC}|" "$ENV_FILE"
else
  echo "COCO_PUBLIC_BASE_URL=${PUBLIC}" >>"$ENV_FILE"
fi
grep '^COCO_PUBLIC_BASE_URL=' "$ENV_FILE"
EOF
  ok "邀请短链域名已设为 https://coco.xyfit.top"
}

remote_backend_apply() {
  info "远端：依赖 / 迁移 / 重启"
  local remote_script
  remote_script="$(
    cat <<EOF
set -Eeuo pipefail
export PATH="/root/.local/bin:\$PATH"
# 国产镜像（uv.lock 含 files.pythonhosted.org 直链，需改写才能走镜像）
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
export UV_PYTHON_INSTALL_MIRROR="https://cdn.npmmirror.com/binaries/python-build-standalone"
export UV_HTTP_TIMEOUT=180
cd ${REMOTE_ROOT}/backend
ln -sfn ${REMOTE_ROOT}/.env .env
# 将官方 PyPI 文件域名替换为清华镜像（下次 rsync 会恢复，不影响本机锁文件）
if [[ -f uv.lock ]]; then
  sed -i \\
    -e 's|https://files.pythonhosted.org|https://pypi.tuna.tsinghua.edu.cn|g' \\
    -e 's|https://pypi.org/simple|https://pypi.tuna.tsinghua.edu.cn/simple|g' \\
    uv.lock
fi
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

  if [[ -n "${DEPLOY_IDENTITY}" ]]; then
    [[ -f "${DEPLOY_IDENTITY}" ]] || die "找不到私钥：${DEPLOY_IDENTITY}"
    chmod 600 "${DEPLOY_IDENTITY}" || true
  fi

  info "目标 ${DEPLOY_USER}@${DEPLOY_HOST} → ${REMOTE_ROOT}"
  ssh_cmd "test -d ${REMOTE_ROOT}/backend && test -d ${REMOTE_ROOT}/web" \
    || die "远端尚未初始化。" "先执行：./scripts/setup_vm.sh"

  if (( DEPLOY_WEB )); then
    build_web
    sync_web
  fi

  sync_nginx

  if (( DEPLOY_BACKEND )); then
    sync_backend
    remote_ensure_invite_env
    remote_backend_apply
  elif (( DEPLOY_WEB )); then
    remote_restart_only
  fi

  ok "部署完成"
  health_hint
  dim "邀请短链：https://coco.xyfit.top/i/{code} → 落地页 /index.html#/invite/{code}"

  # 部署后从本机打公网 HTTPS，验证 Nginx 静态资源与核心 API
  if [[ "${SKIP_SMOKE:-0}" != "1" ]]; then
    info "运行生产门禁…"
    "${SCRIPT_DIR}/smoke_prod.sh" --base-url "https://coco.xyfit.top" || die "生产门禁未通过" "可单独排查：./scripts/smoke_prod.sh"
  fi
}

main "$@"
