import Foundation

/// The map edits a tool can make. Ports the rest of `src/state/model.ts`.

public struct WallOptions {
  public var color: RGB?
  /// True only for a border frame; see `Wall.isBorder`.
  public var isBorder: Bool
  public init(color: RGB? = nil, isBorder: Bool = false) {
    self.color = color
    self.isBorder = isBorder
  }
}

/// Ids come from one counter, as `model.ts` does it. Not serialized and not
/// stable across launches -- which is exactly why the golden fixtures refer to
/// walls by index and never by id.
public enum WallIds {
  @MainActor private static var next = 1
  @MainActor public static func mint() -> Int {
    defer { next += 1 }
    return next
  }
}

@MainActor
public func makeWall(_ polygons: [[Point]], _ options: WallOptions = WallOptions()) -> Wall {
  Wall(id: WallIds.mint(), polygons: polygons,
       color: options.color ?? randomBrightColor(),
       isGoal: false, isBorder: options.isBorder)
}

/// The four bars of a border frame, overlapping at the corners.
///
/// Ports `BorderToolMouseListener.addBorderFrom`. Extending every bar past the
/// corner by the thickness is what seals the frame: bars that merely met at a
/// shared corner point could leave a diagonal gap for a pedestrian to slip
/// through, which is exactly the failure an enclosure must not have.
public func borderFrame(_ a: Point, _ b: Point, _ thickness: Double) -> [[Point]] {
  let t = jsMax(1, thickness)
  let left = jsMin(a.x, b.x), right = jsMax(a.x, b.x)
  let top = jsMin(a.y, b.y), bottom = jsMax(a.y, b.y)
  return [
    rectanglePolygon(Point(left - t, top - t), Point(right + t, top + t)),
    rectanglePolygon(Point(left - t, bottom - t), Point(right + t, bottom + t)),
    rectanglePolygon(Point(left - t, top - t), Point(left + t, bottom + t)),
    rectanglePolygon(Point(right - t, top - t), Point(right + t, bottom + t)),
  ]
}

/// Whether a frame would leave usable space inside.
///
/// Navigation pushes each bar out by the pedestrian radius, so the interior a
/// pedestrian's centre can occupy shrinks by thickness + radius on every side.
/// Below that the box is sealed solid, and drawing one would look like it
/// worked while being unusable.
public func borderFits(_ a: Point, _ b: Point, _ thickness: Double, _ radius: Double) -> Bool {
  let margin = 2 * (jsMax(1, thickness) + radius)
  return abs(b.x - a.x) > margin + 2 * radius
      && abs(b.y - a.y) > margin + 2 * radius
}

public func wallContains(_ wall: Wall, _ p: Point) -> Bool {
  wall.polygons.contains { pointInPolygon($0, p) }
}

public func wallOverlapsPolygon(_ wall: Wall, _ poly: [Point]) -> Bool {
  wall.polygons.contains { polygonsOverlap($0, poly) }
}

/// Whether two walls share any area or crossing edge.
public func wallsOverlap(_ a: Wall, _ b: Wall) -> Bool {
  a.polygons.contains { wallOverlapsPolygon(b, $0) }
}

// MARK: - Boxes on a turned map

/// A world point in the frame the screen's own axes run along.
///
/// A turned map has pulled the two apart: `Viewport.worldToScreen` spins world
/// space by `rotation` on its way to the glass, so "along the top of the
/// screen" stops being "along world +x". These two undo and redo exactly that
/// spin -- about the world origin rather than about the camera, which is all a
/// shape's *orientation* depends on and keeps both functions pure.
public func toViewFrame(_ p: Point, _ rotation: Double) -> Point {
  let (c, s) = (jsCos(rotation), jsSin(rotation))
  return Point(p.x * c - p.y * s, p.x * s + p.y * c)
}

/// The inverse of `toViewFrame`.
public func fromViewFrame(_ p: Point, _ rotation: Double) -> Point {
  let (c, s) = (jsCos(rotation), jsSin(rotation))
  return Point(p.x * c + p.y * s, p.y * c - p.x * s)
}

/// `rectanglePolygon`, but square to the screen rather than to the world.
///
/// Dragging a box out on a map that has been twisted thirty degrees used to
/// give a box thirty degrees off the drag: the corners were world-axis-aligned,
/// so the shape under the finger was a parallelogram of empty space and the
/// wall landed skewed. The box you draw is the box you see, so the drag is
/// squared up in the frame the screen is in and the corners are carried back
/// into world space afterwards -- which is what *rotates the wall itself*, and
/// is the whole of the difference. On a straight map this is the original
/// function, byte for byte, so every drawn map and every fixture is untouched.
public func orientedRectangle(_ a: Point, _ b: Point, _ rotation: Double) -> [Point] {
  guard rotation != 0 else { return rectanglePolygon(a, b) }
  return rectanglePolygon(toViewFrame(a, rotation), toViewFrame(b, rotation))
    .map { fromViewFrame($0, rotation) }
}

/// `borderFrame`, squared to the screen the way `orientedRectangle` is. The
/// four bars are built in the view frame -- overlapping corners and all, so the
/// enclosure is sealed by the same arithmetic that seals a straight one -- and
/// only then carried back into world space.
public func borderFrame(_ a: Point, _ b: Point, _ thickness: Double,
                        _ rotation: Double) -> [[Point]] {
  guard rotation != 0 else { return borderFrame(a, b, thickness) }
  return borderFrame(toViewFrame(a, rotation), toViewFrame(b, rotation), thickness)
    .map { $0.map { fromViewFrame($0, rotation) } }
}

/// Whether a turned frame would leave usable space inside. Measured in the view
/// frame for the reason `borderFrame` builds there: the width and height being
/// checked are the ones the drag actually has, not the bounding box's.
public func borderFits(_ a: Point, _ b: Point, _ thickness: Double, _ radius: Double,
                       _ rotation: Double) -> Bool {
  guard rotation != 0 else { return borderFits(a, b, thickness, radius) }
  return borderFits(toViewFrame(a, rotation), toViewFrame(b, rotation), thickness, radius)
}
