import Testing
import Foundation
@testable import WalkyCore

/// The suite the whole `WalkyCore` split exists for.
///
/// `app.ts:457–720` is the most intricate code in the port and the least
/// forgiving: every rule in it is there because something felt wrong without
/// it. None of this could be tested if it lived in the app target, because
/// there is no simulator runtime to run the app target in.

/// A tool that records what it was told, in order.
@MainActor
private final class RecordingTool: Tool {
  let id = ToolId.wall
  enum Event: Equatable {
    case down(Point), move(Point), up(Point), doubleTap(Point), cancel, left
  }
  var events: [Event] = []

  func onPointerDown(_ e: PointerInfo, _ ctx: ToolContext) { events.append(.down(e.world)) }
  func onPointerMove(_ e: PointerInfo, _ ctx: ToolContext) { events.append(.move(e.world)) }
  func onPointerUp(_ e: PointerInfo, _ ctx: ToolContext) { events.append(.up(e.world)) }
  func onDoubleTap(_ e: PointerInfo, _ ctx: ToolContext) { events.append(.doubleTap(e.world)) }
  func cancel() { events.append(.cancel) }
  func pointerLeft() { events.append(.left) }
  func preview() -> ToolPreview { .empty }
}

@MainActor
private final class FakeHost: PointerHost {
  var viewport = Viewport()
  var tool: Tool?
  var mouseWorld: Point?
  var hoverWorld: Point?
  var renders = 0
  var freePans = 0
  var idleTaps = 0
  let recorder = RecordingTool()

  init() {
    viewport.width = 400
    viewport.height = 300
    tool = recorder
  }

  func requestRender() { renders += 1 }
  func pannedWithoutTool() { freePans += 1 }
  var tappedAt: Point?
  func tappedWithoutTool(at: Point) { idleTaps += 1; tappedAt = at }

  lazy var toolContext: ToolContext = ToolContext(
    addWall: { _, _ in true }, addWallShape: { _, _ in true },
    settings: { SettingsSnapshot(pedestrianRadius: 13, personalSpace: 40,
                                 brushSize: 1, borderThickness: 12) },
    pedestrianBlock: { _, _ in [] }, addPedestrians: { _ in [] },
    setGoalAt: { _ in true }, markGenerator: { _ in true },
    selectPedestriansIn: { _ in 0 }, selectionCount: { 0 },
    clearSelection: {}, standablePoint: { $0 }, deactivateTool: {},
    notify: { _ in }, requestRender: { [unowned self] in self.renders += 1 },
    colorAt: { _ in nil }, worldPerPixel: { [unowned self] in self.viewport.worldPerPixel },
    measure: { _, _ in })
}

private let A = TouchId(1)
private let B = TouchId(2)
private let C = TouchId(3)

@Suite("PointerRouter")
@MainActor
struct PointerRouterTests {

  @Test("a press reaches the tool on the first move, not on the touch")
  func pressIsWithheld() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.began(A, at: Point(100, 100))
    // The whole point: nothing yet. A second finger could still take this back.
    #expect(host.recorder.events.isEmpty)
    #expect(r.hasPendingPress)

    r.moved(A, to: Point(120, 100))
    r.ended(A, at: Point(120, 100))

