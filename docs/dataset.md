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

## Mìn đã biết (phải xử lý trước/khi convert)

1. **Camera mapping sai trong `Unitree_G1_Inspire_3Cam`**
   `unitree_lerobot/unitree_lerobot/utils/constants.py` khai báo config này với **4 camera** và map
   `color_0→cam_left_high, color_1→cam_right_high, color_2→cam_left_wrist, color_3→cam_right_wrist`.
   Nhưng data thô chỉ có **3 camera** (`color_0/1/2`) và `color_1` thực tế là **cổ tay trái**, không phải
   `cam_right_high`. → Xác minh/sửa `camera_to_image_key` trong constants.py cho khớp 3 camera thật
   **trước khi convert thật**. Repo này KHÔNG tự sửa file đó (ngoài phạm vi); `01_convert_to_lerobot.sh`
   sẽ in cảnh báo này.

2. **Khớp `L_ring` (ngón áp út tay trái) luôn ≈ 0.000** — `check_dataset.py` phát hiện qua phương sai cột.

3. **Head cam (`color_0`) thỉnh thoảng đứng hình** — `check_dataset.py` phát hiện qua hash frame trùng.

4. **Đa dạng vị trí vật thể còn ít** — khi thu thêm nên rải vị trí chai/vòng khắp vùng làm việc để ACT
   không overfit vào một chỗ.

## Thu thêm dữ liệu

Dùng repo teleop (không thuộc repo này):
- Thu: `xr_teleoperate/teleop/teleop_hand_and_arm.py` (env `tv`).
- Cắt/xoá episode lỗi: `unitree_lerobot/data_editor/data_editor_EN.py`.
- Sắp xếp lại tên: `unitree_lerobot/unitree_lerobot/utils/sort_and_rename_folders.py`.

## Định dạng LeRobot sau convert

`~/.cache/huggingface/lerobot/local/pick_place_bottle` — LeRobot v3.0 (parquet + ảnh). `observation.state`
và `action` shape `[26]`; camera key theo `camera_to_image_key` (xem mìn #1). Đây là đầu vào cho
`02_train_act.sh`.
