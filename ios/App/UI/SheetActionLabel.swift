import SwiftUI

/// The label for a sheet's Done or Cancel, which is a word everywhere except
/// where the system stands the bar up on a side.
///
/// iPhone Duo puts a sheet's bar down the edge of the outer display, and it is
/// picky about what it will put there. Apple:
///
///   "The system uses an icon for an item it presents vertically ... If your
///    item has a title and doesn't have an icon, the system doesn't present it
///    vertically."
///
/// `Button("Done")` is title-only, so on the Duo it stayed a horizontal pill in
/// the corner while everything around it had turned.
///
/// The obvious fix -- give it a `Label` and be done -- is wrong, because the
/// same page says the system prefers the *icon* when it presents an item
/// horizontally too. One `Label` would quietly turn "Done" into a bare tick on
/// every iPhone, iPad and Mac, and the word is the right control there: it is
/// what a sheet has said since sheets existed, and nothing about an ordinary
/// phone asked for it to change.
///
/// So the icon appears exactly where it buys something. `toolbarVerticalEdge`
/// is the scene's answer to "which side would a vertical bar be on", and it
/// "reflects the system's preferred edge regardless of whether a vertical bar
/// is currently visible" -- so there is no circularity in asking before handing
/// over an item the system needs in order to decide. `nil` means this context
/// never uses one, which is every device but the Duo, and that branch is the
/// literal `Text` this used to be.
struct SheetActionLabel: View {
  let title: LocalizedStringKey
  let symbol: String

  var body: some View {
    // iOS only, and not because a Mac lacks the pose: `toolbarVerticalEdge` is
    // newer than this target's macOS floor, and `Mac/` is excluded from the
    // files that reach for it. Here the exclusion would be the whole view.
    #if os(iOS)
      if #available(iOS 27.1, *) {
        Adaptive(title: title, symbol: symbol)
      } else {
        Text(title)
      }
    #else
      Text(title)
    #endif
  }

  #if os(iOS)
    /// Split out so the environment read can be gated with the view.
    ///
    /// Reading it inside a real `View` matters as well as reads nicely: this is
    /// a tracked scope, unlike the body of a `ToolbarContent` -- which is the
    /// trap `WalkyToolbar` has a long comment about -- so unfolding the phone
    /// re-renders the label rather than leaving yesterday's answer on screen.
    @available(iOS 27.1, *)
    private struct Adaptive: View {
      @Environment(\.toolbarVerticalEdge) private var edge
      let title: LocalizedStringKey
      let symbol: String

      var body: some View {
        if edge == nil {
          Text(title)
        } else {
          Label(title, systemImage: symbol)
        }
      }
    }
  #endif
}
