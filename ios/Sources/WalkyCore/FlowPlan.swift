import Foundation
import WalkyGeo
import WalkySim

/// A crowd-flow study, described in words and laid out here.
///
/// **This replaced a floorplan.** The first version of the describe-a-map
/// feature asked the model for rooms and doors, and it could not produce the
/// one thing a pedestrian simulator is for: a narrow passage. Not because the
/// model is stupid, but because that schema made a passage into arithmetic --
/// two rectangles whose *edges* had to leave a 1.2m gap, which is two absolute
/// coordinates that must be correct **relative to each other**. Relating two
/// numbers is precisely what a small on-device model cannot do.
///
/// So the vocabulary changed to Walky's own. A map here is obstacles on open
/// ground: a bounded field, walls straight across it with the openings **stated
/// outright**, blocks standing in the open, an edge everybody walks to. A narrow
/// passage stops being an emergent property of two coordinates and becomes a
/// field called `metres`.
///
/// The rule the whole design follows: **never make the model compute a
/// relationship between two numbers.** Positions are fractions of the field, so
/// it never has to know the field is 40m to put something in the middle of it;
/// gaps are widths, not the space left between two things; the field is grown
/// to fit the crowd rather than asked to match it.
///
/// In `WalkyCore` rather than `WalkyGeo` -- where the room converter lives --
/// because it builds on `borderFrame` and hands back `RoomPlacement`, and both
/// are here. It is still framework-free and still under `swift test`.

// MARK: - What the model describes

public enum FlowSide: String, Codable, Sendable, CaseIterable {
  case north, south, east, west

  var opposite: FlowSide {
    switch self {
    case .north: .south
    case .south: .north
    case .east: .west
    case .west: .east
    }
  }

  /// True when this edge is reached by travelling along the y axis.
  var isVertical: Bool { self == .north || self == .south }
}

/// Which way a barrier runs. `eastWest` is a wall you walk north or south
/// through; `northSouth` is one you walk east or west through.
public enum FlowAxis: String, Codable, Sendable, CaseIterable {
  case eastWest, northSouth
}

/// An opening in a barrier. `at` is a fraction along the barrier's own length.
public struct FlowGap: Codable, Sendable, Equatable {
  public var at: Double
  public var metres: Double

  public init(at: Double, metres: Double) {
    self.at = at
    self.metres = metres
  }
}

/// A wall straight across the field. `at` is a fraction across the field,
/// perpendicular to the way the barrier runs.
public struct FlowBarrier: Codable, Sendable, Equatable {
  public var across: FlowAxis
  public var at: Double
  public var gaps: [FlowGap]

  public init(across: FlowAxis, at: Double, gaps: [FlowGap]) {
    self.across = across
    self.at = at
    self.gaps = gaps
  }
}

/// Something standing in the open: a pillar, a kiosk, a parked thing.
public struct FlowBlock: Codable, Sendable, Equatable {
  /// Fractions of the field.
  public var x: Double
  public var y: Double
  /// Metres.
  public var width: Double
  public var depth: Double

  public init(x: Double, y: Double, width: Double, depth: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.depth = depth
  }
}

public struct FlowPlan: Codable, Sendable, Equatable {
  public var title: String
  /// Metres.
  public var fieldWidth: Double
  public var fieldDepth: Double
  public var barriers: [FlowBarrier]
  public var blocks: [FlowBlock]

  public init(title: String, fieldWidth: Double, fieldDepth: Double,
              barriers: [FlowBarrier], blocks: [FlowBlock]) {
    self.title = title
    self.fieldWidth = fieldWidth
    self.fieldDepth = fieldDepth
    self.barriers = barriers
    self.blocks = blocks
  }

  /// Which edge the crowd walks to.
  ///
  /// **Decided here, not asked for.** The model picked an edge at random -- a
  /// study whose every wall runs east-west, with the goal to the east, is a
  /// crowd strolling down a corridor past walls it never has to cross. The
  /// interesting direction is the one the walls are across, so the goal is put
  /// perpendicular to whichever way most of them run, and the crowd starts
  /// opposite it with every barrier between.
  public var goal: FlowSide {
    let acrossY = barriers.filter { $0.across == .eastWest }.count
    let acrossX = barriers.count - acrossY
    return acrossX > acrossY ? .east : .south
  }
}

