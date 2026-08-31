---
name: 沪上牌馆 · Shanghai Deco Mahjong Parlor
description: A 1930s Shanghai mahjong parlor — lacquer black, jade, brass, bone — flattened to hairlines and geometry.
colors:
  lacquer-950: "#0a0e0c"
  lacquer-900: "#0e1411"
  lacquer-800: "#131b17"
  lacquer-700: "#1b2621"
  jade: "#3faf87"
  jade-bright: "#74d9b1"
  brass: "#c2a36b"
  brass-bright: "#ddc28d"
  brass-dim: "rgb(194 163 107 / 0.45)"
  brass-faint: "rgb(194 163 107 / 0.2)"
  bone: "#f5f1e6"
  bone-dim: "rgb(245 241 230 / 0.66)"
  bone-faint: "rgb(245 241 230 / 0.55)"
  vermilion: "#b5371f"
  ink: "#171b18"
  tile-face: "#fbfaf6"
typography:
  display:
    fontFamily: '"Poiret One", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", serif'
    fontSize: "2.1rem"
    fontWeight: 400
    lineHeight: 1.1
    letterSpacing: "0.3em"
  body:
    fontFamily: '"PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", ui-sans-serif, system-ui, sans-serif'
    fontSize: "15px"
    fontWeight: 400
  label:
    fontFamily: '"PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", ui-sans-serif, system-ui, sans-serif'
    fontSize: "0.78rem"
    fontWeight: 400
    letterSpacing: "0.14em"
rounded:
  xs: "2px"
  sm: "3px"
  md: "4px"
  lg: "6px"
  felt: "14px"
  pill: "9999px"
spacing:
  xs: "0.3rem"
  sm: "0.5rem"
  md: "0.75rem"
  lg: "1.1rem"
  page: "1.4rem"
components:
  link-brass:
    textColor: "{colors.brass}"
  act:
    backgroundColor: "linear-gradient(180deg, #fdfcf8 0%, #eee8d9 100%)"
    textColor: "{colors.ink}"
    rounded: "5px"
    padding: "0.55rem 0.95rem"
  act-primary:
    backgroundColor: "linear-gradient(180deg, #52c296 0%, #2e8b69 100%)"
    textColor: "{colors.lacquer-950}"
    rounded: "5px"
    padding: "0.55rem 0.95rem"
  act-pass:
    backgroundColor: "transparent"
    textColor: "{colors.bone-dim}"
    rounded: "5px"
    padding: "0.55rem 0.95rem"
  chip-brass:
    backgroundColor: "transparent"
    textColor: "{colors.bone-dim}"
    rounded: "{rounded.md}"
    padding: "0.42rem 0.8rem"
  room-row:
    backgroundColor: "{colors.lacquer-900}"
    textColor: "{colors.bone-dim}"
    rounded: "{rounded.lg}"
    padding: "1rem 1.4rem"
  tile:
    backgroundColor: "{colors.tile-face}"
    rounded: "{rounded.md}"
    width: "45px"
    height: "63px"
  wind-char:
    backgroundColor: "rgb(10 14 12 / 0.72)"
    textColor: "{colors.bone-dim}"
    rounded: "{rounded.sm}"
    size: "2.1rem"
---

# Design System: 沪上牌馆 · Shanghai Deco Mahjong Parlor

## Overview

**Creative North Star: "沪上牌馆 — a 1930s Shanghai mahjong parlor"**

The system renders one material world: a Shanghai art-deco parlor whose tables are lacquer black, whose markers are jade, whose line-work is brass, and whose tiles are bone. All of it is flattened to hairlines and geometry — a near-black ground, 1px metal lines, and exactly one piece of imagery: the tile faces themselves, GIF artwork that supplies all color and texture the interface deliberately refuses. The game table is dense at its edges (four seats, discard ponds, the waiting hand) and empty at its center, where a minimal deco sunburst floats in lacquer light; the hall is a sparse ledger of rooms under wide-spaced display type.

State is carried by material, not by color-wheel badges. Jade is the only living color — it marks whose turn it is, which actions exist, what is live — and it signals through brightness, scale, and glow alone. Brass is structure: every interactive surface is edged in a 1px brass hairline. Bone belongs to content — tile faces are the brightest whites on screen, and display numerals run full bone while running text recedes to bone-dim and bone-faint. Vermilion is ceremony: it appears only where someone wins.

