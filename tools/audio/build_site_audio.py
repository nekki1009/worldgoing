"""Build the authorized P0/P1 WAV slice from the preserved CC0 preview sources.

No network, game edits, Godot, or overwrites. Use the configured bundled Python.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
PREVIEW = ROOT / "output/audio_preview_20261008"
ASSETS = ROOT / "assets/audio"
RECEIPT = ROOT / "output/audio_implementation_20261008"
RATE = 44100
TIMES = {"walk": {"fast": 0.38, "slow": 0.50}, "run": {"fast": 0.18, "slow": 0.26}}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    # Reuse the already acquired decoder; do not install a dependency or ship it.
    sys.path.insert(0, str(PREVIEW / "tools/soundfile"))
    import numpy as np
    import soundfile as sf

    manifest = json.loads((PREVIEW / "manifest.json").read_text(encoding="utf-8"))
    sources = {item["id"]: item for item in manifest["entries"]}
    assert len(sources) == 31 and not manifest["errors"]
    assert not ASSETS.exists(), "Refuse to overwrite an existing formal audio directory"
    assert not (RECEIPT / "material_receipt.json").exists(), "Preserve the completed material receipt"
    ASSETS.mkdir(parents=True)
    RECEIPT.mkdir(parents=True, exist_ok=True)
    used, decoded, outputs, sounds = {}, {}, [], {}

    def source(identity):
        if identity in decoded:
            return decoded[identity]
        item = sources[identity]
        path = (PREVIEW / item["file"]).resolve()
        assert path.is_relative_to(PREVIEW / "clips")
        assert item["license"] == "CC0 1.0" and digest(path) == item["sha256"]
        with sf.SoundFile(path) as reader:
            rate = reader.samplerate
            start = round(float(item["preview_start"]) * rate)
            end = min(len(reader), round(float(item["preview_end"]) * rate))
            assert 0 <= start < end and rate > 0
            reader.seek(start)
            data = reader.read(end - start, dtype="float32", always_2d=True).mean(axis=1)
        assert data.size and np.isfinite(data).all()
        if rate != RATE:
            # ponytail: linear conversion for provisional foley; replace with master-rate files after audition.
            data = np.interp(np.arange(round(len(data) * RATE / rate)) * rate / RATE,
                             np.arange(len(data)), data).astype("float32")
        used[identity] = {key: item[key] for key in ["id", "creator", "source_url", "source_title", "license", "license_url", "quality", "sha256", "file"]}
        used[identity].update({"selected_start": item["preview_start"], "selected_end": item["preview_end"], "source_rate": rate})
        decoded[identity] = data
        return data

    def fade(data, milliseconds=3):
        data = np.asarray(data, dtype="float32").copy()
        size = min(round(RATE * milliseconds / 1000), len(data) // 2)
        if size:
            data[:size] *= np.linspace(0, 1, size)
            data[-size:] *= np.linspace(1, 0, size)
        return data

    def attack(identity, seconds, offset=0):
        data = source(identity)
        offset = min(round(offset * RATE), max(0, len(data) - 1))
        tail = data[offset:]
        crossings = np.flatnonzero(np.abs(tail) >= max(float(np.max(np.abs(tail))) * 0.10, 0.001))
        begin = offset + (max(0, int(crossings[0]) - round(0.002 * RATE)) if len(crossings) else 0)
        body = data[begin:begin + round(seconds * RATE)]
        return fade(body)

    def beat_segment(identity, duration, offset=0):
        body = attack(identity, min(0.15, duration * 0.39), offset)
        out = np.zeros(round(duration * RATE), dtype="float32")
        for index, gain in [(0, 1.0), (round(duration * RATE / 2), 0.88)]:
            size = min(len(body), len(out) - index)
            out[index:index + size] += body[:size] * gain
        return out

    def mix(*parts):
        out = np.zeros(max(len(data) for data, gain in parts), dtype="float32")
        for data, gain in parts:
            out[:len(data)] += data * gain
        return out

    def publish(name, data, ids, modification, *, provisional=True, loop=False, **metadata):
        data = np.asarray(data, dtype="float32").copy()
        assert len(data) > 0 and np.isfinite(data).all()
        peak = float(np.max(np.abs(data)))
        assert peak > 0.00001
        data *= 0.45 / peak
        if not loop:
            data = fade(data)
        path = ASSETS / (name + ".wav")
        assert not path.exists()
        sf.write(path, data, RATE, subtype="PCM_16")
        restored, actual_rate = sf.read(path, dtype="float32", always_2d=True)
        assert actual_rate == RATE and restored.shape == (len(data), 1)
        assert np.isfinite(restored).all() and float(np.max(np.abs(restored))) <= 0.451
        with sf.SoundFile(path) as reader:
            assert reader.subtype == "PCM_16" and reader.channels == 1
        duration = len(restored) / RATE
        asset = {"path": "res://assets/audio/" + path.name, "duration": duration,
                 "provisional": provisional, "loop": loop, **metadata}
        record = {**asset, "file": "assets/audio/" + path.name, "sha256": digest(path),
                  "bytes": path.stat().st_size, "peak": float(np.max(np.abs(restored))),
                  "rms": float(np.sqrt(np.mean(restored[:, 0] ** 2))), "sources": ids,
                  "modification": modification, "license": "CC0 1.0"}
        if loop:
            record["loop_seam_delta"] = abs(float(restored[0, 0]) - float(restored[-1, 0]))
        outputs.append(record)
        return asset

    def kind(name, variants, group, priority, volume_db):
        sounds[name] = {"variants": variants, "group": group, "priority": priority, "volume_db": volume_db}

    # Sixteen banks, twenty-four actual files: grass/hard have two variants per bank.
    for surface, identities in {"grass": ["grass_a", "grass_b"], "hard": ["stone_a", "stone_b"],
                                "wood": ["wood_a"], "water": ["fishing_plop"]}.items():
        for locomotion, tempos in TIMES.items():
            variants = []
            for tempo, duration in tempos.items():
                for variation, identity in enumerate(identities, 1):
                    name = f"step_{surface}_{locomotion}_{tempo}_{variation:02}"
                    variants.append(publish(name, beat_segment(identity, duration), [identity],
                        "Extract attack; arrange two beats at 0 and half the segment; mono, normalize to 0.45 peak, 3 ms cuts. Shallow-water beats use fishing-lure splash, not recorded footsteps.",
                        surface=surface, locomotion=locomotion, tempo=tempo, variant=variation, footsteps=2))
            kind(f"step_{surface}_{locomotion}", variants, "footsteps", 20, -14.0)

    hoof = [publish(f"horse_hoof_{index}", beat_segment("horse_hoof", duration, offset), ["horse_hoof"],
                    "Extract two gallop contact attacks into a provisional completed-step segment; not natural walking cadence or a master recording.", footsteps=2)
            for index, (duration, offset) in enumerate([(0.38, 0.2), (0.50, 1.1), (0.18, 2.1)], 1)]
    kind("hoof_walk", hoof, "footsteps", 25, -12.0)
    kind("hoof_run", hoof, "footsteps", 25, -12.0)
    contact = [publish("contact_light", source("metal_light"), ["metal_light"], "Mono/peak normalization of official generic metal impact.", provisional=False),
               publish("contact_heavy", source("metal_heavy"), ["metal_heavy"], "Mono/peak normalization of official generic metal impact.", provisional=False),
               publish("contact_mixed", mix((source("metal_light"), .8), (source("metal_heavy"), .35)), ["metal_light", "metal_heavy"], "Layer generic CC0 metal impacts; provisional weapon-contact foley.")]
    kind("contact", contact, "combat", 60, -8.0)
    shield = [publish("shield_contact_1", mix((source("metal_light"), .8), (attack("plank", .23), .35)), ["metal_light", "plank"], "Layer metal and wood impacts; provisional shield contact, not a recorded shield or validated material match."),
              publish("shield_contact_2", mix((source("metal_heavy"), .65), (attack("plank", .26), .55)), ["metal_heavy", "plank"], "Layer metal and wood impacts; provisional shield contact, not a recorded shield or validated material match.")]
    kind("shield", shield, "combat", 65, -8.0)
    hurt = [publish("hurt_impact_1", source("punch"), ["punch"], "Body-impact feedback only, not human pain or a character voice."),
            publish("hurt_impact_2", np.convolve(source("punch"), np.ones(5) / 5, mode="same"), ["punch"], "Five-sample smoothing of body impact; provisional damage feedback, not human pain or a character voice.")]
    kind("hurt", hurt, "combat", 90, -5.0)
    bow = publish("bow_release_provisional", mix((attack("knife", .25), .35), (attack("belt", .18), .7)), ["knife", "belt"],
                  "Layer blade-swish and belt handling as provisional dry release foley. Not a true bowstring recording; replace after approved source selection.")
    kind("bow", [bow], "projectile", 70, -9.0)
    crossbow = publish("crossbow_release", source("crossbow"), ["crossbow"], "Mono/peak-normalized public low-quality MP3 preview; spring-device foley, not a master or a true crossbow recording.")
    kind("crossbow", [crossbow], "projectile", 70, -9.0)
    baseline = len(outputs)
    assert baseline == 36
    kind("impact_ground", [publish("projectile_ground", attack("stone_a", .105), ["stone_a"], "Concrete foot-contact reused as provisional projectile-to-ground foley; no claim of a real arrow impact.")], "projectile", 55, -10.0)
    kind("impact_wood", [publish("projectile_wood", attack("plank", .3), ["plank"], "Wood impact excerpt as provisional projectile contact, not recorded arrow penetration.")], "projectile", 55, -10.0)
    kind("impact_metal", [publish("projectile_metal", source("metal_light"), ["metal_light"], "Generic metal impact as provisional projectile contact.")], "projectile", 55, -10.0)
    for name, offset, volume_db in [("fire_small", 0, -16.0), ("fire_large", 4, -12.0)]:
        body = source("fire")[round(offset * RATE):round((offset + 6) * RATE)]
        cross = round(.25 * RATE)
        ramp = np.linspace(0, 1, cross)
        body = np.concatenate([body[cross:-cross], body[-cross:] * (1 - ramp) + body[:cross] * ramp])
        assert len(body) == round(5.75 * RATE)
        clip = publish(name, body, ["fire"], "Selected public MP3 excerpt; 250 ms cyclic crossfade; provisional loop, master quality and audible seam not approved.", loop=True)
        kind(name, [clip], "environment", 15 if name == "fire_small" else 40, volume_db)
    extinguish = publish("fire_extinguish", attack("fishing_plop", .25), ["fishing_plop"], "Water splash reused as provisional extinguishing foley, not a real fire-extinguish recording.")
    kind("fire_extinguish", [extinguish], "environment", 30, -12.0)

    assert len(outputs) == 42 and sum(record.get("surface") is not None for record in outputs) == 24
    catalog = {"version": 1, "sample_rate": RATE, "format": "PCM_16 mono WAV", "status": "P0/P1 prepared assets; subjective listening pending",
               "sounds": sounds, "sources": list(used.values()), "baseline_files": baseline,
               "additional_p1_files": len(outputs) - baseline}
    (ASSETS / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    licenses = ASSETS / "licenses"
    licenses.mkdir()
    for filename in ["kenney_impact_License.txt", "kenney_rpg_License.txt"]:
        shutil.copyfile(PREVIEW / "sources" / filename, licenses / filename)
    for item in used.values():
        if "freesound.org" in item["source_url"]:
            sound_id = item["source_url"].rstrip("/").split("/")[-1]
            snapshot = PREVIEW / "sources" / f"freesound_{sound_id}.html"
            assert snapshot.exists()
            shutil.copyfile(snapshot, licenses / snapshot.name)
    receipt = {"date": "2026-10-08", "source_manifest_sha256": digest(PREVIEW / "manifest.json"),
               "builder_sha256": digest(Path(__file__)), "catalog_sha256": digest(ASSETS / "catalog.json"),
               "baseline_files": baseline, "step_files": 24, "step_banks": 16, "other_baseline_files": 12,
               "additional_p1_files": 6, "total_wav_files": len(outputs), "format": "44100 Hz mono PCM16 WAV",
               "dependency": {"numpy": np.__version__, "soundfile": sf.__version__, "decoder": "Existing preview tool; no install or shipping dependency"},
               "initial_probe_failure": "System Python C:/Python314 had no numpy; configured bundled Python used instead. No ffmpeg on PATH.",
               "checks": ["CC0 source hashes", "16 banks/24 two-beat segments", "36 baseline/6 extra files", "finite mono PCM16 readback", "peak <= 0.451", "actual duration for every catalog variant"],
               "subjective_listening": "NOT_RUN", "godot_import": "NOT_RUN", "game_audio_playback": "NOT_RUN",
               "source_warning": "Freesound are low-quality public previews, not masters. Shore's prior decoder warning is preserved in preview records; shore is not used here.",
               "sources": list(used.values()), "outputs": outputs}
    (RECEIPT / "material_receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"baseline": baseline, "step_files": 24, "step_banks": 16, "extra": 6, "total": len(outputs), "catalog_kinds": len(sounds), "wav_bytes": sum(record["bytes"] for record in outputs)}))


if __name__ == "__main__":
    watchdog = threading.Timer(90, lambda: os._exit(124))
    watchdog.daemon = True
    watchdog.start()
    try:
        main()
    finally:
        watchdog.cancel()
