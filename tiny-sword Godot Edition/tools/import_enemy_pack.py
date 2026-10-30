"""One-shot importer: copies Enemy Pack PNGs into the project and generates
SpriteFrames .tres resources matching the format of resources/units/*_frames.tres.

Frames are sliced as square cells (frame size = image height), which matches
every Tiny Swords sprite strip.
"""
import shutil
import struct
from pathlib import Path

SRC = Path(r"C:\Users\rabi2\Downloads\Tiny Swords (Enemy Pack)\Tiny Swords (Enemy Pack)\Enemy Pack\Enemies")
PROJECT = Path(r"c:\Users\rabi2\OneDrive\Documents\tiny-sword")
ASSET_DST = PROJECT / "assets" / "enemies"
FRAMES_DST = PROJECT / "resources" / "enemies"

# enemy key -> (asset subfolder, {animation: source filename})
ENEMIES = {
    "bear": ("Caveborn/Bear", {"idle": "Bear_Idle.png", "run": "Bear_Run.png", "attack": "Bear_Attack.png"}),
    "lizard": ("Caveborn/Lizard", {"idle": "Lizard_Idle.png", "run": "Lizard_Run.png", "attack": "Lizard_Attack.png"}),
    "snake": ("Caveborn/Snake", {"idle": "Snake_Idle.png", "run": "Snake_Run.png", "attack": "Snake_Attack.png"}),
    "spider": ("Caveborn/Spider", {"idle": "Spider_Idle.png", "run": "Spider_Run.png", "attack": "Spider_Attack.png"}),
    "turtle": ("Caveborn/Turtle", {"idle": "Turtle_Idle.png", "run": "Turtle_Walk.png", "attack": "Turtle_Attack.png"}),
    "gnoll": ("Gnoll", {"idle": "Gnoll_Idle.png", "run": "Gnoll_Walk.png", "attack": "Gnoll_Throw.png"}),
    "gnome": ("Gnome", {"idle": "Gnome_Idle.png", "run": "Gnome_Run.png", "attack": "Gnome_Attack.png"}),
    "hex_shaman": ("Goblin Raiders/Hex Shaman", {"idle": "Hex Shaman_Idle.png", "run": "Hex Shaman_Run.png", "attack": "Hex Shaman_Attack.png"}),
    "pig_rider": ("Goblin Raiders/Pig Rider Spear Goblin", {"idle": "Pig Rider_Idle.png", "run": "Pig Rider_Run.png", "attack": "Pig Rider_Attack.png"}),
    "spear_goblin": ("Goblin Raiders/Spear Goblin", {"idle": "Spear Goblin_Idle.png", "run": "Spear Goblin_Run.png", "attack": "Spear Goblin_Attack Fast.png"}),
    "torch_goblin": ("Goblin Raiders/Torch Goblin", {"idle": "Torch Goblin_Idle.png", "run": "Torch Goblin_Run.png", "attack": "Torch Goblin_Attack.png"}),
    "minotaur": ("Minotaur", {"idle": "Minotaur_Idle.png", "run": "Minotaur_Walk.png", "attack": "Minotaur_Attack.png"}),
    "panda": ("Panda", {"idle": "Panda_Idle.png", "run": "Panda_Run.png", "attack": "Panda_Attack.png"}),
    "bomb_fish": ("Pirate Fish/Bomb Fish", {"idle": "Bomb Fish_Idle.png", "run": "Bomb Fish_Run.png", "attack": "Bomb Fish_Shoot.png"}),
    "harpoon_shark": ("Pirate Fish/Harpoon Shark", {"idle": "Harpoon Shark_Idle.png", "run": "Harpoon Shark_Run.png", "attack": "Harpoon Shark_Throw.png"}),
    "paddle_shark": ("Pirate Fish/Paddle Shark", {"idle": "Paddle Shark_Idle.png", "run": "Paddle Shark_Run.png", "attack": "Paddle Shark_Attack.png"}),
    "skull": ("Skull", {"idle": "Skull_Idle.png", "run": "Skull_Run.png", "attack": "Skull_Attack.png"}),
    "thief": ("Thief", {"idle": "Thief_Idle.png", "run": "Thief_Run.png", "attack": "Thief_Attack.png"}),
    "troll": ("Troll", {"idle": "Troll_Idle.png", "run": "Troll_Walk.png", "attack": "Troll_Attack.png"}),
}

