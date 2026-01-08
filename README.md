# Bareos WebUI Docker Image

Bareos WebUIのDockerイメージを提供するリポジトリです。

## 概要

Bareos WebUIは、BareosバックアップシステムのWebベースの管理インターフェースです。このリポジトリでは、Ubuntu Noble (24.04) ベースのDockerイメージを提供しています。

## サポートされているバージョン

- **current-ubuntu**: Ubuntu Noble (24.04) ベース、Apache HTTP Server使用

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
