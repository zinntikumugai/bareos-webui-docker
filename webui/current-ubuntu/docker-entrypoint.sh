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

# Apache設定ファイルのパス
apache_conf="/etc/apache2/sites-available/000-default.conf"

# ドキュメントルートの設定
sed -i "s#/var/www/html#/usr/share/bareos-webui/public#g" $apache_conf

# Apacheサーバーステータスの有効化（オプション）
if [ "${SERVER_STATS}" == "yes" ]; then
  sed -i 's!#ServerName.*!Alias /server-status /var/www/dummy!' $apache_conf
fi

# Dockerfile CMDの実行
exec "$@"
