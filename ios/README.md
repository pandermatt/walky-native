# Walky for iOS and macOS

A native Swift port of the simulation in `../web/src/sim` and `../web/src/state`,
and (from Phase 3) a SwiftUI + Metal app around it — on the phone, and on the
Mac as a target of its own. See **The Mac app** below for what the two share,
which is nearly everything.

## Why this is a package and not just an app target

`WalkySim` has no UIKit, no Metal and no Foundation-UI, so it builds and its
conformance runner *runs* under plain SwiftPM. That matters: the risky part of
this port is the simulation, and this arrangement lets it be verified without
Xcode, a simulator or a device.

## Building the app

```bash
xcodegen generate                       # after changing project.yml or adding a file
xcodebuild build -project Walky.xcodeproj -scheme Walky -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

This needs an iOS simulator **runtime** (Xcode ▸ Settings ▸ Components, ~8 GB).
Installing one requires an admin account, and the download hangs at "Preparing
to download…" with no error message behind iCloud Private Relay or on some
university networks — if it stalls, try another network before assuming Xcode is
broken.

Without a runtime the app can still be *compiled*; see the comment at the top of
`project.yml` for the flags that takes and why each is needed.

## The Mac app

`WalkyMac` is a **native macOS target**, not Catalyst and not "Designed for
iPad":

```bash
xcodegen generate
xcodebuild build -project Walky.xcodeproj -scheme WalkyMac
```

The port is what makes a second platform cheap. Everything that is not pixels
is already in `WalkyCore` — the camera, the tools, the world and its undo, and
`PointerRouter`, which is a state machine over *points* and has never heard of
`UITouch` — and `MapRenderer` draws through SwiftUI's `GraphicsContext`, which
is the same type on both platforms. So the Mac target shares all of that plus
every view in `App/UI` that is neither a finger nor a camera, and adds one
folder:

| `Mac/` | |
| --- | --- |
| `WalkyMacApp.swift` | `@main`, the window and the `Settings` scene — which is where ⌘, comes from. |
| `MacRootView.swift` | The window's contents: map, pointer surface, the same floating bar the phone wears. |
| `MacCanvas.swift` | The only file here that knows what a mouse is. `NSEvent` → the router's calls. |
| `MacCommands.swift` | The menu bar. Nothing new, the same actions where a Mac looks for them. |
| `MacShell.swift` | The window state the menu bar also has to reach. |
| `MacSettingsView.swift` | The same settings pages, as a Mac's tabbed Settings window rather than the phone's drill-down sheet. |

What the Mac brings that a touchscreen does not, all of it handled in
`MacCanvas` and answered by four entry points on `PointerRouter`:

- **A hover** — a pointer with no button down, so the tool ghosts follow the
  cursor the way they do on the web, where `app.ts` sends `pointermove`
  whether or not a button is held.
- **Gestures that arrive already recognised** — a trackpad pinch or twist is an
  `NSEvent`, never a second touch. The same `pinched`/`twisted` entry points an
  iPad app on a Mac uses.
- **A scroll wheel** — two-finger scrolling pans, a wheel zooms (⌘ or ⌃ zooms
  either way). `ZoomMouseListener`'s own gesture, back on the platform it was
  written for.

Two features are absent rather than disabled, which is the rule the settings
sheet already follows for a phone without a LiDAR camera: **scanning a room**
(RoomPlan needs a camera no Mac has) and **alternate app icons** (an iOS
affordance). Sharing a map is the Finder's job here — save the `.walky` and
hand over the file.

It is **sandboxed** (`Mac/Walky.entitlements`): the panels' files, the network
for Apple's tiles and OpenStreetMap, and location when you ask for the map
around you. There is no development team in `project.yml`, so a local build
signs to run locally, exactly as the phone target does.

The target's floor is **macOS 26**, where every other target here starts at the
oldest OS it can. The difference is installed base: the phone app has one and
this does not, and starting at 26 is what lets the shared chrome — the
toolbar's glass, the generating border — be one design on both platforms
instead of the Mac carrying a second, older one.

## Keyboard shortcuts

On the Mac and on an iPad with a hardware keyboard, from one table in
`Sources/WalkyCore/Commands.swift`:

| | | | |
|---|---|---|---|
| `1` Wall | `2` Rectangle | `3` Border | `4` Pedestrians |
| `5` Mark goal | `6` Generator | `7` Measure detour | `esc` Put the tool down |
| `Space` Play / pause | `⌘Z` Undo | `⌘0` Reset zoom | `⌘.` Hide controls |
| `⌘O` Open map | `⌘S` Save map | `⇧⌘⌫` Clear map | `⌘,` Settings |

The digits count the cells you can see on the bar — five on the strip, then the
two in the overflow menu. The web app numbers its own strip the same way and
lands on different digits because it has tools this port does not: the rule
travels, the numbers do not.

Three readers, one table: the bar's cells, the menu bar (`App/WalkyCommands.swift`,
attached by *both* apps) and the printed list under Settings ▸ Keyboard
shortcuts. That is the web's argument, ported with the table —
`web/src/ui/toolbar.ts` derives its `SHORTCUTS` from the button table because
"a list of them kept somewhere else is a list that goes wrong the first time a
tool moves". This port had already proved it: the bar said "Mark goal" and the
Mac menu said "Mark Goal".

Two things split by platform, for one reason each:

- **Bare keys are not menu items.** A key equivalent with no modifier is
  reliable on a Mac and is not on iPadOS, so the digits, Space and Escape are
  answered by the input views (`WalkyTouchView.keyCommands`,
  `WalkyPointerView.keyDown`) and everything carrying ⌘ is the menu bar's.
- **They go quiet while anything covers the map** (`AppModel.pressed`). Both of
  Walky's text fields live inside Settings, and somebody typing "5th Avenue"
  into the place search means the digit.

## Closing one side of a door

A door is a wall carrying a `Generator`, so **nobody ever walks through one**:
the only way a crowd reaches the wrong side of a doorway is by *appearing*
there. `generatorMouth` puts them on the side the goal is on, which on a floor
plan can be the room when you wanted the corridor.

So a door may carry a `closedFacing` — one unit vector, the single piece of
judgement the geometry does not contain. The mouth stays derived: the goal
direction is **reflected** across the closed face rather than reversed, so a
crowd headed north-east still leaves pointing north-east, from the other
doorstep.

On macOS, hover a door with no tool in hand and a cap appears on each of its
two doorsteps — *the two candidate mouths*, literally where people would land,
so what you see is what you get. Click one to close it; the closed side is
drawn as a solid bar whether or not you are pointing at it. Closing the side a
door is using moves its crowd; closing the one already closed opens it; closing
the other one moves the seal, so both-closed is unrepresentable.

Three properties worth knowing, each of which a geometry-based seal would lose:

- **Nothing goes stale.** A sealing panel sized against `pedestrianRadius`
  quietly unseals when that slider moves.
- **The demand is untouched.** A door's arrival schedule is hashed on its
  middle, so moving its geometry reshuffles it and the map stops being A/B-able.
- **No navigation rebuild.** Not one wall corner moves, so the O(n^2.5) rebuild
  — 2.1s on a 600m import — is not owed.

It costs one flag bit and codec **version 5**, the same shape version 4 already
used: one more trailing section, so a map with both sides open is written byte
for byte as before, and an older build refuses a newer file by name rather than
misreading its tail.

## The sticker pack

`Walky.app` embeds `WalkyStickers.appex`, an iMessage pack of eighteen stickers.
It has no code: its only build phase is Resources, the executable in the `.appex`
is a stub Xcode links for it, and everything it ships is one compiled asset
catalogue.

Nothing in `Stickers/` is edited by hand. `../web/tools/stickers.ts` writes the
whole `.xcstickers` — the PNGs, every `Contents.json`, and the twelve sizes of
the Messages drawer icon — and the output is committed. Regenerating is a
decision, the way regenerating the icons is:

```bash
cd ../web && npx vite-node tools/stickers.ts
```

The stickers themselves are characters, cut out of three drawn contact sheets in
`web/tools/sheets/`, and they are the one place the brand is not derived from the
model — the drawer icon over them still is. `web/README.md` has that argument in
full, and what is in the pack. Two things about the target are worth knowing
here:

- **Its Info.plist is generated like the app's**, from `info:` in `project.yml`.
  iOS refuses to install an app whose embedded extension carries a different
  `CFBundleShortVersionString`, and two plists written by the same generator
  agree on that by construction where two written by hand agree until somebody
  edits one.
- **`NSStickerSharingLevel` is a plist key here, not a build setting.**
  `INFOPLIST_KEY_NSStickerSharingLevel` is only read on the
  `GENERATE_INFOPLIST_FILE` path; set alongside a generated plist it is silently
  inert and the built `.appex` simply does not have the key — which costs
  nothing at build time and quietly stops a recipient without Walky from keeping
  a sticker, the only way a pack ever travels further than the app does.

To see it: build and run, then open Messages, open the sticker browser from the
compose bar, and the pack is a tab in it under the Walky mark.

## Running the package

Set `DEVELOPER_DIR` — `xcode-select` points at CommandLineTools on this machine,
which has no `XCTest.framework` and cannot resolve swift-testing's `Testing`
module. No sudo needed.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test                    # the unit suites
swift run walky-conform math  # this port vs V8, bit for bit
```

