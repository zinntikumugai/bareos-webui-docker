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
for fn in exec passthru shell_exec system proc_open popen pcntl_exec; do
  if $FPM_PHP -r "exit(function_exists('$fn') ? 1 : 0);"; then
    pass "$fn is disabled"
  else
    fail "$fn is still callable"
  fi
done

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

echo "-- 4. webroot が www-data から書き込み不可 --"
if docker run --rm -u www-data --entrypoint sh "$IMAGE" \
     -c 'test ! -w /usr/share/bareos-webui/public'; then
  pass "/usr/share/bareos-webui/public is not writable by www-data"
else
  fail "/usr/share/bareos-webui/public is writable by www-data"
fi

echo "-- 5. ログイン画面描画 + open_basedir restriction 無し (動作確認) --"
docker run -d --name "$CONTAINER" -p 18080:80 \
  -e BAREOS_DIR_HOST=bareos-dir "$IMAGE" >/dev/null

# Apache / php-fpm の起動待ち
HTTP_OK=0
for _ in $(seq 1 30); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/bareos-webui/ || true)"
  if [ "$CODE" = "200" ]; then HTTP_OK=1; break; fi
  sleep 1
done

BODY="$(curl -s http://localhost:18080/bareos-webui/ || true)"
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
