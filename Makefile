.PHONY: build test app run install uninstall icon snapshots dmg zip clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open build/StorageLens.app

# Copies the app into /Applications so it shows up in Launchpad and Spotlight.
# Do this before granting Full Disk Access — the grant is tied to the app's
# location, so a copy made afterwards has to be granted again.
install: app
	rm -rf /Applications/StorageLens.app
	cp -R build/StorageLens.app /Applications/
	@echo "Installed /Applications/StorageLens.app"

uninstall:
	rm -rf /Applications/StorageLens.app

icon:
	swift Scripts/make-icon.swift

# README screenshots, rendered from preview data rather than captured by hand.
# Run from inside the bundle so localizations resolve through Bundle.main.
snapshots: app
	build/StorageLens.app/Contents/MacOS/StorageLens --snapshot docs/overview-light.png
	build/StorageLens.app/Contents/MacOS/StorageLens --snapshot docs/overview-dark.png --dark
	build/StorageLens.app/Contents/MacOS/StorageLens --snapshot docs/overview-pt-BR.png -AppleLanguages "(pt-BR)"
	build/StorageLens.app/Contents/MacOS/StorageLens --snapshot docs/overview-es-ES.png -AppleLanguages "(es-ES)"

# Drag-to-Applications installer — the artifact most people should download.
dmg: app
	./Scripts/make-dmg.sh

# Release artifact: a zip that keeps the bundle's signature intact.
zip: app
	cd build && ditto -c -k --sequesterRsrc --keepParent StorageLens.app StorageLens.zip
	@echo "Wrote build/StorageLens.zip"

clean:
	rm -rf .build build
