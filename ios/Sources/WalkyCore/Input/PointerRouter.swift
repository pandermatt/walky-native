import Foundation

/// A touch's identity for the life of that touch. `ObjectIdentifier(UITouch)`
/// on iOS; anything stable in a test.
public struct TouchId: Hashable, Sendable {
  public let raw: Int
  public init(_ raw: Int) { self.raw = raw }
}

/// What the router needs from the world it drives.
///
/// Deliberately not `WalkyWorld` itself: this is the most intricate code in the
/// phase, and the whole point of it living in `WalkyCore` rather than the app
/// target is that it can be driven by a fake in a test on a machine with no
/// simulator.
@MainActor
public protocol PointerHost: AnyObject {
  var viewport: Viewport { get set }
  var tool: Tool? { get }
  var toolContext: ToolContext { get }
  /// Where the pointer last hovered, in world units. Nil on iOS except during a
  /// touch -- there is no hover, and a ghost parked at the last touch point is
  /// exactly the artefact to avoid.
  var mouseWorld: Point? { get set }
  /// Where a pointer is hovering with no button down. Nil on iOS always: only
  /// `hovered(at:)` writes it, and a touchscreen never hovers. What it gates is
  /// chrome that can only be clicked by something with a cursor.
  var hoverWorld: Point? { get set }
  func requestRender()
  /// A one-finger drag with no tool armed. Whether that is worth saying
  /// anything about is the host's business, not the router's -- the router
  /// knows the gesture happened; only the world knows whether the map is empty.
  func pannedWithoutTool()
  /// A one-finger tap that went nowhere, with no tool armed. The gesture that
  /// was free: with nothing armed a tap has never done anything at all, where a
  /// drag pans and a second finger pinches. That is what makes it safe to hang
  /// "bring the controls back" on, and the router stays ignorant of what the
  /// host does with it.
  /// The point it landed on, because by now some of them hit something: a
  /// doorstep control is clicked by an idle tap, and the host has to be able to
  /// tell that from a tap on bare ground.
  func tappedWithoutTool(at: Point)
}

/// The pointer and gesture state machine, ported from `app.ts:457–720`.
///
/// Everything about it that looks odd is load-bearing:
///
/// **A press is withheld.** On a touchscreen the tool hears about a press only
/// once the finger has moved or lifted, which is when it is certainly a stroke
/// rather than the first half of a pinch. A tool that has already dropped a
/// block of pedestrians or reassigned every goal cannot be talked out of it by
/// `cancel()`, and the second finger of a pinch always arrives after the first.
/// This is why SwiftUI's `DragGesture` + `MagnificationGesture` cannot be used:
/// by the time a magnification is recognised, `onChanged` has already fired.
///
/// **`pointers` is an ordered array, not a dictionary.** `measurePinch` takes
/// the first two fingers *in insertion order*; a dictionary would pick an
/// arbitrary two on a three-finger touch, and the map would lurch. Same hazard
/// as `Navigation.fieldOrder`, same fix.
///
/// **`gestureTaken` outlives the second finger.** It clears only when the last
/// finger lifts, so the finger still down after a pinch cannot start a stroke.
@MainActor
public final class PointerRouter {
  private unowned let host: PointerHost

  /// Every finger currently down, in view points, oldest first.
  private var pointers: [(id: TouchId, at: Point)] = []
  private var pinch: (gap: Double, mid: Point, angle: Double)?
  /// How far the fingers have turned since this pinch began, in radians. What
  /// the map does with it is `pastSlop`.
  private var spun: Double = 0
  /// A press held back from the tool until it is certainly a stroke.
  private var pendingTouch: (id: TouchId, info: PointerInfo)?
  /// The pinch has claimed this gesture.
  private var gestureTaken = false
  /// Previous screen point: the only source of dxScreen/dyScreen.
  private var lastScreen: Point?
  /// Where the current one-finger gesture landed, for telling a tap from a drag
  /// at the lift. Not `pendingTouch`: that clears on the first `moved`, and a
  /// finger resting on glass reports movement of a point or two, so a tap
  /// measured that way would almost never register.
  private var pressScreen: Point?

