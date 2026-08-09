.PHONY: build test app run icon clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open build/StorageLens.app

icon:
	swift Scripts/make-icon.swift

clean:
	rm -rf .build build
