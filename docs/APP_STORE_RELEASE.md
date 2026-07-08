# App Store Release

This project uses `asc` for App Store Connect release work. Fastlane is not used.

## App

- App Store Connect app ID: `6780068053`
- Bundle ID: `com.ohmyapps.hiplayer`
- SKU: `com.ohmyapps.hiplayer`
- Version: `1.0`
- Build: `4`
- Primary locale: `en-US`

## Local Metadata

Canonical App Store metadata lives in:

- `metadata/app-info/<locale>.json`
- `metadata/version/1.0/<locale>.json`

Validate metadata before pushing:

```bash
asc metadata validate --dir ./metadata --output table
```

Push metadata to every App Store platform version:

```bash
asc metadata push --app 6780068053 --app-info 10d47d76-7774-4997-90c2-2c31be3d24f5 --version 1.0 --platform IOS --dir ./metadata
asc metadata push --app 6780068053 --app-info 10d47d76-7774-4997-90c2-2c31be3d24f5 --version 1.0 --platform MAC_OS --dir ./metadata
asc metadata push --app 6780068053 --app-info 10d47d76-7774-4997-90c2-2c31be3d24f5 --version 1.0 --platform TV_OS --dir ./metadata
```

## Screenshots

Generate the English marketing screenshot set and copy it to all supported App Store locales:

```bash
./scripts/appstore/prepare-screenshots.py
```

The upload-ready screenshots are written to:

- `AppStoreAssets/screenshots/ios/<locale>/iphone_67`
- `AppStoreAssets/screenshots/ios/<locale>/ipad_pro_3gen_129`
- `AppStoreAssets/screenshots/macos/<locale>/desktop`
- `AppStoreAssets/screenshots/tvos/<locale>/apple_tv`

`AppStoreAssets/` is generated output and is ignored by Git. Regenerate it
locally before screenshot validation or upload.

Validate screenshots before uploading:

```bash
asc screenshots validate --path AppStoreAssets/screenshots/ios/en-US/iphone_67 --device-type IPHONE_67 --output table
asc screenshots validate --path AppStoreAssets/screenshots/ios/en-US/ipad_pro_3gen_129 --device-type IPAD_PRO_3GEN_129 --output table
asc screenshots validate --path AppStoreAssets/screenshots/macos/en-US/desktop --device-type DESKTOP --output table
asc screenshots validate --path AppStoreAssets/screenshots/tvos/en-US/apple_tv --device-type APPLE_TV --output table
```

Upload screenshots with locale fan-out:

```bash
asc screenshots upload --app 6780068053 --version 1.0 --platform IOS --path AppStoreAssets/screenshots/ios --device-type IPHONE_67 --replace
asc screenshots upload --app 6780068053 --version 1.0 --platform IOS --path AppStoreAssets/screenshots/ios --device-type IPAD_PRO_3GEN_129 --replace
asc screenshots upload --app 6780068053 --version 1.0 --platform MAC_OS --path AppStoreAssets/screenshots/macos --device-type DESKTOP --replace
asc screenshots upload --app 6780068053 --version 1.0 --platform TV_OS --path AppStoreAssets/screenshots/tvos --device-type APPLE_TV --replace
```

## App Store Setup

These API-backed setup fields can be managed with `asc`:

```bash
asc categories set --app 6780068053 --primary ENTERTAINMENT --secondary UTILITIES
asc apps update --id 6780068053 --content-rights DOES_NOT_USE_THIRD_PARTY_CONTENT
asc age-rating edit --app 6780068053 --all-none --unrestricted-web-access true
asc pricing schedule create --app 6780068053 --free --base-territory US --start-date 2026-06-15
```

App availability may need one-time initialization in App Store Connect if no availability record exists yet. After it exists, use:

```bash
asc pricing availability edit --app 6780068053 --all-territories --available true --available-in-new-territories true
```

## Readiness

Run readiness checks per platform:

```bash
asc validate --app 6780068053 --version 1.0 --platform IOS --output table
asc validate --app 6780068053 --version 1.0 --platform MAC_OS --output table
asc validate --app 6780068053 --version 1.0 --platform TV_OS --output table
```

Builds are uploaded separately via `asc xcode` / `asc publish`. Review contact details are account-specific and should be filled with real contact information before submission.

Before submitting a new app or a new platform, prepare App Review Information
notes and physical-device recordings using
[APP_REVIEW_2_1_RESPONSE.md](APP_REVIEW_2_1_RESPONSE.md).
