"""Run disposable Factorio GUI scenarios and real save migration; never uses live mods/saves."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pack_mod


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", required=True, type=Path)
    parser.add_argument("--steam-app-id", type=int, help="Steam development launch ID; written only inside the test directory")
    parser.add_argument("--baseline", required=True, type=Path, help="ZIP containing the pre-refactor source at archive root")
    parser.add_argument("--output-dir", required=True, type=Path, help="New, empty validation directory")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty so earlier evidence is preserved")
    user, mods = output / "userdata", output / "mods"
    user.mkdir(parents=True, exist_ok=True)
    mods.mkdir()
    if args.steam_app_id:
        (output / "steam_appid.txt").write_text(str(args.steam_app_id), encoding="ascii")
    data = args.factorio.resolve().parents[2] / "data"
    config = output / "config.ini"
    config.write_text(f"[path]\nread-data={data.as_posix()}\nwrite-data={user.as_posix()}\n"
                      "[general]\nlocale=en\n[graphics]\nfull-screen=false\n", encoding="utf-8")
    enabled = {"base", "recycler", "quality", "Factorio_Blueprint_Printer"}
    (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": name in enabled}
        for name in ("base", "recycler", "quality", "elevated-rails", "space-age", "Factorio_Blueprint_Printer")]}))
    scenario = user / "scenarios" / "fbp-validation"
    scenario.mkdir(parents=True)
    (scenario / "control.lua").write_text("-- Player and terrain are prepared by the isolated validation hook.\n")
    info = pack_mod.load_info(root)
    previous_save = None
    for phase in ("seed", "upgrade", "reload"):
        version = "0.2.0" if phase == "seed" else info["version"]
        mod = mods / f"{info['name']}_{version}"
        mod.mkdir(exist_ok=True)
        files = {path for pattern in pack_mod.RELEASE_PATTERNS for path in root.glob(pattern) if path.is_file()}
        for path in files:
            destination = mod / path.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
        if phase == "seed":
            with zipfile.ZipFile(args.baseline) as archive:
                for entry in archive.infolist():
                    destination = (mod / entry.filename).resolve()
                    if not destination.is_relative_to(mod.resolve()):
                        raise ValueError("unsafe baseline archive path")
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(archive.read(entry))
        (mod / "info.json").write_text(json.dumps(dict(info, version=version, factorio_version="2.1")))
        (mod / "tests").mkdir(exist_ok=True)
        shutil.copyfile(root / "tests/engine.lua", mod / "tests/engine.lua")
        with (mod / "control.lua").open("a", encoding="utf-8") as control:
            control.write(f'\nrequire("tests.engine").install("{phase}")\n')
        command = [str(args.factorio.resolve()), "--config", str(config), "--mod-directory", str(mods),
                   "--disable-audio", "--force-graphics-preset", "very-low", "--window-size", "640x480",
                   "--disable-migration-window"]
        command += ["--load-game", str(previous_save)] if previous_save else ["--load-scenario", "fbp-validation"]
        startup = None
        if sys.platform == "win32":
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 0
        with (output / f"{phase}.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, startupinfo=startup)
            try:
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline:
                    failed = user / "script-output" / f"fbp-{phase}.failed"
                    marker = user / "script-output" / f"fbp-{phase}.ok"
                    saves = list((user / "saves").glob(f"*fbp-{phase}*.zip"))
                    if failed.exists():
                        raise RuntimeError(failed.read_text(encoding="utf-8"))
                    if marker.exists() and saves and zipfile.is_zipfile(saves[0]):
                        previous_save = saves[0]
                        break
                    if process.poll() is not None:
                        raise RuntimeError(f"{phase}: engine exited before the validation save was created")
                    time.sleep(0.25)
                else:
                    raise RuntimeError(f"{phase}: validation did not complete; inspect {output / (phase + '.log')}")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
        print(f"PASS {phase}: {previous_save}", flush=True)
    print(f"Engine evidence: {output}")


if __name__ == "__main__":
    main()
