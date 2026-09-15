# Quy trình

Tất cả script nằm ở `scripts/`, đọc cấu hình chung từ `config.env`. Mọi bước nặng chạy trong conda env
`tv` (đã cài lerobot 0.4.1 + torch 2.3.0). ACT train **hoàn toàn local** trên card 16GB — không cần cloud.

## Đường chính: ACT (local)

```bash
# 1. Gom 5 bộ data đã chọn vào staging/ (symlink, không copy)
scripts/00_stage_raw_data.sh

# 2. Soát chất lượng data thô (L_ring=0, head-cam đứng hình, số camera)
scripts/check_dataset.py staging

# 3. Convert gộp -> LeRobot dataset  (đọc kỹ cảnh báo mìn camera trước!)
scripts/01_convert_to_lerobot.sh --dry-run   # xem lệnh
scripts/01_convert_to_lerobot.sh             # chạy thật

# 4. Train ACT (local, card 16GB). Chỉnh batch/step nếu cần.
scripts/02_train_act.sh --dry-run
ACT_BATCH_SIZE=8 ACT_STEPS=100000 scripts/02_train_act.sh

# 5a. Đẩy checkpoint lên HF Hub (private) + dọn đĩa
scripts/push_checkpoint_to_hub.sh outputs/act_pick_bottle/checkpoints/<step>/pretrained_model --delete-local

# 5b. Eval trên robot thật (mặc định KHÔNG gửi lệnh ra robot)
scripts/03_eval_g1.sh outputs/act_pick_bottle/checkpoints/<step>/pretrained_model
SEND_REAL=true scripts/03_eval_g1.sh <checkpoint>   # chỉ khi đã an toàn + trực e-stop
```

Mỗi script `.sh` đều có `--dry-run` để in lệnh mà không thực thi — dùng để kiểm tra trước.

## Vì sao ACT chứ không phải GR00T

Task này cực hẹp và cố định (1 chai, 1 vòng, 1 bàn, tương phản đen-trắng cao, 3 camera cố định). Đây đúng
là kịch bản ACT/ALOHA mạnh nhất; lợi thế generalize của VLA pretrain gần như không dùng tới. Ngoài ra card
16GB **không đủ** finetune GR00T (cần 40–80GB). Xem `docs/superpowers/specs/` để biết chi tiết quyết định.

## Nhánh nâng cấp (tùy chọn — chưa làm)

Chỉ cân nhắc khi cần robot xử lý nhiều loại chai / nhiều môi trường / nghe lệnh ngôn ngữ:

- **GR00T N1.5** (đã tích hợp trong lerobot): đổi `--policy.type=act` thành `--policy.type=groot`
  `--policy.tune_diffusion_model=false`. Cần cài `flash_attn` (env `tv` hiện chưa có) và **GPU cloud
  40–80GB** — không train được trên card local. Dataset dùng lại được (cùng LeRobot format).
- **GR00T N1.7 / Isaac-GR00T**: mới hơn, cần thêm repo + env riêng + converter schema khác (state dim
  132). Xem CLAUDE.md.

Trong cả hai trường hợp, quy trình data (bước 1–3) giữ nguyên; chỉ đổi bước train (chạy trên cloud) rồi
kéo checkpoint về qua HF Hub.
