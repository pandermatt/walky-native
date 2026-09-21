import SwiftUI
import WalkyCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Built from `NumericSetting`, which is the same table `Settings.clamp()` uses
/// on a map arriving from a link. 601 lines of DOM in the web app; the one
/// place the port gets smaller.
/// The platform's own image type, for the one thing in this file that has to
/// be drawn rather than described.
#if os(macOS)
private typealias SwatchImage = NSImage
#else
private typealias SwatchImage = UIImage
#endif

struct SettingsSheetView: View {
  /// Qualified, because on a Mac `Settings` is also SwiftUI's preferences
  /// *scene* -- see `WalkyMacApp`, which builds one of those around this view.
  @Bindable var settings: WalkyCore.Settings
  /// Not a `Settings` property, and so not persisted -- see `Chrome`. It sits in
  /// this sheet anyway because that is where somebody setting up a capture is
  /// already looking, and because the section around it is doing the real work:
  /// explaining that the recorder is the system's, not Walky's.
  @Bindable var chrome: Chrome
  let onChange: () -> Void
  /// iOS only, and nil is a legitimate state: the map section is absent rather
  /// than disabled where there is nothing to import into.
  var mapSection: AnyView?
  /// Likewise, and for a sharper reason: scanning needs a LiDAR camera, so on
  /// a device without one the section decides for itself what is left to offer.
  /// Type-erased like the one above, which also keeps this `Form` inside the
  /// type checker's budget -- see `groundSection`.
  var roomSection: AnyView?
  /// Describing one in words. Nil below iOS 26 and on a phone Apple
  /// Intelligence does not run on -- though the section itself decides what is
  /// left to offer when only the *model* is missing, the way the room section
  /// does without a LiDAR camera.
  var describeSection: AnyView?
  /// Saving and opening a `.walky`. Type-erased for the same two reasons, and
  /// first of the three: opening a map you already have is the shortest way to
  /// get one.
  var fileSection: AnyView?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        // Five rows rather than thirteen sections.
        //
        // What was here before was one scroll of everything: four sliders, three
        // importers, a file section, four separate takes on how the app looks,
        // two lists of toggles and an about box -- and no two of them at the
        // same altitude. The three importers are one question ("where does a
        // map come from"), Appearance/Ground/Accent/App icon are one question
        // ("what does it look like"), and neither was findable next to a
        // brush-size slider.
        //
        // Grouped by the question rather than by the control, which is also why
        // "Pedestrians" and "Drawing" became Crowd and Tools: speed and body
        // size describe the model, brush and border describe the things you
        // draw with, and the old split had `brushSize` filed under the crowd it
        // paints rather than the brush it is.
        Section {
          page("Maps", "map", mapsPage)
          page("Crowd", "figure.walk", CrowdPage(settings: settings))
          page("Appearance", "paintpalette", appearancePage)
          page("Show", "eye", ShowPage(settings: settings, chrome: chrome))
          // Last in the group because it is the one row that is reference
          // rather than setting: nothing on the page can be changed.
          page("Keyboard shortcuts", "keyboard", KeyboardShortcutsPage())
        }

