# Changelog

## 1.0.3

- New, optional: **Stay awake on the charger**. A sleeping Mac turns the light back on and no app
  can stop it, so with this on, Ember keeps a plugged-in Mac awake while the light is off, even
  with the lid shut. The screen still turns off. Unplug, quit Ember, or let the light come back on,
  and the Mac sleeps as normal again. Off unless you turn it on.
- After a plug-in or a wake, Ember checks the light again for about ten seconds, so it goes off
  within a second or two. Before, a second reset from the Mac could leave it on for up to 30 seconds.
- The FAQ explains why the light comes back on while the Mac is asleep, and why no app can stop
  that: the Mac lowers its charger power a few seconds into sleep, which resets the light, and
  nothing runs until it wakes.

## 1.0.2

- New Shortcuts action, **Set MagSafe Light**: Green, Amber, Off or Normal, from any
  automation. The colour holds (and survives sleep and plug-in) until you run it again, pick a
  mode, snooze, or a Focus with Ember's filter starts or ends. Normal hands the light back. The
  menu shows the held colour with a Clear button. ([#4](https://github.com/Getterbetter/ember/issues/4))

## 1.0.1

- Download Ember as a disk image: open it and drag Ember onto Applications.
- Opened from Downloads, Ember now asks to be moved to Applications first. Run from there,
  macOS can't start its helper ("the helper didn't answer in time").
- Uninstall now finishes: Ember quits and moves itself to the Bin. Before, it removed the
  helper and login item but then hung on quit.
- The checksum file lists bare file names, so `shasum -c` works next to a download.

## 1.0.0

First public release.

- Turns the MagSafe charging light off by Focus (Focus filters), on a schedule, for a while, or always.
- Modes: Auto, Always off, Always on. Snoozes: off for an hour, off until morning.
- Low-battery guard keeps the light on while charging below a threshold you pick.
- Re-applies the light after sleep, wake and plug-in; hands it back to macOS on quit, crash or uninstall.
- Shortcuts actions: set the mode, turn the light off for a while, wave.
- Wave: blinks the real light so you can find the cable.
- A small flame called Ember who has opinions.
- Root helper hardened: same-team code-signing checks both ways, value allowlist, idle exit,
  automatic restart after updates.
- About, Check for Updates and Uninstall in the menu.
