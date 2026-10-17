.PHONY: app install run snapshots clean

app:
	./scripts/build-app.sh

install: app
	rm -rf /Applications/Dawn.app
	cp -R build/Dawn.app /Applications/Dawn.app
	open /Applications/Dawn.app

run: app
	open build/Dawn.app

snapshots: app
	build/Dawn.app/Contents/MacOS/Dawn snapshot docs

clean:
	rm -rf .build build
