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
     A referenced file missing in the candidate is a FAILURE for every role
     (closed 2026-11-04: a receiver that has not been sent a file has not
     finished, and "0 failures" must mean the journal is complete).
  5. Side stores, each compared by MEANING rather than as raw defaults
     blobs: AttachmentPrivacy.json and the selected PDF pages for existing
     attachments; audio/video titles (stored title, `displayName`, or the
     typed file name of a legacy recording — C-176); the score library
     (title, favourite, thumbnail page, page count per item); saved Lists
     (name → lines).
  6. Avatar files (`Library/Application Support/Profiles/*-avatar.png`) by
     content: every derived avatar image in the reference must exist in the
     candidate. The `-original.jpg` beside it is device-local (the receiver
     regenerates it) and only noted.
  7. The profile preferences the sync carries, read from the two Preferences
     plists: location (owner scope, falling back to the local profile),
     primary instrument and name (the Profile row), Journal Tint, the
     instrument colour map (merged by UNION on the other device, so every
     assignment of the reference must stand in the candidate; extras are
     noted), primary activity, the Lists contexts (default List, autofill
     flag, typed preset per activity+instrument), favourites (saved
     sessions) — each a FAILURE when a value the reference holds is absent
     or different in the candidate.

Usage:
  compare_containers.py <reference-dir> <candidate-dir>
        [--reference-plist <name>.plist] [--candidate-plist <name>.plist]
        [--role upgraded|receiver] [--out report.json]

