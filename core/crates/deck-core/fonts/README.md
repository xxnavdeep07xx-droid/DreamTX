# Font metrics (generated)

This directory no longer embeds the DejaVu TTFs (~2.16 MB). The layout
solver's font metrics ship as a pre-generated static table instead:
`../src/font_metrics.rs`, produced by `../../..//scripts/gen_font_table.py`.

- `measure()` and `wrap()` return bit-identical widths to the old embedded
  TTF + ttf-parser path (the table stores each cmap-mapped codepoint's
  advance width in font units; `adv / units_per_em * size` is exactly what
  the parser computed).
- Regenerate with a system fonts-dejavu installation:
  `python3 scripts/gen_font_table.py <dir with the 4 DejaVu ttf files>`
  (requires Python `fontTools`).

The fonts themselves (DejaVu, free license — Bitstream Vera-derived,
redistribution + embedding permitted) are not needed at build time
anymore; `ttf-parser` was removed from the dependencies.
