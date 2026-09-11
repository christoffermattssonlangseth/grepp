# Shipping Grepp

The path from a build on one phone to TestFlight and the App Store. What is
already in the repository, then the steps outside it, in order.

## Already done in the repository

- **Privacy manifests** (`PrivacyInfo.xcprivacy`) in the app and the widget:
  no tracking, no collected data, and the required-reason APIs the code uses
  (UserDefaults, the App Group, the iCloud file's modification date).
- **Export compliance** declared in both Info.plists
  (`ITSAppUsesNonExemptEncryption = NO`): TLS only, so no questionnaire per
  upload.
- **No key in any build.** `Secrets.plist` is excluded from the target, and the
  code no longer reads the bundle for secrets. Every lifter pastes their own
  Claude key, GitHub token and Strava credentials; the developer holds none.
- **iOS 26.0 floor** on both targets.
- **Privacy policy and support page** in `docs/` — App Store Connect asks for
  URLs to both.
- **Build number** (`CURRENT_PROJECT_VERSION`) that must go up on every upload.

## Before the first upload

1. **Apple Developer Program.** The team (`7R6QL53THM`) already signs with
   App Groups and iCloud, which needs the paid membership, so this is done.
2. **Publish the two pages.** GitHub ▸ Settings ▸ Pages ▸ Deploy from branch,
   `main`, folder `/docs`. The URLs become
   `https://christoffermattssonlangseth.github.io/grepp/privacy` and
   `.../support`. Any host works; App Store Connect only needs the links.
3. **App Store Connect record.** appstoreconnect.apple.com ▸ My Apps ▸ + ▸ New
   App: iOS, name **Grepp**, primary language, bundle ID `CML.LiftLog` (the
   existing one; the App Store name is separate from the bundle ID), SKU
   `grepp`. If the name is taken at this step, it is taken worldwide; the
   check earlier found it free.
4. **Icons and text.** The 1024 icon is in the asset catalog. Write the
   subtitle (30 characters), description, keywords, and a "what's new" for 1.0.
   Category Health & Fitness. Age rating: answer the questionnaire, none apply.
5. **Screenshots.** One 6.9-inch iPhone set is required; take them in the
   Simulator (iPhone 17 Pro Max or the largest listed) with Cmd+S. Log, Coach,
   Trends, History, the lock-screen rest clock. Optional sets for the 6.5-inch
   and iPad are skipped by unchecking iPad in Xcode's target if you don't want
   iPad review (set `TARGETED_DEVICE_FAMILY = 1`).
6. **App privacy.** Answer "Data not collected". It is true of the developer;
   the policy explains what the lifter sends to their own accounts.
7. **Review notes.** Reviewers need to see the Coach. Either paste a Claude
   key with a spending cap into the notes, revoked after review, or state that
   the Coach requires the user's own key and every other screen works without
   one, which is also true. Say the app has no login.

## The upload

1. In Xcode, select the **LiftLog** scheme and **Any iOS Device (arm64)**.
2. Bump `CURRENT_PROJECT_VERSION` on both targets (they must match) — or use
   the Xcode target editor's Build field, which sets both.
3. Product ▸ **Archive**. Xcode signs with the App Store profile
   automatically; the widget is embedded.
4. Organizer ▸ Distribute App ▸ **TestFlight & App Store** ▸ Upload. Let Xcode
   manage signing and symbols.
5. Processing takes a few minutes; App Store Connect emails when the build is
   ready. Missing-compliance or missing-manifest warnings come by email too;
   both are already answered in the repository.

## TestFlight

- **Internal testers** (your own Apple Account and up to 100 team members):
  available the moment the build is processed, no review.
- **External testers**: add a group, add emails or make a public link, then
  submit the build for TestFlight review (usually under a day). Tester feedback
  and crashes appear in App Store Connect ▸ TestFlight.
- A build expires after 90 days; upload a new one before that.

## App Review

Submit from the app's page in App Store Connect once the build is attached.
Things that get an app like this bounced, and what is already in place:

- **Guideline 5.1.1 (data collection):** the app collects nothing and says so;
  the privacy policy is linked.
- **Guideline 2.1 (completeness):** every screen works with no key; the
  reviewer can log a session and see Trends and History.
- **Guideline 3.1.1 (payments):** nothing is sold in the app, and the Claude
  key is a developer credential the user gets elsewhere, which review accepts
  for API-client apps. Do not link to a page that sells anything.
- **Guideline 4.2 (minimum functionality):** the log, the plate maths, the
  rest clock, Trends and the widget stand on their own.

## After 1.0

- **A relay for the Claude key** is the one thing that would let people use
  the Coach without an Anthropic account. It is a small server that holds the
  key and forwards requests, plus a way to pay for it: a subscription through
  StoreKit, since the developer would be paying Anthropic for everyone. That
  is a product decision, not a checklist item, so it is not started.
- **Renaming the Xcode project** from LiftLog to Grepp is cosmetic and can
  wait; the bundle ID must never change once shipped.
