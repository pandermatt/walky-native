import Testing
import Foundation
@testable import WalkyCore

/// Stubbed context: the tools are driven with no world, no view and no simulator.
@MainActor
private final class Recorder {
  var walls: [[[Point]]] = []
  var options: [WallOptions?] = []
  var pedestriansAt: [Point] = []
  var goalsAt: [Point] = []
  var notices: [String] = []
  var deactivated = 0
  /// How many undo checkpoints a gesture asked for -- one per stroke, not one
  /// per dot; see `PedestrianTool`.
  var checkpoints = 0
  var selectionCleared = 0
  var goalHits = true
  /// Blocks offered to `markGenerator`, and whether one was there to mark.
  var doorsAt: [Point] = []
  var doorFits = true
  var perPixel: Double = 1
  /// Lassos handed to `selectPedestriansIn`, and what each caught.
  var lassos: [[Point]] = []
  var lassoCatches = 1
  var selected = 0
  var measured: [(Point, Point)] = []
  /// How far the map is turned, for the two tools that draw a box.
  var spin: Double = 0
  /// A box that a point may not be inside, as a wall is. Nil means open ground.
  var blocked: (minX: Double, minY: Double, maxX: Double, maxY: Double)?

  /// The id of the wall under a point, for the tools that ask which block they
  /// are pointing at. The same `blocked` box `standable` uses.
  let wallId = 7
  func wallIdAt(_ at: Point) -> Int? {
    guard let b = blocked, at.x >= b.minX, at.x <= b.maxX,
          at.y >= b.minY, at.y <= b.maxY else { return nil }
    return wallId
  }

  /// Out through the left edge, which is enough to tell "it was moved" from
  /// "it was taken as tapped".
  func standable(_ at: Point) -> Point {
    guard let b = blocked, at.x >= b.minX, at.x <= b.maxX,
          at.y >= b.minY, at.y <= b.maxY else { return at }
    return Point(b.minX - 2, at.y)
  }

  lazy var ctx: ToolContext = ToolContext(
    addWall: { [unowned self] polygon, o in
      self.walls.append([polygon]); self.options.append(o); return true },
    addWallShape: { [unowned self] polygons, o in
      self.walls.append(polygons); self.options.append(o); return true },
    settings: { SettingsSnapshot(pedestrianRadius: 13, personalSpace: 40,
                                 brushSize: 1, borderThickness: 12) },
    pedestrianBlock: { at, _ in [at] },
    addPedestrians: { [unowned self] at in
      self.pedestriansAt.append(at)
      return [at]
    },
    checkpoint: { [unowned self] in self.checkpoints += 1 },
    setGoalAt: { [unowned self] at in self.goalsAt.append(at); return self.goalHits },
    markGenerator: { [unowned self] at in self.doorsAt.append(at); return self.doorFits },
    selectPedestriansIn: { [unowned self] lasso in
      self.lassos.append(lasso); self.selected = self.lassoCatches; return self.lassoCatches },
    selectionCount: { [unowned self] in self.selected },
    clearSelection: { [unowned self] in self.selectionCleared += 1; self.selected = 0 },
    // A fake wall to nudge out of: anything inside `blocked` comes back at its
    // near edge, which is what `WalkyWorld.standable` does with a real one.
    standablePoint: { [unowned self] at in self.standable(at) },
    deactivateTool: { [unowned self] in self.deactivated += 1 },
    notify: { [unowned self] m in self.notices.append(m) },
    requestRender: {},
    colorAt: { _ in nil },
    wallIdAt: { [unowned self] at in self.wallIdAt(at) },
    worldPerPixel: { [unowned self] in self.perPixel },
    viewRotation: { [unowned self] in self.spin },
    measure: { [unowned self] a, b in self.measured.append((a, b)) })
}

private func down(_ p: Point) -> PointerInfo { .down(world: p, screen: p) }
private func up(_ p: Point) -> PointerInfo { .up(world: p, screen: p) }
private func move(_ p: Point) -> PointerInfo { .down(world: p, screen: p) }

