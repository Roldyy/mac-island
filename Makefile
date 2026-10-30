.PHONY: help run build test bundle install uninstall dmg notarize icon clean clean-test-prefs check

APP := build/Mac Island.app

help:
	@echo "make run        run from source (no bundle: some permissions cannot be prompted)"
	@echo "make test       run the test suite"
	@echo "make install    build, sign locally (ad hoc) and copy to /Applications"
	@echo "make uninstall  remove the app from /Applications (your settings stay)"
	@echo "make bundle     build 'build/Mac Island.app' (SIGN_IDENTITY=... for a release signature)"
	@echo "make notarize   sign, notarize and staple the app and the DMG (needs a notarytool profile)"
	@echo "make check      personal-data guard + tests"

run:
	swift run MacIsland

build:
	swift build

test:
	swift test

bundle:
	scripts/bundle.sh

install: bundle
	-pkill -x MacIsland
	rm -rf "/Applications/Mac Island.app"
	cp -R "$(APP)" "/Applications/Mac Island.app"
	open "/Applications/Mac Island.app"

uninstall:
	-pkill -x MacIsland
	rm -rf "/Applications/Mac Island.app"
	@echo "Removed the app. Settings and data stay in ~/Library/Application Support/be.roldy.macisland"

dmg notarize:
	scripts/notarize.sh

icon:
	swift scripts/make-icon.swift

check:
	scripts/check-no-personal.sh
	swift test

clean:
	swift package clean
	rm -rf build

clean-test-prefs:
	scripts/clean-test-prefs.sh --apply
