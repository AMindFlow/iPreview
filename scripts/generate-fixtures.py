#!/usr/bin/env python3
"""Create the synthetic media archive used for iPreview's desktop acceptance."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


ARCHIVE_ROOT = "iPreview-fixtures"
ZIP_TIMESTAMP = (2024, 1, 1, 0, 0, 0)


def ffmpeg(*args):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", *args],
        check=True,
    )


def still(output, pattern):
    ffmpeg(
        "-f", "lavfi", "-i", f"{pattern}=size=384x240:rate=1",
        "-frames:v", "1", "-threads", "1", "-f", "image2", "-update", "1",
        str(output),
    )


def video(output, rate, frequency, duration=6):
    ffmpeg(
        "-f", "lavfi", "-i", f"testsrc2=size=384x240:rate={rate}:duration={duration}",
        "-f", "lavfi", "-i", f"sine=frequency={frequency}:sample_rate=44100:duration={duration}",
        "-c:v", "libx264", "-profile:v", "baseline", "-pix_fmt", "yuv420p",
        "-g", str(rate), "-threads", "1",
        "-af", "volume=0.25", "-c:a", "aac", "-b:a", "96k",
        "-map_metadata", "-1", "-movflags", "+faststart", str(output),
    )


def generate_media(work, library):
    harbor = work / "harbor.png"
    dusk = work / "dusk.png"
    skyline = work / "skyline.jpg"
    wave = work / "wave.gif"
    webp = work / "harbor.webp"
    heic = work / "dusk.heic"
    mp4 = work / "sunset.mp4"
    mov = work / "sea.mov"
    long_video = work / "long.mp4"

    still(harbor, "testsrc2")
    still(dusk, "smptehdbars")
    still(skyline, "smptebars")
    ffmpeg(
        "-f", "lavfi", "-i", "testsrc2=size=192x120:rate=5:duration=2",
        "-loop", "0", str(wave),
    )
    subprocess.run(["cwebp", "-quiet", "-lossless", str(harbor), "-o", str(webp)], check=True)
    subprocess.run(
        ["sips", "-s", "format", "heic", str(dusk), "--out", str(heic)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    video(mp4, rate=24, frequency=440)
    video(mov, rate=30, frequency=554)
    video(long_video, rate=24, frequency=440, duration=32)

    samples = {
        "沿海创作者/旅行摄影/01-港湾.jpg": skyline,
        "沿海创作者/旅行摄影/02-港湾.png": harbor,
        "沿海创作者/旅行摄影/10-港湾.webp": webp,
        "沿海创作者/旅行摄影/20-浪花.gif": wave,
        "沿海创作者/旅行摄影/21-礁石.heic": heic,
        "沿海创作者/旅行摄影/.隐藏.PNG": dusk,
        "沿海创作者/Ａ夜景/01-Sunset.MP4": mp4,
        "沿海创作者/Ａ夜景/02-夜幕.PNG": dusk,
        "多创作者/北京摄影/Summer/Lantern_02.PNG": dusk,
        "多创作者/北京摄影/Summer/Lantern_10.png": harbor,
        "多创作者/北京摄影/Summer/Sea.mov": mov,
        "多创作者/海岛摄影/长岸/01-长岸.png": harbor,
        "层级歧义/直属相册/01-公园.png": harbor,
        "层级歧义/创作者甲/远景/01-雾山.png": dusk,
        "直属媒体/Morning.png": harbor,
        "直属媒体/海面.mp4": mp4,
        "视频作品/完整结构/视频/影片.mp4": mp4,
        "视频作品/完整结构/官方样张/样张.jpg": skyline,
        "视频作品/完整结构/附加写真集/写真集 2/封面.png": harbor,
        "视频作品/完整结构/附加写真集/写真集 2/图片 1.png": dusk,
        "视频作品/完整结构/附加写真集/写真集 10/封面.jpg": skyline,
        "视频作品/完整结构/附加写真集/写真集 10/图片 1.png": harbor,
        "视频作品/简化结构/影片.mov": mov,
        "视频作品/简化结构/官方样张.jpg": skyline,
        "视频作品/简化结构/附加写真集/图片 2.png": harbor,
        "视频作品/简化结构/附加写真集/图片 10.png": dusk,
        "视频作品/album/video.mp4": mp4,
        "视频作品/album/pictures/1.png": harbor,
        "视频作品/album/pictures/2.png": dusk,
        "视频作品/album-with-sample/main.mp4": mp4,
        "视频作品/album-with-sample/frame.jpg": skyline,
        "视频作品/album-with-sample/gallery/1.png": dusk,
        "视频作品/full-no-stills/movie/main.mp4": mp4,
        "视频作品/full-no-stills/books/Set 2/1.png": harbor,
        "视频作品/full-no-stills/books/Set 10/1.png": dusk,
        "视频作品/full-with-stills/movie/main.mp4": long_video,
        "视频作品/full-with-stills/stills/frame.jpg": skyline,
        "视频作品/full-with-stills/books/Set 2/1.png": harbor,
        "视频作品/album-17/video.mp4": long_video,
    }
    for number in range(1, 18):
        samples[f"视频作品/album-17/pictures/{number}.png"] = harbor if number % 2 else dusk
    for relative_path, sample in samples.items():
        destination = library / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sample, destination)

    (library / "沿海创作者/旅行摄影/22-坏图.jpg").write_bytes(b"iPreview invalid JPEG fixture\n")
    (library / "视频作品/full-with-stills/books/Set 2/2-broken.jpg").write_bytes(b"iPreview invalid JPEG fixture\n")
    (library / "沿海创作者/旅行摄影/忽略.txt").write_text("非媒体文件\n", encoding="utf-8")


def write_archive(library, output):
    paths = sorted(item for item in library.rglob("*") if item.is_file())
    hashes = []
    with zipfile.ZipFile(output, mode="x") as archive:
        for path in paths:
            name = path.relative_to(library).as_posix()
            data = path.read_bytes()
            hashes.append(f"{hashlib.sha256(data).hexdigest()}  {name}\n")
            info = zipfile.ZipInfo(f"{ARCHIVE_ROOT}/{name}", date_time=ZIP_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)

        manifest = zipfile.ZipInfo(f"{ARCHIVE_ROOT}/SHA256SUMS", date_time=ZIP_TIMESTAMP)
        archive.writestr(manifest, "".join(hashes).encode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="path to a new fixture ZIP archive")
    args = parser.parse_args()

    for tool in ("ffmpeg", "cwebp", "sips"):
        if not shutil.which(tool):
            parser.error(f"required development tool not available: {tool}")
    if args.output.exists():
        parser.error(f"output already exists: {args.output}")

    with tempfile.TemporaryDirectory(prefix="ipreview-fixtures-") as temporary:
        work = Path(temporary)
        library = work / ARCHIVE_ROOT
        generate_media(work, library)
        write_archive(library, args.output)

    print(args.output.resolve())


if __name__ == "__main__":
    main()
