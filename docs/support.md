# Grepp support

Grepp is an iOS lifting log that keeps your training in a text file you own,
with a coach powered by Claude that reads it. The app and its source are at
<https://github.com/christoffermattssonlangseth/grepp>.

## Getting help

- **Something is wrong, or you want something:** open an issue at
  <https://github.com/christoffermattssonlangseth/grepp/issues>. Say what you
  did, what you expected, and what happened. A screenshot helps.

## Common questions

**Where is my data?** In `training.md`, either in iCloud Drive (Files app ▸
Grepp) or in the GitHub repository you chose. The app never writes anything
else to it. The format is one line per lift per day; see the README.

**The Coach says it needs a key.** The Coach uses your own Claude API key,
created at the Claude Console and pasted into Settings ▸ Coach. Usage bills to
your account. Everything else in the app works without one.

**The widget is behind.** It refreshes when the app goes to the background.
Open the app and close it again.

**A lift landed on the wrong day.** In History, swipe the lift for Move, or
tap the date to move the whole day.

**Strava shows a duplicate.** Strava keeps an activity's original date, so a
day moved in Grepp is posted fresh; delete the old activity in Strava.

## Privacy

The developer collects nothing. See [the privacy policy](privacy.md).
