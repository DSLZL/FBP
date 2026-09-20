"""Build Factorio packages without changing the source manifest (stdlib only)."""

import argparse
import json
from pathlib import Path
import re
import tempfile
import zipfile


TARGETS = ("2.0", "2.1")
RELEASE_PATTERNS = (
    "control.lua", "data.lua", "settings.lua", "thumbnail.png", "README.md", "CHANGELOG.md",
    "scripts/**/*.lua", "graphics/**/*.png", "locale/**/*.cfg",
)


def load_info(source):
    info = json.loads((source / "info.json").read_text(encoding="utf-8"))
    if not isinstance(info, dict):
        raise ValueError("info.json must contain an object")
    for field, pattern in (("name", r"[A-Za-z0-9_-]+"), ("version", r"[0-9]+\.[0-9]+\.[0-9]+")):
        if not isinstance(info.get(field), str) or not re.fullmatch(pattern, info[field]):
            raise ValueError(f"Invalid info.json {field}")
    if info.get("factorio_version") not in TARGETS:
        raise ValueError("info.json factorio_version must be 2.0 or 2.1")
    if not (source / "control.lua").is_file():
        raise ValueError("Missing control.lua")
    return info


def build(source, output_dir, info, target):
    if target not in TARGETS:
        raise ValueError(f"Unsupported Factorio target: {target}")
    folder = f"{info['name']}_{info['version']}"
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"{folder}.zip"
    files = sorted({path for pattern in RELEASE_PATTERNS for path in source.glob(pattern) if path.is_file()})
    manifest = dict(info, factorio_version=target)
    with tempfile.TemporaryDirectory(dir=output_dir) as temporary:
        staged = Path(temporary) / output.name
        with zipfile.ZipFile(staged, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(f"{folder}/info.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
            for path in files:
                archive.write(path, f"{folder}/{path.relative_to(source).as_posix()}")
        staged.replace(output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio-version", choices=(*TARGETS, "both"))
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    try:
        info = load_info(source)
        targets = TARGETS if args.factorio_version == "both" else (args.factorio_version or info["factorio_version"],)
        for target in targets:
            if args.factorio_version:
                output_dir = (args.output_dir or source / "dist") / target
            else:
                output_dir = args.output_dir or source
            print(build(source, output_dir, info, target))
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
