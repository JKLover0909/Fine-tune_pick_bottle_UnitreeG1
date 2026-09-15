# Thiết kế: Khung repo train ACT cho task "chai vào vòng" trên Unitree G1

Ngày: 2026-09-14 (sửa 2026-09-15: chuyển sang ACT-first sau khi khảo sát dữ liệu thật)
Trạng thái: Đã duyệt, đang triển khai scaffold

## 1. Mục tiêu

Dựng khung (scaffold) cho repo `Fine-tune_pick_bottle_UnitreeG1`. Repo làm **đúng một việc**: huấn luyện
một policy cho Unitree G1 thực hiện task **cầm chai (quấn băng keo đen, nắp xanh) đưa vào vòng dây đen
trên mặt bàn tròn trắng**, dùng dữ liệu teleop + 3 camera đã thu sẵn.

Repo này là **lớp điều phối mỏng ("sổ tay + nút bấm")** gọi sang các repo/công cụ đã có; nó KHÔNG viết
lại code train, convert hay thu dữ liệu.

## 2. Quyết định chính (đã chốt)

- **Policy: ACT** (Action Chunking Transformer), train **from scratch, hoàn toàn local** trên card 16GB.
  KHÔNG dùng GR00T/cloud cho giai đoạn này.
- **Lý do**: task cực kỳ hẹp và cố định (1 chai, 1 vòng, 1 bàn, tương phản đen-trắng cao, 3 camera cố
  định). Đây đúng là kịch bản ACT/ALOHA giỏi nhất; lợi thế generalize của VLA pretrain gần như bị lãng
  phí ở đây. Khoảng cách chất lượng so với GR00T co lại rất nhiều trên single-task cố định.
- **GR00T N1.5/N1.7 + cloud** trở thành **nhánh nâng cấp tùy chọn** — chỉ làm nếu sau này cần robot xử
  lý nhiều loại chai / nhiều môi trường / nghe lệnh ngôn ngữ.

## 3. Bối cảnh đã khảo sát (2026-09-14/15)

**Các repo đã tồn tại trên máy (repo này KHÔNG tạo lại):**
- `/home/jkl/Projects/Humanoid/xr_teleoperate` — thu teleop. Env conda `tv`. Chứa data thô ở
  `teleop/utils/data/`.
- `/home/jkl/Projects/Humanoid/unitree_lerobot` (branch `hungvd`) — convert + train + eval. Env `tv`.
  - Convert: `unitree_lerobot/utils/convert_unitree_json_to_lerobot.py`
  - Train (mọi policy): `unitree_lerobot/lerobot/src/lerobot/scripts/lerobot_train.py` (có sẵn ACT,
    Diffusion, Pi0, Pi05, GR00T).
  - Eval robot thật: `unitree_lerobot/eval_robot/eval_g1.py`
- Env `tv` đã cài `lerobot 0.4.1`, `unitree-lerobot 0.3.0`, `torch 2.3.0`. **Chưa có `flash_attn`** (chỉ
  cần cho GR00T, không cần cho ACT).

**Dữ liệu thô** (`xr_teleoperate/teleop/utils/data/`, tổng 12 bộ / 87 ep / ~15GB). Tất cả cùng schema:
30fps, ảnh 640×480, 3 camera (`color_0`=head, `color_1`=cổ tay trái, `color_2`=cổ tay phải),
state/action 26 chiều = left_arm(7)+right_arm(7)+left_ee(6)+right_ee(6). Cả 3 buổi thu (11/08, 11/09,
14/09) **dùng chung một setup vật lý** (đã kiểm tra bằng ảnh head-cam).

**64 episode dùng được** (cùng task "pick place bottle" + cùng setup):

| Bộ raw | Episode | Trạng thái |
|---|---|---|
| pick_bottle_0914_2 | 21 | raw |
| place_bottle_0911_2 | 16 | raw |
| place_bottle_test1 | 11 | đã convert → `local/place_bottle_test1` |
| pick_bottle_0914_1 | 10 | raw |
| place_bottle_0911 | 6 | raw |
| **Tổng** | **64** | |

**Loại ra:** `pick_bottle` (goal thật = "pick up the cube", vật thể khác), `open_bottle_test1/2/3` (task
mở nắp), các bản `pick_bottle-test1/2/3` (1-2 ep lẻ).

