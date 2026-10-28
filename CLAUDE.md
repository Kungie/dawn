# Dawn

A macOS menu bar app (Swift package, Command Line Tools only, macOS 13+). Code, UI text and docs are in English.

## Build and test

- `make test` runs the Swift Testing suites. With only the Command Line Tools the testing macros need `-load-plugin-library`, which the Makefile adds. No `@State` macro: keep view state in the model or use `@StateObject`.
- `.build` is a link to `~/Library/Caches/Dawn/build` (`make scratch`), because iCloud on the Desktop breaks codesign of build products.
- `make app` builds the universal `build/Dawn.app`, `build/Dawn.zip` and, with dmgbuild, `build/Dawn.dmg`.

## Releasing

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist` and `DawnInfo.version` in `Sources/Dawn/DawnApp.swift`. They must match each other and the tag `vX.Y.Z`; the app refuses an update whose version isn't the one the release announced.
2. `make test`, then `make release`. It checks the two versions match, builds, and signs `build/Dawn.zip` into `build/Dawn.zip.sig` with `scripts/sign-update.swift`.
3. Ask the maintainer before committing, pushing or releasing. Then `gh release create vX.Y.Z build/Dawn.dmg build/Dawn.zip build/Dawn.zip.sig`.

## Update signing: keep the key secret

- Dawn's release key is an Ed25519 key in the login Keychain: service `io.github.kungie.dawn.update-signing`, account `release`. It was made once with `swift scripts/update-key.swift`. It is Dawn's own key; never use Binder's.
- Never print, copy, log or commit the private key. The scripts read it straight from the Keychain and only ever print the public half.
- The public key is in `Sources/Dawn/Update.swift` (`Update.publicKey`) and in `scripts/sign-update.swift`, which refuses to sign if the Keychain key doesn't match it.
- Releases without `Dawn.zip.sig` are read but never installed by the app; a manual check then says to download from GitHub.

## Things an update must never touch

- Settings are JSON in UserDefaults under `settings` (`io.github.kungie.dawn`). Every field is decoded with a default (`Settings.init(from:)`), so new fields go in the same way and one unreadable field never resets the rest.
- Claude Code's hook and status line point at `/Applications/Dawn.app/Contents/MacOS/Dawn`; the update replaces the bundle at the same path.
- The scheduled wake (`pmset`) and the files in `~/Library/Application Support/Dawn` live outside the bundle.
- `UpdateInstallerTests` checks all of this; keep it passing.

## Privacy

Dawn sends nothing to Vektor Labs. It talks to Anthropic only through the official `claude` CLI (the ping and `/usage`) and to GitHub only for the daily update check (`api.github.com`, User-Agent `Dawn`, no data about the user) and the update download. It never reads or stores Claude credentials. If any of this changes, update `../site/datenschutz.html` (the Dawn section) too.
