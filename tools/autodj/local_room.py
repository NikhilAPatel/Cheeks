#!/usr/bin/env python3
"""A Listening Room that stays on this Mac, for the owner's own music: commercial tracks don't go on a hosted page.

Serves a folder holding index.html, clips/ and strips/ to this machine only. Ratings are saved to ratings.json beside
them, where the planner's tuning can read them.

    local_room.py FOLDER [PORT]
"""
import json, os, re, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

folder = os.path.abspath(sys.argv[1])
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
ratings_path = os.path.join(folder, "ratings.json")


def load():
    try:
        return json.load(open(ratings_path))
    except (OSError, ValueError):
        return {}


class Room(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=folder, **kwargs)

    def send_json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ratings":
            return self.send_json(load())
        wanted = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if wanted and (wanted[1] or wanted[2]):
            return self.send_range(wanted)
        return super().do_GET()

    def send_range(self, wanted):
        """Part of a file: Safari won't play audio from a server that can't do this."""
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return self.send_error(404)
        size = os.path.getsize(path)
        first = int(wanted[1]) if wanted[1] else max(0, size - int(wanted[2]))
        last = min(size - 1, int(wanted[2])) if wanted[1] and wanted[2] else size - 1
        if first > last:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
        self.send_header("Content-Length", str(last - first + 1))
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(first)
            self.wfile.write(f.read(last - first + 1))

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def do_POST(self):
        if not self.path.startswith("/ratings/"):
            return self.send_error(404)
        doc = self.path[len("/ratings/"):]
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        ratings = load()
        ratings[doc] = data
        temporary = ratings_path + ".tmp"
        json.dump(ratings, open(temporary, "w"), indent=1, ensure_ascii=False)
        os.replace(temporary, ratings_path)
        self.send_json({"ok": True})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    # Only this machine can reach it.
    print(f"http://localhost:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Room).serve_forever()
