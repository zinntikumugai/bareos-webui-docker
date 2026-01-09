#!/usr/bin/env bash

# 初回起動チェック（制御ファイルの存在確認）
if [ ! -f /etc/bareos-webui/bareos-config.control ];then
  # 設定ファイルの展開
  tar xzf /bareos-webui.tgz --backup=simple --suffix=.before-control

  # Bareos Directorのホストアドレスを環境変数から設定
  sed -i 's#diraddress.*#diraddress = '\""${BAREOS_DIR_HOST}"\"'#' \
    /etc/bareos-webui/directors.ini

  # 制御ファイルの作成（再実行防止）
  touch /etc/bareos-webui/bareos-config.control
fi

# Bareos Directorのホストアドレスをデフォルト値に設定（環境変数が未設定の場合）
: ${BAREOS_DIR_HOST:=bareos-dir}

# Apacheサーバーステータスの有効化（オプション）
if [ "${SERVER_STATS}" == "yes" ]; then
  apache_conf="/etc/apache2/sites-available/000-default.conf"
  sed -i 's!#ServerName.*!Alias /server-status /var/www/dummy!' $apache_conf
fi

# PHP-FPMを起動（バックグラウンド）
echo "Starting PHP-FPM..."
php-fpm8.3 -D

# PHP-FPMの起動を待機
sleep 2

# Dockerfile CMDの実行（Apache）
echo "Starting Apache..."
exec "$@"
