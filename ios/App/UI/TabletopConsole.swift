import SwiftUI
import WalkyCore

/// The base of a folded phone, as a console.
///
/// Tabletop is the pose where you have finished drawing and set the phone
/// down: half the screen stands up with the map on it, half lies flat under
/// your hands. So the flat half is a remote for a simulation that is already
/// running, not a toolbar that happens to be lower. Play is the hero, the
/// walking speed sits directly beneath it, and the switches that change what
/// you can *see* get real buttons instead of four taps into a sheet.
///
/// The drawing tools are still here, in one subordinate row, and that is a
/// requirement rather than a courtesy: Apple asks that an app "provide access
/// to the same controls and content regardless of how someone holds or views
/// the device". Demoting them costs nothing and buys something -- the row has
/// space for all seven, so `.generator` and `.measure` get a cell at last.
/// On a phone held flat they have none, because eight 44pt cells do not fit a
/// 375pt bar; that is `Command.barTools` taking the first five.
///
/// **Every tile is its own `View` taking an observable object, never a value.**
/// This is the rule the comment at the top of `RootView` and the one in
/// `CrowdBanner` both exist to state: reading `crowd.count` in a body that also
/// builds the toolbar re-initialises the map, the touch surface *and* the bar
/// on every brush point, which is what made play/pause miss every second or
/// third press. A console is a dozen controls reading a dozen properties, so it
/// is exactly the shape of thing that would bring that bug back wholesale.
struct TabletopConsole: View {
  let toolbar: ToolbarState
  let routing: Routing
  let crowd: Crowd
  let settings: WalkyCore.Settings
  let world: WalkyWorld
  /// Not `@Observable`, and taken anyway: the readout polls it on a timer
  /// rather than observing it. See `ConsoleReadout`.
  let model: AppModel
  let tint: Accent
  let onTool: (ToolId) -> Void
  let onAction: (ToolbarAction) -> Void

  /// The namespace the armed pill travels in, as in the bar.
  @Namespace private var glass