@Suite("RectangleTool")
@MainActor
struct RectangleToolTests {
  @Test("a drag past the threshold commits from press to release")
  func dragCommits() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerUp(up(Point(100, 80)), r.ctx)
    #expect(r.walls.count == 1)
    #expect(r.walls[0][0] == rectanglePolygon(Point(0, 0), Point(100, 80)))
  }

  @Test("a press and release in place sets one corner and commits nothing")
  func tapSetsCorner() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(down(Point(10, 10)), r.ctx)
    t.onPointerUp(up(Point(11, 11)), r.ctx)
    #expect(r.walls.isEmpty)
    // A second tap elsewhere completes it.
    t.onPointerDown(down(Point(90, 70)), r.ctx)
    t.onPointerUp(up(Point(90, 70)), r.ctx)
    #expect(r.walls.count == 1)
  }

  @Test("the drag threshold is measured in points, not world units")
  func thresholdIsInPoints() {
    // The deliberate divergence: rectangleTool.ts:42 compares DRAG_THRESHOLD
    // against a world-space distance, so zoomed out every tap became a drag and
    // two-tap mode was unreachable. Here it scales with worldPerPixel.
    let r = Recorder()
    r.perPixel = 10          // zoomed out: one point is ten world units
    let t = RectangleTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    // 20 world units is 2 points of finger travel -- a tap, not a drag.
    t.onPointerUp(up(Point(20, 0)), r.ctx)
    #expect(r.walls.isEmpty, "20 world units at 10 units/pt is a 2pt tap")

    // The web app would have committed a wall here, because 20 >= 6.
    let sameAtZoomOne = Recorder()
    let t2 = RectangleTool()
    t2.onPointerDown(down(Point(0, 0)), sameAtZoomOne.ctx)
    t2.onPointerUp(up(Point(20, 20)), sameAtZoomOne.ctx)
    #expect(sameAtZoomOne.walls.count == 1)
  }

  @Test("a press with no primary button does nothing")
  func ignoresNonPrimary() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(up(Point(0, 0)), r.ctx)      // buttons == 0
    t.onPointerUp(up(Point(100, 80)), r.ctx)
    #expect(r.walls.isEmpty)
  }

  @Test("a degenerate rectangle is refused")
  func refusesDegenerate() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerUp(up(Point(50, 0)), r.ctx)       // no height
    #expect(r.walls.isEmpty)
  }
}

@Suite("BorderTool")
@MainActor
struct BorderToolTests {
  @Test("commits four bars as one wall, flagged as a border")
  func fourBarsOneWall() {
    let r = Recorder(); let t = BorderTool()
    t.onPointerDown(down(Point(-400, -400)), r.ctx)
    t.onPointerUp(up(Point(400, 400)), r.ctx)
    #expect(r.walls.count == 1)
    #expect(r.walls[0].count == 4)
    #expect(r.options[0]?.isBorder == true)
  }

  @Test("refuses a frame with no usable interior, and says so in the preview")
  func refusesTooSmall() {
    let r = Recorder(); let t = BorderTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerMove(move(Point(30, 30)), r.ctx)
    // thickness 12 + radius 13 on every side leaves nothing to stand in.
    #expect(t.preview().pendingPolygonsInvalid)
    t.onPointerUp(up(Point(30, 30)), r.ctx)
    #expect(r.walls.isEmpty)
  }
}

@Suite("PedestrianTool")
@MainActor
struct PedestrianToolTests {
  @Test("a tap paints, and a drag keeps painting")
  func paints() {
    let r = Recorder(); let t = PedestrianTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerMove(move(Point(30, 0)), r.ctx)
    t.onPointerMove(move(Point(60, 0)), r.ctx)
    t.onPointerUp(up(Point(60, 0)), r.ctx)
    #expect(r.pedestriansAt == [Point(0, 0), Point(30, 0), Point(60, 0)])
  }

  @Test("moving without a press paints nothing but still previews")
  func hoverDoesNotPaint() {
    let r = Recorder(); let t = PedestrianTool()
    t.onPointerMove(move(Point(10, 10)), r.ctx)
    #expect(r.pedestriansAt.isEmpty)
    #expect(t.preview().pendingPedestrians == [Point(10, 10)])
  }
}

@Suite("GoalTool")
@MainActor
struct GoalToolTests {
  @Test("a hit clears the selection and steps off the tool")
  func hitCompletes() {
    let r = Recorder(); let t = GoalTool()
    // At the lift, not the touch: that is what leaves room to tell a tap from
    // the lasso drag, and it is where RectangleTool and BorderTool decide too.
    t.onPointerDown(down(Point(50, 50)), r.ctx)
    #expect(r.goalsAt.isEmpty)
    t.onPointerUp(up(Point(50, 50)), r.ctx)
    #expect(r.goalsAt == [Point(50, 50)])
    #expect(r.selectionCleared == 1)
    #expect(r.deactivated == 1)
  }

