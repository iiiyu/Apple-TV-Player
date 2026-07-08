# App Review Guideline 2.1 Information Needed

This checklist is for the App Review "Information Needed - New App
Submission" response.

## Current ASC state

Checked with `asc review history --app 6780068053` on 2026-06-16 NZT:

- iOS version 1.0: unresolved issues, review detail `a4259c60-29c6-4a6b-a0f5-08d75a4d5098`
- macOS version 1.0: unresolved issues, review detail `52e2d3d3-28c7-49d3-aa69-f5522ca1346a`
- tvOS version 1.0: unresolved issues, review detail `458552d3-9708-42b7-9904-870649903475`
- No App Review attachments were present on those review details.

These IDs are specific to the current 1.0 versions. For later versions, resolve
the current review detail first:

```bash
asc review details-for-version --version-id "VERSION_ID" --output json
```

## Required before replying

Do not submit notes with placeholders. First prepare:

- Physical-device screen recording file or public video link.
- Exact tested physical device model names and operating system versions.
- If possible, one recording per rejected platform, or one combined recording
  that clearly shows the submitted app running on the physical platforms.

## Screen recording flow

Record from the physical device home screen so the launch is visible.

1. Launch Hi IPTV Player.
2. Show that no account registration or login is required.
3. Open Add Playlist.
4. Enter:
   - Name: `App Review`
   - Playlist URL: `https://raw.githubusercontent.com/iiiyu/Apple-TV-Player/master/docs/review.m3u`
   - Leave optional EPG/logo/image URL fields blank.
   - Leave PIN/passcode blank unless you also want to demonstrate PIN protection.
5. Save the playlist and wait for it to load.
6. Open the playlist, select the Apple HLS Sample channel, start playback, and
   show fullscreen playback. On tvOS, let the controls hide after inactivity.
7. Open playlist settings or the playlist list to show management features.
8. If demonstrating PIN protection, enable a PIN on a sample playlist, reopen it,
   then enter the PIN. Do not make PIN protection look mandatory.
9. Show that there are no purchase, subscription, user account, camera,
   microphone, contacts, photos, location, or tracking prompts.

The sample playlist is a review-only M3U file in this repository. It references
Apple's public HLS sample stream and does not provide developer-hosted channels.

## Reply text for App Review

Paste this as the response to App Review after replacing the TODO fields and
attaching or linking the recording.

```text
Hello App Review Team,

Thank you for the guidance. We have provided the requested review information below.

1. Screen recording
Screen recording: TODO: attached file name or public video link.
The recording starts from launching the app on a physical device and shows the typical core flow: adding a playlist, loading the playlist, opening a channel, playback, fullscreen playback, and playlist management. The app has no account registration, login, account deletion, paid content, subscriptions, user-generated public content, reporting/blocking flow, or sensitive-data permission prompts.

2. Tested devices and operating systems
TODO: replace with the exact physical devices and OS versions used before submission, for example:
- Apple TV 4K (3rd generation), tvOS TODO
- iPhone TODO, iOS TODO
- iPad TODO, iPadOS TODO
- Mac TODO, macOS TODO

3. App purpose and target audience
Hi IPTV Player / HiPlayer is a private M3U and M3U8 playlist player for users who already have lawful playlist or stream sources and want a simple way to watch them on Apple TV, iPhone, iPad, and Mac. The app solves playlist playback and organization across Apple devices. It does not provide, host, sell, or include any channels, media, or playlists.

4. Setup and access instructions
No login credentials are required because the app does not use developer accounts.
To test the main flow:
- Launch the app.
- Choose Add Playlist.
- Name: App Review
- Playlist URL: https://raw.githubusercontent.com/iiiyu/Apple-TV-Player/master/docs/review.m3u
- Leave optional EPG/logo/image URL fields blank.
- Save the playlist, open it, select "Apple HLS Sample", and start playback.

The sample playlist is only for App Review. It points to Apple's public HLS sample stream. Users normally add their own M3U/M3U8 playlists or playlist files.

5. External services, tools, or platforms
The app does not use a developer backend, authentication service, payment processor, advertising network, analytics SDK, or AI service. It may use:
- Apple iCloud/CloudKit private database sync when the user is signed into iCloud and iCloud is available.
- User-provided playlist, EPG, logo/image, and stream URLs.
- Apple's AVPlayer and the app's bundled SGPlayer playback engine/fallback flow.
- Open-source Swift dependencies for local parsing, image loading, compression, and dependency injection.

6. Regional differences
The app functions consistently across all regions. Interface and App Store metadata are localized, but features do not change by region. Available playlist content depends entirely on the playlist sources the user adds and is not supplied by the developer.

7. Regulated industry or protected third-party material
The app is not operating in a regulated industry. The app does not include protected third-party channels, media, or playlists. It is a player for user-provided content only, and users are responsible for having rights to access any content they add. The review sample uses Apple's public HLS sample stream.
```

## Notes field for future submissions

Use the same text above in the App Review Information Notes field, with the
screen recording and device list updated for the actual submission. Keep the
sample playlist URL in the notes unless it changes.

## ASC update commands

After replacing the TODOs, save the final notes to a local text file and update
each platform's review detail:

```bash
asc review details-update --id a4259c60-29c6-4a6b-a0f5-08d75a4d5098 --notes "$(cat ./review-notes-final.txt)"
asc review details-update --id 52e2d3d3-28c7-49d3-aa69-f5522ca1346a --notes "$(cat ./review-notes-final.txt)"
asc review details-update --id 458552d3-9708-42b7-9904-870649903475 --notes "$(cat ./review-notes-final.txt)"
```

Upload recordings or supporting files to the same review details:

```bash
asc review attachments-upload --review-detail a4259c60-29c6-4a6b-a0f5-08d75a4d5098 --file ./AppReview-iOS.mov
asc review attachments-upload --review-detail 52e2d3d3-28c7-49d3-aa69-f5522ca1346a --file ./AppReview-macOS.mov
asc review attachments-upload --review-detail 458552d3-9708-42b7-9904-870649903475 --file ./AppReview-tvOS.mov
```

Then reply to the unresolved issue in App Store Connect and resubmit if App
Store Connect requires a resubmission after the issue is answered.
