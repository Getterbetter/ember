<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Ember, a small smiling flame">
</p>

<h1 align="center">Ember</h1>

<p align="center">
  <b>Turns your MacBook's MagSafe charging light off when you want dark.</b><br>
  Follows your Focus modes, lives in the menu bar, and has a bit of personality.
</p>

<p align="center">
  <a href="https://github.com/Getterbetter/ember/releases/latest">Download</a> ·
  <a href="#set-up">Set up</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="SECURITY.md">Security</a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MagSafe%203-orange">
  <img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue">
</p>

---

That little amber-then-green light on the MagSafe cable is lovely on a desk and less lovely
at 2am in a dark bedroom. Ember switches it off when you're sleeping, focusing, or just over it,
and hands it back to macOS the rest of the time.

Ember is a small flame. It dozes when the light is off, wakes when it's on, gets wide-eyed when
the battery is low, and winks when you poke it. Click **Wave** and it blinks the real light so
you can find the cable in the dark.

## What it does

- **Focus aware.** Add Ember's Focus filter to Sleep, Do Not Disturb, Work, whatever. The light
  goes dark (or green, or amber) while that Focus is on and comes back when it ends.
- **Modes.** Auto (follow Focus), Always off, Always on.
- **Snoozes.** Off for an hour, or off until morning.
- **Lights-out schedule.** Optional, for example 22:00 to 07:00.
- **Low-battery guard.** Plugged in and under 20% (you pick)? The light stays on so you can see
  it's charging.
- **Self-healing.** macOS resets the light when you plug in, sleep or wake. Ember puts it back.
- **Safe exit.** Quit, crash or uninstall, and the light goes back to normal.
- **Shortcuts.** Set the mode, turn the light off for a while, or wave, from Shortcuts or Siri.

## Install

1. Download `Ember-x.y.z.dmg` from [Releases](https://github.com/Getterbetter/ember/releases/latest),
   open it, and drag **Ember** onto the **Applications** shortcut. (A zip is there too if you prefer.)
2. Open it. It's signed and notarised by Apple, so it opens normally.

Requires an Apple Silicon MacBook with a MagSafe 3 port and macOS 26 or later.

## Set up

The welcome window walks you through three steps:

1. **Let Ember reach the light.** Changing the light needs admin rights, so Ember installs a tiny
   helper. Approve **Ember** in System Settings › General › Login Items.
2. **Add Ember to your Focuses.** System Settings › Focus › pick a Focus › Focus Filters ›
   Add Filter › Ember › MagSafe light: **Off**. Repeat for each Focus you want dark.
3. **Open at login**, so the light behaves after a restart.

## FAQ

**Is it safe?**
The helper does exactly one thing: write one of the light's states to one SMC key (`ACLC`). It only
talks to Ember itself (checked by code signature on every connection), refuses anything that isn't a
light state, and exits when it's not needed. It never touches charging, fans or anything else.
Details in [SECURITY.md](SECURITY.md).

**Why does a light switch need admin rights?**
macOS only lets root write to the System Management Controller, which is the chip that drives
the light. Reading it doesn't need root, so Ember checks the light itself and only asks the
helper when something needs changing.

**How does it know my Focus?**
macOS doesn't tell apps which Focus is on. It only says whether one is. Focus filters are
Apple's supported way: you tell each Focus what Ember should do, and macOS tells Ember when that
Focus starts and ends. Nothing private is read and no Full Disk Access is needed.

**Does it work with AlDente or batt?**
Yes, as long as only one app controls the light. Ember warns you if AlDente is running. Ember never
touches charge limits.

**Intel Macs or older MagSafe?**
No. Ember needs an Apple Silicon MacBook with MagSafe 3.

**How do I uninstall it?**
Ember menu › ⋯ › Uninstall Ember. It hands the light back, removes the helper and login item, and
shows Ember in Finder so you can drag it to the Bin.

**Does it phone home?**
No. The only network request is **Check for Updates**, which asks GitHub for the latest release
when you pick it.

## Build from source

macOS 26+, Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
echo 'EMBER_BUNDLE_PREFIX = com.yourname' > Config/Local.xcconfig
DEVELOPMENT_TEAM=YOURTEAMID scripts/build.sh install   # tests, signed build, into /Applications
swift scripts/smc-probe.swift                          # read-only: does this Mac have the light key?
```

If XcodeGen is a symlink to a release download (not Homebrew), link its `SettingPresets` folder next to the
symlink too (for example `ln -s ~/.local/share/xcodegen/share/xcodegen/SettingPresets ~/.local/share/xcodegen/SettingPresets`),
or the generated project has no product names.

Releases are built with `scripts/release.sh` (Developer ID signing, hardened runtime, notarisation).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how the code is laid out.

## How it works

- **EmberKit**: the decision logic. Precedence, highest first: low-battery guard, Always off, an
  active snooze, Always on, then in Auto: Focus filter, schedule, normal. Pure Swift, unit tested.
- **Ember.app**: the menu bar app, Focus filter and Shortcuts actions.
- **EmberHelper**: the root launchd daemon (`SMAppService`) with one job.

The light's values (`0` macOS controls it, `1` off, `3` green, `4` amber) come from the
open-source [batt](https://github.com/charlie0129/batt) project, which deserves the credit for
working them out.

## Licence

MIT. Ember isn't affiliated with Apple. It writes to your Mac's SMC; it's been careful to touch only
the light, but you use it at your own risk.