Confirmed rejections: no casino green felt, no gold emboss, no texture or pattern fills, no decorative gradients. Gradients exist only as material light — the felt's radial sheen and the face of an engraved plate — never as ornament.

**Key Characteristics:**

- Lacquer ground in a four-step green-cast ramp (lacquer-950 `#0a0e0c` → lacquer-700 `#1b2621`)
- 1px brass hairlines carry every interactive surface; plates of record get a double hairline (border + offset outline)
- Jade marks only the living state — turn, available actions, live status text
- Tile faces are GIF artwork on an integer 5:7 grid and are the brightest whites on screen
- Poiret One display voice for Latin and numerals; PingFang SC system stack carries all Chinese
- Signature motion: a discard lands with a settle (rise, drop, shadow tightening); every other transition is ≤0.18s ease-out
- Whose turn it is must read from brightness alone: scale 1.14 + jade fill + glow

## Colors

A green-cast lacquer world lit by three precious materials — jade, brass, bone — and sealed by one ceremonial red; everything else is darkness graded by light.

### Primary
- **Jade · 玉** (`#3faf87`): the living state. Fills the turning wind character and the in-turn wind glyph, borders the in-turn seat plate, colors the live status word in the header ("东家出牌"), the primary action gradient's border, and text selection. The brighter jade-bright (`#74d9b1`) edges jade fills and colors the low-wall alarm.

### Secondary
- **Vermilion · 朱** (`#b5371f`): winning only. Fills the 胡 win seal on the result plate and colors the 胡 claim plate's text. Deliberately deep — it sits on lacquer without glowing — and never brightened or reused decoratively.

### Tertiary
- **Brass · 铜** (`#c2a36b`): the structural metal. Every interactive surface is framed by its 1px hairlines at two dilutions — brass-dim (`rgb(194 163 107 / 0.45)`) for resting edges and brass-faint (`rgb(194 163 107 / 0.2)`) for ambient or secondary frames. Full brass colors the compass rays, focus rings, and engraved plate titles; brass-bright (`#ddc28d`) is brass raised to speech — fans, scores, the low-wall count, hover states.

### Neutral
- **Lacquer 950 · 漆黑** (`#0a0e0c`): the room itself — body ground, deepest recess of the felt.
- **Lacquer 900** (`#0e1411`): raised lacquer furniture — header bar, opening and result plates, room rows.
- **Lacquer 800** (`#131b17`): the felt's lit center under the radial light; flash plate ground.
- **Lacquer 700** (`#1b2621`): nearest relief — filled seat slots, scrollbar thumb.
- **Lacquer veil**: plates floating over the felt are lacquer 950 at 60–90% alpha (`rgb(10 14 12 / α)`), deepening with importance — wind characters and seat plates 0.72, wall hub 0.82, waiting note 0.7, opening plate 0.9.
- **Bone · 骨** (`#f5f1e6`): content at full brightness — display numerals and titles only. Bone-dim (`rgb(245 241 230 / 0.66)`) is running text; bone-faint (`rgb(245 241 230 / 0.55)`) is the dimmest sanctioned text, for ambient labels.
- **Tile face · 骨白** (`#fbfaf6`): the tile body, a step brighter than bone — nothing else in the system may be this white.
- **Ink · 墨** (`#171b18`): text engraved on bone and jade surfaces (claim plates, turning wind character).

### Named Rules
**The Living Jade Rule.** Jade marks only the living state: the turning seat, available actions, live status. It never decorates a static surface, and the turn is legible from brightness and scale alone.

**The Vermilion Seal Rule.** Vermilion appears only on winning — the 胡 claim text and the result seal. Once per screen, never brightened.

**The Hairline Ledger Rule.** Every interactive surface is carried by a 1px brass hairline — dim at rest, never heavier than 1px. A faint brass outline offset 4–6px behind the border (the double hairline) marks plates of record: the felt, the opening plate, the result plate.

