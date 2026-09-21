import AppKit
import SwiftUI
import WalkyCore

/// The Mac's input surface: the counterpart of `TouchCanvas`, and the only
/// file in the Mac target that knows what a mouse is.
///
/// It translates `NSEvent` into the same `PointerRouter` calls the phone makes
/// from `UITouch`, which is the whole reason the router lives in `WalkyCore`
/// and speaks in points rather than in touches. A Mac brings three things a
/// touchscreen does not, and each is handled here rather than in the router:
///
/// **A hover.** There is a pointer on screen with no button down, which is what
/// the web has and the phone does not -- so the tool ghosts, which on iOS
/// appear only while a finger is down, follow the cursor here as they do on the
/// web. See `PointerRouter.hovered`.
///
/// **Gestures that arrive already recognised.** A trackpad pinch or twist is an
/// `NSEvent`, never a second touch, so it goes through the same `pinched` and
/// `twisted` entry points that an iPad app on a Mac uses.
///
/// **A scroll wheel.** Two-finger scrolling pans; a wheel -- which has no
/// precise deltas -- zooms, because that is what a wheel does on a map. Holding
/// Command or Control zooms either way.
struct MacCanvas: NSViewRepresentable {
  let router: PointerRouter
  /// A bare key: the digits, Space and Escape. See `WalkyPointerView.keyDown`.
  var onCommand: (Command) -> Void = { _ in }

  func makeNSView(context: Context) -> WalkyPointerView {
    let v = WalkyPointerView()
    v.router = router
    v.onCommand = onCommand
    return v
  }

  func updateNSView(_ view: WalkyPointerView, context: Context) {
    view.router = router
    view.onCommand = onCommand
  }
}

final class WalkyPointerView: NSView {
  var router: PointerRouter?
  var onCommand: (Command) -> Void = { _ in }

  /// One pointer, so one identity for the whole session: a mouse cannot put a
  /// second finger down, and the router keys its fingers by id.
  private static let pointer = TouchId(1)

  private var tracking: NSTrackingArea?

  /// Top-left origin, like everything else here.
  ///
  /// Not cosmetic: `MapCanvas` draws through SwiftUI's `GraphicsContext`, whose
  /// origin is the top-left corner, and `Viewport` maps world to screen in
  /// those same coordinates. An unflipped `NSView` would hand every click a y
  /// measured from the bottom, and the map would answer the mirror image of
  /// wherever the cursor was.
  override var isFlipped: Bool { true }

  override var acceptsFirstResponder: Bool { true }

  /// A click on an inactive window arms the tool as well as activating it. The
  /// map is a canvas, and a canvas that eats the first click makes you click
  /// twice to start a line.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // The map is what the window is for, and nothing else in it wants the
    // keyboard: a field in the Settings *window* is a different window's
    // responder chain.
    window?.makeFirstResponder(self)
  }

  // MARK: - A keyboard

  /// The bare keys. Everything carrying Command is the menu bar's, and a menu
  /// key equivalent is consumed before this is ever called -- so there is no
  /// double-fire to guard against, only the keys the menu declines to take.
  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.isDisjoint(with: [.command, .control, .option]) else {
      super.keyDown(with: event)
      return
    }
    let match: Command?
    switch event.keyCode {
    case 49: match = Command.space
    case 53: match = Command.escape
    default: match = event.charactersIgnoringModifiers.flatMap { Command.bare($0) }
    }
    guard let match else {
      // Unhandled keys keep travelling, or the window stops beeping about
      // things it should beep about.
      super.keyDown(with: event)
      return
    }
    onCommand(match)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    // `.inVisibleRect` keeps this correct through every resize without
    // recomputing the rect, which is the one thing tracking areas are famous
    // for getting wrong.
    let area = NSTrackingArea(rect: .zero,
                              options: [.mouseMoved, .mouseEnteredAndExited,
                                        .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    tracking = area
  }

  private func at(_ event: NSEvent) -> Point {
    let p = convert(event.locationInWindow, from: nil)
    return Point(Double(p.x), Double(p.y))
  }

  // MARK: - The mouse

  override func mouseDown(with event: NSEvent) {
    // A double-click is delivered as a second `mouseDown` with
    // `clickCount == 2`, on top of the first -- the web gets `dblclick`
    // alongside its pointer events in exactly the same way, and the wall tool
    // depends on both arriving.
    if event.clickCount == 2 { router?.doubleTapped(at: at(event)) }
    router?.began(Self.pointer, at: at(event))
  }

  override func mouseDragged(with event: NSEvent) {
    router?.moved(Self.pointer, to: at(event))
  }

  override func mouseUp(with event: NSEvent) {
    router?.ended(Self.pointer, at: at(event))
  }

  override func mouseMoved(with event: NSEvent) {
    router?.hovered(at: at(event))
  }

  override func mouseExited(with event: NSEvent) {
    router?.hoverEnded()
  }

  // MARK: - The trackpad

  override func magnify(with event: NSEvent) {
    switch event.phase {
    case .changed:
      // `magnification` is the change since the last event, which is the shape
      // `pinched` wants: the camera is a running sum.
      router?.pinched(at: at(event), by: 1 + Double(event.magnification))
    case .ended, .cancelled:
      router?.indirectGestureEnded()
    default: break
    }
  }

  override func rotate(with event: NSEvent) {
    switch event.phase {
    case .changed:
      // Negated: `NSEvent.rotation` is degrees counterclockwise, and the
      // viewport's angle is radians clockwise -- screen y points down.
      router?.twisted(at: at(event), by: -Double(event.rotation) * .pi / 180)
    case .ended, .cancelled:
      router?.indirectGestureEnded()
    default: break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard let router else { return }
    let zooming = event.modifierFlags.contains(.command)
      || event.modifierFlags.contains(.control)
      // A wheel has detents and no precise deltas. On a map a wheel zooms --
      // it is what `ZoomMouseListener` was written for, and the original's
      // whole camera is a count of wheel notches.
      || !event.hasPreciseScrollingDeltas

    if zooming {
      let notches = Double(event.hasPreciseScrollingDeltas
                           ? event.scrollingDeltaY / 20
                           : event.scrollingDeltaY)
      guard notches != 0 else { return }
      // Scrolling up zooms in, and `zoomLevel` counts the other way.
      router.scrolled(at: at(event), notches: -notches)
      return
    }

    // The map travels with the fingers, as it does under a two-finger drag on
    // the phone and as it does in Maps.
    //
    // The delta is used as it arrives, and that is the fix rather than the
    // shortcut: the system has *already* applied the natural-scrolling setting
    // to the sign it hands over. Reading `isDirectionInvertedFromDevice` and
    // flipping again applied it twice, which is why the map used to walk away
    // from the fingers pushing it.
    router.panned(by: Double(event.scrollingDeltaX), Double(event.scrollingDeltaY))
  }
}