// MARK: - The limits a repair works to

public enum FlowLimits {
  public static let minField: Double = 8
  public static let maxField: Double = 120
  public static let maxBarriers = 6
  public static let maxBlocks = 8
  public static let maxCrowd = 400
  public static let maxInflow = 4

  /// The narrowest opening a crowd can actually flow through, in metres.
  ///
  /// Four thresholds govern a gap, and the last one is the one that matters:
  ///
  /// - a body fits at all above `2 * radius` -- `gapSeals`
  /// - a *visibility-graph node* survives in the mouth only above
  ///   `2 * radius + NODE_MARGIN`; below that `buildVisibilityGraph` culls every
  ///   node in the gap, the goal's Dijkstra field has no source there, every
  ///   route through costs infinity, and **the crowd stands still on a map that
  ///   looks perfect**
  /// - two people pass abreast at `4 * radius`
  /// - **a crowd under pressure flows only above `2 * radius + personalSpace`**
  ///
  /// The last was measured rather than reasoned. A 1m opening satisfies all
  /// three of the others -- and a hundred people at one moved two of
  /// themselves through it in three minutes and then stopped. Obstacle
  /// inflation eats a radius from each side, so a 1m gap leaves a 0.54m band
  /// for a body that wants 0.71m of room; pressed from behind, the crowd repels
  /// itself into both walls and locks. Allowing for the space a body *wants*
  /// rather than the space it occupies is what makes an opening a doorway
  /// instead of a plug.
  ///
  /// It is still narrow: at the shipped settings this is about 1.2m, which is
  /// one person at a time and a proper queue behind them.
  public static func minGap(_ radius: Double, personalSpace: Double = 40) -> Double {
    (2 * radius + personalSpace) / PX_PER_METRE
  }

  /// How thick a barrier is drawn, in metres -- the scanner's wall thickness,
  /// so a generated map and a scanned one look like the same kind of object.
  public static let barrierThickness: Double = WALL_THICKNESS

  /// How deep the goal bar is. A metre is enough to be unmistakably a wall and
  /// little enough not to eat the field.
  public static let goalDepth: Double = 1

  /// How wide each inflow door is.
  public static let inflowWidth: Double = 1.5
}

/// A plan, repaired, and a record of what had to be done to it.
public struct RepairedFlow: Sendable, Equatable {
  public var plan: FlowPlan
  public var notes: [String]
  public var problem: String?

  public var isUsable: Bool { problem == nil }
}

// MARK: - Repair

