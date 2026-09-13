import Testing
import Foundation
@testable import WalkyCore
@testable import WalkyGeo
@testable import WalkySim

/// **Not a port.** Nothing on the web side describes a space in words.
///
/// The `real…` cases are transcripts of what the on-device model actually
/// answered, typed in unchanged, and they are the point of the suite: the
/// repair exists to survive what the tool does rather than what it was asked
/// to do. Every one of them exposed something -- the field pinned at its
/// minimum whatever the description, the same wall stated twice, an unshakeable
/// fondness for 0.5.

private let R: Double = 13
private var floorGap: Double { FlowLimits.minGap(R) }

private func gap(_ at: Double, _ m: Double) -> FlowGap { FlowGap(at: at, metres: m) }

private func plan(_ barriers: [FlowBarrier] = [], blocks: [FlowBlock] = [],
                  field: (Double, Double) = (30, 24)) -> FlowPlan {
  FlowPlan(title: "t", fieldWidth: field.0, fieldDepth: field.1,
           barriers: barriers, blocks: blocks)
}

@Suite("Repairing a flow study")
struct FlowRepairTests {

  @Test("a study that was already good is left alone")
  func leavesGoodPlansAlone() {
    let fixed = repairFlow(.sample, radius: R)
    #expect(fixed.isUsable)
    #expect(fixed.notes.isEmpty)
    #expect(fixed.plan == FlowPlan.sample)
  }

