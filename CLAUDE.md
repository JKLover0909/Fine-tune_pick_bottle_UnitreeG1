# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Thin orchestration repo for one task: train an **ACT** policy for a Unitree G1 to pick a bottle (wrapped
in black tape, blue cap) with both hands and place it into a black cable ring on a white round table,
using pre-collected teleop + 3-camera data. Scaffold was built 2026-09-15 (ACT-first). The repo does NOT
reimplement training/conversion/collection — it calls into repos already on the machine.

Design decision + full survey: `docs/superpowers/specs/2026-09-14-finetune-scaffold-design.md`.
Workflow: `docs/workflow.md`. Data + known landmines: `docs/dataset.md`. Shared paths: `config.env`.

## Operating rules for Claude Code in this repo

- Always reply to the user in Vietnamese.
- Do not create, edit, or scaffold any code/config files in this repo until the user explicitly gives
  permission to start. Research, hardware surveys, and updates to this CLAUDE.md are fine without asking;
  writing actual project code is not.

## Surveyed context (repos already on this machine — this repo calls them, never edits them)

- `/home/jkl/Projects/Humanoid/unitree_lerobot` (branch `hungvd`) — convert + train + eval.
  - Convert: `unitree_lerobot/utils/convert_unitree_json_to_lerobot.py` (globs `raw-dir/*/*`, so it
    merges every task-dir under raw-dir into one dataset — see `scripts/00_stage_raw_data.sh`).
  - Train (all policies incl. ACT/GR00T): `unitree_lerobot/lerobot/src/lerobot/scripts/lerobot_train.py`.
  - Eval on real robot: `unitree_lerobot/eval_robot/eval_g1.py`.
- `/home/jkl/Projects/Humanoid/xr_teleoperate` — teleop collection; raw JSON data under
  `teleop/utils/data/` (12 datasets, 87 episodes; 64 usable for this task — see `docs/dataset.md`).
- Conda env `tv` — has `lerobot 0.4.1`, `torch 2.3.0`. **No `flash_attn`** (only GR00T needs it; ACT
  does not).
- One dataset already converted: `~/.cache/huggingface/lerobot/local/place_bottle_test1`.

**Known landmine**: robot_type `Unitree_G1_Inspire_3Cam` in `unitree_lerobot/.../constants.py` declares 4
cameras and maps `color_1→cam_right_high`, but raw data has 3 cameras and `color_1` is actually the LEFT
wrist. Verify/fix that mapping before trusting a real conversion. Do not edit constants.py from here.

## Goal

Train ACT locally on the pre-collected pick-place-bottle data (camera + teleop), eval on the G1.

## Local hardware (surveyed 2026-09-14)

- GPU: RTX 4070 Ti Super, 16376 MiB VRAM (Ada/sm_89, compute cap 8.9), driver 580.173.02, CUDA 13.0
  (driver) / nvcc 12.8 installed.
- CPU: Intel i7-14700K, 28 threads.
- RAM: 31 GiB total (~18 GiB available at survey time).
- Disk: 94 GB free on `/` (468 GB volume, 79% used). This is a real constraint, not just VRAM — LeRobot
  video datasets, conda/venv environments (PyTorch etc. easily 5–10 GB each), and GR00T checkpoints
  (multi-GB each) can fill this quickly. Plan to prune old checkpoints/envs or attach external storage
  before collecting large datasets.
- OS: Ubuntu 24.04.4 LTS, kernel 6.8. Python 3.12.3 (system), conda available (miniconda3).
- 16GB is enough to train ACT and to run GR00T *inference*, but NOT to finetune GR00T (needs 40–80GB).

## Model decision — ACT-first

**Chosen: ACT** (Action Chunking Transformer), trained from scratch, fully local on the 16GB card.

Why ACT and not a pretrained VLA here: the task is extremely narrow and fixed (one bottle, one ring, one
table, high black-on-white contrast, 3 fixed cameras). That is exactly where ACT/ALOHA is strongest; a
pretrained VLA's generalization advantage is mostly wasted, and the quality gap to GR00T collapses on a
single fixed task. ACT also trains comfortably on 16GB, no cloud needed. ~64 usable episodes is plenty
(ALOHA tasks often need ~50). ACT has no language conditioning and is single-task — fine here.

GR00T / cloud is an **optional upgrade branch**, only if the robot later needs many bottle types / many
environments / language commands. Reference (not the current path):
- **GR00T N1.5** is already bundled in the `tv` env's lerobot (`--policy.type=groot`, base
  `nvidia/GR00T-N1.5-3B`). Reuses the same LeRobot dataset. Needs `flash_attn` (not installed) and a
  40–80GB cloud GPU.
- **GR00T N1.7 / Isaac-GR00T**: newer, separate repo + env + a different converter (state dim 132). Not
  set up here.
- SmolVLA, UnifoLM-WLA-1.0, π₀/π₀.₅ were considered and deprioritized (see the design spec).

## Workflow (see docs/workflow.md for exact commands)

1. `scripts/00_stage_raw_data.sh` — symlink the 5 chosen raw datasets into `staging/`.
2. `scripts/check_dataset.py staging` — flag known data issues (L_ring stuck at 0, head-cam freezes,
   camera count).
3. `scripts/01_convert_to_lerobot.sh` — merge-convert to `local/pick_place_bottle` (heed the camera
   landmine above).
4. `scripts/02_train_act.sh` — train ACT locally on the 16GB card.
5. `scripts/push_checkpoint_to_hub.sh` — push checkpoint to HF Hub (private), prune local (94GB disk).
6. `scripts/03_eval_g1.sh` — eval on the real G1 (defaults to not sending commands to the robot).