        Section {
          Text(Self.about)
            .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Walky") }
      }
      .navigationTitle("Settings")
      // A Mac has no navigation bar to size the title in; on this platform the
      // same form is the content of the Settings window.
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItemGroup(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .repaintingTheMap(settings, onChange)
    }
  }

  // MARK: - The pages

  /// Where a map comes from, and what to do with the one you have.
  ///
  /// A page each rather than four sections stacked, and the reason is the
  /// settings rather than the length: importing owns an area and a scale,
  /// scanning owns the furniture switch and a role per doorway, and stacked
  /// together nothing said which slider belonged to which source. A page
  /// boundary says it.
  ///
  /// The row is also where "Describe a map" wears its BETA, so it is met
  /// before the text field rather than after.
  @ViewBuilder private var mapsPage: some View {
    Form {
      Section {
        if let fileSection { page("Map file", "doc", Form { fileSection }) }
        if let mapSection { page("Real map", "map", Form { mapSection }) }
        if let roomSection { page("Your room", "ruler", Form { roomSection }) }
        if let describeSection {
          page("Describe a map", "sparkles", Form { describeSection }, beta: true)
        }
      } footer: {
        Text("Four ways to get a map: open one you have, import a real place, "
           + "scan a room, or describe one.")
      }
    }
  }

  private var appearancePage: some View { AppearancePage(settings: settings) }

  /// One row into one page. `Label` rather than a bare title so the list is
  /// scannable by shape as well as by word -- five words in a column read as a
  /// wall, five icons do not.
  private func page(_ title: String, _ icon: String,
                    _ destination: some View, beta: Bool = false) -> some View {
    NavigationLink {
      destination
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    } label: {
      Label {
        HStack(spacing: 6) {
          Text(title)
          if beta { BetaTag() }
        }
      } icon: {
        Image(systemName: icon)
      }
    }
  }


  // Two lines each, on the narrowest phone this runs on -- so about ninety
  // characters, and every one of these used to be three or four times that.
  // A settings sheet is scanned, not read: what survives the cut is the thing
  // the control cannot say for itself, and the provenance line, which is the
  // one reason this app exists. What went was everything a reader would learn
  // faster by flipping the switch.
  // It used to argue for Orange by calling it the colour a route to a goal is
  // drawn in, which stopped being visible the moment Route to goal defaulted
  // off. A footer may not point at something the reader cannot see -- and the
  // shorter it is, the less chance it gets to.
  // Both halves are load-bearing and neither is obvious. The escape route,
  // because the switch hides the very bar you would look for to undo it with;
  // and Control Centre, because the absence of a record button in a section
  // called Recording is otherwise just a gap.
  private static let recordingFooter: String =
    "Hides the bar and status bar. Tap the map to restore; record from Control "
    + "Centre."

  private static let about: String =
    "A pedestrian simulator. Draw walls, mark a goal, paint a crowd, and watch "
    + "them go."

  private func slider(_ setting: NumericSetting, format: String = "%.0f",
                      warning: String? = nil) -> some View {
    let r = setting.range
    return VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(setting.label)
        Spacer()
        Text(String(format: format, settings[keyPath: setting.keyPath]))
          .foregroundStyle(.secondary).monospacedDigit()
      }
      Slider(value: Binding(get: { settings[keyPath: setting.keyPath] },
                            set: { settings[keyPath: setting.keyPath] = $0 }),
             in: r.min...r.max, step: r.step)
      if let warning {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// What the brush actually costs at its current size.
  ///
  /// A number rather than a caution, because the number is the surprising part:
  /// the brush is n across, so a *tap* drops n x n pedestrians, and a drag
  /// paints continuously. At 14 that is 196 a tap, and a crowd big enough to
  /// slow the tick arrives in about a second of dragging without it ever looking
  /// like a lot of taps.
  private var brushWarning: String? {
    let n = Int(settings.brushSize)
    guard n > 9 else { return nil }
    return "\(n) x \(n) — that is \(n * n) pedestrians a tap, more while you drag."
  }
}

/// The settings that change what the map *looks* like, so the map has to be
/// told when one of them moves.
///
/// A modifier rather than a list of `onChange`s in one view's body, because
/// there are two bodies now: the phone's sheet and the Mac's Settings window
/// are laid out differently and both write the same object.
extension View {
  func repaintingTheMap(_ settings: WalkyCore.Settings,
                        _ onChange: @escaping () -> Void) -> some View {
    self
      .onChange(of: settings.pedestrianRadius) { _, _ in onChange() }
      .onChange(of: settings.personalSpace) { _, _ in onChange() }
      .onChange(of: settings.showConvexHull) { _, _ in onChange() }
      // Both read by `MapRenderer` and both missing here until now. A sheet
      // hid it: dismissing one sets `isCovered` back to false, which asks for
      // a frame anyway. A Mac's Settings is a window and covers nothing, so
      // there the map simply did not change until the next edit.
      .onChange(of: settings.showLineToTarget) { _, _ in onChange() }
      .onChange(of: settings.showBasemap) { _, _ in onChange() }
      .onChange(of: settings.showPersonalSpace) { _, _ in onChange() }
      .onChange(of: settings.showDebug) { _, _ in onChange() }
      .onChange(of: settings.groundId) { _, _ in onChange() }
      // Appearance moves the ground now, not just the chrome.
      .onChange(of: settings.appearance) { _, _ in onChange() }
  }
}