  @Test("a miss says so and leaves the tool and selection alone")
  func missIsAMiss() {
    // Clearing up after a miss would mean lassoing the same group again to
    // have another go.
    let r = Recorder(); r.goalHits = false
    let t = GoalTool()
    t.onPointerDown(down(Point(5, 5)), r.ctx)
    t.onPointerUp(up(Point(5, 5)), r.ctx)
    #expect(r.notices.count == 1)
    #expect(r.selectionCleared == 0)
    #expect(r.deactivated == 0)
  }

  @Test("a drag lassos instead of assigning, and keeps the tool")
  func dragLassos() {
    let r = Recorder(); let t = GoalTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    // A curved stroke enclosing real area, so `outline` uses it rather than
    // falling back to the bounding rectangle.
    for p in [Point(0, 40), Point(40, 60), Point(70, 30), Point(40, -10)] {
      t.onPointerMove(move(p), r.ctx)
    }
    t.onPointerUp(up(Point(0, 0)), r.ctx)
    #expect(r.lassos.count == 1)
    #expect(r.lassos[0].count >= 3)
    // Not a goal, and the tool stays in hand for the tap that follows.
    #expect(r.goalsAt.isEmpty)
    #expect(r.deactivated == 0)
    #expect(r.notices.isEmpty)
  }

  @Test("a lasso that catches nobody says so and stays armed")
  func emptyLasso() {
    let r = Recorder(); r.lassoCatches = 0
    let t = GoalTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerMove(move(Point(60, 60)), r.ctx)
    t.onPointerUp(up(Point(60, 60)), r.ctx)
    #expect(r.notices.count == 1)
    #expect(r.deactivated == 0)
  }

  @Test("a fast straight drag still selects, by falling back to a rectangle")
  func straightDragSelects() {
    // Three collinear points enclose no area at all. Without the fallback a
    // quick drag would select nobody, which just reads as the tool being broken.
    let r = Recorder(); let t = GoalTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerMove(move(Point(50, 50)), r.ctx)
    t.onPointerMove(move(Point(100, 100)), r.ctx)
    t.onPointerUp(up(Point(100, 100)), r.ctx)
    #expect(r.lassos.count == 1)
    #expect(r.lassos[0] == [Point(0, 0), Point(100, 0), Point(100, 100), Point(0, 100)])
  }

  @Test("the threshold is in screen points, so a zoomed-out drag is a tap")
  func thresholdScales() {
    // 6 world units is a drag at zoom 0 and well under a finger's width when
    // zoomed out -- the divergence DRAG_THRESHOLD's comment exists for.
    let r = Recorder(); r.perPixel = 8
    let t = GoalTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerMove(move(Point(6, 0)), r.ctx)
    t.onPointerUp(up(Point(6, 0)), r.ctx)
    #expect(r.lassos.isEmpty)
    #expect(r.goalsAt == [Point(6, 0)])
  }
}

@Suite("No hover on iOS")
@MainActor
struct HoverTests {
  /// The web keeps a cursor ghost after a gesture because a mouse really is
  /// still hovering there. A finger is not, so a ghost left at the last touch
  /// point sits on the map for the rest of the session -- which is exactly
  /// what happened, and is visible in the first freehand wall drawn on device.

  @Test("the wall tool's ghost does not outlive the touch")
  func wallGhost() {
    let r = Recorder(); let t = WallTool()
    t.onPointerDown(down(Point(10, 10)), r.ctx)
    // Under the 5pt drag threshold, so this is still a tap and the ghost shows.
    // Move further and the tool starts tracing, which hides the ghost anyway.
    t.onPointerMove(move(Point(13, 13)), r.ctx)
    #expect(t.preview().cursorGhost != nil)
    t.onPointerUp(up(Point(13, 13)), r.ctx)
    #expect(t.preview().cursorGhost == nil)
  }

  @Test("a traced stroke leaves no ghost behind either")
  func wallGhostAfterTrace() {
    let r = Recorder(); let t = WallTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    for i in stride(from: 0.0, through: 90.0, by: 5) { t.onPointerMove(move(Point(i, i)), r.ctx) }
    t.onPointerUp(up(Point(90, 90)), r.ctx)
    #expect(t.preview().cursorGhost == nil)
  }

  @Test("the brush's ghost dots show what is free, and clear on lift")
  func pedestrianGhost() {
    let r = Recorder(); let t = PedestrianTool()
    // Not painting -- `up` is a move with no button, which is what a hover is.
    // The ghost is the block that *would* be filled.
    t.onPointerMove(up(Point(0, 0)), r.ctx)
    #expect(!t.preview().pendingPedestrians.isEmpty)

    // Painting fills it, so nothing there is still free. This used to be
    // discovered by asking `pedestrianBlock` a second time in the same event,
    // spatial-hash rebuild and all.
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    #expect(t.preview().pendingPedestrians.isEmpty)
    t.onPointerUp(up(Point(0, 0)), r.ctx)
    #expect(t.preview().pendingPedestrians.isEmpty)
  }

