<p align="center">
  <img src="LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="LiftLog icon">
</p>

# LiftLog — iOS workout logger

A native SwiftUI app that logs workouts into a plain-text `training.md` and
pushes each entry straight to a GitHub repo via the Contents API. No server, no
database — the text file stays the single source of truth, human-readable and
diff-friendly.

Point the app at any repo you control from the **Settings** tab (GitHub owner /
repo / path / branch + a fine-grained token). It reads and writes one file, so
your training history is portable, greppable, and outlives the app itself.

<p align="center">
  <img src="docs/session.png" width="300" alt="LiftLog Session screen — bold, gym-friendly logging UI">
</p>

## `training.md` format

One line per exercise per day; a blank line separates dates:

```
2026-08-30 deadlift 82.5x8 82.5x8 82.5x8
2026-08-30 chin-ups bwx6 bwx6 bw+5x6
```

- **Date** — ISO `YYYY-MM-DD`. Exercises sharing a date form one session.
- **Exercise** — lowercase `kebab-case` (consistent spelling groups sessions for trends).
- **Sets** — space-separated `weightxreps` tokens: `82.5x8` (kg × reps),
  `bwx6` (bodyweight × reps), `bw+5x8` (bodyweight **+ 5 kg** × reps).

## Why plain text? (great for LLMs)

Because the log is just a small Markdown file, there's nothing to export and no
schema to reverse-engineer — you can hand the whole thing to an LLM and ask real
questions about your training:

> _"Am I actually progressing on squat over the last two months, or just adding
> volume?"_
> _"Plan next week's lower-body session at ~RPE 8 based on my recent top sets."_
> _"Which lifts have stalled the longest?"_

The format **is** the data: greppable, diffable, and directly readable by any
model. Your training history stays portable and future-proof — usable by tools
that don't exist yet, no database migration required.

## Coach

The **Coach** tab is a chat with Claude that reads your training log and tells
you what to do next. Ask it to plan a session, take a lift forward, or explain
why something has stalled, and it answers with actual numbers — load, sets and
reps, sized from the increments *you* have been making — rather than training
theory. It cites the dates and loads behind each call, says when the log is too
thin to support one, and is told plainly that it can only read the log: it can't
log a session for you.

The system prompt carries that brief, a key to the `training.md` format, and the
log itself. **The whole file goes over**, up to a 120,000-character budget —
about 3,500 exercise lines, or roughly five years at three sessions a week. Past
that it sends the newest sessions that fit (whole days, never half a day) and
tells the model how many older ones it couldn't see. Both models take a million
tokens of context, so the budget is generous on purpose; a full send is a few
cents a question at most, and less once the prompt cache warms.

Answers stream in token by token. A **Sonnet 5 / Opus 5** picker sits above the
input: Sonnet is the default because it's fast and cheap; Opus is there when you
want it to chew on a few years of history.

