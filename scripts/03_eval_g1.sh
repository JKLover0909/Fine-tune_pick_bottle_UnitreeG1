#!/usr/bin/env bash
# 03_eval_g1.sh — eval checkpoint ACT trên robot Unitree G1 thật.
# Bọc eval_robot/eval_g1.py trong repo unitree_lerobot (env tv).
#
# ⚠  AN TOÀN: mặc định --send_real_robot=false (chỉ chạy policy, KHÔNG gửi lệnh ra robot).
#    Chỉ đặt SEND_REAL=true khi đã đảm bảo vùng làm việc an toàn và có người trực e-stop.
#    Nhớ mở image_server trước (xem README repo unitree_lerobot / xr_teleoperate).
#
# Dùng:  scripts/03_eval_g1.sh <checkpoint_dir> [--dry-run]
#   ví dụ checkpoint_dir: outputs/act_pick_bottle/checkpoints/100000/pretrained_model
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

CKPT="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
SEND_REAL="${SEND_REAL:-false}"

if [[ -z "$CKPT" ]]; then
  echo "Dùng: $0 <checkpoint_dir> [--dry-run]" >&2
  exit 1
fi
if [[ ! -f "$EVAL_SCRIPT" ]]; then
  echo "LỖI: không thấy eval script: $EVAL_SCRIPT" >&2
  exit 1
fi

cat <<EOF
==> Eval trên G1
    checkpoint     : $CKPT
    dataset        : $REPO_ID
    arm/ee         : $ARM / $EE
    frequency      : $EVAL_FREQ Hz
    send_real_robot: $SEND_REAL   $( [[ "$SEND_REAL" == "true" ]] && echo "‼ SẼ GỬI LỆNH RA ROBOT THẬT" )
EOF

CMD=(python "$EVAL_SCRIPT"
  --policy.path="$CKPT"
  --repo_id="$REPO_ID"
  --root=""
  --episodes=0
  --frequency="$EVAL_FREQ"
  --arm="$ARM"
  --ee="$EE"
  --visualization=true
  --send_real_robot="$SEND_REAL")

echo
echo "Lệnh: conda run -n $CONDA_ENV ${CMD[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: không chạy)"
  exit 0
fi

if [[ "$SEND_REAL" == "true" ]]; then
  read -r -p "‼ SEND_REAL=true — robot sẽ chuyển động. Đã an toàn? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Huỷ."; exit 0; }
fi

conda run -n "$CONDA_ENV" "${CMD[@]}"