  var body: some View {
    // The console's own region, measured by the console. Nothing further up
    // the tree learns the size, so nothing further up is invalidated by it.
    GeometryReader { proxy in
      content(size: proxy.size)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  @ViewBuilder private func content(size: CGSize) -> some View {
    // Which way the fold cut. A horizontal crease leaves a wide, short base
    // under your hands -- the laptop pose these tiles were drawn for. A
    // vertical one leaves a tall column beside the map, which is the same
    // controls in a different shape, not a different set of controls.
    let column = size.height > size.width
    VStack(spacing: 10) {
      // The only part that is laid out twice. Everything below adapts by
      // itself, from the width it is handed.
      if column {
        play
        HStack(spacing: 10) {
          step.frame(width: 104)
          ConsoleSpeed(settings: settings, world: world, fillsHeight: true)
        }
      } else {
        HStack(spacing: 10) {
          play
          step.frame(width: 112)
        }
        ConsoleSpeed(settings: settings, world: world)
      }
      toggles(perRow: perRow(size.width, tile: 92, spacing: 6, of: Self.viewToggles.count))
      ConsoleReadout(crowd: crowd, model: model, world: world)
      toolRow(perRow: perRow(size.width, tile: 72, spacing: 4, of: Self.toolCells.count))
    }
  }

  /// How many tiles of at least `tile` points fit across `width`.
  ///
  /// The arithmetic `LazyVGrid`'s `.adaptive` does, done here instead so that
  /// the *rows* can be built explicitly. A grid pins every cell to a column, so
  /// a five-item run in three columns leaves the last row two thirds full with
  /// a third of it empty; rows of `maxWidth: .infinity` cells divide whatever
  /// they are given, so the same run ends three-across then two halves.
  private func perRow(_ width: CGFloat, tile: CGFloat, spacing: CGFloat, of count: Int) -> Int {
    guard width > 0 else { return count }
    let fits = Int((width + spacing) / (tile + spacing))
    return max(1, min(count, fits))
  }

  /// `items` in rows of `size`, the last one short if it has to be.
  private func rows<T>(_ items: [T], _ size: Int) -> [[T]] {
    stride(from: 0, to: items.count, by: size).map {
      Array(items[$0..<Swift.min($0 + size, items.count)])
    }
  }

  private var play: some View {
    ConsolePlayTile(toolbar: toolbar, routing: routing, tint: tint) { onAction(.start) }
      .frame(maxWidth: .infinity)
  }

  private var step: some View {
    ConsoleStepTile(toolbar: toolbar, routing: routing, onStep: { model.step(6) })
  }

  /// The five switches worth flipping while the crowd is walking.
  ///
  /// A table rather than five call sites, so the rows can be chunked from it.
  /// Deliberately **not** `ToggleSetting` from `Scenario`: that one is the
  /// share link's wire format, where "the position is the format" -- it has no
  /// `showBasemap`, which never travels in a link, and carries three nothing
  /// here exposes. Reordering it to suit a console would mis-decode every link
  /// ever made.
  private struct ViewToggle: Identifiable {
    let title: String
    let icon: String
    let keyPath: ReferenceWritableKeyPath<WalkyCore.Settings, Bool>
    var id: String { title }
  }

  private static let viewToggles: [ViewToggle] = [
    .init(title: "Hulls", icon: "hexagon", keyPath: \.showConvexHull),
    .init(title: "Route", icon: "arrow.triangle.turn.up.right.diamond",
          keyPath: \.showLineToTarget),
    .init(title: "Space", icon: "circle.dashed", keyPath: \.showPersonalSpace),
    .init(title: "Debug", icon: "speedometer", keyPath: \.showDebug),
    .init(title: "Map", icon: "map", keyPath: \.showBasemap),
  ]

  /// The switches, in rows that fill.
  ///
  /// Each tile is its own view over the same `Settings` object. `@Observable`
  /// tracks per property, so flipping Debug invalidates the Debug tile and
  /// nothing else -- not the four beside it, and not this body.
  private func toggles(perRow: Int) -> some View {
    VStack(spacing: 6) {
      ForEach(Array(rows(Self.viewToggles, perRow).enumerated()), id: \.offset) { _, row in
        HStack(spacing: 6) {
          ForEach(row) { toggle in
            ConsoleToggleTile(settings: settings, world: world, tint: tint,
                              title: toggle.title, icon: toggle.icon,
                              keyPath: toggle.keyPath)
              .frame(maxWidth: .infinity)
          }
        }
      }
    }
  }

  /// A cell in the tool row: one of the seven, or the menu that ends it.
  private enum ToolCell: Identifiable {
    case tool(ToolId)
    case menu
    var id: String {
      switch self {
      case .tool(let id): id.rawValue
      case .menu: "menu"
      }
    }
  }

  private static let toolCells: [ToolCell] = Command.tools.map(ToolCell.tool) + [.menu]

  /// All seven tools, and the menu that holds everything else.
  ///
  /// Smaller than the tiles above on purpose. This row is how you get back to
  /// drawing, not what you came to this surface to do, and a row of seven
  /// full-size tiles would compete with Play for the eye.
  ///
  /// `…` is last in the sequence, so it is last in whichever row the width
  /// leaves it in.
  private func toolRow(perRow: Int) -> some View {
    VStack(spacing: 4) {
      ForEach(Array(rows(Self.toolCells, perRow).enumerated()), id: \.offset) { _, row in
        HStack(spacing: 4) {
          ForEach(row) { cell in
            switch cell {
            case .tool(let id):
              ConsoleToolCell(toolbar: toolbar, id: id, tint: tint, in: glass) { onTool(id) }
                .frame(maxWidth: .infinity)
            case .menu:
              menuCell
            }
          }
        }
      }
    }
  }

  private var menuCell: some View {
    Menu {
      // Without the two modal tools: they have cells of their own here.
      ToolbarMenuItems(state: toolbar, onTool: onTool, onAction: onAction,
                       showsModalTools: false)
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.primary)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        // A `.frame` is a layout box, not a hit box -- see `ToolbarView.icon`.
        .contentShape(Rectangle())
    }
    // `.primary` is a hierarchical level, not a colour, and a `Menu` with the
    // automatic style installs the accent as its base. See `ToolbarView`.
    .buttonStyle(.plain)
    .accessibilityLabel("More")
  }
}

// MARK: - Tiles

/// Play, or pause, or neither while the first navigation graph is built.
///
/// That third state is not decoration. The first press goes through
/// `AppModel.prepareThenRun`, which has to wait for `world.navReady()` before
/// anything moves; without a spinner here the hero tile of the whole surface
/// looks like it ignored the press.
private struct ConsolePlayTile: View {
  let toolbar: ToolbarState
  let routing: Routing
  let tint: Accent
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        if routing.preparing {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: toolbar.running ? "pause.fill" : "play.fill")
            .font(.system(size: 30, weight: .medium))
        }
        Text(label).font(.headline)
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 84, maxHeight: .infinity)
      .background(MapRenderer.color(tint.color).opacity(0.28),
                  in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .animation(.snappy(duration: 0.25), value: toolbar.running)
    .animation(.snappy(duration: 0.25), value: routing.preparing)
  }

  private var label: String {
    if routing.preparing { return "Thinking…" }
    return toolbar.running ? "Pause" : "Play"
  }
}

