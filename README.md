# 雀馆 Mahjong

An online four-player Chinese mahjong parlor built with Phoenix LiveView.
Create a room, share the link, and everyone who opens it takes a seat —
empty seats are filled by AI players with distinct personalities. Spectators
can watch the game live from any seat's perspective.

## Features

- **Instant rooms** — no sign-up. Open a room, share the URL, and friends
  join straight from the link
- **Real-time play** — Phoenix LiveView + PubSub keep every seat, discard
  pile, and claim window in sync
- **AI players** — fill empty seats with persona-driven AIs (an optional
  LLM decision layer refines their play; a built-in rule engine is the
  offline fallback)
- **Complete fan scoring** — 全求人 (quan qiu ren), 将将胡 (jiang jiang hu),
  碰碰胡 (pung pung), 清一色 (pure suit), 七小对 (seven pairs), 平胡 (ping
  hu) and more. Independent hand types stack and compound in the name:
  a discard win with all-melded 2/5/8 tiles calls *全求人碰碰胡将将胡*
- **Spectators** — watch any room live; the table is rendered from your
  own seat's perspective

## The rules, briefly

Four players, East starts. Standard Chinese mahjong play: draw, discard,
claim discards for chows (吃), pungs (碰) and kongs (杠). A hand wins with
four sets plus a pair — or through the special shapes above. 全求人 is a
big-fan hand: with four melds exposed, the last tile wins no matter what
it is, as long as you take it off a discard.

## Getting started

```bash
mix setup
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000), open a room, add AI
players, and start.

Requires Elixir and Erlang (`mix setup` installs everything else) and a
running PostgreSQL instance (dev defaults: `postgres:postgres@localhost`).

## Optional: LLM-powered AI

AI players work out of the box with the built-in rule engine. To give them
LLM-driven decision making (DeepSeek-compatible chat API):

```bash
export MAHJONG_AI_LLM=true
export DEEPSEEK_API_KEY=sk-...
# optional overrides
export MAHJONG_AI_MODEL=deepseek-chat
export MAHJONG_AI_BASE_URL=https://api.deepseek.com
```

## Testing

```bash
mix test
```

## Deployment

Production-ready for [Fly.io](https://fly.io): the repo ships with
`fly.toml`, a `Dockerfile`, and release config in `rel/`.

```bash
fly launch
fly deploy
```

## Acknowledgements

**Special thanks to [来夢来人](https://www.civillink.net/fsozai/majan.html)**
— the mahjong tile image assets ([麻雀の画像・素材 -
来夢来人](https://www.civillink.net/fsozai/majan.html)) used across the
game and this project's branding come from their wonderful free asset
collection.

Built with [Phoenix LiveView](https://www.phoenixframework.org/) and
[Tailwind CSS](https://tailwindcss.com/).