/// What the app looks like: the scheme, the ground the crowd walks on, and the
/// accent behind the tool in your hand.
///
/// Its own type for the two reasons the other pages are -- each is a
/// type-checking unit of its own, and it takes only the object it writes -- and
/// now for a third: a Mac lays these pages out as *tabs* rather than as a
/// drill-down list, so each one has to be something a `TabView` can be handed.
struct AppearancePage: View {
  @Bindable var settings: WalkyCore.Settings

  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Appearance", selection: $settings.appearance) {
          ForEach(Appearance.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      groundSection
      accentSection
      // Alternate icons are an iOS affordance: a Mac app has one icon, and it
      // is in the Dock.
      #if os(iOS)
      AppIconSection(accent: settings.accent.color)
      #endif
    }
  }

  /// Rows rather than a Picker. Four grounds with a colour swatch each is a
  /// thing to look at, not a value to pick from a popup -- and the menu style
  /// hid all four behind a tap that showed the answer only after you had
  /// already chosen.
  ///
  /// The ground is a separate choice from the appearance on purpose. #1E1E1E is
  /// not a preference -- `palette.ts` derives it from the 2016 original's
  /// `Color.DARK_GRAY.darker().darker()` -- so "light mode" cannot simply mean
  /// inverting the map. Picking a ground is picking what the crowd walks on;
  /// picking an appearance lights the chrome around it.
  ///
  /// Out of `body` because the type checker gave up on the Form once both this
  /// and the accent section were inline: "unable to type-check this expression
  /// in reasonable time".
  @ViewBuilder private var groundSection: some View {
    Section {
      automaticRow
      ForEach(Grounds.all) { ground in groundRow(ground) }
    } header: { Text("Ground") } footer: {
      Text(Self.groundFooter)
    }
  }


  /// The row that defers to Appearance, and the default.
  ///
  /// A row rather than a hidden state, because "automatic until you touch it"
  /// with no way back is a trap: once a ground is picked outright there has to
  /// be something to pick to undo it.
  private var automaticRow: some View {
    let chosen = settings.groundId == Grounds.automatic
    return Button {
      settings.groundId = Grounds.automatic
    } label: {
      HStack(spacing: 12) {
        // The swatch shows what it currently resolves to, so the row says
        // which ground rather than only that something decides.
        groundSwatch(settings.ground)
        VStack(alignment: .leading, spacing: 1) {
          Text("Automatic").foregroundStyle(.primary)
          Text("Follows Appearance").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if chosen {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(MapRenderer.color(settings.accent.color))
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// One ground row. Its own function because the nested overlays are what
  /// pushed the Form past the type checker's budget.
  private func groundRow(_ ground: Ground) -> some View {
    let chosen = settings.groundId == ground.id
    return Button {
      settings.groundId = ground.id
    } label: {
      HStack(spacing: 12) {
        groundSwatch(ground)
        Text(ground.label).foregroundStyle(.primary)
        Spacer()
        if chosen {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(MapRenderer.color(settings.accent.color))
        }
      }
      // The same trap as the toolbar cells: a `.plain` Button is hit-tested
      // against its label's *drawn* content, and a row that is mostly Spacer
      // has almost none -- so the tap landed on nothing. The frame is a layout
      // box; this is the hit box.
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// A pedestrian at the size it would be on that ground: the swatch shows what
  /// the ink does, not just the paint.
  private func groundSwatch(_ ground: Ground) -> some View {
    let dot = Circle()
      .fill(MapRenderer.color(ORANGE))
      .overlay(Circle().strokeBorder(MapRenderer.color(ground.ink), lineWidth: 1.5))
      .frame(width: 13, height: 13)
    return RoundedRectangle(cornerRadius: 5)
      .fill(MapRenderer.color(ground.background))
      .overlay(dot)
      .overlay(RoundedRectangle(cornerRadius: 5)
        .strokeBorder(.primary.opacity(0.18), lineWidth: 1))
      .frame(width: 40, height: 28)
  }

  /// A palette Picker, not a row of tappable circles.
  ///
  /// The hand-built row looked exactly right and set nothing: inside a Form row
  /// a bare `.onTapGesture` never fired, and neither `.plain` nor `.borderless`
  /// Buttons did either -- the row swallows the tap. Only reading the app's own
  /// preferences plist showed the key was never being written at all.
  /// `.palette` is the system control for exactly this -- a handful of choices
  /// small enough to be shown rather than named -- so hit-testing stops being
  /// ours to get wrong.
  @ViewBuilder private var accentSection: some View {
    Section {
      #if os(macOS)
      // Buttons, not the palette Picker the phone uses.
      //
      // A palette Picker on a Mac is drawn as a segmented control: six swatches
      // in a grey pill with hairline dividers between them and a blue focus box
      // round the chosen one. It reads as a toolbar somebody shrank, and the
      // dividers make the colours look like *segments* rather than like paint.
      // A Mac is also the platform where a Button in a Form does work -- the
      // hit-testing trouble noted below is the phone's -- so the row can be
      // what it looks like: six circles of colour, the chosen one ringed.
      HStack(spacing: 12) {
        ForEach(Accents.all) { accent in
          Button { settings.accentId = accent.id } label: {
            Circle()
              .fill(MapRenderer.color(accent.color))
              .frame(width: 22, height: 22)
              .overlay {
                Circle()
                  .strokeBorder(.primary,
                                lineWidth: settings.accentId == accent.id ? 2.5 : 0)
                  .padding(-3)
              }
          }
          .buttonStyle(.plain)
          .help(accent.label)
          .accessibilityLabel(accent.label)
        }
        Spacer()
      }
      .padding(.vertical, 4)
      #else
      Picker("Accent", selection: $settings.accentId) {
        ForEach(Accents.all) { accent in
          // A drawn dot rather than `Image(systemName: "circle.fill")`. A
          // palette Picker colours its labels itself and ignores both `.tint`
          // and `.foregroundStyle` on them, so every swatch came out white --
          // six identical circles and no way to tell which colour was which.
          // An `.alwaysOriginal` image is not template art, so nothing recolours
          // it.
          Self.swatch(accent.color)
            .accessibilityLabel(accent.label)
            .tag(accent.id)
        }
      }
      .pickerStyle(.palette)
      .paletteSelectionEffect(.automatic)
      .labelsHidden()
      #endif
    } header: { Text("Accent") } footer: {
      Text(Self.accentFooter)
    }
  }



  /// The swatch art, drawn once per colour and kept -- a Picker rebuilds its
  /// labels on every selection change.
  private static let dots: [String: SwatchImage] = Accents.all.reduce(into: [:]) {
    $0[$1.id] = render($1.color)
  }
  private static func dot(_ rgb: RGB) -> SwatchImage {
    dots[Accents.all.first { $0.color == rgb }?.id ?? ""] ?? render(rgb)
  }

  /// The drawn swatch as a SwiftUI `Image`, which is the only part of this
  /// that differs between the platforms -- the drawing is the same circle
  /// either way, and so is the reason it is an image at all.
  private static func swatch(_ rgb: RGB) -> Image {
    #if os(macOS)
    Image(nsImage: dot(rgb))
    #else
    Image(uiImage: dot(rgb))
    #endif
  }

  private static let side: CGFloat = 22

  #if os(macOS)
  private static func render(_ rgb: RGB) -> NSImage {
    let image = NSImage(size: CGSize(width: side, height: side))
    image.lockFocus()
    NSColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
            blue: CGFloat(rgb.2) / 255, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
    image.unlockFocus()
    // Not template art, for the reason the `.alwaysOriginal` below gives: a
    // palette Picker recolours anything that is.
    image.isTemplate = false
    return image
  }
  #else
  private static func render(_ rgb: RGB) -> UIImage {
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
      UIColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
              blue: CGFloat(rgb.2) / 255, alpha: 1).setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    return image.withRenderingMode(.alwaysOriginal)
  }
  #endif

  private static let groundFooter: String =
    "What the crowd walks on. Automatic follows Appearance; Classic is the "
    + "2016 one."

  private static let accentFooter: String =
    "The colour behind the tool you are holding. Orange is the 2016 original's "
    + "own."
}

/// The controls that write, as views of their own.
///
/// Views rather than `@ViewBuilder` properties on the sheet: each is its own
/// type-checking unit, which is the budget this Form has run out of twice
/// before -- see the note on `groundSection` -- and each takes only the object
/// it actually edits.
///
struct CrowdPage: View {
  @Bindable var settings: WalkyCore.Settings

  var body: some View {
    Form {
      Section("The crowd") {
        slider(.speed, format: "%.2f m/s")
        slider(.pedestrianRadius)
        slider(.personalSpace)
      }
      // Brush and border together, which is the split "Pedestrians"/"Drawing"
      // got wrong: brush size was filed with the crowd it paints rather than
      // with the brush it is, leaving Drawing a section of one slider.
      Section("Tools") {
        slider(.brushSize, warning: brushWarning)
        slider(.borderThickness)
      }
    }
  }

  /// What the brush actually costs at its current size.
  ///
  /// A number rather than a caution, because the number is the surprising part:
  /// the brush is n across, so a *tap* drops n x n pedestrians, and a drag
  /// paints continuously.
  private var brushWarning: String? {
    let n = Int(settings.brushSize)
    guard n > 9 else { return nil }
    return "\(n) x \(n) — that is \(n * n) pedestrians a tap, more while you drag."
  }

  private func slider(_ setting: NumericSetting, format: String = "%.0f",
                      warning: String? = nil) -> some View {
    let r = setting.range
    return VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(setting.label)
        Spacer()
        Text(String(format: format, settings[keyPath: setting.keyPath]))
          .foregroundStyle(.secondary).monospacedDigit()
      }
      Slider(value: Binding(get: { settings[keyPath: setting.keyPath] },
                            set: { settings[keyPath: setting.keyPath] = $0 }),
             in: r.min...r.max, step: r.step)
      if let warning {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// What a keyboard can do, printed from the same table the bar and the menu
/// bar are built from -- so a digit that moves moves here too. See
/// `WalkyCore/Commands.swift`.
///
/// Only the ones with a key. A page of shortcuts listing things that have none
/// is a page you have to read to find out it has nothing to tell you.
struct KeyboardShortcutsPage: View {
  var body: some View {
    Form {
      ForEach(Command.Group.allCases, id: \.self) { group in
        let rows = Command.all.filter { $0.group == group && $0.shortcut != nil }
        if !rows.isEmpty {
          Section(group.rawValue) {
            ForEach(rows, id: \.self) { command in
              LabeledContent {
                Text(command.shortcut?.label ?? "")
                  .monospaced()
                  .foregroundStyle(.secondary)
              } label: {
                Label(command.title, systemImage: command.symbol)
              }
            }
          }
        }
      }
      Section {
        Text(Self.footer).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private static let footer =
    "A hardware keyboard only. Hold Command to see the same list as a menu, "
    + "where the rest of Walky's commands are too."
}

struct ShowPage: View {
  @Bindable var settings: WalkyCore.Settings
  @Bindable var chrome: Chrome

  var body: some View {
    Form {
      Section("Show") {
        Toggle("Convex hulls", isOn: $settings.showConvexHull)
        Toggle("Route to goal", isOn: $settings.showLineToTarget)
        Toggle("Personal space", isOn: $settings.showPersonalSpace)
        Toggle("Debug info", isOn: $settings.showDebug)
        Toggle("Basemap", isOn: $settings.showBasemap)
      }
      Section {
        Toggle("Hide controls", isOn: $chrome.hidden)
      } header: { Text("Recording") } footer: {
        Text("Hides the bar and status bar. Tap the map to restore; record from "
           + "Control Centre.")
      }
    }
  }
}