/// One nudge of the simulation, for a crowd that is standing still.
///
/// A tap is **six** ticks, not one. One tick is 1/60th of a second of
/// simulated time and moves a walker about a fifth of their own width -- a
/// press that appears to do nothing, which reads as a broken button. Six is a
/// tenth of a second: enough that the crowd visibly shifts, little enough that
/// you can walk a jam forward a press at a time and watch what it does.
///
/// Disabled while running, because "step" has no meaning against something
/// already stepping sixty times a second.
private struct ConsoleStepTile: View {
  let toolbar: ToolbarState
  let routing: Routing
  let onStep: () -> Void

  var body: some View {
    Button(action: onStep) {
      VStack(spacing: 3) {
        Image(systemName: "forward.frame.fill").font(.system(size: 24, weight: .medium))
        Text("Step").font(.caption2)
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 84, maxHeight: .infinity)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Disabled rather than hidden: a control that vanishes is a layout that
    // jumps, and greying it is also what says stepping is the paused-mode tool.
    .disabled(toolbar.running || routing.preparing)
    .opacity(toolbar.running || routing.preparing ? 0.4 : 1)
    .accessibilityLabel("Step forward")
  }
}

/// How fast the crowd walks.
///
/// `settings.speed` is metres per second, not a time scale: turning it up
/// makes people walk faster, it does not fast-forward the simulation. The
/// label says the unit for exactly that reason.
///
/// Its own view over `Settings`, which is what keeps a drag -- one write per
/// frame while a finger is down -- inside this tile instead of in the body
/// that builds the toolbar.
private struct ConsoleSpeed: View {
  @Bindable var settings: WalkyCore.Settings
  let world: WalkyWorld
  /// Whether to grow to the height on offer.
  ///
  /// True only in the column, where this sits beside Step and two tiles of
  /// different heights on one line read as a mistake. Set from the caller and
  /// applied *before* the background: a `.frame` wrapped around the finished
  /// tile would grow the layout box and leave the drawn tile its old size,
  /// centred in the space -- which is the bug this fixes, not the fix.
  ///
  /// False in the base, where Speed is a row of its own under the transport
  /// and growing would take the height the hero tile is there to have.
  var fillsHeight = false