    // The down carries where the finger *landed*, not where it had moved to.
    let landed = host.viewport.screenToWorld(Point(100, 100))
    let moved = host.viewport.screenToWorld(Point(120, 100))
    #expect(host.recorder.events == [.down(landed), .move(moved), .up(moved)])
  }

  @Test("a press with no move at all still reaches the tool on lift")
  func pressFlushesOnLift() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(50, 60))
    r.ended(A, at: Point(50, 60))
    let p = host.viewport.screenToWorld(Point(50, 60))
    #expect(host.recorder.events == [.down(p), .up(p)])
  }

  @Test("a second finger retracts the withheld press and cancels the tool")
  func secondFingerRetracts() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.began(A, at: Point(100, 100))
    r.began(B, at: Point(200, 100))

    // The tool never heard the press, and was told to abandon anything begun.
    #expect(host.recorder.events == [.cancel])
    #expect(!r.hasPendingPress)
    #expect(r.hasGestureTaken)
    #expect(r.isPinching)
  }

  @Test("two fingers moving together pan and zoom, and the tool hears nothing")
  func pinchPansAndZooms() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(150, 150))
    r.began(B, at: Point(250, 150))
    host.recorder.events.removeAll()

    // Spread apart and shift right: zoom in, and carry the map along.
    r.moved(A, to: Point(140, 150))
    r.moved(B, to: Point(280, 150))

    #expect(host.recorder.events.isEmpty)
    #expect(host.viewport.zoomLevel < 0)          // gap grew -> zoomed in
    #expect(host.viewport.targetX != 0 || host.viewport.targetY != 0)
  }

  @Test("the finger left after a pinch cannot start a stroke")
  func leftoverFingerIsInert() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(150, 150))
    r.began(B, at: Point(250, 150))
    r.ended(B, at: Point(250, 150))
    host.recorder.events.removeAll()

    r.moved(A, to: Point(160, 160))
    r.ended(A, at: Point(160, 160))

    #expect(host.recorder.events.isEmpty)
    // Only now, with the last finger gone, is the gesture over.
    #expect(!r.hasGestureTaken)
    #expect(r.activeTouches == 0)
  }

  @Test("a third finger is ignored, and the pinch stays on the first two")
  func thirdFingerIgnored() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(100, 150))
    r.began(B, at: Point(200, 150))
    let afterTwo = host.viewport.zoomLevel

    // This is the ordered-array regression test. A dictionary could pick any
    // two of the three, and the map would lurch as the pinch re-anchored.
    r.began(C, at: Point(390, 150))
    r.moved(C, to: Point(395, 150))

    #expect(r.activeTouches == 3)
    #expect(host.viewport.zoomLevel == afterTwo)   // C moving alone changes nothing
    #expect(host.recorder.events == [.cancel])     // only the second finger's cancel
  }

  @Test("a cancelled touch abandons the stroke without committing")
  func cancelAbandons() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(100, 100))
    r.moved(A, to: Point(130, 100))
    host.recorder.events.removeAll()

    r.cancelled(A)

    #expect(host.recorder.events == [.cancel])
    #expect(r.activeTouches == 0)
    #expect(!r.hasPendingPress)
  }

  @Test("the ghost does not linger after the finger lifts")
  func noHoverGhost() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(100, 100))
    r.moved(A, to: Point(120, 100))
    #expect(host.mouseWorld != nil)
    r.ended(A, at: Point(120, 100))
    // There is no hover on iOS. A straight port of the web would park a cursor
    // ghost at the last touch point for the rest of the session.
    #expect(host.mouseWorld == nil)
  }

  @Test("a move measures its delta from where the finger landed")
  func deltaFromLanding() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    var seen: Double?
    final class Probe: Tool {
      let id = ToolId.wall
      var onMove: ((PointerInfo) -> Void)?
      func onPointerMove(_ e: PointerInfo, _ ctx: ToolContext) { onMove?(e) }
      func preview() -> ToolPreview { .empty }
    }
    let probe = Probe()
    probe.onMove = { seen = $0.dxScreen }
    host.tool = probe

    r.began(A, at: Point(100, 100))
    r.moved(A, to: Point(137, 100))
    // 37, not 0: flushing the held press sets lastScreen to the landing point.
    #expect(seen == 37)
  }

  // MARK: - Panning with one finger

  /// Dragging with nothing armed used to do nothing whatsoever: `moved` ended
  /// in `host.tool?.onPointerMove`, and with no tool that optional chain is a
  /// no-op. Panning was two-fingers-only and the obvious gesture was dead.
  @Test("with no tool armed, one finger pans the map")
  func oneFingerPans() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)
    let before = (host.viewport.targetX, host.viewport.targetY)

    r.began(A, at: Point(200, 150))
    r.moved(A, to: Point(240, 130))
    r.ended(A, at: Point(240, 130))

    // panBy subtracts the screen delta over the scale, so dragging right and up
    // moves the camera left and down -- the map follows the finger.
    let s = host.viewport.scale
    #expect(host.viewport.targetX == before.0 - 40 / s)
    #expect(host.viewport.targetY == before.1 - (-20) / s)
  }

  /// The regression that matters more than the feature: a tool armed must still
  /// draw, and must not drag the map out from under the stroke.
  @Test("with a tool armed, one finger draws and does not pan")
  func armedToolStillDraws() {
    let host = FakeHost()   // init arms the recorder
    let r = PointerRouter(host: host)
    let before = (host.viewport.targetX, host.viewport.targetY)

    r.began(A, at: Point(200, 150))
    r.moved(A, to: Point(240, 130))
    r.ended(A, at: Point(240, 130))

    #expect(host.viewport.targetX == before.0)
    #expect(host.viewport.targetY == before.1)
    #expect(host.recorder.events.contains(.move(host.viewport.screenToWorld(Point(240, 130)))))
    #expect(host.freePans == 0)
  }

  @Test("the host hears about a free pan only when nothing is armed")
  func tellsTheHost() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.moved(A, to: Point(210, 150))
    r.moved(A, to: Point(220, 150))
    r.ended(A, at: Point(220, 150))
    // Once per move, which is exactly why the world guards it with a flag.
    #expect(host.freePans == 2)
  }

  /// The new branch sits after the pinch guard, so two fingers must be
  /// untouched by it -- including the tool-less case, which now has two ways to
  /// pan and must not apply both at once.
  @Test("two fingers still pinch, and do not also free-pan")
  func pinchUnaffected() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(100, 100))
    r.began(B, at: Point(200, 100))
    #expect(r.isPinching)
    r.moved(A, to: Point(90, 100))
    r.moved(B, to: Point(210, 100))

    // The pinch branch returns before the free-pan branch is reached.
    #expect(host.freePans == 0)
  }

  // MARK: - The idle tap, which brings hidden controls back

  @Test("a tap with nothing armed reaches the host")
  func idleTap() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.ended(A, at: Point(200, 150))

    #expect(host.idleTaps == 1)
    #expect(host.freePans == 0)
  }

  /// A finger resting on glass reports a point or two of travel, so measuring
  /// this by "was there a move at all" would mean the tap almost never landed.
  @Test("a little jitter is still a tap; a real drag is not")
  func tapSlop() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.moved(A, to: Point(203, 152))
    r.ended(A, at: Point(203, 152))
    #expect(host.idleTaps == 1)

    r.began(A, at: Point(200, 150))
    r.moved(A, to: Point(260, 150))
    r.ended(A, at: Point(260, 150))
    #expect(host.idleTaps == 1)
  }

  /// The regression that would make the feature invisible: with a tool armed a
  /// tap is a *stroke*, and treating it as idle would put the controls back
  /// every time somebody dropped a block of pedestrians.
  @Test("a tap with a tool armed is not an idle tap")
  func armedTapIsNotIdle() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.ended(A, at: Point(200, 150))

    #expect(host.idleTaps == 0)
    #expect(host.recorder.events.contains(.up(host.viewport.screenToWorld(Point(200, 150)))))
  }

  /// `host.tool` is read before the lift is delivered, and this is why: the
  /// goal tool steps off itself on a hit, so reading it afterwards would see
  /// nil and report a deliberate assignment as an idle tap.
  @Test("a tool that deactivates itself does not become an idle tap")
  func selfDeactivatingToolIsNotIdle() {
    let host = FakeHost()
    let stepper = SelfDeactivating(host: host)
    host.tool = stepper
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.ended(A, at: Point(200, 150))

    #expect(host.tool == nil)
    #expect(host.idleTaps == 0)
  }

  /// The leftover finger of a pinch must not read as a tap either -- it already
  /// must not reach a tool, and `releasePointer` returns before either.
  @Test("the last finger of a pinch is not an idle tap")
  func pinchLeftoverIsNotATap() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(100, 100))
    r.began(B, at: Point(200, 100))
    r.ended(B, at: Point(200, 100))
    r.ended(A, at: Point(100, 100))

    #expect(host.idleTaps == 0)
  }
}

