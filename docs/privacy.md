# Grepp privacy policy

*Last updated 11 September 2026.*

Grepp is a lifting log. Your training log is a text file, `training.md`, that
you own. The developer of Grepp runs no server and receives nothing from the
app: no log, no account, no analytics, no crash reports, no advertising
identifiers.

## What the app stores on your phone

- Your log, your brief files (`coaching.md`, `goals.md`, `program.md`,
  `research.md`) and the app's settings.
- Keys and tokens you paste in — a GitHub token, a Claude API key, a Strava
  client ID and secret and the Strava tokens that follow — in the iOS Keychain.
- The exercise in progress, the rest clock and the Coach conversation, so an
  app that is killed resumes where it was.

None of this leaves the phone except as described below, and all of it is
deleted with the app.

## Where your data goes, and only when you choose

**iCloud Drive.** If you keep the log in iCloud Drive, Apple syncs the file
between your devices under your Apple Account. Apple's terms apply.

**GitHub.** If you keep the log in a GitHub repository, every save is a commit
to that repository over TLS, using a token you created. GitHub's terms apply.
The repository can be private.

**Anthropic (the Coach).** When you ask the Coach a question, the app sends
your question, your log, your brief files and the session in progress to
`api.anthropic.com` over TLS, using a Claude API key you created in your own
Anthropic account. Usage bills to that account. Anthropic's terms and privacy
policy apply to what it does with API requests. The Coach never sends anything
until you tap send, and a message with a DOI or link in it also lets the model
fetch that paper from journal sites, PubMed, preprint servers or doi.org for
that one answer.

**Strava.** If you connect Strava and tap Post, the app sends that day's lifts
and a summary to Strava as an activity, using tokens from your own Strava
account. Nothing is read back from Strava.

You can stop any of these by removing the key, token or connection in
Settings, or by deleting the app.

## What the app does not do

- No tracking, no advertising, no fingerprinting, no third-party SDKs.
- No account with the developer. There is nothing to sign up for.
- No data collected by the developer, so nothing for the developer to sell,
  share or lose.

## Notifications and Live Activities

The app can show a rest-timer notification and a Live Activity on the lock
screen. Both are scheduled on the phone and involve no server.

## Children

Grepp is not directed at children under 13.

## Changes

If this policy changes, the date at the top changes with it, and the file's
history is in the repository.

## Contact

Open an issue at <https://github.com/christoffermattssonlangseth/grepp/issues>.
