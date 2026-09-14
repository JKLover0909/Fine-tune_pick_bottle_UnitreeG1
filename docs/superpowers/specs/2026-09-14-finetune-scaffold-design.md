# Thiết kế: Khung repo finetune GR00T cho task nhặt chai Unitree G1

Ngày: 2026-09-14
Trạng thái: Đã duyệt thiết kế, chuẩn bị lập kế hoạch triển khai

## 1. Mục tiêu

Dựng khung (scaffold) cho repo `Fine-tune_pick_bottle_UnitreeG1`. Repo này làm **đúng một việc**:
finetune một VLA policy (GR00T N1.5) cho robot Unitree G1 thực hiện task nhặt chai, dựa trên dữ liệu
teleop + camera đã được thu thập và convert sẵn bởi các repo khác trên máy.

Phạm vi lần này là **chỉ dựng khung**: cấu trúc thư mục, README, config với giá trị mặc định hợp lý,
và script có phần khung + TODO rõ ràng cho logic còn thiếu. Không viết logic filter dữ liệu chi tiết,
không chạy train thật, không đụng vào các repo khác.

## 2. Bối cảnh (đã khảo sát trên máy, 2026-09-14)

Các thành phần đã tồn tại sẵn, repo này KHÔNG tạo lại:

- **Thu thập dữ liệu teleop**: `/home/jkl/Projects/Humanoid/xr_teleoperate` (fork của
  unitreerobotics/xr_teleoperate). Chạy trong conda env `tv`. Script chính:
  `teleop/teleop_hand_and_arm.py`.
- **Convert sang LeRobot dataset**: `/home/jkl/Projects/Humanoid/unitree_lerobot` (fork của
  unitreerobotics/unitree_lerobot, branch `hungvd`). Chạy trong conda env `tv`. Script chính:
  `unitree_lerobot/utils/convert_unitree_json_to_lerobot.py`.
- **Package lerobot + policy GR00T**: đã cài sẵn trong env `tv` (`lerobot 0.4.1`,
  `unitree-lerobot 0.3.0`, `torch 2.3.0`). Policy `groot` có sẵn tại
  `unitree_lerobot/unitree_lerobot/lerobot/src/lerobot/policies/groot/`, mặc định trỏ tới checkpoint
  `nvidia/GR00T-N1.5-3B` (xem `configuration_groot.py`).
- **Dataset đã convert**: `~/.cache/huggingface/lerobot/local/place_bottle_test1` (5.8 GB, 11 episode,
  5521 frame, fps 30, `robot_type = "Unitree_G1_Inspire_3Cam"`). `observation.state`/`action` shape
  `[26]` = 14 khớp tay (7 trái + 7 phải) + 12 khớp Inspire (6 trái + 6 phải). 3 camera:
  `cam_left_high`, `cam_left_wrist`, `cam_right_wrist` (480×640×3).

Phần cứng dev: RTX 4070 Ti Super 16GB, i7-14700K, 31GB RAM, **chỉ còn 94GB đĩa trống**. Conda envs hiện
đã chiếm ~63GB, HF cache ~13GB.

## 3. Quyết định thiết kế (đã chốt với người dùng)

| Quyết định | Lựa chọn | Lý do |
|---|---|---|
| Phạm vi task | Tabletop 2 tay (tag `UNITREE_G1`) | Đơn giản để chạy hết pipeline trước; dữ liệu hiện có là place/pick bottle trên bàn |
| Phiên bản model | GR00T **N1.5** qua lerobot có sẵn | Không cần cài thêm, không tốn thêm đĩa cho env/submodule mới. N1.7 để sau |
| Liên kết repo ngoài | Không nhúng submodule | Repo này chỉ điều phối; gọi thẳng vào env `tv` và các repo đã có |
| Môi trường Python | Tái dùng env `tv` | Đã có sẵn lerobot + groot, không tạo env mới (tiết kiệm đĩa) |
| Lưu checkpoint | Push lên HF Hub (private) sau mỗi lần train, dọn local | Đĩa chỉ còn 94GB; đồng thời tiện kéo checkpoint train từ cloud về |

Ràng buộc VRAM: 16GB **không đủ** finetune GR00T N1.5 (cần 40-80GB, GPU A100/L40 cloud). 16GB đủ cho
inference và đủ để train ACT/smoke-test local. Đây là lý do pipeline tách "validate local" khỏi
"finetune cloud".