  var body: some View {
    VStack(spacing: 2) {
      HStack {
        Text("Walking speed").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(settings.speed, format: .number.precision(.fractionLength(2)))
          .font(.caption.monospacedDigit())
        Text("m/s").font(.caption).foregroundStyle(.secondary)
      }
      Slider(value: $settings.speed, in: 0.4...3, step: 0.05)
        .tint(.primary)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxHeight: fillsHeight ? .infinity : nil)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    // A running simulation picks the new speed up on its own -- it is read in
    // `stepOnce`. A stopped one draws it: `MapRenderer.walkyLine` puts the
    // figure in the debug overlay, so with Debug on and the crowd paused the
    // number on the map is stale until something asks for a frame.
    .onChange(of: settings.speed) { _, _ in world.requestRender() }
    .accessibilityElement(children: .combine)
  }
}

/// One of the five switches that change what the map draws.
///
/// Generic over the key path so the five are one view rather than five, and
/// so each reads exactly one property: `@Observable` tracks per property, so
/// flipping one of these invalidates one tile.
private struct ConsoleToggleTile: View {
  @Bindable var settings: WalkyCore.Settings
  let world: WalkyWorld
  let tint: Accent
  let title: String
  let icon: String
  let keyPath: ReferenceWritableKeyPath<WalkyCore.Settings, Bool>

  var body: some View {
    let on = settings[keyPath: keyPath]
    Button {
      settings[keyPath: keyPath].toggle()
      // `repaintingTheMap` covers three of these five and misses
      // `showLineToTarget` and `showBasemap`, which is invisible in a sheet
      // that is dismissed before you look at the map again -- and very visible
      // here, a thumb's width from what it draws. Asking for a frame on all
      // five is one call and cannot drift.
      world.requestRender()
    } label: {
      VStack(spacing: 3) {
        Image(systemName: icon).font(.system(size: 20, weight: .medium))
        Text(title).font(.caption2)
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 58, maxHeight: .infinity)
      .background(on ? AnyShapeStyle(MapRenderer.color(tint.color).opacity(0.28))
                     : AnyShapeStyle(.quaternary),
                  in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(on ? [.isSelected] : [])
    .animation(.snappy(duration: 0.2), value: on)
  }
}

/// What the simulation is doing, in three numbers.
///
/// The headcount is observed -- `Crowd` is a shell that exists for exactly
/// this. The other two are **polled**, once a second, because `AppModel` is
/// deliberately not `@Observable`: it carries `fps` and `tps`, and a view that
/// observed them would be rebuilt by the thing it is reporting on. A
/// `TimelineView` here reads them on its own schedule, inside this leaf, which
/// is the cheapest honest way to show a number that changes every frame.
private struct ConsoleReadout: View {
  let crowd: Crowd
  let model: AppModel
  let world: WalkyWorld

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      HStack {
        stat(crowd.count.formatted(), "walkers")
        Spacer()
        stat(model.fps.formatted(), "fps")
        Spacer()
        stat(world.simTicks.formatted(), "ticks")
      }
      .font(.caption.monospacedDigit())
      .padding(.horizontal, 6)
    }
    .accessibilityElement(children: .combine)
  }

  private func stat(_ value: String, _ unit: String) -> some View {
    HStack(spacing: 4) {
      Text(value)
      Text(unit).foregroundStyle(.secondary)
    }
  }
}

/// One tool, as a small cell in the demoted row.
///
/// Wears the same travelling pill the bar does -- `armed(_:_:in:)`, shared
/// from `ToolbarView` -- so a tool armed here looks armed the way it does
/// anywhere else in the app.
private struct ConsoleToolCell: View {
  let toolbar: ToolbarState
  let id: ToolId
  let tint: Accent
  let namespace: Namespace.ID
  let onTap: () -> Void

  init(toolbar: ToolbarState, id: ToolId, tint: Accent,
       in namespace: Namespace.ID, onTap: @escaping () -> Void) {
    self.toolbar = toolbar
    self.id = id
    self.tint = tint
    self.namespace = namespace
    self.onTap = onTap
  }

  var body: some View {
    let command = Command.of(id)
    let armed = toolbar.selected == id
    return Button(action: onTap) {
      Image(systemName: command?.symbol ?? "questionmark")
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.primary)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .armed(armed, tint.color, in: namespace)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(command?.title ?? "")
    .accessibilityAddTraits(armed ? [.isSelected] : [])
    .animation(.snappy(duration: 0.32, extraBounce: 0.08), value: armed)
  }
}