**The Bone Discipline Rule.** White is a brightness ladder: tile faces (`#fbfaf6`) are brightest; full bone is for display numerals and titles; bone-dim (0.66) carries running text; bone-faint (0.55) is the dimmest readable floor. Nothing brighter than bone-faint is spent on ambient labels; nothing dimmer than bone-faint carries text at all.

**The Brass Alarm Rule.** Alarms are material changes, not new colors: when the wall runs low (≤8 tiles), the wall count simply turns bone → brass-bright, at unchanged size and position.

*(Compatibility note: daisyUI is loaded with themes disabled except one compatibility theme whose "dark" and "light" palettes are identical lacquer/jade values with `--depth: 0; --noise: 0` — it exists only so core flash/base utilities stay on-palette. The system itself never reads daisyUI tokens.)*

## Typography

**Display Font:** Poiret One (weight 400 only, self-hosted OFL woff2 at `/fonts/poiret-one-latin.woff2`, `font-display: swap`) with PingFang SC fallback
**Body Font:** PingFang SC system stack ("PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", ui-sans-serif)
**Label/Mono Font:** none — labels use the body stack; all live numerals use Poiret One with `font-variant-numeric: tabular-nums`

**Character:** A thin, geometric art-deco Latin voice floats over a neutral, workmanlike Chinese sans — the bilingual sign of a Shanghai establishment: Latin for the marquee and the numbers, Chinese for everything that matters. The bundle also ships `I.MahjongCAN.otf` (unused; available, not part of the system).

### Hierarchy
- **Display** (400, 2.1rem hall title / 1.65rem result title / 1.8rem wall count / 1.35rem score, line-height 1.1): Poiret One renders Latin and digits; Chinese characters fall through the stack to PingFang SC automatically. Always letter-spaced wide (0.3–0.55em) and always with matching `text-indent` so centered spaced lines sit optically true.
- **Title** (400, 0.9rem, spacing 0.55em): engraved plate titles — "入 席" on the opening plate; also the brand word "MAHJONG 雀馆" (0.85rem, spacing 0.42em).
- **Body** (400, 15px base): all running copy, result meta, and seat names. No max line length is enforced; the hall column caps at 56rem.
- **Label** (400, 0.58–0.85rem, spacing 0.08–0.42em, no case transform — Chinese labels carry the tracking): guide words (0.78rem/0.14em), wall label (0.58rem/0.42em), seat plates (0.72rem/0.08em), brass links (0.78rem/0.22em).

### Named Rules
**The Display Split Rule.** Poiret One owns Latin letters and digits; Chinese stays in the PingFang stack. The split is achieved by stack order alone — never wrap languages in separate elements to switch fonts.

**The Spaced-Plate Rule.** Wide letter-spacing is the system's ornament: display and label lines carry 0.08–0.55em tracking, always paired with an equal `text-indent` when centered.

## Layout

One full-viewport table. `.table-shell` is a column filling `100svh`: a slim header (0.7rem 1.4rem padding, lacquer-900, faint hairline beneath) carries the brand seal, guide words, and the brass back-link; everything else is the felt — a single framed field (margin 1.1rem 1.4rem 1.4rem, min-height 600px, radius 14px) under a radial material light. Seats are absolutely positioned at the felt's inset corners (0.9rem): you sit at bottom, opponents map top/left/right relative to your wind — mapping computed server-side per viewer. The compass (15rem) hangs dead center, pointer-events: none. **Discard piles read chronologically from each seat's own perspective** — every pile is a 6-track grid whose first row/column sits nearest the table heart and fills toward the owner's hand: the top seat's pile rotates 180°, the left pile flips its column order (`direction: rtl`), the right pile mirrors vertically (`scaleY(-1)` with a compensating face matrix on the tile img). The hand lies along the bottom as 45×63 bone plates; the claim-action fan hovers over the felt's lower edge (bottom 9.2rem), the opening plate holds center felt during the waiting phase, and the result overlay dims the whole table at settle.

The hall is the same world at rest: one centered column (max-width 56rem, padding 2.4rem 1.5rem 3rem) — display title, one room-list of hairline rows, nothing else.

Responsive tiers are max-width steps, each preserving the tile GIFs' integer pixel grid:

