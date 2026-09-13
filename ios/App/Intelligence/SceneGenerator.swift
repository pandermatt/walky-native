import Foundation
import FoundationModels
import Observation
import WalkyCore
import WalkyGeo
import WalkySim

/// A described space, laid out by the on-device model.
///
/// The third importer, beside `MapImporter` and `RoomScanner`, and shaped like
/// both: `@MainActor @Observable`, a `phase` the sheet reads, and `step()` to
/// move it along.
///
/// **This file is deliberately thin.** Everything it does is: ask the model,
/// hand what comes back to `repairFlow`, and place the result. The judgement --
/// what to do about an opening too tight to route through, a wall stated twice,
/// or a field too small for the crowd standing on it -- is in
/// `WalkyCore/FlowPlan.swift`, framework-free and under `swift test`, which is
/// the same split RoomPlan gets and for the same reason. The `@Generable` types
/// below never leave this file; `FlowPlan` does.
///
/// Gated on iOS 26 at the type level rather than per-method: the whole feature
/// is unavailable below it, and the settings sheet asks `SceneGenerator.status`
/// before it offers anything.
@available(iOS 26.0, *)
@MainActor
@Observable
final class SceneGenerator {

  // MARK: - What the model is asked for

  @Generable
  enum ModelAcross: String {
    case eastWest, northSouth
  }

  @Generable
  struct ModelGap {
    @Guide(description: "Where along the wall the opening is: 0 is one end, 0.5 the middle, 1 the other end.",
           .range(0...1))
    var at: Double
    @Guide(description: "How wide the opening is, in metres. 1.5 is a squeeze, "
                     + "3 is a doorway, 8 is a gateway.", .range(1.5...20))
    var metres: Double
  }

  @Generable
  struct ModelBarrier {
    @Guide(description: "Which way this wall runs across the field.")
    var across: ModelAcross
    @Guide(description: "How far across the field the wall sits: 0 at one edge, 0.5 the middle, 1 the far edge.",
           .range(0...1))
    var at: Double
    @Guide(description: "The openings in this wall. One small opening makes a bottleneck.",
           .count(1...4))
    var gaps: [ModelGap]
  }

  @Generable
  struct ModelBlock {
    @Guide(description: "Position across the field, 0 at the west edge, 1 at the east.",
           .range(0...1))
    var x: Double
    @Guide(description: "Position down the field, 0 at the north edge, 1 at the south.",
           .range(0...1))
    var y: Double
    @Guide(description: "Width in metres.", .range(1...30))
    var width: Double
    @Guide(description: "Depth in metres.", .range(1...30))
    var depth: Double
  }

  @Generable
  struct ModelPlan {
    @Guide(description: "Two to four words naming the study.")
    var title: String
    @Guide(description: "How wide the field is, east to west, in metres. A room is 10, a concourse 40, a square 100.",
           .range(10...120))
    var fieldWidth: Int
    @Guide(description: "How deep the field is, north to south, in metres.", .range(10...120))
    var fieldDepth: Int
    @Guide(description: "Walls straight across the field, each with openings in it.",
           .count(0...5))
    var barriers: [ModelBarrier]
    @Guide(description: "Freestanding obstacles standing in the open, clear of the walls.",
           .count(0...6))
    var blocks: [ModelBlock]
  }

  /// What the model is told before it is asked anything.
  ///
  /// **The rewrite that made this feature work.** It used to ask for rooms and
  /// doors, and the result could not produce a narrow passage -- the one thing a
  /// pedestrian simulator is for -- because a passage was then two rectangles
  /// whose edges had to leave a gap, which is arithmetic between two numbers and
  /// the thing a small model cannot do. Here the opening is a field the model
  /// states outright, and positions are fractions so it never has to know how
  /// wide the field is to put something in the middle of it.
  ///
  /// The concrete widths in the last paragraph are doing real work: without
  /// them every opening came back as exactly 1 metre.
  ///
  /// It no longer asks for the crowd, the goal or the doors either. It answered
  /// ten people to nearly everything and picked a goal edge at random -- often
  /// one *along* its own walls, making a study out of a stroll. All three are
  /// better derived: see `FlowPlan.goal` and `crowdBlock`.
  private static let instructions = """
    You design floor plans for a pedestrian crowd simulation, seen from above.

    The map is an open field with a wall around it. You place only the walls:
    - barriers: walls straight across the field, each with openings in it
    - blocks: freestanding obstacles standing in the open

    Somebody else decides where the crowd starts and which way it walks. Your
    job is the shape of the place.

    Positions are fractions of the field, never metres: 0 is one edge, 0.5 the
    middle, 1 the far edge. Only sizes are in metres.

    An opening of 1.5 metres is a squeeze one person at a time; 2 to 4 metres is
    a normal doorway; 8 metres is a wide gateway. Never use an opening under 1.5
    metres: a crowd cannot get through it at all.

    Vary the numbers. Walls belong wherever the place puts them -- 0.3, 0.45,
    0.72 -- not always halfway. Two walls on the same axis must be well apart.
    """

