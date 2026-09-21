import SwiftUI
import WalkyCore

/// The Mac app.
///
/// A target of its own rather than Catalyst or "Designed for iPad". The whole
/// port was built so that this would be cheap: everything that is not pixels
/// lives in `WalkyCore` -- the camera, the tools, the world's edits, and
/// `PointerRouter`, which is a state machine over points and knows nothing
/// about `UITouch`. So a Mac app is a new shell around the same model: this
/// file, a window, an `NSView` that turns mouse and trackpad events into the
/// same calls the phone's fingers make, and the menu bar.
///
/// What is shared with the phone is everything below the shell: `MapCanvas`
/// and `MapRenderer` (SwiftUI's `GraphicsContext`, which is cross-platform),
/// `AppModel` and its loop, the toolbar, the banners and the settings form.
/// What is not shared is `RootView` itself, and deliberately: a phone's root is
/// a sheet stack over a full-bleed map, and a Mac's is a window with a menu bar
/// and a Settings scene. Guarding one view into serving both would make every
/// line of it answer two questions at once.
@main
struct WalkyMacApp: App {
  /// The same `AppModel.shared` the phone uses -- and it has to be shared here
  /// too, because the Settings scene is a second window over one world.
  @State private var model = AppModel.shared

  var body: some Scene {
    WindowGroup {
      MacRootView(model: model)
    }
    // The map is the content, so the title bar sits over it rather than above
    // it, the way Maps and Photos do it.
    .windowStyle(.hiddenTitleBar)
    .commands { WalkyCommands(model: model) }

    // Cmd-, for free: a `Settings` scene is what the system hangs that key on,
    // and hanging it on a sheet of our own would put Walky's preferences
    // somewhere no Mac app keeps them.
    SwiftUI.Settings {
      MacSettingsView(model: model)
    }
  }
}
