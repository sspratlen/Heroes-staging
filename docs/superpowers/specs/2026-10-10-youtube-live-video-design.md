# Live Game Video (Mevo → YouTube → Site) — Design

**Date:** 2026-10-10 · **Status:** Draft for review · **Approach:** C — automatic sync with admin cleanup

## Goal
Stream Heroes games from Mevo cameras to a Heroes YouTube channel — up to three games at once — and show those games on heroesseniorsoftball.com both live and as a library of past games, tied to the team, game and tournament they belong to.

## Scope
**In:** YouTube channel + Mevo setup checklist; `videos` table; `youtube-sync` Edge Function; Watch page; per-video page; site-wide LIVE banner; ▶ links on Events cards and game results; Admin → Videos page.
**Out:** recording or hosting video anywhere but YouTube; highlights/clipping; chat or comments on the site; paid/ticketed streams; merging the Events list with the tournaments table (separate backlog epic).

## Current state (as of 2026-10-10)
- No YouTube channel; no video features on the site.
- Games live in `heroes_data` collection `games` (277 records) with `id, date, teamId, opponent, tournamentId, heroScore, oppScore, result, season`. Games are usually entered **after** they are played.
- Events page cards come from `heroes_data` collection `events` (`id, name, date, endDate, teams, status, …`); games reference the separate `tournaments` table via `tournamentId`.
- Teams: `55s-aaa` (55 AAA), `50s-aaa` (50 AAA), `50s-aa` (50 AA), plus 60s.
- RLS helpers exist in schema `private` (`is_staff()` = approved admin/manager/coach).

