# ABRAXAS Publisher · Shared Cloud Contract

## Supabase

Publisher uses the same Supabase project and Auth as Editorial OS.

Table:

public.editorial_state

Workspace:

abraxas-publisher

Never use editorial-os for Publisher.

## Row identity

user_id + workspace_key

## Publisher portable payload

{
  version,
  brands,
  contents,
  accounts,
  publicationJobs,
  activity,
  syncMeta
}

## Sync

Desktop and Web/PWA use the same portable domain state.

Desktop additionally mirrors native operations into:

- SQLite
- filesystem
- Tauri
- ffmpeg/ffprobe
- future local publishing worker

Supabase is the cross-device source of truth for portable metadata.

## Conflict model

syncMeta includes:

revision
baseRevision
deviceId
productVersion
updatedAt

Next revision is based on the maximum local/base/remote revision.

## Google Drive

Desktop:
OAuth Desktop via Tauri.

Web/PWA:
Google Identity Services OAuth Web.

Web token:
memory only.

Scope:
drive.readonly.

A separate explicit write authorization should be used if Publisher later writes
receipts/corrections back to Drive.

## Security

Never expose:

service_role
database password
OAuth client secrets
refresh tokens

Browser may use:

Supabase project URL
publishable/anon key
Google OAuth Web Client ID
