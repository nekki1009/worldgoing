"""Bound the Blender prop build and prove existing character/horse sources unchanged."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime

ROOT=Path(__file__).resolve().parents[2]
PROTECTED=[ROOT/"project.godot",ROOT/"assets/3D/Horse.blend"]
PROTECTED+=list((ROOT/"assets/mounts/horse").glob("standard_horse_pack.*"))
PROTECTED+=list((ROOT/"assets/characters/human/q35").glob("standard_anime_*_character_pack.glb"))
PROTECTED+=list(ROOT.glob("*.csproj"))


def hashes():
    return {str(p.relative_to(ROOT)):hashlib.file_digest(p.open("rb"),"sha256").hexdigest() for p in PROTECTED}


def main():
    directory=ROOT/"output/logistics_vehicles_v1"/datetime.now().strftime("%Y%m%d_%H%M%S")
    directory.mkdir(parents=True,exist_ok=True)
    before=hashes()
    command=[str(ROOT/".tools/blender-4.2.22-windows-x64/blender.exe"),"--background",
        "--python-exit-code","1","--python",str(ROOT/"scripts/tools/blender/build_logistics_vehicles.py")]
    environment=os.environ.copy()
    environment["BLENDER_USER_RESOURCES"]=str(ROOT/".godot-temp/blender-user-resources")
    result={"command":command,"timeout_seconds":180,"before":before}
    try:
        with (directory/"blender.log").open("w",encoding="utf-8") as stream:
            run=subprocess.run(command,cwd=ROOT,env=environment,stdout=stream,stderr=subprocess.STDOUT,timeout=180)
        result["exit_code"]=run.returncode
    except subprocess.TimeoutExpired:
        result["exit_code"]=124
        result["failure"]="Blender exceeded 180 seconds; child terminated by subprocess.run"
    result["after"]=hashes()
    result["protected_unchanged"]=result["before"]==result["after"]
    result["pass"]=result["exit_code"]==0 and result["protected_unchanged"]
    (directory/"result.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print("LOGISTICS SOURCE", "PASS" if result["pass"] else "FAIL",directory,flush=True)
    return 0 if result["pass"] else 1


if __name__=="__main__":
    sys.exit(main())
