# SpotHub Privacy Notice

Last updated: October 11, 2026

SpotHub has separate **official** and **personal** Android flavors. The data sent to third parties depends on the installed flavor and the features you use.

## Official flavor

The official flavor stores the YouTube Data API key entered in Settings on the device. Searches send the query and key directly to Google's YouTube Data API. YouTube videos play in the embedded IFrame player.

## Personal flavor

The personal flavor does not use a YouTube Data API key. It uses `youtube_explode_dart` to request YouTube search results, video metadata, playlist contents, and audio stream information. `just_audio` streams the selected audio from YouTube's media servers through Android's background media service. Stream URLs are resolved when needed and can be refreshed after an error. If you choose to download a track, SpotHub saves that audio in app-private storage for offline playback; uninstalling SpotHub removes those files.

This path relies on undocumented YouTube web interfaces. YouTube handles its network requests under its own terms and privacy practices. The personal flavor is a separate sideload build.

## Spotify

If you connect Spotify, SpotHub uses Authorization Code with PKCE. Your Spotify password is entered on Spotify's authorization page and is never available to SpotHub. SpotHub requests playlist access, stores access and refresh tokens with Android secure storage, and deletes them when you disconnect Spotify. Playlist and track metadata is requested as you browse and is displayed separately from YouTube results. Opening a Spotify item sends its link to Spotify's app or browser.

## Local app data

Your playlists, favorites, playback history, search cache, configured YouTube API key, and Spotify Client ID are stored on your device. Spotify tokens are stored in Android secure storage. SpotHub does not operate an app server or collect analytics. Uninstalling the app removes its local data.

## Your choices

Remove the YouTube API key or disconnect Spotify in Settings. You can also revoke SpotHub's Spotify access from your Spotify account settings.
