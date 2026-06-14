#!/bin/bash
# Generates TURNSecrets.generated.swift from TURNConfig.plist.
# Falls back to empty stub if plist is missing.

# SRCROOT is set by Xcode at build time; fall back to script location
: "${SRCROOT:=$(cd "$(dirname "$0")/.." && pwd)}"

PLIST="${SRCROOT}/Sources/Config/TURNConfig.plist"
OUTPUT="${SRCROOT}/Sources/Config/TURNSecrets.generated.swift"

USERNAME=""
CREDENTIAL=""
APIKEY=""

if [ -f "$PLIST" ]; then
    USERNAME=$(/usr/libexec/PlistBuddy -c "Print :METERED_TURN_USERNAME" "$PLIST" 2>/dev/null || echo "")
    CREDENTIAL=$(/usr/libexec/PlistBuddy -c "Print :METERED_TURN_CREDENTIAL" "$PLIST" 2>/dev/null || echo "")
    APIKEY=$(/usr/libexec/PlistBuddy -c "Print :METERED_API_KEY" "$PLIST" 2>/dev/null || echo "")
fi

cat > "$OUTPUT" << 'SWIFTEOF'
// Auto-generated from TURNConfig.plist — DO NOT COMMIT
enum TURNSecrets {
    static let turnUsername = "TURN_USERNAME_PLACEHOLDER"
    static let turnCredential = "TURN_CREDENTIAL_PLACEHOLDER"
    static let meteredAPIKey = "METERED_API_KEY_PLACEHOLDER"
}
SWIFTEOF

# Replace placeholders with actual values
sed -i '' "s|TURN_USERNAME_PLACEHOLDER|${USERNAME}|g" "$OUTPUT"
sed -i '' "s|TURN_CREDENTIAL_PLACEHOLDER|${CREDENTIAL}|g" "$OUTPUT"
sed -i '' "s|METERED_API_KEY_PLACEHOLDER|${APIKEY}|g" "$OUTPUT"

if [ -f "$PLIST" ]; then
    echo "✅ TURNSecrets generated with real credentials"
else
    echo "⚠ TURNSecrets generated as stub (TURNConfig.plist not found)"
fi
