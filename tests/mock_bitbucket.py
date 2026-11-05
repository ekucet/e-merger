#!/usr/bin/env python3
"""Mock Bitbucket Server / Data Center REST API.

Usage: python3 -I mock_bitbucket.py [port] [context-path]

With a context path (e.g. /bitbucket) every Bitbucket route lives under it and the
host root answers 503 — like a corporate reverse proxy. Mirrors two real Data Center
behaviours: REST responses carry `X-AUSERNAME`, and the applinks `whoami` servlet
returns an empty body for HTTP access tokens."""
import hashlib
import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 7990
CONTEXT = ""  # e.g. "/bitbucket"
LOCK = threading.RLock()
# Reachable without a Bitbucket token (the CI hook is a plain webhook; application-properties
# is public on real servers and is what the app probes to find the context path).
AUTH_EXEMPT = {"/ci/trigger", "/rest/api/1.0/application-properties", "/rest/api/latest/application-properties"}

TOKENS = {"tok-mudur": "mudur", "tok-dev": "gelistirici", "tok-ayse": "ayse"}
USERS = {
    "mudur": {"name": "mudur", "slug": "mudur", "displayName": "Ersel (Müdür)",
              "emailAddress": "mudur@example.com", "id": 1, "active": True, "type": "NORMAL"},
    "gelistirici": {"name": "gelistirici", "slug": "gelistirici", "displayName": "Ersel (Geliştirici)",
                    "emailAddress": "gelistirici@example.com", "id": 2, "active": True, "type": "NORMAL"},
    "ayse": {"name": "ayse", "slug": "ayse", "displayName": "Ayşe Yılmaz",
             "emailAddress": "ayse@example.com", "id": 3, "active": True, "type": "NORMAL"},
}
PROJECTS = {"MOB": {"key": "MOB", "id": 10, "name": "Mobile"},
            "CORE": {"key": "CORE", "id": 11, "name": "Core"}}
REPOS = {("MOB", "ios-app"): {"slug": "ios-app", "id": 100, "name": "ios-app"},
         ("MOB", "android-app"): {"slug": "android-app", "id": 101, "name": "android-app"},
         ("CORE", "payments"): {"slug": "payments", "id": 102, "name": "payments"}}


def now_ms():
    return int(time.time() * 1000)


def commit_for(pr_id):
    return hashlib.sha1(("pr-%d-from" % pr_id).encode()).hexdigest()


def ref(pkey, rslug, branch, commit):
    r = REPOS[(pkey, rslug)]
    return {"id": "refs/heads/" + branch, "displayId": branch, "latestCommit": commit,
            "repository": {"slug": r["slug"], "id": r["id"], "name": r["name"], "public": False,
                           "project": dict(PROJECTS[pkey])}}


def participant(slug, role, approved=False):
    return {"user": dict(USERS[slug]), "role": role, "approved": approved,
            "status": "APPROVED" if approved else "UNAPPROVED"}


PRS = {}
BUILD_BY_PR = {5: "FAILED", 3: "INPROGRESS"}
CONFLICTED = {3}
MIN_APPROVALS = {1: 2}


def make_pr(pid, pkey, rslug, author, reviewers, branch, title, approved=(), tasks=(0, 0, 0)):
    t = now_ms() - (7 - pid) * 3600_000
    PRS[pid] = {
        "id": pid, "version": 0, "title": title, "description": "Description for: " + title,
        "state": "OPEN", "open": True, "closed": False, "createdDate": t, "updatedDate": t,
        "fromRef": ref(pkey, rslug, branch, commit_for(pid)),
        "toRef": ref(pkey, rslug, "develop", hashlib.sha1(("to-%d" % pid).encode()).hexdigest()),
        "locked": False,
        "author": participant(author, "AUTHOR"),
        "reviewers": [participant(r, "REVIEWER", r in approved) for r in reviewers],
        "participants": [],
        "properties": {"openTaskCount": tasks[0], "resolvedTaskCount": tasks[1], "commentCount": tasks[2]},
        "_repo": (pkey, rslug),
    }


