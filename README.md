<p align="center">
  <img src="LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="LiftLog icon">
</p>

# LiftLog

### An iOS workout log that lives in your own GitHub repo — with a Claude coach that reads it.

Log a session on the big number pads, and every set lands as a line of text in a
repo you control. No server, no database, no export — the file *is* the data,
which is exactly why an LLM can pick it up and coach from it with nothing in
between.

Ask **Coach** what to squat on Thursday and it answers from your own history:
real loads, real rep schemes, the dates it reasoned from. Tell it how you train
and what you're chasing in two more Markdown files beside the log, and it coaches
to your rules rather than a textbook's — changing its mind is a commit.

Point the app at any repo you control from the **Settings** tab (GitHub owner /
repo / path / branch + a fine-grained token). It reads and writes one file, so
your training history is portable, greppable, and outlives the app itself.

<p align="center">
  <img src="docs/session.png" width="280" alt="LiftLog Session screen — today's three exercises logged, the next one being added">
  <img src="docs/coach-2.png" width="280" alt="LiftLog Coach screen — a prescribed session with a Log the session button and a Log button per exercise">
</p>
<p align="center">
  <em><b>Session</b> — log it. &nbsp; <b>Coach</b> — ask what to do, then log that.</em>
</p>

## Ask your log

Nothing to export, no schema to reverse-engineer: the whole file goes to the
model as it is. So these are questions you type into the app, not things you'd
have to build something to answer:

> _"Am I progressing on squat over the last two months, or just adding volume?"_
> _"Plan next week's lower body from my recent top sets."_
> _"Which lifts have stalled the longest, and what do I do about it?"_

You get numbers back. An actual answer to "what session should I do today":

