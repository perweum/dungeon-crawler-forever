#!/usr/bin/env python3
"""Upload a packaged zip to CurseForge (legacy upload API), used by .github/workflows/release.yml.

Environment: CF_API_KEY (CurseForge API token, a GitHub secret), CF_PROJECT_ID, CF_GAME_VERSION_IDS (comma separated ids,
repository variables). Optional: CF_RELEASE_TYPE (alpha|beta|release, default beta; a tag like v0.2.0-alpha1 overrides).

    tools/upload_curseforge.py --list-versions              print the game versions (id, name) so the Forever id can be found
    tools/upload_curseforge.py <zip> --tag v0.1.1 [--dry-run]

The changelog is the commit subjects since the previous tag. Never prints the token.
"""
import json, os, subprocess, sys, urllib.error, urllib.request, uuid

API = "https://wow.curseforge.com/api"

def token():
    t = os.environ.get("CF_API_KEY", "")
    if not t:
        sys.exit("CF_API_KEY is not set")
    return t

def list_versions():
    req = urllib.request.Request(f"{API}/game/versions", headers={"X-Api-Token": token(), "User-Agent": "dungeon-crawler-forever-release"})
    for v in json.load(urllib.request.urlopen(req, timeout=60)):
        print(v.get("id"), "|", v.get("name"), "|", v.get("gameVersionTypeID"))

def changelog(tag):
    try:
        prev = subprocess.run(["git", "describe", "--tags", "--abbrev=0", f"{tag}^"], capture_output=True, text=True).stdout.strip()
        rng = f"{prev}..{tag}" if prev else tag
        out = subprocess.run(["git", "log", rng, "--pretty=- %s", "--no-merges"], capture_output=True, text=True).stdout.strip()
        return out or "See the GitHub release for details."
    except Exception:
        return "See the GitHub release for details."

def release_type(tag):
    t = tag.lower()
    if "-alpha" in t: return "alpha"
    if "-beta" in t: return "beta"
    if "-rc" in t: return "beta"
    return os.environ.get("CF_RELEASE_TYPE", "beta")

def multipart(fields, files):
    boundary = uuid.uuid4().hex
    body = b""
    for k, v in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, (fn, data) in files.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: application/zip\r\n\r\n'.encode() + data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"

def main():
    if "--list-versions" in sys.argv:
        return list_versions()
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tag = sys.argv[sys.argv.index("--tag") + 1] if "--tag" in sys.argv else ""
    if tag in args: args.remove(tag)
    if not args or not tag:
        sys.exit(__doc__)
    zpath = args[0]
    ids = [int(x) for x in os.environ.get("CF_GAME_VERSION_IDS", "").replace(" ", "").split(",") if x]
    project = os.environ.get("CF_PROJECT_ID", "")
    if not (ids and project):
        sys.exit("CF_PROJECT_ID and CF_GAME_VERSION_IDS must be set")
    meta = {"changelog": changelog(tag), "changelogType": "markdown", "displayName": tag.lstrip("v"),
            "gameVersions": ids, "releaseType": release_type(tag)}
    if "--dry-run" in sys.argv:
        print("would upload", zpath, "to project", project)
        print(json.dumps(meta, indent=2))
        return
    body, ctype = multipart({"metadata": json.dumps(meta)}, {"file": (os.path.basename(zpath), open(zpath, "rb").read())})
    req = urllib.request.Request(f"{API}/projects/{project}/upload-file", data=body, method="POST",
                                 headers={"X-Api-Token": token(), "Content-Type": ctype, "User-Agent": "dungeon-crawler-forever-release"})
    try:
        print("uploaded:", urllib.request.urlopen(req, timeout=300).read().decode())
    except urllib.error.HTTPError as e:  # show why CurseForge refused (never the token)
        print(f"CurseForge answered HTTP {e.code} {e.reason}: {e.read().decode(errors='replace')[:2000]}")
        print("metadata sent:", json.dumps({k: v for k, v in meta.items() if k != "changelog"}), "| file:", os.path.basename(zpath))
        sys.exit(1)

if __name__ == "__main__":
    main()
