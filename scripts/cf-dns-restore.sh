#!/usr/bin/env bash
# Restore `*`, `@`, `www` A records from a cf-dns-export snapshot JSON.
# Scope mirrors cf-dns-cutover: only the 3 names. Same idempotent delete-then-
# recreate pattern. Requires --apply to commit.
#
# Usage:
#   just cf-dns-restore /tmp/snapshot-pre-cutover.json              # dry-run
#   just cf-dns-restore /tmp/snapshot-pre-cutover.json --apply      # commit
#
# Environment:
#   CF_API_TOKEN  Zone:DNS:Edit scope

set -euo pipefail

SNAPSHOT="${1:?usage: cf-dns-restore <snapshot.json> [--dry-run|--apply]}"
MODE="${2:---dry-run}"

case "$MODE" in
  --dry-run|--apply) ;;
  *) echo "ERROR: mode must be --dry-run or --apply (got: $MODE)" >&2; exit 2 ;;
esac

[ -f "$SNAPSHOT" ] || { echo "ERROR: snapshot file not found: $SNAPSHOT" >&2; exit 2; }
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"

# Export for Python
export SNAPSHOT MODE CF_API_TOKEN

python3 <<'PYTHON_EOF'
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

snapshot_path = os.environ["SNAPSHOT"]
mode = os.environ["MODE"]
token = os.environ["CF_API_TOKEN"]

with open(snapshot_path) as f:
    snap = json.load(f)

if not snap.get("success"):
    sys.exit(f"snapshot is not a successful CF API response: {snap.get('errors')}")

records = snap.get("result", [])
if not records:
    sys.exit("snapshot contains no records")

# Derive zone from the first record's zone_id + zone_name
zone_id = records[0]["zone_id"]
zone_name = records[0]["zone_name"]

API = "https://api.cloudflare.com/client/v4"
HEADERS = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())

# Scope: only restore A records for '@', 'www', '*'.
RESTORE_NAMES = {zone_name, f"www.{zone_name}", f"*.{zone_name}"}
restorable = [r for r in records if r["type"] == "A" and r["name"] in RESTORE_NAMES]

print(f"Zone:     {zone_name} ({zone_id})")
print(f"Snapshot: {len(records)} total records")
print(f"To restore: {len(restorable)} A records across {{@, www, *}}")
print(f"Mode:     {mode}")
print("")

if not restorable:
    sys.exit("no A records for @ www * in snapshot — nothing to restore")

# Step 1: delete current A records for the 3 names
for short, full in [("@", zone_name), ("www", f"www.{zone_name}"), ("*", f"*.{zone_name}")]:
    qs = urllib.parse.urlencode({"name": full, "type": "A"})
    current = req("GET", f"/zones/{zone_id}/dns_records?{qs}")
    for rec in current.get("result", []):
        if mode == "--apply":
            resp = req("DELETE", f"/zones/{zone_id}/dns_records/{rec['id']}")
            assert resp.get("success"), f"delete failed: {resp.get('errors')}"
            print(f"deleted current {short} A (id={rec['id']}, content={rec['content']})")
        else:
            print(f"[dry-run] would delete current {short} A (id={rec['id']}, content={rec['content']})")

# Step 2: recreate from snapshot
for r in restorable:
    short = "@" if r["name"] == zone_name else r["name"].split(".", 1)[0]
    body = {
        "type": "A",
        "name": short,
        "content": r["content"],
        "ttl": r.get("ttl", 60),
        "proxied": r.get("proxied", True),
    }
    if mode == "--apply":
        resp = req("POST", f"/zones/{zone_id}/dns_records", body)
        assert resp.get("success"), f"create failed for {short} -> {r['content']}: {resp.get('errors')}"
        print(f"restored {short} A -> {r['content']}")
    else:
        print(f"[dry-run] would restore {short} A -> {r['content']}")

print("")
print("dry-run complete — re-run with --apply to commit." if mode == "--dry-run" else "restore applied.")
PYTHON_EOF
