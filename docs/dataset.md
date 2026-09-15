# Dữ liệu

## Task

Cầm chai (quấn băng keo đen, nắp xanh) bằng hai tay, đưa vào **vòng dây đen** đặt trên **bàn tròn trắng**.
3 camera: 1 head cam (có sẵn trên G1) + 2 wrist cam. Tay: Inspire dexterous (6 khớp/tay). Nền: sàn phòng.

## Data thô

Nằm ở `xr_teleoperate/teleop/utils/data/` (repo khác, không thuộc repo này). Định dạng Unitree JSON:
mỗi episode có `colors/` (3 ảnh/frame: `color_0`=head, `color_1`=cổ tay trái, `color_2`=cổ tay phải),
`depths/`, `audios/`, `data.json`. Chung schema: 30fps, 640×480, state/action **26 chiều** =
left_arm(7) + right_arm(7) + left_ee(6) + right_ee(6).

Tổng 12 bộ / 87 episode / ~15GB. **64 episode dùng được** cho task này (cùng goal "pick place bottle",
cùng setup vật lý — đã kiểm tra bằng head-cam ở cả 3 buổi thu 11/08, 11/09, 14/09):

| Bộ raw | Episode | Ghi chú |
|---|---:|---|
| pick_bottle_0914_2 | 21 | mới nhất, nhiều nhất |
| place_bottle_0911_2 | 16 | |
| place_bottle_test1 | 11 | đã convert sẵn → `local/place_bottle_test1` |
| pick_bottle_0914_1 | 10 | |
| place_bottle_0911 | 6 | |
| **Tổng dùng được** | **64** | |

**Loại ra** (đừng trộn vào — làm nhiễu policy):
- `pick_bottle` (8 ep) — goal thật là **"pick up the cube"**, vật thể khác. Tên thư mục gây hiểu nhầm.
- `open_bottle_test1/2/3` (10 ep) — task **mở nắp chai**, động tác khác hẳn.
- `pick_bottle-test1/2/3` (5 ep lẻ) — mỗi bộ 1-2 ep, bỏ cho sạch.

Danh sách 5 bộ dùng được nằm ở biến `DATASETS` trong `config.env`.

## Chủ ý thiết kế (KHÔNG phải lỗi)

- **Tay TRÁI cố tình giữ yên**: tay trái được giữ ở một pose cố định để **wrist-cam trái nhìn cố định
  xuống bàn** (dùng như một camera bàn). Vì vậy các khớp ngón tay trái (`left_ee`, idx 14-19) có phương
  sai ≈ 0 trong từng episode là **bình thường**. `check_dataset.py` báo nhóm này ở mức `info`, không coi
  là lỗi. Tay PHẢI mới là tay thao tác chai — nếu khớp tay phải đứng yên thì đó mới là bất thường.
- **Camera mapping đã đúng**: `G1_INSPIRE_3CAM_CONFIG` trong `unitree_lerobot/.../constants.py` map 3
  camera: `color_0→cam_left_high` (head), `color_1→cam_left_wrist`, `color_2→cam_right_wrist` — khớp với
  dataset `local/place_bottle_test1` đã convert. Không cần sửa. (Trước đó từng nhầm với một config Dex1
  4-cam khác trong cùng file — đã xác minh lại.)

## Vấn đề thật cần chú ý

1. **Head cam (`color_0`) đôi khi drop/đứng frame** — `check_dataset.py` phát hiện qua hash frame trùng.
   Mức nhẹ (<20%) là drop lẻ tẻ, thường chấp nhận được; ≥20% mới coi là nặng và nên cắt episode đó.

2. **Đa dạng vị trí vật thể còn ít** — khi thu thêm nên rải vị trí chai/vòng khắp vùng làm việc để ACT
   không overfit vào một chỗ.

## Thu thêm dữ liệu

Dùng repo teleop (không thuộc repo này):
- Thu: `xr_teleoperate/teleop/teleop_hand_and_arm.py` (env `tv`).
- Cắt/xoá episode lỗi: `unitree_lerobot/data_editor/data_editor_EN.py`.
- Sắp xếp lại tên: `unitree_lerobot/unitree_lerobot/utils/sort_and_rename_folders.py`.

## Định dạng LeRobot sau convert

`~/.cache/huggingface/lerobot/local/pick_place_bottle` — LeRobot v3.0 (parquet + ảnh). `observation.state`
và `action` shape `[26]`; 3 camera key: `cam_left_high` (head), `cam_left_wrist`, `cam_right_wrist`. Đây
là đầu vào cho `02_train_act.sh`.
