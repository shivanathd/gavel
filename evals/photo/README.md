# Photo eval

49 labelled cases over 43 distinct images, through the six photo decisions, run live: `Gavel.run` in a scratch org against `jev-1.14.0`.
Each case has a photo, the record text (claim, product, job or product name) and the expected answer for each Noul.

- **Generated (`gen/`)**: 21 images from `gpt-image-2.5-flare`, prompts in `gen/prompts.json`. Generated in matched
  pairs (the same mug cracked and intact, the catalog lamp and a different lamp) so the label is known by construction.
- **Real (Wikimedia Commons)**: 22 photos, downloaded at run time by `run.py fetch` and not stored here. Each case
  names the file, its licence and its page. Commons search results are noisy, so each photo was checked by hand.

Run it (Python 3 with Pillow) against an org set up as in `.claude/skills/verify/SKILL.md` (released packages, egress on, key set):

```bash
python3 evals/photo/run.py fetch records upload run score
```

`score` prints every miss and how each Box was handled: kept or dropped, right or wrong, where "right" means kept
exactly when the gate Noul's label says the thing is there.

## Results

| Build | Labels right | Confidently wrong | Boxes handled right |
|---|---|---|---|
| 1.2.0 (box confidence only) | 93 / 94 | 1 | 21 / 26 |
| 1.3.0 (box gated by its Noul, ADR 0019), installed from the release, 2026-10-19 | 93 / 94 | 1 | 26 / 26 |

The one miss: a phone screenshot of a shop page was read as "shows a physical product" (0.89). The same run said it
is not the catalog product (0.11), so the case still came out as the wrong item. The five dropped boxes were correct:
the damage on three real cracked phones (box confidence 0.31 to 0.49) and the totals on two legible receipts (0.20,
0.44). That is the evidence for [ADR 0019](../../docs/adr/0019-box-gated-by-a-noul.md).

All of these are drawn or staged photos, or public ones. Accuracy on your own customers' photos still needs Shadow.
