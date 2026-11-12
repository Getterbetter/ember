# Contributing

Thanks for helping. Ember is small on purpose: one job (the MagSafe light), done nicely.

## Building

You need macOS 26+, Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
echo 'EMBER_BUNDLE_PREFIX = com.yourname' >> Config/Local.xcconfig   # your own bundle prefix
DEVELOPMENT_TEAM=YOURTEAMID scripts/build.sh test                   # unit tests
DEVELOPMENT_TEAM=YOURTEAMID scripts/build.sh install                # signed build into /Applications
```

The helper only runs when it is signed with a team ID (an Apple Development or Developer ID certificate).

## Where things live

| Folder | What |
|---|---|
| `EmberKit/` | The policy, personality and settings. Pure Swift, unit tested. Most changes start here. |
| `Ember/` | The menu bar app, Focus filter and Shortcuts. |
| `EmberHelper/` | The root helper. Keep it tiny; changes here get extra scrutiny. |
| `Shared/` | SMC access and the XPC contract, compiled into both. |

## Pull requests

- Add or update tests in `EmberKitTests/` for behaviour changes.
- If you change `EmberHelper/` or `Shared/`, bump `EmberIdentity.helperVersion` so installed
  helpers restart on update.
- Keep Ember's voice: short, dry, a little cheeky, one line.
