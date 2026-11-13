# Privacy in Cueframe

Screen recording, webcam capture, microphone monitoring, playback, and export run locally with Apple frameworks. The application does not implement analytics or automatic recording uploads.

## Local project storage

Each recording is saved as independent screen, camera, microphone, and optional Mac audio tracks in the app sandbox’s Application Support directory. Projects also contain recording settings, source-relative cursor positions and clicks, audio activity levels, edit suggestions, and any generated transcript. The app does not record typed key values. Project names can include the selected window title.

Use **Recordings → Open → Show source files** to locate a project. Originals remain on disk after export. Delete an unwanted project through Finder. This version does not automatically remove recordings or guarantee recovery of unfinished media after a forced shutdown.

## Optional OpenAI processing

AI editing is opt-in for each recording through **Generate AI Edit**. It sends sampled screen JPEGs, timestamped click positions, and microphone audio directly to `api.openai.com` for visual analysis and transcription. Camera video and Mac audio are not uploaded. Transcripts are stored locally with the project. No API request runs just because you record or open a project.

The Responses request uses `store: false`. OpenAI’s own processing and retention policies still apply; this setting is not a guarantee of zero retention. See [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data). API usage is billed to the user’s OpenAI project.

Your API key is saved in macOS Keychain. The app does not save it in preferences, projects, logs, exported videos, or source files. **Settings → Remove saved key** deletes the saved Keychain item. It does not delete recordings or transcripts.

## macOS permissions

Apple’s sharing picker authorizes the window or display you explicitly select for a capture session. The app does not infer authorization from a global privacy toggle. Microphone and camera access are needed only for enabled inputs. Permissions can be revoked in System Settings. The preflight microphone meter listens locally while its controls are visible and microphone access is granted.

The app requests outbound network access for optional OpenAI calls. Local recording and export remain usable without an API key or internet connection. This document describes this personal fork; the original project’s policy is archived in [docs/UPSTREAM-PRIVACY.md](docs/UPSTREAM-PRIVACY.md).