/// Make a described study into one that can be walked.
///
/// Written against what the model actually emits, which a probe run established
/// before any of this existed: fields pinned at the minimum whatever the
/// description, the same barrier stated twice, and a strong pull towards 0.5
/// and towards 0.1/0.2/0.3. None of that needs the model's help to fix.
public func repairFlow(_ raw: FlowPlan, radius: Double = 13,
                       personalSpace: Double = 40) -> RepairedFlow {
  var notes: [String] = []
  let floor = FlowLimits.minGap(radius, personalSpace: personalSpace)

  var width = clamp(jsRound(raw.fieldWidth), FlowLimits.minField, FlowLimits.maxField)
  var depth = clamp(jsRound(raw.fieldDepth), FlowLimits.minField, FlowLimits.maxField)
  let body = 2 * radius / PX_PER_METRE

  // Barriers: in range, deduplicated, and each with at least one opening wide
  // enough to walk through.
  var barriers: [FlowBarrier] = []
  var duplicates = 0
  for barrier in raw.barriers.prefix(FlowLimits.maxBarriers) {
    let at = clamp(barrier.at, 0.05, 0.95)
    // Two different dimensions, and confusing them was a real bug. `length` is
    // how far the barrier *runs*; `span` is the axis its `at` is a fraction of,
    // which is the perpendicular one. The clash test below used `length` and so
    // measured the distance between two walls in the wrong direction: on a
    // 100x10 field two duplicates 0.5m apart scored as 5m and both survived.
    let length = barrier.across == .eastWest ? width : depth
    let span = barrier.across == .eastWest ? depth : width

    // The same wall said twice is one wall. The model does this: asked for
    // pillars in a hall it returned the identical northSouth barrier at 0.5
    // twice over. Two coincident walls are not twice as solid, they are one
    // wall and a wasted shell in the visibility graph -- and their gaps do not
    // line up, so together they seal.
    let clash = barriers.contains {
      $0.across == barrier.across && abs($0.at - at) * span < 2 * body
    }
    if clash { duplicates += 1; continue }

    var gaps = barrier.gaps.map { gap -> FlowGap in
      let metres = clamp(gap.metres, floor, jsMax(floor, length - 2 * body))
      // Held far enough along the wall for the *whole* opening to be on it.
      // Clamping `at` to 0...1 alone is not enough: an opening at 1.0 keeps its
      // recorded width while half of it hangs off the end, `flowPlacement`
      // clips that half against the field, and what the crowd actually meets is
      // half the width the floor guaranteed -- which is the silent jam
      // `minGap` exists to prevent, reintroduced at the edges.
      let inset = jsMin(0.5, metres / 2 / jsMax(length, 1))
      return FlowGap(at: clamp(gap.at, inset, 1 - inset), metres: metres)
    }
    gaps = mergeGaps(gaps, along: length, apart: 2 * body, floor: floor)
    if gaps.isEmpty {
      // A solid wall across an enclosed field makes the goal unreachable. Rather
      // than search for that afterwards, every barrier is given a way through
      // and reachability holds by construction.
      gaps = [FlowGap(at: 0.5, metres: jsMax(floor, 2))]
      notes.append("a solid wall was given a way through")
    }
    barriers.append(FlowBarrier(across: barrier.across, at: at, gaps: gaps))
  }
  if duplicates > 0 { notes.append(note(duplicates, "wall", "stated twice")) }

  // Blocks: on the field, off the barriers, and never close enough to a
  // barrier to narrow the opening it is standing beside.
  var blocks: [FlowBlock] = []
  var swallowed = 0
  for block in raw.blocks.prefix(FlowLimits.maxBlocks) {
    var b = block
    b.width = clamp(jsRound(block.width), 1, width / 2)
    b.depth = clamp(jsRound(block.depth), 1, depth / 2)
    // The centre, so half the block sits either side of it: clamped to the
    // field's edge, a block hangs half of itself through the border wall.
    b.x = clamp(block.x, b.width / 2 / width, 1 - b.width / 2 / width)
    b.y = clamp(block.y, b.depth / 2 / depth, 1 - b.depth / 2 / depth)
    let centre = Point(b.x * width, b.y * depth)

    // Keep clear of every barrier by the width of the widest opening in it. A
    // block in the open field is the interesting case -- a pillar the crowd
    // parts around -- but a block against a barrier is a gap that silently got
    // narrower, which is the failure this whole file exists to prevent.
    let fouls = barriers.contains { barrier in
      let line = barrier.across == .eastWest ? barrier.at * depth : barrier.at * width
      let here = barrier.across == .eastWest ? centre.y : centre.x
      let reach = barrier.across == .eastWest ? b.depth / 2 : b.width / 2
      let clear = (barrier.gaps.map(\.metres).max() ?? floor) + FlowLimits.barrierThickness
      return abs(here - line) < reach + clear
    }
    if fouls { swallowed += 1; continue }
    blocks.append(b)
  }
  if swallowed > 0 { notes.append(note(swallowed, "block", "standing in a doorway")) }

  let plan = FlowPlan(title: raw.title, fieldWidth: width, fieldDepth: depth,
                      barriers: barriers, blocks: blocks)
  return RepairedFlow(plan: plan, notes: notes, problem: nil)
}