  @Test("an opening too tight to route through is widened to one that works")
  func widensGaps() {
    // 0.3m fits a body and is *below* the node-culling threshold, which is the
    // failure with no symptom: the crowd would stand still on a map that looks
    // perfectly fine. See `FlowLimits.minGap`.
    let fixed = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5,
                                             gaps: [gap(0.5, 0.3)])]), radius: R)
    let opening = fixed.plan.barriers[0].gaps[0].metres
    #expect(opening >= floorGap)
    #expect(opening * PX_PER_METRE > 2 * R + 2)   // clear of NODE_MARGIN culling
    #expect(gapSeals(opening * PX_PER_METRE, R) == false)
  }

  @Test("a solid wall is given a way through, so the goal stays reachable")
  func neverSealsTheField() {
    let fixed = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5, gaps: [])]),
                           radius: R)
    #expect(fixed.plan.barriers[0].gaps.count == 1)
    #expect(fixed.notes.contains { $0.contains("way through") })
  }

  @Test("openings that overlap, or leave a splinter between them, become one")
  func mergesGaps() {
    let overlapping = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5,
                                                   gaps: [gap(0.5, 6), gap(0.55, 6)])]),
                                 radius: R)
    #expect(overlapping.plan.barriers[0].gaps.count == 1)

    // Two metres apart on a 30m wall is a scrap of wall narrower than a person.
    let splinter = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5,
                                                gaps: [gap(0.40, 2), gap(0.47, 2)])]),
                              radius: R)
    #expect(splinter.plan.barriers[0].gaps.count == 1)

    // Far apart stays two doors, which is a different study and must survive.
    let two = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5,
                                           gaps: [gap(0.2, 2), gap(0.8, 2)])]), radius: R)
    #expect(two.plan.barriers[0].gaps.count == 2)
  }

  @Test("the same wall said twice is one wall")
  func dedupesBarriers() {
    let fixed = repairFlow(plan([
      FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.5, 2)]),
      FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.5, 2)]),
      // A different axis at the same place is a crossing, not a duplicate.
      FlowBarrier(across: .eastWest, at: 0.5, gaps: [gap(0.5, 2)]),
    ]), radius: R)
    #expect(fixed.plan.barriers.count == 2)
    #expect(fixed.notes.contains { $0.contains("twice") })
  }

  @Test("the field is kept at the size it was described")
  func keepsTheField() {
    let fixed = repairFlow(plan(field: (40, 30)), radius: R)
    #expect(fixed.plan.fieldWidth == 40)
    #expect(fixed.plan.fieldDepth == 30)
  }

  @Test("the goal is put across the walls, not along them")
  func aimsAcrossTheBarriers() {
    // Walls running east-west are ones you cross going north or south, so the
    // goal belongs on a north or south edge. The model used to pick this and
    // picked it at random, which made half its studies a stroll down a corridor.
    #expect(plan([FlowBarrier(across: .eastWest, at: 0.5, gaps: [gap(0.5, 2)])]).goal
            == .south)
    #expect(plan([FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.5, 2)])]).goal
            == .east)
    // An open field still needs somewhere to walk to.
    #expect(plan().goal == .south)
  }

  @Test("a block standing in a doorway is dropped, one in the open is kept")
  func keepsOpeningsClear() {
    let barrier = FlowBarrier(across: .eastWest, at: 0.5, gaps: [gap(0.5, 2)])
    let inTheWay = repairFlow(plan([barrier],
                                   blocks: [FlowBlock(x: 0.5, y: 0.5, width: 2, depth: 2)]),
                              radius: R)
    #expect(inTheWay.plan.blocks.isEmpty)
    #expect(inTheWay.notes.contains { $0.contains("doorway") })

    let clear = repairFlow(plan([barrier],
                                blocks: [FlowBlock(x: 0.5, y: 0.1, width: 2, depth: 2)]),
                           radius: R)
    #expect(clear.plan.blocks.count == 1)
  }

  @Test("wild numbers are clamped rather than believed")
  func clampsWildNumbers() {
    let fixed = repairFlow(FlowPlan(title: "t", fieldWidth: 9_000, fieldDepth: -4,
                                    barriers: [FlowBarrier(across: .eastWest, at: 40,
                                                           gaps: [gap(-3, 900)])],
                                    blocks: [FlowBlock(x: 8, y: -8,
                                                       width: 900, depth: 900)]),
                           radius: R)
    #expect(fixed.plan.fieldWidth <= FlowLimits.maxField)
    #expect(fixed.plan.fieldDepth >= FlowLimits.minField)
    let b = fixed.plan.barriers[0]
    #expect(b.at >= 0 && b.at <= 1)
    #expect(b.gaps.allSatisfy { $0.metres <= fixed.plan.fieldWidth })
  }

  @Test("an opening at the very end of a wall keeps its full width")
  func insetsGapsFromTheEnds() {
    // The silent version of the jam: `at: 1` clamps into range and the width
    // survives the record, but half the opening hangs off the end of the wall,
    // `flowPlacement` clips it against the field, and the crowd meets half of
    // what the floor promised.
    let fixed = repairFlow(plan([FlowBarrier(across: .eastWest, at: 0.5,
                                             gaps: [gap(1.0, 3)])],
                                field: (30, 24)), radius: R)
    let g = fixed.plan.barriers[0].gaps[0]
    let along = 30.0
    #expect(g.at * along - g.metres / 2 >= -0.001)     // wholly on the wall
    #expect(g.at * along + g.metres / 2 <= along + 0.001)

    let built = flowPlacement(fixed.plan, radius: R)
    let bars = built.walls[1]
    let left = bars.map { $0.map(\.x).max()! }.min()!
    let right = bars.map { $0.map(\.x).min()! }.max()!
    #expect(right - left >= FlowLimits.minGap(R) * PX_PER_METRE - 2)
  }

  @Test("two walls are compared across the axis their position is measured on")
  func dedupesOnTheRightAxis() {
    // On a long thin field these two east-west walls are 0.5m apart, which is
    // a duplicate. Scaling the fraction by the barrier's *run* rather than the
    // axis it sits on scored them as 5m and kept both.
    let fixed = repairFlow(plan([
      FlowBarrier(across: .eastWest, at: 0.50, gaps: [gap(0.5, 2)]),
      FlowBarrier(across: .eastWest, at: 0.55, gaps: [gap(0.5, 2)]),
    ], field: (100, 10)), radius: R)
    #expect(fixed.plan.barriers.count == 1)
    #expect(fixed.notes.contains { $0.contains("twice") })
  }

  @Test("a block stays inside the field rather than half through the wall")
  func keepsBlocksInside() {
    let fixed = repairFlow(plan(blocks: [FlowBlock(x: 0, y: 1, width: 6, depth: 4)],
                                field: (30, 24)), radius: R)
    let b = fixed.plan.blocks[0]
    #expect(b.x * 30 - b.width / 2 >= -0.001)
    #expect(b.y * 24 + b.depth / 2 <= 24.001)
  }

  @Test("the floor allows for the room a body wants, not just the room it takes")
  func floorClearsPersonalSpace() {
    // The measured failure: 1m satisfies every geometric rule and still jams,
    // because obstacle inflation leaves 0.54m for a body that wants 0.71m.
    #expect(FlowLimits.minGap(R, personalSpace: 40) * PX_PER_METRE > 2 * R + 40 - 0.001)
    #expect(FlowLimits.minGap(R, personalSpace: 40) > 1.0)
  }
}