  /// How far a finger may travel and still count as a tap, in screen points.
  /// The system's own figure for the same question.
  private static let TAP_SLOP: Double = 10

  /// How far the fingers must turn before the map follows, in radians -- about
  /// ten degrees. Two fingers pinching are never quite parallel to where they
  /// started, and without this every zoom would leave the map a little crooked.
  /// Internal rather than private so the tests can say what they mean.
  static let ROTATE_SLOP: Double = 0.175

  /// How far the map has turned, given how far the fingers have: everything
  /// past the slop, and nothing at all inside it.
  ///
  /// The slop is *subtracted* rather than forgiven, which is the whole design.
  /// Forgive it -- start turning from wherever the fingers were when they broke
  /// through -- and the map jumps by ten degrees at that instant, and worse, a
  /// twist out to fifteen degrees and back to zero leaves it ten degrees
  /// crooked with the fingers exactly where they started and nothing on screen
  /// to explain it. Subtracting keeps the map a continuous function of the
  /// fingers: no jump when it engages, and every twist undoable by untwisting.
  static func pastSlop(_ spun: Double) -> Double {
    if spun > ROTATE_SLOP { return spun - ROTATE_SLOP }
    if spun < -ROTATE_SLOP { return spun + ROTATE_SLOP }
    return 0
  }

  public init(host: PointerHost) { self.host = host }

  // Exposed for tests, which is the reason this type exists apart from the app.
  public var activeTouches: Int { pointers.count }
  public var isPinching: Bool { pinch != nil }
  public var hasGestureTaken: Bool { gestureTaken }
  public var hasPendingPress: Bool { pendingTouch != nil }

  private func info(_ screen: Point, buttons: Int) -> PointerInfo {
    let dx = lastScreen.map { screen.x - $0.x } ?? 0
    let dy = lastScreen.map { screen.y - $0.y } ?? 0
    return PointerInfo(world: host.viewport.screenToWorld(screen), screen: screen,
                       dxScreen: dx, dyScreen: dy, shiftKey: false, buttons: buttons)
  }

  public func began(_ id: TouchId, at screen: Point) {
    pointers.append((id, screen))

    if pointers.count == 2 {
      // A second finger says the first one was never a stroke. Whatever it
      // began is taken back here, before the map starts moving under it.
      pendingTouch = nil
      host.tool?.cancel()
      lastScreen = nil
      gestureTaken = true
      pinch = measurePinch()
      host.requestRender()
      return
    }
    if pointers.count > 2 || gestureTaken { return }

    lastScreen = screen
    pressScreen = screen
    // Held rather than delivered -- see the note on the type.
    pendingTouch = (id, info(screen, buttons: 1))
  }

  public func moved(_ id: TouchId, to screen: Point) {
    if let i = pointers.firstIndex(where: { $0.id == id }) { pointers[i].at = screen }

    if let was = pinch {
      guard let now = measurePinch(), was.gap > 0 else { return }
      // The midpoint carries the map with it, so the same gesture pans: two
      // fingers travelling together are a drag, and holding the view still
      // under them would feel like the map had come loose.
      host.viewport.panBy(now.mid.x - was.mid.x, now.mid.y - was.mid.y)
      host.viewport.zoomByRatio(now.mid, now.gap / was.gap)

      // Rotation is withheld the way a press is, and for a cousin of the same
      // reason: a gesture that has not declared itself should not move the map
      // in a way that cannot be taken back. The map turns by the change in what
      // the fingers have *earned*, not by the change in where they are -- see
      // `pastSlop`.
      let earned = Self.pastSlop(spun)
      spun += wrapAngle(now.angle - was.angle)
      host.viewport.rotateBy(now.mid, Self.pastSlop(spun) - earned)

      pinch = now
      host.requestRender()
      return
    }
    if gestureTaken { return }
    if pendingTouch?.id == id { flushPendingTouch() }

    let e = info(screen, buttons: 1)
    // Computed before the pan, which is the honest answer to "what was under the
    // finger" at this instant, and keeps the debug readout's X/Y live.
    host.mouseWorld = e.world
    if host.tool == nil {
      // With nothing armed, one finger drags the map. It used to do nothing at
      // all: this line was `host.tool?.onPointerMove`, and with no tool that
      // optional chain is a no-op, so panning was two-fingers-only and the
      // obvious one-handed gesture was silently dead.
      //
      // `dxScreen`/`dyScreen` are already the right delta -- `flushPendingTouch`
      // sets `lastScreen` to the landing point precisely so the move delivered
      // next measures from it -- and the sign matches the two-finger branch
      // above, which pans by the midpoint's travel.
      host.viewport.panBy(e.dxScreen, e.dyScreen)
      host.pannedWithoutTool()
      host.requestRender()
    } else {
      host.tool?.onPointerMove(e, host.toolContext)
    }
    lastScreen = screen
  }

