#!/usr/bin/env python3
"""registry-recoverability.py - prove a registry can still serve whole images.

A `/v2/_catalog` listing only proves a repository name exists. That is not
recovery evidence: a repo can list while its blobs are gone (interrupted GC,
deleted tags, half-pushed layers). This walks the manifest the way a kubelet
would and HEADs every config and layer blob, so a PASS means "the registry can
serve this image completely, right now".

Read-only. No pushes, no deletes, no downloads of layer bodies.

Usage:
  registry-recoverability.py --registry 192.168.0.236:5000 \\
      sailpoint-iiq:8.5 openlingo:v10-dynamic-models ai-language-learning:latest

  # digest-pinned refs work too:
  registry-recoverability.py --registry 192.168.0.236:5000 \\
      'sailpoint-iiq@sha256:a572c48e...'

  --platform linux/arm64   select a different child manifest from an index
  --json                   machine-readable result

Exit status: 0 = every reference fully served, 1 = at least one failure.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

INDEX_TYPES = (
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.index.v1+json",
)
MANIFEST_TYPES = (
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
)
ACCEPT = ",".join(INDEX_TYPES + MANIFEST_TYPES)


def request(registry, path, accept=None, method="GET", timeout=20):
    req = urllib.request.Request(f"http://{registry}{path}", method=method)
    if accept:
        req.add_header("Accept", accept)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return {
                "status": resp.status,
                "headers": dict(resp.headers),
                "body": resp.read(),
            }
    except urllib.error.HTTPError as exc:
        return {"status": exc.code, "headers": dict(exc.headers), "body": exc.read()}
    except Exception as exc:  # network/DNS/timeout
        return {"status": 0, "headers": {}, "body": str(exc).encode()}


def check(registry, ref, platform):
    """Return a result dict for one repo:tag or repo@digest reference."""
    out = {"ref": ref, "ok": False, "error": None, "digest": None,
           "mediaType": None, "platforms": [], "blobs": 0, "bytes": 0}

    if "@" in ref:
        repo, selector = ref.split("@", 1)
        path = f"/v2/{repo}/manifests/{selector}"
    else:
        repo, _, tag = ref.rpartition(":")
        if not repo:  # no tag given
            repo, tag = ref, "latest"
        path = f"/v2/{repo}/manifests/{tag}"

    res = request(registry, path, accept=ACCEPT)
    if res["status"] != 200:
        out["error"] = f"manifest HTTP {res['status']}: {res['body'][:200]!r}"
        return out

    out["digest"] = res["headers"].get("Docker-Content-Digest")
    try:
        manifest = json.loads(res["body"])
    except ValueError:
        out["error"] = "manifest is not JSON (registry returned an error page?)"
        return out

    media_type = manifest.get("mediaType") or res["headers"].get("Content-Type", "")
    out["mediaType"] = media_type

    if media_type in INDEX_TYPES or "manifests" in manifest:
        out["platforms"] = [
            f"{m.get('platform', {}).get('os')}/{m.get('platform', {}).get('architecture')}"
            for m in manifest.get("manifests", [])
        ]
        want_os, want_arch = platform.split("/", 1)
        child = next(
            (m for m in manifest.get("manifests", [])
             if m.get("platform", {}).get("os") == want_os
             and m.get("platform", {}).get("architecture") == want_arch),
            None,
        )
        if child is None:
            out["error"] = f"index has no {platform} manifest (has: {out['platforms']})"
            return out
        res2 = request(registry, f"/v2/{repo}/manifests/{child['digest']}", accept=ACCEPT)
        if res2["status"] != 200:
            out["error"] = f"{platform} child manifest HTTP {res2['status']}"
            return out
        manifest = json.loads(res2["body"])

    blobs = [manifest.get("config", {})] + list(manifest.get("layers", []))
    missing = []
    total = 0
    for blob in blobs:
        digest = blob.get("digest")
        total += blob.get("size") or 0
        if not digest:
            missing.append("(layer with no digest)")
            continue
        head = request(registry, f"/v2/{repo}/blobs/{digest}", method="HEAD")
        if head["status"] != 200:
            missing.append(f"{digest[:24]} HTTP {head['status']}")

    out["blobs"] = len(blobs)
    out["bytes"] = total
    if missing:
        out["error"] = f"{len(missing)} unservable blob(s): {', '.join(missing[:4])}"
        return out

    out["ok"] = True
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("refs", nargs="+", help="repo:tag or repo@sha256:digest")
    ap.add_argument("--registry", default="192.168.0.236:5000")
    ap.add_argument("--platform", default="linux/amd64")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    results = [check(args.registry, ref, args.platform) for ref in args.refs]

    if args.json:
        print(json.dumps({"registry": args.registry, "platform": args.platform,
                          "results": results}, indent=2))
    else:
        print(f"registry {args.registry}  platform {args.platform}\n")
        for r in results:
            flag = "PASS" if r["ok"] else "FAIL"
            print(f"[{flag}] {r['ref']}")
            if r["digest"]:
                print(f"       digest   {r['digest']}")
            if r["mediaType"]:
                extra = f"  (index: {', '.join(r['platforms'])})" if r["platforms"] else ""
                print(f"       manifest {r['mediaType']}{extra}")
            if r["ok"]:
                print(f"       blobs    {r['blobs']} served, "
                      f"{r['bytes'] / 1024 ** 2:.1f} MiB")
            else:
                print(f"       error    {r['error']}")
        bad = [r["ref"] for r in results if not r["ok"]]
        print()
        print("all references fully served" if not bad else f"FAILED: {', '.join(bad)}")

    return 0 if all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