## The arithmetic

ECMAScript and Swift both leave `exp`, `log`, `sin`, `cos`, `atan2`, `acos` and
`pow` implementation-approximated, and V8 and Darwin's libm are both correct and
disagree. Measured over the ranges this model actually uses:

| | atan2 | acos | exp | cos | log | sin | pow |
|---|---|---|---|---|---|---|---|
| V8 vs Darwin libm | 19.0% | 15.1% | 10.6% | 5.4% | 4.2% | 3.6% | 0% |

Walky's determinism is exact rather than approximate — every fidget, trait and
tie-break is a positional hash — so a last-bit disagreement is not a small
error. It is a different run a few hundred ticks later. `acos` is the sharpest
case: it ranks ear candidates in `convexDecompose`, so it changes how a wall is
split, which changes the visibility graph, which changes where everybody walks.

So `CWalkyMath` carries fdlibm, which is what V8 carries. **With one exception**:
`pow`. V8 does not use fdlibm for it — Darwin's `pow` agrees with V8 on every
sample while the fdlibm routine is one ULP out on 10.7% of them. `walky_pow`
stays in the C target, uncalled, as the evidence for why it is not called.

`Math.hypot` is a third case again: not approximated by a library but computed
by V8 as `max * sqrt(1 + (min/max)^2)`, which the naive `sqrt(a*a + b*b)`
differs from on 39% of inputs. `jsHypot` reproduces V8's form, where every
operation is IEEE-correctly-rounded and so matches by construction.

