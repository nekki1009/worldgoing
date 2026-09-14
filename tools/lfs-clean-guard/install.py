"""Install only a tested bundle; preserve a repository-local config rollback record."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--verified-root", type=Path, required=True)
parser.add_argument("--destination", type=Path, required=True)
args = parser.parse_args()
project = Path(__file__).resolve().parents[2]
bundle = Path(__file__).resolve().parent / "bin" / "Release" / "net8.0"
hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(bundle.glob("lfs-clean-guard.*"))
          if path.suffix in (".exe", ".dll", ".json")}
assert len(hashes) == 4, "Missing runtime bundle files"
for case in ("compatibility", "interruption", "integration"):
    result = json.loads((args.verified_root / (case + "-result.json")).read_text())
    assert result["status"] == "PASS" and result["bundle_sha256"] == hashes


def git(*arguments, allowed=(0,)):
    result = subprocess.run(["git", "config", "--local", *arguments], cwd=project,
                            capture_output=True, text=True, encoding="utf-8", timeout=10)
    if result.returncode not in allowed:
        raise RuntimeError(result.stderr)
    return result.stdout.rstrip("\n")


original = {name: git("--get-all", name, allowed=(0, 1)).splitlines()
            for name in ("filter.lfs.clean", "filter.lfs.process")}
assert original == {"filter.lfs.clean": ["git-lfs clean -- %f"],
                    "filter.lfs.process": ["git-lfs filter-process"]}, "Filter configuration changed; review before installing"
destination = args.destination.resolve()
destination.mkdir(parents=True, exist_ok=False)
for name, digest in hashes.items():
    shutil.copy2(bundle / name, destination / name)
    assert hashlib.sha256((destination / name).read_bytes()).hexdigest() == digest
command = '"' + (destination / "lfs-clean-guard.exe").as_posix() + '"'
replacement = {"filter.lfs.clean": command, "filter.lfs.process": command + " --filter-process"}
record = {"project": str(project), "original": original, "installed": replacement,
          "bundle_sha256": hashes, "status": "prepared"}
record_path = destination / "installation.json"
record_path.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
try:
    for name, value in replacement.items():
        git(name, value)
        assert git("--get", name) == value
except BaseException:
    for name, values in original.items():
        git("--unset-all", name, allowed=(0, 5))
        for value in values:
            git("--add", name, value)
    raise
record["status"] = "active"
record_path.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(record, ensure_ascii=False))