  /// The brush was the only drag tool committing a world edit on every raw
  /// pointer event -- sixty or a hundred and twenty a second, each one a
  /// checkpoint copying every wall and every agent already placed.
  @Test("a stroke is one checkpoint, and one dot per body's width")
  func strokeIsOneEdit() {
    let r = Recorder(); let t = PedestrianTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    #expect(r.pedestriansAt.count == 1)

    // The fake's radius is 13, so the pitch is 26: every one of these lands
    // inside the block just painted and can put nobody anywhere new.
    for x in stride(from: 4.0, through: 24.0, by: 4) {
      t.onPointerMove(move(Point(x, 0)), r.ctx)
    }
    #expect(r.pedestriansAt.count == 1, "it painted where there was no room")

    // Past the pitch, and it paints again.
    t.onPointerMove(move(Point(30, 0)), r.ctx)
    #expect(r.pedestriansAt.count == 2)

    t.onPointerUp(up(Point(30, 0)), r.ctx)
    #expect(r.checkpoints == 1, "a stroke is one edit, so one undo takes it back")
  }

  @Test("the goal tool's target lines clear on lift")
  func goalLines() {
    let r = Recorder(); r.goalHits = false
    let t = GoalTool()
    t.onPointerMove(move(Point(30, 30)), r.ctx)
    #expect(t.preview().targetLines != nil)
    t.onPointerUp(up(Point(30, 30)), r.ctx)
    #expect(t.preview().targetLines == nil)
  }

  @Test("the rectangle tool's ghost clears, and the first corner survives")
  func rectangleGhost() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(down(Point(10, 10)), r.ctx)
    t.onPointerUp(up(Point(10, 10)), r.ctx)          // a tap: sets the first corner
    #expect(t.preview().cursorGhost == nil)
    #expect(t.preview().pendingRect == nil)
    // The corner is still held, so a second tap completes the rectangle.
    t.onPointerDown(down(Point(90, 70)), r.ctx)
    t.onPointerUp(up(Point(90, 70)), r.ctx)
    #expect(r.walls.count == 1)
  }
}

@Suite("WallTool")
@MainActor
struct WallToolTests {
  @Test("a traced stroke is simplified before it becomes a wall")
  func traceSimplifies() {
    let r = Recorder(); let t = WallTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    // A dense trace round a triangle: one sample every few units, as a finger
    // would give.
    for i in stride(from: 0.0, through: 120.0, by: 4) { t.onPointerMove(move(Point(i, 0)), r.ctx) }
    for i in stride(from: 0.0, through: 120.0, by: 4) { t.onPointerMove(move(Point(120, i)), r.ctx) }
    for i in stride(from: 0.0, through: 120.0, by: 4) { t.onPointerMove(move(Point(120 - i, 120 - i)), r.ctx) }
    t.onPointerUp(up(Point(0, 0)), r.ctx)

    #expect(r.walls.count == 1)
    // Vertex count is what the whole navigation pipeline costs scale on, so a
    // ~90-sample trace must not become a 90-vertex polygon.
    #expect(r.walls[0][0].count < 12)
    #expect(r.walls[0][0].count >= 3)
  }

  @Test("tapped vertices close on a double tap")
  func tapMode() {
    let r = Recorder(); let t = WallTool()
    for p in [Point(0, 0), Point(100, 0), Point(100, 100)] {
      t.onPointerDown(down(p), r.ctx)
      t.onPointerUp(up(p), r.ctx)
    }
    #expect(r.walls.isEmpty)          // still open
    t.onDoubleTap(down(Point(0, 100)), r.ctx)
    #expect(r.walls.count == 1)
    #expect(r.walls[0][0].count == 4)
  }

  @Test("vertices closer than the minimum are ignored")
  func minimumSpacing() {
    let r = Recorder(); let t = WallTool()
    for p in [Point(0, 0), Point(3, 0), Point(5, 0)] {
      t.onPointerDown(down(p), r.ctx)
      t.onPointerUp(up(p), r.ctx)
    }
    // All within MINIMUM_DISTANCE of each other: one vertex, so no polygon.
    t.onDoubleTap(down(Point(6, 0)), r.ctx)
    #expect(r.walls.isEmpty)
  }

