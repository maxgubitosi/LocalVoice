BINARY := .build/release/LocalVoice

.PHONY: build run clean

build:
	swift build -c release
	codesign --force --sign - $(BINARY)

run: build
	$(BINARY)

clean:
	swift package clean
