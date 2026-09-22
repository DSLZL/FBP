"""FMTK hooks for paired Factorio 2.0/2.1 releases (Python standard library only)."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

from pack_mod import TARGETS, build, load_info


PORTAL = "https://mods.factorio.com"


def version_parts(version):
    parts = version.split(".")
    if len(parts) != 3 or any(not part.isascii() or not part.isdigit() or str(int(part)) != part
                              or int(part) > 65535 for part in parts):
        raise ValueError("Mod versions must contain three integers from 0 to 65535, without leading zeros")
    return tuple(map(int, parts))


def release_versions(info):
    major, minor, patch = version_parts(info["version"])
    if info["factorio_version"] != "2.0" or patch % 2 or patch > 65532:
        raise ValueError("Paired publishing requires factorio_version 2.0 and an even patch number <= 65532")
    return dict(zip(TARGETS, (info["version"], f"{major}.{minor}.{patch + 1}")))


def request_json(url, data=None, headers=None):
    request = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
        if not isinstance(result, dict):
            raise ValueError("Mod Portal returned an unexpected JSON response")
        return result
    except urllib.error.HTTPError as error:
        try:
            detail = json.load(error).get("message", "request rejected")
        except (ValueError, AttributeError):
            detail = "request rejected"
        raise RuntimeError(f"Mod Portal HTTP {error.code}: {detail}") from None


def fetch_releases(name):
    # Portal metadata is cached; every publish check must see completed uploads.
    url = f"{PORTAL}/api/mods/{name}/full?publish_check={uuid.uuid4().hex}"
    data = request_json(url)
    if data.get("name") != name or not isinstance(data.get("releases"), list):
        raise ValueError("Unexpected Mod Portal release response")
    return {release["version"]: release for release in data["releases"]}


def upload_file(name, path, api_key):
    response = request_json(
        f"{PORTAL}/api/v2/mods/releases/init_upload",
        urllib.parse.urlencode({"mod": name}).encode("ascii"),
        {"Authorization": f"Bearer {api_key}", "Content-Type": "application/x-www-form-urlencoded"},
    )
    url = response.get("upload_url", "")
    if not isinstance(url, str):
        raise ValueError("Mod Portal returned an invalid upload URL")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Mod Portal returned an invalid upload URL")
    boundary = uuid.uuid4().hex
    data = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
            'Content-Type: application/zip\r\n\r\n').encode("ascii")
    data += path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    # The API key belongs only on init_upload, never on the returned storage URL.
    result = request_json(url, data, {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    if result.get("success") is not True:
        raise RuntimeError(f"Mod Portal upload failed: {result.get('message', 'no success response')}")


def git(source, *args, optional=False):
    result = subprocess.run(["git", *args], cwd=source, capture_output=True, text=True)
    if result.returncode and not (optional and result.returncode == 1):
        raise RuntimeError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip()


def check_tags(source, versions):
    tree = git(source, "rev-parse", "HEAD^{tree}")
    for version in versions.values():
        tag = f"refs/tags/mod-portal-{version}"
        if git(source, "rev-parse", "--verify", "--quiet", tag, optional=True):
            if git(source, "rev-parse", f"{tag}^{{tree}}") != tree:
                raise ValueError(f"Tag mod-portal-{version} already refers to different source")


def push_remote(source):
    branch = git(source, "branch", "--show-current")
    remote = (git(source, "config", f"branch.{branch}.pushRemote", optional=True)
              or git(source, "config", "remote.pushDefault", optional=True)
              or git(source, "config", f"branch.{branch}.remote", optional=True))
    if not remote or remote == ".":
        raise ValueError("Configure a Git push remote before publishing")
    return remote


def publish_tags(source, versions):
    check_tags(source, versions)
    remote = push_remote(source)
    tags = []
    for target, version in versions.items():
        tag = f"mod-portal-{version}"
        if not git(source, "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}", optional=True):
            git(source, "tag", "-a", tag, "-m", f"Factorio {target}: {version}")
        tags.append(f"refs/tags/{tag}")
    git(source, "push", remote, *tags)
    print("Published Git tags: " + ", ".join(tags))


def pending_packages(packages, releases):
    pending = []
    for target, version, path, sha1 in packages:
        release = releases.get(version)
        if release is None:
            pending.append((target, version, path, sha1))
        elif (release.get("info_json", {}).get("factorio_version") != target
              or release.get("file_name") != path.name or release.get("sha1") != sha1):
            raise ValueError(f"Published version {version} differs from the local Factorio {target} package; use a new version pair")
    return pending


def publish(source, upload=False):
    info = load_info(source)
    versions = release_versions(info)
    if upload:
        if git(source, "status", "--porcelain"):
            raise ValueError("Commit changes before publishing")
        if git(source, "branch", "--show-current") != info["package"]["git_publish_branch"]:
            raise ValueError("Publish from the configured Git branch")
        push_remote(source)
    check_tags(source, versions)
    packages = []
    for target, version in versions.items():
        path = build(source, source / "dist" / "publish" / info["version"] / target,
                     dict(info, version=version), target)
        sha1 = hashlib.sha1(path.read_bytes()).hexdigest()
        packages.append((target, version, path, sha1))
        print(f"Factorio {target}: {version} -> {path} (SHA1 {sha1})")
    pending = pending_packages(packages, fetch_releases(info["name"]))
    if not upload:
        print(f"Preflight passed: {len(pending)} upload(s), {len(packages) - len(pending)} already verified")
        return
    api_key = os.environ.get("FACTORIO_UPLOAD_API_KEY", "").strip()
    if pending and not api_key:
        raise ValueError("Use FMTK Publish Mod with its saved API key, or set FACTORIO_UPLOAD_API_KEY")
    for target, version, path, _ in pending:
        upload_file(info["name"], path, api_key)
        print(f"Uploaded {version} for Factorio {target}")
    if pending_packages(packages, fetch_releases(info["name"])):
        raise RuntimeError("Portal verification is incomplete; retry the same release after metadata refreshes")
    if git(source, "status", "--porcelain"):
        raise ValueError("Source changed during publishing; stop before tagging or incrementing versions")
    publish_tags(source, versions)
    print("Both releases verified against Mod Portal SHA1 values")


def advance_version(source):
    info = load_info(source)
    major, minor, patch = version_parts(info["version"])
    if not patch % 2 or patch >= 65535:
        raise ValueError("This hook must run after FMTK increments the even patch to the next odd patch")
    info["version"] = f"{major}.{minor}.{patch + 1}"
    path = source / "info.json"
    staged = source / ".info.json.next"
    staged.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    staged.replace(path)
    print(f"Next dual-version release: {info['version']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="build and check both packages without uploading (default)")
    mode.add_argument("--upload", action="store_true", help="upload, verify and tag both packages; used by FMTK")
    mode.add_argument("--advance", action="store_true", help="FMTK version hook: reserve the next even/odd pair")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    try:
        if args.advance:
            advance_version(source)
        else:
            publish(source, upload=args.upload)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        message = str(error)
        key = os.environ.get("FACTORIO_UPLOAD_API_KEY", "").strip()
        if key:
            message = message.replace(key, "[redacted]")
        parser.exit(1, f"Publish failed: {message}\n")


if __name__ == "__main__":
    main()
