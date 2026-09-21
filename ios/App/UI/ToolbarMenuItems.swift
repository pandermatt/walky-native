import SwiftUI
import WalkyCore

/// Everything you reach for occasionally, in one place.
///
/// Its own type because there are two places to reach it from now: the
/// floating bar's `…` cell, and the same `…` at the end of the console's tool
/// row when the phone is folded. One list, so folding a phone cannot quietly
/// change what is in the menu -- which is the whole of how Walky keeps the bar,
/// the Mac's menu bar and the printed list in Settings agreeing.
///
/// A `View` rather than a `@ViewBuilder` function, and that is load-bearing:
/// the items read `state.selected` and `state.canUndo`, and a function would
/// read them in whichever body called it. As a view they are read here, in a
/// leaf, which is the rule the comment at the top of `RootView` states.
struct ToolbarMenuItems: View {
  let state: ToolbarState
  let onTool: (ToolId) -> Void
  let onAction: (ToolbarAction) -> Void
  /// Whether to carry Generator and Measure.
  ///
  /// True in the floating bar, where eight 44pt cells do not fit a 375pt phone
  /// and those two have nowhere else to live. False in the console, whose tool
  /// row has room for all seven -- and an item that is also a lit button an
  /// inch away is a second place to look at the same state.
  var showsModalTools = true

  var body: some View {
    Button { onAction(.undo) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
      .disabled(!state.canUndo)
    Button { onAction(.resetPedestrians) } label: {
      Label("Reset pedestrians", systemImage: "arrow.counterclockwise")
    }
    Button { onAction(.resetZoom) } label: {
      Label("Reset zoom", systemImage: "scope")
    }
    // With the other immediate actions rather than beside Settings, which is
    // where the switch that shares this flag lives. The grouping is about
    // what an item *does*: these three change the view now, the next two
    // raise a sheet. Reaching it here is two taps against Settings' four,
    // which for something you flip before a screenshot and back after is the
    // difference between using it and not.
    Button { onAction(.hideControls) } label: {
      Label("Hide controls", systemImage: "eye.slash")
    }
    Divider()
    // The two modal tools with no cell in the bar. The armed state is carried
    // by the icon swapping to a checkmark, because without it these would be
    // the only modes you cannot see are armed. (A `Toggle` here draws nothing
    // at all in a Menu on iOS 26, which is how this started as one.)
    //
    // Both have a cell of their own on a Mac, where the bar has room for
    // seven, and in the console, where the row does -- so neither carries them.
    #if os(iOS)
    if showsModalTools {
      Button { onTool(.generator) } label: {
        Label(state.selected == .generator ? "Marking a generator" : "Generator",
              systemImage: state.selected == .generator ? "checkmark" : "door.left.hand.open")
      }
      Button { onTool(.measure) } label: {
        Label(state.selected == .measure ? "Measuring" : "Measure detour",
              systemImage: state.selected == .measure ? "checkmark" : "ruler")
      }
    }
    #endif
    if state.hasMeasurement {
      Button { onAction(.clearMeasurement) } label: {
        Label("Clear measurement", systemImage: "ruler.fill")
      }
    }
    Divider()
    // Above Settings, in the group that is about the app rather than about
    // the map, and well clear of the destructive item at the bottom.
    Button { onAction(.welcome) } label: {
      Label("Getting started", systemImage: "lightbulb")
    }
    Button { onAction(.settings) } label: { Label("Settings", systemImage: "gearshape") }
    // Destructive last and marked as such, so the one irreversible item in
    // the menu does not sit next to Undo looking like its neighbour.
    Button(role: .destructive) { onAction(.clear) } label: {
      Label("Clear map", systemImage: "trash")
    }
  }
}
