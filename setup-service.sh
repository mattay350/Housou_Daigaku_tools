#!/usr/bin/env bash

set -euo pipefail

# サービス名とターゲットディレクトリの設定
SERVICE_NAME="syllabus-db-server.service"
TARGET_DIR="${HOME}/.config/systemd/user"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Systemd User Service Setup ==="

# 1. 保存先ディレクトリの作成（存在しない場合）
if [ ! -d "${TARGET_DIR}" ]; then
    echo "[+] Creating directory: ${TARGET_DIR}"
    mkdir -p "${TARGET_DIR}"
fi

# 2. .service ファイルのコピー
if [ -f "${SCRIPT_DIR}/${SERVICE_NAME}" ]; then
    echo "[+] Copying ${SERVICE_NAME} to ${TARGET_DIR}/"
    cp "${SCRIPT_DIR}/${SERVICE_NAME}" "${TARGET_DIR}/"
else
    echo "[-] Error: ${SERVICE_NAME} not found in ${SCRIPT_DIR}" >&2
    exit 1
fi

# 3. systemd の再読み込み
echo "[+] Reloading systemd user daemon..."
systemctl --user daemon-reload

# 4. サービスの有効化と起動
echo "[+] Enabling and starting ${SERVICE_NAME}..."
systemctl --user enable "${SERVICE_NAME}"
systemctl --user restart "${SERVICE_NAME}"

# 5. ステータス確認
echo "=== Current Service Status ==="
systemctl --user status "${SERVICE_NAME}" --no-pager