@Suite("Building a flow study")
struct FlowPlacementTests {

  @Test("the field is enclosed, and every barrier reaches the wall")
  func encloses() {
    let built = flowPlacement(repairFlow(.sample, radius: R).plan, radius: R)
    // Border, plus one wall for the barrier.
    #expect(built.walls.count == 2)
    #expect(built.walls[0].count == 4)          // four bars of the frame
    #expect(built.walls[1].count == 2)          // the barrier, either side of its gap

    // Both bars run past the field's edge, into the border, so the seal cannot
    // depend on two numbers being exactly equal.
    let w = FlowPlan.sample.fieldWidth * PX_PER_METRE
    let xs = built.walls[1].flatMap { $0.map(\.x) }
    #expect(xs.min()! < 0)
    #expect(xs.max()! > w)
  }

  @Test("the opening survives into the geometry at a width a body fits")
  func keepsTheOpening() {
    let built = flowPlacement(repairFlow(.sample, radius: R).plan, radius: R)
    let bars = built.walls[1]
    // The gap is the space between the two bars' facing edges.
    let left = bars.map { $0.map(\.x).max()! }.min()!
    let right = bars.map { $0.map(\.x).min()! }.max()!
    let opening = right - left
    #expect(opening > 2 * R + 2)
    #expect(abs(opening - 1.2 * PX_PER_METRE) < 2)
  }

  @Test("the goal is a bar on its own edge, with its anchor inside it")
  func buildsAGoal() {
    let plan = repairFlow(.sample, radius: R).plan
    let built = flowPlacement(plan, radius: R)
    #expect(built.exits.count == 1)
    let goal = built.exits[0]
    #expect(goal.slab.count == 4)
    // `setGoalAt` point-tests the anchor against the wall's own polygon, so it
    // has to be inside rather than merely near.
    let xs = goal.slab.map(\.x), ys = goal.slab.map(\.y)
    #expect(goal.at.x > xs.min()! && goal.at.x < xs.max()!)
    #expect(goal.at.y > ys.min()! && goal.at.y < ys.max()!)
    // South edge, so it sits at the bottom of the field.
    #expect(goal.at.y > plan.fieldDepth * PX_PER_METRE * 0.9)
  }

  @Test("the crowd starts on the far side of the barrier from the goal")
  func startsBehindTheBarrier() {
    let plan = repairFlow(.sample, radius: R).plan
    let built = flowPlacement(plan, radius: R)
    let barrier = plan.barriers[0].at * plan.fieldDepth * PX_PER_METRE
    // Goal is south, barrier at 0.55, so the crowd must be north of it.
    #expect(built.crowdAt!.y < barrier)
    #expect(built.crowdCells! >= 2)
  }