**Phần cứng:** RTX 4070 Ti Super 16GB (đủ train ACT), i7-14700K, 31GB RAM, **94GB đĩa trống** (ràng buộc
thật; conda envs đã chiếm ~63GB, HF cache ~13GB).

## 4. Rủi ro / "mìn" đã phát hiện (phải ghi rõ, không im lặng)

1. **Camera mapping sai trong `Unitree_G1_Inspire_3Cam`**: data thô có 3 cam (`color_0/1/2`) nhưng config
   trong `unitree_lerobot/.../constants.py` khai báo 4 cam và map `color_1→cam_right_high` (sai — thực
   tế `color_1` là cổ tay trái). Cần xác minh/sửa mapping ở repo `unitree_lerobot` **trước khi convert
   thật**. Repo này KHÔNG tự sửa constants.py — chỉ cảnh báo và ghi vào docs.
2. **Khớp `L_ring` (ngón áp út tay trái) luôn ≈ 0.000** trên dữ liệu hiện có.
3. **Head cam (`color_0`) thỉnh thoảng đứng hình** (frame lặp y hệt liên tiếp).
4. **Đa dạng vị trí vật thể còn ít** — khi thu thêm nên rải vị trí chai/vòng.

## 5. Kiến trúc & luồng

```
[xr_teleoperate/teleop/utils/data/*]   raw JSON (12 bộ) — repo khác
        │
        ▼  00_stage_raw_data.sh: symlink 5 bộ đã chọn vào 1 thư mục staging
staging/pick_place_bottle/{pick_bottle_0914_2, ...}
        │
        ▼  check_dataset.py: soát L_ring=0, head-cam đứng hình, số camera/episode, số frame
        │
        ▼  01_convert_to_lerobot.sh: convert_unitree_json_to_lerobot.py (--robot_type Unitree_G1_Inspire_3Cam)
~/.cache/huggingface/lerobot/local/pick_place_bottle   (LeRobot v3.0, 26-dim, 3 cam)
        │
        ▼  02_train_act.sh: lerobot_train.py --policy.type=act  (env tv, card 16GB)
outputs/act_pick_bottle/checkpoints/...
        │
        ├─▶ push_checkpoint_to_hub.sh: đẩy checkpoint lên HF Hub (private), dọn local
        └─▶ 03_eval_g1.sh: eval_g1.py trên robot thật
```

Điểm mấu chốt: `convert_unitree_json_to_lerobot.py` glob `raw-dir/*/*` (task-dir/episode) và **gộp mọi
task-dir con thành một dataset**. Nên để gộp 5 bộ, ta tạo một thư mục staging chỉ chứa symlink tới 5 bộ
đã chọn, rồi convert **một lần** → một dataset hợp nhất. Không trỏ thẳng `--raw-dir` vào thư mục data
gốc (sẽ nuốt cả bộ cube/open_bottle).

## 6. Cấu trúc thư mục

```
Fine-tune_pick_bottle_UnitreeG1/
├── CLAUDE.md
├── README.md
├── .gitignore                     # bỏ outputs/, staging/, __pycache__, wandb/
├── config.env                     # biến dùng chung (đường dẫn repo, env, repo_id, robot_type, DATASETS, HF repo)
├── scripts/
│   ├── 00_stage_raw_data.sh       # symlink 5 bộ đã chọn → staging/
│   ├── check_dataset.py           # soát chất lượng data thô (chạy trước convert)
│   ├── 01_convert_to_lerobot.sh   # convert staging → local/pick_place_bottle
│   ├── 02_train_act.sh            # train ACT local (env tv)
│   ├── 03_eval_g1.sh              # eval trên robot thật
│   └── push_checkpoint_to_hub.sh  # push checkpoint → HF Hub, dọn local
├── docs/
│   ├── dataset.md                 # 12 bộ raw, 64 ep dùng được, các mìn đã biết, cách thu thêm
│   └── workflow.md                # quy trình đầy đủ + nhánh nâng cấp GR00T/cloud (tùy chọn)
└── outputs/                       # gitignore — checkpoint tạm trước khi push Hub
    └── .gitkeep
```

## 7. Đặc tả từng thành phần

### 7.1 `config.env`
Nguồn biến chung mà mọi script source: `UNITREE_LEROBOT_DIR`, `XR_TELEOP_DIR`, `CONDA_ENV=tv`,
`REPO_ID=local/pick_place_bottle`, `ROBOT_TYPE=Unitree_G1_Inspire_3Cam`, danh sách `DATASETS` (5 bộ),
`HF_REPO` (đích push, để trống chờ người dùng điền), `OUTPUT_DIR`.

