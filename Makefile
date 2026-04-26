APP_NAME  := LocalVoice
APP       := $(APP_NAME).app
CONTENTS  := $(APP)/Contents
BINARY    := .build/release/$(APP_NAME)

.PHONY: build run bundle release-zip clean

build:
	swift build -c release
	@./scripts/build-metallib.sh
	codesign --force --sign - $(BINARY)

run: build
	$(BINARY)

bundle: build
	rm -rf $(APP)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BINARY) $(CONTENTS)/MacOS/$(APP_NAME)
	cp Sources/LocalVoice/Info.plist $(CONTENTS)/Info.plist
	-cp AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns 2>/dev/null || true
	codesign --force --deep --sign - $(APP)

release-zip: bundle
	xattr -cr $(APP)
	ditto -c -k --keepParent $(APP) LocalVoice.zip
	@echo "Done: LocalVoice.zip — upload to GitHub Releases"

clean:
	swift package clean
