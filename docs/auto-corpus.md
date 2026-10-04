# Auto tuning corpus

The photos Suggested settings ("Auto") were tuned on ([`auto-tuning.md`](auto-tuning.md)): 69
in all. Only the six regression photos are committed (`Tests/Corpus`); this file records where
each came from and under which licence, so the corpus can be rebuilt. Wikimedia, Unsplash and
most image hosts are blocked from the build machines, so every new photo comes from a public
GitHub repository (cloned with `git`, which the proxy allows) and is pinned to the commit it was
fetched at.

Preparation (`/tmp/pbn-w1b/prep.py` during tuning): EXIF orientation applied, converted to
RGB, reduced with Lanczos to at most 2048 px on the long side (the size the app keeps a photo
at, `ArtworkStore.sourceMaxPixelSize`), written as PPM. Smaller photos are used as they are.

## Existing corpus (34)

| Photos | Source | Licence |
| --- | --- | --- |
| barn, espresso, hibiscus, lighthouse, parrots, regatta | `Tests/Corpus/*.jpg` (the regression gate's and the benchmark's photos, never shipped; JPEG copies of Kodak 22, scikit-image coffee, Kodak 07, Kodak 21, Kodak 23, Kodak 09) | as their sources below; credits in `Tests/Corpus/README.md`. The app never offers or credits them (no `library.json` record) |
| kodim01 … kodim24 (768 × 512) | `https://raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite/master/PhotoCD_PCD0992/<n>.png` | Kodak released the suite for unrestricted use |
| astronaut, chelsea, coffee, rocket | scikit-image `skimage/data` | astronaut and rocket: public domain (NASA); chelsea and coffee: CC0 (scikit-image's data licence list) |

## Added for the tuning (35)

Hand-written hints (faces, cats and dogs, normalized rects) lived in `/tmp/pbn-w1b/hints/` (not
committed) for grace-hopper, portrait-tunnel, portrait-dress, dog, chelsea, astronaut, kodim04,
kodim12, kodim15 and kodim18. Only cats and dogs get animal rects, as `VNRecognizeAnimalsRequest`
reports nothing else.

Repositories (all CC0 1.0 unless noted):

- **W** = `waitblock/wikimedia-commons-fp-set` @ `3f73d1e`, CC0 1.0 (`LICENSE.txt`; "100
  photographs that have reached featured picture status on Wikimedia Commons and are also in
  the public domain"; each photo's Commons page is listed in the repository's `index.html`).
  URL: `https://raw.githubusercontent.com/waitblock/wikimedia-commons-fp-set/3f73d1e93f50df996c6f1b4c66f8bd6d8fffee10/images/<nn>.jpg`
- **F** = `peterducai/free_art` @ `90f6d6b`, CC0 1.0 (`LICENSE`, README "released under CC0
  (public domain)"). URL: `https://raw.githubusercontent.com/peterducai/free_art/90f6d6b92305f83dde7e70ba684c1d9fcef61ecb/<path>`
- **I** = `ivanfonin/cc0-photos` @ `22be2e2`, CC0 (README: "my photos which I share under
  Creative Commons Zero"). URL: `https://raw.githubusercontent.com/ivanfonin/cc0-photos/22be2e285db50193362e8ed06712b4146e714f6c/<file>`
- **L** = `LoveBodhi/PhotoWall` @ `75699f8`, CC0 1.0 (`LICENSE`, README waiver). URL:
  `https://raw.githubusercontent.com/LoveBodhi/PhotoWall/75699f8c1cb564d613eaab46e7f7dfad4f391352/001/<file>`
- **M** = `matplotlib/matplotlib` @ `825479c`, `lib/matplotlib/mpl-data/sample_data/grace_hopper.jpg`:
  public domain (official US Navy photograph).

| Name | Category | Source | Original file (Commons title for W) | Prepared size |
| --- | --- | --- | --- | --- |
| portrait-tunnel | portrait | I | `cc0-photo-1.jpg` | 1560 × 910 |
| portrait-dress | portrait | I | `cc0-photo-4.jpg` | 1546 × 2048 |
| grace-hopper | portrait | M | `grace_hopper.jpg` | 512 × 600 |
| dog | pet | F | `other/dog.jpg` | 525 × 900 |
| guineapig | pet | F | `4k/peruvian_guineapig.jpg` | 2048 × 1366 |
| tiger-snow | animal, snow | W 37 | Panthera_tigris_altaica_13_-_Buffalo_Zoo.jpg | 2048 × 1388 |
| red-panda | animal | W 61 | Red_Panda_(24986761703).jpg | 2048 × 1356 |
| lynx | animal | W 76 | Lynx_lynx-4.jpeg | 2048 × 1365 |
| hedgehog | animal, texture | W 64 | Erinaceus_roumanicus_2020_G2.jpg | 2048 × 1463 |
| mongoose | animal | W 15 | Mongoose_pile.jpg | 2048 × 1720 |
| goose | animal | W 26 | Graugans_Anser_Anser.jpg | 2048 × 1360 |
| night-moon | night | F | `other/night_lamp.jpg` | 2048 × 1365 |
| frontenac-night | night, architecture | W 54 | Château_Frontenac_at_night,_Quebec_City,_Canada_2.jpg | 2048 × 1383 |
| light-trails | night | W 39 | Light_trails_near_Paris,_27_May_2022.jpg | 2048 × 1152 |
| aurora | night | W 91 | Polarlicht_2.jpg | 2048 × 1334 |
| paris-night-street | night, people | W 04 | Restaurants,_Place_du_Tertre,_Paris_30_September_2019.jpg | 2048 × 1152 |
| rome-dusk | dusk, architecture | W 98 | Sant'Angelo_bridge,_dusk,_Rome,_Italy.jpg | 2048 × 1030 |
| snowy-road | snow | W 75 | Snowy_road_Sosonka_2013_G1.jpg | 2048 × 1365 |
| bernina-snow | snow | W 47 | Berninabahn_zwischen_Lagalb_und_Ospizio_Bernina_im_Winter.jpg | 2048 × 1261 |
| snow-forest | snow, near-monochrome | F | `other/snowforest.jpg` | 2048 × 1364 |
| cake | food | W 12 | Piece_of_chocolate_cake_on_a_white_plate_decorated_with_chocolate_sauce.jpg | 2048 × 1393 |
| butternut | food | W 59 | Cucurbita_moschata_Butternut_2012_G2.jpg | 2048 × 1365 |
| papayas | food, texture | W 87 | Mamões.jpg | 2048 × 1536 |
| borsen | architecture | W 69 | Børsen_Copenhagen_Denmark.jpg | 2048 × 1480 |
| bamberg | architecture | W 33 | Bamberg_Altes_Rathaus_BW_1.jpeg | 1365 × 2048 |
| mespelbrunn | architecture | W 92 | Wasserschloss_Mespelbrunn,_6.jpg | 2048 × 1315 |
| pont-royal | architecture, dusk | W 93 | Pont_Royal_and_Musée_d'Orsay,_Paris_10_July_2020.jpg | 2048 × 1156 |
| golden-church | architecture, low light | F | `4k/golden_church.jpg` | 2048 × 1152 |
| smoke-haze | haze, low contrast | F | `other/smoke_sun_factories.jpg` | 1152 × 2048 |
| clouds | low contrast | F | `4k/cloudy_middle.jpg` | 2048 × 1256 |
| mountain-haze | haze, snow | W 51 | Kuznetsk_Alatau_1.jpg | 2048 × 1255 |
| palm-fronds | foliage texture | I | `cc0-photo-14.JPG` | 1792 × 2048 |
| tulips | flowers, texture | L | `trello7246398987342814819.jpg` | 2048 × 1536 |
| waterfall | landscape, texture | L | `trello8105715111484255228.jpg` | 2048 × 1536 |
| windsurfer | sport, near-monochrome | W 88 | Robby_Naish_a-1.jpg | 2048 × 1365 |

## Gaps

- **Fog**: no foggy photo in any repository reachable from here. The low-contrast slot is
  covered by haze and smoke (smoke-haze, mountain-haze) and an overcast sky (clouds); a
  true fog scene (soft, nearly uniform, low chroma) is untested.
- **Portraits**: three adult portraits at real size (two at about 1.5–3 MP, one 0.3 MP) plus
  the Kodak and scikit-image faces at 768 px or less; no close-up 12 MP face, where skin tone
  steps matter most.
- **Pets**: one dog (0.5 MP), one cat (scikit-image, 0.1 MP) and a guinea pig; no large cat
  or dog photo was found under a free licence on the reachable hosts.
- Importance maps: on Linux every photo uses the pipeline's fallback importance (Vision's
  saliency, faces and foreground are app-only), so the tuning saw the fallback's flatter
  weighting; the face rule was exercised through the hand-written hints.