`--role receiver` relaxes only what a second device cannot share by design:
the custom-directory owner ids (per install), the materialised file names
(`<id>.<ext>`; contents are still compared), the per-device default-privacy
flag, and a favourite or a Lists context written under the receiver's own
scope. Exit code 1 when anything the reference holds is missing or different.
"""
import argparse, hashlib, json, plistlib, re, shutil, sqlite3, sys, tempfile, uuid
from collections import Counter
from pathlib import Path

CORE_DATA_EPOCH = 978307200  # 2001-01-01, what Core Data stores dates against
LOCAL_PROFILE_SCOPE = "__local_etudes_profile__"
UUID_RE = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")


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
    # 6. Avatar files, by scope: {scope: {"avatar": sha256 or None, "original": sha256 or None}}
    profiles = root / "Library" / "Application Support" / "Profiles"
    avatars = {}
    if profiles.is_dir():
        for p in profiles.iterdir():
            if p.name.endswith("-avatar.png"):
                avatars.setdefault(p.name[:-len("-avatar.png")], {})["avatar"] = sha256(p)
            elif p.name.endswith("-original.jpg"):
                avatars.setdefault(p.name[:-len("-original.jpg")], {})["original"] = sha256(p)
    out["avatars"] = avatars
    # The owner scope the side stores are keyed by: the sessions' owner.
    owners = Counter(v.get("owneruserid") for v in sessions.values() if v.get("owneruserid"))
    out["owner"] = owners.most_common(1)[0][0] if owners else None
    return out


def read_plist(path):
    if not path or not path.exists():
        return {}
    with open(path, "rb") as f:
        return plistlib.load(f)


def decode(value):
    """A defaults value that is a JSON blob, decoded; anything else as is."""
    if isinstance(value, bytes):
        try:
            return json.loads(value)
        except Exception:
            return {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
    return value


# MARK: side stores, by meaning

def safe_user_key_part(scope):
    """`FeedInteractionStore.safeUserKeyPart`: dots, slashes and spaces become underscores."""
    return scope.replace(".", "_").replace("/", "_").replace(" ", "_")


def title_store(defaults):
    titles = {}
    for key, value in defaults.items():
        if key.startswith(("persistedAudioTitles_v1", "persistedVideoTitles_v1")) and isinstance(value, dict):
            titles.update({k.upper(): v for k, v in value.items()})
    return titles


def effective_title(attachment, titles):
    """What the editor shows for a recording: the row's displayName, else the
    stored title, else (C-176) the typed file name unless it is the app's
    `<id>.<ext>` naming."""
    aid = attachment["_id"]
    if attachment.get("displayname"):
        return attachment["displayname"]
    if titles.get(aid):
        return titles[aid]
    stem = Path(attachment.get("file") or "").stem
    if stem and not UUID_RE.match(stem):
        return stem
    return None


def preset_lines(stored):
    """`JournalListContextValues.normalisedPreset`: typed JSON or a legacy
    `[String]`, reduced to (text, type) lines; None when empty."""
    value = decode(stored)
    lines = []
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                lines.append((item.get("text", ""), item.get("type") or "task"))
            elif isinstance(item, str):
                lines.append((item, "task"))
    return lines or None


def list_contexts(defaults, scope):
    """The Lists settings per (activityRef, instrumentID) under `scope`, from
    the keys the Lists manager and timer write (`JournalSettingsSync.localContexts`)."""
    tasks_prefix = f"practiceTasks_v1::{scope}::"
    autofill_prefix = f"practiceTasks_autofill_enabled::{scope}::"
    default_suffix = "::default_set_id_v1"
    legacy_suffix = "::saved_sets_v1"
    contexts = {}
    for key, value in defaults.items():
        if key.startswith(tasks_prefix):
            rest = key[len(tasks_prefix):]
            if rest.endswith(legacy_suffix):
                continue  # per-context legacy saved sets: not synced, superseded by saved Lists
            field = "default" if rest.endswith(default_suffix) else "preset"
            if field == "default":
                rest = rest[:-len(default_suffix)]
        elif key.startswith(autofill_prefix):
            rest, field = key[len(autofill_prefix):], "autofill"
        else:
            continue
        if not (rest.startswith("core:") or rest.startswith("custom:")):
            continue
        ctx = contexts.setdefault(rest, {"default": "", "autofill": None, "preset": None})
        if field == "default":
            ctx["default"] = value or ""
        elif field == "autofill":
            ctx["autofill"] = bool(value)
        else:
            ctx["preset"] = preset_lines(value)
    return {k: v for k, v in contexts.items() if v["default"] or v["autofill"] is not None or v["preset"]}


def saved_lists(defaults, scope):
    value = decode(defaults.get(f"practiceTasks_saved_sets_v2::{scope}"))
    if not isinstance(value, dict):
        return None
    out = {}
    for lst in value.get("lists", []):
        out[lst.get("name", "")] = [(i.get("text", ""), i.get("type") or "task") for i in lst.get("items", [])]
    return out


def score_index(defaults):
    value = decode(defaults.get("scoreLibrary_v2"))
    if not isinstance(value, list):
        return None
    return {item["id"].upper(): {k: item.get(k) for k in ("title", "isFavourite", "thumbnailPage", "pageCount", "fileName")}
            for item in value if "id" in item}


def favourites(defaults, scope):
    """Saved (hearted) session ids under one viewer scope, or None when the
    scope has no key at all."""
    prefix = "feed.interact.v2.save." + safe_user_key_part(scope) + "."
    keys = {k[len(prefix):].upper(): bool(v) for k, v in defaults.items() if k.startswith(prefix)}
    return keys or None


def tint_map(defaults, scope):
    key = "theme.instrumentTint.slotMap.v1." + (scope.strip().lower() if scope else "__anonymous__")
    value = defaults.get(key)
    return dict(value) if isinstance(value, dict) else None


def location(defaults, scope):
    for s in ([scope] if scope else []) + [LOCAL_PROFILE_SCOPE]:
        v = defaults.get(f"profile.{s}.location")
        if v:
            return v.strip()
    return ""


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
    rd_all = read_plist(ref_root / "Library" / "Preferences" / args.reference_plist)
    cd_all = read_plist(cand_root / "Library" / "Preferences" / args.candidate_plist)
    fails, notes = [], []
    receiver = args.role == "receiver"

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
    # migration when it equals the reference's per-device title store entry, or
    # (C-176) the typed file name of a legacy recording.
    ref_titles, cand_titles = title_store(rd_all), title_store(cd_all)
    migrated_titles = 0
    renamed_files = 0
    for aid, rv in ref["attachments"].items():
        cv = cand["attachments"].get(aid)
        if cv is None:
            fails.append(f"attachment {aid} missing in candidate"); continue
        for k, v in rv.items():
            if cv.get(k) != v:
                if k == "displayname" and v is None and effective_title(dict(rv, _id=aid), ref_titles) == cv.get(k):
                    migrated_titles += 1; continue
                if k == "file" and receiver:
                    renamed_files += 1; continue   # a receiver materialises <id>.<ext>; content is checked below
                fails.append(f"attachment {aid} {k}: reference {v!r} candidate {cv.get(k)!r}")
    if migrated_titles:
        notes.append(f"{migrated_titles} attachment title(s) moved from the title store or the file name onto displayName (stage F migration, C-176)")
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
        if receiver:
            if no_owner(ref[key]) != no_owner(cand[key]):
                fails.append(f"{key} (name, core): reference {no_owner(ref[key])} candidate {no_owner(cand[key])}")
            if ref[key] != cand[key]:
                notes.append(f"{key} owner ids differ (per-install scope, expected on a receiver)")
        elif ref[key] != cand[key]:
            fails.append(f"{key}: reference {ref[key]} candidate {cand[key]}")
    # The Profile row: name and primary instrument are synced (stage H) and
    # must match wherever the reference has a value; the default-privacy flag
    # is per device and only noted on a receiver.
    rp = ref["profile"][0] if ref["profile"] else (None, None, None)
    cp = cand["profile"][0] if cand["profile"] else (None, None, None)
    if len(ref["profile"]) != 1 or len(cand["profile"]) != 1:
        notes.append(f"profile rows: reference {len(ref['profile'])}, candidate {len(cand['profile'])}")
    for label, r, c in (("name", rp[0], cp[0]), ("primary instrument", rp[1], cp[1])):
        if (r or "").strip() != (c or "").strip():
            (fails if (r or "").strip() or not receiver else notes).append(f"profile {label}: reference {r!r} candidate {c!r}")
    if rp[2] != cp[2]:
        (notes if receiver else fails).append(f"profile default privacy: reference {rp[2]!r} candidate {cp[2]!r} (per device, not synced)")

    # 4. files. Missing media is a failure for EVERY role.
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
            fails.append(f"attachment {aid} file {ca['file']} missing in candidate (not delivered)"); continue
        if ref["files"][r]["sha256"] != cand["files"][c]["sha256"]:
            fails.append(f"attachment {aid} file content differs ({name} vs {ca['file']})")
    ref_scores = {k: v for k, v in ref["files"].items() if k.startswith("Scores/")}
    cand_scores = {k: v for k, v in cand["files"].items() if k.startswith("Scores/")}
    for k, v in ref_scores.items():
        c = cand_scores.get(k)
        if c is None:
            fails.append(f"score file {k} missing in candidate (not delivered)")
        elif c["sha256"] != v["sha256"]:
            fails.append(f"score file {k} hash differs")
    extra = sorted(set(cand["files"]) - set(ref["files"]))
    if extra:
        notes.append(f"files in candidate not in reference ({len(extra)}): {extra[:20]}{' …' if len(extra) > 20 else ''}")
    unreferenced_missing = sorted(k for k in ref["files"] if Path(k).name not in ref_attachment_files
                                  and not k.startswith("Scores/") and k not in cand["files"])
    if unreferenced_missing:
        notes.append(f"reference files no attachment references, absent in candidate ({len(unreferenced_missing)}): {unreferenced_missing[:10]}")

    # 5. side stores, for existing attachments only
    live_keys = {f"id://{aid}" for aid in ref["attachments"]}
    ref_privacy = {k: v for k, v in (ref["privacy"] or {}).items() if k in live_keys}
    cand_privacy = {k: v for k, v in (cand["privacy"] or {}).items() if k in live_keys}
    if ref_privacy != cand_privacy:
        fails.append(f"AttachmentPrivacy.json differs for existing attachments: reference {len(ref_privacy)} entries, candidate {len(cand_privacy)}, "
                     f"{sum(1 for k in ref_privacy if cand_privacy.get(k) != ref_privacy[k])} differ")
    stale = len(ref["privacy"] or {}) - len(ref_privacy)
    if stale:
        notes.append(f"reference privacy map holds {stale} entries for attachments that no longer exist (not synced)")
    ref_pages = {k.upper(): v for k, v in (decode(rd_all.get("pdfSelectedPages_v1")) or {}).items()}
    cand_pages = {k.upper(): v for k, v in (decode(cd_all.get("pdfSelectedPages_v1")) or {}).items()}
    pages_differ = [aid for aid in ref["attachments"] if (ref_pages.get(aid) or None) != (cand_pages.get(aid) or None)]
    if pages_differ:
        fails.append(f"selected PDF pages differ for {len(pages_differ)} existing attachment(s): {pages_differ[:5]}")
    stale_pages = sum(1 for k in ref_pages if k not in ref["attachments"])
    if stale_pages:
        notes.append(f"reference page selections for {stale_pages} attachment(s) that no longer exist (not synced)")
    title_differ = []
    for aid, ra in ref["attachments"].items():
        ca = cand["attachments"].get(aid)
        if ca is None or (ra.get("kind") or "").lower() not in ("audio", "video"):
            continue
        rt, ct = effective_title(dict(ra, _id=aid), ref_titles), effective_title(dict(ca, _id=aid), cand_titles)
        if (rt or None) != (ct or None):
            title_differ.append(f"{aid} reference {rt!r} candidate {ct!r}")
    if title_differ:
        fails.append(f"recording titles differ for {len(title_differ)} attachment(s): " + "; ".join(title_differ[:5]) + (" …" if len(title_differ) > 5 else ""))
    stale_titles = sum(1 for k in ref_titles if k not in ref["attachments"])
    if stale_titles:
        notes.append(f"reference title store holds {stale_titles} entries for attachments that no longer exist (not synced)")
    rs, cs = score_index(rd_all), score_index(cd_all)
    if rs is None:
        notes.append("reference has no score library index")
    else:
        cs = cs or {}
        for sid, item in rs.items():
            c = cs.get(sid)
            if c is None:
                fails.append(f"score {sid} ({item.get('title')!r}) missing from the candidate's library index"); continue
            for k in ("title", "isFavourite", "thumbnailPage", "pageCount"):
                if item.get(k) != c.get(k):
                    fails.append(f"score {sid} {k}: reference {item.get(k)!r} candidate {c.get(k)!r}")
            if item.get("fileName") != c.get("fileName"):
                notes.append(f"score {sid} file name differs: reference {item.get('fileName')!r} candidate {c.get('fileName')!r}")
        for sid in set(cs) - set(rs):
            (notes if receiver else fails).append(f"score {sid} in candidate's library but not in reference")
    owner = ref["owner"] or cand["owner"]
    notes.append(f"owner scope used for the side stores: {owner!r}")
    rl = saved_lists(rd_all, owner) if owner else None
    if rl is None:
        notes.append("reference has no saved Lists under the owner scope")
    else:
        cl = saved_lists(cd_all, owner) or {}
        if not cl and receiver:
            cl = saved_lists(cd_all, "device") or {}
        for name, lines in rl.items():
            if name not in cl:
                fails.append(f"saved List {name!r} missing in candidate")
            elif cl[name] != lines:
                fails.append(f"saved List {name!r} lines differ: reference {lines} candidate {cl[name]}")
        for name in set(cl) - set(rl):
            (notes if receiver else fails).append(f"saved List {name!r} in candidate but not in reference")
    ensembles = sorted(k for k in rd_all if k.startswith("EnsembleStore.items"))
    if ensembles:
        notes.append(f"reference ensembles ({len(ensembles)} key(s)) are Connected's and not part of the private sync (by decision, 2026-11-04)")

    # 6. avatar files by content
    ref_avatar_hashes = {v["avatar"] for v in ref["avatars"].values() if v.get("avatar")}
    cand_avatar_hashes = {v["avatar"] for v in cand["avatars"].values() if v.get("avatar")}
    for h in ref_avatar_hashes - cand_avatar_hashes:
        scopes = [s for s, v in ref["avatars"].items() if v.get("avatar") == h]
        fails.append(f"avatar image {h[:12]}… (reference scopes {scopes}) missing in candidate")
    for h in cand_avatar_hashes - ref_avatar_hashes:
        scopes = [s for s, v in cand["avatars"].items() if v.get("avatar") == h]
        (notes if receiver else fails).append(f"avatar image {h[:12]}… in candidate (scopes {scopes}) not in reference")
    if ref["avatars"] or cand["avatars"]:
        same_scopes = sorted(s for s in ref["avatars"] if cand["avatars"].get(s, {}).get("avatar") == ref["avatars"][s].get("avatar"))
        notes.append(f"avatar files: reference scopes {sorted(ref['avatars'])}, candidate scopes {sorted(cand['avatars'])}, "
                     f"derived image identical for {same_scopes}; -original.jpg is device-local ("
                     f"{sum(1 for s in ref['avatars'] if ref['avatars'][s].get('original') and ref['avatars'][s].get('original') == cand['avatars'].get(s, {}).get('original'))} identical)")

    # 7. profile preferences the sync carries
    rloc, cloc = location(rd_all, owner), location(cd_all, owner)
    if rloc != cloc:
        (fails if rloc or not receiver else notes).append(f"profile location: reference {rloc!r} candidate {cloc!r}")
    rtint = rd_all.get("appSettings_tintMode") or "auto"
    ctint = cd_all.get("appSettings_tintMode") or "auto"
    if rtint != ctint:
        fails.append(f"Journal Tint: reference {rtint!r} candidate {ctint!r}")
    ract = rd_all.get("primaryActivityRef") or "core:0"
    cact = cd_all.get("primaryActivityRef") or "core:0"
    if ract != cact:
        fails.append(f"primary activity: reference {ract!r} candidate {cact!r}")
    rmap = tint_map(rd_all, owner)
    if rmap is None:
        notes.append("reference has no instrument colour map under the owner scope")
    else:
        cmap = tint_map(cd_all, owner) or {}
        missing = {k: v for k, v in rmap.items() if cmap.get(k) != v}
        if missing:
            fails.append(f"instrument colours: {len(missing)} assignment(s) of the reference not in candidate: {missing} (candidate {cmap})")
        extra_labels = sorted(set(cmap) - set(rmap))
        if extra_labels:
            notes.append(f"instrument colours: candidate assigns {extra_labels} the reference does not (union merge)")
    rctx = list_contexts(rd_all, owner) if owner else {}
    cctx = list_contexts(cd_all, owner) if owner else {}
    if not cctx and receiver:
        cctx = list_contexts(cd_all, "device")
    if not rctx:
        notes.append("reference has no Lists contexts under the owner scope")
    for ctx, rv in rctx.items():
        cv = cctx.get(ctx)
        if cv is None:
            fails.append(f"Lists context {ctx}: missing in candidate (reference {rv})"); continue
        for field in ("default", "autofill", "preset"):
            if rv[field] in ("", None):
                continue  # nothing to carry
            if rv[field] != cv[field]:
                fails.append(f"Lists context {ctx} {field}: reference {rv[field]!r} candidate {cv[field]!r}")
    for ctx in set(cctx) - set(rctx):
        (notes if receiver else fails).append(f"Lists context {ctx} in candidate but not in reference ({cctx[ctx]})")
    rfav = favourites(rd_all, owner) if owner else None
    if rfav is None:
        notes.append("reference carries no favourites under the owner scope (nothing to compare)")
    else:
        cfav = {}
        for key, value in cd_all.items():
            if key.startswith("feed.interact.v2.save."):
                cfav[key.rsplit(".", 1)[-1].upper()] = cfav.get(key.rsplit(".", 1)[-1].upper(), False) or bool(value)
        saved_ref = {sid for sid, v in rfav.items() if v and sid in ref["sessions"]}
        saved_cand = {sid for sid, v in cfav.items() if v and sid in ref["sessions"]}
        for sid in saved_ref - saved_cand:
            fails.append(f"favourite session {sid} not saved in candidate")
        for sid in saved_cand - saved_ref:
            (notes if receiver else fails).append(f"session {sid} saved in candidate but not in reference")
        notes.append(f"favourites: {len(saved_ref)} saved session(s) in the reference, {len(saved_cand)} in the candidate")

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
