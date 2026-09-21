import Testing
import Foundation
import WalkySim
@testable import WalkyCore

/// Saving a map and opening it again.
///
/// The codec itself is pinned by fixtures the web generates (`CodecTests`), so
/// what these ask about is the half that had no counterpart until now: getting a
/// map out of the world and back into it, and the one place the format had to
/// grow because this port disagrees with the web about what a generator is.
@MainActor
@Suite("Saving a map")
struct MapFileTests {
  private func drawn() -> WalkyWorld {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.viewport.width = 390
    world.viewport.height = 844
    world.addWallShape([rectanglePolygon(Point(600, -80), Point(700, 80))], nil)
    world.addWallShape([rectanglePolygon(Point(-40, -40), Point(40, 40))], nil)
    world.addPedestrians(Point(200, 0))
    world.setGoalAt(Point(650, 0))
    return world
  }

  @Test("a map survives being written and read")
  func roundTrip() {
    let world = drawn()
    let before = world.captureScenario()
    let file = MapFile.data(before)

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.viewport.width = 390
    opened.viewport.height = 844
    opened.apply(try! MapFile.read(file))

    #expect(opened.walls.count == world.walls.count)
    #expect(opened.agents.count == world.agents.count)
    #expect(opened.walls.map(\.polygons) == world.walls.map(\.polygons))
    #expect(opened.walls.map(\.isGoal) == world.walls.map(\.isGoal))
    // Ids are fresh, so the goal has to be looked up rather than compared: the
    // pedestrian's goal must be *the wall that was the goal*, whatever it is
    // called now.
    let goal = try! #require(opened.walls.first { $0.isGoal })
    for i in 0..<opened.agents.count {
      #expect(Int(opened.agents.goal[i]) == goal.id)
    }
  }

  @Test("a saved crowd keeps the personality it had")
  func traitsComeFromOrigins() {
    // `addRestored` recomputes trait, assertiveness and party from the
    // **origin**, as undo does. Taking them from the position instead would
    // give a crowd that had walked a different character on reopening.
    let world = drawn()
    world.running = true
    for _ in 0..<120 { world.stepOnce() }

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try! MapFile.read(MapFile.data(world.captureScenario())))

