#!/usr/bin/env python3
"""Compare two copied Études containers field by field (the populated upgrade
trial, 2026-11-04). Never counts alone: every session, attachment, link and
file of the REFERENCE copy must be found in the CANDIDATE copy with the same
values, and the candidate must hold nothing the reference does not explain.

Reads WORKING COPIES of each Core Data store (sqlite + wal + shm copied to a
temporary directory first, so the originals are never opened) and compares:

  1. Sessions by id: timestamp, duration, title, notes, activity type and
     detail, mood, effort, thread label, public flag, private-notes flag,
     owner, user activity/instrument labels, instrument NAME (ids may differ
     between devices), tag names.
  2. Attachments by id: kind, file name, session id, created date, display
     name, thumbnail flag, owner; and each session's ordered attachment list.
  3. Directories by name: Instrument, UserInstrument (name, core code),
     UserActivity (name, core code), the Profile row (name, primary
     instrument, default privacy).
  4. Files: every attachment file by name with its SHA-256; Documents/Scores
     by name and hash; files in the candidate the reference does not have.
  5. Side stores: AttachmentPrivacy.json; chosen UserDefaults keys (score
     library index, audio/video titles, PDF pages, saved task sets, primary
     activity), read from the two Preferences plists.

Usage:
  compare_containers.py <reference-dir> <candidate-dir>
        [--reference-plist <name>.plist] [--candidate-plist <name>.plist]
        [--role upgraded|receiver] [--out report.json]

`--role receiver` relaxes what a second device cannot share by design: the
custom-directory owner ids (per install), the per-device title store scope,
and files the receiver has not been sent yet are reported, not failed.
Exit code 1 when any session, attachment, link or referenced file differs.
"""
import argparse, hashlib, json, plistlib, shutil, sqlite3, sys, tempfile, uuid
from pathlib import Path

CORE_DATA_EPOCH = 978307200  # 2001-01-01, what Core Data stores dates against


def uuid_of(blob):
    if blob is None:
        return None
    if isinstance(blob, bytes) and len(blob) == 16:
        return str(uuid.UUID(bytes=blob)).upper()
    return str(blob).upper()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def norm(v):
    """Values that mean the same thing compare equal: None and '' for text."""
    if isinstance(v, float):
        return round(v, 3)
    if v == "":
        return None
    return v


def open_store(root):
    support = root / "Library" / "Application Support"
    tmp = Path(tempfile.mkdtemp(prefix="etudes-compare-"))
    for suffix in ("", "-wal", "-shm"):
        src = support / f"MOTIVO.sqlite{suffix}"
        if src.exists():
            shutil.copy2(src, tmp / src.name)
    return sqlite3.connect(f"file:{tmp / 'MOTIVO.sqlite'}?mode=ro", uri=True), tmp


def columns(db, table):
    return {r[1] for r in db.execute(f"pragma table_info({table})")}


