import SwiftUI
import WalkyCore

/// The whole app.
///
/// A flat `ZStack` on purpose: the canvas reads only `redraw.version`, the
/// toolbar only `toolbar.*`, and neither is inside the other. Nesting them
/// would make arming a tool repaint the map and stepping the crowd re-evaluate
/// the toolbar.
struct RootView: View {
  /// The shared one, because a TV connected over AirPlay draws the same world.
  @State private var model = AppModel.shared
  @State private var router: PointerRouter?
  /// Whether the screen is divided right now.
  ///
  /// This scene's own, and not the model's: `externalDisplays` lives on
  /// `AppModel` because the loop reads it, whereas this is read only by this
  /// body -- and a TV drawing the same world is not folded in any sense.
  ///
  /// Only *whether*, never the hinge angle. `ArrangementView` already places
  /// the two halves, so the one thing left to decide is where the settings go,
  /// and an angle up in this body would rebuild the toolbar underneath the
  /// finger for every degree of hinge travel -- the bug `AppModel.tick`
  /// documents, wearing a third hat.
  @State private var divided = false
  /// Which side the system wants bars on, or nil where it never puts them there.
  ///
  /// Read rather than decided: `toolbarVerticalEdge` is the system's own answer
  /// for this scene, and taking it is what keeps Walky's bar agreeing with every
  /// other app on the display instead of guessing from a width. See
  /// `BarEdgeReader` at the foot of this file for why a custom bar gets to ask
  /// at all.
  @State private var barEdge: HorizontalEdge?
  @State private var sheet: Sheet?
  /// The two file sheets are the system's, not ours, so they are `Bool`s beside
  /// `sheet` rather than cases in it -- and `isCovered` is set from them too,
  /// because a map behind a save sheet is as covered as one behind Settings.
  @State private var saving = false
  @State private var opening = false
  /// Held while the exporter is up: it asks for the document, and asking the
  /// world for it again mid-presentation would save whatever the crowd had
  /// walked to by then rather than what was on screen when Save was tapped.
  @State private var outgoing: WalkyMapDocument?
  @State private var outgoingName = "Walky map"
  /// The map written to a throwaway file, while the share sheet is up.
  @State private var shared: SharedMap?
  @Environment(\.scenePhase) private var scenePhase
  /// Only the system's own scheme while `followsSystem` -- otherwise it is the
  /// scheme this view itself stated, arriving back down the environment.
  @Environment(\.colorScheme) private var scheme

