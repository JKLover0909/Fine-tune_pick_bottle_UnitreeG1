#!/usr/bin/env python3
"""Soát chất lượng dữ liệu teleop thô (Unitree JSON) TRƯỚC khi convert sang LeRobot.

Chạy được bằng Python chuẩn + numpy, KHÔNG cần env `tv`/lerobot (nhẹ, chạy nhanh).
Chỉ CẢNH BÁO, không sửa/xoá gì — việc cắt/sửa episode lỗi nằm ở data_editor của repo teleop.

Kiểm tra:
  1. Cột state/action có phương sai ~0 xuyên suốt  -> bắt lỗi khớp kẹt (vd L_ring luôn = 0).
  2. Head cam (color_0) đứng hình  -> đếm cặp frame liên tiếp trùng hệt nhau (theo hash file).
  3. Số camera mỗi episode  -> cảnh báo nếu != 3 (data setup này phải là 3: head + 2 cổ tay).

Dùng:
  python check_dataset.py <đường_dẫn>            # thư mục staging (task/episode) hoặc 1 bộ (chứa episode_*)
  python check_dataset.py <đường_dẫn> --max-ep 5 # giới hạn số episode mỗi bộ (soát nhanh)

Exit code: 0 nếu sạch, 1 nếu có cảnh báo nghiêm trọng (khớp kẹt / sai số camera).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np

# 26 chiều state/action = ghép theo thứ tự convert dùng.
# left_arm.qpos(7) + right_arm.qpos(7) + left_ee.qpos(6) + right_ee.qpos(6)
INSPIRE_JOINTS = ["pinky", "ring", "middle", "index", "thumb_bend", "thumb_rot"]
STATE_PARTS = [
    ("left_arm", 7),
    ("right_arm", 7),
    ("left_ee", 6),
    ("right_ee", 6),
]
ZERO_VAR_EPS = 1e-8  # ngưỡng coi một cột là "không đổi"


def column_labels() -> list[str]:
    labels: list[str] = []
    for part, n in STATE_PARTS:
        for i in range(n):
            if part.endswith("_ee"):
                side = "L" if part.startswith("left") else "R"
                labels.append(f"{part}[{i}]={side}_{INSPIRE_JOINTS[i]}")
            else:
                labels.append(f"{part}[{i}]")
    return labels


def find_episode_dirs(root: Path) -> list[Path]:
    """Tìm mọi thư mục episode chứa data.json, sâu tối đa 2 cấp (staging: task/episode)."""
    eps: list[Path] = []
    if (root / "data.json").exists():
        return [root]
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        if (child / "data.json").exists():
            eps.append(child)
        else:
            for gc in sorted(child.iterdir()):
                if gc.is_dir() and (gc / "data.json").exists():
                    eps.append(gc)
    return eps


def stack_vectors(frames: list[dict], key: str) -> np.ndarray:
    """Ghép các part qpos thành ma trận (n_frame, 26). Bỏ frame thiếu part."""
    rows = []
    for fr in frames:
        blk = fr.get(key, {})
        vec: list[float] = []
        ok = True
        for part, n in STATE_PARTS:
            q = blk.get(part, {}).get("qpos", [])
            if len(q) != n:
                ok = False
                break
            vec.extend(q)
        if ok:
            rows.append(vec)
    return np.asarray(rows, dtype=np.float64) if rows else np.empty((0, 26))


def color0_hashes(ep_dir: Path, frames: list[dict]) -> list[str]:
    hashes: list[str] = []
    for fr in frames:
        rel = fr.get("colors", {}).get("color_0")
        if not rel:
            continue
        p = ep_dir / rel
        if not p.exists():
            continue
        hashes.append(hashlib.md5(p.read_bytes()).hexdigest())
    return hashes


def check_episode(ep_dir: Path) -> dict:
    d = json.loads((ep_dir / "data.json").read_text(encoding="utf-8"))
    frames = d.get("data", [])
    n_cam = len(frames[0].get("colors", {})) if frames else 0

    states = stack_vectors(frames, "states")
    zero_cols: list[int] = []
    if states.shape[0] > 1:
        var = states.var(axis=0)
        zero_cols = [i for i, v in enumerate(var) if v < ZERO_VAR_EPS]

    hashes = color0_hashes(ep_dir, frames)
    frozen_pairs = sum(1 for a, b in zip(hashes, hashes[1:]) if a == b)

    return {
        "n_frames": len(frames),
        "n_cam": n_cam,
        "zero_cols": zero_cols,
        "frozen_pairs": frozen_pairs,
        "n_color0": len(hashes),
        "goal": d.get("text", {}).get("goal", "?"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="Thư mục staging hoặc 1 bộ dataset raw")
    ap.add_argument("--max-ep", type=int, default=0, help="Giới hạn số episode soát mỗi lần (0 = tất cả)")
    ap.add_argument("--frozen-frac", type=float, default=0.02,
                    help="Ngưỡng cảnh báo head-cam đứng hình (tỉ lệ cặp frame trùng)")
    args = ap.parse_args()

    root = Path(args.path).expanduser().resolve()
    if not root.exists():
        print(f"LỖI: không tồn tại: {root}", file=sys.stderr)
        return 1

    eps = find_episode_dirs(root)
    if args.max_ep > 0:
        eps = eps[: args.max_ep]
    if not eps:
        print(f"LỖI: không tìm thấy episode nào (data.json) dưới {root}", file=sys.stderr)
        return 1

    labels = column_labels()
    print(f"==> Soát {len(eps)} episode dưới {root}\n")

    zero_col_counter: dict[int, int] = {}
    bad_cam = 0
    frozen_eps: list[str] = []
    total_frames = 0

    for ep in eps:
        try:
            r = check_episode(ep)
        except Exception as e:  # noqa: BLE001 — báo lỗi episode nhưng tiếp tục soát
            print(f"  [LỖI đọc] {ep.name}: {e}", file=sys.stderr)
            continue
        total_frames += r["n_frames"]
        flags = []
        if r["n_cam"] != 3:
            bad_cam += 1
            flags.append(f"CAM={r['n_cam']}(≠3)")
        for c in r["zero_cols"]:
            zero_col_counter[c] = zero_col_counter.get(c, 0) + 1
        frac = r["frozen_pairs"] / max(1, r["n_color0"] - 1)
        if frac >= args.frozen_frac:
            frozen_eps.append(ep.name)
            flags.append(f"FROZEN={frac:.0%}")
        tag = ("  ⚠ " + " ".join(flags)) if flags else ""
        rel = ep.relative_to(root) if root in ep.parents or root == ep.parent else ep.name
        print(f"  {str(rel):40} {r['n_frames']:>4}f  cam={r['n_cam']}  goal={r['goal']}{tag}")

    print("\n" + "=" * 60)
    print(f"Tổng: {len(eps)} episode, {total_frames} frame")

    warn = False
    if zero_col_counter:
        warn = True
        print("\n⚠ Cột state KẸT (phương sai ~0) — khả năng khớp hỏng (tên khớp chỉ là suy đoán; index mới chuẩn):")
        for c in sorted(zero_col_counter):
            print(f"    idx {c:>2} {labels[c]:24} kẹt ở {zero_col_counter[c]}/{len(eps)} episode")
    if bad_cam:
        warn = True
        print(f"\n⚠ {bad_cam}/{len(eps)} episode có số camera ≠ 3.")
    if frozen_eps:
        warn = True
        print(f"\n⚠ {len(frozen_eps)} episode nghi head-cam đứng hình: {', '.join(frozen_eps[:10])}"
              + (" ..." if len(frozen_eps) > 10 else ""))

    # Nhắc mìn camera-mapping (không phát hiện được từ data, nhưng luôn nhắc)
    print("\nGHI NHỚ: robot_type 'Unitree_G1_Inspire_3Cam' map 4 camera (color_0..3) nhưng data chỉ có 3.")
    print("         Xác minh mapping color_1 = cổ tay TRÁI trong constants.py trước khi convert.")

    if warn:
        print("\n=> CÓ CẢNH BÁO. Xem lại / cắt episode lỗi (data_editor của teleop repo) trước khi convert.")
        return 1
    print("\n=> Data sạch (theo các kiểm tra tự động). Có thể convert.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
