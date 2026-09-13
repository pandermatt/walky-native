import SwiftUI
import WalkyCore

/// Say what the place is, and let the model draw it.
///
/// The third importer's section, beside `RealMapSection` and `RoomScanSection`
/// and built like them. The one thing it does differently is that it can be
/// *entirely* unavailable -- not busy, not failed, but not on offer at all --
/// because Apple Intelligence needs both an iOS 26 phone and a capable one. So
/// the reason takes the place of the controls rather than appearing under them:
/// a text field that cannot do anything is worse than no text field.
@available(iOS 26.0, *)
struct DescribeSceneSection: View {
  let world: WalkyWorld
  @Bindable var generator: SceneGenerator
  /// Closes the sheet, and it is not a nicety. `AppModel.tick` stops drawing
  /// entirely while anything covers the map -- `isCovered` -- so a plan
  /// streamed in behind this sheet is invisible *and* wasted: the outlines are
  /// built for a frame that is never painted. The whole point of streaming is
  /// watching it arrive, so asking for one gets out of its way.
  let onStart: () -> Void

  var body: some View {
    Section {
      if let unavailable = SceneGenerator.unavailable {
        Text(unavailable).font(.footnote).foregroundStyle(.secondary)
        // The sample stays reachable. The half of this feature that lays walls
        // out does not need Apple Intelligence, and on a phone that cannot run
        // the model this is the only way to see it work at all.
        Button("Place the example plan") {
          generator.placeSample(into: world)
          onStart()
        }
          .font(.footnote)
          .disabled(generator.isBusy)
      } else {
        HStack {
          TextField("A place, in a sentence", text: $generator.query, axis: .vertical)
            .lineLimit(1...3)
            .submitLabel(.go)
            .onSubmit(run)
          if !generator.isBusy {
            Button("Draw", action: run)
              .disabled(generator.query.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }

        if generator.isBusy {
          // Indeterminate while the model writes, because there is no length to
          // report -- `SceneGenerator.fraction` returns nil for exactly that
          // phase, as the other two importers do for their own unmeasurable one.
          ProgressView(value: generator.progress, total: 1)
            .progressViewStyle(.linear)
        }
      }

      switch generator.phase {
      case .idle:
        EmptyView()
      case .thinking(let parts):
        Text(parts == 0 ? "Thinking…"
                        : "Laying out \(parts) \(parts == 1 ? "wall" : "walls")…")
          .font(.footnote).foregroundStyle(.secondary)
      case .placing:
        Text("Placing the walls…").font(.footnote).foregroundStyle(.secondary)
      case .routing:
        Text("Building the navigation graph…").font(.footnote).foregroundStyle(.secondary)
      case .done(let what):
        Text(what).font(.footnote).foregroundStyle(.secondary)
      case .failed(let why):
        Text(why).font(.footnote).foregroundStyle(.red)
      }

      // What the plan needed doing to it before it would work. Shown rather
      // than swallowed: the model is often wrong in ways that change the map,
      // and quietly building something else is how a tool loses trust.
      if !generator.notes.isEmpty, case .done = generator.phase {
        Text("Repaired: " + generator.notes.joined(separator: ", ") + ".")
          .font(.footnote).foregroundStyle(.orange)
      }
      // The name, the sparkle and the BETA all live on the row that leads
      // here now -- `SettingsSheetView.mapsPage` -- so that somebody deciding
      // whether to trust this meets the word before the text field rather than
      // after it. A header here would only say the page title twice.
      //
      // (`sparkles`, not `apple.intelligence`: that symbol exists in the iOS 26
      // set, but so does `apple.logo`, and shipping either is trademark use of
      // Apple's mark rather than a picture of a feature.)
    } footer: {
      Text("Apple Intelligence lays out walls and openings on device; Walky "
         + "squares them up and walks the crowd. Drawing replaces your map.")
    }
  }

  private func run() {
    generator.describe(into: world)
    onStart()
  }
}

/// A word that means "this will change".
///
/// On the header rather than the footer because it qualifies the feature's
/// name, not its explanation -- and a reader who is deciding whether to trust
/// the output should meet it before the text field, not after.
struct BetaTag: View {
  var body: some View {
    Text("BETA")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(.secondary.opacity(0.2), in: Capsule())
  }
}