/// A tool that steps off itself when the finger lifts, as `GoalTool` does after
/// a successful assignment.
@MainActor
private final class SelfDeactivating: Tool {
  let id = ToolId.goal
  private unowned let host: FakeHost
  init(host: FakeHost) { self.host = host }
  func onPointerUp(_: PointerInfo, _: ToolContext) { host.tool = nil }
  func preview() -> ToolPreview { .empty }
}

/// The twist, which is the pinch wearing a third hat: the same two fingers
/// already pan by their midpoint and zoom by their gap.
@Suite("Two-finger rotation")
@MainActor
struct PointerRotationTests {

  /// Puts two fingers on a horizontal line about the view centre and turns them
  /// by `degrees`, in one move each so the router sees a single step.
  private func twist(_ r: PointerRouter, _ degrees: Double, radius: Double = 100) {
    let c = Point(200, 150)
    r.began(A, at: Point(c.x - radius, c.y))
    r.began(B, at: Point(c.x + radius, c.y))
    let t = degrees * Double.pi / 180
    r.moved(A, to: Point(c.x - radius * cos(t), c.y - radius * sin(t)))
    r.moved(B, to: Point(c.x + radius * cos(t), c.y + radius * sin(t)))
  }

  @Test("a small twist is a pinch that wobbled, and the map stays straight")
  func belowTheSlop() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    twist(r, 5)
    #expect(host.viewport.rotation == 0)
  }

  @Test("past the slop the map turns with the fingers")
  func aboveTheSlop() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    twist(r, 40)
    // Everything past the slop, and the slop subtracted rather than forgiven --
    // so the map is exactly the slop shy of the fingers, at every angle.
    #expect(host.viewport.rotation > 0)
    #expect(abs(host.viewport.rotation
                - (40 * Double.pi / 180 - PointerRouter.ROTATE_SLOP)) < 0.001)
  }

  @Test("the world point between the fingers stays between them")
  func anchoredToTheFingers() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil
    host.viewport.targetX = 55
    host.viewport.targetY = -12

    let mid = Point(200, 150)
    let before = host.viewport.screenToWorld(mid)
    twist(r, 60)
    let after = host.viewport.screenToWorld(mid)
    #expect(abs(after.x - before.x) < 0.001)
    #expect(abs(after.y - before.y) < 0.001)
  }

  @Test("untwisting undoes the twist, all the way back to straight")
  func reversible() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    // Out past the slop and back to exactly where the fingers started. The map
    // has to come back with them: it is the same hand putting it back.
    twist(r, 30)
    #expect(host.viewport.rotation != 0)
    let c = Point(200, 150)
    r.moved(A, to: Point(c.x - 100, c.y))
    r.moved(B, to: Point(c.x + 100, c.y))
    #expect(abs(host.viewport.rotation) < 1e-9)
  }

  @Test("a map left a degree off straight is straightened when the fingers lift")
  func snapsOnLift() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    // Past the slop, then most of the way back: the fingers end a couple of
    // degrees off where they started, which is what hands actually do.
    twist(r, 30)
    let c = Point(200, 150)
    let t = 12 * Double.pi / 180
    r.moved(A, to: Point(c.x - 100 * cos(t), c.y - 100 * sin(t)))
    r.moved(B, to: Point(c.x + 100 * cos(t), c.y + 100 * sin(t)))
    #expect(host.viewport.rotation != 0)
    #expect(abs(host.viewport.rotation) < NORTH_SNAP)

    r.ended(A, at: Point(c.x - 100 * cos(t), c.y - 100 * sin(t)))
    #expect(host.viewport.rotation == 0)
  }

  @Test("a deliberate angle survives the lift")
  func keepsARealTilt() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    twist(r, 45)
    r.ended(A, at: Point(100, 150))
    #expect(abs(host.viewport.rotation
                - (45 * Double.pi / 180 - PointerRouter.ROTATE_SLOP)) < 0.001)
  }

  @Test("the slop is measured per gesture, not once per app")
  func slopResets() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    host.tool = nil

    twist(r, 40)
    r.ended(A, at: Point(100, 150))
    r.ended(B, at: Point(300, 150))
    let after = host.viewport.rotation

    // A second pinch that only wobbles must not inherit the first one's
    // permission to turn.
    twist(r, 4)
    #expect(abs(host.viewport.rotation - after) < 0.001)
  }

  @Test("a twist never reaches a tool")
  func toolsSeeNothing() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    twist(r, 40)
    // The wall tool would otherwise draw an arc across the map while the
    // fingers turned. `gestureTaken` is what keeps it out; this is the twist's
    // version of the assertion the pinch already makes.
    #expect(!host.recorder.events.contains { if case .move = $0 { return true }; return false })
    #expect(host.viewport.rotation != 0)
  }
}