/// Openings merged where they overlap or leave a sliver of wall between them.
///
/// Two gaps a hand's width apart are one gap with a splinter in the middle --
/// and the splinter is a free-standing scrap of wall narrower than a person,
/// which is neither a useful obstacle nor a thing anybody asked for.
private func mergeGaps(_ gaps: [FlowGap], along length: Double,
                       apart: Double, floor: Double) -> [FlowGap] {
  let spans = gaps
    .map { (from: $0.at * length - $0.metres / 2,
            to: $0.at * length + $0.metres / 2, original: $0) }
    .sorted { $0.from < $1.from }
  guard var run = spans.first else { return [] }
  var absorbed = false

  var out: [FlowGap] = []
  func emit(_ span: (from: Double, to: Double, original: FlowGap), merged: Bool) {
    // A run that absorbed nothing is the gap it started as. Recomputing it from
    // `at * length` and back costs a few ulps, and a gap arriving one ulp under
    // the floor has been silently narrowed past the thing the floor exists to
    // guarantee.
    guard merged else { out.append(span.original); return }
    let from = jsMax(0, span.from), to = jsMin(length, span.to)
    guard to - from > 0 else { return }
    out.append(FlowGap(at: ((from + to) / 2) / length, metres: jsMax(floor, to - from)))
  }

  for span in spans.dropFirst() {
    if span.from <= run.to + apart {
      run.to = jsMax(run.to, span.to)
      absorbed = true
    } else {
      emit(run, merged: absorbed)
      run = span
      absorbed = false
    }
  }
  emit(run, merged: absorbed)
  return out
}

// MARK: - Building it

/// The repaired study as walls, a goal, doors and a crowd.
///
/// Hands back the value `WalkyWorld.place` already takes, so the ordering that
/// file documents -- walls, then generators, then the crowd, then `setGoalAt`
/// to aim all of it -- comes for free and is not restated here.
///
/// `thickness` is the border's, from `Settings.borderThickness`, in world units.
public func flowPlacement(_ plan: FlowPlan, radius: Double = 13,
                          thickness: Double = 12) -> RoomPlacement {
  let w = plan.fieldWidth * PX_PER_METRE
  let d = plan.fieldDepth * PX_PER_METRE
  let t = jsMax(1, thickness)
  let bar = FlowLimits.barrierThickness * PX_PER_METRE

  // The field is exactly [0, w] x [0, d]. `borderFrame` straddles the lines it
  // is given -- each bar is `2t` thick, centred -- so passing the field inset
  // by `t` puts the bars' inner faces exactly on the field's edge.
  var walls: [[[Point]]] = [borderFrame(Point(-t, -t), Point(w + t, d + t), t)]

  // Each barrier is one wall of several bars, as a scanned wall with doors cut
  // out of it is: one object, one undo unit, and one shell for the broad phase
  // to reject the whole line by.
  for barrier in plan.barriers {
    let along = barrier.across == .eastWest ? w : d
    let line = barrier.across == .eastWest ? barrier.at * d : barrier.at * w
    let cuts = barrier.gaps
      .map { (from: $0.at * along - $0.metres * PX_PER_METRE / 2,
              to: $0.at * along + $0.metres * PX_PER_METRE / 2) }
      .sorted { $0.from < $1.from }

    var bars: [[Point]] = []
    // Started and ended outside the field so every bar buries itself in the
    // border. Meeting it exactly would leave the seal to a floating-point
    // comparison, and a barrier that does not reach the wall is a barrier the
    // crowd walks round.
    var cursor = -t
    for cut in cuts {
      let stop = jsMin(along + t, cut.from)
      if stop - cursor > 1 { bars.append(run(barrier.across, from: cursor, to: stop,
                                             line: line, thickness: bar)) }
      cursor = jsMax(cursor, cut.to)
    }
    if along + t - cursor > 1 {
      bars.append(run(barrier.across, from: cursor, to: along + t,
                      line: line, thickness: bar))
    }
    if !bars.isEmpty { walls.append(bars) }
  }

  // Blocks stand alone: scattered, so one wall each gets each its own shell.
  for block in plan.blocks {
    let centre = Point(block.x * w, block.y * d)
    let half = Point(block.width * PX_PER_METRE / 2, block.depth * PX_PER_METRE / 2)
    walls.append([rectanglePolygon(rounded(Point(centre.x - half.x, centre.y - half.y)),
                                   rounded(Point(centre.x + half.x, centre.y + half.y)))])
  }

  let goal = edgeBar(plan.goal, w: w, d: d,
                     depth: FlowLimits.goalDepth * PX_PER_METRE, along: 0...1)

  let crowd = crowdBlock(plan, radius: radius, w: w, d: d)
  return RoomPlacement(walls: walls, exits: [goal], entrances: [],
                       crowdAt: crowd.at, crowdCells: crowd.cells)
}