None of this is guesswork. `tools/mathProbe.ts` writes what V8 computes and
`walky-conform math` checks this port against it, 20,000 samples per function,
comparing bit patterns rather than values.

**The web app is deliberately untouched.** The port is the newcomer, so the port
carries the whole compatibility burden.

## The app icons

Nineteen of them, and eighteen are generated:

```bash
swift run walky-icons        # needs ImageMagick and librsvg
```

The project owns two drawings and every icon is one of them. `Walky.icon` is the
app's own pedestrian -- a goal-coloured circle inside a ring, which is what
`PedestrianPanel.drawPedestrian` has always drawn -- three of them in a triangle.
`Icons/walky-2016.png` is the icon of the archived Java app, a walking figure
over three receding crosswalk stripes, and the only artwork that survived the
rewrite. Three families follow from that:

| | |
|---|---|
| **Crossing** | The 2016 stripes, walked by the app's own dots. One, and four abreast. |
| **Ground** | The 2016 figure over ten grounds -- the map's four wearing the `ink` their own `Ground` defines, and the six accents pressed into service as grounds. |
| **Walker** | The 2016 figure in each of the six accents, on `#1E1E1E`. |

No colour is invented: `Sources/WalkyCore/AppIcons.swift` reads `Grounds` and
`Accents` straight out of `Theme.swift`, and where an accent is used as a ground
the ink is picked by `contrastRatio` rather than by eye -- which is how magenta
and rust ended up with the pale ink and everything else with the dark one.

Two things about that source drawing are worth knowing, because both are fixed
in code rather than in a paint program. Its outer stripes have the figure's feet
knocked out of them, which is right while the figure is standing there and wrong
the moment dots replace it, so each stripe is passed through
`monotoneChainHull` -- the hull the simulation wraps walls with -- and comes back
the trapezoid it was drawn as. And the crossing runs out of the bottom of its own
frame, which reads as perspective there and as an amputation once reframed, so
its sides are continued past the tile.

