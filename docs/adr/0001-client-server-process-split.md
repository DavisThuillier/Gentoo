# 0001. Split playback into a bundled XPC service

**Status:** Accepted
**Date:** 2026-08-16
**Spec:** §3

## Context

The player must survive malformed audio files. Third-party decoders sit in the audio path
(see [0002](0002-sfbaudioengine-for-playback-and-tag-io.md)), and a file crafted or
corrupted badly enough to crash a decoder would otherwise take the whole window with it —
losing the user's queue, scroll position, and in-flight scan.

Playback is not required to continue after the GUI closes (spec §2), which removes the
usual argument for a long-lived background daemon.

## Decision

Run decode and audio output in a separate `PlaybackService.xpc`, bundled inside the app at
`Contents/XPCServices/` with `ServiceType: Application` in its `Info.plist`. It terminates
with the app. Communication is `NSXPCConnection`.

The service is a **transport, not a queue manager**. It holds the currently playing track
plus at most one enqueued next track for gapless. All queue semantics — ordering,
advancing, shuffle, repeat, switching active queues — live in the app. The service never
reads the library database and has no concept of a collection.

`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are registered by the **app process**,
not the service. The app mirrors engine state upward and publishes it.

## Consequences

- A decoder crash loses audio, not the application. The app detects XPC interruption,
  restarts the service, and resumes at the last reported position.
- Every playback interaction crosses a process boundary, so the protocol must be typed and
  asynchronous. Position updates are published at ~10Hz rather than per-buffer to keep the
  boundary from becoming a bottleneck.
- State exists in two places and must be reconciled after any interruption. The app's view
  of position is authoritative for resume.
- No `LaunchAgent`, no daemon lifecycle, no login item. The service's lifetime is exactly
  the app's.
- SFBAudioEngine's `AudioPlayer` maintains its own internal decoder queue. Using it as the
  app's queue would silently relocate queue semantics into the service and defeat this
  split. Enqueue exactly one track ahead.

## Alternatives considered

**Single process.** Simpler, one less boundary, no state reconciliation. Rejected because
it puts third-party decoder code in the same address space as the UI and the library
database — the specific failure this decision exists to prevent.

**A long-lived `LaunchAgent` daemon.** Would allow playback to continue after the GUI
quits. Rejected: that is an explicit non-goal (spec §2), and it buys a substantially more
complex lifecycle — install, update, version skew between app and daemon — for a feature
nobody asked for.

**Registering Now Playing from the service.** Would keep all playback concerns in one
place. Rejected because `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` do not work
correctly from an XPC service; media keys and the Control Center widget require the app
process. This is a platform constraint, not a preference.