  public func ended(_ id: TouchId, at screen: Point) {
    let press = pressScreen
    pressScreen = nil
    if releasePointer(id) { return }
    if pendingTouch?.id == id { flushPendingTouch() }
    // Read *before* the lift is delivered. A tool that steps off itself on a
    // successful commit -- as the goal tool does -- would otherwise leave
    // `host.tool` nil by the time this ran, and its own assignment would be
    // indistinguishable from an idle tap on bare ground.
    let idle = host.tool == nil
    let e = info(screen, buttons: 0)
    host.tool?.onPointerUp(e, host.toolContext)
    if idle, let press,
       jsHypot(screen.x - press.x, screen.y - press.y) <= Self.TAP_SLOP {
      host.tappedWithoutTool(at: e.world)
    }
    lastScreen = nil
    // There is no hover on iOS: once the finger is gone the ghost should be too.
    host.mouseWorld = nil
    host.requestRender()
  }

  /// The system taking a gesture back mid-stroke: nothing was finished, so
  /// nothing should be committed.
  public func cancelled(_ id: TouchId) {
    _ = releasePointer(id)
    pendingTouch = nil
    spun = 0
    pressScreen = nil
    host.tool?.cancel()
    lastScreen = nil
    host.mouseWorld = nil
    host.hoverWorld = nil
    host.requestRender()
  }

  public func doubleTapped(at screen: Point) {
    let e = info(screen, buttons: 1)
    host.tool?.onDoubleTap(e, host.toolContext)
    host.requestRender()
  }

  // MARK: - A pointer that is not a finger

  /// The pointer moving with no button down.
  ///
  /// A Mac has a hover where a touchscreen has nothing at all, and the tools
  /// were written for a mouse first: `app.ts` sends `pointermove` whether or
  /// not a button is down, every tool guards its drag on `e.buttons != 0`, and
  /// what that buys is the ghost of the shape you are about to draw following
  /// the cursor. On iOS that path was simply never taken. Here it is, which is
  /// why the buttons are 0: a tool that mistook this for a drag would paint a
  /// line of pedestrians from wherever the cursor last rested.
  public func hovered(at screen: Point) {
    // A button *is* down, so this is a drag and `moved` owns it.
    guard pointers.isEmpty else { return }
    let e = info(screen, buttons: 0)
    host.mouseWorld = e.world
    host.hoverWorld = e.world
    host.tool?.onPointerMove(e, host.toolContext)
    lastScreen = screen
    host.requestRender()
  }

  /// The pointer leaving the map. Clearing `mouseWorld` is what takes the ghost
  /// with it -- see the cursor ghost in `MapRenderer`, which is drawn only
  /// where there is a pointer to draw it under.
  public func hoverEnded() {
    guard pointers.isEmpty else { return }
    lastScreen = nil
    host.mouseWorld = nil
    host.hoverWorld = nil
    // The tool is told, where clearing `mouseWorld` used to be the whole of it:
    // that gates the cursor ghost and nothing else, so the pedestrian block and
    // the goal's fan of lines stayed drawn at the point the pointer left.
    host.tool?.pointerLeft()
    host.requestRender()
  }

  /// A scroll wheel, in notches, about a point: `ZoomMouseListener`'s own
  /// gesture, arriving on the platform it was written for.
  public func scrolled(at screen: Point, notches: Double) {
    guard notches.isFinite, notches != 0 else { return }
    host.viewport.zoomAt(screen, notches)
    host.requestRender()
  }

