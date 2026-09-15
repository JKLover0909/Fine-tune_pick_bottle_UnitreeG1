#!/usr/bin/env bash
# push_checkpoint_to_hub.sh — đẩy checkpoint đã train lên Hugging Face Hub (private),
# rồi (tuỳ chọn) xoá bản local để giải phóng đĩa (máy chỉ còn ~94GB).
#
# Cần: đã `hf auth login` (hoặc đặt HF_TOKEN) và điền HF_REPO trong config.env.
#
# Dùng:  scripts/push_checkpoint_to_hub.sh <checkpoint_dir> [--delete-local] [--dry-run]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../config.env"

CKPT="${1:-}"
DELETE_LOCAL=0
DRY_RUN=0
for a in "${@:2}"; do
  [[ "$a" == "--delete-local" ]] && DELETE_LOCAL=1
  [[ "$a" == "--dry-run" ]] && DRY_RUN=1
done

if [[ -z "$CKPT" || ! -d "$CKPT" ]]; then
  echo "Dùng: $0 <checkpoint_dir> [--delete-local] [--dry-run]" >&2
  exit 1
fi
if [[ -z "$HF_REPO" ]]; then
  echo "LỖI: chưa đặt HF_REPO trong config.env (vd JKLover0909/act_pick_bottle_g1)." >&2
  exit 1
fi

SIZE=$(du -sh "$CKPT" | cut -f1)
echo "==> Push checkpoint"
echo "    từ   : $CKPT ($SIZE)"
echo "    tới  : $HF_REPO (private)"

CMD=(hf upload "$HF_REPO" "$CKPT" --repo-type=model --private)

echo "Lệnh: conda run -n $CONDA_ENV ${CMD[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: không chạy)"
  exit 0
fi

conda run -n "$CONDA_ENV" "${CMD[@]}"
echo "==> Đã push lên https://huggingface.co/$HF_REPO"

if [[ "$DELETE_LOCAL" -eq 1 ]]; then
  read -r -p "Xoá bản local $CKPT để giải phóng $SIZE? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    rm -rf "$CKPT"
    echo "==> Đã xoá $CKPT"
  fi
fi
