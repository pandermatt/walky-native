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
        Label(state.running ? "Pause" : "Start",
              systemImage: state.running ? "pause.fill" : "play.fill")
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
  /// Armed is a tint plus the filled variant of the same symbol. Two signals
  /// rather than one, because a tint alone is a colour and this app lets you
  /// choose the accent -- including ones that read quietly against glass.
  private func toolButton(_ id: ToolId) -> some View {
    let command = Command.of(id)
    let armed = state.selected == id
    return Button {
      onTool(id)
    } label: {
      Label(command?.title ?? "", systemImage: command?.symbol ?? "questionmark")
        .symbolVariant(armed ? .fill : .none)
    }
    .tint(armed ? MapRenderer.color(tint.color) : nil)
    .accessibilityAddTraits(armed ? [.isSelected] : [])
  }
}
