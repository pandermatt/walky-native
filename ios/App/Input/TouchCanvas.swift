import SwiftUI
import UIKit
import WalkyCore

/// The canvas's touch surface.
///
/// Deliberately thin: it translates `UITouch` into a point and hands it to
/// `PointerRouter`, which lives in `WalkyCore` and is unit-tested. Everything
/// subtle -- the withheld press, the second finger retracting it, the pinch --
/// is over there, where it can be driven by a script on a machine with no
/// simulator.
///
/// Raw touches rather than gesture recognisers. A `UIPinchGestureRecognizer`
/// or SwiftUI's `MagnificationGesture` only decides after a threshold, by which
/// time the drag has already told a tool to drop a block of pedestrians that no
/// `cancel()` can take back.
///
/// With one exception, and it is the whole of why the recognisers below exist:
/// a Mac has no fingers. An iPad app running on a Mac gets a trackpad pinch or
/// twist as a *recognised gesture* and never as a second touch, so on macOS the
/// raw-touch path above saw one pointer, always, and zooming and rotating the
/// map were simply not possible. The recognisers stand in for the fingers there
/// -- and on an iPad's trackpad, which had the same hole -- while every device
/// with glass keeps the path it had: see `ownsGesture` in `PointerRouter`,
/// which hands a gesture back to the fingers whenever there are two of them.
struct TouchCanvas: UIViewRepresentable {
  let router: PointerRouter
  /// A bare key from a hardware keyboard, which an iPad may well have. See
  /// `WalkyTouchView.keyCommands`.
  var onCommand: (Command) -> Void = { _ in }

  func makeUIView(context: Context) -> WalkyTouchView {
    let v = WalkyTouchView()
    v.router = router
    v.onCommand = onCommand
    return v
  }

  func updateUIView(_ view: WalkyTouchView, context: Context) {
    view.router = router
    view.onCommand = onCommand
  }
}

final class WalkyTouchView: UIView {
  var router: PointerRouter?
  var onCommand: (Command) -> Void = { _ in }

  override init(frame: CGRect) {
    super.init(frame: frame)
    // Without this there is no pinch, ever: UIKit delivers only one touch.
    isMultipleTouchEnabled = true
    isOpaque = false
    backgroundColor = .clear

    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
    doubleTap.numberOfTapsRequired = 2
    // Deliberately without `require(toFail:)`: the web gets `dblclick`
    // alongside its pointer events rather than instead of them, and the wall
    // tool depends on both arriving.
    doubleTap.delaysTouchesEnded = false
    addGestureRecognizer(doubleTap)

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
    let twist = UIRotationGestureRecognizer(target: self, action: #selector(onTwist(_:)))
    for g in [pinch, twist] as [UIGestureRecognizer] {
      g.delegate = self
      // None of the three may swallow the touches: on a touchscreen those same
      // touches are the pinch, and a `touchesCancelled` arriving mid-stroke
      // would take back a wall that was being drawn.
      g.cancelsTouchesInView = false
      g.delaysTouchesBegan = false
      g.delaysTouchesEnded = false
      addGestureRecognizer(g)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not from a nib") }

  // MARK: - A hardware keyboard

  /// The bare keys, answered here rather than by the menu bar.
  ///
  /// `WalkyCommands` carries everything with Command on it, which iPadOS puts
  /// in the menu a held Command key draws. What it will *not* reliably take is
  /// a key equivalent with no modifier at all, which is every digit and Space.
  /// A `UIKeyCommand` on the view that is already the map's input surface will,
  /// and it is the same surface a touch goes through -- so a shortcut and a
  /// finger reach the app by one route each rather than one route between them.
  override var canBecomeFirstResponder: Bool { true }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // Nothing else in the map wants the keyboard, so this takes it on arrival.
    // A text field in Settings is presented over this and takes it back.
    if window != nil { becomeFirstResponder() }
  }

  override var keyCommands: [UIKeyCommand]? {
    Command.all.compactMap { command in
      guard let shortcut = command.shortcut, !shortcut.command, !shortcut.shift else { return nil }
      let input: String
      switch shortcut.key {
      case .character(let c): input = c
      case .space: input = " "
      case .escape: input = UIKeyCommand.inputEscape
      case .delete: return nil
      }
      let key = UIKeyCommand(title: command.title, action: #selector(onShortcut(_:)),
                             input: input)
      // Space scrolls and Escape dismisses, both of which the system would do
      // first. On the map neither has anything to act on, so this asks for it.
      key.wantsPriorityOverSystemBehavior = true
      return key
    }
  }

  @objc private func onShortcut(_ sender: UIKeyCommand) {
    guard let input = sender.input else { return }
    let match: Command?
    switch input {
    case " ": match = Command.space
    case UIKeyCommand.inputEscape: match = Command.escape
    default: match = Command.bare(input)
    }
    if let match { onCommand(match) }
  }

  private func at(_ t: UITouch) -> Point {
    // Points, not pixels: the view's CGContext is already scaled by
    // contentScaleFactor, so working in points is what keeps world-to-screen
    // sharing units with touches.
    let p = t.location(in: self)
    return Point(Double(p.x), Double(p.y))
  }

  private func id(_ t: UITouch) -> TouchId { TouchId(ObjectIdentifier(t).hashValue) }

  // One call per touch: UIKit batches them into a set where the web delivers
  // one event each, and the router's finger-count rules depend on seeing them
  // one at a time.
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches { router?.began(id(t), at: at(t)) }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches { router?.moved(id(t), to: at(t)) }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches { router?.ended(id(t), at: at(t)) }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches { router?.cancelled(id(t)) }
  }

  /// Reported to the router as the change since the last callback, which is
  /// what resetting `scale` to 1 each time buys: the camera is a running sum,
  /// and a gesture recogniser's own total would apply the same zoom twice.
  @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
    switch g.state {
    case .changed:
      router?.pinched(at: Point(Double(g.location(in: self).x),
                                Double(g.location(in: self).y)), by: Double(g.scale))
      g.scale = 1
    case .ended, .cancelled, .failed:
      router?.indirectGestureEnded()
    default: break
    }
  }

  @objc private func onTwist(_ g: UIRotationGestureRecognizer) {
    switch g.state {
    case .changed:
      router?.twisted(at: Point(Double(g.location(in: self).x),
                                Double(g.location(in: self).y)),
                      by: Double(g.rotation))
      g.rotation = 0
    case .ended, .cancelled, .failed:
      router?.indirectGestureEnded()
    default: break
    }
  }

  @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
    let p = g.location(in: self)
    router?.doubleTapped(at: Point(Double(p.x), Double(p.y)))
  }
}

/// Pinch and twist are one gesture on a trackpad -- you do both at once without
/// meaning to -- so neither recogniser may win the other's events. Without this
/// UIKit lets exactly one of them run and a twisted zoom loses half of itself.
extension WalkyTouchView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ g: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }
}
