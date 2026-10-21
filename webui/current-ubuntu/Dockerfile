FROM ubuntu:noble

# BareOS current (latest) for Ubuntu 24.04 (Noble) - Community Repository
ENV BAREOS_KEY=https://download.bareos.org/current/xUbuntu_24.04/Release.key
ENV BAREOS_REPO=https://download.bareos.org/current/xUbuntu_24.04/
ENV DEBIAN_FRONTEND=noninteractive

# GPGキーの追加とリポジトリ設定
RUN apt-get update -qq \
 && apt-get -qq -y install --no-install-recommends curl tzdata gnupg ca-certificates \
 && install -d /etc/apt/keyrings \
 && curl -fsSL $BAREOS_KEY | gpg --dearmor -o /etc/apt/keyrings/bareos.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/bareos.gpg] $BAREOS_REPO /" > /etc/apt/sources.list.d/bareos.list \
 && apt-get update -qq \
 && apt-get install -qq -y --no-install-recommends \
    bareos-webui \
    apache2 \
    php-fpm \
    php-cli \
    php-curl \
    php-json \
    php-xml \
    php-intl \
    php-mbstring \
 && a2enmod proxy_fcgi setenvif rewrite \
 && a2enconf php8.3-fpm bareos-webui \
 && a2dissite 000-default \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# php2shell (PHP Webシェル) 対策: PHP ハードニング設定を php-fpm の conf.d に投入
# (disable_functions / open_basedir / allow_url_* / file_uploads / expose_php)
COPY conf/99-bareos-webui-hardening.ini /etc/php/8.3/fpm/conf.d/99-bareos-webui-hardening.ini

# php2shell 対策: webroot を実行ユーザ (www-data) から書き込み不可にし、
# PHP プロセス経由での Web シェル投下を封じる。
# 既存の実行ビットは保持したまま group/other の書き込みのみ剥奪する。
RUN chown -R root:root /usr/share/bareos-webui \
 && chmod -R go-w /usr/share/bareos-webui

# エントリーポイントスクリプトのコピーと実行権限付与
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh \
 && chmod u+x /docker-entrypoint.sh

# 設定ファイルのバックアップ作成
RUN tar czf /bareos-webui.tgz /etc/bareos-webui

EXPOSE 80
VOLUME /etc/bareos-webui
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
