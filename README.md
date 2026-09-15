# Fine-tune_pick_bottle_UnitreeG1

Train một policy **ACT** cho robot **Unitree G1** thực hiện task: cầm chai (quấn băng keo đen, nắp xanh)
bằng hai tay và đưa vào **vòng dây đen** trên **bàn tròn trắng**, dùng dữ liệu teleop + 3 camera đã thu sẵn.

Repo này là **lớp điều phối mỏng** — nó gọi sang các repo/công cụ đã có trên máy, KHÔNG viết lại code
train/convert/thu dữ liệu:

- `../unitree_lerobot` — convert data + `lerobot_train.py` (có sẵn ACT) + `eval_g1.py`.
- `../xr_teleoperate` — thu teleop, chứa data thô.
- Env conda `tv` — đã cài `lerobot 0.4.1`, `torch 2.3.0`.

Đường dẫn cụ thể cấu hình trong [`config.env`](config.env).

## Vì sao ACT (không phải GR00T)

Task cực hẹp, môi trường cố định, tương phản cao → đúng thế mạnh của ACT, và train được **local trên card
16GB**. GR00T cần GPU 40–80GB (cloud) và lợi thế của nó gần như không dùng tới ở task này. GR00T/cloud là
nhánh nâng cấp tùy chọn — xem [`docs/workflow.md`](docs/workflow.md).

## Bắt đầu nhanh

```bash
scripts/00_stage_raw_data.sh                 # gom 5 bộ data đã chọn (symlink)
scripts/check_dataset.py staging             # soát chất lượng data thô
scripts/01_convert_to_lerobot.sh             # convert -> LeRobot dataset
scripts/02_train_act.sh                       # train ACT (local, 16GB)
scripts/03_eval_g1.sh <checkpoint>            # eval trên robot (mặc định không gửi lệnh)
```

Chi tiết: [`docs/workflow.md`](docs/workflow.md) · Dữ liệu & các "mìn" đã biết:
[`docs/dataset.md`](docs/dataset.md) · Quyết định thiết kế:
[`docs/superpowers/specs/`](docs/superpowers/specs/).

## Lưu ý

- **94GB đĩa trống** — checkpoint đẩy lên HF Hub rồi dọn local (`push_checkpoint_to_hub.sh`), không commit.
- **Tay trái đứng yên là chủ ý** (giữ wrist-cam nhìn bàn) — không phải lỗi khớp. Xem `docs/dataset.md`.
- Mỗi script `.sh` có `--dry-run` để xem lệnh trước khi chạy thật.
