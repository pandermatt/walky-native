import Foundation

/// Adds pedestrians, from `controller/PedestrianMouseListener`: a tap drops an
/// n x n block and dragging paints continuously, so a crowd can be laid down in
/// one gesture. Ports `src/tools/pedestrianTool.ts`.
@MainActor
public final class PedestrianTool: Tool {
  public let id = ToolId.pedestrian
  private var painting = false
  /// Ghost dots for the block under the cursor, as `drawTemporaryPedestrians` did.
  private var ghost: [Point] = []
  /// Where the last dot landed, so the next one is a body's width away.
  private var lastPlaced: Point?

  public init() {}

  public func onPointerDown(_ e: PointerInfo, _ ctx: ToolContext) {
    if e.buttons != 1 { return }
    painting = true
    // One checkpoint for the whole stroke. It used to be one per dot, and a
    // checkpoint copies every wall on the map and every agent already placed,
    // so a drag pushed a hundred of them -- which buried the forty-deep undo
    // stack under one gesture and made undo rewind a stroke a dot at a time.
    // `addPedestrians`' own doc comment already made this argument for a
    // described crowd; a drag is the same edit made of many events.
    ctx.checkpoint()
    paint(e, ctx)
  }

  public func onPointerMove(_ e: PointerInfo, _ ctx: ToolContext) {
    if painting && e.buttons != 0 {
      paint(e, ctx)
      return
    }
    ghost = ctx.pedestrianBlock(e.world, nil)
    ctx.requestRender()
  }

  /// One dot of a stroke, no nearer than a body's width to the last.
  ///
  /// Every other drag tool samples -- `WallTool` at 3 screen points,
  /// `GoalTool` at 4 -- and this was the one that did not, so it committed a
  /// world edit on every raw pointer event, sixty or a hundred and twenty a
  /// second. The spacing is in world units rather than screen ones because the
  /// thing it is protecting is the brush's own pitch: `pedestrianBlock` lays
  /// bodies `2 * radius` apart, so a move shorter than that cannot put anybody
  /// anywhere new, and the whole cost would be paid to place nothing.
  private func paint(_ e: PointerInfo, _ ctx: ToolContext) {
    let pitch = 2 * ctx.settings().pedestrianRadius
    if let lastPlaced, distance(lastPlaced, e.world) < pitch { return }
    lastPlaced = e.world
    _ = ctx.addPedestrians(e.world)
    // Whatever the block had room for is standing in it now, so nothing there
    // is still free -- which is what the second `pedestrianBlock` call this
    // replaces used to spend a full spatial-hash rebuild to discover.
    ghost = []
    ctx.requestRender()
  }

  public func onPointerUp(_ e: PointerInfo, _ ctx: ToolContext) {
    painting = false
    lastPlaced = nil
    // No hover on iOS: once the finger is gone there is no pointer to preview
    // under, and a ghost left at the last touch point sits there for the rest
    // of the session. The web keeps it because a mouse really is still there.
    ghost = []
    ctx.requestRender()
  }

  /// Otherwise the block of bodies stays parked wherever the pointer left the
  /// window.
  public func pointerLeft() {
    ghost = []
  }

  public func cancel() {
    painting = false
    lastPlaced = nil
    ghost = []
  }

  public func preview() -> ToolPreview {
    var p = ToolPreview()
    p.pendingPedestrians = ghost
    return p
  }
}
