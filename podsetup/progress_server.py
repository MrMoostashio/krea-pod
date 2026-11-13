#!/usr/bin/env python3
"""Tiny progress page for pod setup (port 3000). Standard library only.

It never touches the setup itself. It only READS what setup.sh writes into the status folder
(stage.json, plan.json, nodes/*.done) and looks at the files on disk to see how far the downloads are.
"""
import json
import os
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

D = os.environ.get("PODSETUP_DIR", "/workspace/podsetup")
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PROGRESS_PORT", "3000"))
STARTED = time.time()

LABELS = {
    "diffusion_models": "Downloading the main model (the biggest file, so it takes the longest)",
    "text_encoders": "Downloading the text encoder",
    "vae": "Downloading the VAE",
    "loras": "Downloading LoRAs",
    "upscale_models": "Downloading helper models",
    "ultralytics/bbox": "Downloading helper models",
    "sams": "Downloading helper models",
    "clip_vision": "Downloading the image encoder",
    "detection": "Downloading pose and face detection models",
    "sam2": "Downloading helper models",
}


def read_json(name, default):
    try:
        with open(os.path.join(D, name), "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def comfy_up():
    try:
        urllib.request.urlopen("http://127.0.0.1:8188/", timeout=2)
        return True
    except Exception:
        return False


def size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return -1


def build_status():
    stage = read_json("stage.json", {"state": "running", "step": "waiting", "message": "Waiting for ComfyUI to start"})
    plan = read_json("plan.json", {"files": [], "nodes": []})
    failures = []
    try:
        with open(os.path.join(D, "failures.txt"), "r", encoding="utf-8") as f:
            failures = [ln.strip() for ln in f if ln.strip()]
    except Exception:
        pass

    files, total, got, active = [], 0, 0, []
    for f in plan.get("files", []):
        expected = int(f.get("mb", 0)) * 1024 * 1024
        p = f["path"]
        done_size, part_size = size(p), size(p + ".part")
        if done_size > 100_000:
            state, b = "done", expected
        elif part_size >= 0:
            state, b = "downloading", min(part_size, expected)
            active.append((expected, f))
        else:
            state, b = "waiting", 0
        total += expected
        got += b
        files.append({"name": f["name"], "sub": f.get("sub", ""), "state": state, "mb": f.get("mb", 0), "got_mb": round(b / 1048576)})

    nodes = []
    for n in plan.get("nodes", []):
        nodes.append({"name": n, "done": os.path.exists(os.path.join(D, "nodes", n + ".done"))})
    nodes_left = [n for n in nodes if not n["done"]]

    state = stage.get("state", "running")
    message = stage.get("message", "")
    # a plain-words message based on what is being downloaded right now
    if state == "running" and stage.get("step") == "working":
        if active:
            biggest = max(active, key=lambda a: a[0])[1]
            message = LABELS.get(biggest.get("sub", ""), "Downloading models")
        elif nodes_left:
            message = "Installing extra nodes"
        else:
            message = "Finishing up"

    percent = int(100 * got / total) if total else 0
    if state in ("installed", "problems", "ready"):
        percent = 100
    elif percent >= 100:
        percent = 99
    return {
        "state": state,
        "step": stage.get("step", ""),
        "message": message,
        "percent": percent,
        "files": files,
        "nodes": nodes,
        "failures": failures,
        "comfy_up": comfy_up(),
        "elapsed": int(time.time() - STARTED),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, body, ctype):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            try:
                with open(os.path.join(HERE, "progress.html"), "rb") as f:
                    return self.send(200, f.read(), "text/html; charset=utf-8")
            except Exception:
                return self.send(500, "progress.html is missing", "text/plain")
        if path == "/status":
            return self.send(200, json.dumps(build_status()), "application/json")
        return self.send(404, "not found", "text/plain")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
