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
