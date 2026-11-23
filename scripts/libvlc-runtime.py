#!/usr/bin/env python3
"""Stage the pinned playback-only LibVLC runtime for a desktop release."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "packaging/libvlc"
SPEC = json.loads((PACKAGING / "runtime.json").read_text(encoding="utf-8"))
VERSION = SPEC["version"]
MANIFEST = "runtime-files.sha256"
NOTICES = ("COPYING.LIB", "NOTICE.md", "THIRD-PARTY-NOTICES.txt", "BUILD-CONFIG.txt")


def digest(path, algorithm="sha256"):
    checksum = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def download(url, name, checksum, algorithm, cache):
    path = cache / name
    if not path.is_file():
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="vlc-download-", dir=cache) as directory:
            pending = Path(directory) / name
            subprocess.run(
                ["curl", "--fail", "--location", "--retry", "2", "--connect-timeout", "15",
                 "--output", str(pending), url],
                check=True,
            )
            if digest(pending, algorithm) != checksum:
                raise ValueError(f"LibVLC archive {algorithm} mismatch: {pending}")
            pending.replace(path)
    elif digest(path, algorithm) != checksum:
        raise ValueError(f"LibVLC archive {algorithm} mismatch: {path}")
    return path


def archive(entry, cache):
    name = Path(entry["archive"]).name
    return download(SPEC["release"] + entry["archive"], name, entry["sha256"], "sha256", cache)


def source_bundle(destination, cache):
    destination.mkdir(parents=True, exist_ok=True)
    source = archive(SPEC["source"], cache)
    shutil.copyfile(source, destination / source.name)
    contribs = json.loads((PACKAGING / "source-archives.json").read_text(encoding="utf-8"))
    checksums = {}
    with tarfile.open(source) as vlc:
        for component, entry in contribs.items():
            checksum_path = f"vlc-{VERSION}/contrib/src/{component}/SHA512SUMS"
            with vlc.extractfile(checksum_path) as reader:
                checksums[component] = dict(
                    (name, checksum) for checksum, name in
                    (line.split() for line in reader.read().decode("ascii").splitlines() if line.strip())
                )[entry["archive"]]

    def collect(contrib):
        component, entry = contrib
        package = download(entry["url"], entry["archive"], checksums[component], "sha512", cache)
        shutil.copyfile(package, destination / package.name)
        return f"{checksums[component]}  {package.name}\n"

    with ThreadPoolExecutor(max_workers=6) as workers:
        inventory = "".join(workers.map(collect, contribs.items()))
    (destination / "CONTRIB-SHA512SUMS.txt").write_text(inventory, encoding="utf-8")
    (destination / "VLC-SHA256SUMS.txt").write_text(
        f"{SPEC['source']['sha256']}  {source.name}\n", encoding="utf-8"
    )
    shutil.copyfile(PACKAGING / "source-archives.json", destination / "source-archives.json")


def entries(platform):
    selected = SPEC[platform]
    files = dict(selected["libraries"])
    for entry in SPEC["plugins"] + selected["plugins"]:
        group, name = entry.split("/")
        if platform == "macos":
            path = f"plugins/lib{name}_plugin.dylib"
            files[path] = f"lib/vlc/{path}"
        else:
            path = f"plugins/{group}/lib{name}_plugin.dll"
            files[path] = path
    return files


def copy_macos(archive_path, output, files):
    with tempfile.TemporaryDirectory(prefix="ipreview-vlc-mount-") as directory:
        mount = Path(directory)
        subprocess.run(
            ["hdiutil", "attach", str(archive_path), "-mountpoint", str(mount), "-readonly", "-nobrowse"],
            check=True,
        )
        try:
            root = mount / "VLC.app/Contents/MacOS"
            for source, target in files.items():
                destination = output / target
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / source, destination)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)


def copy_windows(archive_path, output, files):
    with zipfile.ZipFile(archive_path) as payload:
        for source, target in files.items():
            destination = output / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            with payload.open(f"vlc-{VERSION}/{source}") as reader, destination.open("wb") as writer:
                shutil.copyfileobj(reader, writer)


def write_notices(platform, source, runtime, output):
    with tarfile.open(source) as sources:
        license_file = sources.getmember(f"vlc-{VERSION}/COPYING.LIB")
        with sources.extractfile(license_file) as reader, (output / "COPYING.LIB").open("wb") as writer:
            shutil.copyfileobj(reader, writer)
    for name in ("NOTICE.md", "THIRD-PARTY-NOTICES.txt"):
        shutil.copyfile(PACKAGING / name, output / name)

    core = runtime / next(target for target in SPEC[platform]["libraries"].values() if "vlccore" in target)
    flags = re.search(rb"[/\w.-]+/configure +'[^\x00]+", core.read_bytes())
    if flags is None:
        raise ValueError(f"Official LibVLC configure arguments missing from {core.name}")
    (output / "BUILD-CONFIG.txt").write_text(
        f"LibVLC {VERSION}, source revision {SPEC['revision']}\n"
        f"Runtime archive: {SPEC['release']}{SPEC[platform]['archive']}\n"
        f"Runtime archive SHA-256: {SPEC[platform]['sha256']}\n"
        f"Source archive: {SPEC['release']}{SPEC['source']['archive']}\n"
        f"Source archive SHA-256: {SPEC['source']['sha256']}\n\n"
        "Official configure command embedded in libvlccore:\n"
        f"{flags.group().decode('ascii')}\n",
        encoding="utf-8",
    )


def files_in(directory):
    return sorted(path.relative_to(directory).as_posix() for path in directory.rglob("*") if path.is_file())


def file_checksums(platform, runtime, notices):
    by_name = {name: runtime / name for name in entries(platform).values()}
    by_name.update({name: notices / name for name in NOTICES})
    return "".join(f"{digest(by_name[name])}  {name}\n" for name in sorted(by_name))


def verify(platform, runtime, notices):
    code_files = sorted(entries(platform).values())
    notice_files = sorted([*NOTICES, MANIFEST])
    if notices == runtime:
        valid_files = files_in(runtime) == sorted([*code_files, *notice_files])
    else:
        valid_files = files_in(runtime) == code_files and files_in(notices) == notice_files
    if not valid_files:
        raise ValueError(f"Unexpected LibVLC payload: {runtime}")
    if file_checksums(platform, runtime, notices) != (notices / MANIFEST).read_text(encoding="utf-8"):
        raise ValueError(f"LibVLC runtime checksum mismatch: {runtime}")


def stage(platform, destination, notices, cache):
    if destination.exists():
        verify(platform, destination, notices)
        return
    vendor = archive(SPEC[platform], cache)
    source = archive(SPEC["source"], cache)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="libvlc-runtime-", dir=destination.parent) as directory:
        runtime = Path(directory) / "LibVLC"
        documentation = runtime if notices == destination else Path(directory) / "documentation"
        runtime.mkdir()
        documentation.mkdir(exist_ok=True)
        copy = copy_macos if platform == "macos" else copy_windows
        copy(vendor, runtime, entries(platform))
        write_notices(platform, source, runtime, documentation)
        manifest = file_checksums(platform, runtime, documentation)
        (documentation / MANIFEST).write_text(manifest, encoding="utf-8")
        verify(platform, runtime, documentation)
        if notices != destination:
            notices.parent.mkdir(parents=True, exist_ok=True)
            documentation.rename(notices)
        runtime.rename(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("stage", "check", "source"))
    parser.add_argument("destination", type=Path)
    parser.add_argument("--platform", choices=("macos", "windows"))
    parser.add_argument("--notices", type=Path)
    parser.add_argument("--cache", type=Path, default=ROOT / ".build/libvlc-downloads")
    args = parser.parse_args()
    if args.operation == "source":
        source_bundle(args.destination, args.cache)
    else:
        if args.platform is None:
            parser.error("--platform is required for stage and check")
        if args.platform == "macos" and args.notices is None:
            parser.error("--notices must point outside the macOS Frameworks directory")
        notices = args.notices or args.destination
        if args.operation == "stage":
            stage(args.platform, args.destination, notices, args.cache)
        else:
            verify(args.platform, args.destination, notices)



if __name__ == "__main__":
    main()
