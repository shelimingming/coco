#!/usr/bin/env bash
# Coco 虚机首次装机（无 Docker）：swap + uv + Nginx + systemd 骨架。
# 默认还装本机 Postgres；--skip-db 则跳过，改用本机 backend/.env 的云库。
# 装完后请再跑：./scripts/deploy_vm.sh
#
# 用法：
#   ./scripts/setup_vm.sh
#   ./scripts/setup_vm.sh --skip-db          # 不装本机 Postgres，连云库
#   ./scripts/setup_vm.sh --host 1.2.3.4
#   ./scripts/setup_vm.sh --user root
#
# 环境变量（可选）：
#   COCO_DEPLOY_HOST / COCO_DEPLOY_USER / COCO_DEPLOY_SSH_OPTS / COCO_DEPLOY_IDENTITY
#   COCO_DB_PASSWORD  远端本机 Postgres 用户 coco 的密码（默认 coco_demo_password；--skip-db 时忽略）

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

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

DB_PASSWORD="${COCO_DB_PASSWORD:-coco_demo_password}"
SKIP_DB=0
REMOTE_ROOT="/opt/coco"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
else
  C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi

info() { printf '%s\n' "${C_INFO}▸${C_RESET} $*"; }
ok() { printf '%s\n' "${C_OK}✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_WARN}!${C_RESET} $*" >&2; }
die() {
  printf '%s\n' "${C_ERR}✗ $1${C_RESET}" >&2
  [[ $# -gt 1 ]] && printf '%s\n' "  ${2}" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --host) DEPLOY_HOST="${2:?}"; shift 2 ;;
    --user) DEPLOY_USER="${2:?}"; shift 2 ;;
    --identity) DEPLOY_IDENTITY="${2:?}"; SSH_OPTS="${COCO_DEPLOY_SSH_OPTS:--o StrictHostKeyChecking=accept-new} -i ${DEPLOY_IDENTITY}"; shift 2 ;;
    --skip-db) SKIP_DB=1; shift ;;
    -h | --help)
      awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) die "未知参数：$1" ;;
    esac
  done
}

ssh_cmd() {
  # shellcheck disable=SC2086
  ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"
}

scp_to() {
  # shellcheck disable=SC2086
  scp ${SSH_OPTS} "$1" "${DEPLOY_USER}@${DEPLOY_HOST}:$2"
}

