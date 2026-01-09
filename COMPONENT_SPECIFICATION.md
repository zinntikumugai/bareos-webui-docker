# Bareos WebUI コンポーネント仕様書

このドキュメントは、Bareos WebUIの最新バージョン（current-ubuntu）のコンポーネント仕様をまとめたものです。別のAIエージェントで使用するためのプロンプトとして設計されています。

## 概要

Bareos WebUIは、BareosバックアップシステムのWebベースの管理インターフェースです。最新バージョンは以下の実装が提供されています：

- **current-ubuntu**: Ubuntu Noble (24.04) ベース、Apache HTTP Server使用

## 1. current-ubuntu バージョン

### 1.1 Dockerfile 仕様

**ベースイメージ**: `ubuntu:noble` (Ubuntu 24.04)

**主要コンポーネント**:
- Bareos WebUIパッケージ（`bareos-webui`）
- Apache HTTP Server
- PHP 8.3とApache PHPモジュール
- PHP拡張機能（curl, json, xml, intl, mbstring）
- 設定ファイルのバックアップ/リストア機能

**ビルドプロセス**:
```dockerfile
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
    php \
    libapache2-mod-php \
    php-curl \
    php-json \
    php-xml \
    php-intl \
    php-mbstring \
 && a2enmod rewrite \
 && a2enconf bareos-webui \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# エントリーポイントスクリプトのコピーと実行権限付与
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod u+x /docker-entrypoint.sh

# 設定ファイルのバックアップ作成
RUN tar czf /bareos-webui.tgz /etc/bareos-webui

EXPOSE 80
VOLUME /etc/bareos-webui
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
```

**重要なポイント**:
- GPGキーは `/etc/apt/keyrings/bareos.gpg` に保存
- 設定ファイルは `/etc/bareos-webui` に配置
- 設定ファイルのバックアップは `/bareos-webui.tgz` に保存
- Apacheのドキュメントルートは `/usr/share/bareos-webui/public`
- Bareos WebUIのApache設定（`/etc/apache2/conf-available/bareos-webui.conf`）を自動的に有効化
- Apacheのrewriteモジュールを有効化

### 1.2 docker-entrypoint.sh 仕様

**スクリプトの役割**:
1. 初回起動時に設定ファイルを展開
2. Bareos Directorのホストアドレスを設定
3. オプション: Apacheサーバーステータスの有効化

**主要処理**:
```bash
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

# Dockerfile CMDの実行
exec "$@"
```

**環境変数**:
- `BAREOS_DIR_HOST`: Bareos Directorのホスト名（必須）
- `SERVER_STATS`: Apacheサーバーステータスの有効化（オプション、`yes`で有効）

**設定ファイル**:
- `/etc/bareos-webui/directors.ini`: Director接続設定
- `/etc/apache2/sites-available/000-default.conf`: Apache仮想ホスト設定

### 1.3 docker-compose 設定例

```yaml
bareos-webui:
  image: barcus/bareos-webui:current-ubuntu
  ports:
    - 8080:80
  environment:
    - BAREOS_DIR_HOST=bareos-dir
    - SERVER_STATS=yes  # オプション: Apacheサーバーステータスを有効化
  volumes:
    - /data/bareos/config/webui:/etc/bareos-webui
  depends_on:
    - bareos-dir
```

## 2. CI/CD ワークフロー

### 2.1 GitHub Actions ワークフロー

**ファイル**: `.github/workflows/ci-webui-current.yml`

**トリガー**:
- `webui/current-ubuntu/**` の変更
- ワークフローファイルの変更
- 手動実行（`workflow_dispatch`）
- 週次スケジュール（日曜日 6:00 UTC）

**ジョブ構成**:
1. **build**: マルチプラットフォーム対応のイメージビルド
2. **test**: イメージのテスト（設定ファイルの確認）
3. **push**: テスト成功後、masterブランチにプッシュ

**イメージタグ**:
- `current-ubuntu`
- `latest`

**プラットフォーム**:
- `linux/amd64`
- `linux/arm64`

## 3. 共通仕様

### 3.1 ボリュームマウント

**設定ファイル**:
- `/etc/bareos-webui`: WebUI設定ファイル（永続化推奨）

### 3.2 ネットワーク要件

**依存サービス**:
- Bareos Director（必須）

**ポート**:
- `80`（内部）→ `8080`（外部推奨）

### 3.3 認証情報

**デフォルトユーザー**:
- ユーザー名: `admin`
- パスワード: 環境変数 `BAREOS_WEBUI_PASSWORD` で設定（Directorコンテナで設定）

### 3.4 設定ファイル構造

**directors.ini**:
```ini
[director]
diraddress = "bareos-dir"  # 環境変数 BAREOS_DIR_HOST から設定
```

## 4. 使用時の注意事項

1. **初回起動**: 設定ファイルは初回起動時に自動展開されます。制御ファイル（`bareos-config.control`）が存在する場合は再展開されません。

2. **設定の永続化**: `/etc/bareos-webui` をボリュームマウントすることで、設定変更を永続化できます。

3. **ネットワーク**: `BAREOS_DIR_HOST` はコンテナ名で指定する必要があります（Docker Composeのサービス名）。

## 5. トラブルシューティング

### 5.1 設定ファイルのリセット

制御ファイルを削除することで、次回起動時に設定ファイルが再展開されます：

```bash
docker exec -it bareos-webui rm /etc/bareos-webui/bareos-config.control
docker restart bareos-webui
```

### 5.2 Director接続エラー

`directors.ini` の `diraddress` が正しく設定されているか確認：

```bash
docker exec -it bareos-webui cat /etc/bareos-webui/directors.ini
```

## 6. 参考情報

- **リポジトリ**: https://github.com/barcus/bareos
- **メンテナー**: barcus@tou.nu
- **Bareos公式サイト**: https://www.bareos.com/
- **Ubuntu版リポジトリ**: https://download.bareos.org/current/xUbuntu_24.04/

---

**注意**: このドキュメントは最新バージョン（current-ubuntu）のみを対象としています。過去のバージョン（deprecated）は含まれていません。