## 1. Camera & YouTube setup (no code — checklist in `docs/streaming-setup.md`)
1. Create a team-owned Google account and the **Heroes** YouTube channel; enable live streaming (YouTube takes ~24 h the first time).
2. In the Mevo app, connect each camera to the channel. Before the first tournament, run **two simultaneous test streams**.
3. Connectivity: one phone hotspot or cellular connection per camera, ~4–6 Mbps upload for 1080p (less for 720p).
4. Title every stream: `<Team> vs <Opponent> · <Tournament>` — e.g. `55 AAA vs Kansas City Legends · Winter Worlds`.
5. Leave recordings public when the stream ends (YouTube's default).

## 2. Pre-build checks (gate before any site code)
| Check | How | If it fails |
|---|---|---|
| Live streams from this channel can be embedded on our domain | One short live stream; load the embed on staging | Live games link out to YouTube ("Watch on YouTube"); recordings still embed |
| Mevo app can stream to a new channel, and two streams can run at once | Test with the real cameras | Adjust camera plan (e.g. stream key / RTMP setup) before tournaments |
| YouTube Data API key | User creates it in the team Google account; stored as a Supabase Edge Function secret `YOUTUBE_API_KEY` (never in site code); Claude does not create accounts or handle the key | Sync cannot run; site shows nothing new |

## 3. Data model — table `public.videos`
| Column | Type | Notes |
|---|---|---|
| `youtube_id` | text, PK | YouTube video id |
| `title` | text | As on YouTube |
| `status` | text | `upcoming` \| `live` \| `ended` |
| `scheduled_start`, `actual_start`, `actual_end` | timestamptz | From YouTube live details (null for non-live uploads) |
| `published_at` | timestamptz | |
| `thumbnail_url` | text | |
| `team_id` | text | e.g. `55s-aaa`; null = unmatched |
| `game_id` | text | `heroes_data` games[].id; null until matched |
| `tournament_id` | text | Copied from the matched game |
| `match_source` | text | `auto` \| `confirmed` |
| `hidden` | boolean, default false | Hide from site (warm-ups, tests) |
| `last_synced_at`, `created_at` | timestamptz | |

Plus one row in `public.sync_status` (`key = 'youtube'`: `last_run_at`, `last_ok_at`, `last_error`) for the admin page.

**RLS:** anyone (anon + authenticated) may `select` rows where `hidden = false`; staff may `select` all and `update` `team_id, game_id, tournament_id, match_source, hidden`. Inserts and status updates come only from the Edge Function (service role). Tested in a rolled-back dry run before applying, as with earlier migrations.

## 4. `youtube-sync` Edge Function
- **Trigger:** a `pg_cron` job calls the function every 2 min. The function skips the YouTube call unless a row is `live`, a row is `upcoming` within the next hour, or the last successful sync was 30+ min ago — so it effectively checks every 2 min around game time and every 30 min otherwise. Plus an admin **Sync now** call (staff JWT required), which always runs.
- **YouTube calls (low quota):** the channel's uploads playlist via `playlistItems.list` (newest 50), then `videos.list?part=snippet,liveStreamingDetails,status` for those ids. No `search.list`.
- **Upsert:** insert new videos; update `title, status, times, thumbnail` on existing ones. **Never** changes `team_id/game_id/tournament_id` when `match_source = 'confirmed'`, and never touches `hidden`.
- **Status:** `live` if `actualStartTime` set and no `actualEndTime`; `upcoming` if only `scheduledStartTime`; else `ended`.
- **Auto-matching** (only when `match_source` is null or `auto`):
  - *Team* — leading team token in the title, case-insensitive: `55 AAA`, `55AAA`, `55s AAA`, `55s`; `50 AAA`, `50AAA`; `50 AA`, `50AA`; `60s`, `60`. Check AAA before AA.
  - *Game* — a game with that `teamId` whose `date` equals the stream's local start date (America/Chicago); if more than one, pick the one whose `opponent` appears in the title; if still ambiguous, leave `game_id` null.
  - *Tournament* — the matched game's `tournamentId`.
  - Unmatched videos are re-tried on every run, so a game entered after the stream gets linked automatically.
- **Errors:** record `last_error` in `sync_status`; keep existing rows untouched.

## 5. Site pages
1. **Watch** (`#/watch`) — new top-menu item between Season and Players; shows a red ● on every page while anything is live.
   - *Live now:* one card per live video (team label, title, LIVE tag); tap to play; one player at a time.
   - *Coming up:* `upcoming` videos with start time.
   - *Library:* `ended` videos, newest first, thumbnail cards; filters team / season / tournament + search; cards linked to a game show the result (e.g. "L 8–14 vs Friars · Oct 3").
2. **Video page** (`#/watch/<youtube_id>`) — player on top; game details (score, opponent, tournament, box score link) when linked. If a live embed is refused, a prominent **Watch on YouTube** button replaces the player.
3. **LIVE banner — every page** — red strip under the nav while any video is `live`: one game → "● LIVE NOW · 55 AAA vs KC Legends — Watch"; several → "● 3 games live now — Watch". Hidden when nothing is live.
4. **Events cards** — **▶ Watch live** while a video is live whose team is in `event.teams` and whose start falls within `event.date … event.endDate`; **▶ Videos (n)** for matching recordings. Matching by team + date avoids depending on the events/tournaments merge.
5. **Game results** (Schedule / Season pages) — a ▶ next to any game with a linked, visible video, opening its video page.
- **Performance:** thumbnails only; the YouTube player iframe loads on tap. Live status is read from `videos` on page load and refreshed every 60 s while the Watch page or banner is showing.

## 6. Admin → Videos (staff)
- Table of all videos: thumbnail, title, status, team, game, and match state (*auto-matched* / *confirmed* / *needs attention* when team or game is missing).
- **Fix:** team dropdown; game dropdown limited to that team's games within ±3 days of the video date.
- **Confirm:** sets `match_source = 'confirmed'` (sync stops changing it).
- **Hide / Unhide** from site (stays on YouTube).
- **Sync now** button and "Last synced … / last error" line from `sync_status`.
- Every change → `auditLog('video_*', 'videos', youtube_id, …)`; names/titles escaped when rendered.

## 7. Error handling
| Situation | Behaviour |
|---|---|
| YouTube unreachable / key invalid / quota hit | Site shows last known data; admin page shows last error and time |
| Live embed refused by YouTube | "Watch on YouTube" button |
| Game played but no video | Game shows normally without ▶ |
| Video with no team in title | Appears in library unlabeled; flagged *needs attention* in admin |
| Stream ends | Next sync flips it to `ended`; banner disappears within ~2 min |

## 8. Rollout (staging first; production only on explicit instruction)
0. Setup checklist + pre-build checks (section 2).
1. `videos` + `sync_status` tables and `youtube-sync` function — **shared database; ask before applying** (invisible to the live site).
2. Admin → Videos page.
3. Watch page, video page, LIVE banner.
4. ▶ on Events cards and game results.
Each step verified on staging before the next.

## 9. Testing
- RLS: rolled-back dry run (anon sees only non-hidden; player cannot update; staff can fix/confirm/hide; sync-only fields not writable by staff).
- Matching: run the matcher against real game records with sample titles (each team spelling, double-headers, missing opponent, AAA vs AA).
- Sync: one run against the real channel once it exists; verify quota use and `sync_status`.
- End to end: a short test stream → LIVE banner → Watch page → library after it ends → linked to its game once entered.