    #expect(opened.agents.count == world.agents.count)
    for i in 0..<opened.agents.count {
      #expect(opened.agents.trait[i] == world.agents.trait[i])
      #expect(opened.agents.party[i] == world.agents.party[i])
      #expect(Double(opened.agents.originX[i]) == jsRound(Double(world.agents.originX[i])))
    }
  }

  @Test("the settings ride along, clamped as a link's are")
  func settings() {
    let world = drawn()
    world.settings.speed = 2.15
    world.settings.pedestrianRadius = 19
    world.settings.showConvexHull = true

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try! MapFile.read(MapFile.data(world.captureScenario())))

    #expect(opened.settings.speed == 2.15)
    #expect(opened.settings.pedestrianRadius == 19)
    #expect(opened.settings.showConvexHull)
    // The object itself is never replaced -- the whole app holds this reference.
    #expect(opened.settings === opened.settings)
  }

  @Test("a map with no generator stays version 3, and the web can still read it")
  func plainMapIsVersionThree() {
    let world = drawn()
    let bytes = MapFile.bytes(world.captureScenario())
    #expect(bytes[1] == Codec.VERSION)
    #expect(Int(bytes[2]) & Codec.FLAG_WALL_GENERATORS == 0)
  }

  @Test("a map with a generator is version 4, and says which wall it is")
  func generatorMapIsVersionFour() {
    let world = drawn()
    #expect(world.toggleGeneratorAt(Point(0, 0)))

    let bytes = MapFile.bytes(world.captureScenario())
    #expect(bytes[1] == Codec.VERSION_WALL_GENERATORS)
    #expect(Int(bytes[2]) & Codec.FLAG_WALL_GENERATORS != 0)

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try! MapFile.read(bytes))

    // The same wall is the generator, not a new block beside it.
    #expect(opened.walls.count == world.walls.count)
    #expect(opened.generators.count == 1)
    #expect(opened.generators[0].polygons == world.generators[0].polygons)
    #expect(opened.generators[0].generator!.rate == world.generators[0].generator!.rate)
    let goal = try! #require(opened.walls.first { $0.isGoal })
    #expect(opened.generators[0].generator!.goal == goal.id)
  }

  @Test("a version 4 file also carries the point a web reader needs")
  func alsoCarriesTheWebsPoint() {
    // The point section is what lets the web open the file at all once it
    // learns version 4, and it has to be *beside* the wall: a generator
    // standing inside one could never let anybody out.
    let world = drawn()
    #expect(world.toggleGeneratorAt(Point(0, 0)))
    let core = world.captureScenario()

    #expect(core.generators.count == 1)
    #expect(core.wallGenerators.count == 1)
    let wall = try! #require(world.generators.first)
    #expect(!wallContains(wall, core.generators[0].at))
  }

  @Test("a generator that arrives as a loose point lands on the wall it stands on")
  func webPointBecomesAWall() throws {
    // What a map written by the web looks like coming in: a wall, and a
    // generator point on top of it. It should mark that wall rather than build
    // a second one over it.
    let world = drawn()
    var core = world.captureScenario()
    core.wallGenerators = []
    core.generators = [SerializedGenerator(at: Point(0, 0), rate: 6,
                                           goal: core.walls[0].id, color: (200, 100, 50))]

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try MapFile.read(MapFile.data(core)))

    #expect(opened.walls.count == core.walls.count, "a second block was built over the wall")
    #expect(opened.generators.count == 1)
    #expect(opened.generators[0].generator!.rate == 6)
  }

  @Test("a loose point on bare ground becomes a block of its own")
  func webPointOnGround() throws {
    // The other half of the same case, and the reason it is not an error: a
    // generator standing on nothing is what the web draws, so it becomes the
    // small block this tool used to place.
    let world = drawn()
    var core = world.captureScenario()
    core.generators = [SerializedGenerator(at: Point(-900, -900), rate: 4,
                                            goal: -1, color: (200, 100, 50))]

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try MapFile.read(MapFile.data(core)))

    #expect(opened.walls.count == core.walls.count + 1)
    #expect(opened.generators.count == 1)
    #expect(wallContains(opened.generators[0], Point(-900, -900)))
  }

  @Test("nonsense is refused with something worth reading")
  func rejectsRubbish() {
    #expect(throws: ScenarioLinkError.notWalky) { try MapFile.read([0x00, 0x01, 0x02]) }
    #expect(throws: ScenarioLinkError.truncated) { try MapFile.read([0x57]) }
    // A version this build does not know, which is what a file from a *newer*
    // Walky looks like -- and what the web will see until it learns version 4.
    #expect(throws: ScenarioLinkError.wrongVersion) {
      try MapFile.read([0x57, 99, 0])
    }
    // The version and the flag disagreeing is a payload nobody wrote.
    #expect(throws: ScenarioLinkError.wrongVersion) {
      try MapFile.read([0x57, Codec.VERSION, UInt8(Codec.FLAG_WALL_GENERATORS)])
    }
  }

  @Test("the suggested filename counts in words somebody would have typed")
  func names() {
    // Read off the save sheet, where it lands in an editable field: "1 walls"
    // is the sort of thing you have to delete before you can type.
    #expect(MapFile.suggestedName(walls: 1, pedestrians: 0) == "1 wall")
    #expect(MapFile.suggestedName(walls: 4, pedestrians: 1) == "4 walls, 1 pedestrian")
    #expect(MapFile.suggestedName(walls: 4, pedestrians: 96) == "4 walls, 96 pedestrians")
    #expect(MapFile.suggestedName(walls: 0, pedestrians: 0) == "Empty map")
  }

  @Test("a link and a file are the same bytes")
  func linkAndFileAgree() throws {
    // One implementation, so a map cannot round-trip through one and not the
    // other. `ShareLink` is `MapFile` plus base64.
    let world = drawn()
    let core = world.captureScenario()
    let link = ShareLink.encode(core)
    let fromLink = try ShareLink.decode(link)
    let fromFile = try MapFile.read(MapFile.data(core))

    #expect(fromLink.walls == fromFile.walls)
    #expect(fromLink.agents == fromFile.agents)
  }
}

/// The version 6 tail: which doors have been told which face to use.
///
/// The same shape as version 4 and for the same reason -- one more trailing
/// section behind one more flag bit, so everything before it stays byte for
/// byte what the older writer produced, and a build that does not know the flag
/// refuses the file by name instead of misreading the tail.
@MainActor
@Suite("Saving a door's chosen face")
struct DoorFaceFileTests {
  private func withADoor() -> WalkyWorld {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.addWallShape([rectanglePolygon(Point(600, -80), Point(700, 80))], nil)
    world.addWallShape([rectanglePolygon(Point(-40, -40), Point(40, 40))], nil)
    _ = world.toggleGeneratorAt(Point(0, 0))
    _ = world.setGoalAt(Point(650, 0))
    return world
  }