  /// What the chrome states. Nil hands the decision back to the system, which
  /// is both what "System" means and what makes `scheme` above readable.
  private var chromeScheme: ColorScheme? {
    switch model.world.settings.appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  /// What the window states.
  ///
  /// The ground rather than the appearance, and the status bar is why: it sits
  /// over the map, so on a pale ground it has to be dark content -- Paper under
  /// a dark scheme put a white clock on an almost-white background. The two
  /// only diverge when a ground has been picked outright; on Automatic the
  /// ground already follows the appearance, so they agree by construction.
  private var windowScheme: ColorScheme? {
    let settings = model.world.settings
    guard !settings.followsSystem else { return nil }
    return settings.ground.isLight ? .light : .dark
  }

  /// Whether there is a base to put anything in.
  ///
  /// The fold's reserved region is active exactly while the phone is partially
  /// open -- Apple's own note says so -- which makes this the same question as
  /// "is it folded" with one fewer API in it, and no hinge observer at all.
  ///
  /// `chrome.hidden` is folded in here because it is the same decision: it puts
  /// the app in a viewing mode, and a viewing mode has no controls to find a
  /// home for.
  private var hasBase: Bool { divided && !model.chrome.hidden }

  /// The map and the fingers on it.
  ///
  /// A container, and it does not break the rule at the top of this file: what
  /// that rule forbids is the canvas sitting inside something that *reads the
  /// toolbar*. This reads neither.
  ///
  /// The two are together so that they are handed one rect by the arrangement
  /// rather than two, which is what keeps `Viewport.screenToWorld` the exact
  /// inverse of the canvas transform: the touch view reports points in its own
  /// bounds and the renderer writes its own size into `world.viewport`, so the
  /// two agree only while their frames match.
  private var mapLayer: some View {
    ZStack {
      MapCanvas(world: model.world, redraw: model.redraw, basemap: model.basemap,
                stats: { DebugStats(fps: model.fps, tps: model.tps) })

      if let router {
        TouchCanvas(router: router, onCommand: { model.pressed($0) })
      }
    }
    .ignoresSafeArea()
    .overlay {
      // Inside the map's half rather than over the whole screen, because what
      // it is about is the map: a spinner centred across the bend belongs to
      // neither half.
      RoutingOverlay(showing: model.routing.preparing,
                     tint: model.world.settings.accent)
    }
  }

  /// Everything the app draws over the map.
  ///
  /// Gone in one place for a clean capture -- the notice and both banners as
  /// well as the bar, since a screenshot with a capsule floating in it is not a
  /// clean screenshot. Pinch and pan keep working while it is hidden, so the
  /// shot can still be framed; a tap on the map brings it all back.
  private var chromeLayer: some View {
    // The `if` is inside, not around: this view is one half of an arrangement,
    // and a half that stops existing is a half the arrangement has to relayout
    // around. Emptied, it simply draws nothing.
    VStack {
      if !model.chrome.hidden {
        if let notice = model.notice.message {
          Text(notice)
            .font(.footnote)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        // Child views on purpose -- see CrowdBanner. Neither count may be read
        // in this body, which also builds the toolbar.
        SelectionBanner(selection: model.selection) { model.world.clearSelection() }
        CrowdBanner(crowd: model.crowd, toolbar: model.toolbar)
        Spacer()
        // Two shapes for the same controls, and which one appears is the whole
        // of what folding the phone changes. Flat, the bar floats over the map
        // as it always has. Folded, the base is a surface in its own right and
        // gets a console built for it -- see `TabletopConsole`, which also
        // explains why the tools are still in it.
        //
        // A branch, and it is safe here in a way it would not be around the map:
        // what it swaps is chrome, and chrome has no `RenderCache` to lose. The
        // canvas above the crease is untouched by either arm.
        //
        // No switch on the actions in either arm: the four that raise a sheet
        // rather than edit the map are callbacks on the model, set in
        // `onAppear`, so the menu bar an iPad's keyboard draws raises exactly
        // what these do.
        if hasBase {
          TabletopConsole(toolbar: model.toolbar,
                          routing: model.routing,
                          crowd: model.crowd,
                          settings: model.world.settings,
                          world: model.world,
                          model: model,
                          tint: model.world.settings.accent,
                          onTool: { model.toggleTool($0) },
                          onAction: { model.act($0) },
                          // The console's tool row exists so that folding a
                          // phone costs you no control. When the system has
                          // stood a bar up beside it carrying all seven, that
                          // is already true, and a second copy an inch away is
                          // two places to look at one armed state.
                          showsTools: barEdge == nil)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            // Taking the base rather than sitting at the bottom of it. The
            // banners keep their place just under the crease; everything left
            // over goes to the tiles, which is the point of a surface you put
            // your hands on rather than reach a thumb to.
            .frame(maxHeight: .infinity)
            .transition(.opacity)
        }
      }
    }
    // The app's own bar, for every context the system does not take over.
    //
    // Kept exactly as it was -- the glass capsule and the armed pill that flows
    // between cells -- because on an ordinary phone, an iPad or a Mac nothing
    // about the bar needs to change. Where the system *does* want bars on a
    // side, `nativeBar` below hands it the items instead and this is not built
    // at all; the two are mutually exclusive by construction.
    .overlay(alignment: .bottom) {
      if !model.chrome.hidden, !hasBase, barEdge == nil {
        ToolbarView(state: model.toolbar,
                    tint: model.world.settings.accent,
                    onTool: { model.toggleTool($0) },
                    onAction: { model.act($0) })
          .transition(.opacity)
      }
    }
    // Filling its half, rather than shrinking to the widest thing in it.
    //
    // The `ZStack` this used to sit in centred a narrow child; an arrangement
    // aligns one to the leading edge instead, which slid the whole bar a
    // quarter-screen to the left the first time the map went above the fold.
    // Stated here rather than relied on, because it is the difference between
    // "the bar is centred" and "the bar happens to be as wide as the screen".
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.snappy(duration: 0.2), value: model.notice.message)
  }

  /// The map and the chrome, placed.
  ///
  /// An **overlay** arrangement rather than a split one, because that is what
  /// this app already was: a `ZStack` with the controls floating over the map.
  /// Apple's own description of the style is the spec for what is wanted here
  /// -- with no active division it draws the primary over the secondary, which
  /// is today's layout exactly; with one it puts the primary in the part below
  /// the fold and the secondary in the part above it. So the chrome is the
  /// primary and the map is the secondary, and the tabletop pose falls out
  /// without this file measuring anything.
  ///
  /// That is also why there is no `if folded` here. The arrangement is the same
  /// view in both poses, so folding a phone resizes the two halves rather than
  /// rebuilding them -- which is what keeps `MapCanvas`'s `RenderCache`, and
  /// every wall path in it, alive across the fold.
  ///
  /// The `#available` branch is the one fork, and it forks by OS rather than by
  /// pose: on a given device the same arm runs for the life of the process, so
  /// nothing ever switches identity underneath the canvas. Below 27.1 there are
  /// no folding phones, so the `ZStack` is not a degraded layout -- it is the
  /// only layout that pose can have.
  @ViewBuilder private var layout: some View {
    if #available(iOS 27.1, macOS 27.1, *) {
      ArrangementView {
        chromeLayer
      } secondary: {
        mapLayer
      }
      .arrangementViewStyle(.overlay)
    } else {
      ZStack {
        mapLayer
        chromeLayer
      }
    }
  }

