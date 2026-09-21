import SwiftUI
import WalkyCore

/// The wait before the crowd can walk, shown rather than suffered.
///
/// The first navigation graph is the one build the app cannot defer: there is
/// no older graph to carry on with, so `WalkyWorld.ensureNav` builds it on the
/// main actor and everything stops -- 2.1 seconds on a 600m import, with no
/// explanation, immediately after pressing Play. That reads as a crash.
///
/// The wait itself does not go away; `MapImporter` made the same argument at
/// its `.routing` step and reached the same answer, and this reuses its words.
/// A bar over the map rather than a border around it, because unlike a
/// generation this is not the app thinking in the background -- it is the one
/// thing standing between a press and the crowd moving.
struct RoutingOverlay: View {
  let showing: Bool
  let tint: Accent

  var body: some View {
    if showing {
      VStack(spacing: 12) {
        Text("Building the navigation graph…")
          .font(.system(size: 15, weight: .medium))
        ProgressView()
          .progressViewStyle(.linear)
          .tint(MapRenderer.color(tint.color))
          .frame(width: 220)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
      .panel()
      // Nothing to press, and nothing behind it should be pressable either:
      // an edit landing mid-build is an edit against a map the graph in flight
      // does not describe, which is what `navGeneration` exists to notice.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.black.opacity(0.12))
      .contentShape(Rectangle())
      .transition(.opacity)
      .allowsHitTesting(true)
    }
  }
}

private extension View {
  @ViewBuilder func panel() -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      glassEffect(.regular, in: .rect(cornerRadius: 18))
    } else {
      background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
  }
}
