
# HiPlayer

HiPlayer is a fast, private, and simple IPTV player for iPhone, iPad, Mac, and Apple TV. Add your own M3U/M3U8 playlist, browse its channels, and watch streams from your Apple devices.

[Get HiPlayer on the App Store](https://apps.apple.com/us/app/hi-iptv-player/id6780068053)

> HiPlayer is based on [Apple-TV-Player](https://github.com/mikehouse/Apple-TV-Player)
> by **Mikhail Demidov**, used under the [MIT License](LICENSE.txt).
> Huge thanks to Mikhail for building and open-sourcing the original project. ❤️

Features:
- One app for iPhone, iPad, Mac, and Apple TV
- Add remote M3U/M3U8 playlists with optional names, logos, EPG URLs, and image URLs
- Parse channel metadata, groups, logos, stream headers, and multiple playlist entries
- Browse channels by category, search on iPhone, iPad, and Mac, and mark channels as favorites
- Refresh playlists and program guides from their source URLs
- View current and scheduled program information when an EPG is available
- Use SGPlayer when available, with AVPlayer as a fallback and an in-app engine switch
- Full-screen playback with platform-specific controls, including Siri Remote support on Apple TV
- Protect playlists and playlist settings with an optional PIN
- Sync playlist records through Apple's private CloudKit container when available, with local storage fallback
- Free, with no ads, tracking, or HiPlayer account
- Localized user interface
- Open source (the application source code is in this repository; large SGPlayer binaries are supplied separately)


‼️ **Important:**

HiPlayer does not provide, host, sell, or include any channels, media, or playlists. The app only plays content added by the user, and you are responsible for having the rights to access that content.

----

## Supported Platforms

The project currently targets iOS, iPadOS, macOS, and tvOS 26.0 or later. The same SwiftUI codebase provides device-specific navigation and playback experiences for touch devices, Mac, and Apple TV.

## Apple TV
<img src="/docs/tvos-dark.webp" alt="HiPlayer playlist picker on Apple TV" width="1800" height="1013">

----

# Acknowledgements

- [Apple-TV-Player](https://github.com/mikehouse/Apple-TV-Player) by Mikhail Demidov - the original project this app is based on (MIT)
- [Factory](https://github.com/hmlongco/Factory) by Michael Long (MIT)
- [Kanna](https://github.com/tid-kijyun/Kanna) by Atsushi Kiwaki (MIT)
- [Nuke](https://github.com/kean/Nuke) by Alexander Grebenyuk (MIT)
- [SGPlayer](https://github.com/libobjc/SGPlayer) by Single (MIT)
- [SWCompression](https://github.com/tsolomko/SWCompression) by Timofey Solomko (MIT)

----

# For Developers

- Xcode 26.5+
- Swift 6.0
- SwiftPM
- `asc` CLI for App Store Connect release work
- For now there is no CI/CD pipeline

## Local Binary Dependencies

HiPlayer can use SGPlayer as the preferred playback engine with AVPlayer as a fallback. The compiled SGPlayer frameworks are local binary artifacts and are not committed to this repository because they are too large for normal GitHub storage. See [vendor/README.md](vendor/README.md) for the expected local framework paths.

Playlist sources and stream data are fetched directly from the URLs supplied by the user. HiPlayer does not provide, host, sell, or include channels or playlists, and it has no HiPlayer backend. Playlist records use Apple's private CloudKit container when available and otherwise remain in local app storage.

## App Signing

- The tvOS App Store build uses automatic signing for `com.ohmyapps.hiplayer`
- Build for simulators does not require signing
- App Store Connect release automation is documented in [docs/APP_STORE_RELEASE.md](docs/APP_STORE_RELEASE.md)

## Build from Xcode

- Open a project in Xcode
- For the App scheme select `Signing and Capabilities`
- Set your `Bundle Identifier`
- Enable `Automatically manage signing`
- Xcode will do signing for your Team and Bundle Identifier

## Unit Testing

- tvOS: `./scripts/tests/run-unit-tests-appletv.sh` requires tvOS 26.5 Simulator Runtime

## UI Testing

Before any UI Tests must run a python local server that will provide mock data to the app.

```bash
./scripts/tests/server.py
```

- tvOS 26: `./scripts/tests/run-ui-snapshots-tests-appletv-26.sh`
- tvOS 18: `./scripts/tests/run-ui-snapshots-tests-appletv-18.sh`

## App Store Connect Distribution With `asc`

See [ASC.md](ASC.md) for the generated command reference and [docs/APP_STORE_RELEASE.md](docs/APP_STORE_RELEASE.md) for this app's release checklist.

### Regenerate raw snapshots when the UI changes significantly

Must use the latest supported tvOS Simulator Runtime.

- tvOS: `./scripts/tests/make-app-store-snapshots-appletv-26_4.sh`

### Prepare App Store screenshots and metadata

```bash
./scripts/appstore/prepare-screenshots.py
asc metadata validate --dir ./metadata --output table
```

### Validate App Store Connect readiness

```bash
asc validate --app 6780068053 --version 1.0 --platform TV_OS --output table
```

----

If you have any questions or ideas, please open an issue on GitHub.
