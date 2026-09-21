import SwiftUI
import WalkyCore

/// The menu bar, on both platforms.
///
/// Not a Mac thing: an iPad with a hardware keyboard has a menu bar too -- hold
/// Command and it draws one -- and until this existed Walky contributed nothing
/// to it, so not one shortcut in the app was discoverable or worked there.
///
/// Nothing here is a new feature. Every item is something the floating bar or
/// Settings already does; this is the same list where a keyboard looks for it,
/// built from `Command.all` so that the bar, this and the printed list in
/// Settings cannot drift apart.
///
/// **The bare keys are not here.** A menu key equivalent with no modifier is
/// reliable on a Mac and is not on iPadOS, so the digits, Space and Escape are
/// answered by the two input views instead -- `WalkyTouchView.keyCommands` and
/// `WalkyPointerView.keyDown`. What *is* here carries Command, which both
/// platforms route through the menu.
@MainActor
struct WalkyCommands: Commands {
  let model: AppModel
  /// Observed so the menu greys out with the map: `canUndo` and `running` are
  /// mirrored onto the toolbar state once per frame, guarded against writing
  /// when nothing changed. See `AppModel.tick`.
  @Bindable var toolbar: ToolbarState

  init(model: AppModel) {
    self.model = model
    self.toolbar = model.toolbar
  }

  var body: some Commands {
    // Replacing the stock New/Open group: Walky has no documents to make new
    // ones of -- the map is a live canvas, not a file you open into a window.
    CommandGroup(replacing: .newItem) {
      button(.openMap)
      button(.saveMap)
    }

    CommandGroup(replacing: .undoRedo) {
      button(.undo).disabled(!toolbar.canUndo)
    }

    CommandMenu("Map") {
      // The title says which way it will go, so it is the one item that cannot
      // come from the table's fixed name.
      Button(toolbar.running ? "Pause" : "Play") { model.act(.start) }
      Divider()
      ForEach(Command.all.filter { $0.tool != nil }, id: \.self) { command in
        toolButton(command)
      }
      Divider()
      button(.resetPedestrians)
      if toolbar.hasMeasurement { button(.clearMeasurement) }
      button(.clear)
    }

    CommandGroup(after: .toolbar) {
      button(.resetZoom)
      // The only two-way one: the bar's action can only hide, because the way
      // back there is a tap on the map. A menu wants a toggle.
      Button(model.chrome.hidden ? "Show controls" : "Hide controls") {
        if model.chrome.hidden { model.chrome.hidden = false } else { model.act(.hideControls) }
      }
      .keyboardShortcut(key(.hideControls))
      // On a Mac the Settings *scene* supplies Cmd-, and an item here would be
      // a second one fighting it. An iPad has no such scene, so it needs this.
      #if os(iOS)
      button(.settings)
      #endif
    }

    CommandGroup(replacing: .help) {
      button(.welcome)
    }
  }

  private func button(_ action: ToolbarAction) -> some View {
    let command = Command.of(action)
    return Button(command?.title ?? "") { model.act(action) }
      .keyboardShortcut(key(action))
  }

  /// A tool: the same press that arms it puts it down again, exactly as
  /// tapping its cell on the bar does.
  private func toolButton(_ command: Command) -> some View {
    Button(command.title) {
      if let tool = command.tool { model.toggleTool(tool) }
    }
  }

  /// The table's key as SwiftUI spells one, or nothing.
  ///
  /// Bare keys are deliberately dropped here -- see the note on the type -- so
  /// a menu item never claims a digit the input views are answering.
  private func key(_ action: ToolbarAction) -> KeyboardShortcut? {
    guard let shortcut = Command.of(action)?.shortcut, shortcut.command else { return nil }
    let equivalent: KeyEquivalent
    switch shortcut.key {
    case .character(let c): equivalent = KeyEquivalent(Character(c))
    case .space: equivalent = .space
    case .escape: equivalent = .escape
    case .delete: equivalent = .delete
    }
    var modifiers: EventModifiers = [.command]
    if shortcut.shift { modifiers.insert(.shift) }
    return KeyboardShortcut(equivalent, modifiers: modifiers)
  }
}
