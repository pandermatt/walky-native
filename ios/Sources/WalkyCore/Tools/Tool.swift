import Foundation

/// The tool vocabulary, ported from `src/tools/types.ts`.

public enum ToolId: String, CaseIterable, Sendable {
  case wall, rectangle, border, pedestrian, goal, measure, generator
  // Present in the web app, not in v1: select, shift, erase, text, generator.
}

extension ToolId {
  /// Whether this tool's cursor ghost follows a pointer that is merely
  /// *hovering* -- which is a macOS question, because a touchscreen never
  /// hovers and a ghost there is only ever drawn under a finger already down.
  ///
  /// Two of the seven, and the rule is what the ghost is *for*: these are the
  /// ones whose mark answers "what happens if I click here". The pedestrian
  /// block shows which spots are actually free, and the goal's ring and lines
  /// show what would be aimed where. The rest were marking where the cursor
  /// was, which the cursor was already doing.
  public var ghostsOnHover: Bool { self == .pedestrian || self == .goal }
}

/// The shape drawn under the pointer to say what the active tool will do.
///
/// Replaces the original's 32x32 PNG cursors, which could not show a tool's
/// actual dimensions -- they cannot grow with the pedestrian radius or the brush
/// size. On iOS there is no hover, so a ghost is drawn only while a touch is
/// down; see the note in the plan about offsetting it clear of the finger.
public enum GhostKind: Sendable { case square, squiggle, frame, target, eraser }

public struct CursorGhost: Sendable {
  public var kind: GhostKind
  public var at: Point
  /// Radius or half-extent, in world units.
  public var size: Double
  public init(kind: GhostKind, at: Point, size: Double) {
    self.kind = kind; self.at = at; self.size = size
  }
}

/// Lines from each pedestrian to the pointer, for the mark-goal tool.
public struct TargetLines: Sendable {
  public var to: Point
  /// Colour of the shape under the pointer, or nil to use each pedestrian's own.
  public var color: RGB?
  public init(to: Point, color: RGB?) { self.to = to; self.color = color }
}

/// Transient state a tool wants drawn on the overlay.
///
/// Every field has a default, so a tool writes only what it means -- the port of
/// `{ ...EMPTY_PREVIEW, pendingRect }`, except the compiler checks the names
/// where a spread would silently ignore a typo.
public struct ToolPreview: Sendable {
  public var pendingWallPoints: [Point] = []
  /// True while tracing freehand: draw as a closing outline, not placed vertices.
  public var pendingWallTracing = false
  /// The box being dragged, as its four corners rather than two.
  ///
  /// Two opposite corners were enough while every box was axis-aligned. A box
  /// drawn on a turned map is square to the *screen*, which world space sees as
  /// a tilted quad, and two corners cannot say which tilt -- so the tool hands
  /// over the shape it is about to commit rather than the drag it came from.
  public var pendingRect: [Point]?
  /// Arbitrary outlines to preview, e.g. the bars of a border frame.
  public var pendingPolygons: [[Point]] = []
  /// Draw the pending outlines as a warning: the shape would be unusable.
  public var pendingPolygonsInvalid = false
  /// Where pedestrians would land if the brush fired now.
  public var pendingPedestrians: [Point] = []
  public var cursorGhost: CursorGhost?
  /// A wall the pointer is over that the tool would turn into something else.
  ///
  /// The generator's whole preview, and a better one than the ring it replaced:
  /// a mark at the cursor says where the cursor is, which the cursor was
  /// already saying. Naming the block says what the click would do to *it*.
  public var markingWallId: Int?
  public var targetLines: TargetLines?
  /// A point a two-tap tool has already placed, drawn as the endpoint it is
  /// about to become.
  ///
  /// Its own field rather than a one-point `pendingWallPoints`, which is what
  /// the measure tool used to say and which drew nothing at all: a path of one
  /// point strokes to nothing, so the first tap of a measurement landed with no
  /// mark on the map and the tool looked as though it had missed.
  public var anchorPoint: Point?
  /// The lasso being dragged, as a closed outline. Its own field rather than
  /// `pendingWallPoints` + `pendingWallTracing`: those two mean "a wall is being
  /// traced", and a lasso and a wall outline are the one pair of previews that
  /// must never be mistaken for each other -- both are freehand rings drawn with
  /// the same finger, and only the colour says which shape you are about to get.
  public var selectionPolygon: [Point]?

  public init() {}
  public static let empty = ToolPreview()
}

