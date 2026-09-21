import SwiftUI
import WalkyCore

/// The bar, handed to the system instead of drawn by us.
///
/// Walky's own `ToolbarView` is a capsule of glass with a tinted pill that
/// flows from cell to cell, and on a phone, an iPad or a Mac it stays exactly
/// that. But on iPhone Duo the system wants bars stood up on a side -- on the
/// outer display always, and on the inner one in landscape -- and it will only
/// do that for items it owns. Apple is unambiguous about both halves of this:
///
///   "If the system doesn't present your bars vertically, check that you're
///    using the bar support that navigation containers ... provide ... instead
///    of creating a custom bar for your view."
///
///   "If your item uses a custom view rather than a title or icon, the system
///    doesn't present it vertically."
///
/// So there is no version of this where we keep the pill *and* get the vertical
/// presentation: a pill is a custom view, and a custom view is never stood up.
/// This file is the other side of that trade -- plain items, which the system
/// can place, group, rotate and overflow on its own.
///
/// What it buys, beyond the axis: **`Command.barTools` stops mattering.** That
/// list is the first five tools, capped because "eight 44pt cells do not fit a
/// 375pt phone" -- a number we had to guess. Given priorities the system does
/// that arithmetic itself, against the space actually available, so Generator
/// and Measure are on the bar whenever they fit rather than never.
///
/// Armed reads as a tint and a filled symbol rather than as a travelling shape.
/// That is the part of the trade that costs something, and it is worth being
/// honest in the code about which way it went.
@available(iOS 27.1, *)
struct WalkyToolbar: ToolbarContent {
  /// Read as *values*, not off the observable, and that is load-bearing.
  ///
  /// `ToolbarContent` is not a `View`. Its body is not an observation-tracked
  /// scope, so reading `state.selected` in here registers nothing and the bar
  /// is never told the armed tool changed: the tap fires, the model updates,
  /// and the glass keeps drawing the old answer. Taking them as values makes
  /// `RootView.body` the thing that reads them -- which is tracked -- so a new
  /// value arrives here as a new `WalkyToolbar`.
  ///
  /// This is the one thing the comment at the top of `RootView` forbids, done
  /// on purpose and only for these two. What that rule is about is frequency:
  /// `crowd.count` moves on every brush point, sixty times a second, and
  /// reading it up there rebuilt the map under a finger. `selected` moves when
  /// somebody picks a tool and `running` when they press play -- a handful of
  /// times a session, each of them a deliberate act that is already repainting
  /// the map anyway.
  let selected: ToolId?
  let running: Bool
  /// Still the object, because `ToolbarMenuItems` *is* a `View` and tracks its
  /// own reads -- `canUndo` and `hasMeasurement` are live in there.
  let state: ToolbarState
  let tint: Accent
  let onTool: (ToolId) -> Void
  let onAction: (ToolbarAction) -> Void

  var body: some ToolbarContent {
    // Run first, and highest priority, because it is the one control that is
    // never not worth reaching: everything else edits a map, this starts it.
    ToolbarItem {
      Button {
        onAction(.start)
      } label: {
        Label(running ? "Pause" : "Start",
              systemImage: running ? "pause.fill" : "play.fill")
      }
    }
    .visibilityPriority(.high)

    // A spacer, not a `Divider`: in a bar the system owns the grouping, and a
    // divider drawn by us is a custom view again.
    ToolbarSpacer()

    // All seven, each its own item so each can carry its own priority -- a
    // `ToolbarItemGroup` is one piece of toolbar content and would have to
    // share one. They still draw as a single group of glass, because adjacent
    // items merge and it is the `ToolbarSpacer`s either side that break them
    // apart.
    //
    // Each has a title as well as an icon, and that is not optional: the system
    // "uses an icon and title for an item in an overflow menu", so an item
    // without one arrives there nameless.
    ForEach(Command.tools, id: \.self) { id in
      ToolbarItem { toolButton(id) }
        .visibilityPriority(priority(of: id))
    }

    ToolbarSpacer()

    // The things that are never on the bar. `ToolbarOverflowMenu` puts them in
    // the same `…` the system fills with whatever did not fit, so there is one
    // menu rather than ours beside the system's.
    ToolbarOverflowMenu {
      ToolbarMenuItems(state: state, onTool: onTool, onAction: onAction,
                       showsModalTools: false)
    }
  }

  /// Which tools the system should keep when it runs out of room.
  ///
  /// Left to itself it keeps them in declaration order and overflows the tail,
  /// which on a short landscape bar meant losing **Mark goal** while keeping
  /// Rectangle and Border. That is the wrong trade: rectangle and border are
  /// two more ways to draw a wall, and a crowd with no goal has nowhere to walk
  /// at all -- the map does nothing until one is set.
  ///
  /// So: the three that make a working map outrank the two that are variations
  /// on one of them, and the two specialist modes go first. Play is not here
  /// because it is not a tool; it carries `.high` at its own call site and is
  /// declared before all of these, so it outlives everything.
  private func priority(of id: ToolId) -> ToolbarItemVisibilityPriority {
    switch id {
    case .wall, .pedestrian, .goal: .high
    case .rectangle, .border: .automatic
    case .generator, .measure: .low
    }
  }

  /// One tool.
  ///
  /// A `Toggle`, not a `Button`, and that is the whole of how armed reads.
  ///
  /// It was a `Button` tinted with the accent, which worked while the seven sat
  /// in one `ToolbarItemGroup` and stopped working when they became individual
  /// items so they could carry their own priorities -- the system restyles a
  /// bar button and the tint did not survive. Rather than hunt for a tint that
  /// sticks, say the true thing: a tool is not an action you fire, it is a mode
  /// that is on or off. A `Toggle` is that, the system draws its own selected
  /// state for it, and VoiceOver gets the right trait without being told.
  ///
  /// The binding is one-way on purpose. `isOn` is read from the model, and
  /// setting it calls `toggleTool`, which decides what happens -- tapping the
  /// armed tool disarms it, and the model owns that rule. Writing the new value
  /// back here would be a second place that decided it.
  private func toolButton(_ id: ToolId) -> some View {
    let command = Command.of(id)
    let armed = selected == id
    return Toggle(isOn: Binding(get: { armed }, set: { _ in onTool(id) })) {
      Label(command?.title ?? "", systemImage: command?.symbol ?? "questionmark")
    }
    .toggleStyle(.button)
    // Only the armed one, and that is the point: `tint` colours the control
    // whatever its state, so tinting all seven turned the whole strip yellow
    // and told you nothing. On the lit tool it recolours the shape the system
    // already draws for a selected toggle -- which is blue by default, and
    // blue is not this app.
    .tint(armed ? MapRenderer.color(tint.color) : nil)
  }
}