make_pr(1, "MOB", "ios-app", "gelistirici", ["mudur", "ayse"], "feature/login", "Add login screen", approved=("ayse",), tasks=(1, 0, 3))
make_pr(2, "MOB", "ios-app", "gelistirici", ["mudur", "ayse"], "feature/settings", "Settings page refactor", approved=("mudur", "ayse"), tasks=(0, 2, 5))
make_pr(3, "MOB", "android-app", "ayse", ["mudur", "gelistirici"], "feature/push", "Push notification channel", tasks=(2, 1, 4))
make_pr(4, "CORE", "payments", "mudur", ["gelistirici", "ayse"], "feature/refunds", "Refund API endpoints")
make_pr(5, "MOB", "ios-app", "gelistirici", ["mudur"], "bugfix/crash-on-launch", "Fix crash on launch", tasks=(0, 0, 1))
make_pr(6, "CORE", "payments", "gelistirici", [], "chore/deps", "Bump dependencies")
# Opened by the developer with no reviewers, in a repo nobody watches: only the author's
# dashboard lists it; the other account must find it by probing the PR directly.
make_pr(7, "MOB", "ios-app", "gelistirici", [], "feature/no-reviewers-yet", "Opened without reviewers")


def pr_json(pr, port):
    out = {k: v for k, v in pr.items() if not k.startswith("_")}
    pkey, rslug = pr["_repo"]
    out["links"] = {"self": [{"href": "http://localhost:%d/projects/%s/repos/%s/pull-requests/%d" % (port, pkey, rslug, pr["id"])}]}
    return out


def merge_status(pr):
    vetoes = []
    conflicted = pr["id"] in CONFLICTED
    # Bitbucket's "minimum approvals" check counts reviewers and participants alike.
    approvals = sum(1 for r in pr["reviewers"] + pr["participants"] if r["approved"])
    need = MIN_APPROVALS.get(pr["id"], 1)
    if conflicted:
        vetoes.append({"summaryMessage": "Merge conflicts",
                       "detailedMessage": "This pull request has conflicts that must be resolved before merging."})
    if approvals < need:
        if need > 1:
            vetoes.append({"summaryMessage": "Requires 2 approvals",
                           "detailedMessage": "This pull request needs %d approvals before it can be merged (has %d)." % (need, approvals)})
        else:
            vetoes.append({"summaryMessage": "Requires approval",
                           "detailedMessage": "At least one reviewer must approve this pull request before it can be merged."})
    return {"canMerge": not vetoes, "conflicted": conflicted,
            "outcome": "CONFLICTED" if conflicted else "CLEAN", "vetoes": vetoes}


def paged(items, qs):
    try:
        limit = int(qs.get("limit", ["25"])[0])
        start = int(qs.get("start", ["0"])[0])
    except ValueError:
        limit, start = 25, 0
    limit = max(1, limit)
    start = max(0, start)
    page = items[start:start + limit]
    last = start + limit >= len(items)
    res = {"size": len(page), "limit": limit, "isLastPage": last, "values": page, "start": start}
    if not last:
        res["nextPageStart"] = start + limit
    return res


def err(msg, **extra):
    e = {"message": msg}
    e.update(extra)
    return {"errors": [e]}


