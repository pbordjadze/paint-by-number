# Drawings

Eighteen line drawings, each with a simulated phone photo of it on paper, that `tools/drawings/convert.py`
runs through `pbn drawing` (Start from a Drawing: root `CLAUDE.md` › Map, `DrawingScan`). They are test
data: never bundled with the app, never offered as pictures, never credited in it.

- `<name>.png` or `<name>.jpg`: the drawing, at most 1400 px on its long side, as its source gave it
  (the openclipart SVGs rasterized at 2000 px on white, then shrunk).
- `<name>-photo.jpg`: `tools/drawings/phone_photo.py <name> --seed <seed> --long 1800`: the sheet on
  a table, askew, unevenly lit, textured, blurred, noisy and JPEG-compressed. The seed is the one in
  the table below, so the photo is reproducible from the drawing.

## What each one tests

| Name | Seed | What it is | What it tests |
| --- | --- | --- | --- |
| `octopus` | 15 | a baby octopus, thick outline | a child's page: thick lines, few areas |
| `sheep` | 11 | a cartoon sheep | thick lines, a solid black shadow, small eyes |
| `bunny` | 14 | a lop-eared bunny | a coloring page with eyes, whiskers, fur ticks |
| `llama` | 13 | a llama with fur tufts | short texture strokes along an outline |
| `caribou` | 12 | two leaping caribou | small closed shapes (hooves, eyes), two figures |
| `cat` | 17 | a cat face with stripes and whiskers | open strokes (whiskers), stripes as areas |
| `artichoke` | 18 | an engraved artichoke | engraved hatching, a dense figure |
| `manticore` | 19 | a 1678 manticore, traced | fur, mane, heavy hatching, a shadowed ground |
| `barons-prayer` | 20 | Beardsley, The Baron's Prayer | folds, dots, fine hatching, a frame |
| `billet-doux` | 21 | Beardsley, The Billet-Doux | hair, lace, wallpaper pattern, a frame |
| `new-star` | 22 | Beardsley, The New Star | a solid black silhouette with curls |
| `leech-sketch` | 24 | Leech, a pencil sketch with a caption | faint pencil, broken lines, handwriting |
| `beadle` | 25 | Cruikshank, an ink caricature with a caption | sketchy ink on grey paper, handwriting |
| `sancho` | 26 | Doré, Sancho Panza | crosshatching, a signature, a fold in the sheet |
| `contents` | 27 | Greenaway, a contents page | outline lettering, silhouettes, typeset text |
| `wall` | 29 | Greenaway, two children on a wall | a ruled border, a vignette, verse |
| `lear-captions` | 30 | Lear, two drawings with his captions | handwritten captions, a typeset title |
| `kangaroo` | 32 | Lear, the duck and the kangaroo | a small drawing on a page of text |

## Provenance and licence

Evidence was read on October 30, 2026, on the source's own page or API. Openclipart's share
page says every upload is released under CC0 1.0; the Internet Archive items are marked
`possible-copyright-status: NOT_IN_COPYRIGHT`; the Cleveland Museum of Art's open-access API
gives `share_license_status: CC0`; Old Book Illustrations names the Internet Archive scan of the
1896 book as its source, and Beardsley died in 1898.

| File | Artist (dates) | Work / date | Source page | Licence evidence |
| --- | --- | --- | --- | --- |
| `octopus.png` | Deadly44 | Baby Octopus Coloring Page, 2016 | https://openclipart.org/detail/245072/baby-octopus-coloring-page | openclipart, CC0 1.0 |
| `sheep.png` | SeriousTux | Eid Sheep, 2013 | https://openclipart.org/detail/175473/eid-sheep-1 | openclipart, CC0 1.0 |
| `bunny.png` | molumen | Bunny Outline, 2015 | https://openclipart.org/detail/213759/bunny-outline | openclipart, CC0 1.0 |
| `llama.png` | frankes | Llama Lineart, 2015 | https://openclipart.org/detail/213394/llama-lineart | openclipart, CC0 1.0 |
| `caribou.png` | pianoBrad | Caribou Coloring Page, 2013 | https://openclipart.org/detail/187782/caribou-coloring-page | openclipart, CC0 1.0 |
| `cat.png` | gammillian | Cat Line Art, 2010 | https://openclipart.org/detail/75883/cat-line-art | openclipart, CC0 1.0 |
| `artichoke.png` | GangandInfographie, tracing a plate of the Iconographic Encyclopedia (1851) | Engraving of an Artichoke, 2017 | https://openclipart.org/detail/275788/engraving-of-an-artichoke | openclipart, CC0 1.0 |
| `manticore.png` | AdamStanislav, tracing Joannes Johnstonus (d. 1675), 1678 | Mantichora, 2017 | https://openclipart.org/detail/292196/mantichora | openclipart, CC0 1.0 |
| `barons-prayer.jpg` | Aubrey Beardsley (1872–1898) | Pope, *The Rape of the Lock*, 1896: The Baron's Prayer | https://www.oldbookillustrations.com/illustrations/barons-prayer/ | published 1896, artist d. 1898; scan from the Internet Archive |
| `billet-doux.jpg` | Aubrey Beardsley (1872–1898) | *The Rape of the Lock*, 1896: The Billet-Doux | https://www.oldbookillustrations.com/illustrations/billet-doux/ | as above |
| `new-star.jpg` | Aubrey Beardsley (1872–1898) | *The Rape of the Lock*, 1896: The New Star | https://www.oldbookillustrations.com/illustrations/new-star/ | as above |
| `leech-sketch.jpg` | John Leech (1817–1864) | Sketch for "Mrs. Pottles Can't Abide a Crowd", 1856 | https://clevelandart.org/art/1924.1004 | Cleveland Museum of Art, CC0 |
| `beadle.jpg` | George Cruikshank (1792–1878) | The Beadle, c. 1805–78 | https://clevelandart.org/art/1946.445 | Cleveland Museum of Art, CC0 |
| `sancho.jpg` | Gustave Doré (1832–1883) | Sancho Panza, c. 1863 | https://clevelandart.org/art/2018.1066 | Cleveland Museum of Art, CC0 |
| `contents.jpg` | Kate Greenaway (1846–1901), engraved by Edmund Evans | *Under the Window*, 1878, contents page | https://archive.org/details/underwindowpictv00greerich/page/n10 | Internet Archive, not in copyright |
| `wall.jpg` | Kate Greenaway (1846–1901), engraved by Edmund Evans | *Under the Window*, 1878, p. 51 | https://archive.org/details/underwindowpictv00greerich/page/n54 | Internet Archive, not in copyright |
| `lear-captions.jpg` | Edward Lear (1812–1888) | *The Complete Nonsense Book*, 1912 ed., p. 37 | https://archive.org/details/completenonsense00lear/page/n50 | Internet Archive, not in copyright |
| `kangaroo.jpg` | Edward Lear (1812–1888) | *The Complete Nonsense Book*, 1912 ed., p. 127 | https://archive.org/details/completenonsense00lear/page/n140 | Internet Archive, not in copyright |