**They are `.icon` documents, not the loose PNGs at the bundle root that every
guide to alternate icons describes.** A flat PNG cannot be Liquid Glass. `actool`
turns out to take an Icon Composer document for `--alternate-app-icon` exactly as
it does for `--app-icon`: it compiles each into `Assets.car` and writes a
`CFBundleAlternateIcons` entry carrying `CFBundleIconName` and no
`CFBundleIconFiles`, so `project.yml` declares no icon dictionary of its own and
the alternates get specular highlights, parallax and the dark and tinted variants
like the primary. What it costs is that a compiled icon is not loadable as an
image, so the picker draws flat previews rendered alongside the bundles.

`AppIconTests` checks the join nothing else can: an icon missing from
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` is drawn, listed and tappable,
and silently refused at runtime.

## Importing a real map

The walls come from OpenStreetMap and the ground from Apple, because no Apple API
returns a building outline and reading one out of the tiles would break the
licence.

What limits an import is not area but **corners**. The visibility sweep is about
`n^2.5` in them, so a box twice as wide is thirty times the work, and building
density varies by a factor of two between an old town and a campus -- a box that
is comfortable in one is a five-second freeze in the other. `ImportBudget`
therefore counts corners and refuses past 1,000.

### What a building actually looks like

Measured over three 400m extracts, at `radius 13`, medians of three runs:

| extract | rings | corners | mean | median | p90 | p99 | max |
|---|---|---|---|---|---|---|---|
| Winterthur, Technikumstrasse | 182 | 1,589 | 8.7 | 8 | 14 | 33 | 45 |
| Winterthur Altstadt | 280 | 2,523 | 9.0 | 8 | 14 | 36 | 50 |
| Zurich, Kreis 1 | 299 | 2,655 | 8.9 | 8 | 14 | 35 | 37 |

A surveyed building is **eight or nine corners**, not four -- chamfers, bays and
extensions -- and the distribution has a tail: rings over twelve corners are
about 13% of buildings but carry **28-29% of all corners**. That tail is traced
curves, churches and stations, and it is the only part worth simplifying.
`SIMPLIFY_ABOVE` is set from those three rows.

### The model's scale

An import is a **1:10 model by default**, and that is the difference between
watching a crowd and squinting at one. A pedestrian is 13 world units against
`PX_PER_METRE = 56` -- 0.46m, a correctly sized body -- and a 380m import at 1:1
is 21,280 units, so on a 402pt phone a person draws at **half a pixel**. At 1:10
the same person is 4.9pt.

The pedestrian never scales; the map does. That is the whole trick, and its
price: obstacle inflation grows every building by one pedestrian radius so
bodies cannot clip walls, and 0.23m of inflation does not shrink with the map.

| scale | person on screen | streets that stay open |
|---|---|---|
| 1:1 | 0.49 pt | everything, and 100x the spatial-hash cells |
| 1:5 | 2.5 pt | wider than 4.6m |
| **1:10** | **4.9 pt** | **wider than 9.3m** -- the default |
| 1:20 | 9.8 pt | wider than 19m; warned |

`GeoAnchor` owns the ratio, not the importer. `world` and `coordinate` are
inverses and the Overpass box, the basemap crop and every MapKit route are
derived by going back out through `coordinate` -- scale one direction only and
all three break silently. Every metre readout goes through `GeoAnchor.metres`,
so a 1:10 map still reports the walk somebody would really take.

**The cross-check that catches a scale bug** is the measure tool's ratio: it
divides Apple's real-metre route by Walky's, so a mis-scaled Walky figure shows
up immediately as a ratio near 15 instead of near 1.

Related: `Viewport.zoomLevelMax` is raised from the content in
`WalkyWorld.resetZoom`. It used to be raised nowhere outside the tests, so the
camera could not frame an import at all -- a 380m map sat about eight screens
wide with no way out.

### What merging buys

`mergeFootprints` drops rings drawn inside other rings (`building:part` detail
that describes a building already described), then hulls clusters of touching
rings *only where the hull barely grows the area* -- so a terrace collapses and a
courtyard does not.

| extract | walls | corners | rebuild ms |
|---|---|---|---|
| Technikumstrasse raw | 182 | 1,589 | 218 |
| Technikumstrasse merged | 175 | 1,454 | 241 |
| Altstadt raw | 280 | 2,523 | 525 |
| **Altstadt merged** | **158** | **1,459** | **229** |
| Zurich raw | 299 | 2,655 | 783 |
| Zurich merged | 225 | 1,947 | 387 |

**It pays where buildings share walls and not otherwise.** An old town loses 42%
of its corners and rebuilds 2.3x faster -- and crosses the budget, so an import
that was refused now simply works. A campus of detached buildings loses 8%,
almost all of it from simplifying the tail, and the rebuild does not improve;
the 218 -> 241 there is within the noise of three runs, but it is not a
speed-up and should not be reported as one.

Past the budget the import is refused with what merging achieved and an **Import
anyway** button, which places the polygons already fetched. It never re-queries
Overpass: that is a free service on a fair-use policy which already answered.

The extracts are not committed -- three of them are 6MB, and this repository
already refused to carry 15MB of regenerable fixtures once. Fetch the exact
three above and re-measure:

```bash
base=https://api.openstreetmap.org/api/0.6/map
curl -o technikum.osm "$base?bbox=8.7260,47.4950,8.7310,47.4984"
curl -o altstadt.osm  "$base?bbox=8.7245,47.4985,8.7295,47.5019"
curl -o zurich.osm    "$base?bbox=8.5390,47.3720,8.5440,47.3754"
TILES=1 swift run -c release walky-geobench *.osm   # omit TILES for the 1x/2x/3x sweep
```

## Scanning a room

RoomPlan is the other way to get walls, and the easy one: it returns a finished
floor plan rather than a mesh, so every wall, door, window, opening and piece of
furniture arrives as a transform and a size in metres and projects onto the floor
as a rotated rectangle. `Sources/WalkyGeo/RoomScan.swift` does that projection
and cuts the doorways out of their walls; `App/UI/RoomScanner.swift` is the only
code that touches the framework.

**A room is the one map worth having at 1:1.** The scale slider exists because a
380m city at life size draws a pedestrian half a pixel wide. A 4 x 5m room is
224 x 280 world units against a pedestrian's 26 -- eight people abreast -- so a
scan sets no `GeoAnchor` at all, which is also what makes `measure` report real
metres.

Whether a door works is one number. `Behaviour.insideAnyWall` tests an agent's
**centre** against hulls already inflated by one radius, so a gap admits
somebody above `2 * radius`:

| doorway | world units | free centre band | verdict |
|---|---|---|---|
| 0.90m, a front door | 50 | 0.44m | comfortable single file |
| 0.80m, an interior door | 45 | 0.34m | fine |
| 0.60m, a narrow one | 34 | 0.14m | passable, and it will queue |
| 0.47m or less | 26 | none | sealed, and the section says so |

Note this is *half* what `MapImporter.sealsBelowMetres` reports: that figure is
`4 * radius`, the width at which two people pass, which is the right question
for a street and the wrong one for a doorway.

A doorway is offered three roles before the room is placed. **In** fills the gap
and stands a Walky door just inside it -- the door is the doorway's function, and
an open gap lets the crowd walk straight back out of the room it just entered,
which is what the sample room did first time. **Out** fills the gap with a slab
and marks it the goal, because a goal is a wall and in one room reaching the
doorway *is* leaving. **Open** leaves the hole. The widest doorway defaults to
Out and the rest to In, so a three-door room runs the moment it is placed.

**None of this runs in the Simulator** -- RoomPlan needs LiDAR, so it needs an
iPhone Pro, and the section is absent rather than disabled on anything else. So
`ScannedRoom.sample` is a written-down room that everything except the capture
view can be driven from: `RoomScanTests` checks the geometry (including that the
room is not mirrored, which is the one bug a fixture is the only defence
against), `RoomWorldTests` walks a crowd across it, and **Use the sample room**
in Settings does the same on any device. Scanning on a phone needs a camera
usage string (in `project.yml`) and a signing team (see the comment beside
`CODE_SIGN_STYLE`).

## Layout

```
Sources/CWalkyMath    fdlibm, as V8 carries it
Sources/WalkySim      the simulation: no UIKit, no Metal
Sources/WalkyGeo      OpenStreetMap footprints and RoomPlan scans, as walls
Sources/WalkyConform  replays fixtures, reports the first divergence
Sources/WalkyIcons    renders the alternate app icons, from the theme's colours
Sources/WalkyGeoBench what a real neighbourhood costs the rebuild
Fixtures/             generated by ../web/tools, committed
App/*.icon            Icon Composer documents; App/IconPreviews are the picker's
```
