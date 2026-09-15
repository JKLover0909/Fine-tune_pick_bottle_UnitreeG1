#!/usr/bin/env bash
# 00_stage_raw_data.sh — tạo thư mục staging chứa symlink tới đúng các bộ data đã chọn
# (biến DATASETS trong config.env), để convert gộp một lần mà không nuốt các bộ khác
# (cube / open_bottle) trong thư mục data gốc. Dùng symlink, không copy, để tiết kiệm đĩa.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

echo "==> RAW_DATA_DIR : $RAW_DATA_DIR"
echo "==> STAGING_DIR  : $STAGING_DIR"
echo "==> Sẽ stage ${#DATASETS[@]} bộ: ${DATASETS[*]}"
echo

if [[ ! -d "$RAW_DATA_DIR" ]]; then
  echo "LỖI: không thấy RAW_DATA_DIR: $RAW_DATA_DIR" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"

missing=0
for ds in "${DATASETS[@]}"; do
  src="$RAW_DATA_DIR/$ds"
  dst="$STAGING_DIR/$ds"
  if [[ ! -d "$src" ]]; then
    echo "  [THIẾU] $ds  (không có ở $src)" >&2
    missing=$((missing+1))
    continue
  fi
  ln -sfn "$src" "$dst"
  n=$(find -L "$dst" -maxdepth 1 -type d -iname "episode*" | wc -l)
  echo "  [OK]    $ds -> $n episode"
done

echo
echo "==> Staging xong tại: $STAGING_DIR"
if [[ "$missing" -gt 0 ]]; then
  echo "CẢNH BÁO: $missing bộ bị thiếu — kiểm tra lại DATASETS trong config.env." >&2
  exit 2
fi
echo "Bước tiếp: scripts/check_dataset.py \"$STAGING_DIR\"  rồi  scripts/01_convert_to_lerobot.sh"