  @Test("cancel abandons a half-drawn shape")
  func cancelAbandons() {
    let r = Recorder(); let t = WallTool()
    for p in [Point(0, 0), Point(100, 0), Point(100, 100)] {
      t.onPointerDown(down(p), r.ctx)
      t.onPointerUp(up(p), r.ctx)
    }
    t.cancel()
    #expect(t.preview().pendingWallPoints.isEmpty)
    t.onDoubleTap(down(Point(0, 100)), r.ctx)
    #expect(r.walls.isEmpty)
  }
}

@Suite("MeasureTool")
@MainActor
struct MeasureToolTests {
  @Test("two taps measure between them")
  func twoTaps() {
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)
    #expect(host.measured.isEmpty)          // one point is not a measurement

    tool.onPointerDown(down(Point(200, 10)), host.ctx)
    tool.onPointerUp(up(Point(200, 10)), host.ctx)
    #expect(host.measured.count == 1)
    #expect(host.measured[0].0 == Point(10, 10))
    #expect(host.measured[0].1 == Point(200, 10))
    // Two taps is the whole gesture, so the tool puts itself away. Safe only
    // because the answer lives on the world and stays drawn without it.
    #expect(host.deactivated == 1)
  }

  @Test("a measurement of nothing leaves the tool in hand")
  func degenerateStaysArmed() {
    // A fat-fingered double tap on one spot should cost a second try, not a
    // trip back into the menu to re-arm.
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(50, 50)), host.ctx)
    tool.onPointerUp(up(Point(50, 50)), host.ctx)
    tool.onPointerDown(down(Point(50, 50)), host.ctx)
    tool.onPointerUp(up(Point(50, 50)), host.ctx)

    #expect(host.measured.isEmpty)
    #expect(host.deactivated == 0)
  }

  @Test("a drag measures its own two ends")
  func drag() {
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(0, 0)), host.ctx)
    tool.onPointerMove(move(Point(300, 40)), host.ctx)
    tool.onPointerUp(up(Point(300, 40)), host.ctx)

    #expect(host.measured.count == 1)
    #expect(host.measured[0].0 == Point(0, 0))
    #expect(host.measured[0].1 == Point(300, 40))
  }

  @Test("tapping the same spot twice measures nothing")
  func degenerate() {
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(50, 50)), host.ctx)
    tool.onPointerUp(up(Point(50, 50)), host.ctx)
    tool.onPointerDown(down(Point(50, 50)), host.ctx)
    tool.onPointerUp(up(Point(50, 50)), host.ctx)

    #expect(host.measured.isEmpty)
  }

  @Test("the first point is dropped when the tool is put away")
  func cancelForgets() {
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)
    tool.cancel()

    tool.onPointerDown(down(Point(200, 10)), host.ctx)
    tool.onPointerUp(up(Point(200, 10)), host.ctx)
    #expect(host.measured.isEmpty)          // that second tap is a new first tap
  }

  @Test("the first tap leaves a mark on the map")
  func firstTapIsVisible() {
    // It used to leave none: a one-point path strokes to nothing, so between
    // the two taps there was no sign the first had landed.
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)

    #expect(tool.preview().anchorPoint == Point(10, 10))
  }

  @Test("a tap on a wall is measured from just outside it")
  func nudgedOutOfWalls() {
    let host = Recorder()
    host.blocked = (minX: 100, minY: 0, maxX: 300, maxY: 200)
    let tool = MeasureTool()

    // Both ends land in the wall, and neither is refused.
    tool.onPointerDown(down(Point(150, 100)), host.ctx)
    tool.onPointerUp(up(Point(150, 100)), host.ctx)
    #expect(tool.preview().anchorPoint == Point(98, 100))

    tool.onPointerDown(down(Point(250, 50)), host.ctx)
    tool.onPointerUp(up(Point(250, 50)), host.ctx)

    #expect(host.measured.count == 1)
    #expect(host.measured[0].0 == Point(98, 100))
    #expect(host.measured[0].1 == Point(98, 50))
  }

  @Test("a tap on open ground is measured where it landed")
  func openGroundUntouched() {
    let host = Recorder()
    host.blocked = (minX: 100, minY: 0, maxX: 300, maxY: 200)
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)
    tool.onPointerDown(down(Point(600, 10)), host.ctx)
    tool.onPointerUp(up(Point(600, 10)), host.ctx)

    #expect(host.measured.count == 1)
    #expect(host.measured[0].0 == Point(10, 10))
    #expect(host.measured[0].1 == Point(600, 10))
  }

  @Test("no ghost is left parked after the finger lifts")
  func noHover() {
    let host = Recorder()
    let tool = MeasureTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerMove(move(Point(12, 12)), host.ctx)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)

    let p = tool.preview()
    #expect(p.cursorGhost == nil)
    // The placed point stays marked; the rubber band to the finger does not,
    // because there is no finger and no hover to follow.
    #expect(p.anchorPoint == Point(10, 10))
    #expect(p.pendingWallPoints.isEmpty)
  }
}