- **≤820px** — felt margins tighten (0.8rem, min-height 520px), compass 11.5rem, wall hub 3.9rem, hand tiles 35×49 / discards 25×35 (sides 49×35 / 35×25), action line rises to bottom 7.4rem, brand Latin sub-label hidden, room rows drop the seat-slot column.
- **≤600px** — head and felt compress further (0.5rem margin, min-height 480px), compass 9rem, wind characters 1.7rem, hand tiles 25×35 / discards 20×28 (sides 35×25 / 25×20), hand gap 1px, seat gaps 0.3–0.4rem, action line at bottom 6rem with smaller plates, opening plate caps at 92% width.

Density doctrine: information crowds the edges so the lacquer center stays empty; the compass's emptiness is what makes the jade turn marker readable from across the room.

## Elevation & Depth

The world is flat at rest. Depth comes from three honest means — material light, grounding shadows, and lacquer veil — never from emboss, texture, or bevels. The felt is lit from within (radial gradient lacquer-800 → 900 → 950 plus an inset vignette, `inset 0 0 70px rgb(0 0 0 / 0.55)`); plates floating above it darken their ground (lacquer 950 at 0.7–0.9 alpha); physical objects (tiles, claim plates) get small grounding drops, and the one modal moment — the result plate — earns the system's only large shadow (`0 30px 80px rgb(0 0 0 / 0.6)`) behind the sole backdrop blur (2px).

### Shadow Vocabulary
- **Felt vignette** (`inset 0 0 70px rgb(0 0 0 / 0.55)`): the table's own light falloff; part of the material, not an effect.
- **Tile ground** (`0 2px 3px rgb(0 0 0 / 0.45), 0 6px 12px rgb(0 0 0 / 0.22)`): under every bone tile at rest; deepens on hover (`0 2px 3px 0.45, 0 14px 20px 0.5`).
- **Plate edge** (`0 3px 0 rgb(0 0 0 / 0.5), 0 7px 16px rgb(0 0 0 / 0.32)`): the claim plates' hard 3px under-edge reads as thickness — engraved bone resting on felt, not floating.
- **Plate of record** (`0 30px 80px rgb(0 0 0 / 0.6)`): result plate only.
- **Hover lift** (`0 10px 26px rgb(0 0 0 / 0.35)`): room rows on hover, paired with a 1px rise.
- **Living glow** (`0 0 18px rgb(63 175 135 / 0.35)`, seat plate `0 0 14px rgb(63 175 135 / 0.22)`): jade light around the turning wind character and in-turn seat plate. Glows are state, never decoration — only jade may glow.

### Named Rules
**Brightness Is State.** The turn reads through luminance alone: jade fill, 1.14 scale, glow — no arrows, no badges, no color-wheel indicators.

**Material Light, Not Emboss.** The only gradients are the felt's radial sheen and the face gradients of physical plates (bone `#fdfcf8→#eee8d9`, jade `#52c296→#2e8b69`). No emboss, no inner bevels, no textured fills.

## Shapes

The form language is hairline geometry. Corners are nearly square and quietly ranked: 2px on glyph boxes, 3px on brand seal and wind characters, 4px on tiles / seat plates / chips / seals, 5px on claim plates, 6px on plates of record / room rows / identicons, 14px on the felt alone, and true circles (`9999px`) only for hubs — the wall hub, waiting-note pill, seat slots. Borders are always 1px; the double hairline (border + faint outline offset 4–6px) frames the felt (offset 4px), opening plate (5px), and result plate (6px). Deco geometry appears exactly once, in the compass: a sunburst of 24 rays at 15° (major rays at the cardinals) inside two thin rings. Dashed brass hairlines mean "awaiting" — empty seat slots and the hall's empty state. The claim plates' hard 3px under-edge is the only fake thickness in the system.

### Named Rules
**The Dashed Threshold Rule.** A dashed brass hairline marks an empty threshold — a seat not yet taken, a hall with no games. It never marks a state, only an invitation.

## Components

### Brass link (`.link-brass`)
The quiet way out. Brass text (0.78rem, spacing 0.22em) with an invisible 1px underline; on hover the text lifts to brass-bright and the underline surfaces at brass-dim (0.15s ease-out).

