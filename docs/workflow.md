# Quy trình

Tất cả script nằm ở `scripts/`, đọc cấu hình chung từ `config.env`. Mọi bước nặng chạy trong conda env
`tv` (đã cài lerobot 0.4.1 + torch 2.3.0). ACT train **hoàn toàn local** trên card 16GB — không cần cloud.

## Bẫy môi trường đã gặp (đã xử trong scaffold)

Chạy convert/train một lần thực tế (2026-09-15) lộ ra 3 bẫy, đều liên quan version torch 2.3.0 của env `tv`:

1. **`torchvision` ở user site-packages (`~/.local`) lệch version** → lỗi
   `module 'torch.library' has no attribute 'register_fake'` khi import. Khắc phục: `config.env` đặt
   `export PYTHONNOUSERSITE=1` (bẫy này cũng ghi trong `xr_teleoperate/Useme.md`).
2. **`torchcodec` (backend decode video mặc định) không tương thích torch 2.3.0** (cùng lỗi
   `register_fake`). Khắc phục: `02_train_act.sh` truyền `--dataset.video_backend=pyav` (env có `av 16.1.0`).
3. **Process convert treo sau khi ghi xong** (multiprocessing không join). Dataset vẫn hợp lệ; chỉ cần
   `pkill -9 -f convert_unitree_json_to_lerobot` sau khi `meta/info.json` đã có đủ `total_episodes`.

Tốc độ train đo được: **~0.20s/step @ batch 8** (data loading không phải nút thắt). 50k step ≈ 2-3 giờ.

## Đường chính: ACT (local)

```bash
# 1. Gom 5 bộ data đã chọn vào staging/ (symlink, không copy)
scripts/00_stage_raw_data.sh

# 2. Soát chất lượng data thô (L_ring=0, head-cam đứng hình, số camera)
scripts/check_dataset.py staging

# 3. Convert gộp -> LeRobot dataset
scripts/01_convert_to_lerobot.sh --dry-run   # xem lệnh
scripts/01_convert_to_lerobot.sh             # chạy thật

# 4. Train ACT (local, card 16GB). Chỉnh batch/step nếu cần.
scripts/02_train_act.sh --dry-run
ACT_BATCH_SIZE=8 ACT_STEPS=100000 scripts/02_train_act.sh

# 5a. Đẩy checkpoint lên HF Hub (private) + dọn đĩa
scripts/push_checkpoint_to_hub.sh outputs/act_pick_bottle/checkpoints/<step>/pretrained_model --delete-local

# 5b. Kiểm tra policy OFFLINE (không cần robot) — so action dự đoán vs demo, xuất metrics + plot
scripts/04_infer_offline.sh                          # checkpoint 50k, episode 0
scripts/04_infer_offline.sh <checkpoint> <episode>   # tuỳ chọn khác

# 5c. Eval trên robot thật (mặc định KHÔNG gửi lệnh ra robot)
scripts/03_eval_g1.sh outputs/act_pick_bottle/checkpoints/<step>/pretrained_model
SEND_REAL=true scripts/03_eval_g1.sh <checkpoint>   # chỉ khi đã an toàn + trực e-stop
```

`04_infer_offline.sh` bọc `unitree_lerobot/eval_robot/offline_infer_dataset.py` (đã sửa thêm cờ
`--video-backend`, mặc định `pyav`, để tránh lỗi torchcodec với torch 2.3.0). Kết quả ở
`outputs/offline_infer/latest/` (metrics_summary.json, metrics_by_dim.csv, plots/, predictions.npz).
Đây chỉ đo độ khớp demo (open-loop) — success rate thật vẫn phải eval closed-loop trên robot (5c).

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
