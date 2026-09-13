import Foundation
import WalkyGeo
import WalkySim

/// Putting a converted floor plan on the map.
///
/// Lifted out of `RoomScanner` when the scene generator became a second caller.
/// It is one routine rather than two because of what it encodes: **the order is
/// load-bearing.** `setGoalAt` is what aims every generator, and a generator
/// with no goal emits nobody -- so the slabs go down, then the doors, then the
/// aim. Two copies of that would agree until somebody edited one, and the
/// symptom of them disagreeing is a map that looks perfect and stands still.
///
/// In `WalkyCore` rather than the app target for the usual reason: this is
/// logic, so it belongs where `swift test` can reach it.
public struct RoomPlacement: Sendable {
  public var walls: [[[Point]]]
  public var furniture: [[[Point]]]
  /// Filled and marked as the goal: reaching this doorway is leaving.
  public var exits: [Doorway]
  /// Filled and turned into a door people come out of.
  public var entrances: [Doorway]
  /// A block of people to paint, and how many bodies across.
  public var crowdAt: Point?
  public var crowdCells: Int?

  public init(walls: [[[Point]]], furniture: [[[Point]]] = [],
              exits: [Doorway] = [], entrances: [Doorway] = [],
              crowdAt: Point? = nil, crowdCells: Int? = nil) {
    self.walls = walls
    self.furniture = furniture
    self.exits = exits
    self.entrances = entrances
    self.crowdAt = crowdAt
    self.crowdCells = crowdCells
  }
}

/// The colour furniture and obstacles wear: duller than a wall, so the room
/// reads as a room with things in it rather than as more building.
public let OBSTACLE_COLOUR: RGB = (120, 120, 130)

@MainActor
public extension WalkyWorld {
  /// Replace the map with this plan, and wait until the crowd can route on it.
  ///
  /// Returns the point that became the goal, or nil when the plan had no exit
  /// -- which is a map worth showing but not one anybody walks across.
  ///
  /// `onRouting` fires just before the visibility rebuild: the slow,
  /// superquadratic step both importers already put a label on. Without it a
  /// caller can only say "routing" once the routing has finished, which is a
  /// spinner that appears exactly when it is no longer needed.
  @discardableResult
  func place(_ plan: RoomPlacement, onRouting: (() -> Void)? = nil) async -> Point? {
    clearAll()
    // No anchor. A scanned room is not a place on the earth and a described one
    // is not either, and the nil is what makes `measure` report at 1:1.
    addWalls(plan.walls)
    if !plan.furniture.isEmpty {
      // Its own edit, so undoing the furniture without losing the room is
      // possible -- which is the thing somebody actually wants.
      addWalls(plan.furniture, WallOptions(color: OBSTACLE_COLOUR))
    }

    var goal: Point?
    for doorway in plan.exits where addWallShape([doorway.slab],
                                                 WallOptions(color: (0, 200, 120))) {
      goal = doorway.at
    }
    for doorway in plan.entrances {
      // **The doorway is the generator.** The slab filling the gap is what
      // people come out of, and which side they come out of is answered by
      // where the goal is. Filling the gap is necessary rather than tidy: left
      // open, the crowd walks back out of the door it came in by whenever that
      // is the shorter way round to the exit.
      addGeneratorShape([doorway.slab])
    }
    if let at = plan.crowdAt {
      // **Before** the goal, not after. `setGoalAt` is what retargets everybody
      // already on the map, so a crowd painted after it has never been told
      // where to go: it stands in the grid it was painted in, wearing random
      // colours instead of the goal's, while the doors emit people who walk
      // past it. That is what the first generated museum did.
      addPedestrians(at, cells: plan.crowdCells)
    }

    if let goal { setGoalAt(goal) }

    frameImport()
    onRouting?()
    await navReady()
    return goal
  }
}
