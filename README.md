# touch-claude

A small macOS app that shows your Claude subscription usage on the MacBook Touch Bar.

**Control Strip tile** – always visible, in every app: 5-hour session and weekly limit.

![Control Strip tile](docs/control-strip.png)

**Tap the tile** for the detail view: both limits with their reset times and an hourly chart of
input / output tokens over the last 24 hours.

![Expanded view](docs/expanded.png)

Colours follow the limit: orange below 70 %, yellow from 70 %, red from 90 %.

**Menu bar** – the same content as the Touch Bar, with the numbers, refresh and quit in its menu.
By default it shows the whole detail view (limits, reset times and the token chart), so the app
is just as useful on a Mac without a Touch Bar. Turn off **Show Details in Menu Bar** in the menu
to shrink it to the two limits only.

![Menu bar item](docs/menu-bar.png)

The detailed item is about 320 pt wide; macOS hides menu bar items that do not fit next to the notch.

## Requirements

- A MacBook Pro with a Touch Bar – or any Mac, using the menu bar only
- macOS 13 or newer, Xcode Command Line Tools (`xcode-select --install`) – full Xcode is not needed
- [Claude Code](https://claude.com/claude-code) with a Pro or Max subscription, and `jq`

## Install

```sh
./build.sh
open build/ClaudeUsageBar.app
```

Then point Claude Code's status line at the hook in `~/.claude/settings.json`
(use the absolute path of your checkout):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/touch-claude/statusline.sh"
  }
}
```

## How it works

- **Limits** – Claude Code passes the current rate limits to its status line command.
  `statusline.sh` saves them to `~/.claude/usage-touchbar.json` and the app re-reads that file
  every 5 seconds. The numbers therefore only move while Claude Code is running, and appear after
  the first reply of a session.
- **Tokens** – read from the Claude Code session transcripts in `~/.claude/projects`. Only token
  counts and timestamps are read, never message content. "in" is newly sent tokens (input plus
  cache writes); cache reads are left out because they would dwarf everything else. Each half of
  the chart has its own scale. Usage on claude.ai is not included.
- **Touch Bar** – the Control Strip item uses private system API (the same mechanism as MTMR or
  Pock), since Apple offers no public one. A macOS update may break it.

## Options

```
ClaudeUsageBar [--source file|oauth|demo] [--file path] [--once] [--expanded]
```

- `--source demo` – fake limits for trying out the UI (the screenshots above use it)
- `--source oauth` – asks the Anthropic API directly using the Claude Code login from the
  Keychain instead of the status line file. Untested.
- `--once` – print the current numbers and exit
- `--expanded` – open the detail view on launch
- `-menuBarFull YES|NO` – override the "Show Details in Menu Bar" setting for this run
