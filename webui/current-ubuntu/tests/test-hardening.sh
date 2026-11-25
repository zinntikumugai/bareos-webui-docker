#!/usr/bin/env bash
#
# php2shell (PHP Webシェル) ハードニング検証テスト
#
# ビルド済みの Bareos WebUI イメージに対し、適用済みのハードニング設定が
# 有効であることを検証する。CI とローカルの両方から実行できる。
#
# 使い方: bash test-hardening.sh <image-tag>
#   例:    bash test-hardening.sh bareos-webui:test

set -euo pipefail

IMAGE="${1:-bareos-webui:test}"
CONTAINER="bareos-webui-hardening-test-$$"
FAIL=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAIL=1; }

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# php-fpm 用設定 (php.ini + conf.d の drop-in) を CLI で評価する。
# PHP CLI は既定で CLI 用 conf.d を読むため、PHP_INI_SCAN_DIR を fpm の
# conf.d に向けて、ハードニング drop-in を含めた実効値を取得する。
FPM_PHP="docker run --rm -e PHP_INI_SCAN_DIR=/etc/php/8.3/fpm/conf.d --entrypoint php $IMAGE -c /etc/php/8.3/fpm/php.ini"

php_setting() {
  local name="$1"
  $FPM_PHP -r "echo ini_get('$name');"
}

echo "== php2shell hardening test for image: $IMAGE =="

echo "-- 1. disable_functions (コマンド実行系の無効化) --"
DISABLED="$(php_setting disable_functions || true)"
echo "     disable_functions = ${DISABLED:-<empty>}"
# mail/putenv/mb_send_mail: putenv(LD_PRELOAD)+mail() による disable_functions 回避対策
# posix_*/pcntl_*: プロセス操作系 (WebUI は未使用)
for fn in exec passthru shell_exec system proc_open popen pcntl_exec \
          mail putenv mb_send_mail \
          posix_kill posix_setuid posix_setgid posix_setsid posix_mkfifo \
          pcntl_signal pcntl_alarm; do
  if $FPM_PHP -r "exit(function_exists('$fn') ? 1 : 0);"; then
    pass "$fn is disabled"
  else
    fail "$fn is still callable"
  fi
done
# error_log は WebUI が多用するため無効化してはならない (回帰防止)
if $FPM_PHP -r "exit(function_exists('error_log') ? 0 : 1);"; then
  pass "error_log is still available (required by WebUI)"
else
  fail "error_log is disabled (WebUI depends on it)"
fi

echo "-- 2. open_basedir (ファイルアクセス制限) --"
OPEN_BASEDIR="$(php_setting open_basedir || true)"
if [ -n "$OPEN_BASEDIR" ]; then
  pass "open_basedir is set: $OPEN_BASEDIR"
else
  fail "open_basedir is empty"
fi

echo "-- 3. その他の php.ini ハードニング --"
check_off() {
  local name="$1"
  local val
  val="$(php_setting "$name" || true)"
  # ini_get は Off を "" または "0" で返す
  if [ -z "$val" ] || [ "$val" = "0" ]; then
    pass "$name is Off"
  else
    fail "$name is On ($val)"
  fi
}
check_off expose_php
check_off file_uploads
check_off allow_url_include
check_off allow_url_fopen

check_eq() {
  local name="$1" want="$2" val
  val="$(php_setting "$name" || true)"
  if [ "$val" = "$want" ]; then
    pass "$name = $want"
  else
    fail "$name is '${val}' (want '$want')"
  fi
}
echo "-- 3b. セッション Cookie 保護 (php.ini 層での多層防御) --"
check_eq session.use_strict_mode 1
check_eq session.cookie_httponly 1
check_eq session.cookie_samesite Strict

echo "-- 3c. Apache の情報露出低減 / 不要設定の無効化 --"
if docker run --rm --entrypoint sh "$IMAGE" -c \
     'grep -qE "^ServerTokens[[:space:]]+Prod" /etc/apache2/conf-enabled/*.conf'; then
  pass "ServerTokens Prod"
else
  fail "ServerTokens is not Prod"
fi
if docker run --rm --entrypoint sh "$IMAGE" -c \
     'grep -qE "^ServerSignature[[:space:]]+Off" /etc/apache2/conf-enabled/*.conf'; then
  pass "ServerSignature Off"
else
  fail "ServerSignature is not Off"
fi
if docker run --rm --entrypoint sh "$IMAGE" -c \
     'test ! -e /etc/apache2/conf-enabled/serve-cgi-bin.conf'; then
  pass "serve-cgi-bin is disabled"
else
  fail "serve-cgi-bin is enabled"
fi

echo "-- 3d. ビルド専用ツールが残っていない --"
for bin in curl gpg; do
  if docker run --rm --entrypoint sh "$IMAGE" -c "! command -v $bin >/dev/null"; then
    pass "$bin is not installed"
  else
    fail "$bin is installed"
  fi
done

echo "-- 3e. 未適用のセキュリティアップデートが無い --"
# apt-get update の失敗 (ネットワーク障害等) を「更新なし」と誤判定しないよう、
# インデックス取得の成否を終了コードで区別する (失敗時は exit 2)
APT_RC=0
PENDING="$(docker run --rm --entrypoint sh "$IMAGE" -c \
  'apt-get update -qq >/dev/null 2>&1 || exit 2; apt list --upgradable 2>/dev/null | grep -- "-security"; exit 0')" || APT_RC=$?
