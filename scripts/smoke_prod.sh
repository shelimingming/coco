#!/usr/bin/env bash
# Coco 生产环境门禁（smoke gate）：curl 验证基础设施与核心 API，Playwright 验证双端演示页。
#
# 用法：
#   ./scripts/smoke_prod.sh                          # 默认 https://coco.xyfit.top
#   ./scripts/smoke_prod.sh --base-url https://...   # 指定目标
#   ./scripts/smoke_prod.sh --skip-browser           # 仅 curl 层（G01–G14）
#
# 环境变量：
#   COCO_SMOKE_BASE_URL  覆盖默认 base URL

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
E2E_DIR="${ROOT_DIR}/e2e"

BASE_URL="${COCO_SMOKE_BASE_URL:-https://coco.xyfit.top}"
SKIP_BROWSER=0

# 运行时状态
PASS_COUNT=0
FAIL_COUNT=0
FAILED_CASES=()

# 登录链路临时变量
SMOKE_PHONE=""
SMOKE_CHALLENGE_ID=""
SMOKE_DEV_CODE=""
SMOKE_ACCESS_TOKEN=""
SMOKE_INVITE_CODE=""

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
    --base-url) BASE_URL="${2:?--base-url 需要 URL}"; shift 2 ;;
    --skip-browser) SKIP_BROWSER=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "未知参数：$1" "$(usage)" ;;
    esac
  done
  BASE_URL="${BASE_URL%/}"
}

need_cmds() {
  local missing=()
  for cmd in curl python3; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing[@]} > 0 )); then
    die "缺少命令：${missing[*]}"
  fi
}

record_pass() {
  local id="$1"
  local desc="$2"
  PASS_COUNT=$((PASS_COUNT + 1))
  ok "${id} ${desc}"
}

record_fail() {
  local id="$1"
  local desc="$2"
  local detail="${3:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_CASES+=("${id}")
  printf '%s\n' "${C_ERR}✗ ${id} ${desc}${C_RESET}" >&2
  if [[ -n "${detail}" ]]; then
    dim "${detail}"
  fi
}

# curl 带超时；失败时不因 set -e 直接退出，由 record_fail 汇总
curl_body() {
  curl -fsS --connect-timeout 10 --max-time 30 "$@"
}

curl_headers() {
  curl -fsSI --connect-timeout 10 --max-time 30 "$@"
}

json_get() {
  local json="$1"
  local key="$2"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d[sys.argv[2]])' "${json}" "${key}"
}

json_has_key() {
  local json="$1"
  local key="$2"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if sys.argv[2] in d else 1)' "${json}" "${key}"
}

gen_smoke_phone() {
  # 139 + 时间戳后 8 位，避免复跑撞号
  local suffix
  suffix="$(date +%s | tail -c 9)"
  SMOKE_PHONE="139${suffix}"
}

run_g01_health() {
  local body
  if ! body="$(curl_body "${BASE_URL}/health" 2>&1)"; then
    record_fail "G01" "健康检查" "${body}"
    return
  fi
  local status
  status="$(json_get "${body}" "status" 2>/dev/null || echo "")"
  if [[ "${status}" == "ok" ]]; then
    record_pass "G01" "健康检查"
  else
    record_fail "G01" "健康检查" "status=${status} body=${body}"
  fi
}

run_g02_presentation() {
  local body
  if ! body="$(curl_body "${BASE_URL}/" 2>&1)"; then
    record_fail "G02" "演示页" "${body}"
    return
  fi
  if [[ "${body}" == *"可可"* && "${body}" == *"长辈端"* && "${body}" == *"子女端"* ]]; then
    record_pass "G02" "演示页"
  else
    record_fail "G02" "演示页" "缺少关键文案"
  fi
}

run_g03_index() {
  local code
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 "${BASE_URL}/index.html")" || code="000"
  if [[ "${code}" == "200" ]]; then
    record_pass "G03" "SPA 入口"
  else
    record_fail "G03" "SPA 入口" "HTTP ${code}"
  fi
}

run_g04_main_js() {
  local headers code ctype
  if ! headers="$(curl_headers "${BASE_URL}/main.dart.js" 2>&1)"; then
    record_fail "G04" "Flutter 主包" "${headers}"
    return
  fi
  code="$(printf '%s' "${headers}" | awk 'toupper($1) ~ /^HTTP/ { print $2; exit }')"
  ctype="$(printf '%s' "${headers}" | awk 'BEGIN{IGNORECASE=1} /^content-type:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }')"
  if [[ "${code}" == "200" && "${ctype}" == *"javascript"* ]]; then
    record_pass "G04" "Flutter 主包"
  else
    record_fail "G04" "Flutter 主包" "HTTP ${code} content-type=${ctype}"
  fi
}

