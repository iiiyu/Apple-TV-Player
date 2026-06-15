#!/bin/sh
set -eu

case "${PLATFORM_NAME:-}" in
    iphoneos)
        SGPLAYER_FRAMEWORK="${SRCROOT}/vendor/SGPlayer/iOS/SGPlayer.framework"
        ;;
    macosx)
        SGPLAYER_FRAMEWORK="${SRCROOT}/vendor/SGPlayer/macOS/SGPlayer.framework"
        ;;
    appletvos)
        SGPLAYER_FRAMEWORK="${SRCROOT}/vendor/SGPlayer/tvOS/SGPlayer.framework"
        ;;
    *)
        echo "Skipping SGPlayer bundle copy for ${PLATFORM_NAME:-unknown}."
        exit 0
        ;;
esac

if [ ! -d "${SGPLAYER_FRAMEWORK}" ]; then
    echo "error: SGPlayer.framework is missing at ${SGPLAYER_FRAMEWORK}."
    exit 1
fi

DESTINATION_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DESTINATION_FRAMEWORK="${DESTINATION_DIR}/SGPlayer.framework"

mkdir -p "${DESTINATION_DIR}"
rm -rf "${DESTINATION_FRAMEWORK}"
/usr/bin/ditto "${SGPLAYER_FRAMEWORK}" "${DESTINATION_FRAMEWORK}"

if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${DESTINATION_FRAMEWORK}"
fi