  /// How the answer is decoded, which turned out to matter more than any
  /// wording.
  ///
  /// The default is effectively greedy -- the most likely token every time --
  /// and a model taking the most likely token answers `0.5` to "a fraction
  /// across the field" *every time*. Measured over twelve prompts x three runs:
  /// 79% of walls landed on exactly 0.50, and seventy walls between them used
  /// six distinct positions. No wording beats a decoder that cannot pick a
  /// second-best token; with `top 60` at temperature 1 the same run gives 26%
  /// and twenty positions.
  ///
  /// No seed, so asking twice gives two maps -- which is what asking twice is
  /// for. `temperature` is documented as 0...1 inclusive, so 1 is the ceiling
  /// rather than a number picked to sound bold.
  private static let sampling = GenerationOptions(sampling: .random(top: 60),
                                                  temperature: 1.0)

  // MARK: - State

  enum Phase: Equatable {
    case idle
    /// The model is writing. The count is barriers and blocks so far.
    case thinking(parts: Int)
    case placing
    /// The visibility rebuild, as both other importers label it.
    case routing
    case done(String)
    case failed(String)
  }

  private(set) var phase: Phase = .idle
  private(set) var progress: Double?
  /// What the repair had to change, shown under the result. Empty when the
  /// model's plan was used as it stood, which does happen.
  private(set) var notes: [String] = []
  var query: String = ""
  /// The summary line, for the notice capsule. The sheet that would have shown
  /// it is dismissed the moment a plan is asked for, so that the streaming can
  /// be watched -- which leaves the result with nowhere else to go.
  /// `RoomScanner` carries the same callback for the same reason.
  var onNotice: ((String) -> Void)?

  private var task: Task<Void, Never>?

  var isBusy: Bool {
    switch phase {
    case .thinking, .placing, .routing: true
    default: false
    }
  }

  /// Why the feature is not on offer, or nil when it is.
  ///
  /// Each reason gets its own sentence because they need different actions from
  /// whoever is reading: one is "your phone cannot", one is "turn it on", and
  /// one is "wait".
  static var unavailable: String? {
    switch SystemLanguageModel.default.availability {
    case .available:
      return nil
    case .unavailable(.deviceNotEligible):
      return "This iPhone does not run Apple Intelligence."
    case .unavailable(.appleIntelligenceNotEnabled):
      return "Turn on Apple Intelligence in Settings to describe a map."
    case .unavailable(.modelNotReady):
      return "Apple Intelligence is still downloading its model."
    case .unavailable:
      return "Apple Intelligence is not available right now."
    @unknown default:
      return "Apple Intelligence is not available right now."
    }
  }

  // MARK: - Generating

  func cancel() {
    task?.cancel()
    task = nil
  }

  func describe(into world: WalkyWorld) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    cancel()
    notes = []
    step(.thinking(parts: 0))

