# Local YouTube Explode patch

This app vendors the `youtube_explode_dart` dependency pinned at commit `edad2760cc7998bcc18013dc9880c052ad32598f` from the project history. The playlist client now keeps valid playlist video IDs even when YouTube omits uploader channel metadata, supplying a placeholder channel ID instead of silently dropping those videos.

The upstream package license is in `LICENSE`.
