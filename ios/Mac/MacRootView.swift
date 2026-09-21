import SwiftUI
import WalkyCore

/// The window's contents: the map, the surface that takes the mouse, and the
/// same floating bar the phone wears.
///
/// A flat `ZStack` for the reason `RootView` is one -- the canvas reads only
/// `redraw.version` and the bar only `toolbar.*`, and nesting them would make
/// arming a tool repaint the map.
///
/// What is deliberately *not* here: the sheets. A Mac keeps its preferences in
/// a Settings window on Cmd-, and its file commands in the File menu, so the
/// settings sheet, the share sheet and the room scanner -- which has no camera
/// to use here anyway -- have no place in the window. What is left is the map
/// and the tools over it.
struct MacRootView: View {
  let model: AppModel
  @Bindable private var shell = MacShell.shared
  @State private var router: PointerRouter?
  @Environment(\.colorScheme) private var scheme
  /// The supported way to raise the `Settings` scene from code, which is what
  /// the bar's own Settings button has to do -- `SettingsLink` is a *button*
  /// and cannot be triggered from the toolbar's action closure.
  @Environment(\.openSettings) private var openSettings

  /// What the window states. The ground rather than the appearance: on the
  /// Paper ground a dark window would put light chrome over an almost-white
  /// map. On Automatic the two agree by construction.
  private var windowScheme: ColorScheme? {
    let settings = model.world.settings
    guard !settings.followsSystem else { return nil }
    return settings.ground.isLight ? .light : .dark
  }

  var body: some View {
    ZStack {
      MapCanvas(world: model.world, redraw: model.redraw, basemap: model.basemap,
                stats: { DebugStats(fps: model.fps, tps: model.tps) })

      if let router {
        // `.ignoresSafeArea()` for the same reason `MapCanvas` has it, and it
        // has to be *both*: this window hides its title bar, so the safe area
        // still insets by its height. Without it the pointer surface sat that
        // far below the map it is pointing at, and everything drawn landed a
        // title bar's height off the cursor.
        MacCanvas(router: router, onCommand: { model.pressed($0) })
          .ignoresSafeArea()
      }

      // Above the map and the pointer surface, below the chrome -- it is not a
      // control, and a clean capture still wants to say when the map is not
      // finished being drawn.
      GeneratingBorder(generator: model.describer)

      if !model.chrome.hidden {
        VStack {
          if let notice = model.notice.message {
            Text(notice)
              .font(.footnote)
              .padding(.horizontal, 14).padding(.vertical, 8)
              .background(.ultraThinMaterial, in: Capsule())
              .transition(.move(edge: .top).combined(with: .opacity))
          }
          // Child views on purpose -- see CrowdBanner. Neither count may be
          // read in this body, which also builds the toolbar.
          SelectionBanner(selection: model.selection) { model.world.clearSelection() }
          CrowdBanner(crowd: model.crowd, toolbar: model.toolbar)
          Spacer()
          // No switch here any more: the four that are a window or a sheet
          // rather than an edit are callbacks on the model, set in `onAppear`,
          // so the menu bar raises exactly what this bar does.
          ToolbarView(state: model.toolbar,
                      tint: model.world.settings.accent,
                      onTool: { model.toggleTool($0) },
                      onAction: { model.act($0) })
        }
        .animation(.snappy(duration: 0.2), value: model.notice.message)
        .transition(.opacity)
      }
    }
    .overlay {
      RoutingOverlay(showing: model.routing.preparing,
                     tint: model.world.settings.accent)
    }
    .animation(.snappy(duration: 0.25), value: model.routing.preparing)
    .animation(.snappy(duration: 0.25), value: model.chrome.hidden)
    .background(MapRenderer.color(model.world.settings.ground.background))
    .preferredColorScheme(windowScheme)
    .frame(minWidth: 520, minHeight: 400)
    .sheet(isPresented: $shell.welcome) {
      WelcomeSheetView(accent: model.world.settings.accent)
        .frame(minWidth: 420, minHeight: 520)
    }
    .fileExporter(isPresented: $shell.saving,
                  document: shell.outgoing,
                  contentType: .walkyMap,
                  defaultFilename: shell.outgoingName) { result in
      if case .failure(let error) = result { model.show(error.localizedDescription) }
      shell.outgoing = nil
    }
    .fileImporter(isPresented: $shell.opening,
                  allowedContentTypes: [.walkyMap]) { result in
      switch result {
      case .success(let url): shell.open(url, into: model)
      case .failure(let error): model.show(error.localizedDescription)
      }
    }
    // A `.walky` opened from the Finder, which is how a map arrives here when
    // the app is already running.
    .onOpenURL { shell.open($0, into: model) }
    // Hiding the chrome puts the app in a viewing mode, and disarming is what
    // makes that true rather than merely tidy -- see the same handler in
    // `RootView`, which explains why this is keyed on the flag.
    .onChange(of: model.chrome.hidden) { _, hidden in
      if hidden { model.world.setTool(nil) }
    }
    .onChange(of: shell.isCovered) { _, covered in model.isCovered = covered }
    .onChange(of: scheme) { _, now in noteSystemScheme(now) }
    .onChange(of: model.world.settings.followsSystem) { _, _ in noteSystemScheme(scheme) }
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
    .onAppear {
      noteSystemScheme(scheme)
      if router == nil { router = PointerRouter(host: model.world) }
      model.onOpenMap = { shell.startOpen() }
      model.onSaveMap = { shell.startSave(model) }
      model.onSettings = { openSettings() }
      model.onWelcome = { shell.welcome = true }
      model.start()
      // `WalkyWorld.init` restores the settings, so the flag is already correct
      // by the time this runs.
      if !model.world.settings.hasSeenWelcome { shell.welcome = true }
    }
    .onDisappear { model.stop() }
    .onChange(of: shell.welcome) { was, now in
      // Dismissed by any route counts as having seen it; see `RootView`.
      if was && !now { model.world.settings.hasSeenWelcome = true }
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
