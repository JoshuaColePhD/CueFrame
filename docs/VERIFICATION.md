# Mac verification — 2026-11-13

Verified on the user's Apple Silicon Mac with macOS 27.2.1 and Xcode 27.2. The personal app is installed at `~/Applications/EasyDemo Personal.app`. Original capture files and QA exports remain local and are excluded from Git.

## Completed

- Debug build and all **17 logic, media, transport, and startup tests** passed. The suite includes permission denial and late permission cancellation, missing credentials, malformed/refused AI responses, HTTP 401, interrupted requests, conservative pause detection, settings/project persistence, safe export failure and original-file protection.
- Release build, local certificate signing, strict signature verification, ZIP packaging, installation, and application launch succeeded. Debug uses a separate bundle identifier to protect the installed app's privacy identity.
- Apple’s native source picker successfully authorized both a window and a display. Camera and microphone permissions were granted by the user. Replacing the global screen-preflight requirement with the picker’s selected filter resolved the capture startup blocker.
- An **86.284-second display recording** saved independent screen, camera, and microphone tracks without errors. Native export produced a playable **1920×1080, 30 fps H.264 MP4 with AAC audio**, approximately 20 MB. The export was decoded for integrity checking.
- A **795.381-second window recording** (13 minutes 15 seconds) saved screen, camera, microphone, and Mac audio separately, with a complete manifest and no capture failure. All files grew throughout the session.
- A further **20.561-second display recording**, with all four inputs enabled, captured an audible system test sound. The Mac audio track had a measured peak of **−14.1 dBFS**. The Mac audio preference was restored to off afterward.
- Native review playback, manual zoom controls, original comparison, project reopening, and save-panel export were exercised. A synthetic media integration test verifies that zooms enlarge the screen target while the camera's bounds stay fixed within one encoded pixel, and that cuts affect every track together.
- The shared squircle path is used by preview and export. Source selection and recording preferences survive app relaunch. A permission request can be cancelled without a late grant starting a recording.
- The user selected **HD Pro Webcam C920**. This device choice was saved, and a 26.292-second screen/camera/microphone recording completed without capture errors. Moving the squircle using Custom position was verified manually, then its position was restored to Bottom Left. The initial camera image was dark because its physical cover was closed. After the user opened the cover, live preview and a further **20.422-second C920/screen/microphone recording** showed a clear picture. Its native H.264 MP4 export and composite playback succeeded.

## Timing evidence and limits

All captured sources use the host clock; source offsets are retained in the composition rather than shifting each track to zero.

The 795-second window recording had these encoded endpoints:

| Track | Start (seconds) | End (seconds) |
| --- | ---: | ---: |
| Screen | 0.073333 | 795.410000 |
| Camera | 0.058333 | 795.421666 |
| Microphone | 0.213833 | 795.413833 |
| Mac audio | 0.117083 | 795.317083 |

Screen, camera, and microphone ended within **11.7 ms**. Mac audio ended **104.6 ms** before the camera; this slightly exceeds the requested 100 ms endpoint target. Track endpoints include frame/packet boundaries and capture shutdown tails and do not establish acoustic drift or lip sync. Preview/export preserve these timestamps and fill missing tail audio with silence. A human clap/voice comparison at both ends remains necessary to establish hardware synchronization below 100 ms.

The ten-minute synthetic writer and composition tests pass their timing checks, including an idle screen extended through narration. These complement the live run but do not replace an acoustic synchronization measurement.

## Remaining verification

- **Live OpenAI editing:** the user chose to leave this test for later. No API key was saved during verification. Missing-key, HTTP failure, cancellation, and output-validation behavior passed automated tests; an actual transcription/visual-analysis request remains unverified. Enter a key in the app's Settings and invoke Generate AI Edit on a recording to complete this check. Camera and Mac audio are not uploaded.
- Real hardware disconnects and every combination of macOS permission denial were not forced during the live recording. The implementation has explicit unavailable-device checks, startup cleanup, and camera/microphone stall handling; automated coverage does not simulate every physical fault.
- This is a local personal build, not a notarized public installer. Remote GitHub CI status is separate from the passing local checks.

Local recordings remain in the app's sandbox under Application Support/EasyDemo/Recordings. Use Recordings → Open → Show source files to inspect them. Unfinished MOV files after a force quit or power loss are not guaranteed recoverable.