if [ "$APT_RC" -ne 0 ]; then
  fail "could not refresh package index (apt-get update failed, rc=$APT_RC)"
elif [ -z "$PENDING" ]; then
  pass "no pending security updates"
else
  fail "pending security updates found:"
  printf '%s\n' "$PENDING" | head -10
fi

echo "-- 3f. entrypoint: BAREOS_DIR_HOST の既定値と入力検証 --"
DIRADDR="$(docker run --rm "$IMAGE" grep -E '^[[:space:]]*diraddress' /etc/bareos-webui/directors.ini 2>/dev/null || true)"
if printf '%s' "$DIRADDR" | grep -q '"bareos-dir"'; then
  pass "default diraddress is bareos-dir"
else
  fail "default diraddress is wrong: ${DIRADDR:-<none>}"
fi
DIRADDR="$(docker run --rm -e BAREOS_DIR_HOST=dir.example.local "$IMAGE" grep -E '^[[:space:]]*diraddress' /etc/bareos-webui/directors.ini 2>/dev/null || true)"
if printf '%s' "$DIRADDR" | grep -q '"dir.example.local"'; then
  pass "BAREOS_DIR_HOST is applied"
else
  fail "BAREOS_DIR_HOST not applied: ${DIRADDR:-<none>}"
fi
if docker run --rm -e 'BAREOS_DIR_HOST=bad"#host' "$IMAGE" true >/dev/null 2>&1; then
  fail "invalid BAREOS_DIR_HOST was accepted"
else
  pass "invalid BAREOS_DIR_HOST is rejected"
fi

echo "-- 3g. entrypoint: PHP-FPM 起動失敗時は起動中止 --"
# /run/php を読み取り専用にしてソケット作成を失敗させる
if docker run --rm --tmpfs /run/php:ro "$IMAGE" true >/dev/null 2>&1; then
  fail "container continued although php-fpm failed to start"
else
  pass "container aborts when php-fpm fails to start"
fi

echo "-- 4. webroot が www-data から書き込み不可 --"
if docker run --rm -u www-data --entrypoint sh "$IMAGE" \
     -c 'test ! -w /usr/share/bareos-webui/public'; then
  pass "/usr/share/bareos-webui/public is not writable by www-data"
else
  fail "/usr/share/bareos-webui/public is writable by www-data"
fi

echo "-- 5. ログイン画面描画 + open_basedir restriction 無し (動作確認) --"
# ホストポートは Docker に動的割当させ、CI ランナーでのポート衝突を避ける
docker run -d --name "$CONTAINER" -p 127.0.0.1::80 \
  -e BAREOS_DIR_HOST=bareos-dir "$IMAGE" >/dev/null
HOST_PORT="$(docker port "$CONTAINER" 80/tcp | head -1 | sed 's/.*://')"
BASE_URL="http://127.0.0.1:${HOST_PORT}/bareos-webui/"

# Apache / php-fpm の起動待ち
HTTP_OK=0
for _ in $(seq 1 30); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL" || true)"
  if [ "$CODE" = "200" ]; then HTTP_OK=1; break; fi
  sleep 1
done

BODY="$(curl -s "$BASE_URL" || true)"
if [ "$HTTP_OK" = "1" ]; then
  pass "login page returned HTTP 200"
else
  fail "login page did not return HTTP 200 (last code: ${CODE:-none})"
fi

if printf '%s' "$BODY" | grep -qiE '<form|login|password'; then
  pass "login form markup present"
else
  fail "login form markup not found"
fi

HEADERS="$(curl -sI "$BASE_URL" || true)"
SERVER_HDR="$(printf '%s' "$HEADERS" | tr -d '\r' | grep -i '^Server:' | sed 's/^[^:]*:[[:space:]]*//')"
if [ "$SERVER_HDR" = "Apache" ]; then
  pass "Server header hides version/OS ($SERVER_HDR)"
else
  fail "Server header leaks details: ${SERVER_HDR:-<none>}"
fi
for hdr in 'X-Frame-Options: SAMEORIGIN' 'X-Content-Type-Options: nosniff' 'Referrer-Policy: same-origin'; do
  if printf '%s' "$HEADERS" | tr -d '\r' | grep -qi "^${hdr}$"; then
    pass "header present: $hdr"
  else
    fail "header missing: $hdr"
  fi
done
if curl -s "http://127.0.0.1:${HOST_PORT}/no-such-page" | grep -qi '<address>'; then
  fail "error page shows server signature"
else
  pass "error page has no server signature"
fi

LOGS="$(docker logs "$CONTAINER" 2>&1 || true)"
if printf '%s' "$LOGS" | grep -qi 'open_basedir restriction'; then
  fail "open_basedir restriction error found in container logs"
  printf '%s\n' "$LOGS" | grep -i 'open_basedir' | head -5
else
  pass "no open_basedir restriction error in logs"
fi

echo "== result =="
if [ "$FAIL" -ne 0 ]; then
  echo "HARDENING TEST FAILED"
  exit 1
fi
echo "HARDENING TEST PASSED"