  /// A two-finger scroll, as a screen-space delta. The sign is the caller's
  /// business -- a Mac's natural-scrolling switch is not the router's to read.
  public func panned(by dxScreen: Double, _ dyScreen: Double) {
    guard dxScreen != 0 || dyScreen != 0 else { return }
    host.viewport.panBy(dxScreen, dyScreen)
    host.requestRender()
  }

  // MARK: - Gestures that arrive without fingers

  /// A pinch reported as a ratio rather than measured from two touches.
  ///
  /// The whole of why this exists: a Mac has no fingers on the glass. An iPad
  /// app on a Mac gets a trackpad pinch as a *recognised gesture*, and its
  /// `touchesBegan` never sees a second touch at all -- so `measurePinch`, and
  /// with it every zoom and every twist, simply never happened there. The
  /// arithmetic is the same either way; only where the numbers come from
  /// differs, which is why this hands them to the same `Viewport` calls the
  /// two-finger branch of `moved` uses.
  ///
  /// Reported as the change since the last call, not as the total since the
  /// gesture began, so the caller resets its recogniser each time and the
  /// camera stays a running sum -- the shape `rotateBy` and `zoomByRatio`
  /// already expect.
  public func pinched(at screen: Point, by ratio: Double) {
    guard !ownsGesture else { return }
    host.viewport.zoomByRatio(screen, ratio)
    host.requestRender()
  }

  /// A twist reported the same way, in radians since the last call.
  ///
  /// No `ROTATE_SLOP` here, and that is deliberate: the slop exists because two
  /// fingers pinching are never quite parallel to where they started, and a
  /// recogniser that has already decided this is a rotation has applied a
  /// threshold of its own. `snapNorth` on the lift still settles it straight.
  public func twisted(at screen: Point, by radians: Double) {
    guard !ownsGesture else { return }
    host.viewport.rotateBy(screen, radians)
    host.requestRender()
  }

  /// The end of a recognised pinch or twist: where a map left a degree off
  /// straight is put straight, exactly as the last finger of a pinch does it.
  public func indirectGestureEnded() {
    guard !ownsGesture else { return }
    if host.viewport.snapNorth() { host.requestRender() }
  }

  /// Whether the fingers already have this gesture. Two of them on the glass
  /// are driving the map through `moved`, and a recogniser watching the same
  /// two would zoom it a second time.
  private var ownsGesture: Bool { pointers.count >= 2 }

  private func measurePinch() -> (gap: Double, mid: Point, angle: Double)? {
    guard pointers.count >= 2 else { return nil }
    let a = pointers[0].at, b = pointers[1].at
    // The angle is of the line between the fingers, which is why the pair has
    // to keep its insertion order: swap the two and it jumps by pi.
    return (jsHypot(b.x - a.x, b.y - a.y),
            Point((a.x + b.x) / 2, (a.y + b.y) / 2),
            jsAtan2(b.y - a.y, b.x - a.x))
  }

  private func flushPendingTouch() {
    guard let held = pendingTouch else { return }
    pendingTouch = nil
    // The *original* info: the tool sees the press where the finger landed, not
    // where it has moved to. `lastScreen` becomes that landing point, so the
    // move delivered next measures its delta from it.
    lastScreen = held.info.screen
    host.tool?.onPointerDown(held.info, host.toolContext)
  }

  /// Removes a finger. True when the release belonged to the pinch -- including
  /// the last finger of one, which is a leftover rather than the start of a
  /// stroke, and must not reach a tool.
  private func releasePointer(_ id: TouchId) -> Bool {
    pointers.removeAll { $0.id == id }
    let wasGesture = gestureTaken
    if pinch != nil && pointers.count < 2 {
      pinch = nil
      // The end of the twist, so this is where a map left a degree off straight
      // is put straight. Doing it per-move instead would fight the fingers.
      if host.viewport.snapNorth() { host.requestRender() }
      spun = 0
    }
    else if pinch != nil { pinch = measurePinch() }
    if pointers.isEmpty { gestureTaken = false }
    if wasGesture { lastScreen = nil }
    return wasGesture
  }
}