run_g05_bootstrap() {
  local code
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 "${BASE_URL}/flutter_bootstrap.js")" || code="000"
  if [[ "${code}" == "200" ]]; then
    record_pass "G05" "Bootstrap"
  else
    record_fail "G05" "Bootstrap" "HTTP ${code}"
  fi
}

run_g06_spa_fallback() {
  local body code
  body="$(curl -sS --connect-timeout 10 --max-time 30 "${BASE_URL}/__smoke_not_found__" 2>&1)" || body=""
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 "${BASE_URL}/__smoke_not_found__")" || code="000"
  if [[ "${code}" == "200" && "${body}" == *"<html"* ]]; then
    record_pass "G06" "SPA fallback"
  else
    record_fail "G06" "SPA fallback" "HTTP ${code}"
  fi
}

run_g07_phone_code() {
  gen_smoke_phone
  local body
  if ! body="$(curl_body -X POST "${BASE_URL}/v1/auth/phone/code" \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"${SMOKE_PHONE}\"}" 2>&1)"; then
    record_fail "G07" "发验证码" "${body}"
    return
  fi
  if json_has_key "${body}" "challenge_id"; then
    SMOKE_CHALLENGE_ID="$(json_get "${body}" "challenge_id")"
    if json_has_key "${body}" "dev_code"; then
      SMOKE_DEV_CODE="$(json_get "${body}" "dev_code")"
    else
      SMOKE_DEV_CODE="246810"
    fi
    record_pass "G07" "发验证码"
  else
    record_fail "G07" "发验证码" "${body}"
  fi
}

run_g08_login() {
  if [[ -z "${SMOKE_CHALLENGE_ID}" ]]; then
    record_fail "G08" "登录" "G07 未通过，跳过"
    return
  fi
  local body
  if ! body="$(curl_body -X POST "${BASE_URL}/v1/auth/phone/login" \
    -H 'Content-Type: application/json' \
    -d "{\"challenge_id\":\"${SMOKE_CHALLENGE_ID}\",\"phone\":\"${SMOKE_PHONE}\",\"code\":\"${SMOKE_DEV_CODE}\",\"role\":\"parent\",\"display_name\":\"门禁测试\",\"device_id\":\"smoke-gate\"}" 2>&1)"; then
    record_fail "G08" "登录" "${body}"
    return
  fi
  if json_has_key "${body}" "access_token"; then
    SMOKE_ACCESS_TOKEN="$(json_get "${body}" "access_token")"
    record_pass "G08" "登录"
  else
    record_fail "G08" "登录" "${body}"
  fi
}

run_g09_me() {
  if [[ -z "${SMOKE_ACCESS_TOKEN}" ]]; then
    record_fail "G09" "当前用户" "G08 未通过，跳过"
    return
  fi
  local body
  if ! body="$(curl_body "${BASE_URL}/v1/me" -H "Authorization: Bearer ${SMOKE_ACCESS_TOKEN}" 2>&1)"; then
    record_fail "G09" "当前用户" "${body}"
    return
  fi
  local role
  role="$(json_get "${body}" "role" 2>/dev/null || echo "")"
  if [[ "${role}" == "parent" ]]; then
    record_pass "G09" "当前用户"
  else
    record_fail "G09" "当前用户" "role=${role}"
  fi
}

run_authed_get() {
  local id="$1"
  local desc="$2"
  local path="$3"
  if [[ -z "${SMOKE_ACCESS_TOKEN}" ]]; then
    record_fail "${id}" "${desc}" "未登录，跳过"
    return
  fi
  local code
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "${BASE_URL}${path}" -H "Authorization: Bearer ${SMOKE_ACCESS_TOKEN}")" || code="000"
  if [[ "${code}" == "200" ]]; then
    record_pass "${id}" "${desc}"
  else
    record_fail "${id}" "${desc}" "HTTP ${code}"
  fi
}

