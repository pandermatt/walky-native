import Foundation

/// Everything the app can be *told to do*, in one table.
///
/// Ported from `web/src/ui/toolbar.ts`, where the same list is the toolbar's
/// button table and the keyboard map is derived from it rather than written out
/// again beside the key handler. The comment there is the whole argument:
///
/// > the digits mean how far down the strip a tool is -- so a list of them kept
/// > somewhere else is a list that goes wrong the first time a tool moves.
///
/// The iOS port had drifted exactly that far already: the toolbar said "Mark
/// goal" and the Mac menu said "Mark Goal", and the two disagreed about what
/// the digits meant. So there is one table: the bar's cells, the menu bar and
/// the printed list in Settings all read it.
///
/// What it deliberately does **not** hold is the overflow menu's prose -- a
/// tool in there says "Marking a generator" while it is armed, because it has
/// no cell to light up. That is a sentence about a state, not a name.
///
/// In `WalkyCore` because it is not pixels. What it holds is a title, a symbol
/// and a key, none of which need a screen to be checked -- see `ToolTests`.
///
/// The table hangs off `Command` itself rather than a `Commands` namespace,
/// because SwiftUI has a `Commands` protocol and a menu bar is exactly where
/// both names would be in scope at once.

/// An action that is not a tool: something the app does once when you ask.
///
/// Was `ToolbarAction`, in the app target. It moved here with the table, and
/// the two that the *view* owns -- the sheets -- are still marked as such below
/// rather than being a second enum.
public enum ToolbarAction: Sendable, Hashable, CaseIterable {
  case start, resetPedestrians, undo, clear, resetZoom
  case hideControls, clearMeasurement, putToolDown
  /// Raised by the app layer, because each one is a window or a sheet rather
  /// than an edit: `AppModel` turns these into the callbacks its shell sets.
  case openMap, saveMap, settings, welcome
}

/// A tool to arm, or an action to run.
public enum CommandId: Sendable, Hashable {
  case tool(ToolId)
  case action(ToolbarAction)
}

/// A key, said once so that the menu bar, the raw key handlers and the printed
/// list in Settings cannot disagree about it.
public struct Shortcut: Sendable, Hashable {
  public enum Key: Sendable, Hashable {
    /// A bare character, which is every digit the tools use.
    case character(String)
    case space, escape, delete
  }

  public var key: Key
  public var command: Bool
  public var shift: Bool

  public init(_ key: Key, command: Bool = false, shift: Bool = false) {
    self.key = key; self.command = command; self.shift = shift
  }

  /// How a person writes it. The modifier glyphs are the same on both
  /// platforms -- an iPad with a keyboard draws the same Command symbol a Mac
  /// does -- so there is one spelling rather than one per platform.
  public var label: String {
    var out = ""
    if shift { out += "\u{21E7}" }
    if command { out += "\u{2318}" }
    switch key {
    case .character(let c): out += c.uppercased()
    case .space: out += "Space"
    case .escape: out += "esc"
    case .delete: out += "\u{232B}"
    }
    return out
  }
}

/// One thing the app can be told to do.
public struct Command: Sendable, Hashable {
  public var id: CommandId
  /// Sentence case with one capital, which is the convention across the bar,
  /// the menu and the settings sheet: "Mark goal", not "Mark Goal".
  public var title: String
  /// SF Symbol. Template art, so it tints itself wherever it is drawn.
  public var symbol: String
  public var shortcut: Shortcut?
  /// Which part of the printed list it belongs under.
  public var group: Group

  public enum Group: String, Sendable, CaseIterable {
    case run = "Run"
    case tools = "Tools"
    case map = "Map"
    case file = "File"
    case view = "View"
  }

  public var tool: ToolId? {
    if case .tool(let id) = id { return id }
    return nil
  }

  public var action: ToolbarAction? {
    if case .action(let a) = id { return a }
    return nil
  }
}

