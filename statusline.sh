#!/bin/sh
# Claude Code status line hook.
# 1. Saves the subscription rate limits Claude Code hands us to a file that
#    ClaudeUsageBar.app shows on the Touch Bar.
# 2. Prints a one-line status for Claude Code itself.
input=$(cat)
out="${CLAUDE_USAGE_FILE:-$HOME/.claude/usage-touchbar.json}"

# rate_limits is missing until the first API response of a session; never
# overwrite good numbers with nothing. Write atomically, sessions run in parallel.
limits=$(printf '%s' "$input" | /usr/bin/jq -c \
    'select(.rate_limits.five_hour or .rate_limits.seven_day) | {rate_limits}' 2>/dev/null)
if [ -n "$limits" ]; then
    tmp="$out.$$"
    printf '%s\n' "$limits" > "$tmp" && mv "$tmp" "$out"
fi

printf '%s' "$input" | /usr/bin/jq -r '
    [ .model.display_name // empty,
      (.rate_limits.five_hour | select(.) | "5h \(.used_percentage | round)%"),
      (.rate_limits.seven_day | select(.) | "7d \(.used_percentage | round)%")
    ] | join(" · ")' 2>/dev/null