run_g14_invite() {
  if [[ -z "${SMOKE_ACCESS_TOKEN}" ]]; then
    record_fail "G14" "邀请短链" "未登录，跳过"
    return
  fi
  local body code location preview_code
  if ! body="$(curl_body -X POST "${BASE_URL}/v1/family/invite" \
    -H "Authorization: Bearer ${SMOKE_ACCESS_TOKEN}" 2>&1)"; then
    record_fail "G14" "邀请短链" "创建邀请失败：${body}"
    return
  fi
  if ! json_has_key "${body}" "code"; then
    record_fail "G14" "邀请短链" "无 code：${body}"
    return
  fi
  SMOKE_INVITE_CODE="$(json_get "${body}" "code")"

  # 短链 302
  location="$(curl -sS -o /dev/null -D - --connect-timeout 10 --max-time 30 \
    "${BASE_URL}/i/${SMOKE_INVITE_CODE}" 2>&1 | awk 'BEGIN{IGNORECASE=1} /^location:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }')" || location=""
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "${BASE_URL}/i/${SMOKE_INVITE_CODE}")" || code="000"

  if [[ "${code}" != "302" || "${location}" != *"#/invite/${SMOKE_INVITE_CODE}"* ]]; then
    record_fail "G14" "邀请短链" "HTTP ${code} Location=${location}"
    return
  fi

  # 免登录预览
  preview_code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "${BASE_URL}/v1/family/invites/${SMOKE_INVITE_CODE}")" || preview_code="000"
  if [[ "${preview_code}" == "200" ]]; then
    record_pass "G14" "邀请短链"
  else
    record_fail "G14" "邀请短链" "预览 HTTP ${preview_code}"
  fi
}

run_g13_family() {
  if [[ -z "${SMOKE_ACCESS_TOKEN}" ]]; then
    record_fail "G13" "家庭视图" "未登录，跳过"
    return
  fi
  local body code
  body="$(curl -sS --connect-timeout 10 --max-time 30 \
    "${BASE_URL}/v1/family" -H "Authorization: Bearer ${SMOKE_ACCESS_TOKEN}" 2>&1)" || body=""
  code="$(curl -o /dev/null -sS -w '%{http_code}' --connect-timeout 10 --max-time 30 \
    "${BASE_URL}/v1/family" -H "Authorization: Bearer ${SMOKE_ACCESS_TOKEN}")" || code="000"
  # 未绑定家庭时 404 亦表示接口与鉴权正常
  if [[ "${code}" == "200" ]]; then
    record_pass "G13" "家庭视图"
  elif [[ "${code}" == "404" && "${body}" == *"family.not_found"* ]]; then
    record_pass "G13" "家庭视图（未绑定）"
  else
    record_fail "G13" "家庭视图" "HTTP ${code} body=${body}"
  fi
}

run_curl_gate() {
  info "curl 门禁 → ${BASE_URL}"
  run_g01_health
  run_g02_presentation
  run_g03_index
  run_g04_main_js
  run_g05_bootstrap
  run_g06_spa_fallback
  run_g07_phone_code
  run_g08_login
  run_g09_me
  run_authed_get "G10" "提醒列表" "/v1/reminders"
  run_authed_get "G11" "记忆列表" "/v1/memories"
  run_authed_get "G12" "语音能力" "/v1/voice/capabilities"
  run_g13_family
  run_g14_invite
}

run_browser_gate() {
  if (( SKIP_BROWSER )); then
    dim "跳过浏览器门禁（--skip-browser）"
    return
  fi
  if (( FAIL_COUNT > 0 )); then
    warn "curl 层已有失败，仍继续浏览器门禁"
  fi

  info "浏览器门禁（Playwright）"
  if [[ ! -d "${E2E_DIR}" ]]; then
    record_fail "Bxx" "Playwright 目录" "找不到 ${E2E_DIR}"
    return
  fi
  if ! command -v npx >/dev/null 2>&1; then
    record_fail "Bxx" "Playwright 运行环境" "缺少 npx；请安装 Node.js 后执行：cd e2e && npm ci && npx playwright install chromium"
    return
  fi
  if [[ ! -d "${E2E_DIR}/node_modules" ]]; then
    warn "e2e 依赖未安装，尝试 npm ci…"
    if ! (cd "${E2E_DIR}" && npm ci --silent 2>&1); then
      record_fail "Bxx" "Playwright 依赖" "npm ci 失败；请手动：cd e2e && npm ci && npx playwright install chromium"
      return
    fi
  fi

  local output
  if output="$(cd "${E2E_DIR}" && COCO_SMOKE_BASE_URL="${BASE_URL}" npx playwright test 2>&1)"; then
    PASS_COUNT=$((PASS_COUNT + 5))
    ok "B01–B05 浏览器门禁"
    dim "${output}" | tail -5
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_CASES+=("B01-B05")
    printf '%s\n' "${C_ERR}✗ B01–B05 浏览器门禁${C_RESET}" >&2
    printf '%s\n' "${output}" >&2 | tail -30
  fi
}

print_summary() {
  echo
  info "门禁汇总：通过 ${PASS_COUNT}，失败 ${FAIL_COUNT}"
  if (( FAIL_COUNT > 0 )); then
    printf '%s\n' "${C_ERR}失败用例：${FAILED_CASES[*]}${C_RESET}" >&2
    exit 1
  fi
  ok "生产门禁全部通过"
}

main() {
  parse_args "$@"
  need_cmds
  run_curl_gate
  run_browser_gate
  print_summary
}

main "$@"