public struct PointerInfo: Sendable {
  public var world: Point
  public var screen: Point
  /// Screen-space movement since the last event, for drag handlers.
  public var dxScreen: Double
  public var dyScreen: Double
  /// Whether a modifier was held. Always false on a touchscreen.
  public var shiftKey: Bool
  /// Which buttons are held.
  ///
  /// The name survives the port on purpose. Every tool guards on
  /// `e.buttons !== 1` exactly as `tools/*.ts` does, so `WallTool.swift` still
  /// diffs against `wallTool.ts` line by line. iOS has no analogue, so it is
  /// synthesised: 1 from `touchesBegan` to `touchesEnded`, 0 after. Build these
  /// through `.down`/`.up` rather than writing the number at a call site.
  public var buttons: Int

  public static func down(world: Point, screen: Point,
                          dxScreen: Double = 0, dyScreen: Double = 0) -> PointerInfo {
    PointerInfo(world: world, screen: screen, dxScreen: dxScreen, dyScreen: dyScreen,
                shiftKey: false, buttons: 1)
  }

  public static func up(world: Point, screen: Point,
                        dxScreen: Double = 0, dyScreen: Double = 0) -> PointerInfo {
    PointerInfo(world: world, screen: screen, dxScreen: dxScreen, dyScreen: dyScreen,
                shiftKey: false, buttons: 0)
  }
}

/// What a tool is allowed to do to the world, kept narrow on purpose.
///
/// A struct of closures, as `app.ts:344` builds it. Fourteen members rather than
/// the web's twenty-two: the rest belong to tools outside v1, and each should
/// arrive with the tool that needs it -- the two selection members below did,
/// with the lasso that the goal tool grew. `selectPedestriansIn` has no
/// `extend:` parameter and there is no `selectPedestrianAt`: `PointerInfo`'s
/// own comment says `shiftKey` is always false on a touchscreen, so extend mode
/// has no gesture, and a tap already means "assign", so single-pedestrian
/// picking has none either -- lasso a small circle instead. Built once in a `lazy var` with
/// `[unowned self]` -- a computed property would reallocate twelve closures on
/// every pointer event, and a strong capture would be a retain cycle.
public struct ToolContext {
  public var addWall: ([Point], WallOptions?) -> Bool
  /// Adds one wall made of several polygons, as a border frame is.
  public var addWallShape: ([[Point]], WallOptions?) -> Bool
  /// Current settings, for tools that need sizes at preview time.
  public var settings: () -> SettingsSnapshot
  /// Legal positions in a block centred on `at`, for placement and preview.
  public var pedestrianBlock: (Point, Int?) -> [Point]
  /// Paints a block of bodies and answers the spots it filled.
  ///
  /// It does **not** checkpoint: a drag is one edit, so the tool takes one
  /// checkpoint on the press. The spots come back so the caller does not have
  /// to ask `pedestrianBlock` the same question twice in one event.
  public var addPedestrians: (Point) -> [Point]
  /// Takes an undo checkpoint, for a tool whose gesture is one edit made of
  /// many events.
  public var checkpoint: () -> Void
  /// Marks the wall under a point as a goal; false when there is no wall there.
  public var setGoalAt: (Point) -> Bool
  /// Turns the block under a point into a generator, or back into a plain
  /// block. False when there is no block there, so the tool can say so -- the
  /// same contract `setGoalAt` has, because it is the same kind of question.
  public var markGenerator: (Point) -> Bool
  /// Selects every pedestrian inside a lasso outline, replacing any current
  /// selection, and answers how many it caught. The count is the return value
  /// rather than a second query because "caught nobody" is the one case the
  /// tool has to say something about, and asking afterwards cannot distinguish
  /// it from a selection that was already empty.
  public var selectPedestriansIn: ([Point]) -> Int
  public var selectionCount: () -> Int
  public var clearSelection: () -> Void
  /// The nearest place a pedestrian could stand, for a point that may not be
  /// one. Answers the point itself wherever it is already clear.
  public var standablePoint: (Point) -> Point
  /// Put the toolbar back to no active tool, so a one-shot cannot repeat.
  public var deactivateTool: () -> Void
  /// Say something to the user, as the chip that shared maps and updates use.
  public var notify: (String) -> Void
  public var requestRender: () -> Void
  /// Colour of the wall under a point, if any -- used to tint the goal preview.
  public var colorAt: (Point) -> RGB?
  /// The wall under a point, by id -- what the generator previews. Beside
  /// `colorAt`, which asks the same question of the same wall.
  public var wallIdAt: (Point) -> Int?
  /// World units per screen point, so tolerances can be expressed in points.
  public var worldPerPixel: () -> Double
  /// How far the map is turned on screen, in radians. What squares a dragged
  /// box to the glass instead of to world space; see `orientedRectangle`.
  public var viewRotation: () -> Double
  /// Walky's walk from a to b, stored on the world and drawn until replaced.
  public var measure: (Point, Point) -> Void