def read_container(root):
    db, tmp = open_store(root)
    out = {}
    scols = columns(db, "ZSESSION")
    has_umod = "ZUSERMODIFIEDAT" in scols
    instruments = {r[0]: r[1] for r in db.execute("select Z_PK, ZNAME from ZINSTRUMENT")}
    tag_names = {r[0]: r[1] for r in db.execute("select Z_PK, ZNAME from ZTAG")}
    # session ↔ tag join table name varies with the entity numbering; find it.
    join = next((r[0] for r in db.execute("select name from sqlite_master where type='table' and name like 'Z_%TAGS'")), None)
    session_tags = {}
    if join:
        jcols = [r[1] for r in db.execute(f"pragma table_info({join})")]
        scol = next(c for c in jcols if "SESSION" in c)
        tcol = next(c for c in jcols if "TAG" in c)
        for s, t in db.execute(f"select {scol}, {tcol} from {join}"):
            session_tags.setdefault(s, set()).add(tag_names.get(t))
    sessions = {}
    pk_to_id = {}
    fields = ["ZTIMESTAMP", "ZDURATIONSECONDS", "ZTITLE", "ZNOTES", "ZACTIVITYTYPE", "ZACTIVITYDETAIL", "ZMOOD", "ZEFFORT",
              "ZTHREADLABEL", "ZISPUBLIC", "ZARENOTESPRIVATE", "ZOWNERUSERID", "ZUSERACTIVITYLABEL", "ZUSERINSTRUMENTLABEL"]
    present = [f for f in fields if f in scols]
    q = f"select Z_PK, ZID, ZINSTRUMENT, {', '.join(present)}{', ZUSERMODIFIEDAT' if has_umod else ''} from ZSESSION"
    for row in db.execute(q):
        pk, sid, inst = row[0], uuid_of(row[1]), row[2]
        pk_to_id[pk] = sid
        values = {f[1:].lower(): norm(v) for f, v in zip(present, row[3:3 + len(present)])}
        values["instrument"] = instruments.get(inst)
        values["tags"] = sorted(t for t in session_tags.get(pk, set()) if t)
        values["usermodifiedat"] = norm(row[-1]) if has_umod else None
        sessions[sid] = values
    acols = columns(db, "ZATTACHMENT")
    afields = ["ZKIND", "ZFILEURL", "ZCREATEDAT", "ZDISPLAYNAME", "ZISTHUMBNAIL", "ZOWNERUSERID"]
    apresent = [f for f in afields if f in acols]
    attachments = {}
    for row in db.execute(f"select ZID, ZSESSION, {', '.join(apresent)} from ZATTACHMENT"):
        aid = uuid_of(row[0])
        values = {f[1:].lower(): norm(v) for f, v in zip(apresent, row[2:])}
        values["file"] = Path(values.pop("fileurl") or "").name or None
        values["session"] = pk_to_id.get(row[1])
        attachments[aid] = values
    per_session = {}
    for aid, a in attachments.items():
        per_session.setdefault(a["session"], []).append((a.get("createdat") or 0, aid))
    out["session_attachments"] = {s: [aid for _, aid in sorted(v)] for s, v in per_session.items()}
    out["sessions"], out["attachments"] = sessions, attachments
    out["instruments"] = sorted(instruments.values())
    out["user_instruments"] = sorted((r[0], instruments.get(r[1]), r[2]) for r in db.execute("select ZDISPLAYNAME, ZCOREINSTRUMENT, ZOWNERUSERID from ZUSERINSTRUMENT"))
    out["user_activities"] = sorted((r[0], r[1], r[2]) for r in db.execute("select ZDISPLAYNAME, ZCOREACTIVITYCODE, ZOWNERUSERID from ZUSERACTIVITY"))
    out["profile"] = [tuple(r) for r in db.execute("select ZNAME, ZPRIMARYINSTRUMENT, ZDEFAULTPRIVACY from ZPROFILE")]
    meta = plistlib.loads(db.execute("select Z_PLIST from Z_METADATA").fetchone()[0])
    tables = {r[0] for r in db.execute("select name from sqlite_master where type='table'")}
    history = "ATRANSACTION" in tables
    out["store_meta"] = {
        "model_versions": meta.get("NSStoreModelVersionIdentifiers"),
        "history_tracking": history,
        "history_transactions": db.execute("select count(*) from ATRANSACTION").fetchone()[0] if history else 0,
        "history_authors": [r[0] for r in db.execute("select distinct ZAUTHOR from ATRANSACTION")] if history else [],
        "has_userModifiedAt": has_umod,
    }
    db.close()
    shutil.rmtree(tmp, ignore_errors=True)
    docs = root / "Documents"
    files = {}
    for p in docs.rglob("*"):
        if p.is_file():
            files[str(p.relative_to(docs))] = {"bytes": p.stat().st_size, "sha256": sha256(p)}
    out["files"] = files
    privacy = root / "Library" / "Application Support" / "AttachmentPrivacy.json"
    out["privacy"] = json.loads(privacy.read_text()) if privacy.exists() else None
    return out


def read_plist(path):
    if not path or not path.exists():
        return {}
    with open(path, "rb") as f:
        return plistlib.load(f)