/// The gestures that arrive already recognised, which is the only kind a Mac
/// has: an iPad app on a Mac never sees a second touch, so before these the
/// map there could not be zoomed or turned at all.
@Suite("A trackpad's pinch and twist")
@MainActor
struct IndirectGestureTests {
  @Test("a pinch zooms the map by the ratio it reports")
  func pinchZooms() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.pinched(at: Point(200, 150), by: 2)
    #expect(abs(host.viewport.scale - 2) < 1e-9)
    // Reported as the change since the last call, so two halves make a double.
    r.pinched(at: Point(200, 150), by: 0.5)
    #expect(abs(host.viewport.scale - 1) < 1e-9)
  }

  @Test("a twist turns the map, with no slop to break through first")
  func twistTurns() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    // Less than ROTATE_SLOP: two fingers would still be inside the dead zone,
    // a recogniser has already made up its mind.
    r.twisted(at: Point(200, 150), by: 0.1)
    #expect(abs(host.viewport.rotation - 0.1) < 1e-9)
  }

  @Test("the point under the gesture stays under it")
  func anchorHolds() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    let anchor = Point(80, 220)
    let before = host.viewport.screenToWorld(anchor)

    r.pinched(at: anchor, by: 1.8)
    r.twisted(at: anchor, by: 0.4)

    let after = host.viewport.screenToWorld(anchor)
    #expect(abs(after.x - before.x) < 1e-6)
    #expect(abs(after.y - before.y) < 1e-6)
  }

  @Test("fingers on the glass keep the gesture to themselves")
  func fingersWin() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(100, 100))
    r.began(B, at: Point(200, 100))
    let level = host.viewport.zoomLevel
    let spin = host.viewport.rotation

    // A recogniser watching the same two fingers would zoom the map twice.
    r.pinched(at: Point(150, 100), by: 2)
    r.twisted(at: Point(150, 100), by: 0.4)
    #expect(host.viewport.zoomLevel == level)
    #expect(host.viewport.rotation == spin)
  }

  @Test("the end of one puts a nearly-straight map straight")
  func endSnapsNorth() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.twisted(at: Point(200, 150), by: 0.05)
    r.indirectGestureEnded()
    #expect(host.viewport.rotation == 0)

    // A twist meant on purpose survives it.
    r.twisted(at: Point(200, 150), by: 0.6)
    r.indirectGestureEnded()
    #expect(abs(host.viewport.rotation - 0.6) < 1e-9)
  }
}

