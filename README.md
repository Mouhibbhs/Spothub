# SpotHub

![SpotHub app icon](final-icon.png)

SpotHub is an Android music discovery app for searching, organizing, and playing music. It brings YouTube search, Spotify playlist matching, local playlists, background audio, and offline downloads into one rounded, dark interface.

## Download

Get the [latest SpotHub Personal APK](https://github.com/Mouhibbhs/Spothub/releases/latest), or browse [all versioned releases](https://github.com/Mouhibbhs/Spothub/releases).

## Features

- Search YouTube and browse music categories.
- Import a YouTube playlist from its link.
- Paste a public Spotify playlist link to match its tracks to YouTube videos and add the matches to a SpotHub playlist.
- Create and organize playlists, change their covers, save favorites, and revisit recently played tracks.
- Add songs to play next, then return to the existing queue order. Shuffle and repeat controls are available in the player.
- Save supported songs or entire playlists for offline playback. Track download progress through Android notifications, manage saved songs in Downloads, and create offline playlists from selected downloads.
- Export and restore a library backup from Your Library.

## Android builds

SpotHub has two Android flavors. They have separate application IDs and can be installed side by side.

| Flavor | Package | Search and playback |
| --- | --- | --- |
| Official | `com.spothub.spothub` | YouTube Data API v3 search and the embedded YouTube player. Add an API key in Settings. |
| Personal | `com.spothub.personal` | YouTube catalog, native background audio, notification controls, and offline downloads. No YouTube Data API key is used. |

The personal flavor is a separate sideload build. Its YouTube search, playlist import, and audio playback depend on unofficial YouTube web interfaces and may stop working if YouTube changes them. SpotHub is an independent project and is not affiliated with YouTube, Google, or Spotify.

## Build from source

See the [source code and build guide](SOURCE_README.md) for prerequisites, setup, and commands for running or building each flavor.

For a personal release APK, use:

```powershell
flutter pub get
flutter build apk --release --flavor personal -t lib/main_personal.dart
```

The APK is created at `build/app/outputs/flutter-apk/app-personal-release.apk`. The current Android release configuration signs it with the local debug key for private sideloading.

You can also download the included [personal release APK](releases/SpotHub-personal-release.apk) from this repository.

## Data and offline files

Playlists, favorites, history, covers, and settings are stored locally on the device. Use the library backup controls to export and restore library data. Personal-flavor audio downloads are stored in app-private storage and are removed when SpotHub is uninstalled.
