# Privacy policy and terms — drafts for optional iCloud sync (not published)

Written 2026-11-04 for Samuel's review. The documents of record are the
Desktop drafts (`~/Desktop/ETUDES legal documents/Etudes-Privacy-Policy-DRAFT-2026-09-23.docx`
and `Etudes-Terms-of-Use-DRAFT-2026-09-23.docx`, both "Last updated: [date of
publication]"); the website copies at `etudes.app/privacy` and `/terms` are
holding pages. Each item below quotes the current passage and gives the
replacement beside it. Nothing has been changed in the drafts or published.

What the sync does, as built (the wording must stay true to this):

- Off by default. The person turns it on in Profile ("Sync this journal with
  iCloud") or on the set-up screen of a second device.
- On, it uploads to **the person's own iCloud private database** (Apple's
  CloudKit, container `iCloud.com.sdsongs.etudes`): the journal (sessions,
  Thoughts, notes, titles, tags, favourites, privacy choices and page
  selections), attachments (photos, videos, recordings, PDFs), scores and
  their reading positions, the profile name, location and avatar, the
  personal settings (Journal Tint, instrument colours, primary activity),
  saved Lists and the Lists settings per activity and instrument. We cannot
  read any of it; Apple holds it under Apple's terms, counted against the
  person's iCloud storage.
- Not synced: ensembles and everything else that belongs to Études
  Connected; tool visibility and layout settings; drafts, the running timer
  and unfinished recordings.
- Sync is not a backup: it keeps devices the same, so a deletion on one is a
  deletion everywhere; Apple's normal device backup remains the backup.
