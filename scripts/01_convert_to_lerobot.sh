#!/usr/bin/env bash
# 01_convert_to_lerobot.sh — convert các bộ raw đã stage sang một LeRobot dataset hợp nhất.
# Gọi convert_unitree_json_to_lerobot.py trong repo unitree_lerobot (env tv).
# Dataset kết quả nằm ở ~/.cache/huggingface/lerobot/$REPO_ID
#
# Dùng:  scripts/01_convert_to_lerobot.sh [--dry-run]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ ! -d "$STAGING_DIR" ]]; then
  echo "LỖI: chưa có staging ($STAGING_DIR). Chạy scripts/00_stage_raw_data.sh trước." >&2
  exit 1
fi
if [[ ! -f "$CONVERT_SCRIPT" ]]; then
  echo "LỖI: không thấy convert script: $CONVERT_SCRIPT" >&2
  exit 1
fi

cat <<EOF
==> Convert -> LeRobot
    raw-dir   : $STAGING_DIR
    repo-id   : $REPO_ID   (-> ~/.cache/huggingface/lerobot/$REPO_ID)
    robot_type: $ROBOT_TYPE
    env       : $CONDA_ENV

⚠  MÌN CAMERA: robot_type '$ROBOT_TYPE' hiện map 4 camera (color_0..3), map color_1->cam_right_high.
   Data thô chỉ có 3 camera (color_0=head, color_1=cổ tay TRÁI, color_2=cổ tay PHẢI).
   Hãy xác minh/sửa camera_to_image_key trong:
     $UNITREE_LEROBOT_DIR/unitree_lerobot/utils/constants.py
   TRƯỚC khi tin tưởng dataset đầu ra. Xem docs/dataset.md.
EOF

CMD=(python "$CONVERT_SCRIPT"
  --raw-dir "$STAGING_DIR"
  --repo-id "$REPO_ID"
  --robot_type "$ROBOT_TYPE")

echo
echo "Lệnh: conda run -n $CONDA_ENV ${CMD[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: không chạy)"
  exit 0
fi

read -r -p "Tiếp tục convert? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Huỷ."; exit 0; }

conda run -n "$CONDA_ENV" "${CMD[@]}"
echo "==> Xong. Soát lại: ls ~/.cache/huggingface/lerobot/$REPO_ID"