@Suite("GeneratorTool")
@MainActor
struct GeneratorToolTests {
  @Test("a tap marks the block under it and puts the tool away")
  func marksAndDisarms() {
    let host = Recorder()
    let tool = GeneratorTool()

    tool.onPointerDown(down(Point(40, 60)), host.ctx)
    tool.onPointerUp(up(Point(40, 60)), host.ctx)

    #expect(host.doorsAt == [Point(40, 60)])
    // The same bargain the goal tool strikes: the gesture is finished, so the
    // next tap on the map cannot mark something by accident.
    #expect(host.deactivated == 1)
    #expect(host.notices.isEmpty)
  }

  @Test("a tap on bare ground says so and leaves the tool in hand")
  func missStaysArmed() {
    // Nothing there to mark. A miss is a fat finger, not a change of mind, so
    // it costs another tap rather than a trip back to the menu.
    let host = Recorder()
    host.doorFits = false
    let tool = GeneratorTool()

    tool.onPointerDown(down(Point(40, 60)), host.ctx)
    tool.onPointerUp(up(Point(40, 60)), host.ctx)

    #expect(host.doorsAt == [Point(40, 60)])   // it was offered, and there was nothing
    #expect(host.deactivated == 0)
    #expect(host.notices.count == 1)
  }

  @Test("nothing is marked until the finger lifts")
  func commitsOnTheLift() {
    // It used to mark on touch-down, which is the one tool behaviour nobody can
    // take back mid-gesture.
    let host = Recorder()
    let tool = GeneratorTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    tool.onPointerMove(move(Point(12, 12)), host.ctx)
    #expect(host.doorsAt.isEmpty)

    tool.onPointerUp(up(Point(12, 12)), host.ctx)
    #expect(host.doorsAt == [Point(12, 12)])
  }

  /// It used to draw the goal tool's ring at the cursor. A ring at the cursor
  /// says where the cursor is, which the cursor was already saying -- and three
  /// of the seven tools were drawing the same one.
  @Test("the block under the pointer is previewed as the door it would become")
  func marksTheBlock() {
    let host = Recorder()
    host.blocked = (minX: 0, minY: 0, maxX: 20, maxY: 20)
    let tool = GeneratorTool()

    tool.onPointerMove(move(Point(10, 10)), host.ctx)
    #expect(tool.preview().markingWallId == host.wallId)
    #expect(tool.preview().cursorGhost == nil, "the ring is what this replaced")

    // Bare ground names nothing: there is no block there to become anything.
    tool.onPointerMove(move(Point(100, 100)), host.ctx)
    #expect(tool.preview().markingWallId == nil)
  }

  @Test("no block is left outlined after the finger lifts")
  func noHover() {
    let host = Recorder()
    host.blocked = (minX: 0, minY: 0, maxX: 20, maxY: 20)
    let tool = GeneratorTool()

    tool.onPointerDown(down(Point(10, 10)), host.ctx)
    #expect(tool.preview().markingWallId != nil)
    tool.onPointerUp(up(Point(10, 10)), host.ctx)
    #expect(tool.preview().markingWallId == nil)
  }
}

/// The box tools on a map somebody has twisted.
///
/// Driven through a real `Viewport` rather than by handing the tools an angle
/// and asserting on the angle back: what the complaint was about is what the
/// *screen* shows, so every assertion here is made after `worldToScreen`, and a
/// sign error in either direction fails it.
@Suite("A box drawn on a turned map")
@MainActor
struct TurnedBoxTests {
  private func turned(_ degrees: Double) -> Viewport {
    var v = Viewport()
    v.width = 400
    v.height = 300
    v.rotateBy(Point(200, 150), degrees * Double.pi / 180)
    return v
  }

  /// Whether every side of a ring runs along one of the screen's own axes.
  /// The tolerance is a point and a half: `snap` rounds both drag corners to
  /// whole world units before the box is built from them.
  private func squareToScreen(_ ring: [Point], _ v: Viewport) -> Bool {
    let onScreen = ring.map { v.worldToScreen($0) }
    for i in onScreen.indices {
      let a = onScreen[i], b = onScreen[(i + 1) % onScreen.count]
      if abs(a.x - b.x) > 1.5 && abs(a.y - b.y) > 1.5 { return false }
    }
    return true
  }

