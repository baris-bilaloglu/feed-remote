# Feed Remote

A browser extension for scrolling TikTok, YouTube Shorts and Instagram Reels with global hotkeys, so you can skip videos without tabbing out of a game.

## Install

For Chromium-based browsers (Chrome, Brave, Edge, Opera, Vivaldi). For Zen, Firefox and other Firefox-based browsers, see [Zen / Firefox](#zen--firefox) below.

1. Clone the repo, or download it as a ZIP and extract it.
2. Open `chrome://extensions` and turn on Developer mode.
3. Click "Load unpacked" and select the folder.

## Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+2` | Next video |
| `Ctrl+Shift+1` | Previous video |
| `Ctrl+Shift+3` | Play / pause |

You can change them at `chrome://extensions/shortcuts`. Set the scope to **Global**, otherwise they only work while the browser is focused. Chrome requires every shortcut to include Ctrl or Alt (media keys are the only exception).

You don't need a special mouse. The shortcuts work from any keyboard. If you want, you can also bind them to macro keys or anything else that can send a key combo (a Stream Deck, AutoHotkey, etc.). Just make sure it holds the keys down together instead of pressing them one after another. Recording yourself pressing the combo once is usually the easiest way.

The shortcuts only scroll the TikTok home feed (For You / Following), YouTube Shorts and Instagram Reels. Other TikTok pages like profiles are left alone.

## Mouse side buttons (Windows)

The `native` folder has an optional helper that turns the mouse side buttons into next / previous video (the lower button scrolls down, the upper one scrolls up), but only while a feed is the selected tab of a window that isn't minimized. The rest of the time they work as normal back / forward buttons, so you don't need mouse macros.

1. Double-click `native/install.bat`. It registers the helper for Chrome, Brave, Edge, Chromium and Vivaldi.
2. Restart the browser. The browser starts and stops the helper by itself.

The button mapping can be changed at the top of `native/feed-remote-host.ps1`. If you move the folder, run `install.bat` again. `uninstall.bat` removes it.

If you had mouse macros sending the shortcuts, set those buttons back to their defaults first.

## Badge

If you pin the extension, its icon shows a badge after each key press:

- `✓` worked
- `?` no TikTok/Shorts/Reels feed tab is open
- `!` tab found, but nothing to scroll (usually a login popup in the way)

No badge at all means the shortcut never reached the extension, so check the scope or your macro.

If nothing happens, make sure the feed tab is the selected tab in its window.

## Zen / Firefox

Firefox-based browsers don't support global extension shortcuts, and Zen won't permanently install unsigned extensions. So the `firefox` folder has a version in two parts:

- `feed-remote-helper.ps1` listens for the hotkeys system-wide (Windows only).
- `feed-remote.user.js` is a userscript that does the scrolling. It runs in Violentmonkey.

The helper runs a tiny HTTP server on `localhost:17345`, and the userscript keeps a request open to it. Nothing leaves your machine.

1. Install [Violentmonkey](https://addons.mozilla.org/firefox/addon/violentmonkey/).
2. Open [feed-remote.user.js](https://raw.githubusercontent.com/baris-bilaloglu/feed-remote/main/firefox/feed-remote.user.js) and click Install. If Violentmonkey asks for permission to connect to `localhost`, allow it.
3. Double-click `firefox/start.bat`. A minimized PowerShell window opens, and the hotkeys work as long as it stays open.

The default shortcuts are the same as above. Change them in the settings block at the top of `feed-remote-helper.ps1` and restart the helper. Unlike the Chrome extension, single keys without Ctrl or Alt work too (`F13` to `F24`, `Pause`, `ScrollLock`, ...), which makes binding them to mouse buttons easier. A single key is captured everywhere, so pick one you don't use for anything else.

The helper also takes over the mouse side buttons (the lower button scrolls down, the upper one scrolls up), but only while a TikTok home feed, YouTube Shorts or Instagram Reels tab is visible. The rest of the time they work as normal back / forward buttons, so you don't need mouse macros. You can change or turn this off with `$MouseForward` and `$MouseBack` in the same settings block.

To start the helper hidden with Windows, run `firefox/install-autostart.bat` once. It puts a shortcut in your Startup folder (no admin rights needed) and starts the helper right away, so you don't need `start.bat` anymore. `uninstall-autostart.bat` removes the shortcut. While it runs hidden there is no window, so if you want to see what it's doing, end it in Task Manager and use `start.bat` instead.

Don't run the helper while a Chromium browser with the extension is open. Both try to grab the same shortcuts, and the helper window will show `FAILED`.

If the helper prints `-> next` but nothing scrolls, make sure the feed tab is visible and nothing is covering it. If it prints nothing, the key combo isn't reaching it.

## Privacy

No content scripts and no data collection. A small script is only injected into the tab when you press a shortcut.

## License

MIT