# Static props copied as-is (no SpriteFrames needed).
PROPS = [
    "Goblin Raiders/Goblin Hut/Goblin Hut.png",
    "Goblin Raiders/Wooden Fence/Wooden Fence_64x64 tile.png",
    "Caveborn/Cave/Cave_Idle.png",
    "Root Troll/Dead Tree.png",
    "Root Troll/Bones_01.png",
    "Root Troll/Bones_02.png",
    "Root Troll/Bones_03.png",
    "Root Troll/Skull Spike_01.png",
    "Root Troll/Skull Spike_02.png",
    "Pirate Fish/Fish Hut/Fish Hut.png",
    "Pirate Fish/Pirate Tower/Pirate Tower_Water.png",
    "Pirate Fish/Boat/Boat_Idle.png",
]

ANIM_SPEED = {"idle": 8.0, "run": 10.0, "attack": 10.0}


def png_size(path: Path) -> tuple[int, int]:
    with open(path, "rb") as f:
        header = f.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    w, h = struct.unpack(">II", header[16:24])
    return w, h


def copy_asset(rel: str) -> Path:
    src = SRC / rel
    dst = ASSET_DST / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst


def res_path(dst: Path) -> str:
    return "res://" + dst.relative_to(PROJECT).as_posix()


def build_frames_tres(key: str, folder: str, anims: dict) -> None:
    ext_lines = []
    sub_lines = []
    anim_blocks = []
    tex_ids = {}
    sub_n = 0

    for i, (anim, fname) in enumerate(anims.items(), start=1):
        rel = f"{folder}/{fname}"
        dst = copy_asset(rel)
        w, h = png_size(dst)
        count = max(1, w // h)
        tex_id = f"tex_{i}"
        tex_ids[anim] = tex_id
        ext_lines.append(f'[ext_resource type="Texture2D" path="{res_path(dst)}" id="{tex_id}"]')

        frame_refs = []
        for f_idx in range(count):
            sub_n += 1
            sid = f"AtlasTexture_{sub_n}"
            sub_lines.append(
                f'[sub_resource type="AtlasTexture" id="{sid}"]\n'
                f'atlas = ExtResource("{tex_id}")\n'
                f"region = Rect2({f_idx * h}, 0, {h}, {h})\n"
            )
            frame_refs.append(sid)

        frames_json = ", ".join(
            '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % sid for sid in frame_refs
        )
        anim_blocks.append(
            '{\n"frames": [%s],\n"loop": true,\n"name": &"%s",\n"speed": %s\n}'
            % (frames_json, anim, ANIM_SPEED.get(anim, 10.0))
        )

    load_steps = len(ext_lines) + sub_n + 1
    out = []
    out.append(f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3]')
    out.append("")
    out.extend(ext_lines)
    out.append("")
    out.extend(sub_lines)
    out.append("[resource]")
    out.append("animations = [%s]" % ", ".join(anim_blocks))
    out.append("")

    FRAMES_DST.mkdir(parents=True, exist_ok=True)
    tres = FRAMES_DST / f"{key}_frames.tres"
    tres.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"{key}: {tres.name} ({sub_n} frames)")


def main() -> None:
    for key, (folder, anims) in ENEMIES.items():
        build_frames_tres(key, folder, anims)
    for rel in PROPS:
        copy_asset(rel)
        print(f"prop: {rel}")
    print("Done.")


if __name__ == "__main__":
    main()
