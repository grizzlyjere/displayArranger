# Skills And Lessons Learned

## App Shortcuts On macOS

- `NSSupportsAppShortcuts` in `Info.plist` is necessary but not sufficient.
- A macOS app must ship `Contents/Resources/Metadata.appintents` for Shortcuts to discover `AppIntent` and `AppShortcutsProvider` actions reliably.
- If the bundle does not contain `Metadata.appintents`, rebooting or reopening Shortcuts will not make the actions appear.

## SwiftPM Packaging Gap

- A plain `swift build` app bundle can compile and run while still missing App Intents metadata.
- Xcode contains the tooling needed to generate that metadata even when the app is packaged from scripts:
  - `swift-frontend` with `-emit-const-values-path`
  - `appintentsmetadataprocessor`
- The metadata generation flow is:
  1. Find Swift files that define App Intents-related types.
  2. Run `swift-frontend -frontend -typecheck` for each primary source file and emit `.swiftconstvalues`.
  3. Run `appintentsmetadataprocessor` with the source file list and const-values list.
  4. Copy `Metadata.appintents` into `Contents/Resources/`.

## Xcode Tooling Assumptions

- Do not assume the active developer directory points at full Xcode.
- `xcode-select -p` may point to Command Line Tools only, which is not enough for some App Intents workflows.
- The scripts can safely use `/Applications/Xcode.app/Contents/Developer` directly when the required tools are present there.
- The Xcode SDK path is a directory, so validate it with `[[ -d ... ]]`, not `[[ -f ... ]]`.

## Bash Portability

- macOS system Bash is usually 3.x, so avoid `mapfile`.
- Prefer `while IFS= read -r ...; do ...; done` loops for portable array population in build scripts.

## Install And Ownership Pitfalls

- Old root-owned build artifacts can block later non-root builds and packaging.
- Root-owned `.app` bundles in the repo root are especially disruptive because `rm -rf` and repackaging will fail.
- Packaging into a writable build-owned location like `.build/packaged-apps/` is safer than writing the app bundle into the repo root.
- Installing to `/Applications` may fail if an existing copy is root-owned or the directory is not writable.
- A practical fallback is `~/Applications/<AppName>.app`.

## Verification Checklist

- Confirm the installed bundle contains:
  - `Contents/Resources/Metadata.appintents/extract.actionsdata`
  - `Contents/Resources/Metadata.appintents/version.json`
- Launch the installed app once from the actual installed location.
- Quit and reopen Shortcuts after installing a newly packaged build.
- Search for both the app name and the specific shortcut titles.

## DisplayArranger-Specific Notes

- The key Shortcuts surfaced by this app are:
  - `Export Display Layout`
  - `Apply Display Layout`
- The packaging and install scripts now handle:
  - generating App Intents metadata
  - bundling metadata into the app
  - installing from `.build/packaged-apps`
  - falling back to `~/Applications` when needed
