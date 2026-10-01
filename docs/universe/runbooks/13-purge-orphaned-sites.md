# Runbook — take down a deregistered site that is still serving

Rewritten 2026-08-22 after running it against all seven orphans. **The first version was wrong in
two places** and both are corrected below. Read the warnings before the commands.

A deregistered site keeps its R2 alias and therefore keeps serving. This takes it down and
reclaims its bytes.

> **SUPERSEDED 2026-08-25 — do not run the commands below on 1.10.0.**
>
> `?purge=true` is retired: artemis accepts the flag and ignores it, so every command here that
> relies on it now performs a plain reserving `DELETE` instead of a purge. On 1.10.0 the procedure
> for an orphaned alias is one call with no flag:
>
> ```sh
> curl -sS -X DELETE -H "Authorization: Bearer $GH_TOKEN" \
>   "https://uploads.freecode.camp/api/site/<slug>"
> ```
>
> It removes both alias objects and answers `200 {"status":"unpublished","reserved":false}` when the
> name has no registry row, or `204` when it has one and the name is now reserved for 72h. The bytes
> are NOT reclaimed by that call on either path — see `docs/COMPATIBILITY.md` entries 19 and 22, and
> ADR 0006. The nightly sweep trashes a reserved site's origin bytes after the grace period.
>
> `drift-detect` now finds these on its own and reports them as `drift.orphan_aliases`, so the
> hand-written discovery queries below are also obsolete.
>
> Kept as the record of the 2026-08-22 incident and of what 1.9.1 required. Nothing below is a
> current instruction.

## Version boundary — read this first

Everything below describes **artemis 1.9.1 and earlier**, which is what runs in production today.
A fix is committed on `artemis:fix/purge-audit-and-locks` and not yet released. Once it ships, three
things in this runbook stop being true:

- A purge of an orphan returns **200, not 404**, and writes an audit row. `Registry.Delete`
  returning `ErrNotFound` is treated as satisfied.
- Every failed purge writes an audit row naming the stage and how many objects it had already
  moved. There is no longer a silent destructive path.
- The two alias objects move **first**, so the site goes dark in the first second whatever its
  size, and the endpoint refuses to report success while the source prefix still lists objects.

Steps 4 and 6 below — the manual `rclone` legs — exist only because the old code could not finish
a large site. Keep using them until the fix is live.

## Two things that will mislead you

**1. `404` is the success case.** The purge branch runs
`RecordSitePurge` → `MovePrefix` → `Registry.Delete`. For an orphan the registry row is already
gone, so that last call returns `ErrNotFound` and the handler answers `404` — *after* the
destructive work has happened. The same failure skips the audit write, so **a purge that works
leaves no `audit_log` row**. Do not use `curl -f`; it will hide the body and imply failure.

**2. Success does not mean complete.** `MovePrefix` copies and deletes one object at a time at
roughly 0.36 objects/sec, inside a 10-minute `destructiveMoveTimeout`. **Any site above about 215
objects cannot finish in one call.** Two of the seven stalled mid-move and kept serving, because
the alias objects sit at the top of the prefix and were never reached.

**Never trust the response. Verify in R2.**

## Setup

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
export TOKEN=$(gh auth token)
B=universe-static-apps-01
```

`rclone` must have the `r2-fcc` remote configured. The CLI cannot do any of this:
`universe-cli`'s `deleteSite` omits `?purge=true` entirely
(`src/lib/proxy-client.ts:667-674`), so `universe sites rm` performs the very delete that strands
sites.

## 1. Find them — always re-run, never trust an old list

```sh
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -At -F'|' -c "
SELECT a.site, a.name, a.deploy_id FROM aliases a
WHERE NOT EXISTS (SELECT 1 FROM sites s WHERE a.site = s.slug || '.freecode.camp')
ORDER BY a.site, a.name;"
```

Until the code is fixed, every `universe sites rm` adds another one.

## 2. Check the grace window

```sh
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -At -F'|' -c "
SELECT occurred_at, actor, site FROM audit_log
WHERE action IN ('site.delete','site.purge') AND occurred_at > now() - interval '7 days'
ORDER BY occurred_at DESC;"
```

Anything deleted inside 72 hours belongs to someone who may want it back. Confirm with the actor
before touching it.

## 3. Confirm what you are about to destroy

```sh
for s in <slugs>; do
  printf '  %-30s HTTP %s  %s\n' "$s" \
    "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://$s.freecode.camp/?_=$(date +%s)")" \
    "$(curl -sS --max-time 20 "https://$s.freecode.camp/" | grep -oiE '<title>[^<]*' | head -1 | sed 's/<title>//i')"
done
```

## 4. Take the site down first — this is the important step

Move only the two alias objects. The site goes dark in seconds regardless of its size, and it is
fully reversible because nothing is deleted.

```sh
S=<slug>.freecode.camp
for a in production preview; do
  rclone moveto "r2-fcc:$B/$S/$a" "r2-fcc:$B/_trash/$S/$a" -v
done
curl -sS -o /dev/null -w 'now: %{http_code}\n' --max-time 20 "https://$S/?_=$(date +%s)"
```

Expect `404`. Do this before anything slow — it is the whole point of the exercise.

## 5. Write the tombstone, or the bytes are stranded forever

```sh
curl -sS -o /dev/null -w '%{http_code}\n' -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://uploads.freecode.camp/api/site/<slug>?purge=true"
```

Expect `404`. It will also start moving bytes and probably time out — that does not matter here.
What matters is that `RecordSitePurge` runs **before** the move, so the tombstone row gets written.

**Why this is not optional:** `tombstone-purge` reclaims `_trash/<site>/` only
(`internal/gc/tombstone.go:61-69,99`). With no tombstone row, nothing ever collects the site.

```sh
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -At -c \
  "SELECT count(*) FROM tombstones WHERE site LIKE '<slug>%';"
```

Expect `1` or more.

## 6. Move the remaining bytes

The API will not finish a large site. Complete it directly:

```sh
rclone move "r2-fcc:$B/$S/" "r2-fcc:$B/_trash/$S/" --transfers 16 --stats-one-line
```

If a server-side purge is still running, expect `NoSuchKey` errors on the first attempt — both are
deleting the same keys. rclone retries and the second attempt succeeds. Harmless, but it can lose
an object to the race; one was lost this way on `languagegames` (798 in trash against 799
originally).

## 7. Verify — all four must hold

```sh
echo "origin: $(rclone lsf "r2-fcc:$B/$S/" --recursive --files-only | wc -l)"     # expect 0
echo "trash : $(rclone lsf "r2-fcc:$B/_trash/$S/" --recursive --files-only | wc -l)"  # expect > 0
curl -sS -o /dev/null -w 'url   : %{http_code}\n' "https://$S/?_=$(date +%s)"     # expect 404
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -At -c \
  "SELECT count(*) FROM aliases WHERE site='$S';"                                  # expect 0
```

Use `--recursive --files-only` when counting. A bare `rclone lsf` counts top-level entries and
will report a handful when hundreds of files remain — that miscount nearly let a still-serving
site pass as clean.

## What good looks like

Origin prefix empty, bytes in `_trash/`, URL `404`, zero alias rows, at least one tombstone row.
Cross-check against a never-registered hostname, which also returns `404` — that proves the `404`
is real and not a wildcard.