### Claim plates — 碰 / 杠 / 吃 / 胡 / 过 (`.act` + variants)
The signature button: an engraved bone plate. Bone face gradient (`#fdfcf8→#eee8d9`), ink text (0.95rem, weight 600, spacing 0.06em), brass-dim border, 5px radius, `0.55rem 0.95rem` padding, hard 3px under-edge. Hover lifts 2px with a deeper shadow; active presses 1px into the felt. Variants: **claim-primary** (碰/杠) bolder ink; **win** (胡) vermilion text, weight 700; **pass** (过) a ghost — transparent, brass-faint border, bone-dim text, no shadow, no lift. **Primary jade plate** (`.act-primary`, used for 开局 / 入座 / 开新局 / 再来一局): jade face gradient (`#52c296→#2e8b69`), jade-bright border, lacquer-950 text, weight 700. Keyboard focus anywhere is the brass hairline itself: `:focus-visible` outline 1px brass, offset 2px.

### Brass chips (`.chip-brass`)
The +AI seats. Transparent, faint brass hairline, 4px radius, bone-dim text (0.8rem). Hover: border to brass-dim, text to bone, 1px rise (0.15s ease-out).

### Compass — wind characters & wall hub (`.compass`, `.wind-char`, `.wall-hub`)
A 15rem deco sunburst: brass rays at 0.26 opacity (major cardinals 0.5), two rings at 0.22, all `pointer-events: none`. Wind characters are 2.1rem lacquer-veil squares (3px radius, hairline, bone-dim); the turning seat fills jade with a jade-bright border, lacquer-950 bold glyph, 1.14 scale, and an 18px jade glow (0.18s ease-out). The wall hub is a 4.6rem double-ringed circle holding the wall count — Poiret One 1.8rem, tabular-nums, full bone; label "余牌" beneath at 0.58rem/0.42em bone-faint. At ≤8 tiles the count turns brass-bright.

### Tiles (`.tile`, `.tile-hand`, `.tile-discard`, `.tile-drawn`)
The visual mass of the system. Bone body (`#fbfaf6`), 4px radius, near-black border (`rgb(0 0 0 / 0.35)`), tile-ground shadow; the face is always the 80×112 GIF artwork (`characters/dots/bamboos_N.gif`, `hidden_tile.gif`) at aspect-exact integer sizes — hand 45×63, discard 30×42 desktop, scaled down at 820px/600px per Layout; side seats swap axes with ±90° image rotation, top rotates 180°. A just-drawn tile leaves the hand: lifted 5px and separated by a 10px gap. Your own hand is interactive — cursor pointer, hover lifts 9px with a deepening shadow (0.16s ease-out). Concealed hands render `hidden_tile.gif` until reveal or game end.

### The settle (`.discards .tile:last-child`)
The signature moment: each new discard lands with `tile-settle` (0.3s, `cubic-bezier(0.2, 0.7, 0.3, 1)`) — rises in at −16px and 1.07 scale, drops through a 1.5px overshoot, and settles as the shadow tightens. No other animation in the system is longer than 0.18s.

### Seat plates (`.seat-id`) & waiting note (`.waiting-note`)
The nameplate: lacquer-veil chip (0.72 alpha), faint hairline, 4px radius, 0.72rem bone-dim, holding a 1.15rem wind-glyph box (brass glyph), the player label, and the 庄 dealer tag. In-turn: jade border, full-bone text, jade-filled glyph, 14px jade glow. Spectator rows reuse the plate at static position (`.seat-waiting`). The waiting note is a centered veil pill (faint hairline, 9999px radius, 0.78rem bone-dim) at the action line: "等待其他玩家行动…".

### Opening plate (`.opening-plate`)
The threshold of the table: a centered veil plate (0.9 alpha), double hairline at offset 5px, 6px radius, brass "入 席" title (0.9rem/0.55em), a jade primary row (入座 / 开局) and a row of brass +AI chips.

