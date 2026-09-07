.PHONY: build run app install uninstall clean dmg sign notarize release

PRODUCT = Perekluk
VERSION = 1.6.0
BUILD_DIR = .build/release
APP_NAME = Perekluk.app
APP_DIR = $(APP_NAME)/Contents
INSTALL_DIR = /Applications
SIGN_ID = Developer ID Application: Alexander Abaskalov (JU5MCCQQ8J)

build:
	swift build -c release

run:
	swift run

app: build
	@mkdir -p "$(APP_DIR)/MacOS"
	@mkdir -p "$(APP_DIR)/Resources"
	@cp "$(BUILD_DIR)/$(PRODUCT)" "$(APP_DIR)/MacOS/$(PRODUCT)"
	@test -f AppIcon.icns && cp AppIcon.icns "$(APP_DIR)/Resources/AppIcon.icns" || true
	@/usr/libexec/PlistBuddy -c "Clear dict" "$(APP_DIR)/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy \
		-c "Add :CFBundleExecutable string $(PRODUCT)" \
		-c "Add :CFBundleIdentifier string com.perekluk.app" \
		-c "Add :CFBundleName string Perekluk" \
		-c "Add :CFBundlePackageType string APPL" \
		-c "Add :CFBundleVersion string $(VERSION)" \
		-c "Add :CFBundleShortVersionString string $(VERSION)" \
		-c "Add :CFBundleIconFile string AppIcon" \
		-c "Add :LSUIElement bool true" \
		-c "Add :NSHighResolutionCapable bool true" \
		"$(APP_DIR)/Info.plist"
	@echo "Built: $(APP_NAME)"

sign: app
	@codesign --deep --force --options runtime --sign "$(SIGN_ID)" "$(APP_NAME)"
	@codesign --verify --verbose "$(APP_NAME)"
	@echo "Signed: $(APP_NAME)"

dmg: sign
	@rm -f Perekluk.dmg
	@rm -rf dmg_staging
	@mkdir -p dmg_staging
	@cp -R "$(APP_NAME)" dmg_staging/
	@ln -s /Applications dmg_staging/Applications
	@cp AppIcon.icns dmg_staging/.VolumeIcon.icns
	@SetFile -a C dmg_staging
	@hdiutil create -volname "Perekluk" -srcfolder dmg_staging -ov -format UDZO Perekluk.dmg
	@rm -rf dmg_staging
	@codesign --sign "$(SIGN_ID)" Perekluk.dmg
	@echo "Created: Perekluk.dmg"

notarize: dmg
	@xcrun notarytool submit Perekluk.dmg --keychain-profile "notarytool" --wait
	@xcrun stapler staple Perekluk.dmg
	@echo "Notarized: Perekluk.dmg"

release: notarize
	@echo "Ready for distribution: Perekluk.dmg"

install: app
	@cp -R "$(APP_NAME)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME)"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME)"

clean:
	swift package clean
	@rm -rf "$(APP_NAME)" dmg_staging