  @Test("no doors are placed: the crowd is the study")
  func noInflow() {
    let built = flowPlacement(repairFlow(.sample, radius: R).plan, radius: R)
    #expect(built.entrances.isEmpty)
    #expect(built.crowdAt != nil)
  }

  @Test("every vertex is a whole number, and the corner budget holds")
  func quantisesAndFits() {
    let built = flowPlacement(repairFlow(.sample, radius: R).plan, radius: R)
    for wall in built.walls {
      for polygon in wall {
        #expect(polygon.count >= 3)
        for p in polygon { #expect(p.x == jsRound(p.x) && p.y == jsRound(p.y)) }
      }
    }
    #expect(ImportBudget.fits(built.walls.flatMap { $0 }))
  }
}

@Suite("What the model actually answered")
struct RealFlowTests {

  /// "a narrow passage" — the request the old rooms-and-doors schema could not
  /// express at all. Two crossed barriers at 0.5, 1m openings, a 10x10 field.
  @Test("a narrow passage")
  func narrowPassage() {
    let raw = FlowPlan(title: "A Narrow Passage", fieldWidth: 10, fieldDepth: 10,
      barriers: [
        FlowBarrier(across: .eastWest, at: 0.5, gaps: [gap(0.10, 1), gap(0.40, 1)]),
        FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.10, 1), gap(0.40, 1)]),
      ],
      blocks: [FlowBlock(x: 0.20, y: 0.20, width: 1, depth: 1)])

    let fixed = repairFlow(raw, radius: R)
    #expect(fixed.isUsable)
    // The whole point: every opening is one a crowd can actually get through.
    for barrier in fixed.plan.barriers {
      #expect(!barrier.gaps.isEmpty)
      for g in barrier.gaps { #expect(g.metres >= floorGap) }
    }
    let built = flowPlacement(fixed.plan, radius: R)
    #expect(built.exits.count == 1)
    #expect(ImportBudget.fits(built.walls.flatMap { $0 }))
  }

  /// "pillars in a big hall" — the same barrier twice, and six blocks walking
  /// a diagonal.
  @Test("pillars in a big hall")
  func pillars() {
    let raw = FlowPlan(title: "Pillars in a Big Hall", fieldWidth: 120, fieldDepth: 20,
      barriers: [
        FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.10, 1), gap(0.90, 1)]),
        FlowBarrier(across: .northSouth, at: 0.5, gaps: [gap(0.10, 1), gap(0.90, 1)]),
      ],
      blocks: (1...6).map { FlowBlock(x: Double($0) / 10, y: Double($0) / 10,
                                      width: 10, depth: 10) })

    let fixed = repairFlow(raw, radius: R)
    #expect(fixed.isUsable)
    #expect(fixed.plan.barriers.count == 1)
    #expect(fixed.notes.contains { $0.contains("twice") })
    #expect(ImportBudget.fits(flowPlacement(fixed.plan, radius: R).walls.flatMap { $0 }))
  }

  /// "a station platform emptying through four gates" — 200 people on a 10x10
  /// field, and three 1m gates rather than four.
  @Test("a station platform")
  func stationPlatform() {
    let raw = FlowPlan(title: "Station Platform Emptying", fieldWidth: 10, fieldDepth: 10,
      barriers: [FlowBarrier(across: .eastWest, at: 0.5,
                             gaps: [gap(0.25, 1), gap(0.50, 1), gap(0.75, 1)])],
      blocks: [FlowBlock(x: 0.30, y: 0.50, width: 1, depth: 2),
               FlowBlock(x: 0.70, y: 0.50, width: 1, depth: 2)])

    let fixed = repairFlow(raw, radius: R)
    #expect(fixed.isUsable)
    #expect(fixed.plan.blocks.isEmpty)           // both were sitting in the gates
    // Three gates, and all of them wide enough to walk through.
    #expect(fixed.plan.barriers[0].gaps.count == 3)
    #expect(fixed.plan.barriers[0].gaps.allSatisfy { $0.metres >= floorGap })
  }
}
