"""NDMS Web API (Keenetic/Netcraze). Только stdlib."""
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.getenv("ROUTER_URL", "http://192.168.2.1")
LOGIN = os.getenv("ROUTER_USER", "admin")
PASS = os.getenv("ROUTER_PASS", "")
_ctx = {"token": os.getenv("ROUTER_TOKEN", "")}


def raw(path, data=None, headers=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, dict(r.headers), r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode("utf-8", "replace")


def md5(s):
    return hashlib.md5(s.encode()).hexdigest()


def login():
    if _ctx["token"]:
        return _ctx["token"]
    st, hdrs, body = raw("/auth")
    realm = hdrs.get("X-NDM-Realm") or ""
    challenge = hdrs.get("X-NDM-Challenge") or ""
    if not realm:
        raise SystemExit(f"нет realm ({st}): {body[:200]}")
    pwd = md5(f"{LOGIN}:{realm}:{PASS}")
    token = md5(challenge + pwd) if challenge else pwd
    st, _, body = raw("/auth", {"login": LOGIN, "password": token})
    try:
        tok = json.loads(body).get("token") or ""
    except Exception:
        tok = ""
    if not tok:
        raise SystemExit(f"логин не удался ({st}): {body[:300]}")
    _ctx["token"] = tok
    return tok


def rci(path, payload=None):
    tok = login()
    status, _, body = raw(path, payload, {"X-NDM-Token": tok})
    try:
        return status, json.loads(body)
    except Exception:
        return status, body


def show(*paths):
    out = {}
    for p in paths:
        st, data = rci("/rci/" + p.lstrip("/"))
        out[p] = data if st == 200 else f"HTTP {st}: {str(data)[:200]}"
    return out


if __name__ == "__main__":
    args = sys.argv[1:] or ["show/version"]
    for p in args:
        st, data = rci("/rci/" + p.lstrip("/"))
        print(f"### {p} -> {st}")
        print(json.dumps(data, ensure_ascii=False, indent=1)[:3000] if isinstance(data, (dict, list)) else str(data)[:2000])
