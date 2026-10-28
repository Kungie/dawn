.PHONY: scratch test app release install run snapshots clean

# ~/Desktop syncs with iCloud, which stamps Finder attributes on build products and breaks codesign.
# Keep .build as a link to a folder outside iCloud.
SCRATCH := $(HOME)/Library/Caches/Dawn/build

# With only the Command Line Tools, Swift Testing's macro plugin doesn't load through the
# plugin server. Loading the macro library in-process works.
TESTING_MACROS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS := $(if $(wildcard $(TESTING_MACROS)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS),)

scratch:
	@if [ ! -L .build ]; then rm -rf .build; mkdir -p "$(SCRATCH)"; ln -s "$(SCRATCH)" .build; fi

test: scratch
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

app: scratch
	./scripts/build-app.sh

# The DMG and zip plus Dawn.zip.sig, signed with Dawn's release key from the Keychain. Upload all three.
release: app
	@v=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	grep -q "version = \"$$v\"" Sources/Dawn/DawnApp.swift || { echo "Info.plist says $$v but DawnInfo.version doesn't"; exit 1; }; \
	echo "Dawn $$v: tag the release v$$v"
	swift scripts/sign-update.swift build/Dawn.zip

install: app
	rm -rf /Applications/Dawn.app
	cp -R build/Dawn.app /Applications/Dawn.app
	open /Applications/Dawn.app

run: app
	open build/Dawn.app

snapshots: app
	build/Dawn.app/Contents/MacOS/Dawn snapshot docs

clean:
	rm -rf "$(SCRATCH)" build