PR_RE = r"^/rest/api/1\.0/projects/([^/]+)/repos/([^/]+)/pull-requests"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "MockBitbucket/1.0"

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json;charset=UTF-8"):
        data = body.encode("utf-8") if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if getattr(self, "_user", None):
            self.send_header("X-AUSERNAME", self._user)
        self.end_headers()
        self.wfile.write(data)

    def read_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        return self.rfile.read(n) if n > 0 else b""

    def handle_any(self, method):
        raw = self.read_body()
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        qs = parse_qs(u.query)
        auth = self.headers.get("Authorization", "")
        token = auth[7:].strip() if auth.startswith("Bearer ") else None
        user = TOKENS.get(token)
        self._user = user
        xat = "present" if self.headers.get("X-Atlassian-Token") else "absent"
        print("%s %s user=%s x-atlassian-token=%s" % (method, self.path, user or "-", xat), flush=True)
        if CONTEXT and path != "/ci/trigger":
            if path == CONTEXT or path.startswith(CONTEXT + "/"):
                path = path[len(CONTEXT):] or "/"
            else:  # outside the context path the reverse proxy has nothing to serve
                self._user = None
                return self.send(503, "Service Unavailable", "text/plain")
        if not user and path not in AUTH_EXEMPT:
            return self.send(401, err("Authentication failed"))
        body = None
        if raw:
            try:
                body = json.loads(raw.decode("utf-8"))
            except Exception:
                body = None
        port = self.server.server_address[1]
        with LOCK:
            try:
                self.route(method, path, qs, user, body, raw, port)
            except Exception as e:  # keep server alive
                self.send(500, err("Internal mock error: %r" % e))

    def route(self, method, path, qs, user, body, raw, port):
        if method == "GET" and path in ("/rest/api/1.0/application-properties", "/rest/api/latest/application-properties"):
            return self.send(200, {"version": "9.4.2", "buildNumber": "9004002", "buildDate": "1736803793767", "displayName": "Bitbucket"})

        if method == "GET" and path == "/plugins/servlet/applinks/whoami":
            # Data Center: empty for HTTP access tokens (the client must use X-AUSERNAME).
            return self.send(200, "", "text/plain;charset=UTF-8")

        m = re.match(r"^/rest/api/1\.0/users/([^/]+)$", path)
        if method == "GET" and m:
            u = USERS.get(m.group(1))
            return self.send(200, u) if u else self.send(404, err("User %s does not exist." % m.group(1)))

        if method == "GET" and path == "/rest/api/1.0/dashboard/pull-requests":
            state = qs.get("state", ["OPEN"])[0].upper()
            role = qs.get("role", [None])[0]
            role = role.upper() if role else None
            res = []
            for pid in sorted(PRS):
                pr = PRS[pid]
                if state != "ALL" and pr["state"] != state:
                    continue
                is_a = pr["author"]["user"]["name"] == user
                is_r = any(r["user"]["name"] == user for r in pr["reviewers"])
                is_p = any(r["user"]["name"] == user for r in pr["participants"])
                ok = {"AUTHOR": is_a, "REVIEWER": is_r, "PARTICIPANT": is_p}.get(role, is_a or is_r or is_p)
                if ok:
                    res.append(pr_json(pr, port))
            return self.send(200, paged(res, qs))

        m = re.match(PR_RE + r"$", path)
        if method == "GET" and m:
            key, slug = m.group(1), m.group(2)
            if (key, slug) not in REPOS:
                return self.send(404, err("Repository %s/%s does not exist." % (key, slug)))
            state = qs.get("state", ["OPEN"])[0].upper()
            res = [pr_json(p, port) for _, p in sorted(PRS.items())
                   if p["_repo"] == (key, slug) and (state == "ALL" or p["state"] == state)]
            return self.send(200, paged(res, qs))

        m = re.match(PR_RE + r"/(\d+)(/.*)?$", path)
        if m:
            key, slug, pid, sub = m.group(1), m.group(2), int(m.group(3)), m.group(4) or ""
            pr = PRS.get(pid)
            if not pr or pr["_repo"] != (key, slug):
                return self.send(404, err("Pull request %d does not exist in %s/%s." % (pid, key, slug)))
            return self.pr_route(method, sub, qs, user, body, pr, port)

        m = re.match(r"^/rest/build-status/1\.0/commits/([^/]+)$", path)
        if method == "GET" and m:
            cid = m.group(1)
            vals = []
            for pid, pr in PRS.items():
                if pr["fromRef"]["latestCommit"] == cid:
                    st = BUILD_BY_PR.get(pid, "SUCCESSFUL")
                    vals.append({"state": st, "key": "BUILD-%d" % pid, "name": "CI #%d" % (100 + pid),
                                 "url": "http://localhost:%d/ci/builds/%d" % (port, pid),
                                 "description": "Build %s" % st.lower(), "dateAdded": now_ms() - 600_000})
            r = {"size": len(vals), "limit": 25, "isLastPage": True, "values": vals, "start": 0}
            return self.send(200, r)

        if method == "POST" and path == "/ci/trigger":
            print("  CI trigger body: %s" % raw.decode("utf-8", "replace"), flush=True)
            return self.send(201, {"queued": True})

        self.send(404, err("No such resource: %s %s" % (method, path)))

    def pr_route(self, method, sub, qs, user, body, pr, port):
        if method == "GET" and sub == "":
            return self.send(200, pr_json(pr, port))
        if method == "GET" and sub == "/merge":
            return self.send(200, merge_status(pr))
        if method == "POST" and sub == "/merge":
            v = qs.get("version", [None])[0]
            if v is None and isinstance(body, dict):
                v = body.get("version")
            try:
                v = int(v)
            except (TypeError, ValueError):
                v = None
            if v != pr["version"]:
                return self.send(409, err("You are attempting to modify a pull request based on out-of-date information.",
                                          currentVersion=pr["version"], expectedVersion=v))
            ms = merge_status(pr)
            if not ms["canMerge"] or pr["state"] != "OPEN":
                return self.send(409, err("Pull request cannot be merged.", vetoes=ms["vetoes"]))
            pr.update(state="MERGED", open=False, closed=True, updatedDate=now_ms())
            pr["version"] += 1
            return self.send(200, pr_json(pr, port))
        m = re.match(r"^/participants/([^/]+)$", sub)
        if method == "PUT" and m:
            slug = m.group(1)
            if slug != user:
                return self.send(401, err("You are not permitted to modify the status of another user."))
            if slug not in USERS:
                return self.send(404, err("User %s does not exist." % slug))
            if pr["author"]["user"]["name"] == slug:
                return self.send(409, err("The author of a pull request cannot approve it."))
            status = (body or {}).get("status") if isinstance(body, dict) else None
            if status not in ("APPROVED", "UNAPPROVED", "NEEDS_WORK"):
                return self.send(400, err("Invalid status."))
            ent = next((r for r in pr["reviewers"] + pr["participants"] if r["user"]["name"] == slug), None)
            if ent is None:  # a non-reviewer who approves becomes a PARTICIPANT (real Bitbucket behaviour)
                ent = participant(slug, "PARTICIPANT")
                pr["participants"].append(ent)
            ent["approved"] = status == "APPROVED"
            ent["status"] = status
            pr["version"] += 1
            pr["updatedDate"] = now_ms()
            return self.send(200, {"user": ent["user"], "role": ent["role"], "approved": ent["approved"], "status": ent["status"]})
        if method == "POST" and sub == "/comments":
            text = (body or {}).get("text") if isinstance(body, dict) else None
            if text is None:
                return self.send(400, err("Comment text is required."))
            pr["properties"]["commentCount"] += 1
            cid = pr["properties"]["commentCount"] * 100 + pr["id"]
            return self.send(201, {"id": cid, "version": 0, "text": text,
                                   "author": dict(USERS[user]), "createdDate": now_ms()})
        self.send(404, err("No such resource: %s %s" % (method, sub)))

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PUT(self): self.handle_any("PUT")
    def do_DELETE(self): self.handle_any("DELETE")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        PORT = int(sys.argv[1])
    if len(sys.argv) > 2:
        CONTEXT = "/" + sys.argv[2].strip("/")
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    srv.daemon_threads = True
    print("Mock Bitbucket listening on http://localhost:%d%s" % (PORT, CONTEXT), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
