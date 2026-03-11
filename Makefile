.PHONY: build run app install uninstall clean dmg

PRODUCT = Perekluk
BUILD_DIR = .build/release
APP_NAME = Perekluk.app
APP_DIR = $(APP_NAME)/Contents
INSTALL_DIR = /Applications

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
		-c "Add :CFBundleVersion string 1.0" \
		-c "Add :CFBundleShortVersionString string 1.0" \
		-c "Add :CFBundleIconFile string AppIcon" \
		-c "Add :LSUIElement bool true" \
		-c "Add :NSHighResolutionCapable bool true" \
		"$(APP_DIR)/Info.plist"
	@echo "Built: $(APP_NAME)"

install: app
	@cp -R "$(APP_NAME)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME)"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME)"

clean:
	swift package clean
	@rm -rf "$(APP_NAME)"

dmg: app
	@rm -f Perekluk.dmg
	@hdiutil create -volname "Perekluk" -srcfolder "$(APP_NAME)" -ov -format UDZO Perekluk.dmg
	@echo "Created: Perekluk.dmg"