  /// Whether a fold is dividing the screen, as the geometry sees it.
  ///
  /// Nil-safe by construction below 27.1: there is no folding phone there, so
  /// the answer is false rather than unknown.
  private func creased(_ proxy: GeometryProxy) -> Bool {
    guard #available(iOS 27.1, macOS 27.1, *) else { return false }
    // Queried without `.includeInactive`, which is the point: an inactive
    // division is a crease that is not currently dividing anything -- a phone
    // lying flat -- and counting one would put the settings in a base that is
    // not there.
    return !proxy.reservedRegions(kind: .division).isEmpty
  }

  var body: some View {
    // Unconditionally, and that is the point.
    //
    // The system will only stand a bar up on a side for items a navigation
    // container owns, so there has to be one. Wrapping it in an `if` instead
    // would put the *map* under a different ancestor whenever the Duo is opened
    // or closed, which is a change of SwiftUI identity and would throw away
    // `MapCanvas`'s `RenderCache` -- every wall path rebuilt to move a bar. One
    // stack, always, and only the toolbar's contents vary.
    //
    // The bar itself is hidden unless the system is taking it over, so on a
    // phone, an iPad or in any flat pose nothing about the layout moves.
    NavigationStack {
      layout
        // Wherever the system asks for it, folded or not. It used to be
        // suppressed when the console was up, to stop the seven tools appearing
        // twice -- but that left the strip the system had reserved sitting
        // empty beside a console that had duplicated it. The tools come out of
        // the console instead; see `showsTools` below.
        .toolbar { if barEdge != nil, #available(iOS 27.1, *) {
          WalkyToolbar(state: model.toolbar,
                       tint: model.world.settings.accent,
                       onTool: { model.toggleTool($0) },
                       onAction: { model.act($0) })
        } }
        // The iOS 16 spellings, not the 18 ones: this target's floor is 17.
        .toolbar(barEdge == nil ? .hidden : .automatic, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
      // Across the whole screen and across the bend on purpose, unlike the
      // routing spinner: it says *the app* is busy, not *the map* is busy, and
      // a border around only the standing half would say something narrower
      // than it means.
      .overlay {
        if #available(iOS 26.0, macOS 26.0, *) {
          GeneratingBorder(generator: model.describer)
        }
      }
      // A zero-size reader in the background, so asking the question costs the
      // layout nothing. `.division` is the crease; `.occlusion` -- the camera
      // housing -- is the system's problem, not ours, because every view Walky
      // puts near it is one the system already insets.
      .background {
        GeometryReader { proxy in
          Color.clear.onChange(of: creased(proxy), initial: true) { _, now in
            divided = now
          }
        }
      }
      // Zero-size, like the fold reader above it, so asking costs the layout
      // nothing. Below 27.1 it is never built and `barEdge` stays nil, which is
      // the horizontal bar this app has always drawn.
      .background {
        if #available(iOS 27.1, macOS 27.1, *) {
          BarEdgeReader { barEdge = $0 }
        }
      }
    .animation(.snappy(duration: 0.25), value: model.routing.preparing)
    .animation(.snappy(duration: 0.25), value: model.chrome.hidden)
    .animation(.snappy(duration: 0.25), value: divided)
    .animation(.snappy(duration: 0.25), value: barEdge)
    .background(MapRenderer.color(model.world.settings.ground.background))
    .preferredColorScheme(windowScheme)
    .statusBarHidden(model.chrome.hidden)
    .sheet(item: $sheet) { which in
      // The chrome's own lighting, declared rather than inherited -- on a Mac
      // the window chrome follows this, which is why an undeclared style gave
      // Walky a light title bar over a dark map. Stated once here rather than
      // once per sheet, which is the second dividend of `.sheet(item:)`.
      content(of: which).preferredColorScheme(chromeScheme)
    }
    .fileExporter(isPresented: $saving,
                  document: outgoing,
                  contentType: .walkyMap,
                  defaultFilename: outgoingName) { result in
      if case .failure(let error) = result { model.show(error.localizedDescription) }
      outgoing = nil
    }
    .fileImporter(isPresented: $opening,
                  allowedContentTypes: [.walkyMap]) { result in
      switch result {
      case .success(let url): open(url)
      case .failure(let error): model.show(error.localizedDescription)
      }
    }
    .sheet(item: $shared) { map in
      MapShareSheet(url: map.url)
    }
    // A `.walky` tapped in Files, Mail or AirDrop. The same path as the
    // importer, so a map arrives the same way however it got here.
    .onOpenURL { open($0) }
    // Hiding the chrome puts the app in a viewing mode, and disarming is what
    // makes that true rather than merely tidy. It is also the only thing
    // guaranteeing a way back: the tap that restores the controls is delivered
    // to the *tool* when one is armed, so hiding with the brush in hand would
    // paint pedestrians instead of bringing the bar back, and nothing else on
    // screen could undo it. Keyed on the flag rather than done at the two call
    // sites, so the menu item and the Settings switch cannot drift apart.
    .onChange(of: model.chrome.hidden) { _, hidden in
      if hidden { model.world.setTool(nil) }
    }
    .onChange(of: saving) { _, up in model.isCovered = up || opening || sheet != nil }
    .onChange(of: opening) { _, up in model.isCovered = up || saving || sheet != nil }
    .onChange(of: shared?.id) { _, _ in
      model.isCovered = shared != nil || saving || opening || sheet != nil
    }
    .onChange(of: sheet) { was, now in
      // One handler, because the map does not care which sheet is over it.
      model.isCovered = now != nil || saving || opening
      // Dismissed by any route -- Continue, a swipe, anything later -- counts as
      // having seen it. Recording it when the sheet *opens* would mark a thing
      // that had not happened yet; recording it only on Continue would bring it
      // back at the next launch for anyone who swiped it away, which reads as a
      // bug. Being wrong here costs two taps in the menu.
      if was == .welcome { model.world.settings.hasSeenWelcome = true }
    }
    // Kept current only while it can be, which is also the only time anything
    // reads it. Writing it unconditionally would feed this view's own stated
    // scheme back into the setting that decides that scheme.
    .onChange(of: scheme) { _, now in noteSystemScheme(now) }
    .onChange(of: model.world.settings.followsSystem) { _, _ in noteSystemScheme(scheme) }
    .onAppear {
      noteSystemScheme(scheme)
      if router == nil { router = PointerRouter(host: model.world) }
      model.onOpenMap = { opening = true }
      model.onSaveMap = { startSave() }
      model.onSettings = { sheet = .settings }
      model.onWelcome = { sheet = .welcome }
      model.start()
      // `WalkyWorld.init` restores the settings, and `model` is a `@State`
      // initial value, so the flag is already correct by the time this runs.
      if !model.world.settings.hasSeenWelcome { sheet = .welcome }
    }
    .onDisappear { model.stop() }
    .onChange(of: model.world.settings.appearance) { _, _ in model.world.requestRender() }
    // Apple's map is drawn light or dark by the snapshotter, so it has to be
    // retaken when the ground changes under it. `refresh` answers immediately
    // unless the lighting is actually wrong.
    // The map is drawn from the ground's own palette, so a new ground means
    // repainting what this app put on it -- otherwise a crowd placed on
    // Classic stays at full strength on Paper, where it barely reads. See
    // `WalkyWorld.restyle`.
    .onChange(of: model.world.settings.ground.id) { _, _ in
      model.world.restyle(to: model.world.settings.ground)
    }
    .onChange(of: model.world.settings.ground.isLight) { _, light in
      model.basemap.refresh(dark: !light)
    }
    .onChange(of: scenePhase) { _, phase in
      // The port of the web's visibilitychange handler: time spent in the
      // background is not owed, and resuming must not open on a burst of
      // catch-up steps.
      if phase == .active {
        model.start()
      } else {
        model.stop()
        // Nothing shared should outlive the app being put away.
        SharedMap.sweep()
      }
    }
  }

  /// The describe-a-map section, or nothing at all below iOS 26.
  ///
  /// Type-erased on the way out like the other three, and gated here rather
  /// than inside the section because the section's own type is
  /// `@available(iOS 26)` -- there is nothing to construct on an older phone,
  /// not even something that says so.
  private var describeSection: AnyView? {
    guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
    return AnyView(DescribeSceneSection(world: model.world, generator: model.describer,
                                       onStart: { sheet = nil }))
  }

  @ViewBuilder private func content(of which: Sheet) -> some View {
    switch which {
    case .welcome:
      WelcomeSheetView(accent: model.world.settings.accent)
    case .settings:
      SettingsSheetView(settings: model.world.settings,
                        chrome: model.chrome,
                        onChange: { model.world.requestRender() },
                        mapSection: AnyView(
                          RealMapSection(world: model.world, basemap: model.basemap,
                                         importer: model.importer,
                                         locator: model.locator,
                                         dark: model.world.settings.ground.wantsDarkMap)),
                        roomSection: AnyView(
                          RoomScanSection(world: model.world, scanner: model.scanner,
                                          basemap: model.basemap,
                                          locator: model.locator,
                                          dark: model.world.settings.ground.wantsDarkMap,
                                          // Swapping the item on the one sheet
                                          // rather than presenting from inside
                                          // it: `isCovered` stays one fact.
                                          onScan: { sheet = .roomScan })),
                        describeSection: describeSection,
                        // Dismissing Settings first, because the exporter and
                        // the importer are sheets too and iOS will not stack a
                        // second one over the first: without this the file
                        // sheet opens on nothing.
                        fileSection: AnyView(
                          MapFileSection(onOpen: { sheet = nil; opening = true },
                                         onSave: { sheet = nil; startSave() },
                                         onShare: { sheet = nil; startShare() })))
    case .roomScan:
      RoomCaptureContainer(scanner: model.scanner)
    }
  }

  /// The map as it stands, handed to the exporter.
  ///
  /// Taken here rather than in the `document:` argument because that is
  /// evaluated while the sheet is up: with the simulation running, the file
  /// would hold wherever the crowd had walked to by the time somebody picked a
  /// folder, rather than the map they chose to save.
  private func startSave() {
    let core = model.world.captureScenario()
    outgoing = WalkyMapDocument(bytes: MapFile.data(core))
    outgoingName = MapFile.suggestedName(walls: model.world.walls.count,
                                         pedestrians: model.world.agents.count)
    saving = true
  }

  /// The map as a file somebody can be sent.
  ///
  /// Snapshotted at the tap, as saving is, and written to disk here rather than
  /// in the sheet: the share sheet wants a URL, and a name on that URL is what
  /// makes the map arrive as `4 walls.walky` at the other end instead of as an
  /// untitled blob.
  private func startShare() {
    // Whatever the last share left behind, before this one adds to it.
    SharedMap.sweep()
    let core = model.world.captureScenario()
    let name = MapFile.suggestedName(walls: model.world.walls.count,
                                     pedestrians: model.world.agents.count)
    guard let map = SharedMap(core, named: name) else {
      model.show("Could not write the map to share.")
      return
    }
    shared = map
  }

  /// A file, from either sheet or from Files itself.
  ///
  /// The security-scoped dance is not optional: a URL out of the importer or
  /// `onOpenURL` is somebody else's file, and reading it without the access
  /// call works in the Simulator and fails on a device, which is the worst
  /// possible way for it to fail.
  private func open(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let core = try MapFile.read(try Data(contentsOf: url))
      model.world.apply(core)
      model.show("Opened \(url.deletingPathExtension().lastPathComponent).")
    } catch let error as ScenarioLinkError {
      // The codec's own sentence, which is written to be shown: "not a Walky
      // map", "saved by a newer Walky", "larger than Walky can hold".
      model.show(error.message)
    } catch {
      model.show(error.localizedDescription)
    }
  }

  private func noteSystemScheme(_ now: ColorScheme) {
    let settings = model.world.settings
    guard settings.followsSystem else { return }
    let dark = now == .dark
    // @Observable fires on every set, not every change, and this one feeds the
    // ground that feeds the map.
    if settings.systemIsDark != dark {
      settings.systemIsDark = dark
      model.world.requestRender()
    }
  }
}

