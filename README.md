
# HiPlayer

HiPlayer is a fast, private, and simple Apple TV app for watching your own M3U playlists.

> HiPlayer is based on [Apple-TV-Player](https://github.com/mikehouse/Apple-TV-Player)
> by **Mikhail Demidov**, used under the [MIT License](LICENSE.txt).
> Huge thanks to Mikhail for building and open-sourcing the original project. ❤️

Features:
- Built for Apple TV and the Siri Remote
- Supports M3U and M3U8 playlists
- Supports EPG
- Uses SGPlayer as the preferred playback engine with AVPlayer as a fallback
- Clean full-screen playback that hides controls after inactivity
- Protect playlists with a PIN for extra privacy
- Saved playlists and app data stay on your device and are never sent to our servers (actually we do not have servers at all)
- Free
- No account or registration required
- No ads, no tracking
- Open source (this repo contains the all application source code)
- 15 languages supported (ar, de, es, fr, hi, id, it, ja, ko, pt-BR, ru, th, tr, vi, zh-Hans)


‼️ **Important:**

HiPlayer does not provide, host, sell, or include any channels, media, or playlists. The app only plays content added by the user, and you are responsible for having the rights to access that content.

----

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
- Swift 6.2+
- SwiftPM
- `asc` CLI for App Store Connect release work
- For now there is no CI/CD pipeline

## Local Binary Dependencies

HiPlayer can use SGPlayer as the preferred playback engine with AVPlayer as a fallback. The compiled SGPlayer frameworks are local binary artifacts and are not committed to this repository because they are too large for normal GitHub storage. See [vendor/README.md](vendor/README.md) for the expected local framework paths.

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