  public init(
    addWall: @escaping ([Point], WallOptions?) -> Bool,
    addWallShape: @escaping ([[Point]], WallOptions?) -> Bool,
    settings: @escaping () -> SettingsSnapshot,
    pedestrianBlock: @escaping (Point, Int?) -> [Point],
    addPedestrians: @escaping (Point) -> [Point],
    checkpoint: @escaping () -> Void = {},
    setGoalAt: @escaping (Point) -> Bool,
    markGenerator: @escaping (Point) -> Bool,
    selectPedestriansIn: @escaping ([Point]) -> Int,
    selectionCount: @escaping () -> Int,
    clearSelection: @escaping () -> Void,
    standablePoint: @escaping (Point) -> Point,
    deactivateTool: @escaping () -> Void,
    notify: @escaping (String) -> Void,
    requestRender: @escaping () -> Void,
    colorAt: @escaping (Point) -> RGB?,
    // Defaulted, like `viewRotation`: a caller with no map to ask -- every
    // test fake that does not care -- means a point with no wall under it.
    wallIdAt: @escaping (Point) -> Int? = { _ in nil },
    worldPerPixel: @escaping () -> Double,
    // Defaulted alone among the seventeen: a caller with no camera to ask --
    // every test fake, today -- means a map nobody has turned, and that is the
    // behaviour every one of them was written against.
    viewRotation: @escaping () -> Double = { 0 },
    measure: @escaping (Point, Point) -> Void
  ) {
    self.addWall = addWall
    self.addWallShape = addWallShape
    self.settings = settings
    self.pedestrianBlock = pedestrianBlock
    self.addPedestrians = addPedestrians
    self.checkpoint = checkpoint
    self.setGoalAt = setGoalAt
    self.markGenerator = markGenerator
    self.selectPedestriansIn = selectPedestriansIn
    self.selectionCount = selectionCount
    self.clearSelection = clearSelection
    self.standablePoint = standablePoint
    self.deactivateTool = deactivateTool
    self.notify = notify
    self.requestRender = requestRender
    self.colorAt = colorAt
    self.wallIdAt = wallIdAt
    self.worldPerPixel = worldPerPixel
    self.viewRotation = viewRotation
    self.measure = measure
  }
}

/// A tool. A class, not an enum: every one holds mutable per-stroke state and
/// the world keeps one long-lived instance each, exactly as `app.ts` does.
@MainActor
public protocol Tool: AnyObject {
  var id: ToolId { get }
  func onPointerDown(_ e: PointerInfo, _ ctx: ToolContext)
  func onPointerMove(_ e: PointerInfo, _ ctx: ToolContext)
  func onPointerUp(_ e: PointerInfo, _ ctx: ToolContext)
  func onDoubleTap(_ e: PointerInfo, _ ctx: ToolContext)
  /// Abandon anything in progress, e.g. on a second finger or a tool switch.
  func cancel()
  /// The pointer has left the map, so anything drawn *under* it should go.
  ///
  /// Not `cancel()`, which throws away what has been committed: leaving the
  /// window with one corner of a rectangle already placed must not abandon the
  /// rectangle, only stop the other corner following a pointer that is no
  /// longer there. Nothing on iOS ever calls this -- see `ToolId.ghostsOnHover`.
  func pointerLeft()
  func preview() -> ToolPreview
}

extension Tool {
  /// Most tools hold nothing that a pointer leaving should clear.
  public func pointerLeft() {}
}

/// The port of TypeScript's optional methods.
public extension Tool {
  func onPointerDown(_: PointerInfo, _: ToolContext) {}
  func onPointerMove(_: PointerInfo, _: ToolContext) {}
  func onPointerUp(_: PointerInfo, _: ToolContext) {}
  func onDoubleTap(_: PointerInfo, _: ToolContext) {}
  func cancel() {}
}

/// Past this, a press-and-release counts as a drag rather than a tap.
///
/// **Deliberate divergence from the web app.** `rectangleTool.ts:42` and
/// `borderTool.ts:48` compare this constant -- documented as pixels -- against a
/// *world-space* distance, where `wallTool.ts:56` and `textTool.ts:36` correctly
/// multiply by `worldPerPixel()`. At zoom level 0 the two readings coincide,
/// which is why it has never shown on a desktop. On a phone, where people pinch
/// constantly, they diverge: zoomed out five notches a 6-unit drag is under 4pt
/// of finger travel, so every tap becomes a drag and two-tap mode is
/// unreachable. Both tools here multiply. The same one-line fix is filed
/// against the web app separately.
public let DRAG_THRESHOLD: Double = 6

@inline(__always)
func snap(_ p: Point) -> Point { Point(jsRound(p.x), jsRound(p.y)) }
