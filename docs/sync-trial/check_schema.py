#!/usr/bin/env python3
"""Check a CloudKit schema export (.ckdb) against every record type and field
the private sync writes. Run it on the Production export before any Production
build sends: Production refuses a field it does not know, and the Development
environment hides the gap by creating fields just in time.

Why it exists (2026-11-10, C-184): the trial container's development schema
was taken as complete, but CloudKit creates a field only when a NON-NIL value
is saved, and the trial journal never held a custom instrument or activity
label or a score made from an attachment. Three fields were missing from the
export and were added by hand before the Production deploy.

The table is the code's, kept by hand: `JournalRecordMapping` (sessionKeys,
attachmentKeys, metaKeys, the directory keys, the link, asset and list keys),
`JournalMetadataKeys`, `JournalProfileKeys`, `JournalScoreKeys`,
`JournalSettingsKeys`. A new synced field must be added here AND to the
schema before a build that writes it ships.

Usage: check_schema.py <export.ckdb> [more.ckdb …]   (exit 1 on any gap)
"""
import re, sys
from pathlib import Path

EXPECTED = {
    "Session": {"title": "STRING", "notes": "STRING", "activityDetail": "STRING", "threadLabel": "STRING",
                "userInstrumentLabel": "STRING", "userActivityLabel": "STRING", "ownerUserID": "STRING",
                "instrumentName": "STRING", "timestamp": "TIMESTAMP", "userModifiedAt": "TIMESTAMP",
                "durationSeconds": "INT64", "activityType": "INT64", "mood": "INT64", "effort": "INT64",
                "areNotesPrivate": "INT64", "isPublic": "INT64", "isSaved": "INT64", "instrumentRef": "REFERENCE"},
    "Attachment": {"kind": "STRING", "fileExt": "STRING", "fileHash": "STRING", "createdAt": "TIMESTAMP",
                   "userModifiedAt": "TIMESTAMP", "session": "REFERENCE", "file": "ASSET"},
    "AttachmentMeta": {"displayName": "STRING", "selectedPages": "STRING", "isThumbnail": "INT64",
                       "isPrivate": "INT64", "userModifiedAt": "TIMESTAMP"},
    "Instrument": {"name": "STRING"},
    "UserInstrument": {"displayName": "STRING", "normalizedName": "STRING", "instrumentName": "STRING",
                       "displayOrder": "INT64", "isVisibleOnProfile": "INT64", "instrumentRef": "REFERENCE"},
    "UserActivity": {"displayName": "STRING", "normalizedName": "STRING", "coreActivityCode": "INT64"},
    "SavedList": {"name": "STRING", "items": "BYTES"},
    "Profile": {"name": "STRING", "location": "STRING", "instrumentName": "STRING", "instrumentRef": "REFERENCE",
                "userModifiedAt": "TIMESTAMP"},
    "ProfileAvatar": {"file": "ASSET", "fileHash": "STRING", "userModifiedAt": "TIMESTAMP"},
    "Score": {"file": "ASSET", "fileHash": "STRING", "fileExt": "STRING", "fileName": "STRING",
              "sourceAttachmentID": "STRING", "initialTitle": "STRING", "pageCount": "INT64", "createdAt": "TIMESTAMP"},
    "ScoreMeta": {"title": "STRING", "isFavourite": "INT64", "thumbnailPage": "INT64", "userModifiedAt": "TIMESTAMP"},
    "ScorePosition": {"lastViewedPage": "INT64", "userModifiedAt": "TIMESTAMP"},
    "Setting": {"value": "STRING", "userModifiedAt": "TIMESTAMP"},
    "ListContext": {"activityRef": "STRING", "instrumentName": "STRING", "defaultListID": "STRING",
                    "autofill": "INT64", "preset": "BYTES", "userModifiedAt": "TIMESTAMP"},
    "TintMap": {"map": "BYTES"},
}


def parse(path):
    out = {}
    for m in re.finditer(r"RECORD TYPE (\w+) \((.*?)\n\s*\);", Path(path).read_text(), re.S):
        fields = {}
        for line in m.group(2).split("\n"):
            fm = re.match(r'"?([\w_]+)"?\s+(\w+)', line.strip().rstrip(","))
            if fm and not line.strip().startswith("GRANT"):
                fields[fm.group(1)] = fm.group(2)
        out[m.group(1)] = fields
    return out


def main():
    bad = 0
    for path in sys.argv[1:]:
        got, gaps, extras = parse(path), [], []
        for rtype, fields in EXPECTED.items():
            if rtype not in got:
                gaps.append(f"record type {rtype} missing"); continue
            for name, kind in fields.items():
                have = got[rtype].get(name)
                if have is None:
                    gaps.append(f"{rtype}.{name} ({kind}) missing")
                elif have != kind:
                    gaps.append(f"{rtype}.{name}: the code writes {kind}, the schema says {have}")
            more = sorted(k for k in got[rtype] if k not in fields and not k.startswith("___"))
            if more:
                extras.append(f"{rtype}: {more}")
        print(f"{path}: {len(EXPECTED)} record types, {sum(len(f) for f in EXPECTED.values())} fields expected; "
              f"{len(gaps)} gap(s)")
        for g in gaps:
            print("  GAP:", g)
        for e in extras:
            print("  note: fields in the schema the current code does not write —", e)
        bad += len(gaps)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
