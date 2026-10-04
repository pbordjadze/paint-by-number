# Corpus

Six photographs the quality regression gate and the pipeline benchmark run on, pinned by
name. They are test data: never bundled with the app, never offered as pictures, never
credited in it. The app's picture library is `App/PaintByNumber/Resources/Samples/`.

- `tools/regression.py` (`SAMPLE_NAMES`) generates each photo in every regime and checks the
  results against `tools/baseline/regression.json` and `tools/baseline/auto.json`.
- The Pipeline benchmark step of `.github/workflows/ci.yml` times `pbn bench` on the same six.
- `tools/baseline/lines/<name>-contours.png` and `-drawing.png` are the edge maps the book
  regime reads, made from these files and as large as they are.
- `Tests/PaintCoreTests/Fixtures/auto-parrots-draft.ppm` is `parrots.jpg` at the draft size.

The baselines are metrics of these exact bytes: replacing a photo moves every one of them
(`tools/regression.py --update`, and new maps), so add a photo rather than swap one.

## Provenance and credit

| File | Size | What | Source | Credit and licence |
| --- | --- | --- | --- | --- |
| `barn.jpg` | 768 × 512 | a red barn and its reflection in a pond | Kodak 22 (`kodim22`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company |
| `espresso.jpg` | 600 × 400 | a coffee cup | scikit-image `coffee` (`skimage/data/coffee.png`) | Rachel Michetti, CC0 1.0 (scikit-image: "No copyright restrictions. CC0 by the photographer") |
| `hibiscus.jpg` | 768 × 512 | a hibiscus before a shuttered window | Kodak 07 (`kodim07`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company |
| `lighthouse.jpg` | 768 × 512 | a lighthouse | Kodak 21 (`kodim21`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company |
| `parrots.jpg` | 768 × 512 | two macaws | Kodak 23 (`kodim23`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company |
| `regatta.jpg` | 512 × 768 | sailboats under spinnakers | Kodak 09 (`kodim09`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company |

The Kodak suite is 24 lossless 768 × 512 images that Eastman Kodak Company released for
unrestricted use. The copies came from
`https://raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite/master/PhotoCD_PCD0992/<n>.png`
and were re-encoded as JPEG at their own size (against the PNGs, a mean difference of
1.4–2.1 of 255 per channel, `coffee` included). The rest of the Kodak suite belongs to Auto's
tuning corpus, which is not committed; `docs/auto-corpus.md` records where each of its photos
came from.