/// What a Mac has and a touchscreen does not: a pointer with no button down,
/// and a wheel.
@Suite("A pointer that is not a finger")
@MainActor
struct MacPointerTests {
  @Test("a hover reaches the tool with no buttons, so nothing is drawn")
  func hoverIsNotADrag() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.hovered(at: Point(140, 120))
    // Delivered, because the ghost under the cursor is what the tools draw
    // from -- and delivered as a *move with no button*, which is the whole
    // difference between a hover and painting a line of pedestrians.
    #expect(host.recorder.events == [.move(host.viewport.screenToWorld(Point(140, 120)))])
    #expect(host.mouseWorld != nil)
  }

  @Test("a hover while a button is down is left to the drag")
  func hoverYieldsToTheDrag() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    r.began(A, at: Point(100, 100))
    r.moved(A, to: Point(120, 100))
    let so_far = host.recorder.events.count

    r.hovered(at: Point(300, 300))
    #expect(host.recorder.events.count == so_far)
  }

  @Test("only a hover is a hover")
  func hoverWorldIsHoverOnly() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    // The one thing that gates the doorstep controls, and it has to be nil on a
    // touchscreen *by construction* rather than by policy: nothing below
    // writes it, and on iOS `hovered` is never called at all.
    r.began(A, at: Point(100, 100))
    r.moved(A, to: Point(120, 100))
    #expect(host.hoverWorld == nil)
    r.ended(A, at: Point(120, 100))
    #expect(host.hoverWorld == nil)

    r.hovered(at: Point(140, 120))
    #expect(host.hoverWorld != nil)
    // It survives the click it is about to be used by: down, then up.
    r.began(A, at: Point(140, 120))
    #expect(host.hoverWorld != nil)
    r.ended(A, at: Point(140, 120))
    #expect(host.hoverWorld != nil)

    r.hoverEnded()
    #expect(host.hoverWorld == nil)
    // And the *tool* is told, which clearing the two points above does not do:
    // only the cursor ghost was ever gated on them, so everything else a tool
    // draws under the pointer stayed on screen without this.
    #expect(host.recorder.events.contains(.left))
  }

  @Test("an idle tap says where it landed")
  func idleTapCarriesThePoint() {
    let host = FakeHost()
    host.tool = nil
    let r = PointerRouter(host: host)

    r.began(A, at: Point(200, 150))
    r.ended(A, at: Point(203, 152))
    #expect(host.idleTaps == 1)
    // The world needs the point to tell a click on a doorstep control from a
    // tap on bare ground.
    let landed = try! #require(host.tappedAt)
    let expected = host.viewport.screenToWorld(Point(203, 152))
    #expect(abs(landed.x - expected.x) < 1e-9)
    #expect(abs(landed.y - expected.y) < 1e-9)
  }

  @Test("the pointer leaving takes the ghost with it")
  func hoverEndsClean() {
    let host = FakeHost()
    let r = PointerRouter(host: host)

    r.hovered(at: Point(140, 120))
    r.hoverEnded()
    // `MapRenderer` draws the cursor ghost only where this is set, so clearing
    // it is what stops a ghost sitting in the window after the cursor has gone.
    #expect(host.mouseWorld == nil)
  }

  @Test("a wheel zooms about the pointer, in the original's own notches")
  func wheelZooms() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    let at = Point(120, 90)
    let under = host.viewport.screenToWorld(at)

    r.scrolled(at: at, notches: -3)
    #expect(host.viewport.zoomLevel == -3)
    // Whatever was under the cursor is still under it -- the property every
    // zoom in this app has.
    let now = host.viewport.screenToWorld(at)
    #expect(abs(now.x - under.x) < 1e-9)
    #expect(abs(now.y - under.y) < 1e-9)
  }

  @Test("a two-finger scroll pans by the delta it is given")
  func scrollPans() {
    let host = FakeHost()
    let r = PointerRouter(host: host)
    let before = (host.viewport.targetX, host.viewport.targetY)

    r.panned(by: 30, -12)
    // The same direction the two-finger branch of `moved` pans in: the map
    // travels with the fingers.
    #expect(host.viewport.targetX == before.0 - 30)
    #expect(host.viewport.targetY == before.1 + 12)
  }
}
