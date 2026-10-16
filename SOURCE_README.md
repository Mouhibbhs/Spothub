# SpotHub source code and build guide

This guide covers the Flutter source tree and how to configure, run, and build the Android flavors. For a feature overview of the app, see [README.md](README.md).

## Requirements

- Flutter 3.47.2 or newer and its matching Dart SDK
- Android SDK Platform 36 and Android Build Tools 36.0.0 (or the versions selected by Flutter)
- Java 17 or newer
- An Android emulator or device for running the app

Check the local setup with `flutter doctor`.

## Flavors

SpotHub has two isolated Android flavors:

- **Official** (`com.spothub.spothub`): YouTube Data API v3 search with a key entered in Settings and video playback in the embedded YouTube IFrame player.
- **Personal** (`com.spothub.personal`): uses `youtube_explode_dart` for YouTube search, playlist links, metadata, and audio streams; `just_audio` and `audio_service` provide native background playback and media controls. It does not use a YouTube Data API key. This is a separate sideload build and uses YouTube's undocumented web interfaces, which may change or stop working.

The flavors have separate entry points, application IDs, Android activities, and playback implementations. The personal release APK is signed with the local Android debug key for sideloading.

## YouTube search setup

Only **official** builds need a YouTube Data API v3 key:

1. Create a Google Cloud project and enable YouTube Data API v3.
2. Create an API key, then restrict it to the YouTube Data API v3.
3. Run the official flavor and enter the key under **Settings → YouTube Data API v3 key**.

The key is stored on the device and used for official-flavor YouTube searches. Restrict its Android application ID to `com.spothub.spothub`. See Google's [Search: list reference](https://developers.google.com/youtube/v3/docs/search/list) and Cloud quota dashboard for details.

The personal flavor does not read or send this key.

## Run and build

```powershell
flutter pub get
flutter analyze
flutter run --flavor official -t lib/main.dart
flutter build apk --release --flavor official -t lib/main.dart
flutter run --flavor personal -t lib/main_personal.dart
flutter build apk --debug --flavor personal -t lib/main_personal.dart
flutter build apk --release --flavor personal -t lib/main_personal.dart
```

APK output paths:

- Official release: `build/app/outputs/flutter-apk/app-release.apk`
- Personal debug: `build/app/outputs/flutter-apk/app-personal-debug.apk`
- Personal release: `build/app/outputs/flutter-apk/app-personal-release.apk`

## Download versioned APKs

The [GitHub Releases page](https://github.com/Mouhibbhs/Spothub/releases) keeps APKs attached to each app version. Each tagged release contains both the official and personal flavor.

To publish a new version:

1. Update the `version` in `pubspec.yaml` (for example, `1.0.1+2`).
2. Commit and push the source changes to `main`.
3. Create and push the matching version tag, using the version before `+` (for example, `v1.0.1`).

GitHub Actions builds both release APKs and adds them to a versioned release automatically. The release tag must match the version in `pubspec.yaml`.

Both flavors display the app name **SpotHub** and can be installed side by side because they use different package IDs.

## Source layout

- `lib/app/` — theme, router, providers, and app shell
- `lib/core/database/` — versioned SQLite database and foreign-key configuration
- `lib/features/search/` — shared search UI and official API-backed search
- `lib/features/personal/` — personal-flavor YouTube catalog and playlist import
- `lib/features/player/` — embedded YouTube player and personal native audio playback
- `lib/features/library/` — playlists, favorites, playback history, and library screens
- `lib/features/downloads/` — audio downloads, download notifications, and saved-song listing
- `lib/features/backup/` — local library export and restore
- `lib/features/spotify/` — public Spotify playlist import and YouTube matching
- `lib/features/settings/` — app settings and playback preferences
- `third_party/youtube_explode_dart/` — bundled YouTube client source and license

Search results are cached locally for up to seven days. Playlist, favorite, and playback-history records use track IDs. Imported Spotify tracks are matched to YouTube videos and added to SpotHub playlists; Spotify sign-in is not required.

## Import playlists

### YouTube

In **Your Library**, choose **Import YouTube playlist from link** and paste a playlist URL. The personal flavor can import up to 500 available videos from a public or unlisted playlist.

### Spotify

In **Your Library**, choose **Import Spotify playlist from link** and paste a public Spotify playlist URL. SpotHub reads the playlist's tracks and searches YouTube for matches, then saves matched tracks in a local SpotHub playlist. Matching can take time for large playlists and not every track is guaranteed to have a match. No Spotify account login, Client ID, or client secret is needed.

### CSV

From **Your Library**, use the file-import icon and select a CSV file. The file can be up to 2 MB and contain at most 500 videos. Required columns are `videoId` (or `youtubeUrl`) and `title`; `channelName` or `artist` is optional. IDs must be 11-character YouTube IDs, or the URL can be a `youtube.com/watch`, `/shorts`, `/embed`, `/live`, or `youtu.be` link. Rows without a valid ID or title are skipped. Spotify track IDs are not YouTube video IDs; include the matching YouTube ID or URL in the CSV.

## Playback and downloads

The official flavor plays videos in YouTube's embedded player. The personal flavor uses native Android audio playback with a media session, foreground service, and notification controls. Stream URLs are resolved as needed and retried if they expire. The personal flavor also supports shuffle, repeat, queue controls, song and playlist downloads, and offline playlists built from saved songs.

Personal-flavor downloads are stored inside the app's private data directory. On Android, the current path is `/data/user/0/com.spothub.personal/app_flutter/audio_downloads`. Normal file managers cannot access this private directory, and Android removes it when the app is uninstalled.

## Library backup

Use the **Export backup** and **Restore backup** controls in Your Library to move playlist and library data between installations. Audio download files are not included in the backup and must be downloaded again after reinstalling.
