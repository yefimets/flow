---
name: flow
description: Work with the user's Flow window manager (macOS). Use it to ask for the user's attention when you are blocked on them, to withdraw that request, and to open a web page in a browser column next to your own window. Trigger whenever you need a decision, approval or input from the user, when you finish a long task, or when you want to show the user a page, docs, a PR or research results.
---

# Flow: attention and windows for agents

Flow is the user's window manager. Every terminal window you run in sits in a *flow* (a workspace).
The user may be looking at a different flow. Flow gives you three commands so you never have to hope
they notice. All three are safe, instant, and idempotent.

## Setup: find flow and tag your window (once per session)

```bash
FLOW=$(command -v flow || ls ~/flow/build/Flow.app/Contents/MacOS/flow /Applications/Flow.app/Contents/MacOS/flow 2>/dev/null | head -1)
[ -n "$FLOW" ] || echo "Flow is not installed; skip the flow commands"
TAG="flow:$(basename "$PWD")-$$"
printf '\033]0;%s\007' "$TAG"     # sets this terminal window's title so Flow can find it
```

Do this at the start of a session. The tag must stay in the window title, so if you later change the
title, include the tag again.

## Ask for the user (you are blocked, or done)

```bash
"$FLOW" cmd attention --tag "$TAG" --priority 2 "Need your OK to push 3 commits to main"
```

- Flow shows a small card in the corner with the message and plays a sound. The user presses ⌥⇥ and
  lands in your window, switching flows if needed.
- `--priority 3` for things that block you and cost money or time (a failing deploy, a permission
  prompt), `2` for a decision or approval, `1` for "done, have a look when you like".
- Keep the message under 80 characters and say what you need, not what you did.
- One request per tag at a time: a new request replaces your previous one.

When the user has answered, or you found another way, withdraw it:

```bash
"$FLOW" cmd attention --clear --tag "$TAG"
```

## Show the user a page

```bash
"$FLOW" cmd open "https://github.com/org/repo/pull/42" --tag "$TAG"
```

Opens the URL in a new browser window tiled into your flow, next to your window. If the user is on
another flow, Flow buzzes "Page ready" and ⌥⇥ takes them there. Use it for a PR you opened, docs you
found, a dashboard to check, or a comparison you prepared. One page per call; prefer the one page that
answers the question over five tabs.

## Rules

- Never call `attention` for routine progress. It interrupts a human. Blocked, finished, or a real
  decision only.
- Do not repeat a request that is still open. If nothing happens, keep working on what you can.
- Never send secrets or personal data in the message; it is shown on screen and written to a log.
- If `$FLOW` is empty, do nothing; fall back to asking in chat.

## Other commands you may use

`"$FLOW" cmd new` (a fresh flow), `"$FLOW" cmd browser` (empty browser window in the grid),
`"$FLOW" cmd screenshot` (PNG of every window in the current flow, into ~/Desktop/flow-screenshots,
for you to read). Only when the user asked you to arrange their screen.