- Turning it off keeps everything on the device and stops sending and
  receiving; what was uploaded stays in iCloud until it is removed (from
  another device with sync on, or through iCloud's own data management).
- "Remove Études Data from This Device" leaves the iCloud journal and other
  devices unchanged; the journal can be restored to that device afterwards.
- Deleting a Connected account erases this device's Études data and deletes
  the Connected content; it does **not** touch the iCloud journal, which
  stays for the person's other devices or a later restore — also when sync
  was turned on once and is off now (the upload is kept, as section 3 says).

## Privacy policy

**P1 — Section 1, opening paragraph.**

Current:

> Études on its own (Solo) collects nothing. Your journal, recordings, scores, lists and settings stay on your iPhone. You need no account, and nothing is sent to us.

Replacement:

> Études on its own (Solo) collects nothing. Your journal, recordings, scores, lists and settings stay on your iPhone, and nothing is sent to us. You need no account. If you choose to turn on iCloud sync, Études keeps a copy of your journal in your own iCloud account so that your other devices show the same journal; we cannot see it (section 3).

**P2 — "If you're young" paragraph.**

Current:

> … Everything you write, record or save in it stays on your iPhone. We don't collect anything from Solo, we can't see it, and nobody else can either. …

Replacement:

> … Everything you write, record or save in it stays on your iPhone, or, if you turn on iCloud sync, in your own iCloud account. We don't collect anything from Solo, we can't see it, and nobody else can either. …

**P3 — Section 3, "What stays on your iPhone" (title and body).**

Current:

> 3. What stays on your iPhone
> Your journal, sessions, notes, Thoughts, recordings, photos, videos, scores, lists, tasks and settings are stored on your device. They are included in your normal iPhone backups (iCloud or your computer), which Apple provides under its own terms. We cannot see any of it. Your membership ending, for any reason, never deletes any of it.

Replacement:

> 3. What stays on your iPhone, and optional iCloud sync
> Your journal, sessions, notes, Thoughts, recordings, photos, videos, scores, lists, tasks and settings are stored on your device. They are included in your normal iPhone backups (iCloud or your computer), which Apple provides under its own terms. We cannot see any of it. Your membership ending, for any reason, never deletes any of it.
>
> iCloud sync is optional and off until you turn it on in Profile. When it is on, Études uploads your journal and its attachments, your scores, your profile name, location and photo, and your Études settings and lists to the private part of your own iCloud account, and brings them to your other devices signed in to the same iCloud account. This uses Apple's iCloud under Apple's terms and counts against your iCloud storage; the data goes only to your iCloud account, never to us, and we cannot read it. Ensembles and the other Études Connected features are not part of this sync.
>
> Sync keeps your devices the same; it is not a backup. If you delete something on one device it is deleted on the others. Keep your normal iPhone backup.
>
> Turning sync off keeps everything on that device and stops it sending and receiving. What was already uploaded stays in your iCloud account until it is removed: delete it from another device that still syncs, or remove the Études data from iCloud in your iPhone's Settings (Apple Account → iCloud → Manage Storage).
>
> "Remove Études Data from This Device" (Profile) removes the journal from that device only; your iCloud copy and your other devices are unchanged, and you can restore the journal to that device later.

**P4 — Section 7 (deletion), the "Delete Account" paragraph.**

Current:

> Profile → Delete Account removes your Connected account and your posts, comments you wrote and files you sent, even if a follower still has them in their inbox. It does not delete comments other people wrote to you, or anything someone has already saved to their own device. It never requires an active membership. It also erases all Études data on that iPhone, including your journal, as the button says, so keep a copy of anything you want first. The only exception is data we must keep by law (see section 8).

Replacement:

> Profile → Delete Account removes your Connected account and your posts, comments you wrote and files you sent, even if a follower still has them in their inbox. It does not delete comments other people wrote to you, or anything someone has already saved to their own device. It never requires an active membership. It also erases all Études data on that iPhone, including your journal, as the button says, so keep a copy of anything you want first. If you have previously turned on iCloud sync, whether or not it is on now, the copy of your journal in your own iCloud account is not deleted by this: it stays for your other devices, or for restoring later, until you remove it yourself (section 3). The only exception to deletion is data we must keep by law (see section 8).

**P5 — Section 2 / the data table, if the policy lists where data is stored
(Samuel to check the Desktop draft's table).** Add one row: *iCloud sync
(optional)* — the journal, attachments, scores, profile name, location and
photo, settings and lists — stored in your own iCloud account by Apple;
not received by us; kept until you remove it or turn sync off and delete it
from iCloud.

**App Store privacy labels.** Data that goes only to the person's own iCloud
private database, which we cannot access, is not something we collect;
Apple's App Privacy Details guidance should be read to confirm that no label
changes before this ships to the public. Nothing changes for the internal
TestFlight trial.

## Terms of Use

**T1 — Section 1.**

Current:

> Études (Solo) is a private practice journal. It needs no account, everything stays on your iPhone, and anyone may use it.

Replacement:

> Études (Solo) is a private practice journal. It needs no account, everything stays on your iPhone unless you turn on the optional iCloud sync, and anyone may use it.

**T2 — Section 2 or a new short section, "iCloud sync", after the Solo
description.**

New:

> iCloud sync is optional and off until you turn it on. When it is on, Études stores a copy of your journal, attachments, scores, profile and settings in your own iCloud account and keeps your devices the same. It uses Apple's iCloud under Apple's terms and your iCloud storage. It is not a backup: a deletion on one device is a deletion on all of them, and you remain responsible for backing up your device. We cannot see, recover or restore anything you store in iCloud. Turning sync off keeps what is on the device and stops transfers; what was uploaded stays in your iCloud account until you remove it. Ensembles and other Connected features are not part of iCloud sync.

**T3 — Section 4, the "You are responsible…" paragraph.**

Current:

> You are responsible for what you share and for backing up your own device. Deleting your Connected account also erases all Études data on that iPhone, as the button says.

Replacement:

> You are responsible for what you share and for backing up your own device. Deleting your Connected account also erases all Études data on that iPhone, as the button says; it does not delete a copy of your journal in your iCloud account from a time you had iCloud sync turned on, which stays until you remove it.

**T4 — Section 3 (subscription ending), the "If your subscription ends"
paragraph.** No change needed: "your journal and everything on your iPhone
stay exactly as they are" remains true, and iCloud sync is independent of
the membership.

**T5 — Section 8 (liability), "Please keep your iPhone backed up, as we
cannot see or recover what is stored on it."**

Replacement:

> Please keep your iPhone backed up, as we cannot see or recover what is stored on it or in your iCloud account.

## In-app copy already in place (for consistency with the above)

- Profile toggle: "Optional. On: your journal, scores, profile and settings
  are kept the same on every device signed in to the same iCloud account.
  Off: this device keeps everything it has and stops sending and receiving;
  what was already uploaded stays in iCloud. Ensembles and other Connected
  features are not part of this sync."
- Set-up card: "iCloud sync is optional. If this iPhone is signed in to the
  same iCloud account as your other device, turn it on to bring your
  profile, journal, scores and settings here before choosing a name. You
  can turn it on or off later in Profile; turning it off keeps everything
  on this device."
- The removal and deletion sheets (`ProfileView`) already say it: "It does
  not erase your private iCloud journal or the copies on your other devices.
  Sync is turned off on this device; if you enable it again, your journal
  can be downloaded again." (Connected deletion) and "Your private iCloud
  journal and your other devices are not changed. …" (device-only removal).
  P3 and P4 above say the same in the policy's words.
