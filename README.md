# Bareos WebUI Docker Image

Bareos WebUIのDockerイメージを提供するリポジトリです。

## 概要

Bareos WebUIは、BareosバックアップシステムのWebベースの管理インターフェースです。このリポジトリでは、Ubuntu Noble (24.04) ベースのDockerイメージを提供しています。

## サポートされているバージョン

- **current-ubuntu**: Ubuntu Noble (24.04) ベース、Apache HTTP Server + PHP-FPM 8.3使用

## クイックスタート

### Docker Composeを使用する場合

```yaml
version: '3.8'

services:
  bareos-webui:
    image: barcus/bareos-webui:current-ubuntu
    ports:
      - 8080:80
    environment:
      - BAREOS_DIR_HOST=bareos-dir
      - SERVER_STATS=yes  # オプション
    volumes:
      - ./data/bareos/config/webui:/etc/bareos-webui
    depends_on:
      - bareos-dir
```

### Dockerコマンドを使用する場合

```bash
docker run -d \
  --name bareos-webui \
  -p 8080:80 \
  -e BAREOS_DIR_HOST=bareos-dir \
  -e SERVER_STATS=yes \
  -v ./data/bareos/config/webui:/etc/bareos-webui \
  barcus/bareos-webui:current-ubuntu
```

## 環境変数

| 変数名 | 説明 | 必須 | デフォルト値 |
|--------|------|------|--------------|
| `BAREOS_DIR_HOST` | Bareos Directorのホスト名 | はい | - |
| `SERVER_STATS` | Apacheサーバーステータスの有効化 | いいえ | - |

## ボリューム

| パス | 説明 |
|------|------|
| `/etc/bareos-webui` | WebUI設定ファイル（永続化推奨） |

## ポート

| ポート | 説明 |
|--------|------|
| `80` | HTTP（内部） |

## 認証情報

デフォルトの認証情報：
- **ユーザー名**: `admin`
- **パスワード**: 環境変数 `BAREOS_WEBUI_PASSWORD` で設定（Directorコンテナで設定）

## セキュリティ（php2shell 対策）

PHP Webシェル（php2shell）攻撃に対する多層防御（defense-in-depth）を適用しています。
Bareos WebUI は Director と TCP ソケットで通信するだけで、コマンド実行系関数・
ファイルアップロード・URLインクルードを必要としないため、これらを無効化しても
アプリ動作には影響しません。

適用内容（`webui/current-ubuntu/conf/99-bareos-webui-hardening.ini` を php-fpm に投入）:

| 項目 | 設定 | 目的 |
|------|------|------|
| `disable_functions` | `exec`, `shell_exec`, `system`, `passthru`, `proc_open`, `popen`, `pcntl_exec` ほか | Webシェルの要であるOSコマンド実行/プロセス制御を無効化 |
| `open_basedir` | アプリ関連パスのみ許可 | PHPがアクセスできるファイルシステム範囲を限定 |
| `allow_url_fopen` / `allow_url_include` | `Off` | リモートファイルインクルード(RFI)対策 |
| `file_uploads` | `Off` | 不要なファイルアップロード経路を遮断 |
| `expose_php` | `Off` | PHPバージョン等の情報漏えいを低減 |
| webroot 権限 | `www-data` から書き込み不可 | PHPプロセス経由でのWebシェル投下を封じる |

> `open_basedir` は環境によって追加のパスが必要になる場合があります。
> `open_basedir restriction in effect` エラーが出る場合は、当該 ini に必要なパスを追記してください。

これらの設定は `webui/current-ubuntu/tests/test-hardening.sh` で検証され、CI（test ジョブ）で
自動的にチェックされます。ローカルでの検証:

```bash
cd webui/current-ubuntu
docker build -t bareos-webui:test .
bash tests/test-hardening.sh bareos-webui:test
```

## ビルド方法

### ローカルビルド

```bash
cd webui/current-ubuntu
docker build -t bareos-webui:current-ubuntu .
```

### GitHub Actions

プッシュまたはプルリクエスト時に自動的にビルドとテストが実行されます。

## トラブルシューティング

### 設定ファイルのリセット

制御ファイルを削除することで、次回起動時に設定ファイルが再展開されます：

```bash
docker exec -it bareos-webui rm /etc/bareos-webui/bareos-config.control
docker restart bareos-webui
```

### Director接続エラー

`directors.ini` の `diraddress` が正しく設定されているか確認：

```bash
docker exec -it bareos-webui cat /etc/bareos-webui/directors.ini
```

## 詳細仕様

詳細なコンポーネント仕様については、[COMPONENT_SPECIFICATION.md](./COMPONENT_SPECIFICATION.md) を参照してください。

## ライセンス

このプロジェクトはBareosのライセンスに従います。

## メンテナー

- barcus@tou.nu

## 参考リンク

- [Bareos公式サイト](https://www.bareos.com/)
- [GitHubリポジトリ](https://github.com/barcus/bareos)
- [Ubuntu版リポジトリ](https://download.bareos.org/current/xUbuntu_24.04/)
