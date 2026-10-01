extension ColorNickname {
    /// The vocabulary, one entry per line: the sRGB hex of the color the name evokes, then the
    /// name. Hand-picked, in rough groups (neutrals, warm earth tones, reds and pinks through
    /// yellows, greens and teals, blues and purples, then names added for gamut gaps and
    /// character). Style guide, enforced where mechanical by `ColorNicknameTests`:
    ///
    /// - One or two words, Title Case, ASCII letters, spaces and at most one hyphen; at most 16
    ///   characters; no digits.
    /// - Concrete and evocative: things, places, weather, food, materials, times of day.
    /// - Never brand names, people's names, body parts, skin-tone words, anything crude, religious,
    ///   political or medical; no word that is a different color from the anchor ("Blue Fog" for a
    ///   grey), no plain color word alone, no superlatives.
    /// - Varied: no leading word is shared by more than four entries.
    /// - The anchor has to look like its name to a careful person: pick the hex from the actual
    ///   object, material or weather, and check it on a swatch before adding it.
    ///
    /// Anchors must also cover the sRGB gamut (`ColorNicknameTests.vocabularyCoversTheGamut`), so a
    /// new name goes where the test finds a gap or where the table is thin, never as a stretched
    /// duplicate of a neighbour.
    static let table = """
050507 Void
0F0E0D Soot
0B0E1A Inkwell
14110F Coal Cellar
120F16 Obsidian
0F1215 Raven Wing
191512 Tar Pit
1C0F12 Licorice Twist
080A12 Starless Night
101319 Midnight Oil
1E140E Dark Roast
0E130F Pitch Pine
17111A Cellar Door
071016 Moonless Sea
1D1020 Plum Ink
111A13 Fern Shadow
2A1B14 Cold Brew
1C1410 Coffee Grounds
202224 Cast Iron
2B2D30 Wet Asphalt
38383A Charcoal Smudge
2D3339 Blued Steel
454B55 Thunderhead
56514E Chimney Smoke
48525B Slate Roof
3F4042 Graphite Pencil
3B3F44 Iron Gate
4E5053 Anvil
5B5D5E Flint
4A4A4C Basalt Cliff
5C6064 Rainy Cobbles
78797A Pewter Mug
2F2E2E Coal Dust
7A756F Weathered Fence
565A5C Shale
5C5A57 Cinder Path
8B837A Field Mouse
7B7A77 Stone Wall
8E8E8B River Pebble
9A9A97 Concrete Slab
9FA1A6 Dove Wing
98A2A8 Harbor Fog
B9BBBD Silver Spoon
A3A8AB Tin Roof
9DA3A6 Zinc Bucket
8F9293 Nickel Plate
6F767C Steel Beam
C6C8CA Aluminum Foil
D2DDE3 Window Frost
C9CDD0 Cloudy Day
9EA3A8 Overcast
A59D92 Dusty Road
D7D5D0 Sidewalk Chalk
B3ADA4 Pebble Beach
F4F7FA Snowdrift
F2F2F0 Cotton Cloud
F6F1E7 Milk Foam
F1EBDD Fresh Linen
EDEBE6 Salt Flat
FAF8F4 Sugar Dust
F2ECD8 Rice Paper
E8E6E1 Chalk Dust
E3E9EC Frosted Glass
D7D2C8 Moth Wing
F7F6EF Dandelion Fluff
F8F1DE Meringue Peak
FBF5E6 Whipped Cream
EFE8D8 Eggshell
EDEAE3 Pearl Button
D9D2C5 Oyster Shell
F2E8D0 Candle Wax
F5F4F1 Goose Down
F0ECE6 Lace Curtain
F0F3F5 Cumulus
F5F3EE Blank Canvas
EDF0EC Sea Salt
F8F8F6 Crisp Sheet
EFEEEA Whitewash
E6E0D4 Birch Bark
F7EFEA Marshmallow
F1EEEC Talc Dust
DCE7E1 Duck Egg
D8EBE2 Seafoam Spray
D9ECF2 Ice Cube
D4E6EE Glacier Melt
FDFDFD Printer Paper
E9E9EA Polished Marble
DADCDF Quiet Fog
BEC2C5 Rain Gutter
AEB2B3 Galvanized Pail
1A1B1E Piano Lacquer
262B33 Nightfall
EEF1EF Winter Linen
E5E1D8 Almond Milk
EFEBE0 Ricotta
E2DED3 Oat Flour
D8CBB2 Oat Milk
D8C3A0 Sand Dune
A99175 Wet Sand
9C8B79 Driftwood
C8B48A Dune Grass
B89E72 Burlap Sack
BBA27C Hemp Rope
D6BD93 Biscotti
E3CFA3 Shortbread
CFA97E Toasted Almond
D9BC7C Wheat Field
E0C98B Straw Hat
D4A872 Graham Cracker
D9A55E Croissant
D9B17A Pie Crust
D9BE98 Peanut Shell
D9C5AA Latte Foam
B79C80 Cappuccino
7B5239 Cocoa Powder
D1B08A Hazelnut Praline
8D6E50 Walnut Shell
A5703F Pecan Pie
B8741F Maple Syrup
E6A82B Honeycomb
C57E1A Burnt Honey
BF7A1A Amber Glass
C68A4B Salted Caramel
B67E3F Toffee Crunch
DA9A36 Butterscotch
9B5A2B Gingerbread
8E4F2A Cinnamon Stick
8A5D3D Nutmeg
7B4A2F Roasted Chestnut
5B2C1D Mahogany Desk
5A4030 Walnut Table
9A6E3A Teak Deck
86582F Oak Barrel
A0603A Cedar Chest
7C3A2A Redwood Bark
7A5B3C Pine Cone
9D7C4D Acorn Cap
5A4636 Tree Bark
3C2E26 Wet Bark
3B2D20 Peat Moss
4C3A2B Mud Pie
3B2418 Coffee Bean
3A2119 Dark Chocolate
6A4330 Milk Chocolate
5D4037 Truffle Dust
4A2C20 Fudge Sauce
8B5A2B Saddle Leather
7E5A3C Worn Leather
8C5E3C Leather Satchel
A5441F Rust Bucket
8A3324 Old Barn
C46A47 Terracotta Pot
A8603F Flowerpot Clay
A24B3B Brick Wall
B5654A Brick Dust
9C5440 Kiln Brick
C69B7B Adobe Wall
B7683F Canyon Dusk
B2603B Mesa Rock
C8946A Sandstone
B97A57 Desert Clay
C0703F Copper Pipe
A9683F Old Penny
9C6B35 Bronze Medal
C79C3E Polished Brass
A7843C Antique Brass
D9B23C Gold Leaf
E8B923 Goldfinch
C5A24A Gilded Frame
F5C34D Candle Flame
F2B84A Lantern Glow
B8683A Copper Kettle
6B4423 Boot Leather
4E3A2A Stable Floor
6E5A47 Old Saddlebag
8A7358 Cork Board
A89070 Dry Riverbank
7D6B55 Sparrow Wing
9B8A6E Tumbleweed
5C4B3B Smoked Oak
463A30 Charred Log
34281F Burnt Toast
C9A66B Hay Bale
B8955A Barley Straw
E8D5A5 Parchment Scroll
EAD9B5 Old Lace
D8C49A Manila Folder
C4A77D Cardboard Box
D0B488 Corn Husk
C7AD8A Chai Latte
AA8E6C Thatched Roof
8F7556 Bark Chip
704C30 Smokehouse
64412A Dark Walnut
E2C48D Cider Donut
EBD4A3 Shortcake
C41E3A Cherry Pie
D3112B Maraschino
E02020 Fire Engine
C8281F Ladybug
D23A2A Ripe Tomato
D93A2B Poppy Field
A8212F Strawberry Jam
C8344A Wild Strawberry
B0213E Raspberry Jam
A31F34 Cranberry Juice
8A1C2E Cranberry Bog
A3203A Pomegranate
6F2A35 Merlot
7B1E2B Garnet
5B1B2D Cocoa Cherry
6E2230 Spiced Plum
8A2236 Sour Cherry
5E1A2A Currant Jelly
A8112D Ruby Glass
C0452A Paprika
A8402A Smoked Paprika
B5251E Chili Pepper
D54B3B Boiled Lobster
8B1A2B Theater Curtain
D8566F Rose Petal
D9607A Wild Rose
65322E Rosewood
F0C8CC Rose Quartz
F5D6D6 Rose Water
E8957C Smoked Salmon
F07C4F Salmon Fillet
F0705E Coral Reef
F24E5E Watermelon Slice
F07C86 Flamingo
E8908F Flamingo Feather
F5A3BD Bubble Gum
F7C1DB Cotton Candy
E5426E Raspberry Sorbet
C23B5B Rhubarb Stalk
B8334F Rhubarb Compote
8E1B4B Beetroot
A02456 Beet Juice
7E1F3E Radicchio
F4C7D3 Cherry Blossom
C42A2A Orchard Apple
CB6A2E Fox Fur
E0501E Ember Glow
C8381F Hot Coals
E8553A Campfire
D8432C Tomato Soup
BE3B33 Barn Roof
9D2B2B Fire Brick
B12A34 Red Currant
E34A5F Strawberry Fizz
DD5E7A Candy Floss
F2A7B8 Sugared Petals
F9CDD3 Peony Froth
F6B8C6 Taffy Pull
EE8FA6 Sweet Pea
D13F6A Hibiscus
C72C5C Cherry Cordial
F5A9A0 Guava Sorbet
F7B5A0 Apricot Fizz
F0C0A8 Conch Shell
F4D2C4 Seashell
EBB5A8 Salmon Mousse
E39A8C Coral Sand
D98B7C Dusty Coral
C97B7B Faded Rose
A55A6A Antique Mauve
C98D96 Rose Ash
D8A9AD Faded Peony
E7C1C6 Powder Puff
E4B7BD Ballet Slipper
D9A5B3 Lychee Fizz
C9748F Raspberry Ripple
FF7F50 Hot Coral
FF5A36 Blaze
FF6A13 Safety Cone
F26B21 Pumpkin Patch
EF7B1A Tangerine Zest
F58A07 Marmalade
F08A24 Orange Peel
F29B38 Cantaloupe
F3A15B Apricot Jam
F7B26B Apricot Nectar
F8C291 Peach Cobbler
F9D2A8 Melon Sorbet
FBD9B5 Melon Cream
F6C9A0 Sherbet Cone
E9762B Carrot Top
E56A1C Autumn Pumpkin
D9531E Persimmon
E8883A Sweet Potato
D2691E Cinnamon Candy
C25B1B Rust Leaf
E07B39 Mango Chutney
F0A53C Papaya
F6B93B Mango Lassi
FBB040 Saffron Thread
F6C65B Yellow Squash
FACC2E Egg Yolk
FFD21F Sunflower
FFDA3A Lemon Zest
FFE04D Canary
FDE47F Buttercup
FDEB9E Lemon Chiffon
F9E7A0 Banana Pudding
F7E08C Sunbaked Straw
F1D26A Mustard Seed
E3B72E Dijon
D8A31D Turmeric
CFA018 Goldenrod
E7C84A Corn Silk
F4DC72 Lemon Meringue
FCE883 Pollen
EAC541 Daffodil
F2D544 Dandelion
FFD93B Rubber Duck
FFE97A Chick Fluff
FFEFA8 Butter Cream
E8D98A Chamomile
8A8A3A Olive Grove
6B6B2E Olive Oil
808040 Dried Oregano
9A9A52 Sage Brush
8C9A6B Sage Leaf
A3AE8A Eucalyptus
B5BE9F Dusty Sage
7D8F69 Lichen
8E9A7A Pistachio Shell
B7D07D Pistachio Gelato
C5D68A Honeydew
D8E8B4 Honeydew Mist
C6DDA8 Pear Blossom
B5CC6B Ripe Pear
CDDB6F Tart Apple
A8C23A Lime Wedge
B5D334 Key Lime
C4E043 Lime Sherbet
D3E85C Chartreuse Fizz
9ACD32 Spring Shoot
8DB600 Young Apple
7CB518 Fresh Peas
6FA83A Garden Peas
5E9E2F Clover Patch
4C9A2A Lucky Clover
5BAE3C Meadow
66B032 Spring Lawn
3F8A2A Fresh Lawn
2E7D32 Ivy Wall
3B7A3A Shamrock
2F6B2F Holly Leaf
1F5B2E Pine Boughs
1B4D2E Spruce Forest
1E4D3A Evergreen
14392A Deep Forest
123524 Dark Woods
1A3D2B Cypress
24543A Cedar Grove
2E5B3E Juniper
3C6B45 Boxwood
4A7C4F Fern Frond
5D8F5B Fern Hollow
6E9B63 Wet Moss
7BA05B Mossy Bank
688B3E Moss Garden
4F6D2E Swamp Reed
556B2F Olive Branch
5C6B34 Artichoke
6B7B3A Cattail
8A9B4F Lemon Balm
9AAF5E Basil Leaf
7A9A3E Fresh Basil
85A34A Parsley
4C7A34 Rosemary Sprig
A4B494 Celery Stalk
B6C9A0 Cabbage Leaf
C8D8B0 Butter Lettuce
A8C8A0 Spring Mint
B5DCB5 Mint Syrup
C8EBD0 Mint Chip
D7F0DC Peppermint Tea
98D8B3 Minty Breeze
7FC8A0 Sea Glass
8FCDB0 Sea Lettuce
A8D5BA Celadon Vase
B9DEC8 Jade Veil
6BB38A Jade Garden
3E9B6B Jade Plant
2A8A5E Emerald Isle
19875A Emerald Pool
0F7A4E Malachite
007F5F Tropical Fern
008F6B Parrot Wing
00A86B Jungle Gecko
00B26B Parakeet
00C070 Glowworm
5FD38D Mint Sorbet
2E8B57 Kelp Forest
1D6B4F Kelp Bed
0C5A45 Lagoon Depths
0A4B3C Bottle Glass
0E3B33 Pondweed
0B2B26 Forest Floor
1B5E4B Spruce Shadow
2F6F5E Eucalyptus Bark
4E8A78 Verdigris
6FA593 Weathered Copper
86B5A5 Patina
A3C6B8 Oxidized Dome
7BA89B Sea Foam
5B9A8B Tidal Pool
3A8A7E Lagoon Edge
2A7F7A Peacock Tail
1F7A7A Teal Tide
188A8A Mermaid Cove
0F6B6E Teal Lagoon
00828A Turquoise Bay
12A3A5 Reef Water
1FB5B0 Caribbean Cove
40C9C0 Aqua Splash
6FD6CF Swimming Pool
9DE3DC Lagoon Shallows
B8EDE6 Spindrift
C9F0EA Mint Frost
7FD1D1 Pool Tile
50B5B8 Surf Wash
2D9CA0 Plunge Pool
087F8C Peacock Feather
0A6970 Murky Lagoon
0B4F55 Reef Shadow
0C3E45 Abyss
06323A Harbor Night
D6EAF5 Morning Frost
C8E1F2 Ice Pond
B8D9EE Robin Egg
A6CFE8 Clear Sky
8EC3E6 Summer Sky
74B3E0 Kite Sky
5BA3DA Pool Float
3E92D4 Open Water
2A83CC Bluebird
1C75BC Denim Jacket
1A5FA8 Harbor Blue
1D4F91 Diving Bell
163F7A Sailor Stripe
123163 Navy Peacoat
0E2A55 Midnight Harbor
0B2147 Night Tide
0A1A38 Deep Ocean
071430 Midnight Sky
0B1226 Midnight Ferry
111C3A Twilight Edge
1B2A52 Dusk Indigo
2A3B6B Tarpaulin
344A7E Indigo Dye
4A5F96 Faded Denim
6076A8 Stonewashed
7A8FB8 Hydrangea
97A9C9 Cornflower Haze
A9B9D4 Powder Sky
B8C6DE Baby Bunting
CAD5E6 Winter Sky
D5DEEA Dawn Mist
C0CAD8 Steel Frost
8FA3BA Rain Cloud
6E86A3 Storm Sea
566F8C Slate Lake
435B77 Blueprint
34495E Slate Pencil
2C3E55 Storm Slate
25364F Shipyard
1F2F4A Stormy Night
5C7A99 Mountain Lake
7B97B2 Mountain Haze
9BB3C7 Distant Ridge
B4C7D6 Morning Haze
3F6FB8 Delft Tile
2F5DC0 Cobalt Dive
1F4FD0 Ultramarine
2D43E0 Electric Blue
3A34E8 Neon Indigo
2C1FD6 Lapis Lazuli
1B14B8 Sapphire Night
221A9A Violet Dusk
2A2078 Velvet Ink
2A2569 Pansy Night
383083 Grape Hyacinth
4A3F9A Iris Garden
5E54B0 Wisteria Vine
746CC4 Periwinkle
8F89D3 Lilac Haze
A9A4DE Lavender Fields
BDB8E6 Lavender Milk
D2CEF0 Lilac Whisper
E2DFF5 Lilac Mist
CFC3E8 Orchid Whisper
B9A8DC Lilac Bush
A18CCB Amethyst Geode
8C74BE Grape Soda
7A5FB0 Concord Grape
694AA0 Plum Jam
583A8C Aubergine
4B2E7B Plum Velvet
3D2468 Grape Jelly
2E1A52 Night Plum
231442 Deep Plum
1A0F33 Violet Ink
3B1E5F Wine Grape
522A76 Damson
6A3A8A Heliotrope
7C4B99 Fig Jam
8E5CA8 Plum Blossom
A275BA Sweet Violet
B890CC Orchid Bloom
CBA9DC Lavender Sorbet
DCC2E6 Wisteria Cloud
E8D5EE Iced Lilac
5A3E6E Dusty Plum
6D5380 Thistle
836A96 Heather Moor
9A83A9 Dusk Heather
B09DBB Faded Lavender
C5B7CE Foggy Lilac
D5CCDB Mauve Smoke
4A3A55 Smoky Plum
372A44 Crow Feather
5D2A5E Elderberry
7A2F6E Boysenberry
9B3A86 Dragon Fruit
B8479C Fuchsia Bloom
D45FB0 Orchid Pop
E87AC4 Cyclamen
F28DCE Bubblegum Orchid
D6339A Camera Flash
BE1E8C Electric Berry
A0157A Raspberry Crush
8A1068 Berry Compote
6E0F55 Loganberry
6A1B4D Mulberry
010102 Event Horizon
02030A Deep Space
04040A Inkpot
030303 Cavern
050403 Hollow Log
070606 Coal Mine
6E1BC1 Amethyst Crystal
7B2FD6 Ultraviolet
9550EA Phlox Bloom
8A3FE0 Violet Flare
A15CEE Petunia Bed
5715E4 Electric Violet
5441F5 Blue Raspberry
5B6CF0 Bluebell Wood
7A2DEA Grape Gumball
0F0AA8 Cobalt Night
D842C9 Bougainvillea
C236E7 Neon Orchid
FA21F7 Electric Fuchsia
F618CA Fuchsia Flare
FC129D Neon Rose
F544AC Lollipop Swirl
E488F5 Orchid Candy
F571EA Bubble Orchid
C168DF Wild Orchid
1A8EF1 Swimming Hole
00A9F4 Lagoon Glow
6CF238 Neon Lime
4BEF74 Gumdrop
29F8B5 Aurora Glow
40F4D0 Aqua Lantern
9AF13A Peridot
BBFB2D Firefly Glow
AEFC7A Lime Fizz
C423E6 Festival Lights
FD28EA Pinball Flash
A815AB Pitaya
F676F8 Cosmic Candy
F396FD Unicorn Mist
B16AFA Laser Lavender
697CFC Periwinkle Pop
790DB6 Violet Storm
3EF22D Lime Slushie
37E447 Tree Frog
33F5B0 Spearmint Fizz
5F71FB Hyacinth Bloom
FB2BF0 Pop Art
C61AE6 Cattleya Orchid
C52DE5 Moth Orchid
EFA066 Last Light
EDB85A Golden Hour
3A4F8C Blue Hour
F08F5E Afterglow
8C86A8 Dusk Haze
9AA8B0 Drizzle
5E6F7A Monsoon
E8C9A0 Heat Haze
D5DDE0 Hailstone
4C5A68 Squall Line
D7B98A Sahara Sand
8A9A7B Salt Marsh
9A927F Tidal Flat
6F6B4B Moorland
8FB04F Rice Terrace
7E9654 Tea Garden
9AA54F Bamboo Grove
5C7D54 Saguaro
A5A56B Prairie Grass
9FB4B8 Morning Lake
8E8A82 Quarry Stone
7D7F83 Granite Peak
7FB5C9 Glacial Lake
5BD9A8 Northern Lights
E57A55 Starfish
F28C28 Clownfish
E8602F Koi Pond
D63A2E Macaw Wing
4A78B8 Blue Jay
1AA5B8 Kingfisher
2E6F5A Mallard
8A98A5 Heron
A25DA0 Foxglove
F5A81C Marigold
E8742A Nasturtium
D13B5B Zinnia
E3305B Tulip Field
F7E9EA Magnolia
D8A6C4 Water Lily
EFB2C8 Lotus Bloom
4E5226 Bog Myrtle
565A2C Moss Rock
7C8434 Split Pea
5C6B2E Hop Vine
3B3A19 Pine Tar
80536D Berry Smoke
4B190C Dried Chili
7A2410 Rooibos Tea
5E1C0E Ancho Chile
1F0B06 Roasted Cacao
B59B22 Ochre Wall
797A3D Fennel Seed
"""
}
