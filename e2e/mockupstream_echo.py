#!/usr/bin/env python3
"""Mock AgentRouter upstream: echoes the credentials it received, and answers
401 like the real upstream when the token is not the expected one."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os, sys

EXPECT_KEY = os.environ.get("EXPECT_KEY", "")
PORT = int(os.environ.get("PORT", "9000"))


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self._send(200, {"ok": True})

    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        xkey = self.headers.get("x-api-key", "")
        cookie = self.headers.get("Cookie", "")
        ua = self.headers.get("User-Agent", "")
        tok = auth[len("Bearer "):] if auth.lower().startswith("bearer ") else (xkey or "")

        sys.stderr.write("UPSTREAM SAW auth=%r x-api-key=%r cookie=%r ua=%r\n"
                         % (auth, xkey, cookie, ua))

        if EXPECT_KEY and tok != EXPECT_KEY:
            self._send(401, {"error": {"message": "无效的令牌", "type": "new_api_error"}})
            return
        self._send(200, {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": "glm-5.3",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "ok"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
            "_echo": {"authorization": auth, "x_api_key": xkey},
        })

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


HTTPServer(("0.0.0.0", PORT), H).serve_forever()