### Result seals (`.seal-win`, `.seal-draw`)
The ceremony. Win: a 3.6rem vermilion square stamped at −4° with 胡 in warm bone (`#f7ead9`, 1.55rem, weight 700) and an inset 2px light ring — the system's only stamp and its only vermilion surface. Draw (荒庄): the same square as a hairline outline, bone-draw glyph, no fill. Around them: Poiret result title (1.65rem/0.32em), meta at 0.8rem, fans and score in brass-bright (score tabular Poiret 1.35rem), and a jade 再来一局 plate — all on a lacquer-900 plate of record under the veil overlay (66% black + 2px blur).

### Room rows & seat slots (`.room-row`, `.seat-slot`)
The hall's ledger line: a 4-part grid (identicon · name · slots · action) on lacquer-900, faint hairline, 6px radius, `1rem 1.4rem` padding; hover lifts 1px, borders to brass-dim, gains the 10px/26px shadow. Room names are tabular Poiret-adjacent digits (body font, `tabular-nums`, 0.85rem/0.1em). Seat slots are 1.55rem circles — dashed faint brass when empty, solid hairline over lacquer-700 when filled (a brass dot when no identicon). The empty hall is a dashed faint-brass box with wide-spaced bone-faint text.

### Identicons (`.ident`)
Minidenticon SVGs (CDN module) are the only multicolor elements; the system frames them, never recolors them — 2.5rem, faint hairline, 6px radius (round variant for avatars), on `rgb(255 255 255 / 0.04)`.

### Flash (`.flash-group`) & brand seal (`.brand-seal`)
Flashes are fixed top-center veil plates on lacquer-800: hairline, 4px radius, full-bone text, 12px/30px shadow. The brand seal is a 2.1rem square: hairline frame with a double inset ring (2.5px lacquer-900, then faint brass), jade 雀 in Poiret One — the world's mark, always `aria-hidden`, always the same in hall and game.

## Do's and Don'ts

### Do:
- **Do** carry every interactive surface on a 1px brass hairline (brass-dim at rest); give plates of record — felt, opening plate, result plate — the double hairline (faint outline offset 4–6px).
- **Do** keep all ornament at 1px geometry: hairlines, thin rings, the compass sunburst. Brightness, scale, and spacing do the rest.
- **Do** keep tile faces on the integer 5:7 grid of the 80×112 GIFs — 45×63 / 30×42 desktop, 35×49 / 25×35 at ≤820px, 25×35 / 20×28 at ≤600px — and swap axes with ±90° rotations on the side seats.
- **Do** mark the living state with jade only, and let brightness read it: jade fill + 1.14 scale + glow for the turning wind character; jade borders for the in-turn seat plate.
- **Do** set every live numeral in Poiret One with `font-variant-numeric: tabular-nums` (wall count, score), and pair wide letter-spacing with equal `text-indent` on centered lines.
- **Do** let new discards land with the settle (`tile-settle`, 0.3s, `cubic-bezier(0.2, 0.7, 0.3, 1)`); keep every other transition ≤0.18s ease-out.
- **Do** raise alarms by material change — bone → brass-bright at ≤8 wall tiles — and dim text no further than bone-faint (0.55).

### Don't:
- **Don't** import casino mahjong defaults: no green felt, no gold emboss, no texture or pattern fills, no bevels — depth is material light and grounding shadows only.
- **Don't** decorate with gradients; the only sanctioned gradients are the felt's radial light and the face gradients of physical plates (bone `#fdfcf8→#eee8d9`, jade `#52c296→#2e8b69`).
- **Don't** spend jade on static decoration or vermilion anywhere except winning (胡 claim text, win seal).
- **Don't** put full-brightness bone on running text (use bone-dim 0.66 / bone-faint 0.55) and never let any UI surface be brighter than the tile faces (`#fbfaf6`).
- **Don't** rename or hand-write the server-minted class hooks — `seat-bottom/top/left/right/waiting`, `wind-char`/`wind-char-turn`, and the action-button classes are generated in `game_live.ex` (`seat_class/2`, `wind_chip_class/2`, `action_buttons/1`); CSS and templates must consume them as-is.
- **Don't** replace, recolor, or non-uniformly scale the tile-face GIFs (`priv/static/images/{characters,dots,bamboos}_{1..9}.gif`, `hidden_tile.gif`) — they are the only sanctioned face artwork and the system's only imagery.
