#!/usr/bin/env python3
"""Real API verification using one labelled disposable PNG; no third-party dependencies."""
import argparse
import json
import struct
import subprocess
import time
import urllib.request
import uuid
import zlib


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base_url")
    parser.add_argument("--restart-ssh", help="Explicitly restart this app on the specified SSH host")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")

    def request(path, method="GET", body=None, headers=None):
        req = urllib.request.Request(base + path, data=body, method=method, headers=headers or {})
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, response.read()

    def api(path, method="GET"):
        status, raw = request(path, method)
        return status, json.loads(raw) if raw else None

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    marker = "deployment-check-" + uuid.uuid4().hex
    health = api("/api/health")[1]
    assert health["ok"], health
    date = health["time"][:10]
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
           + chunk(b"tEXt", marker.encode())
           + chunk(b"IDAT", zlib.compress(b"\0\x3e\x7a\x5e"))
           + chunk(b"IEND", b""))
    boundary = "tianzige-" + uuid.uuid4().hex
    parts = []
    for name, value in (("date", date), ("note", marker)):
        parts.append(('--' + boundary + '\r\nContent-Disposition: form-data; name="' + name
                      + '"\r\n\r\n' + value + '\r\n').encode())
    parts.append(('--' + boundary + '\r\nContent-Disposition: form-data; name="files"; filename="deployment-check.png"'
                  + '\r\nContent-Type: image/png\r\n\r\n').encode() + png + b"\r\n")
    parts.append(("--" + boundary + "--\r\n").encode())
    body = b"".join(parts)
    headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
    owned_id = None
    try:
        status, raw = request("/api/ingest", "POST", body, headers)
        result = json.loads(raw)
        assert status == 202 and not result.get("duplicate_of"), result
        owned_id = result["batch_id"]
        status, raw = request("/api/ingest", "POST", body, headers)
        assert status == 202 and json.loads(raw)["duplicate_of"] == owned_id
        detail = None
        for _ in range(60):
            detail = api("/api/batch/" + str(owned_id))[1]
            if detail["status"] in ("failed", "done"):
                break
            time.sleep(0.25)
        assert detail["status"] in ("failed", "done"), detail
        if health["ocr"] == "unconfigured":
            assert detail["status"] == "failed" and not detail["subjects"], detail
        image_url = detail["images"][0]["url"]
        assert request(image_url)[1] == png
        day = api("/api/day?date=" + date)[1]
        assert owned_id in day["batch_ids"]
        assert any(image["url"] == image_url for image in day["images"])
        if args.restart_ssh:
            subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                            args.restart_ssh,
                            'sh "$HOME/.local/share/tianzige-at-home/nas-service.sh" restart'],
                           check=True, timeout=30)
            assert api("/api/health")[1]["ok"]
            assert api("/api/batch/" + str(owned_id))[1]["note"] == marker
            assert request(image_url)[1] == png
        print("PASS: health, HTTP 202, duplicate detection, processing state, day API, original image"
              + (", restart persistence" if args.restart_ssh else ""))
    finally:
        if owned_id is not None:
            detail = api("/api/batch/" + str(owned_id))[1]
            if detail["note"] != marker:
                raise RuntimeError("Refusing to delete a batch not owned by this check")
            status, _ = request("/api/batch/" + str(owned_id), "DELETE")
            assert status == 204
            print("PASS: disposable verification image removed")


if __name__ == "__main__":
    main()
