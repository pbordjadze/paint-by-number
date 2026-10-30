# Evaluation set

The photos the template algorithm is judged on (painting-company row 188): what people paint
(pets, faces, couples, landscapes, flowers, food, buildings) and a few hard ones (low light, busy
scenes, small subjects). `tools/scene_eval.py` generates every one with the color method and the
scene method, measures both and lays them side by side; `manifest.json` lists them with a
category and, for the ones that live elsewhere in the repository (`Tests/Corpus`, the app's
picture library), their path. They are test data: never bundled with the app, never offered as
pictures, never credited in it.

Beside each photo, `scenes/<id>/` holds the Linux stand-in for what Vision finds on the device
(`tools/scene_standin.py`: `scene.json`, `subject.pgm`, `saliency.pgm`, `eyes.json`; its
`--preview` pictures are not committed) and `maps/<id>-contours.png` and `-drawing.png` the edge
maps the coloring book draws from, made as `tools/baseline/lines` were by `tools/evalset_maps.py`
(the two converters' `--map` on the photo at most 1152 px on the long side, the app's
`EdgeDetector.maximumLongSide`; 14 MB for the set).
The stand-in is checked against Vision on CI (`SceneStandInTests`).

The photos were taken at their published size (the Openverse ones at the 1024-px rendition its
record links), re-encoded as JPEG (quality 92, no chroma subsampling); the scanned slides had
their film frame cropped.

## Provenance and credit

| File | Size | What | Category | Source | Credit and licence |
| --- | --- | --- | --- | --- | --- |
| `kodim04.jpg` | 512 × 768 | a woman in a red hat | face | Kodak 04 (`kodim04`) | Kodak Lossless True Color Image Suite, Eastman Kodak Company, released for unrestricted use |
| `kodim15.jpg` | 768 × 512 | a girl with face paint | face | Kodak 15 | Kodak suite, as above |
| `kodim12.jpg` | 768 × 512 | a couple wading on a beach | couple, small subjects | Kodak 12 | Kodak suite, as above |
| `kodim13.jpg` | 768 × 512 | a mountain stream | landscape | Kodak 13 | Kodak suite, as above |
| `kodim16.jpg` | 768 × 512 | an island under clouds | landscape | Kodak 16 | Kodak suite, as above |
| `kodim08.jpg` | 768 × 512 | half-timbered houses | building, busy | Kodak 08 | Kodak suite, as above |
| `kodim24.jpg` | 768 × 512 | a painted Alpine house | building | Kodak 24 | Kodak suite, as above |
| `kodim05.jpg` | 768 × 512 | a row of motocross bikes | busy | Kodak 05 | Kodak suite, as above |
| `kodim20.jpg` | 768 × 512 | a parked fighter plane | small subject | Kodak 20 | Kodak suite, as above |
| `astronaut.jpg` | 512 × 512 | Eileen Collins, astronaut portrait | face | NASA, via scikit-image `astronaut` | NASA, public domain |
| `sailor-and-girl.jpg` | 975 × 782 | a sailor and a girl at the Tomb of the Unknown Soldier, 1943 | couple | Library of Congress, FSA/OWI color, LC-DIG-fsac-1a34519 | Library of Congress, Prints & Photographs Division; public domain (no known restrictions) |
| `rail-yard-night.jpg` | 961 × 733 | a rail yard at night, Kansas City, 1943 | low light | Library of Congress, LC-DIG-fsac-1a34717 | as above |
| `shepherd-horse-dog.jpg` | 731 × 959 | a shepherd on horseback with his dog, Montana, 1942 | pet, landscape | Library of Congress, LC-DIG-fsac-1a35022 | as above |
| `school-children.jpg` | 883 × 668 | school children singing, Pie Town, 1940 | faces, low light, busy | Library of Congress, LC-DIG-fsac-1a34152 | as above |
| `coast-artilleryman.jpg` | 649 × 929 | a coastal-defense soldier at a field telephone, 1942 | face | Library of Congress, LC-DIG-fsac-1a35087 | as above |
| `german-shepherd.jpg` | 683 × 1024 | a German shepherd's portrait | pet | rawpixel, "Brown dog portrait close face", via Openverse (`https://www.rawpixel.com/image/6038832/photo-image-face-public-domain-eyes`) | CC0 1.0 (public domain) |
| `tabby-cat.jpg` | 1024 × 634 | a tabby cat's face | pet | rawpixel, "Cat portrait", via Openverse (`https://www.rawpixel.com/image/3296740/free-photo-image-cat-abyssinian-animal`) | CC0 1.0 (public domain) |
| `street-couple.jpg` | 1024 × 1024 | a couple on a street, one drinking, one on the phone | couple | Mussi Katz, "Couple", Flickr, via Openverse (`https://www.flickr.com/photos/52775988@N00/51285291964`) | CC0 1.0 |
| `chocolate-cake.jpg` | 960 × 1440 | a slice of chocolate cake on a plate | food | Oriana Ortiz, "Chocolate Cake", StockSnap, via Openverse (`https://stocksnap.io/photo/chocolate-cake-XTNRPGQBYL`) | CC0 1.0 |

Photos elsewhere in the repository, used in place (their provenance is in `Tests/Corpus/README.md`
and the picture library's `library.json`):

| Path | What | Category |
| --- | --- | --- |
| `Tests/Corpus/parrots.jpg` | two macaws | pet, animal |
| `Tests/Corpus/barn.jpg` | a red barn and its reflection | building, landscape |
| `Tests/Corpus/hibiscus.jpg` | a hibiscus before a shuttered window | flower |
| `Tests/Corpus/lighthouse.jpg` | a lighthouse on rocks | building |
| `Tests/Corpus/espresso.jpg` | a coffee cup | food |
| `App/PaintByNumber/Resources/Samples/red-fox.jpg` | a red fox in snow | animal |
| `App/PaintByNumber/Resources/Samples/bald-eagle.jpg` | a bald eagle | animal |
| `App/PaintByNumber/Resources/Samples/bison-in-snow.jpg` | a bison in snow | animal, hard (white ground) |
| `App/PaintByNumber/Resources/Samples/hummingbird.jpg` | a hummingbird at a flower | small subject |
| `App/PaintByNumber/Resources/Samples/oxbow-bend.jpg` | Oxbow Bend in autumn | landscape |
| `App/PaintByNumber/Resources/Samples/horseshoe-bend.jpg` | Horseshoe Bend | landscape |
| `App/PaintByNumber/Resources/Samples/lassen-lupine.jpg` | lupine before Lassen Peak | flower, landscape |
| `App/PaintByNumber/Resources/Samples/monarch-coneflower.jpg` | a monarch on a coneflower | flower, small subject |

The Kodak files came from
`https://raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite/master/PhotoCD_PCD0992/<n>.png`
(the suite's lossless PNGs); the Library of Congress files from
`https://tile.loc.gov/storage-services/service/pnp/fsac/<prefix>/<id>v.jpg` (the 1024-px service
copies); the Openverse ones (CC0 and public-domain photographs found with its API,
`https://api.openverse.org/v1/images/?license=cc0,pdm`) from the image URL of their records;
`astronaut.png` from the scikit-image package. Adding a photo: a row here, an entry in `manifest.json`, and its scene and maps from
the stand-in.
