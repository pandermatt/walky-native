import Foundation
import Observation
import SwiftUI
import WalkyCore

/// The window-level state the menu bar and the window both have to reach.
///
/// On the phone all of this is `@State` inside `RootView`, because the only
/// thing that can ask to open a map is a control inside that view. A Mac has a
/// menu bar, which is a second scene: File ▸ Open has to raise the same
/// importer the Settings window's button does, and neither can reach the
/// other's `@State`. So the three flags move out here, shared the way
/// `AppModel` is and for the same reason.
///
/// The map is snapshotted when Save is *chosen*, not when the panel returns:
/// `fileExporter` asks for its document while the panel is up, and with the
/// simulation running that would write wherever the crowd had walked to by the
/// time somebody picked a folder rather than the map they chose to save.
@MainActor
@Observable
final class MacShell {
  static let shared = MacShell()

  var opening = false
  var saving = false
  var welcome = false
  /// Held while the exporter is up; see the note on the type.
  var outgoing: WalkyMapDocument?
  var outgoingName = "Walky map"

  /// True while anything is over the map, which is what pauses its frames --
  /// the phone's `isCovered`, said about panels and windows instead of sheets.
  var isCovered: Bool { opening || saving || welcome }

  func startOpen() { opening = true }

  func startSave(_ model: AppModel) {
    let core = model.world.captureScenario()
    outgoing = WalkyMapDocument(bytes: MapFile.data(core))
    outgoingName = MapFile.suggestedName(walls: model.world.walls.count,
                                         pedestrians: model.world.agents.count)
    saving = true
  }

  /// A file, from the importer or from the Finder.
  ///
  /// The security-scoped dance is not optional: a URL out of the importer is
  /// somebody else's file, and a sandboxed app reading it without the access
  /// call fails at the one moment nobody is watching.
  func open(_ url: URL, into model: AppModel) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let core = try MapFile.read(try Data(contentsOf: url))
      model.world.apply(core)
      model.show("Opened \(url.deletingPathExtension().lastPathComponent).")
    } catch let error as ScenarioLinkError {
      // The codec's own sentence, which is written to be shown: "not a Walky
      // map", "saved by a newer Walky", "larger than Walky can hold".
      model.show(error.message)
    } catch {
      model.show(error.localizedDescription)
    }
  }
}