def defaults_view(d):
    """The keys the trial compares, decoded where they are JSON blobs."""
    view = {}
    for key, value in d.items():
        if key.startswith(("scoreLibrary_v2", "persistedAudioTitles_v1", "persistedVideoTitles_v1", "pdfSelectedPages_v1",
                           "practiceTasks_saved_sets_v2", "primaryActivityRef", "EnsembleStore.items")):
            if isinstance(value, bytes):
                try:
                    value = json.loads(value)
                except Exception:
                    value = {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
            if key.startswith("scoreLibrary_v2") and isinstance(value, list):
                # Device-local by design (stage I): when a score was last opened
                # here and the page it was left on are never part of the record.
                value = [{k: v for k, v in item.items() if k not in ("lastOpenedAt", "lastViewedPage")} for item in value]
            view[key] = value
    return view


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference"); ap.add_argument("candidate")
    ap.add_argument("--reference-plist", default="com.samueldixon.motivo.dev.plist")
    ap.add_argument("--candidate-plist", default="com.samueldixon.motivo.synctest.plist")
    ap.add_argument("--role", choices=["upgraded", "receiver"], default="upgraded")
    ap.add_argument("--out")
    args = ap.parse_args()
    ref_root, cand_root = Path(args.reference), Path(args.candidate)
    ref, cand = read_container(ref_root), read_container(cand_root)
    fails, notes = [], []

    # 1. sessions
    for sid, rv in ref["sessions"].items():
        cv = cand["sessions"].get(sid)
        if cv is None:
            fails.append(f"session {sid} missing in candidate"); continue
        for k, v in rv.items():
            if k == "usermodifiedat":
                continue
            if cv.get(k) != v:
                fails.append(f"session {sid} {k}: reference {v!r} candidate {cv.get(k)!r}")
    for sid in set(cand["sessions"]) - set(ref["sessions"]):
        fails.append(f"session {sid} in candidate but not in reference ({cand['sessions'][sid].get('title')!r})")
    stamped = sum(1 for v in cand["sessions"].values() if v.get("usermodifiedat") is not None)
    notes.append(f"candidate sessions carrying userModifiedAt: {stamped} of {len(cand['sessions'])}")

    # 2. attachments and order. A displayName the reference lacks is the stage F
    # migration when it equals the reference's per-device title store entry.
    ref_titles = {}
    for key, value in read_plist(ref_root / "Library" / "Preferences" / args.reference_plist).items():
        if key.startswith(("persistedAudioTitles_v1", "persistedVideoTitles_v1")) and isinstance(value, dict):
            ref_titles.update({k.upper(): v for k, v in value.items()})
    migrated_titles = 0
    renamed_files = 0
    for aid, rv in ref["attachments"].items():
        cv = cand["attachments"].get(aid)
        if cv is None:
            fails.append(f"attachment {aid} missing in candidate"); continue
        for k, v in rv.items():
            if cv.get(k) != v:
                if k == "displayname" and v is None and ref_titles.get(aid) == cv.get(k):
                    migrated_titles += 1; continue
                if k == "file" and args.role == "receiver":
                    renamed_files += 1; continue   # a receiver materialises <id>.<ext>; content is checked below
                fails.append(f"attachment {aid} {k}: reference {v!r} candidate {cv.get(k)!r}")
    if migrated_titles:
        notes.append(f"{migrated_titles} attachment title(s) moved from the title store onto displayName (stage F migration)")
    if renamed_files:
        notes.append(f"{renamed_files} attachment file(s) materialised under the attachment id on the receiver (by design); contents compared per attachment")
    for aid in set(cand["attachments"]) - set(ref["attachments"]):
        fails.append(f"attachment {aid} in candidate but not in reference")
    for sid, order in ref["session_attachments"].items():
        if cand["session_attachments"].get(sid) != order:
            fails.append(f"session {sid} attachment order: reference {order} candidate {cand['session_attachments'].get(sid)}")

    # 3. directories
    if ref["instruments"] != cand["instruments"]:
        fails.append(f"instrument names: reference {ref['instruments']} candidate {cand['instruments']}")
    def no_owner(rows): return sorted((n, c) for n, c, _ in rows)
    for key in ("user_instruments", "user_activities"):
        if args.role == "receiver":
            if no_owner(ref[key]) != no_owner(cand[key]):
                fails.append(f"{key} (name, core): reference {no_owner(ref[key])} candidate {no_owner(cand[key])}")
            if ref[key] != cand[key]:
                notes.append(f"{key} owner ids differ (per-install scope, expected on a receiver)")
        elif ref[key] != cand[key]:
            fails.append(f"{key}: reference {ref[key]} candidate {cand[key]}")
    if ref["profile"] != cand["profile"]:
        (fails if args.role == "upgraded" else notes).append(f"profile row: reference {ref['profile']} candidate {cand['profile']}")

    # 4. files
    ref_attachment_files = {a["file"] for a in ref["attachments"].values() if a["file"]}
    ref_by_name = {Path(k).name: k for k in ref["files"]}
    cand_by_name = {Path(k).name: k for k in cand["files"]}
    for aid, ra in ref["attachments"].items():
        name = ra["file"]
        ca = cand["attachments"].get(aid)
        if not name or ca is None:
            continue
        r, c = ref_by_name.get(name), cand_by_name.get(ca["file"] or "")
        if r is None:
            fails.append(f"reference attachment file {name} missing in reference copy"); continue
        if c is None:
            (fails if args.role == "upgraded" else notes).append(f"attachment {aid} file {ca['file']} missing in candidate"); continue
        if ref["files"][r]["sha256"] != cand["files"][c]["sha256"]:
            fails.append(f"attachment {aid} file content differs ({name} vs {ca['file']})")
    ref_scores = {k: v for k, v in ref["files"].items() if k.startswith("Scores/")}
    cand_scores = {k: v for k, v in cand["files"].items() if k.startswith("Scores/")}
    for k, v in ref_scores.items():
        c = cand_scores.get(k)
        if c is None:
            (fails if args.role == "upgraded" else notes).append(f"score file {k} missing in candidate")
        elif c["sha256"] != v["sha256"]:
            fails.append(f"score file {k} hash differs")
    extra = sorted(set(cand["files"]) - set(ref["files"]))
    if extra:
        notes.append(f"files in candidate not in reference ({len(extra)}): {extra[:20]}{' …' if len(extra) > 20 else ''}")
    unreferenced_missing = sorted(k for k in ref["files"] if Path(k).name not in ref_attachment_files
                                  and not k.startswith("Scores/") and k not in cand["files"])
    if unreferenced_missing:
        notes.append(f"reference files no attachment references, absent in candidate ({len(unreferenced_missing)}): {unreferenced_missing[:10]}")

    # 5. side stores
    live_keys = {f"id://{aid}" for aid in ref["attachments"]}
    ref_privacy = {k: v for k, v in (ref["privacy"] or {}).items() if k in live_keys}
    cand_privacy = {k: v for k, v in (cand["privacy"] or {}).items() if k in live_keys}
    if ref_privacy != cand_privacy:
        fails.append(f"AttachmentPrivacy.json differs for existing attachments: reference {len(ref_privacy)} entries, candidate {len(cand_privacy)}, "
                     f"{sum(1 for k in ref_privacy if cand_privacy.get(k) != ref_privacy[k])} differ")
    stale = len(ref["privacy"] or {}) - len(ref_privacy)
    if stale:
        notes.append(f"reference privacy map holds {stale} entries for attachments that no longer exist (not synced)")
    if ref["privacy"] != cand["privacy"] and args.role == "upgraded" and ref_privacy == cand_privacy:
        notes.append("privacy map differs only in entries for attachments that no longer exist")
    rd = defaults_view(read_plist(ref_root / "Library" / "Preferences" / args.reference_plist))
    cd = defaults_view(read_plist(cand_root / "Library" / "Preferences" / args.candidate_plist))
    for key in sorted(set(rd) | set(cd)):
        if rd.get(key) != cd.get(key):
            (fails if args.role == "upgraded" and key in rd else notes).append(
                f"defaults {key}: {'equal' if rd.get(key) == cd.get(key) else 'differs'} (reference {'set' if key in rd else 'absent'}, candidate {'set' if key in cd else 'absent'})")

    report = {
        "reference": str(ref_root), "candidate": str(cand_root), "role": args.role,
        "reference_store": ref["store_meta"], "candidate_store": cand["store_meta"],
        "counts": {"reference_sessions": len(ref["sessions"]), "candidate_sessions": len(cand["sessions"]),
                   "reference_attachments": len(ref["attachments"]), "candidate_attachments": len(cand["attachments"]),
                   "reference_files": len(ref["files"]), "candidate_files": len(cand["files"])},
        "failures": fails, "notes": notes,
    }
    if args.out:
        Path(args.out).write_text(json.dumps(report, indent=1, default=str))
    print(json.dumps(report["counts"]), "| reference store", ref["store_meta"], "| candidate store", cand["store_meta"])
    for n in notes:
        print("note:", n)
    for f in fails:
        print("FAIL:", f)
    print(f"{len(fails)} failure(s), {len(notes)} note(s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