extension Command {
  /// The table.
  ///
  /// The digits count the cells you can see on the bar, in the order they are
  /// drawn: five on the strip, then the two that live in the overflow menu. The
  /// web app numbers its own strip the same way and lands on different digits
  /// because it has tools this port does not -- the rule travels, the numbers
  /// do not.
  public static let all: [Command] = [
    Command(id: .action(.start), title: "Play / pause", symbol: "play.fill",
            shortcut: Shortcut(.space), group: .run),

    Command(id: .tool(.wall), title: "Wall", symbol: "scribble",
            shortcut: Shortcut(.character("1")), group: .tools),
    Command(id: .tool(.rectangle), title: "Rectangle", symbol: "rectangle.fill",
            shortcut: Shortcut(.character("2")), group: .tools),
    Command(id: .tool(.border), title: "Border", symbol: "square",
            shortcut: Shortcut(.character("3")), group: .tools),
    Command(id: .tool(.pedestrian), title: "Pedestrians", symbol: "person.3.fill",
            shortcut: Shortcut(.character("4")), group: .tools),
    Command(id: .tool(.goal), title: "Mark goal", symbol: "target",
            shortcut: Shortcut(.character("5")), group: .tools),
    Command(id: .tool(.generator), title: "Generator", symbol: "door.left.hand.open",
            shortcut: Shortcut(.character("6")), group: .tools),
    Command(id: .tool(.measure), title: "Measure detour", symbol: "ruler",
            shortcut: Shortcut(.character("7")), group: .tools),
    Command(id: .action(.putToolDown), title: "Put the tool down", symbol: "hand.raised",
            shortcut: Shortcut(.escape), group: .tools),

    Command(id: .action(.undo), title: "Undo", symbol: "arrow.uturn.backward",
            shortcut: Shortcut(.character("z"), command: true), group: .map),
    Command(id: .action(.resetPedestrians), title: "Reset pedestrians",
            symbol: "arrow.counterclockwise", group: .map),
    Command(id: .action(.clearMeasurement), title: "Clear measurement",
            symbol: "ruler.fill", group: .map),
    Command(id: .action(.clear), title: "Clear map", symbol: "trash",
            shortcut: Shortcut(.delete, command: true, shift: true), group: .map),

    Command(id: .action(.openMap), title: "Open map", symbol: "folder",
            shortcut: Shortcut(.character("o"), command: true), group: .file),
    Command(id: .action(.saveMap), title: "Save map", symbol: "square.and.arrow.down",
            shortcut: Shortcut(.character("s"), command: true), group: .file),

    Command(id: .action(.resetZoom), title: "Reset zoom", symbol: "scope",
            shortcut: Shortcut(.character("0"), command: true), group: .view),
    Command(id: .action(.hideControls), title: "Hide controls", symbol: "eye.slash",
            shortcut: Shortcut(.character("."), command: true), group: .view),
    Command(id: .action(.settings), title: "Settings", symbol: "gearshape",
            shortcut: Shortcut(.character(","), command: true), group: .view),
    Command(id: .action(.welcome), title: "Getting started", symbol: "lightbulb",
            group: .view),
  ]

  /// Every tool, in the order the digits count them.
  ///
  /// A Mac's bar shows all seven: a window has room for nine cells where a
  /// 375pt phone has room for seven, and the two that a phone has to file in
  /// the overflow menu are the two with no cell to light up when they are
  /// armed -- which is the one thing the menu could not fix.
  public static let tools: [ToolId] = [.wall, .rectangle, .border, .pedestrian,
                                       .goal, .generator, .measure]

  /// The five a phone's bar has room for. The digits are `tools`, so these are
  /// its first five and cannot be renumbered without moving a button.
  public static let barTools: [ToolId] = Array(tools.prefix(5))

  public static func of(_ id: CommandId) -> Command? {
    all.first { $0.id == id }
  }

  public static func of(_ tool: ToolId) -> Command? { of(.tool(tool)) }
  public static func of(_ action: ToolbarAction) -> Command? { of(.action(action)) }

  /// What a bare keypress means, keyed the way a key handler asks.
  ///
  /// Bare only: anything with Command on it is the menu bar's to answer, and a
  /// menu key equivalent is consumed before a view ever sees it.
  public static func bare(_ character: String) -> Command? {
    all.first { $0.shortcut == Shortcut(.character(character)) }
  }

  public static var space: Command? { all.first { $0.shortcut == Shortcut(.space) } }
  public static var escape: Command? { all.first { $0.shortcut == Shortcut(.escape) } }
}
