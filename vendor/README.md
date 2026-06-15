# Vendor Dependencies

`vendor/SGPlayer/` is intentionally ignored.

The local App Store build can use SGPlayer as the preferred playback engine, but
the compiled SGPlayer frameworks are large binary artifacts and should not be
committed to this repository. To build SGPlayer support locally, build or obtain
the SGPlayer frameworks for iOS, macOS, and tvOS, then place them at:

- `vendor/SGPlayer/iOS/SGPlayer.framework`
- `vendor/SGPlayer/macOS/SGPlayer.framework`
- `vendor/SGPlayer/tvOS/SGPlayer.framework`

Keep the upstream SGPlayer license and any bundled third-party codec licenses
with the local framework distribution.
