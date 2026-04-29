APP_NAME   := LocalVoice
APP        := $(APP_NAME).app
CONTENTS   := $(APP)/Contents
BINARY     := .build/release/$(APP_NAME)
BUILD_DIR  := .build/arm64-apple-macosx/release
METALLIB   := .build/release/mlx.metallib

.PHONY: build run bundle verify-bundle release-zip clean

build:
	swift build -c release
	@./scripts/build-metallib.sh
	codesign --force --sign - $(BINARY)

run: build
	$(BINARY)

bundle: build
	rm -rf $(APP)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(CONTENTS)/Frameworks
	cp $(BINARY) $(CONTENTS)/MacOS/$(APP_NAME)
	cp $(METALLIB) $(CONTENTS)/MacOS/mlx.metallib
	cp Sources/LocalVoice/Info.plist $(CONTENTS)/Info.plist
	cp AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	cp -R $(BUILD_DIR)/Sparkle.framework $(CONTENTS)/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(CONTENTS)/MacOS/$(APP_NAME)
	xattr -cr $(APP)
	codesign --force --deep --sign - $(APP)
	$(MAKE) verify-bundle

verify-bundle:
	test -x $(CONTENTS)/MacOS/$(APP_NAME)
	test -f $(CONTENTS)/MacOS/mlx.metallib
	test -f $(CONTENTS)/Info.plist
	test -f $(CONTENTS)/Resources/AppIcon.icns
	test -d $(CONTENTS)/Frameworks/Sparkle.framework
	codesign --verify --deep --strict $(APP)

release-zip: bundle
	rm -f LocalVoice.zip
	ditto -c -k --keepParent $(APP) LocalVoice.zip
	@echo "Done: LocalVoice.zip — public beta artifact for GitHub Releases"
	@echo "Note: ad-hoc signed beta builds require the README quarantine step until Developer ID notarization is available."

clean:
	swift package clean