    task = Task {
      defer { world.transientPreview = nil }
      do {
        let session = LanguageModelSession(instructions: Self.instructions)
        var latest: FlowPlan?

        // Streamed rather than awaited whole, so the plan arrives a room at a
        // time. Each snapshot is repaired and drawn as an *outline* -- never
        // built into the world, which would run the superquadratic navigation
        // rebuild once per token and stutter the app to a stop.
        for try await partial in session.streamResponse(
      to: text, generating: ModelPlan.self, options: Self.sampling) {
          guard !Task.isCancelled else { return }
          let plan = Self.plan(from: partial.content)
          latest = plan
          step(.thinking(parts: plan.barriers.count + plan.blocks.count))
          world.transientPreview = Self.outline(
            of: plan, radius: world.settings.pedestrianRadius,
            personalSpace: world.settings.personalSpace)
        }

        guard !Task.isCancelled else { return }
        guard let latest else {
          fail("The model did not answer with a plan.")
          return
        }
        await place(latest, into: world)
      } catch let error as LanguageModelSession.GenerationError {
        fail(Self.describe(error))
      } catch is CancellationError {
        phase = .idle
      } catch {
        fail(error.localizedDescription)
      }
    }
  }

  /// Place the sample, for a device where the model is not on offer -- and for
  /// checking the half of this feature that is not the model. `RoomScanner`
  /// carries the same door, for the same reason.
  func placeSample(into world: WalkyWorld) {
    cancel()
    notes = []
    task = Task { await place(.sample, into: world) }
  }

  private func place(_ raw: FlowPlan, into world: WalkyWorld) async {
    let radius = world.settings.pedestrianRadius
    let fixed = repairFlow(raw, radius: radius,
                           personalSpace: world.settings.personalSpace)
    notes = fixed.notes
    if let problem = fixed.problem {
      fail(problem)
      return
    }

    step(.placing)
    world.transientPreview = nil

    // No matching-back to do any more. The old schema returned doors that
    // `roomWalls` re-emitted in wall order, so each had to be found again by
    // position; here the goal and the inflow doors are built as themselves.
    let placement = flowPlacement(fixed.plan, radius: radius,
                                  thickness: world.settings.borderThickness)
    let goal = await world.place(placement,
                                 onRouting: { [weak self] in self?.step(.routing) })

    progress = nil
    let line = Self.summary(fixed.plan, hasGoal: goal != nil)
    phase = .done(line)
    onNotice?(notes.isEmpty ? line : line + " " + notes.joined(separator: ", ") + ".")
  }

  // MARK: - Converting what came back

  /// A partially generated plan, taking only what has fully arrived.
  ///
  /// Every field of a streamed value is optional until it lands, so a barrier
  /// that is half-written is skipped rather than guessed at -- one with a
  /// position and no openings would be drawn as a solid wall and then jump.
  private static func plan(from partial: ModelPlan.PartiallyGenerated) -> FlowPlan {
    let barriers: [FlowBarrier] = (partial.barriers ?? []).compactMap { b in
      guard let across = b.across, let at = b.at else { return nil }
      let gaps: [FlowGap] = (b.gaps ?? []).compactMap { g in
        guard let at = g.at, let metres = g.metres else { return nil }
        return FlowGap(at: at, metres: metres)
      }
      guard !gaps.isEmpty else { return nil }
      return FlowBarrier(across: across == .eastWest ? .eastWest : .northSouth,
                         at: at, gaps: gaps)
    }
    let blocks: [FlowBlock] = (partial.blocks ?? []).compactMap { b in
      guard let x = b.x, let y = b.y, let width = b.width, let depth = b.depth
      else { return nil }
      return FlowBlock(x: x, y: y, width: width, depth: depth)
    }
    return FlowPlan(title: partial.title ?? "",
                    fieldWidth: Double(partial.fieldWidth ?? 30),
                    fieldDepth: Double(partial.fieldDepth ?? 24),
                    barriers: barriers, blocks: blocks)
  }

  /// The plan so far, as outlines to draw over the map.
  ///
  /// Repaired first, so what appears while the model writes is what would be
  /// built if it stopped there -- a preview of the raw answer would jump every
  /// time a field was grown or an opening widened, which reads as a bug rather
  /// than as a plan being assembled.
  private static func outline(of plan: FlowPlan, radius: Double,
                              personalSpace: Double) -> ToolPreview {
    let fixed = repairFlow(plan, radius: radius, personalSpace: personalSpace)
    var preview = ToolPreview()
    preview.pendingPolygons = flowPlacement(fixed.plan, radius: radius)
      .walls.flatMap { $0 }
    return preview
  }

  // MARK: - Saying what happened

  private func step(_ next: Phase, _ fraction: Double? = nil) {
    phase = next
    progress = fraction ?? Self.fraction(of: next)
  }

  private func fail(_ message: String) {
    progress = nil
    phase = .failed(message)
    onNotice?(message)
  }

  /// Weights, and honest about it -- as both other importers are. Thinking has
  /// no length to report: the model finishes when it finishes.
  private static func fraction(of phase: Phase) -> Double? {
    switch phase {
    case .placing: 0.8
    case .routing: 0.95
    default: nil
    }
  }

  private static func summary(_ plan: FlowPlan, hasGoal: Bool) -> String {
    var parts = ["\(Int(plan.fieldWidth))x\(Int(plan.fieldDepth)) m"]
    if !plan.barriers.isEmpty {
      let gaps = plan.barriers.reduce(0) { $0 + $1.gaps.count }
      parts.append("\(plan.barriers.count) \(plan.barriers.count == 1 ? "wall" : "walls")")
      // The narrowest opening is the headline of a flow study, and the number
      // somebody asked for when they typed "narrow".
      if let tightest = plan.barriers.flatMap({ $0.gaps }).map(\.metres).min() {
        parts.append("\(gaps) \(gaps == 1 ? "gap" : "gaps"), "
                   + "narrowest \(String(format: "%.1f", tightest)) m")
      }
    }
    if !plan.blocks.isEmpty { parts.append("\(plan.blocks.count) obstacles") }
    if !hasGoal { parts.append("no way out") }
    return parts.joined(separator: ", ") + "."
  }

  private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
    switch error {
    case .guardrailViolation:
      "Apple Intelligence would not answer that one. Try describing a place."
    case .exceededContextWindowSize:
      "That description is too long. Try a shorter one."
    case .unsupportedLanguageOrLocale:
      "Apple Intelligence does not handle that language yet."
    default:
      "Apple Intelligence could not lay that out."
    }
  }
}
