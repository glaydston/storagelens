.PHONY: build test app run install uninstall icon zip clean

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

# Release artifact: a zip that keeps the bundle's signature intact.
zip: app
	cd build && ditto -c -k --sequesterRsrc --keepParent StorageLens.app StorageLens.zip
	@echo "Wrote build/StorageLens.zip"

clean:
	rm -rf .build build
