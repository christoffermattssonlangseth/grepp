<p align="center">
  <img src="LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="LiftLog icon">
</p>

# LiftLog — iOS workout logger

A native SwiftUI app that logs workouts into a plain-text `training.md` and
pushes each entry straight to a GitHub repo via the Contents API. No server, no
database — the text file stays the single source of truth, human-readable and
diff-friendly.

Because the log is plain text, it doubles as a **coach**. The Coach tab puts the
whole file in front of Claude and answers "what should I squat on Thursday?" with
numbers from your own history — coached to rules you write yourself, in Markdown,
in the same repo.

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

## Ask your log

There's nothing to export and no schema to reverse-engineer, so the whole file
goes straight to the model. Which means these are questions you type into the
app, not things you'd have to build something to answer:

> _"Am I progressing on squat over the last two months, or just adding volume?"_
> _"Plan next week's lower body from my recent top sets."_
> _"Which lifts have stalled the longest, and what do I do about it?"_

You get numbers back — load, sets and reps, sized from the increments *you've*
been making — with the dates each call rests on. Write down how you train and
what you're aiming at in two more Markdown files beside the log, and it coaches
to your rules instead of a textbook's. Changing its mind is a commit.

The format **is** the data: greppable, diffable, and readable by any model. Your
history stays portable and outlives the app — usable by tools that don't exist
yet, no migration required.

## Coach

A chat with Claude that reads your training log and tells you what to do next.
Ask it to plan a session, push a lift forward, or explain why something has
stalled, and it answers with numbers — load, sets and reps, sized from the
increments *you* have been making — citing the dates behind each call, and
saying so when the log is too thin to support one. Answers stream in, and a
**Sonnet 5 / Opus 5** picker sits above the input.

Your whole `training.md` goes with every question (up to about five years of it),
so there's nothing to export. It calls the
[Messages API](https://platform.claude.com/docs/en/api/messages/create) directly
over HTTPS — no SDK, no extra packages, nothing to install.

### Teach it who you are

Two optional files beside your log, both plain Markdown with no schema:
**`coaching.md`** for how you like to train, **`goals.md`** for what you're
working toward.

```markdown
- Four days a week, upper/lower. Squat and deadlift once each.
- I add 2.5 kg upper / 5 kg lower when the top set moves cleanly.
- Left shoulder doesn't like flat barbell benching at volume.
- 140 kg squat by June. Currently 120. First meet in the autumn.
```

**Changing how you're coached is a commit** — edit, push, and the next answer
reflects it. Versioned and revertable like the log, with no model to fine-tune.

Edit both in the app from **Your brief** (the person icon in the Coach toolbar),
or let it interview you: *Set up your goals* asks a few questions — specific
ones, since it can already see your log — then writes `goals.md` and offers to
commit it. Once goals exist, the same button becomes *Update your goals* and
opens by asking what's changed. Both files are optional; rename or disable them
in *Settings ▸ Coach*.

### The API key

Create one in the [Claude Console](https://platform.claude.com/) and paste it
into *Settings ▸ Coach*, where it goes in the Keychain. **It is never in source
and never committed** — this repo is public. For Simulator work you can use an
`ANTHROPIC_API_KEY` scheme variable or an untracked `LiftLog/Secrets.plist`
instead; `.gitignore` covers both. Usage bills to your Anthropic account.

If your key isn't scoped to one workspace, the API also needs a workspace ID —
the `wrkspc_…` from [Settings ▸ Workspaces](https://platform.claude.com/settings/workspaces),
pasted into the same screen. A workspace-scoped key needs nothing extra.

Your question and log go straight to `api.anthropic.com` over TLS, and are never
logged or stored anywhere else.

> **Before giving this app to anyone else**: a key inside the binary can be
> extracted from it. Put a small backend in front that holds the key server-side
> and point `ClaudeService` at that instead.

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
  concrete loads and rep schemes, cited from your own dates and numbers. Add a
  `coaching.md` and `goals.md` beside your log and it coaches to *your* rules,
  toward *your* targets. See [Coach](#coach) below.
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
tiles), and the Coach context builder — how much log gets sent, how the brief is
assembled, and that what reaches the model still round-trips through the parser.

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
