#!/bin/sh
set -eu
license="${PODS_ROOT}/Target Support Files/Pods-CloudPlay/Pods-CloudPlay-acknowledgements.plist"
target="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/PodsAcknowledgements.plist"
test -f "$license" || { echo 'error: Missing upstream license acknowledgements' >&2; exit 1; }
# CocoaPods can include GNU COPYING form-feed characters, illegal in XML 1.0.
# Normalize page breaks, preserving all copyright and license wording.
/usr/bin/tr '\014' '\012' < "$license" > "$target"
/usr/bin/plutil -lint "$target"