### 7.2 `scripts/00_stage_raw_data.sh`
Tạo `staging/pick_place_bottle/` chứa symlink tới đúng 5 bộ trong `DATASETS`. In cảnh báo nếu bộ nào
thiếu. Không copy (tiết kiệm 94GB đĩa).

### 7.3 `scripts/check_dataset.py`
- Nhận đường dẫn staging (hoặc 1 bộ raw). Nạp `data.json` từng episode. In tóm tắt: số episode, số frame,
  fps, số camera thực có, dims state/action, goal text.
- **Cảnh báo** (không tự sửa):
  1. Cột state/action nào có phương sai ≈ 0 xuyên suốt (bắt lỗi `L_ring`=0 và tương tự).
  2. Head cam (`color_0`) đứng hình: đếm cặp frame liên tiếp trùng byte-hash quá ngưỡng.
  3. Số camera/episode ≠ 3, hoặc thiếu `color_3` mà config lại map 4 cam (cảnh báo mìn #1).
- Exit code khác 0 nếu có cảnh báo nghiêm trọng → có thể dùng làm cổng chặn trong `01_convert`.
- Chỉ phụ thuộc thư viện chuẩn + `numpy` (không cần import lerobot → chạy được cả ngoài env `tv`).

### 7.4 `scripts/01_convert_to_lerobot.sh`
Kích hoạt env `tv`, chạy `convert_unitree_json_to_lerobot.py --raw-dir staging/... --repo-id $REPO_ID
--robot_type $ROBOT_TYPE` (không `--push_to_hub` — giữ local). In cảnh báo về mìn camera mapping trước
khi chạy, yêu cầu xác nhận. Có cờ dry-run in lệnh mà không chạy.

### 7.5 `scripts/02_train_act.sh`
`cd $UNITREE_LEROBOT_DIR/unitree_lerobot/lerobot` rồi `lerobot_train.py --dataset.repo_id=$REPO_ID
--policy.type=act --policy.push_to_hub=false --output_dir=<repo>/outputs/act_pick_bottle
--job_name=act_pick_bottle`. Tham số batch/step đặt qua biến, mặc định hợp lý cho 16GB. Có dry-run.

### 7.6 `scripts/03_eval_g1.sh`
Gọi `eval_g1.py` với `--policy.path=<checkpoint>`, `--repo_id=$REPO_ID`, `--arm=G1_29`, `--ee=inspire1`
(hoặc biến thể FTP đang dùng — ghi chú để người dùng chỉnh), `--frequency=30`. In cảnh báo an toàn robot
(`--send_real_robot` mặc định false).

### 7.7 `scripts/push_checkpoint_to_hub.sh`
Nhận đường dẫn checkpoint + `HF_REPO` (private), dùng `hf upload`/`huggingface-cli`. Hỏi xác nhận trước
khi (tùy chọn) xóa bản local để giải phóng đĩa.

### 7.8 `docs/dataset.md`, `docs/workflow.md`
Ghi lại toàn bộ khảo sát: bảng 12 bộ, 64 ep dùng được, các mìn, cách thu thêm (trỏ về teleop repo), và
nhánh nâng cấp GR00T/cloud (giữ để tham khảo, không phải đường chính).

### 7.9 Cập nhật `CLAUDE.md`
Đổi phần model decision + intended workflow sang **ACT-first**, thêm mục bối cảnh repo/dataset đã khảo
sát, giữ GR00T như nhánh tùy chọn.

## 8. Kiểm thử

- `check_dataset.py` phải chạy thật trên staging và in tóm tắt đúng + phát hiện được `L_ring`=0 (kiểm thử
  E2E chính của scaffold).
- Các `.sh`: `bash -n` sạch, và chạy chế độ dry-run in đúng lệnh (không chạy convert/train thật trong
  phạm vi scaffold).
- `config.env` source được không lỗi.

## 9. Ngoài phạm vi

- Chạy convert/train/eval thật (người dùng sẽ chạy sau khi review scaffold).
- Sửa `constants.py` hay bất cứ file nào trong `unitree_lerobot`/`xr_teleoperate`.
- GR00T/cloud/N1.7, SmolVLA, whole-body (`UNITREE_G1_SONIC`).
- Logic tự động sửa/cắt dữ liệu lỗi (chỉ cảnh báo, việc sửa nằm ở data_editor của teleop repo).