  @Test("the rectangle follows the screen's axes, which turns the wall itself")
  func rectangleIsSquareToTheScreen() {
    let v = turned(31)
    let r = Recorder(); r.spin = v.rotation
    let t = RectangleTool()
    t.onPointerDown(down(v.screenToWorld(Point(120, 90))), r.ctx)
    t.onPointerUp(up(v.screenToWorld(Point(300, 210))), r.ctx)

    #expect(r.walls.count == 1)
    #expect(squareToScreen(r.walls[0][0], v))
    // And it really is turned: a wall square to a 31° screen cannot also be
    // square to the world, so this is what says the fix is not a no-op.
    #expect(!squareToScreen(r.walls[0][0], Viewport()))
  }

  @Test("the preview is the shape that will be committed, not its bounding box")
  func previewMatchesTheCommit() {
    let v = turned(-47)
    let r = Recorder(); r.spin = v.rotation
    let t = RectangleTool()
    let a = v.screenToWorld(Point(100, 100)), b = v.screenToWorld(Point(260, 190))
    t.onPointerDown(down(a), r.ctx)
    t.onPointerMove(move(b), r.ctx)
    let shown = t.preview().pendingRect
    t.onPointerUp(up(b), r.ctx)

    guard let shown, r.walls.count == 1 else { Issue.record("nothing drawn"); return }
    #expect(squareToScreen(shown, v))
    // Corner for corner the same shape, to within the rounding `snap` does to
    // the committed drag and the preview does not -- which is the only
    // difference between the two, and was so before rotation existed.
    #expect(shown.count == r.walls[0][0].count)
    for (p, q) in zip(shown, r.walls[0][0]) {
      #expect(distance(p, q) < 1.5)
    }
  }

  @Test("a straight map draws exactly the box it always did")
  func straightIsUntouched() {
    let r = Recorder(); let t = RectangleTool()
    t.onPointerDown(down(Point(0, 0)), r.ctx)
    t.onPointerUp(up(Point(100, 80)), r.ctx)
    #expect(r.walls[0][0] == rectanglePolygon(Point(0, 0), Point(100, 80)))
  }

  @Test("every bar of a border frame is square to the screen too")
  func borderIsSquareToTheScreen() {
    let v = turned(19)
    let r = Recorder(); r.spin = v.rotation
    let t = BorderTool()
    t.onPointerDown(down(v.screenToWorld(Point(60, 40))), r.ctx)
    t.onPointerUp(up(v.screenToWorld(Point(340, 260))), r.ctx)

    #expect(r.walls.count == 1)
    #expect(r.walls[0].count == 4)
    for bar in r.walls[0] { #expect(squareToScreen(bar, v)) }
  }

  @Test("a frame that fits on screen is not called unusable for being turned")
  func borderFitsMeasuresTheDrag() {
    // 45° is the worst case: the bounding box of this drag in world space is
    // half again as wide as the drag, so a fit test that measured the box
    // would pass frames with no room in them -- and, turned the other way,
    // refuse ones that have.
    let v = turned(45)
    let a = v.screenToWorld(Point(100, 100)), b = v.screenToWorld(Point(220, 200))
    #expect(borderFits(a, b, 12, 13, v.rotation))
    // The same drag shrunk below the margin is refused, turned or not.
    let small = v.screenToWorld(Point(150, 150))
    #expect(!borderFits(a, small, 12, 13, v.rotation))
  }
}

/// The one table the bar, the menu bar and the Settings page all read.
///
/// The port of `web/src/__tests__/toolbar.test.ts`, which asserts the same
/// derivation for the same reason: the web's own comment says a list of
/// shortcuts kept anywhere but the button table "goes wrong the first time a
/// tool moves", and this port had already proved it -- two spellings of "Mark
/// goal" and two opinions about what 5 does.
@Suite("The command table")
struct CommandTableTests {
  @Test("every tool has a digit, in the order the bar draws them")
  func digitsFollowTheBar() {
    // The five with a cell, then the two in the overflow menu.
    let expected = ["1": ToolId.wall, "2": .rectangle, "3": .border,
                    "4": .pedestrian, "5": .goal, "6": .generator, "7": .measure]
    for (digit, tool) in expected {
      #expect(Command.bare(digit)?.tool == tool, "\(digit) should arm \(tool)")
    }
    #expect(Command.tools == [.wall, .rectangle, .border, .pedestrian,
                             .goal, .generator, .measure])
    // A phone's bar is the first five of those, so the digits are the same on
    // both platforms -- a Mac simply shows two more cells.
    #expect(Command.barTools == [.wall, .rectangle, .border, .pedestrian, .goal])
    // And the bar's five are the first five digits, which is the whole rule:
    // the number is how far down the bar a tool is.
    for (index, tool) in Command.tools.enumerated() {
      #expect(Command.of(tool)?.shortcut == Shortcut(.character("\(index + 1)")))
    }
  }

  @Test("every tool is in the table exactly once")
  func everyToolIsListed() {
    for tool in ToolId.allCases {
      let found = Command.all.filter { $0.tool == tool }
      #expect(found.count == 1, "\(tool) should appear once")
      #expect(found.first?.shortcut != nil, "\(tool) has no key")
    }
  }

  @Test("no key is bound twice")
  func noKeyIsBoundTwice() {
    let keys = Command.all.compactMap(\.shortcut)
    #expect(Set(keys).count == keys.count)
  }

  @Test("every action in the enum has a row")
  func everyActionIsListed() {
    for action in ToolbarAction.allCases {
      #expect(Command.all.contains { $0.action == action }, "\(action) is not in the table")
    }
  }

  @Test("a shortcut writes itself the way a person does")
  func keysReadCorrectly() {
    #expect(Command.of(.undo)?.shortcut?.label == "\u{2318}Z")
    #expect(Command.of(.start)?.shortcut?.label == "Space")
    #expect(Command.of(.clear)?.shortcut?.label == "\u{21E7}\u{2318}\u{232B}")
    #expect(Command.of(.wall)?.shortcut?.label == "1")
  }

  /// The guard the key handlers rely on: only the bare keys are theirs, and
  /// everything with Command on it belongs to the menu bar.
  @Test("bare lookup never answers with a Command shortcut")
  func bareIsBare() {
    #expect(Command.bare("z") == nil, "Cmd-Z is the menu's")
    #expect(Command.bare("o") == nil)
    #expect(Command.bare("0") == nil, "Cmd-0 is the menu's")
    #expect(Command.bare("1")?.tool == .wall)
  }
}

