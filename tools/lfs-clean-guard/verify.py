"""Local-only checks; every child has a timeout and all fixtures stay in --root."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("case", choices=["init", "compatibility", "interruption", "integration"])
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--guard", type=Path, required=True)
args = parser.parse_args()
root, guard = args.root.resolve(), args.guard.resolve()
bundle_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(guard.parent.glob("lfs-clean-guard.*"))
                 if path.suffix in (".exe", ".dll", ".json")}
env = os.environ.copy()
for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_OPTIONAL_LOCKS", "GIT_TRACE"):
    env.pop(name, None)


def run(command, data=None, check=True):
    result = subprocess.run(command, input=data, capture_output=True, cwd=root, env=env,
                            timeout=12, creationflags=subprocess.CREATE_NO_WINDOW)
    if check and result.returncode:
        raise AssertionError(f"{command[0]} exit {result.returncode}: {result.stderr.decode(errors='replace')}")
    return result


def git(*arguments):
    return run(["git", *map(str, arguments)]).stdout


def clean(data):
    return run([str(guard)], data).stdout


def object_path(data):
    oid = hashlib.sha256(data).hexdigest()
    return root / "lfs-storage" / "objects" / oid[:2] / oid[2:4] / oid


def no_temps():
    assert not list((root / "lfs-storage" / "tmp").glob("*")), "Orphan temporary file"


started = time.monotonic()
results = []
if args.case == "init":
    root.mkdir(parents=True, exist_ok=False)
    git("init", "-q")
    git("lfs", "install", "--local")
    git("config", "core.autocrlf", "false")
    git("config", "core.quotePath", "false")
    git("config", "core.hooksPath", "NUL")
    git("config", "lfs.storage", root / "lfs-storage")
    (root / "fixture.json").write_text(json.dumps({"bundle_sha256": bundle_hashes}))
    results.append("isolated repository initialized")
else:
    fixture = json.loads((root / "fixture.json").read_text())
    assert fixture["bundle_sha256"] == bundle_hashes, "Runtime bundle changed during verification"

if args.case == "compatibility":
    pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:" + b"a" * 64 + b"\nsize 123\n"
    extended = pointer.replace(b"\noid ", b"\next-0-test sha256:" + b"b" * 64 + b"\noid ")
    cases = [b"", b"\x00small\xff\r\n", b"x" * 1023, b"x" * 1024,
             os.urandom(3 * 1024 * 1024), pointer,
             pointer.replace(b"https://git-lfs.github.com/spec/v1", b"http://git-media.io/v/2"),
             b" \n" + pointer.replace(b"\n", b"\r\n") + b" \n", extended,
             pointer.replace(b"sha256:", b"sha512:"), pointer.ljust(1024, b" ")]
    for index, data in enumerate(cases):
        expected = run(["git", "-c", "lfs.storage=" + str(root / "upstream-lfs-storage"), "lfs", "clean"], data).stdout
        assert clean(data) == expected, f"Pointer compatibility case {index}"
        no_temps()
    results.append(f"{len(cases)} upstream-compatible empty/binary/pointer/boundary cases")
    data = os.urandom(2 * 1024 * 1024)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        outputs = list(pool.map(clean, [data, data]))
    assert outputs[0] == outputs[1]
    assert object_path(data).read_bytes() == data
    no_temps()
    results.append("concurrent identical new objects")
    corrupt_data = b"existing-object-mismatch" * 100
    corrupt_path = object_path(corrupt_data)
    corrupt_path.parent.mkdir(parents=True, exist_ok=True)
    corrupt_path.write_bytes(b"bad")
    failure = run([str(guard)], corrupt_data, check=False)
    assert failure.returncode != 0 and failure.stdout == b""
    assert corrupt_path.read_bytes() == b"bad"
    corrupt_path.unlink()
    no_temps()
    results.append("existing-object mismatch refuses pointer and preserves object")
    git("config", "lfs.extension.test.clean", "unused")
    try:
        rejected = run([str(guard)], b"test", check=False)
        assert rejected.returncode != 0 and rejected.stdout == b""
    finally:
        git("config", "--unset", "lfs.extension.test.clean")
    results.append("custom extension configuration fails closed")

if args.case == "interruption":
    for index in range(8):
        no_temps()
        protocol = index % 2 == 1
        child = subprocess.Popen([str(guard)] + (["--filter-process"] if protocol else []), cwd=root, env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        watchdog = threading.Timer(10, child.kill)
        watchdog.daemon = True
        watchdog.start()
        try:
            def packet(data):
                child.stdin.write(f"{len(data) + 4:04x}".encode() + data)

            def response():
                received = []
                while True:
                    header = child.stdout.read(4)
                    assert len(header) == 4, "Missing protocol response"
                    size = int(header, 16)
                    if size == 0:
                        return received
                    received.append(child.stdout.read(size - 4))

            if protocol:
                packet(b"git-filter-client\n")
                packet(b"version=2\n")
                child.stdin.write(b"0000")
                child.stdin.flush()
                assert response() == [b"git-filter-server\n", b"version=2\n"]
                packet(b"capability=clean\n")
                packet(b"capability=smudge\n")
                child.stdin.write(b"0000")
                child.stdin.flush()
                assert set(response()) == {b"capability=clean\n", b"capability=smudge\n"}
                packet(b"command=clean\n")
                packet(b"pathname=interrupted.blend\n")
                child.stdin.write(b"0000")
                payload = os.urandom(2 * 1024 * 1024)
                for offset in range(0, len(payload), 65516):
                    packet(payload[offset:offset + 65516])
            else:
                child.stdin.write(os.urandom(2 * 1024 * 1024))
            child.stdin.flush()  # Keep input open: the object is deliberately incomplete.
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                temporary = list((root / "lfs-storage" / "tmp").glob("clean-*.tmp"))
                if temporary and temporary[0].stat().st_size > 1024:
                    break
                if child.poll() is not None:
                    raise AssertionError(child.stderr.read().decode(errors="replace"))
                time.sleep(0.01)
            else:
                raise AssertionError("No active temporary file observed")
            child.kill()  # Windows TerminateProcess, no language-level finally block.
            child.wait(timeout=5)
            no_temps()
            assert child.stdout.read() == b""
        finally:
            watchdog.cancel()
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
            child.stdin.close()
            child.stdout.close()
            child.stderr.close()
    results.append("8 forced process terminations (4 direct, 4 Git protocol): zero orphan bytes/files")

if args.case == "integration":
    git("config", "filter.lfs.process", '"' + guard.as_posix() + '" --filter-process')
    git("config", "filter.lfs.clean", '"' + guard.as_posix() + '"')
    (root / ".gitattributes").write_text("*.blend filter=lfs diff=lfs merge=lfs -text\n")
    model = root / "models" / "角色 example.blend"
    model.parent.mkdir(exist_ok=True)
    data = os.urandom(5 * 1024 * 1024)
    model.write_bytes(data)
    second = root / "models" / "second.blend"
    second_data = os.urandom(65536)
    second.write_bytes(second_data)
    relative = model.relative_to(root).as_posix()
    git("add", ".gitattributes", "--", relative, "models/second.blend")
    staged = git("show", ":" + relative)
    assert staged == clean(data)
    assert object_path(data).read_bytes() == data
    assert run(["git-lfs", "smudge"], staged).stdout == data
    model.unlink()
    second.unlink()
    git("checkout-index", "--force", "--", relative, "models/second.blend")
    assert model.read_bytes() == data
    assert second.read_bytes() == second_data
    model.write_bytes(data + b"new revision")
    assert relative.encode() in git("diff", "--no-ext-diff", "--no-textconv", "--numstat", "--", relative)
    no_temps()
    results.append("Git add, indexed pointer, upstream smudge, checkout and modified diff")

    # Both normal streaming and a failed request must leave the long-running protocol sound.
    def pkt(data):
        return f"{len(data) + 4:04x}".encode() + data

    def request(command, path, data):
        return (pkt(b"command=" + command + b"\n") + pkt(b"pathname=" + path + b"\n") + b"0000"
                + b"".join(pkt(data[offset:offset + 65516]) for offset in range(0, len(data), 65516)) + b"0000")

    missing = b"version https://git-lfs.github.com/spec/v1\noid sha256:" + b"0" * 64 + b"\nsize 123\n"
    historical = os.urandom(200000)
    wire = (pkt(b"git-filter-client\n") + pkt(b"version=2\n") + b"0000"
            + pkt(b"capability=clean\n") + pkt(b"capability=smudge\n") + b"0000"
            + request(b"smudge", b"missing.blend", missing)
            + request(b"smudge", b"historical.blend", historical)
            + request(b"clean", b"new.blend", b"new data"))
    protocol = run([str(guard), "--filter-process"], wire).stdout
    groups, group, offset = [], [], 0
    while offset < len(protocol):
        length = int(protocol[offset:offset + 4], 16)
        offset += 4
        if length == 0:
            groups.append(group)
            group = []
        else:
            group.append(protocol[offset:offset + length - 4])
            offset += length - 4
    assert len(groups) == 11 and not group
    assert groups[2] == [b"status=success\n"] and groups[4] == [b"status=error\n"]
    assert groups[5] == [b"status=success\n"] and groups[7] == []
    assert b"".join(groups[6]) == historical
    assert groups[8] == [b"status=success\n"] and groups[10] == []
    assert b"".join(groups[9]) == clean(b"new data")
    no_temps()
    results.append("missing-object smudge fails; same process then streams historical blob and cleans correctly")

record = {"case": args.case, "status": "PASS", "checks": results,
          "bundle_sha256": bundle_hashes,
          "seconds": round(time.monotonic() - started, 3)}
(root / (args.case + "-result.json")).write_text(json.dumps(record, indent=2))
print(json.dumps(record))
