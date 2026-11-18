# Feed Remote

A browser extension for scrolling TikTok, YouTube Shorts and Instagram Reels with global hotkeys, so you can skip videos without tabbing out of a game.

## Install

Only works in Chromium-based browsers (Chrome, Brave, Edge, Opera, Vivaldi). Firefox doesn't support global extension shortcuts.

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

You don't need a special mouse. The shortcuts work from any keyboard. If you want, you can also bind them to mouse side buttons, macro keys or anything else that can send a key combo (a Stream Deck, AutoHotkey, etc.). Just make sure it holds the keys down together instead of pressing them one after another. Recording yourself pressing the combo once is usually the easiest way.

## Badge

If you pin the extension, its icon shows a badge after each key press:

- `✓` worked
- `?` no TikTok/Shorts/Reels tab is open
- `!` tab found, but nothing to scroll (usually a login popup in the way)

No badge at all means the shortcut never reached the extension, so check the scope or your macro.

If nothing happens, make sure the feed tab is the selected tab in its window.

## Privacy

No content scripts and no data collection. A small script is only injected into the tab when you press a shortcut.

## License

MIT