/// What a pointer that is merely hovering is allowed to draw.
///
/// Hover exists on macOS and nowhere else -- `PointerRouter.hovered` is called
/// from one place, the Mac's `mouseMoved` -- so this is the rule for what
/// follows a cursor around a Mac window, and it cost the phone nothing to
/// write: on iOS a ghost is only ever drawn under a finger already down.
@Suite("Hovering")
@MainActor
struct HoverPreviewTests {
  @Test("two of the seven tools mark where the pointer is")
  func onlyTwoGhostOnHover() {
    for tool in ToolId.allCases {
      let expected = tool == .pedestrian || tool == .goal
      #expect(tool.ghostsOnHover == expected, "\(tool)")
    }
  }

  @Test("the pointer leaving takes the block of bodies with it")
  func pedestrianBlockGoes() {
    let host = Recorder()
    let tool = PedestrianTool()
    tool.onPointerMove(move(Point(40, 40)), host.ctx)
    #expect(!tool.preview().pendingPedestrians.isEmpty)

    tool.pointerLeft()
    // It used to stay parked wherever the pointer left the window: the ghost
    // was the only preview the renderer gated on there being a pointer at all.
    #expect(tool.preview().pendingPedestrians.isEmpty)
  }

  @Test("and the fan of lines to the goal")
  func targetLinesGo() {
    let host = Recorder()
    let tool = GoalTool()
    tool.onPointerMove(move(Point(40, 40)), host.ctx)
    #expect(tool.preview().targetLines != nil)
    #expect(tool.preview().cursorGhost != nil)

    tool.pointerLeft()
    #expect(tool.preview().targetLines == nil)
    #expect(tool.preview().cursorGhost == nil)
  }

  /// The one that would break two-tap mode if `pointerLeft` were `cancel`.
  @Test("a half-drawn rectangle survives the pointer leaving")
  func halfDrawnShapesSurvive() {
    let host = Recorder()
    let tool = RectangleTool()
    // One corner placed, by a tap rather than a drag.
    tool.onPointerDown(down(Point(0, 0)), host.ctx)
    tool.onPointerUp(up(Point(1, 1)), host.ctx)
    tool.onPointerMove(move(Point(80, 60)), host.ctx)
    #expect(tool.preview().pendingRect != nil, "the band should follow the pointer")

    tool.pointerLeft()
    #expect(tool.preview().pendingRect == nil, "the band should stop following")

    // Back in the window, and the corner is still where it was put: leaving is
    // not abandoning.
    tool.onPointerMove(move(Point(90, 70)), host.ctx)
    let band = try! #require(tool.preview().pendingRect)
    #expect(band.contains { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 },
            "the first corner should still be the origin")
  }
}
