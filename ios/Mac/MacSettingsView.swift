import SwiftUI
import WalkyCore

/// What Cmd-, opens.
///
/// The same settings as the phone's, over the same `Settings` object and built
/// from the same page views -- but **not** the same layout, and that was the
/// whole trouble with reusing the sheet here. A phone has one column and a
/// navigation stack, so it files forty controls behind five rows you drill
/// into. A Mac Settings window is a fixed panel with a row of tabs across the
/// top, and every app on the machine keeps its preferences that way; a stack of
/// chevron rows with a Done button in it reads as an iPhone in a window, which
/// is exactly what it was.
///
/// So the pages are the same types -- `AppearancePage`, `CrowdPage`,
/// `ShowPage`, `KeyboardShortcutsPage` -- and only the furniture around them
/// differs. `.formStyle(.grouped)` is what gives them the System Settings look
/// rather than the flat inspector one.
///
/// Two of the phone's four ways to get a map are missing, for the reasons the
/// sheet already states about a phone without the hardware: **no room scan**
/// (RoomPlan wants a LiDAR camera, which no Mac has) and **no app icon**
/// (alternate icons are an iOS affordance; a Mac app has one, in the Dock).
struct MacSettingsView: View {
  let model: AppModel

  var body: some View {
    TabView {
      maps
        .tabItem { Label("Maps", systemImage: "map") }
      CrowdPage(settings: model.world.settings)
        .tabItem { Label("Crowd", systemImage: "figure.walk") }
      AppearancePage(settings: model.world.settings)
        .tabItem { Label("Appearance", systemImage: "paintpalette") }
      ShowPage(settings: model.world.settings, chrome: model.chrome)
        .tabItem { Label("Show", systemImage: "eye") }
      KeyboardShortcutsPage()
        .tabItem { Label("Shortcuts", systemImage: "keyboard") }
    }
    .formStyle(.grouped)
    // A Settings window is sized by its content and does not remember being
    // dragged, so the size is stated once here rather than per tab -- with
    // tabs of different heights the window would jump every time you changed
    // one.
    .frame(width: 520, height: 460)
    .repaintingTheMap(model.world.settings) { model.world.requestRender() }
  }

  /// Where a map comes from, laid out as one page.
  ///
  /// The phone files these behind four rows because four importers do not fit
  /// a phone screen at once; two of them do fit a Settings panel, and a tab you
  /// have already clicked into should not ask you to click again.
  private var maps: some View {
    Form {
      MapFileSection(onOpen: { MacShell.shared.startOpen() },
                     onSave: { MacShell.shared.startSave(model) },
                     // Sharing on a Mac is the Finder's job: save the map and
                     // send the file. The phone's share sheet is a
                     // `UIActivityViewController`, which does not exist here.
                     onShare: nil)
      RealMapSection(world: model.world, basemap: model.basemap,
                     importer: model.importer,
                     locator: model.locator,
                     // The ground's own lighting, as iOS asks it -- not this
                     // window's scheme, which says nothing about the floor the
                     // map is going under.
                     dark: model.world.settings.ground.wantsDarkMap)
      // No availability gate, where the phone needs one: this target's floor is
      // the release `FoundationModels` shipped in.
      DescribeSceneSection(world: model.world, generator: model.describer,
                           onStart: {})
    }
  }
}
