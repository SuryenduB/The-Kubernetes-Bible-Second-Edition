#!/usr/bin/env python3
"""
abs-gate: session-cookie login gate for the public Audiobookshelf endpoint.

Replaces nginx auth_basic, which Chrome re-challenges endlessly over HTTP/2
(the public endpoint is HTTP/2 at the Cloudflare edge, and Chrome has a
long-standing bug dropping Basic auth credentials on reused h2 connections).

Runs as a sidecar in the abs-auth-proxy pod on 127.0.0.1:9001. nginx calls it
via auth_request; it never listens on a port the cluster or the internet can
reach.

Routes (all loopback-only, nginx proxies to them):
  GET  /login   -> HTML login form
  POST /login   -> verify PBKDF2 password, set signed cookie, redirect
  GET  /authz   -> auth_request target: 200 = valid session, 401 = no session
  POST /logout  -> clear the cookie

Design notes:
  - Stateless: no session store, so 2 replicas need no shared state and a
    pod restart logs nobody out.
  - Cookie is HMAC-signed with SESSION_SECRET over the username + expiry.
    Cookie contents carry no secrets: it is a bearer credential.
  - PBKDF2-HMAC-SHA256, 200k iterations, verified in constant time.
"""

import base64
import hashlib
import hmac
import html
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlparse

LISTEN_PORT = int(os.environ.get("GATE_PORT", "9001"))
COOKIE_NAME = os.environ.get("GATE_COOKIE", "abs_gate")
SESSION_TTL = int(os.environ.get("GATE_TTL_SECONDS", str(7 * 24 * 3600)))

SESSION_SECRET = os.environ["GATE_SESSION_SECRET"]
# Format: pbkdf2_sha256$<iterations>$<salt_hex>$<hash_hex>
PASSWD_ENTRY = os.environ["GATE_PASSWORD_ENTRY"]
GATE_USERNAME = os.environ.get("GATE_USERNAME", "absproxy")


def parse_passwd_entry(entry):
    parts = entry.split("$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        raise ValueError("GATE_PASSWORD_ENTRY must be pbkdf2_sha256$iter$salt$hash")
    return int(parts[1]), bytes.fromhex(parts[2]), bytes.fromhex(parts[3])


ITERATIONS, SALT, EXPECTED_HASH = parse_passwd_entry(PASSWD_ENTRY)


def verify_password(candidate):
    derived = hashlib.pbkdf2_hmac("sha256", candidate.encode(), SALT, ITERATIONS)
    return hmac.compare_digest(derived, EXPECTED_HASH)


def sign_session(username, expires_at):
    """Return base64url(expiry.username) + '.' + hex hmac."""
    payload = f"{expires_at}.{username}".encode()
    key = base64.urlsafe_b64decode(SESSION_SECRET + "=" * (-len(SESSION_SECRET) % 4))
    mac = hmac.new(key, payload, hashlib.sha256).hexdigest()[:32]
    body = base64.urlsafe_b64encode(payload).decode().rstrip("=")
    return f"{body}.{mac}"


def verify_session(token):
    """Return the username if the cookie is valid and unexpired, else None."""
    if not token or "." not in token:
        return None
    body, _, mac = token.rpartition(".")
    try:
        payload = base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)).decode()
        expires_at, username = payload.split(".", 1)
    except Exception:
        return None

    key = base64.urlsafe_b64decode(SESSION_SECRET + "=" * (-len(SESSION_SECRET) % 4))
    expected = hmac.new(key, payload.encode(), hashlib.sha256).hexdigest()[:32]
    # Compare before parsing expiry so a forged token cannot be probed.
    if not hmac.compare_digest(expected, mac):
        return None
    if int(expires_at) < int(time.time()):
        return None
    return username