/// The one thing that can cover the map.
///
/// A single `.sheet(item:)` over this rather than a `.sheet(isPresented:)` per
/// Bool. Two of those do both work on iOS 17 -- the old bug where the second
/// one silently lost is long fixed -- but `model.isCovered` is a fact about the
/// *map* being covered and not about any one sheet, and with two Bools it has
/// to be maintained by two handlers that must never disagree. With one optional
/// it is `now != nil`, once.
private enum Sheet: String, Identifiable {
  case welcome, settings, roomScan
  var id: String { rawValue }
}

/// What the system says about where bars belong.
///
/// Its own view because `@Environment(\.toolbarVerticalEdge)` is
/// `@available(iOS 27.1, *)` and a stored property cannot be declared
/// conditionally -- the same shape the fold reader uses for the same reason.
///
/// Walky has no navigation container in its main scene and so no bars for the
/// system to place, which sounds like it should make this useless. It does not:
/// the UIKit counterpart is a *trait*, and its header says it "reflects the
/// system's preferred edge regardless of whether a vertical bar is currently
/// visible". Nil means this context never uses one.
@available(iOS 27.1, macOS 27.1, *)
private struct BarEdgeReader: View {
  @Environment(\.toolbarVerticalEdge) private var edge
  let onChange: (HorizontalEdge?) -> Void

  var body: some View {
    Color.clear.onChange(of: edge, initial: true) { _, now in onChange(now) }
  }
}