# 从本机 backend/.env 取云库 URL / 鉴权密钥 / 百炼 Key（不打印）
build_remote_env() {
  local out="$1"
  python3 - <<PY
from pathlib import Path
import sys

def env_map(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.is_file():
        return data
    for line in path.read_text().splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        data[key] = value.strip()
    return data

src = env_map(Path("${ROOT_DIR}/backend/.env"))
skip_db = "${SKIP_DB}" == "1"
key = src.get("COCO_ALIYUN_API_KEY", "")
# 与云库共用同一套用户表时，pepper / signing key 必须和本机一致
signing = src.get(
    "COCO_AUTH_SIGNING_KEY",
    "demo-signing-key-change-me-0123456789abcdef",
)
pepper = src.get(
    "COCO_AUTH_HASH_PEPPER",
    "demo-pepper-change-me-0123456789abcdef12",
)
if skip_db:
    db = src.get("COCO_DATABASE_URL", "")
    if not db:
        print("skip-db 需要本机 backend/.env 里已有 COCO_DATABASE_URL", file=sys.stderr)
        sys.exit(1)
    if "127.0.0.1" in db or "localhost" in db:
        print("skip-db 时 COCO_DATABASE_URL 不能指向本机 Postgres", file=sys.stderr)
        sys.exit(1)
else:
    pwd = """${DB_PASSWORD}"""
    db = f"postgresql+asyncpg://coco:{pwd}@127.0.0.1:5432/coco"

lines = [
    "COCO_ENVIRONMENT=development",
    "COCO_LOG_LEVEL=INFO",
    f"COCO_DATABASE_URL={db}",
    f"COCO_AUTH_SIGNING_KEY={signing}",
    f"COCO_AUTH_HASH_PEPPER={pepper}",
    "COCO_AUTH_ISSUER=coco-backend",
    "COCO_AUTH_AUDIENCE=coco-web",
    "COCO_ACCESS_TOKEN_TTL_SECONDS=3600",
    "COCO_REFRESH_TOKEN_TTL_DAYS=30",
    "COCO_SMS_PROVIDER=dev",
    "COCO_DEV_SMS_CODE=246810",
    "COCO_OTP_TTL_SECONDS=300",
    "COCO_OTP_MAX_ATTEMPTS=5",
    "COCO_OTP_REQUEST_LIMIT_PER_HOUR=20",
    "COCO_CORS_ALLOWED_ORIGINS=*",
    "COCO_PUBLIC_BASE_URL=https://coco.xyfit.top",
    "COCO_WEB_STATIC_DIR=/opt/coco/web",
    f"COCO_ALIYUN_API_KEY={key}",
    "COCO_ALIYUN_REGION=cn-beijing",
    "COCO_REALTIME_MODEL=qwen-audio-3.0-realtime-plus",
    "COCO_REALTIME_VOICE=longanqian",
    "COCO_TEXT_MODEL=qwen-plus",
    "COCO_VISION_MODEL=qwen3.7-plus",
    "COCO_ASR_MODEL=qwen-audio-3.0-asr-flash",
    "COCO_TTS_MODEL=qwen3-tts-flash",
    "COCO_TTS_VOICE=Cherry",
]
Path("${out}").write_text("\n".join(lines) + "\n")
print("env_ready", "with_key" if key else "no_key", "cloud_db" if skip_db else "local_db")
PY
}

main() {
  parse_args "$@"
  command -v ssh >/dev/null || die "需要 ssh"
  command -v scp >/dev/null || die "需要 scp"
  command -v python3 >/dev/null || die "需要 python3"

  if [[ -n "${DEPLOY_IDENTITY}" ]]; then
    [[ -f "${DEPLOY_IDENTITY}" ]] || die "找不到私钥：${DEPLOY_IDENTITY}"
    chmod 600 "${DEPLOY_IDENTITY}" || true
  else
    warn "未指定 IdentityFile，将使用 ssh 默认密钥"
  fi

  info "探测 ${DEPLOY_USER}@${DEPLOY_HOST}"
  ssh_cmd "echo SSH_OK" >/dev/null || die "无法 SSH 登录。" "检查密钥与安全组 22。"

  ENV_TMP="$(mktemp)"
  # 退出时清理含密钥的临时文件
  trap 'rm -f "${ENV_TMP}"' EXIT
  build_remote_env "${ENV_TMP}"

  info "上传远端 .env"
  scp_to "${ENV_TMP}" /tmp/coco.env

  if (( SKIP_DB )); then
    info "远端装机（跳过 Postgres，连云库 / uv / Nginx / systemd）"
  else
    info "远端装机（Postgres / uv / Nginx / systemd）"
  fi
  # DB 密码经环境注入远端脚本，避免写进仓库
  # shellcheck disable=SC2086
  ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" \
    "DB_PASSWORD=$(printf '%q' "${DB_PASSWORD}") SKIP_DB=$(printf '%q' "${SKIP_DB}") REMOTE_ROOT=$(printf '%q' "${REMOTE_ROOT}") bash -s" <<'REMOTE'
set -Eeuo pipefail
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:$PATH"
# 国产镜像：清华 PyPI + npmmirror Python 构建
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
export UV_PYTHON_INSTALL_MIRROR="https://cdn.npmmirror.com/binaries/python-build-standalone"
export UV_HTTP_TIMEOUT=180
mkdir -p /root/.config/uv
cat > /root/.config/uv/uv.toml <<'TOML'
[[index]]
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true
TOML


APP_ROOT="${REMOTE_ROOT}"
BACKEND_DIR="${APP_ROOT}/backend"
WEB_DIR="${APP_ROOT}/web"
ENV_FILE="${APP_ROOT}/.env"

echo "▸ swap（小机）"
if [[ ! -f /swapfile ]]; then
  fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
fi
free -m | head -2

echo "▸ 系统包"
# 只装缺的包；已有的 curl/python3 不要再 dnf install，否则会把 openssl 升到 3.5 并弄挂 sshd
PKGS=(nginx)
if [[ "${SKIP_DB:-0}" != "1" ]]; then
  PKGS+=(postgresql-server postgresql)
fi
dnf install -y "${PKGS[@]}"

if [[ "${SKIP_DB:-0}" == "1" ]]; then
  echo "▸ 跳过本机 Postgres，使用云库"
else
echo "▸ 初始化 Postgres"
if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
  postgresql-setup --initdb || /usr/bin/postgresql-setup --initdb || true
fi
systemctl enable --now postgresql
for i in $(seq 1 45); do
  sudo -u postgres psql -c 'SELECT 1' >/dev/null 2>&1 && break
  sleep 1
done
sudo -u postgres psql -c 'SELECT 1' >/dev/null

echo "▸ 库与用户 coco"
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'coco') THEN
    CREATE ROLE coco LOGIN PASSWORD '${DB_PASSWORD}';
  ELSE
    ALTER ROLE coco WITH PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE coco OWNER coco'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'coco')\\gexec
GRANT ALL PRIVILEGES ON DATABASE coco TO coco;
SQL

PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file" | tr -d '[:space:]')
cp -a "${PG_HBA}" "${PG_HBA}.bak.$(date +%s)"
cat > "${PG_HBA}" <<'HBA'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
HBA

PG_CONF=$(sudo -u postgres psql -tAc "SHOW config_file" | tr -d '[:space:]')
sed -i -E 's/^#?shared_buffers.*/shared_buffers = 64MB/' "${PG_CONF}" || true
sed -i -E 's/^#?work_mem.*/work_mem = 4MB/' "${PG_CONF}" || true
systemctl restart postgresql
sleep 2
PGPASSWORD="${DB_PASSWORD}" psql -h 127.0.0.1 -U coco -d coco -c 'SELECT 1'
fi

echo "▸ 安装 uv"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="/root/.local/bin:$PATH"
uv --version

echo "▸ 目录骨架"
mkdir -p "${BACKEND_DIR}" "${WEB_DIR}"
# 占位，满足 deploy_vm 的目录检查；真正内容由 deploy 同步
[[ -f "${WEB_DIR}/index.html" ]] || echo '<!doctype html><title>coco</title>pending' > "${WEB_DIR}/index.html"
cp /tmp/coco.env "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
ln -sfn "${ENV_FILE}" "${BACKEND_DIR}/.env"
# 先放最小后端占位，避免 systemd 立刻失败；deploy 会覆盖
if [[ ! -f "${BACKEND_DIR}/pyproject.toml" ]]; then
  mkdir -p "${BACKEND_DIR}/src/coco"
  printf '%s\n' '[project]' 'name="coco"' 'version="0.0.0"' 'requires-python=">=3.12"' > "${BACKEND_DIR}/pyproject.toml"
fi

echo "▸ systemd coco（127.0.0.1:8000）"
if [[ "${SKIP_DB:-0}" == "1" ]]; then
cat > /etc/systemd/system/coco.service <<'UNIT'
[Unit]
Description=Coco demo (API + Web)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/coco/backend
EnvironmentFile=/opt/coco/.env
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin
Environment=UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
Environment=UV_PYTHON_INSTALL_MIRROR=https://cdn.npmmirror.com/binaries/python-build-standalone
ExecStart=/root/.local/bin/uv run --python 3.12 uvicorn coco.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=3
MemoryMax=800M

[Install]
WantedBy=multi-user.target
UNIT
else
cat > /etc/systemd/system/coco.service <<'UNIT'
[Unit]
Description=Coco demo (API + Web)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/coco/backend
EnvironmentFile=/opt/coco/.env
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin
Environment=UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
Environment=UV_PYTHON_INSTALL_MIRROR=https://cdn.npmmirror.com/binaries/python-build-standalone
ExecStart=/root/.local/bin/uv run --python 3.12 uvicorn coco.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=3
MemoryMax=800M

[Install]
WantedBy=multi-user.target
UNIT
fi

systemctl daemon-reload
systemctl enable coco.service
# 代码尚未同步，先不强制 start；deploy 后会重启

echo "▸ Nginx :80（静态 + 反代 API）"
cat > /etc/nginx/conf.d/coco.conf <<'NGINX'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream coco_app {
    server 127.0.0.1:8000;
    keepalive 32;
}

server {
    listen 80 default_server;
    server_name _;

    root /opt/coco/web;
    index index.html;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_types text/plain text/css application/javascript application/json application/wasm font/ttf font/otf image/svg+xml;
    gzip_vary on;

    location /v1/ {
        proxy_pass http://coco_app;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location = /health {
        proxy_pass http://coco_app;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /docs {
        proxy_pass http://coco_app;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /openapi.json {
        proxy_pass http://coco_app;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Flutter Web 的 html/js 文件名无内容 hash；禁止长期缓存，否则发版后仍打开旧包。
    location ~* \.(html|js|css|json)$ {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }

    location ~* \.(wasm|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|otf)$ {
        expires 7d;
        add_header Cache-Control "public";
        try_files $uri =404;
    }

    # 根路径进双端演示页（与 FastAPI 行为一致）
    location = / {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files /presentation.html /index.html =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX

# 去掉可能冲突的默认站（Baidulinux 常在 nginx.conf 内嵌 listen 80）
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
python3 - <<'PY'
from pathlib import Path

p = Path("/etc/nginx/nginx.conf")
text = p.read_text()
if "COCO_DISABLED_DEFAULT_SERVER" in text:
    print("default_already_disabled")
else:
    lines = text.splitlines(True)
    out: list[str] = []
    i = 0
    disabled = False
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
    print("disabled_default" if disabled else "no_default_block")
PY
nginx -t
systemctl enable --now nginx
systemctl reload nginx

if [[ "${SKIP_DB:-0}" == "1" ]]; then
  echo "▸ 探测云库 TCP"
  python3 - <<'PY'
from pathlib import Path
import socket
import sys
import urllib.parse

url = ""
for line in Path("/opt/coco/.env").read_text().splitlines():
    if line.startswith("COCO_DATABASE_URL="):
        url = line.split("=", 1)[1].strip()
        break
if not url:
    sys.exit("missing COCO_DATABASE_URL")
raw = url.replace("postgresql+asyncpg://", "postgresql://", 1)
parsed = urllib.parse.urlparse(raw)
host = parsed.hostname
port = parsed.port or 5432
print(f"tcp {host}:{port}")
try:
    sock = socket.create_connection((host, port), timeout=8)
    sock.close()
except OSError as exc:
    sys.exit(f"无法连云库 {host}:{port}：{exc}（检查 RDS 白名单是否含本机公网 IP）")
print("tcp_ok")
PY
fi

rm -f /tmp/coco.env
echo "▸ SETUP_OK"
REMOTE

  ok "装机完成：${DEPLOY_USER}@${DEPLOY_HOST}"
  info "下一步：./scripts/deploy_vm.sh   # 同步后端 + 构建并部署 Web"
}

main "$@"