LOGIN_PAGE = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Audiobookshelf</title>
<style>
 body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
   background:#0f1115;color:#e8e8ea;display:flex;align-items:center;
   justify-content:center;height:100vh;margin:0}}
 form{{background:#181b21;padding:32px;border-radius:12px;width:300px;
   border:1px solid #262a33}}
 h1{{font-size:18px;margin:0 0 20px}}
 label{{font-size:12px;color:#9aa0aa;display:block;margin-bottom:6px}}
 input{{width:100%;padding:10px;margin-bottom:16px;border-radius:6px;
   border:1px solid #333844;background:#0f1115;color:#e8e8ea;font-size:15px;
   box-sizing:border-box}}
 button{{width:100%;padding:11px;border:0;border-radius:6px;background:#3b82f6;
   color:#fff;font-size:15px;font-weight:600;cursor:pointer}}
 .err{{color:#f87171;font-size:13px;margin-bottom:14px}}
</style></head><body>
<form method="POST" action="/login">
 <h1>Audiobookshelf</h1>
 {error}
 <label for="u">Username</label>
 <input id="u" name="username" value="{username}" autocomplete="username"
        autocapitalize="none" autocorrect="off" required>
 <label for="p">Password</label>
 <input id="p" name="password" type="password" autocomplete="current-password"
        required autofocus>
 <button type="submit">Sign in</button>
</form></body></html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "abs-gate"
    sys_version = ""

    def log_message(self, fmt, *args):
        # Structured single-line log to stdout; collected by kubectl logs.
        print("abs-gate %s %s" % (self.address_string(), fmt % args), flush=True)

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _cookie(self):
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            name, _, value = part.strip().partition("=")
            if name == COOKIE_NAME:
                return value
        return None

    def _login_page(self, status=200, error="", username=""):
        page = LOGIN_PAGE.format(error=error, username=html.escape(username))
        self._send(status, page.encode(), "text/html; charset=utf-8",
                   {"Cache-Control": "no-store"})

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/authz":
            user = verify_session(self._cookie())
            if user:
                # Attribute the request for the nginx access log.
                self._send(200, user.encode())
            else:
                # Plain bodyless 401. nginx distinguishes this from
                # Audiobookshelf's own 401 using $gate_denied (the
                # auth_request subrequest status), not by inspecting headers,
                # so no Location header is needed here.
                self._send(401, b"")
            return

        if path == "/healthz":
            self._send(200, b"ok")
            return

        if path == "/login":
            if verify_session(self._cookie()):
                self._send(302, b"", headers={"Location": "/"})
            else:
                self._login_page()
            return

        if path == "/logout":
            self._send(302, b"", headers={
                "Location": "/login",
                "Set-Cookie": f"{COOKIE_NAME}=; Max-Age=0; Path=/; HttpOnly; "
                              f"SameSite=Lax; Secure",
            })
            return

        self._send(404, b"not found")

    def do_POST(self):
        if urlparse(self.path).path != "/login":
            self._send(404, b"not found")
            return

        length = int(self.headers.get("Content-Length", 0) or 0)
        # Bound the body: this is a login form, nothing legitimate is large.
        if length > 4096:
            self._send(413, b"too large")
            return
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        username = (form.get("username") or [""])[0]
        password = (form.get("password") or [""])[0]

        # Do the same work whether the username is wrong or the password is
        # wrong, so response time does not reveal which usernames exist.
        ok_user = hmac.compare_digest(username.encode(), GATE_USERNAME.encode())
        ok_pass = verify_password(password)
        if not (ok_user and ok_pass):
            self.log_message("denied user=%r from=%s", username,
                             self.headers.get("X-Real-IP", self.address_string()))
            self._login_page(401, "Incorrect username or password.", username)
            return

        expires_at = int(time.time()) + SESSION_TTL
        token = sign_session(GATE_USERNAME, expires_at)
        self.log_message("issued session for %s from=%s", GATE_USERNAME,
                         self.headers.get("X-Real-IP", self.address_string()))
        self._send(302, b"", headers={
            "Location": "/",
            "Set-Cookie": f"{COOKIE_NAME}={token}; Max-Age={SESSION_TTL}; Path=/; "
                          f"HttpOnly; SameSite=Lax; Secure",
            "Cache-Control": "no-store",
        })


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler).serve_forever()
