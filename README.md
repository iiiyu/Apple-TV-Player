
# HiPlayer

HiPlayer is a fast, private, and simple way to watch M3U playlists on iPhone, iPad, Mac, and Apple TV.

> HiPlayer is based on [Apple-TV-Player](https://github.com/mikehouse/Apple-TV-Player)
> by **Mikhail Demidov**, used under the [MIT License](LICENSE.txt).
> Huge thanks to Mikhail for building and open-sourcing the original project. ❤️

Features:
- Works across iOS, iPadOS, macOS, and tvOS
- Supports M3U and M3U8 playlists
- Supports EPG
- Protect playlists with a PIN for extra privacy
- Saved playlists and app data stay on your device and are never sent to our servers (actually we do not have servers at all)
- Share playlists with other devices
- Free
- No account or registration required
- No ads, no tracking
- Open source (this repo contains the all application source code)
- 15 languages supported (ar, de, es, fr, hi, id, it, ja, ko, pt-BR, ru, th, tr, vi, zh-Hans)


‼️ **Important:**

HiPlayer does not provide, host, sell, or include any channels, media, or playlists. The app only plays content added by the user, and you are responsible for having the rights to access that content.

----

## Apple TV
<img src="/docs/tvos-dark.webp" alt="">

----

## macOS
<img src="/docs/macos-dark.webp" alt="">

----

## iPad
<img src="/docs/ipad-dark.webp" alt="">

----

# Acknowledgements

- [Apple-TV-Player](https://github.com/mikehouse/Apple-TV-Player) by Mikhail Demidov - the original project this app is based on (MIT)
- [Factory](https://github.com/hmlongco/Factory) by Michael Long (MIT)
- [Kanna](https://github.com/tid-kijyun/Kanna) by Atsushi Kiwaki (MIT)
- [Nuke](https://github.com/kean/Nuke) by Alexander Grebenyuk (MIT)
- [SWCompression](https://github.com/tsolomko/SWCompression) by Timofey Solomko (MIT)

----

# For Developers

- Xcode 26.5+
- Swift 6.2+
- SwiftPM
- `asc` CLI for App Store Connect release work
- For now there is no CI/CD pipeline

## Local Binary Dependencies

HiPlayer can use SGPlayer as the preferred playback engine with AVPlayer as a fallback. The compiled SGPlayer frameworks are local binary artifacts and are not committed to this repository because they are too large for normal GitHub storage. See [vendor/README.md](vendor/README.md) for the expected local framework paths.

## App Signing

- The app target uses automatic signing for `com.ohmyapps.hiplayer`
- Build for simulators does not require signing
- App Store Connect release automation is documented in [docs/APP_STORE_RELEASE.md](docs/APP_STORE_RELEASE.md)

## Build from Xcode

- Open a project in Xcode
- For the App scheme select `Signing and Capabilities`
- Set your `Bundle Identifier`
- Enable `Automatically manage signing`
- Xcode will do signing for your Team and Bundle Identifier

## Unit Testing

- iOS: `./scripts/tests/run-unit-tests-iphone.sh` requires iOS 26.5 Simulator Runtime
- tvOS: `./scripts/tests/run-unit-tests-appletv.sh` requires tvOS 26.5 Simulator Runtime
- macOS: `./scripts/tests/run-unit-tests-macos.sh` runs on the current machine

## UI Testing

Before any UI Tests must run a python local server that will provide mock data to the app.

```bash
./scripts/tests/server.py
```

### iOS

- iPhone iOS 26: `./scripts/tests/run-ui-snapshots-tests-iphone-26.sh`
- iPad iOS 26: `./scripts/tests/run-ui-snapshots-tests-ipad-26.sh`
- iPhone iOS 18: `./scripts/tests/run-ui-snapshots-tests-iphone-18.sh`
- iPad iOS 18: `./scripts/tests/run-ui-snapshots-tests-ipad-18.sh`

### tvOS

- tvOS 26: `./scripts/tests/run-ui-snapshots-tests-appletv-26.sh`
- tvOS 18: `./scripts/tests/run-ui-snapshots-tests-appletv-18.sh`

### macOS

Screenshots in repo created on macOS 26.5 with macOS SDK 26.5

```bash
./scripts/tests/run-ui-snapshots-tests-macos.sh
```

## App Store Connect Distribution With `asc`

See [ASC.md](ASC.md) for the generated command reference and [docs/APP_STORE_RELEASE.md](docs/APP_STORE_RELEASE.md) for this app's release checklist.

### Regenerate raw snapshots when the UI changes significantly

Must use the latest Simulator Runtime, now it is 26.4

- iPhone: `./scripts/tests/make-app-store-snapshots-iphone-26_4.sh`
- iPad: `./scripts/tests/make-app-store-snapshots-ipad-26_4.sh`
- tvOS: `./scripts/tests/make-app-store-snapshots-appletv-26_4.sh`
- macOS: `./scripts/tests/make-app-store-snapshots-macos.sh`

### Prepare App Store screenshots and metadata

```bash
./scripts/appstore/prepare-screenshots.py
asc metadata validate --dir ./metadata --output table
```

### Validate App Store Connect readiness

```bash
asc validate --app 6780068053 --version 1.0 --platform IOS --output table
asc validate --app 6780068053 --version 1.0 --platform MAC_OS --output table
asc validate --app 6780068053 --version 1.0 --platform TV_OS --output table
```

----

If you have any questions or ideas, please open an issue on GitHub.
