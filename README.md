<p align="center">
  <img src="LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="Grepp icon">
</p>

# Grepp

[![CI](https://github.com/christoffermattssonlangseth/liftlog/actions/workflows/ci.yml/badge.svg)](https://github.com/christoffermattssonlangseth/liftlog/actions/workflows/ci.yml)

### An iOS lifting log that lives in a text file you own, with a coach powered by Claude that reads it.

*Grepp* is Swedish for grip.

Every set you log becomes a line of text in a file you control: in your iCloud
Drive, where it shows up in the Files app, or in a GitHub repo where every set is
a commit. No server, no database, no export: the file is the data, which is why
a model can coach from it with nothing in between. Ask **Coach** what to squat today and it answers
from your own history, with the loads, the reps and the dates it reasoned from,
then puts the session on the Log tab with one tap.

<p align="center">
  <img src="docs/session.png" width="280" alt="Session screen: today's exercises logged, the next being added">
  <img src="docs/coach-2.png" width="280" alt="Coach screen: a prescribed session with a Log the session button">
</p>

## The file

`training.md`, one line per exercise per day, blank lines between days:

```
2026-08-30 deadlift 82.5x8 82.5x8 82.5x8
2026-08-30 chin-ups bwx6 bwx6 bw+5x6
```

Date, `kebab-case` exercise, then `weightxreps` tokens: `82.5x8` (kg × reps),
`bwx6` (bodyweight), `bw+5x8` (bodyweight plus 5 kg). The app never writes
anything else to it.

No exercise images, no videos, no programme library. The numbers are the
product.

## What it does

**Log.** Big number pads. A plate calculator under the weight field, worked out
from the plates you own and the bar that lift uses. A PR badge when a set beats
your best. A rest timer that starts on every set and flips the card when you're
due. Each finished exercise pushes to GitHub on its own.

**Lock screen and Dynamic Island.** The rest clock runs as a Live Activity with
the app asleep, flips to READY at the target, and has one button, labelled with
the set it lands, so the next set goes in without unlocking the phone. A
notification says when rest is up too.

**Coach.** A chat with Claude that has your log in front of it. Sonnet 5 by
default, Opus 5 a tap away. It prescribes with numbers, and each exercise it
prescribes is a card with a **Log** button, or one button for the whole session
(**Load for next session** once you've already trained today). Mid-session it
also sees the lift in your hands: the sets landed a minute ago, the plan, the
queue, the rest. It keeps what it prescribed next to what you did, and reads
your weekly sets per muscle, so the next prescription starts from the session as
lifted. A cost line under each answer shows the API's own token counts.

**Your brief.** Four optional Markdown files beside the log, editable in the
app: `coaching.md` for how you train, `goals.md` for what you're chasing (the
coach can interview you and write it), `research.md` for the findings you want
it to programme from, and `program.md` for the plan you're running. Changing
how you're coached is a commit. When the coach
learns something worth keeping, it offers a **Remember** card that appends a
dated note to `coaching.md`. Nothing is written until you tap.

**Programme.** Ask for one, "write me a programme", and the coach designs it
from your log, goals and evidence, asks what it doesn't know (days, time,
equipment), and writes `program.md`: days under headings, one lift per line
with its set scheme and progression rule, no loads. Save it, and from then on
"what should I do today" is that programme's next day with loads from your
log, and the Programme screen in the Coach toolbar lists the days with a
button each. The design rules it follows are the usual evidence-based ones
(hard sets per muscle per week, two exposures, 1–3 reps in reserve, reactive
deloads), stated as defaults your evidence brief overrides; Liftosaur's
programme-design guide was the checklist for what to cover.

**Evidence.** `research.md` holds one finding per line, tagged `[R1]`, `[R2]`…
The coach cites the tag when an answer rests on one, and the tag is a link to
the entry. Hand it a paper, an abstract or a DOI and it writes the entry, with
an **Add to evidence** button. A message with a DOI or link in it gives the
coach the web for that one answer, restricted to journals, PubMed, preprint
servers and doi.org, so it reads the paper rather than remembering it; searches
cost a cent each. A starter file is in
[`docs/research-seed.md`](docs/research-seed.md), written from the model's
memory of the literature and meant to be checked, not trusted.

**Trends.** Two views. *Lift*: a chart per lift (top set, Est. 1RM, or reps
and added load for bodyweight lifts) with three-week and all-time change, and
under it **work and result**: the lift's weekly best over the last eight weeks
above its own weekly sets, with every set for its main muscle as a faint bar
behind, and one computed sentence naming the lever — flat at low volume means add sets, flat inside or above the band
means volume isn't it. The coach is told to make the same cross before it
prescribes a way out of a stall.
*Volume*: a training-days grid, Monday to Sunday, and sets per muscle for the
week as bars against a 10–20 band with the four-week average marked. A
compound counts fully for its prime mover and half for each muscle that also
works (bench is chest, half triceps, half front delts), every logged set is a
working set, and lifts the app doesn't know are assigned once in
Settings ▸ Muscles. No tonnage, on purpose.

**History.** Every day, newest first, with sets per muscle under each date and
whether it's on Strava. Tap an exercise to edit, swipe to delete.

**Widget.** *Last session* on the home screen: how long ago, the lifts and
their sets, and **Up next** when a session is loaded and not yet lifted.

**Strava.** A **Post to Strava** button under today's session. The day goes up
as a Weight Training activity named after its lifts, the log lines in the
description with a "Tracked with Grepp" sign-off, and the length from your
first set to the post. Press again and it updates the same activity. History
offers a post button per day, and Settings posts every day not yet up, oldest
first. Nothing is read back from Strava.

**Offline.** With GitHub, a save that can't reach it is queued, shown at once, and
replayed on the next successful load or save through the same safe path: every
save fetches the current file, merges one exercise into it, and writes. The
lift in progress, the rest clock and the Coach chat survive an app kill.

## Setup

**Run it.** Open `LiftLog.xcodeproj`, pick your iPhone, press ▶. First run on a
phone: enable Developer Mode and trust the developer in iOS Settings.
`LiftLog/` is the app, `LiftLogWidgets/` the widget extension, `Shared/` what
both compile; the folders, targets and bundle IDs keep the project's first
name so an installed build carries on. The app needs the App Group
`group.CML.LiftLog` and the iCloud container `iCloud.CML.LiftLog`, both in its
entitlements; automatic signing registers them (open Signing & Capabilities on
each target if it complains).
The palette is one constant, `Theme.accent`, and `Scripts/make-icon.py` draws
the icon from it.

**Where the log lives.** The first run asks: iCloud Drive or a GitHub repo.
iCloud needs nothing else; the file is `Grepp/training.md` in the Files app,
synced by Apple. GitHub takes the owner, repo, path and branch in Settings plus
a fine-grained token with Contents read and write on that repo, kept in the
Keychain. Switch either way later in Settings; the format is the same.

**Claude.** A key from the [Claude Console](https://platform.claude.com/),
pasted into Settings ▸ Coach. Keychain, never in source: this repo is public. A
key not scoped to one workspace also needs the workspace ID. For the Simulator,
an `ANTHROPIC_API_KEY` scheme variable or an untracked `LiftLog/Secrets.plist`
works too. Questions and the log go to `api.anthropic.com` over TLS and nowhere
else; usage bills to your account. A key inside a binary is extractable, so put a
backend in front before giving the app to anyone else.

**Strava.** Register an API app at strava.com/settings/api with `localhost` as
the Authorization Callback Domain, paste its client ID and secret into
Settings ▸ Strava (or `Secrets.plist` as `STRAVA_CLIENT_ID` and
`STRAVA_CLIENT_SECRET`), and tap Connect. Tokens live in the Keychain.

**Brief files.** Optional. `coaching.md`, `goals.md`, `program.md` and
`research.md` sit beside the log, wherever it lives; create them from the app
or by hand. Paths are in Settings ▸ Coach.

## Tests

The logic layer in `LiftLog/Core` is Foundation-only and doubles as a Swift
package, so it runs without a simulator:

```
swift test
```

It covers the file format, the analytics, the muscle map, the plan-versus-done
verdicts, the Strava post, and the Coach context: what reaches the model, how
the brief is assembled, and how its blocks are parsed back out. CI runs it on
every push, and builds the app and widget for the Simulator alongside.
