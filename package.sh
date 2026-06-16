#!/bin/bash
set -e

APP_NAME="snag_report_extractor_app"
CERT_NAME="MySelfSignedCert"
DMG_FILE_NAME="${APP_NAME}-Installer.dmg"
VOLUME_NAME="${APP_NAME} Installer"

# Paths
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="dmg-staging"

# echo "🚀 Building Flutter macOS app..."
# flutter build macos --release

# 🔎 Check if certificate exists
if ! security find-identity -p codesigning -v | grep -q "${CERT_NAME}"; then
  echo "⚠️  Certificate ${CERT_NAME} not found. Creating self-signed certificate..."

  # Generate private key & certificate
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "${CERT_NAME}.key" \
    -out "${CERT_NAME}.csr" \
    -subj "/CN=${CERT_NAME}"

  openssl x509 -req -sha256 -days 3650 \
    -in "${CERT_NAME}.csr" \
    -signkey "${CERT_NAME}.key" \
    -out "${CERT_NAME}.crt"

  # Import into login keychai
  security import "${CERT_NAME}.crt" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
  security import "${CERT_NAME}.key" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign

  echo "✅ Self-signed certificate ${CERT_NAME} created and imported."
else
  echo "✅ Certificate ${CERT_NAME} already exists."
fi


echo "🧹 Cleaning staging directory..."
rm -rf "${STAGING_DIR}" "${DMG_FILE_NAME}"
mkdir -p "${STAGING_DIR}"
# Since create-dmg does not clobber, be sure to delete previous DMG
[[ -f "${DMG_FILE_NAME}" ]] && rm "${DMG_FILE_NAME}"


echo "📦 Copying .app bundle..."
cp -R "${APP_PATH}" "${STAGING_DIR}"

echo "🔏 Code signing .app with certificate: ${CERT_NAME}"
codesign --deep --force --verify --verbose \
  --sign "${CERT_NAME}" "${STAGING_DIR}/${APP_NAME}.app"

echo "📀 Creating DMG..."
create-dmg \
  --volname "${VOLUME_NAME}" \
  --background "assets/images/dmg_background.jpg" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 200 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 600 185 \
  "${DMG_FILE_NAME}" \
  "${STAGING_DIR}"

echo "✅ Done! DMG created: ${DMG_FILE_NAME}"