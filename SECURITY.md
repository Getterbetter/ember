# Security

Ember installs a small helper that runs as root, so its security matters.

## What the helper can do

- It accepts XPC connections only from Ember.app signed with an Apple-issued certificate from
  the same team as the helper itself (checked with a code-signing requirement on every connection).
- It exposes two real operations: write one value to the MagSafe light SMC key (`ACLC`), and report
  its version. Values outside the light's known states are refused. It never reads or writes any
  other SMC key, file, or setting.
- It refuses to start if it isn't root or isn't signed with a team ID.
- If Ember.app disappears it hands the light back to macOS, then exits after a minute of idling.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** (Security tab › Report a vulnerability).
Don't open a public issue for security problems. You'll get a reply within a week.

## Supported versions

Only the latest release gets fixes.
