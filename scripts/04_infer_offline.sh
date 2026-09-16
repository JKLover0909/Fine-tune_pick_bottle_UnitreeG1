#!/usr/bin/env bash
# 04_infer_offline.sh — kiểm tra policy ACT đã train mà KHÔNG cần robot.
# Bọc unitree_lerobot/eval_robot/offline_infer_dataset.py: chạy policy trên dataset đã ghi,
# so action dự đoán vs action thật, xuất metrics (MAE/RMSE) + plot. Không gửi lệnh ra robot.
#
# Dùng:  scripts/04_infer_offline.sh [checkpoint_dir] [episode] [--dry-run]
#   checkpoint_dir mặc định: outputs/act_pick_bottle/checkpoints/050000/pretrained_model
#   episode mặc định: 0
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

# Tách cờ --dry-run khỏi tham số vị trí
DRY_RUN=0
POS=()
for a in "$@"; do
  if [[ "$a" == "--dry-run" ]]; then DRY_RUN=1; else POS+=("$a"); fi
done
CKPT="${POS[0]:-$HERE/../outputs/act_pick_bottle/checkpoints/050000/pretrained_model}"
EPISODE="${POS[1]:-0}"

INFER_SCRIPT="$UNITREE_LEROBOT_DIR/unitree_lerobot/eval_robot/offline_infer_dataset.py"
DATASET_ROOT="$HOME/.cache/huggingface/lerobot/$REPO_ID"
OUT_DIR="$HERE/../outputs/offline_infer"

if [[ ! -d "$CKPT" ]]; then
  echo "LỖI: không thấy checkpoint: $CKPT" >&2; exit 1
fi
if [[ ! -f "$INFER_SCRIPT" ]]; then
  echo "LỖI: không thấy infer script: $INFER_SCRIPT" >&2; exit 1
fi

cat <<EOF
==> Infer offline (KHÔNG robot)
    checkpoint : $CKPT
    dataset    : $REPO_ID  (root: $DATASET_ROOT)
    episode    : $EPISODE
    output     : $OUT_DIR
    env        : $CONDA_ENV   video_backend: pyav
EOF

CMD=(python "$INFER_SCRIPT"
  --repo-id "$REPO_ID"
  --root "$DATASET_ROOT"
  --policy-path "$CKPT"
  --episode "$EPISODE"
  --mode queued
  --video-backend pyav
  --output-root "$OUT_DIR")

echo
echo "Lệnh: conda run -n $CONDA_ENV ${CMD[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: không chạy)"; exit 0
fi

conda run -n "$CONDA_ENV" "${CMD[@]}"
echo "==> Xong. Kết quả (metrics + plot) ở: $OUT_DIR/latest"