/// One bar of a barrier, from `from` to `to` along its own axis.
private func run(_ across: FlowAxis, from: Double, to: Double,
                 line: Double, thickness: Double) -> [Point] {
  let half = thickness / 2
  switch across {
  case .eastWest:
    return rectanglePolygon(rounded(Point(from, line - half)),
                            rounded(Point(to, line + half)))
  case .northSouth:
    return rectanglePolygon(rounded(Point(line - half, from)),
                            rounded(Point(line + half, to)))
  }
}

/// A bar lying against one edge of the field, covering `along` of that edge.
private func edgeBar(_ side: FlowSide, w: Double, d: Double,
                     depth: Double, along: ClosedRange<Double>) -> Doorway {
  let span = side.isVertical ? w : d
  let from = along.lowerBound * span, to = along.upperBound * span
  let rect: [Point]
  switch side {
  case .north: rect = rectanglePolygon(rounded(Point(from, 0)), rounded(Point(to, depth)))
  case .south: rect = rectanglePolygon(rounded(Point(from, d - depth)), rounded(Point(to, d)))
  case .west:  rect = rectanglePolygon(rounded(Point(0, from)), rounded(Point(depth, to)))
  case .east:  rect = rectanglePolygon(rounded(Point(w - depth, from)), rounded(Point(w, to)))
  }
  let centre = Point((rect[0].x + rect[2].x) / 2, (rect[0].y + rect[2].y) / 2)
  // `metres` and `inward` are the scanner's business; `place` reads `slab` and
  // `at`, and `at` has to be *inside* the slab because `setGoalAt` point-tests
  // it against the wall's own polygon.
  return Doorway(kind: .door, at: rounded(centre),
                 metres: (to - from) / PX_PER_METRE, inward: nil, slab: rect)
}

/// Where the crowd starts, and how wide a block will fit there.
///
/// In the strip between the starting edge and the first barrier in the way, so
/// the crowd has to use the opening rather than starting past it. Bounded by
/// what the strip holds: `pedestrianBlock` silently drops what does not fit, so
/// a block sized from the head count alone spills across the map.
private func crowdBlock(_ plan: FlowPlan, radius: Double,
                        w: Double, d: Double) -> (at: Point, cells: Int) {
  let start = plan.goal.opposite
  let pitch = 2 * radius
  let alongY = start.isVertical

  // How far in the first barrier across the path is, as a fraction.
  let blocking = plan.barriers
    .filter { alongY ? $0.across == .eastWest : $0.across == .northSouth }
    .map { start == .north || start == .west ? $0.at : 1 - $0.at }
    .min() ?? 1

  // **How many people is the app's decision, not the model's.** Asked, it
  // answered ten to almost everything and two hundred to a platform the size of
  // a room; and a crowd sized without reference to the doorway it has to use is
  // either a queue of three or a jam that never resolves. Two thirds of what the
  // starting strip holds fills the map without packing it solid.
  let strip = jsMin((alongY ? d : w) * blocking, alongY ? w : d)
  let cells = Int(jsMax(2, jsMin(18, (strip / pitch * 0.66).rounded(.down))))

  let into = jsMin(0.5, blocking / 2)
  let fraction = start == .north || start == .west ? into : 1 - into
  let at = alongY ? Point(w / 2, d * fraction) : Point(w * fraction, d / 2)
  return (rounded(at), cells)
}

// MARK: - Small shared things

private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
  lo <= hi ? jsMin(jsMax(v, lo), hi) : lo
}

/// Whole units out. `orient` is exact only on integers, which is why every
/// other geometry producer in the project rounds on the way out too.
private func rounded(_ p: Point) -> Point { Point(jsRound(p.x), jsRound(p.y)) }

private func note(_ n: Int, _ thing: String, _ why: String) -> String {
  "\(n) \(thing)\(n == 1 ? "" : "s") \(why)"
}

// MARK: - A study with no model behind it

public extension FlowPlan {
  /// The bottleneck, which is the thing this vocabulary exists to make easy:
  /// one wall across the field with one narrow way through it, a crowd on one
  /// side and the goal on the other. Drives the tests, and stands in for the
  /// model on a phone that cannot run one.
  static let sample = FlowPlan(
    title: "A narrow passage",
    fieldWidth: 30, fieldDepth: 24,
    barriers: [FlowBarrier(across: .eastWest, at: 0.55,
                           gaps: [FlowGap(at: 0.5, metres: 1.2)])],
    blocks: [])
}
