# Assets

How the mark and the social card are drawn, rendered and published.

| File | Is |
| --- | --- |
| `assets/logo.svg` | the source of the mark |
| `assets/social.svg` | the source of the 1280×640 social preview card; it carries its own copy of the mark's paths |
| `assets/*.png` | rendered from the SVGs; never edited by hand |

## Drawing

- One accent colour, `#d97757` — Claude Code terracotta, the same value as the README's plugin badge — on no background, so both read on a light or a dark page.
- The six arc segments are the six phases.
- The node at twelve o'clock is one iteration on the cycle.
- The three centre rules are a spec.
- Changing the phase count means redrawing the ring, in the logo and in the card.

## Rendering

Render with headless Chrome: `--screenshot --window-size=1280,640`. Do not use `qlmanage`: it scales a thumbnail to fill its square, which makes every margin measurement wrong.

## Publishing

GitHub exposes no API for the social preview: `assets/social.png` is uploaded by hand under Settings › General.