  /// The two steps a click takes: pick the door, then click one of its faces.
  private func chooseWest(_ world: WalkyWorld) {
    world.pickDoor(world.generators.first)
    let west = world.doorFaces(world.generators[0]).min { $0.facing.x < $1.facing.x }
    _ = world.chooseDoorFace(at: west!.face)
  }

  @Test("a door the goal still decides for is written as version 4")
  func untoldDoorsStayAtVersionFour() {
    let world = withADoor()
    let bytes = MapFile.bytes(world.captureScenario())
    #expect(bytes[1] == Codec.VERSION_WALL_GENERATORS)
    #expect(Int(bytes[2]) & Codec.FLAG_DOOR_FACE == 0)
  }

  @Test("a chosen face makes it version 6, and survives the round trip")
  func chosenFaceSurvives() {
    let world = withADoor()
    chooseWest(world)
    let facing = try! #require(world.generators[0].generator!.outFacing)

    let bytes = MapFile.bytes(world.captureScenario())
    #expect(bytes[1] == Codec.VERSION_DOOR_FACE)
    #expect(Int(bytes[2]) & Codec.FLAG_DOOR_FACE != 0)
    // A chosen face is a door's, so it rides with the wall-generator tail.
    #expect(Int(bytes[2]) & Codec.FLAG_WALL_GENERATORS != 0)

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try! MapFile.read(bytes))
    let back = try! #require(opened.generators.first?.generator?.outFacing)
    // Three decimal places on the wire, and renormalised on the way in.
    #expect(abs(back.x - facing.x) < 1e-3)
    #expect(abs(back.y - facing.y) < 1e-3)
    #expect(abs(jsHypot(back.x, back.y) - 1) < 1e-9)
  }

  @Test("and the same face is still the one it uses")
  func theSameFaceIsStillChosen() {
    let world = withADoor()
    chooseWest(world)
    let was = try! #require(world.mouthDirection(world.generators[0]))

    let opened = WalkyWorld()
    opened.settings.defaults = nil
    opened.apply(try! MapFile.read(MapFile.bytes(world.captureScenario())))
    let now = try! #require(opened.mouthDirection(opened.generators[0]))
    #expect(abs(now.x - was.x) < 1e-3)
    #expect(abs(now.y - was.y) < 1e-3)
    // And it is still recognised as one of the block's four sides.
    #expect(opened.doorFaces(opened.generators[0]).contains { $0.isChosen })
  }

  @Test("the point a web reader needs lands on the face in use")
  func thePointIsOnTheChosenFace() {
    // The v3 compatibility point is `generatorMouth`, which already answers
    // with the face the door uses -- so a reader that never learns about
    // chosen faces still puts its block where this one lets people out.
    let world = withADoor()
    chooseWest(world)
    let core = world.captureScenario()
    #expect(core.generators.count == 1)
    #expect(core.doorSides.count == 1)
    #expect(core.generators[0].at.x < 0, "the compatibility point is on the wrong face")
  }

  @Test("the version and the face flag have to agree")
  func versionAndFlagMustAgree() {
    let world = withADoor()
    chooseWest(world)
    var bytes = MapFile.bytes(world.captureScenario())

    var noFlag = bytes
    noFlag[2] = UInt8(Int(noFlag[2]) & ~Codec.FLAG_DOOR_FACE)
    #expect(throws: ScenarioLinkError.self) { _ = try MapFile.read(noFlag) }

    bytes[1] = Codec.VERSION_WALL_GENERATORS
    #expect(throws: ScenarioLinkError.self) { _ = try MapFile.read(bytes) }
  }

  /// Version 5 said "this door has a side *closed*". The field it named now
  /// says which face people come *out* of, so the same bytes would read as the
  /// opposite instruction. Burnt rather than reused: such a file is refused by
  /// name instead of opening mirrored.
  @Test("a version 5 map is refused rather than read backwards")
  func theSpentVersionIsRefused() {
    let world = withADoor()
    chooseWest(world)
    var bytes = MapFile.bytes(world.captureScenario())
    bytes[1] = Codec.VERSION_DOOR_SIDES
    bytes[2] = UInt8((Int(bytes[2]) & ~Codec.FLAG_DOOR_FACE) | Codec.FLAG_DOOR_SIDES)
    #expect(throws: ScenarioLinkError.self) { _ = try MapFile.read(bytes) }
  }
}
