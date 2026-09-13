import SwiftUI
import WalkyCore

/// A light around the edge of the screen while the model is writing a plan.
///
/// Generation takes a second or two and, until now, showed nothing: the sheet
/// closes so the plan can be watched arriving, which leaves whoever asked
/// looking at their old map wondering whether the button worked. A border is
/// the right shape for that answer -- it says *the app* is busy rather than any
/// one control, and it does not cover the map it is about to replace.
///
/// **In Walky's colours, deliberately not Apple's.** The iridescent edge glow is
/// Apple Intelligence's own visual identity, and Apple's guidance is that it
/// stays on Apple's surfaces rather than badging somebody else's feature -- the
/// same reason the section wears a sparkle instead of the `apple.intelligence`
/// symbol. These are the six accents from `Accents.all`, which is the app
/// saying *Walky* is thinking. It happens to be the honest claim too: most of
/// the wait is Walky's own repair and navigation rebuild.
///
/// **Its own `View`, and that is the point** -- see `CrowdBanner`. `phase` moves
/// on every streamed snapshot, dozens of times in a generation, and reading
/// `isBusy` up in `RootView.body` would rebuild the toolbar underneath a finger
/// each time.
@available(iOS 26.0, *)
struct GeneratingBorder: View {
  let generator: SceneGenerator

  /// How long one turn of the light takes.
  private let period: Double = 2.4

  var body: some View {
    Group {
      if generator.isBusy {
        // Half display rate. The sweep is a slow gradient and nobody can see
        // sixty steps of it, but the simulation is drawing on the same main
        // actor and this should not take a frame from it.
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
          let turn = timeline.date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
          edge(turn)
        }
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.35), value: generator.isBusy)
    // Nothing here is touchable: the map underneath stays live, so a generation
    // can be watched and panned at the same time.
    .allowsHitTesting(false)
    .ignoresSafeArea()
  }

  private func edge(_ turn: Double) -> some View {
    let sweep = AngularGradient(
      // Doubled and wrapped so the ring closes on the colour it opened with --
      // a single pass through six colours has a seam where red meets orange,
      // and a seam travelling round the screen reads as a glitch.
      gradient: Gradient(colors: ring),
      center: .center,
      angle: .degrees(turn * 360))

    // Two strokes rather than one: a wide blurred pass for the light it throws
    // onto the map, and a thin sharp one so the edge still has an edge. A blur
    // alone looks like a rendering fault on a dark ground.
    return ZStack {
      shape.strokeBorder(sweep, lineWidth: 14).blur(radius: 11).opacity(0.55)
      shape.strokeBorder(sweep, lineWidth: 2.5).opacity(0.9)
    }
    // On the shapes rather than on the outer Group: this is what has to reach
    // the bezel, and an expansion applied further out has a conditional and a
    // TimelineView to travel through first.
    .ignoresSafeArea()
  }

  /// The display's own corner.
  ///
  /// Measured rather than guessed: a probe build drew 47.33, 55 and
  /// `ContainerRelativeShape` over each other and photographed the result. 55
  /// hugs the bezel, 47.33 sits visibly inside it, and `ContainerRelativeShape`
  /// -- which sounds like exactly the right tool -- renders as a plain
  /// rectangle outside a widget and is no use at all.
  ///
  /// A constant because there is no public API for this. SwiftUI does carry a
  /// `displayCornerRadius` environment value, but it is absent from the public
  /// swiftinterface: it is SPI, and shipping it would be shipping private API.
  /// So this is one number that will need revisiting on a device that rounds
  /// differently, and it is written down here rather than left as a mystery.
  ///
  /// `.continuous` because a display corner is a squircle, not an arc -- a
  /// circular corner of the *right* radius still reads as the wrong shape
  /// beside it.
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 55, style: .continuous)
  }

  private var ring: [Color] {
    let colours = Accents.all.map { MapRenderer.color($0.color) }
    return colours + colours + [colours[0]]
  }
}
