import SwiftUI
import WalkyCore

@main
struct WalkyApp: App {
  /// Held here rather than only in `RootView` because the menu bar is a second
  /// reader of it: an iPad with a hardware keyboard draws one, and until
  /// `WalkyCommands` existed Walky put nothing in it.
  @State private var model = AppModel.shared

  var body: some Scene {
    WindowGroup { RootView() }
      .commands { WalkyCommands(model: model) }
  }
}