> **Session 6: deadlift, bench, seal row.** Last session (09-03) was the light
> squat/OHP/chin-up day, so you're up for the second deadlift+bench day.
>
> – Bench: 52.5 gave you 8/8/**12** on 09-01 after 8/8/8 on 08-28 — that 12 is a
> clear green light for +2.5. Make the third set an AMRAP but stop 2 shy; if it
> comes in under 6, hold 55 next time.

It knows which day of your split is due and that you'd rather not AMRAP a
deadlift — that's your `coaching.md` being read, not guessed. And under the
answer, one button logs the whole session.

The prescription first, then the numbers it rests on — and a straight "the log
doesn't show that" when it can't support one. When it prescribes your next
session, each exercise comes as a card with a **Log** button — or one **Log the
session** button for all of them. Either way you land on the Session tab with
the lift and the first set filled in, the plan shown as a target, each set you
land prefilling the next, and the next exercise loading as you finish the last.
Every exercise still pushes on its own the moment it's done. Under each answer a
quiet line gives the API's own token counts and what they cost — switch it off
in *Settings ▸ Coach* if you'd rather not know.

The format **is** the data: greppable, diffable, readable by any model. Your
history stays portable and outlives the app — usable by tools that don't exist
yet, no migration required.

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

## Coach

<p align="center">
  <img src="docs/coach.png" width="300" alt="LiftLog Coach screen — the answer itself: which day is due, and why each load is what it is">
</p>

Setting it up, and the details. Answers stream in, and a **Sonnet 5 / Opus 5**
picker sits above the input — Sonnet by default, Opus when you want it to chew
on a few years of history. It calls the
[Messages API](https://platform.claude.com/docs/en/api/messages/create) directly
over HTTPS, so there's no SDK or extra package to install.

It also sees the lift in your hands. Between sets, "should I go up for the last
one?" is answered against the sets you landed a minute ago, the plan, what's
still queued and how long you've been resting — none of which is in the log
until you finish the exercise. That goes as its own uncached block, so the
log's prompt cache holds across the session.

It sees your weekly sets per muscle for the last four weeks too, so "what
should I do this week" is a balance question, not a guess.

And it can remember. When it learns something worth keeping across chats — how
you respond to a stall, a constraint, a thing you've told it to stop doing — it
offers a note with a **Remember** button. Saved, the note goes into
`coaching.md` under a *Coach's notes* heading, dated, and is part of the brief
from then on. Nothing is written until you tap; the brief is the memory, and
you can edit or delete any note in **Your brief**.

And it remembers what it asked for. When you load a prescription and finish
the lift, the app keeps the plan next to what you actually did, and the coach
sees both for the next two weeks: "prescribed 87.5x5 ×3 · did 87.5x5 87.5x5
87.5x4 (1 rep short)", or "not done yet". The next prescription starts from
the session as lifted, not as written. Nothing about this touches
`training.md`; the log stays what you did.

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
  `LiftLogWidgets/` is the widget extension (the Live Activity and the home
  screen widget) and `Shared/` is the handful of files both targets compile.
- The two targets talk through the App Group `group.CML.LiftLog`, declared in
  each target's `.entitlements`. Automatic signing registers it; if Xcode
  complains about the group the first time, open **Signing & Capabilities** for
  each target and it will offer to fix it.
- The whole palette is `Theme.accent`; the app icon is drawn from it by
  `Scripts/make-icon.py` (needs `pillow`), so a re-skin is one constant and one
  re-run rather than an edited PNG.
- Select your iPhone as the run destination and press ▶. Free provisioning runs
  it for 7 days per rebuild; a paid Apple Developer account keeps it installed.
- First run: enable **Developer Mode** on the phone (Settings ▸ Privacy & Security)
  and **Trust** the developer (Settings ▸ General ▸ VPN & Device Management).

## Features

**Session** — logging, built for a gym floor.
- A searchable exercise picker: your own history first, then a built-in
  library, or just type a new name.
- Big number pads. Under the weight field, what to load per side — worked out
  from the plates you actually own, so it never suggests one you don't have.
  The line names the bar, and tapping it sets a different one for *that*
  exercise: seal rows on the 10, everything else on your default.
- Land a set and it's felt. A set that beats your all-time best for the lift
  gets a **PR** badge and a heavier buzz.
- A rest timer that starts on every set and fills toward a target you pick
  (1:00 / 1:30 / 2:00 / 3:00). When you're due the whole card flips to the
  accent and buzzes. Outside the app the same clock runs as a **Live Activity**
  on the lock screen and in the Dynamic Island, counting down without the app
  awake and flipping to READY when the target lands; a notification says so
  too, and names the next set if the plan knows it. The Live Activity has one
  button, labelled with the set it lands — the next planned one, or the last
  one again — so a set goes in and the rest restarts without unlocking the phone.
- "Today's Session" builds up live. Each finished exercise pushes to GitHub on
  its own — nothing waits on an "end session" tap that a dead phone could swallow.
- When Coach hands over a session: the plan shows as a target, each set
  prefills the next, and the next lift loads as you finish the last.

**History** — every session, newest first. Pull to refresh. Tap an exercise to
edit it, swipe to delete; both push like any other change.

**Trends** — a progression chart per lift: top-set weight, Est. 1RM, or added
load / max reps for bodyweight lifts, with short-term (3-week) and all-time
change tiles. Drag along the line to read a session off it. Drawn so it can
never show a peak you didn't lift. Below it, **training days**: every day of
the last months as a dot, Monday to Sunday, deeper the more sets, so a missed
week is a blank column you can see without asking. And **sets per muscle per
week**, six weeks across, the number a programme is written in — a compound
counts fully for its prime mover and half for what it also trains, every
logged set is a working set. Tonnage isn't here on purpose: it rewards a light
leg press over a heavy triple and says nothing about where the work went.
Lifts the app doesn't know are assigned once in **Settings ▸ Muscles**;
until then they're listed as not counted rather than guessed. History shows
the same count per workout under each date.

**Coach** — a chat with Claude that has your `training.md` in front of it. Ask
"what session should I do today" and get loads and rep schemes cited from your
own numbers, with a **Log the session** button (it reads **Load for next
session** once you've already trained today). Teach it who you are with
`coaching.md` and `goals.md`, or let it interview you. See [Coach](#coach).

**Settings** — the GitHub repo and token, the Claude key, your bar and plates,
and the offline sync queue.

**Home screen widget** — *Last session*: how many days ago, which day, and
the lifts with their sets (small shows each lift's last set, medium shows them
all). It reads a snapshot the app leaves in the App Group, never the log or
the token, and re-renders at midnight so "2 days ago" stays true.

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
handling, the Trends analytics (top-set, Est. 1RM, volume and added-load
series, change tiles, the Monday-first weeks grid), the muscle map and its
set counts, the plan-versus-done verdicts, and the Coach context builder — how much log gets sent, how the brief is
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

The exercise you're mid-way through — sets landed, the plan, the rest clock —
and the Coach conversation both survive the app being killed in the background,
and come back on the next launch. Gyms also eat battery, and iOS quietly kills
whatever's behind the music app.
