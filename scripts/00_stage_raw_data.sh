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

# Dựng lại staging từ đầu để phản ánh đúng EXCLUDE_EPISODES hiện tại.
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Hàm kiểm tra một "dataset/episode" có nằm trong danh sách loại không.
is_excluded() {
  local key="$1"
  for ex in "${EXCLUDE_EPISODES[@]:-}"; do
    [[ "$key" == "$ex" ]] && return 0
  done
  return 1
}

missing=0
excluded=0
total_ep=0
for ds in "${DATASETS[@]}"; do
  src="$RAW_DATA_DIR/$ds"
  if [[ ! -d "$src" ]]; then
    echo "  [THIẾU] $ds  (không có ở $src)" >&2
    missing=$((missing+1))
    continue
  fi
  # Tạo thư mục task thật, symlink từng episode (bỏ episode bị loại).
  dst="$STAGING_DIR/$ds"
  mkdir -p "$dst"
  n=0
  while IFS= read -r ep; do
    epname="$(basename "$ep")"
    if is_excluded "$ds/$epname"; then
      excluded=$((excluded+1))
      continue
    fi
    ln -sfn "$ep" "$dst/$epname"
    n=$((n+1))
  done < <(find "$src" -maxdepth 1 -type d -iname "episode*" | sort)
  total_ep=$((total_ep+n))
  echo "  [OK]    $ds -> $n episode"
done

echo
echo "==> Staging xong tại: $STAGING_DIR ($total_ep episode dùng được, $excluded episode bị loại)"
if [[ "$missing" -gt 0 ]]; then
  echo "CẢNH BÁO: $missing bộ bị thiếu — kiểm tra lại DATASETS trong config.env." >&2
  exit 2
fi
echo "Bước tiếp: scripts/check_dataset.py \"$STAGING_DIR\"  rồi  scripts/01_convert_to_lerobot.sh"
