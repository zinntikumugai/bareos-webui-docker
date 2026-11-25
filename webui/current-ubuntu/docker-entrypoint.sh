#!/usr/bin/env bash

# Bareos Directorのホストアドレスをデフォルト値に設定（環境変数が未設定の場合）
# ※ 設定ファイルへの書き込みより前に確定させる必要がある
: "${BAREOS_DIR_HOST:=bareos-dir}"

# 入力検証: ホスト名 / IPv4 / IPv6 に使われる文字のみ許可する
# （sed 置換や ini の引用符を壊す値の混入を防ぐ）
if [[ ! "${BAREOS_DIR_HOST}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: invalid BAREOS_DIR_HOST: '${BAREOS_DIR_HOST}'" >&2
  exit 1
fi

# 初回起動チェック（制御ファイルの存在確認）
if [ ! -f /etc/bareos-webui/bareos-config.control ];then
  # 設定ファイルの展開
  tar xzf /bareos-webui.tgz --backup=simple --suffix=.before-control

  # Bareos Directorのホストアドレスを環境変数から設定
  sed -i 's#diraddress.*#diraddress = "'"${BAREOS_DIR_HOST}"'"#' \
    /etc/bareos-webui/directors.ini

  # 制御ファイルの作成（再実行防止）
  touch /etc/bareos-webui/bareos-config.control
fi

# PHP-FPMを起動（バックグラウンド）
echo "Starting PHP-FPM..."
if ! php-fpm8.3 -D; then
  # FPM が起動できないと全 PHP リクエストが失敗するため、Apache を起動せず異常終了する
  echo "ERROR: failed to start PHP-FPM" >&2
  exit 1
fi

# PHP-FPMの起動を待機
sleep 2

# Dockerfile CMDの実行（Apache）
echo "Starting Apache..."
exec "$@"
