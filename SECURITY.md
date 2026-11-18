# Security

Ember installs a small helper that runs as root, so its security matters.

## What the helper can do

- It accepts XPC connections only from Ember.app signed with an Apple-issued certificate from
  the same team as the helper itself (checked with a code-signing requirement on every connection).
- It exposes three real operations: write one value to the MagSafe light SMC key (`ACLC`), switch
  macOS sleep off or on, and report its version. Values outside the light's known states are
  refused. It never reads or writes any other SMC key.
- Switching sleep is for the optional **Stay awake on the charger** setting. The helper runs
  `/usr/bin/pmset -a disablesleep 1` or `0` with fixed arguments, refuses to switch sleep off on
  battery, and turns it back on by itself when the Mac is unplugged (checked every 15 s), when
  Ember.app goes away, and before it exits for an update. It records that it switched sleep off in
  `/Library/Application Support/<prefix>.ember.helper/sleep-disabled`, so if it is ever killed, its
  next start turns sleep back on. It only turns sleep back on if it was the one that switched it
  off, so a `disablesleep` you set yourself is left alone.
- It refuses to start if it isn't root or isn't signed with a team ID.
- If Ember.app disappears it hands the light back to macOS and lets the Mac sleep again, then exits
  after a minute of idling.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** (Security tab › Report a vulnerability).
Don't open a public issue for security problems. You'll get a reply within a week.

## Supported versions

Only the latest release gets fixes.