It talks to the [Claude Messages API](https://platform.claude.com/docs/en/api/messages/create)
directly over HTTPS — `ClaudeService` is a plain `URLSession` client sitting next
to `GitHubService`, no SDK and no extra packages. So Coach runs on the same iOS
version as the rest of the app, with nothing to install.

The whole conversation is sent each turn, so follow-up questions keep the thread,
and the log is rebuilt per question — log a set mid-chat and the next answer sees
it. The system prompt is marked for prompt caching, which makes follow-ups
cheaper once the log is long enough to clear the model's minimum cacheable prefix.

### The API key

**The key is never in source and never committed** — this repo is public. It's
read from the first of these that has one:

1. **Keychain** — paste it into *Settings ▸ Coach*. The normal path, and the
   only one that works on a device from the home screen.
2. **`ANTHROPIC_API_KEY`** environment variable — set it in the scheme
   (*Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments*), which lives in
   `xcuserdata/` and is already gitignored. Convenient in the Simulator.
3. **`LiftLog/Secrets.plist`** — untracked, one `ANTHROPIC_API_KEY` string.
   Gitignored, but it *is* copied into the app bundle, so it's dev-only: a key
   in a bundle is extractable from the binary just like a hardcoded one.

`.gitignore` covers `Secrets.plist`, `LiftLog/Secrets.plist`, `.env` and
`*.local.xcconfig`. Usage bills to your Anthropic account at standard API
pricing; create a key in the [Claude Console](https://platform.claude.com/).

### Workspace ID (only for some keys)

A key scoped to one workspace needs nothing else — leave the field blank. A
**personal or service account key that spans several workspaces** has to say
which one each request acts in, or the API answers `400 anthropic-workspace-id
is required when authenticating with an identity-linked API key`. Paste the
`wrkspc_…` value into *Settings ▸ Coach*; it's the **ID** column of
[Settings ▸ Workspaces](https://platform.claude.com/settings/workspaces) in the
Console. It's an identifier rather than a secret, so it lives in `UserDefaults`
beside the repo config, not the Keychain. Creating a workspace-scoped key
instead works just as well and needs no ID.

> **Before distributing this to anyone else**, a key that ships inside the app is
> the wrong model — anyone with the binary can pull it out and bill you. Put a
> small backend in front that holds the key server-side and forwards requests,
> and point `ClaudeService.endpoint` at it.

### What leaves the phone

The question and the log excerpt go straight from the app to `api.anthropic.com`
over TLS. The log text is built in exactly one place (`CoachContext.systemPrompt`)
and handed to the request; it is never printed, never logged to the console, and
never written anywhere but the existing offline cache. Errors surface the API's
status and reason, never the prompt.

### If you'd rather use Apple's Foundation Models

Anthropic also ships [`ClaudeForFoundationModels`](https://github.com/anthropics/ClaudeForFoundationModels),
which plugs Claude into Apple's `FoundationModels` framework so it's driven by
the same `LanguageModelSession` API as the on-device model. That's the nicer
long-term integration — Apple handles tool calling and structured output, and
you can switch to the on-device model for cheap tasks by swapping one argument.
It needs **iOS 27 and Xcode 27**, both in beta as of this writing, which is why
this app doesn't use it: the direct HTTPS client above runs on iOS 26 today.
Swapping back later means replacing `ClaudeService` and nothing else —
`CoachContext`, `CoachService`, the view and the key handling all stay as they are.

## Open & run
- Open **`LiftLog.xcodeproj`** in Xcode.
- Source lives in `LiftLog/` (an Xcode 16 synchronized folder, so files in it
  are part of the target automatically — just add new files there).
- Select your iPhone as the run destination and press ▶. Free provisioning runs
  it for 7 days per rebuild; a paid Apple Developer account keeps it installed.
- First run: enable **Developer Mode** on the phone (Settings ▸ Privacy & Security)
  and **Trust** the developer (Settings ▸ General ▸ VPN & Device Management).

## Tabs
- **Session** — pick a date, choose an exercise (searchable list + your history,
  or type a new name), enter weight/reps on the big number pads, and "Finish
  exercise" to add it to the day. A live "Today's Session" list shows the workout
  building up, and a **rest timer** starts counting up each time you add a set.
  Bold / gym-friendly styling: strong accent, large touch targets, chunky buttons.
- **History** — browse every session; pull to refresh from GitHub. Swipe any
  exercise to delete it (with a confirm), which is pushed like any other edit.
- **Trends** — per-lift progression chart (top-set weight by default; Est. 1RM as a
  secondary metric; added-load or max-reps for bodyweight lifts) with short-term
  (3-week) and long-term (all-time) change tiles.
- **Coach** — a chat with Claude that has your `training.md` in front of it. Ask
  "what should my next squat session be" or "which lifts have stalled" and get
  concrete loads and rep schemes, cited from your own dates and numbers. See
  [Coach](#coach) below.
- **Settings** — GitHub owner / repo / path / branch + a fine-grained token, and
  the Claude API key for Coach.

## Tests
The pure-logic layer (parsing, serialization, analytics) lives in `LiftLog/Core`
and is Foundation-only, so it builds and runs as a Swift package with no
simulator:

```
swift test
```

The same files compile into the iOS target via Xcode's synchronized folder, so
`swift test` exercises the exact production code. Coverage: `training.md`
parse/serialize round-trips, the `bw` / `bw+5` bodyweight tokens, malformed-line
handling, the Trends analytics (top-set, Est. 1RM, added-load series, change
tiles), and the Coach context builder (that a four-year log is sent whole, the
newest-first trimming and truncation notes beyond that, and that what we send the
model still round-trips through the parser).

## GitHub token
Create a **fine-grained personal access token** scoped to only this repo with
**Contents: Read and write**, and paste it into the Settings tab. It's stored in
the iOS Keychain, never in source or UserDefaults.

## How saves stay safe
Each save **fetches the current `training.md`, merges the one edited exercise into
it, then writes** — it never serializes stale in-memory state, so a save can't drop
history that exists on GitHub. The fetch bypasses the URL cache and retries on
GitHub 409 conflicts to avoid stale-SHA errors.

## Offline
Gyms eat signal, so writes are offline-first. If a save (or delete) can't reach
GitHub, it's **queued locally and applied optimistically** — the entry shows up in
the app immediately — and the file's last-known content is cached so History and
Trends still work with no connection. The queue **flushes automatically on the next
successful load or save**, replaying each change through the same safe
merge-on-remote path; you can also see and retry it from **Settings ▸ Waiting to
sync**. The queue survives an app kill (persisted in `UserDefaults`; the token stays
in the Keychain).
