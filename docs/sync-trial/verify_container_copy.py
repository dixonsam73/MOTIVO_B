#!/usr/bin/env python3
"""Verify a copied Études container (Checkpoint 2 of the private sync trial).

Reads a WORKING COPY of the Core Data store (sqlite + wal + shm are copied
first, so the downloaded originals are never opened), counts sessions and
attachments, checks that every attachment's file is present in Documents/ by
filename (the same rule AttachmentPathResolver uses), hashes every file and
writes a manifest JSON next to the container. Exit code 1 if anything that a
record references is missing.

Usage: verify_container_copy.py <container-dir> <manifest.json>
"""
import hashlib, json, os, shutil, sqlite3, sys, tempfile, uuid
from pathlib import Path

root = Path(sys.argv[1])
out = Path(sys.argv[2])
docs = root / "Documents"
support = root / "Library" / "Application Support"

def uuid_of(blob):
    if blob is None: return None
    if isinstance(blob, bytes) and len(blob) == 16: return str(uuid.UUID(bytes=blob)).upper()
    return str(blob).upper()

with tempfile.TemporaryDirectory() as tmp:
    for suffix in ("", "-wal", "-shm"):
        src = support / f"MOTIVO.sqlite{suffix}"
        if src.exists(): shutil.copy2(src, Path(tmp) / src.name)
    db = sqlite3.connect(f"file:{Path(tmp) / 'MOTIVO.sqlite'}?mode=ro", uri=True)
    sessions = db.execute("select ZID, ZTIMESTAMP, ZTITLE, ZOWNERUSERID from ZSESSION").fetchall()
    attachments = db.execute("select a.ZID, a.ZKIND, a.ZFILEURL, s.ZID from ZATTACHMENT a left join ZSESSION s on a.ZSESSION = s.Z_PK").fetchall()
    owners = sorted({r[3] for r in sessions if r[3]})
    db.close()

files = {}
for p in docs.rglob("*"):
    if p.is_file():
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
        files[str(p.relative_to(docs))] = {"bytes": p.stat().st_size, "sha256": h.hexdigest()}

by_name = {Path(k).name: k for k in files}
att_rows, missing, orphan_attachments = [], [], []
referenced = set()
for aid, kind, fileurl, sid in attachments:
    name = Path(fileurl or "").name
    rel = by_name.get(name)
    if rel: referenced.add(rel)
    else: missing.append({"attachment": uuid_of(aid), "kind": kind, "file": name})
    if sid is None: orphan_attachments.append(uuid_of(aid))
    att_rows.append({"id": uuid_of(aid), "kind": kind, "file": name, "present": rel is not None,
                     "session": uuid_of(sid), **(files.get(rel, {}) if rel else {})})

unreferenced = sorted(k for k in files if k not in referenced and not k.startswith("Scores/"))
manifest = {
    "container": str(root),
    "sessions": len(sessions),
    "attachments": len(attachments),
    "owners": owners,
    "session_date_range_coredata_seconds": [min(r[1] for r in sessions), max(r[1] for r in sessions)] if sessions else None,
    "documents_files": len(files),
    "documents_bytes": sum(v["bytes"] for v in files.values()),
    "scores_files": sum(1 for k in files if k.startswith("Scores/")),
    "attachments_missing_file": missing,
    "attachments_without_session": orphan_attachments,
    "unreferenced_files": unreferenced,
    "attachment_rows": att_rows,
    "files": files,
}
out.write_text(json.dumps(manifest, indent=1))
print(f"sessions={len(sessions)} attachments={len(attachments)} owners={len(owners)} "
      f"files={len(files)} bytes={manifest['documents_bytes']} scores={manifest['scores_files']} "
      f"missing={len(missing)} orphanAttachments={len(orphan_attachments)} unreferenced={len(unreferenced)}")
sys.exit(1 if missing else 0)
