#!/usr/bin/env bash
# 02_train_act.sh — train ACT policy (from scratch) trên dataset đã convert.
# Chạy LOCAL trên card 16GB, env tv. Dùng lerobot_train.py trong repo unitree_lerobot.
#
# Dùng:  scripts/02_train_act.sh [--dry-run]
# Chỉnh batch/step qua biến môi trường: ACT_BATCH_SIZE=16 ACT_STEPS=50000 scripts/02_train_act.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ ! -f "$TRAIN_SCRIPT" ]]; then
  echo "LỖI: không thấy train script: $TRAIN_SCRIPT" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

cat <<EOF
==> Train ACT (local, card 16GB)
    dataset  : $REPO_ID
    output   : $OUTPUT_DIR
    batch    : $ACT_BATCH_SIZE   steps: $ACT_STEPS   save_freq: $ACT_SAVE_FREQ
    env      : $CONDA_ENV   video_backend: pyav
EOF

# lerobot_train.py phải chạy từ trong thư mục lerobot (đường dẫn tương đối tới src).
CMD=(python "$TRAIN_SCRIPT"
  --dataset.repo_id="$REPO_ID"
  --dataset.video_backend=pyav   # torchcodec lỗi với torch 2.3.0 (thiếu register_fake); pyav ổn
  --policy.type=act
  --policy.push_to_hub=false
  --policy.device=cuda
  --batch_size="$ACT_BATCH_SIZE"
  --steps="$ACT_STEPS"
  --save_freq="$ACT_SAVE_FREQ"
  --output_dir="$OUTPUT_DIR"
  --job_name="$JOB_NAME")

echo
echo "Lệnh (cwd=$LEROBOT_DIR):"
echo "  conda run -n $CONDA_ENV ${CMD[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: không chạy)"
  exit 0
fi

cd "$LEROBOT_DIR"
conda run -n "$CONDA_ENV" "${CMD[@]}"
echo "==> Train xong. Checkpoint ở: $OUTPUT_DIR/checkpoints/"
echo "    Đẩy lên Hub + dọn đĩa: scripts/push_checkpoint_to_hub.sh <checkpoint_dir>"