**Lưu ý kỹ thuật đã phát hiện**: env `tv` hiện **chưa cài `flash_attn`**, mà GR00T N1.5 yêu cầu flash
attention để chạy. Cần xử lý (cài `flash-attn`, hoặc để phần train GR00T chỉ chạy trên cloud nơi cài
flash-attn). Scaffold phải ghi rõ điều này chứ không giả định đã có.

## 4. Kiến trúc

Repo là **lớp điều phối finetune** mỏng. Không chứa code thu thập/convert dữ liệu. Luồng:

```
[unitree_lerobot / xr_teleoperate]  (repo khác — ngoài phạm vi)
        │  thu teleop → convert
        ▼
~/.cache/huggingface/lerobot/local/<dataset>   (LeRobot v3.0, dim 26, 3 cam)
        │
        ▼
scripts/check_dataset.py        ── cảnh báo lỗi chất lượng đã biết, KHÔNG tự sửa
        │
        ▼
scripts/train_local.sh          ── ACT baseline, chạy env tv trên card 16GB → xác thực pipeline
        │
        ▼
scripts/train_groot_smoke_test.sh ── GR00T vài step/batch nhỏ, chỉ kiểm tra config+shape chạy được
        │
        ▼
scripts/train_groot_cloud.sh    ── finetune GR00T N1.5 đầy đủ, chạy trên cloud GPU 40-80GB
        │
        ▼
scripts/push_checkpoint_to_hub.sh ── đẩy checkpoint lên HF Hub private, dọn outputs/ local
```

## 5. Cấu trúc thư mục

```
Fine-tune_pick_bottle_UnitreeG1/
├── CLAUDE.md                          # đã có — cập nhật thêm bối cảnh repo đã khảo sát
├── README.md                          # tổng quan + quickstart
├── .gitignore                         # bỏ qua outputs/, __pycache__, *.pyc, wandb/
├── configs/
│   ├── act_pick_bottle.yaml           # baseline ACT — validate pipeline
│   └── groot_n1_5_pick_bottle.yaml    # config finetune GR00T N1.5
├── scripts/
│   ├── check_dataset.py               # kiểm tra dataset trước khi train
│   ├── train_local.sh                 # train ACT local (env tv)
│   ├── train_groot_smoke_test.sh      # smoke test GR00T local
│   ├── train_groot_cloud.sh           # finetune GR00T đầy đủ trên cloud
│   └── push_checkpoint_to_hub.sh      # push checkpoint → HF Hub, dọn local
├── docs/
│   ├── dataset.md                     # dataset hiện có, vấn đề chất lượng, cách lấy thêm data
│   └── cloud_setup.md                 # các bước thuê GPU cloud và chạy train ở đó
└── outputs/                           # gitignore — checkpoint tạm trước khi push Hub
    └── .gitkeep
```

## 6. Đặc tả từng thành phần

### 6.1 `scripts/check_dataset.py`
- **Việc làm**: nạp một LeRobot dataset (theo `repo_id`, mặc định `local/place_bottle_test1`), in tóm tắt
  (số episode, frame, fps, danh sách feature + shape, danh sách camera), và **cảnh báo** hai lỗi chất
  lượng đã biết:
  1. Khớp `L_ring` (ngón áp út tay trái) có giá trị luôn ≈ 0.000 trên toàn episode.
  2. Camera `cam_left_high` có đoạn đứng hình (frame lặp lại y hệt liên tiếp).
- **Không** tự sửa/xóa dữ liệu — chỉ báo cáo để người dùng quyết định. Việc sửa dữ liệu gốc thuộc repo
  `unitree_lerobot`.
- **Phụ thuộc**: `lerobot` (env `tv`), `numpy`.
- **Exit code**: 0 nếu sạch, khác 0 (hoặc cảnh báo nổi bật) nếu phát hiện lỗi — để có thể chèn vào
  script train như một cổng chặn.
- Phạm vi scaffold: khung script chạy được + đọc metadata + in tóm tắt là bắt buộc; hai kiểm tra chất
  lượng cụ thể được viết ở mức khung có TODO nếu logic dò cần tinh chỉnh, nhưng nên cố gắng hiện thực
  luôn vì thuật toán đơn giản (so sánh phương sai theo cột / so sánh frame liền kề).

### 6.2 `configs/act_pick_bottle.yaml`
- Config train ACT trên dataset hiện có, batch đủ nhỏ để vừa 16GB (ví dụ 8-16), số step vừa phải để
  xác thực pipeline (không cần hội tụ tốt). Ghi rõ đây là baseline validate, không phải policy production.

