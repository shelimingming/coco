#!/usr/bin/env bash
# 将 scripts/Nginx 证书与 coco.conf 安装到虚机（HTTPS）。
#
# 用法：
#   ./scripts/apply_nginx_ssl.sh
#   ./scripts/apply_nginx_ssl.sh --host 106.13.110.85
#
# 前提：scripts/Nginx/ 下有
#   coco.xyfit.top.key
#   coco.xyfit.top_ca.crt
#   coco.conf

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="${SCRIPT_DIR}/Nginx"
DEPLOY_HOST="${COCO_DEPLOY_HOST:-106.13.110.85}"
DEPLOY_USER="${COCO_DEPLOY_USER:-root}"
DEFAULT_IDENTITY="${SCRIPT_DIR}/coco-vm.key"
DEPLOY_IDENTITY="${COCO_DEPLOY_IDENTITY:-}"
if [[ -z "${DEPLOY_IDENTITY}" && -f "${DEFAULT_IDENTITY}" ]]; then
  DEPLOY_IDENTITY="${DEFAULT_IDENTITY}"
fi
SSH_OPTS="${COCO_DEPLOY_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
if [[ -n "${DEPLOY_IDENTITY}" ]]; then
  SSH_OPTS="${SSH_OPTS} -i ${DEPLOY_IDENTITY}"
fi

CERT_KEY="${NGINX_DIR}/coco.xyfit.top.key"
CERT_CHAIN="${NGINX_DIR}/coco.xyfit.top_ca.crt"
CONF_SRC="${NGINX_DIR}/coco.conf"

info() { printf '▸ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
die() { printf '✗ %s\n' "$1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
  --host) DEPLOY_HOST="${2:?}"; shift 2 ;;
  --user) DEPLOY_USER="${2:?}"; shift 2 ;;
  *) die "未知参数：$1" ;;
  esac
done

[[ -f "${CERT_KEY}" ]] || die "缺少 ${CERT_KEY}"
[[ -f "${CERT_CHAIN}" ]] || die "缺少 ${CERT_CHAIN}"
[[ -f "${CONF_SRC}" ]] || die "缺少 ${CONF_SRC}"

# shellcheck disable=SC2086
ssh_cmd() { ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"; }
# shellcheck disable=SC2086
scp_to() { scp ${SSH_OPTS} "$1" "${DEPLOY_USER}@${DEPLOY_HOST}:$2"; }

info "校验证书与私钥配对"
cert_mod="$(openssl x509 -in "${CERT_CHAIN}" -noout -modulus | openssl md5)"
key_mod="$(openssl rsa -in "${CERT_KEY}" -noout -modulus | openssl md5)"
[[ "${cert_mod}" == "${key_mod}" ]] || die "证书与私钥不匹配"

info "上传到 ${DEPLOY_USER}@${DEPLOY_HOST}"
ssh_cmd "mkdir -p /etc/coco/ssl && chmod 700 /etc/coco/ssl"
scp_to "${CERT_CHAIN}" /tmp/coco-fullchain.pem
scp_to "${CERT_KEY}" /tmp/coco-privkey.pem
scp_to "${CONF_SRC}" /tmp/coco.conf

ssh_cmd "bash -s" <<'REMOTE'
set -Eeuo pipefail
install -m 644 /tmp/coco-fullchain.pem /etc/coco/ssl/fullchain.pem
install -m 600 /tmp/coco-privkey.pem /etc/coco/ssl/privkey.pem
install -m 644 /tmp/coco.conf /etc/nginx/conf.d/coco.conf
rm -f /tmp/coco-fullchain.pem /tmp/coco-privkey.pem /tmp/coco.conf
# 确保 nginx.conf 内置 default:80 已禁用（避免与跳转冲突）
if ! grep -q COCO_DISABLED_DEFAULT_SERVER /etc/nginx/nginx.conf; then
  python3 - <<'PY'
from pathlib import Path
p = Path("/etc/nginx/nginx.conf")
lines = p.read_text().splitlines(True)
out, i, disabled = [], 0, False
while i < len(lines):
    if (
        not disabled
        and lines[i] == "    server {\n"
        and i + 3 < len(lines)
        and "listen       80;" in lines[i + 1]
        and "server_name  _;" in lines[i + 3]
    ):
        out.append("    # COCO_DISABLED_DEFAULT_SERVER begin\n")
        depth = 0
        while i < len(lines):
            line = lines[i]
            depth += line.count("{") - line.count("}")
            out.append("# " + line if line.strip() else line)
            i += 1
            if depth <= 0:
                break
        out.append("    # COCO_DISABLED_DEFAULT_SERVER end\n")
        disabled = True
        continue
    out.append(lines[i])
    i += 1
p.write_text("".join(out))
print("disabled_default" if disabled else "default_ok")
PY
fi
nginx -t
systemctl reload nginx
ss -lntp | grep -E ':80|:443' || true
curl -fsS http://127.0.0.1/health >/dev/null || true
echo APPLY_OK
REMOTE

ok "已启用 https://coco.xyfit.top/ （需安全组放行 443）"
info "自检：curl -fsSI https://coco.xyfit.top/health"