### 6.3 `configs/groot_n1_5_pick_bottle.yaml`
- Config finetune GR00T N1.5: `base_model_path: nvidia/GR00T-N1.5-3B`, batch 32, ~10k step, trỏ vào
  dataset `local/place_bottle_test1`. Đánh dấu rõ các tham số nào chỉ chạy được trên GPU 40-80GB.

### 6.4 `scripts/train_local.sh`
- Kích hoạt env `tv`, gọi lệnh train ACT của lerobot với config `act_pick_bottle.yaml`. Chạy được trên
  card 16GB. Mục đích: xác thực dataset → pipeline sạch trước khi tốn tiền cloud.

### 6.5 `scripts/train_groot_smoke_test.sh`
- Chạy GR00T N1.5 với vài step + batch cực nhỏ trên card local, **chỉ** để kiểm tra config/shape/khớp
  nối chạy được (không kỳ vọng vừa VRAM cho train thật). Ghi chú rõ nếu OOM là bình thường, và cần
  `flash_attn`.

### 6.6 `scripts/train_groot_cloud.sh`
- Lệnh train GR00T N1.5 đầy đủ (batch 32, 10k step) để chạy trên máy cloud GPU thuê. Có biến môi trường
  cho `DATASET_REPO_ID`, `OUTPUT_DIR`, `HF_TOKEN`. Kèm chú thích các bước setup env trên cloud (trỏ tới
  `docs/cloud_setup.md`).

### 6.7 `scripts/push_checkpoint_to_hub.sh`
- Nhận đường dẫn checkpoint local + tên repo HF đích (private), dùng `huggingface-cli`/`hf` để upload,
  rồi (tùy chọn) xóa bản local để giải phóng đĩa. Cảnh báo trước khi xóa.

### 6.8 `docs/dataset.md`
- Ghi: đường dẫn dataset hiện có, schema (dim 26, 3 cam, tay Inspire), các vấn đề chất lượng đã biết
  (L_ring=0, cam_left_high đứng hình, đa dạng vị trí vật thể còn ít), và cách thu thêm dữ liệu (trỏ
  ngược về `unitree_lerobot` + `xr_teleoperate`, kèm lệnh mẫu).

### 6.9 `docs/cloud_setup.md`
- Các bước dựng env trên cloud GPU (cài lerobot + groot + flash-attn), đồng bộ dataset lên cloud (hoặc
  qua HF Hub), chạy `train_groot_cloud.sh`, và kéo checkpoint về qua HF Hub.

### 6.10 Cập nhật `CLAUDE.md`
- Thêm mục "Bối cảnh repo đã khảo sát" (đường dẫn các repo, env `tv`, dataset hiện có, vấn đề flash_attn),
  và cập nhật phần model decision để phản ánh quyết định dùng N1.5 qua lerobot có sẵn (thay vì N1.7) cho
  giai đoạn đầu — vẫn giữ ghi chú N1.7 là bước nâng cấp tương lai.

## 7. Xử lý lỗi & chất lượng dữ liệu

- Vấn đề chất lượng dữ liệu đã biết được **phát hiện** ở `check_dataset.py` nhưng **sửa** ở repo
  `unitree_lerobot` — repo này không sửa dữ liệu gốc.
- `flash_attn` chưa có trong env `tv`: ghi rõ trong `train_groot_smoke_test.sh` và `docs/cloud_setup.md`;
  không giả định đã cài.
- Ràng buộc đĩa 94GB: `.gitignore` loại `outputs/`; `push_checkpoint_to_hub.sh` dọn local sau khi push.

## 8. Kiểm thử

- `check_dataset.py` phải chạy được thật trên `local/place_bottle_test1` và in ra tóm tắt đúng (11
  episode, dim 26, 3 cam). Đây là kiểm thử end-to-end chính của scaffold.
- Các script `.sh` chỉ cần kiểm tra cú pháp (`bash -n`) và chạy tới bước in usage/echo lệnh (dùng cờ
  dry-run hoặc `echo` lệnh trước khi thực thi) — không chạy train thật trong phạm vi scaffold.
- Config YAML phải parse được.

## 9. Ngoài phạm vi (không làm lần này)

- Nâng cấp lên GR00T N1.7 / Isaac-GR00T submodule.
- Logic filter/sửa dữ liệu tự động.
- Thu thập thêm dữ liệu teleop.
- Chạy finetune thật (local hoặc cloud).
- Deploy/inference checkpoint lên robot.
- Whole-body control (`UNITREE_G1_SONIC`).
