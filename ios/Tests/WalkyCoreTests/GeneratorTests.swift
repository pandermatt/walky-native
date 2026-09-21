import Testing
import Foundation
@testable import WalkyCore
@testable import WalkySim

/// Doors that let people out.
///
/// The arithmetic behind them was ported with the rest of the simulation and
/// sat unused: `Arrivals.swift` turns a door's position and its beat into a
/// clump size and a gap, hashed so the same door replays the same demand.
///
/// A generator **is a wall** here, unlike in the web app: any block can be
/// marked as one, exactly as any block can be marked a goal, it blocks the
/// crowd like the wall it is, and people come out of it on the side its goal is
/// on rather than standing in it. So most of what these tests ask about is a
/// wall with a `Generator` on it, and the one genuinely new question -- which
/// side do people appear on -- is `emitsOnTheGoalSide` below.
@MainActor
@Suite("Generators")
struct GeneratorTests {
  private func fresh() -> WalkyWorld {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.addWallShape([rectanglePolygon(Point(600, -80), Point(700, 80))], nil)
    return world
  }

  /// A block, marked. Two steps now rather than one, and that is the feature:
  /// there is no generator-shaped thing to place, only blocks you already drew
  /// and a tap that says what one of them is.
  @discardableResult
  private func mark(_ world: WalkyWorld, at: Point, half: Double = 39) -> Bool {
    world.addWallShape([rectanglePolygon(Point(at.x - half, at.y - half),
                                         Point(at.x + half, at.y + half))], nil)
    return world.toggleGeneratorAt(at)
  }

  @Test("a door with no goal lets nobody out")
  func unpinnedIsIdle() {
    // It has nowhere to send anybody, and since its people only leave the map
    // by arriving, what it would make is a pile that never goes away.
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    for _ in 0..<600 { world.stepOnce() }
    #expect(world.agents.count == 0)
  }

  @Test("a door pinned to a goal fills the map")
  func pinnedEmits() async {
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.setGoalAt(Point(650, 0)))
    await world.navReady()

    for _ in 0..<600 { world.stepOnce() }
    #expect(world.agents.count > 0, "the door never opened")
    // And they are going somewhere: everybody it made wears the goal.
    let goalId = try! #require(world.walls.first { $0.isGoal }).id
    for i in 0..<world.agents.count {
      #expect(Int(world.agents.goal[i]) == goalId)
    }
  }

  /// The reason the goal tool aims at doors at all: pinning a pedestrian sends
  /// one person, pinning a door sends everybody it will ever let out.
  @Test("marking a goal aims the doors as well as the crowd")
  func goalAimsDoors() {
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.generators[0].generator!.goal == -1)
    #expect(world.setGoalAt(Point(650, 0)))
    #expect(world.generators[0].generator!.goal == world.walls[0].id)  // the goal wall was placed first
    #expect(world.generators[0].color == world.walls[0].color)
  }

  /// A goal wall is kept marked only while somebody is heading there. A door
  /// counts as somebody, or its goal would be un-marked the moment the last of
  /// its people arrived and the door would be left aiming at nothing.
  @Test("a door keeps its goal marked with nobody on the map")
  func doorHoldsItsGoal() {
    // Two doors, so the second goal can be given to one of them and leave the
    // other still wanting the first. With nothing selected a goal re-aims
    // *everything* -- doors included -- which is why this picks one.
    let world = fresh()
    world.addWallShape([rectanglePolygon(Point(-700, -80), Point(-600, 80))], nil)
    #expect(mark(world, at: Point(0, 0)))
    #expect(mark(world, at: Point(300, 0)))
    #expect(world.setGoalAt(Point(650, 0)))
    #expect(world.agents.count == 0)

    // Aim the second door at the other wall. Nobody is on the map at all, so
    // the first wall stays a goal only because a door still wants it.
    #expect(world.selectPedestriansIn(rectanglePolygon(Point(200, -100), Point(400, 100))) == 1)
    #expect(world.setGoalAt(Point(-650, 0)))
    #expect(world.walls[1].isGoal)
    #expect(world.walls[0].isGoal, "the door's goal was pruned out from under it")
  }

  @Test("a tap on bare ground marks nothing")
  func missesEmptyGround() {
    // The goal tool's own answer to the same gesture, and the reason the tool
    // stays armed after one: there is nothing there to be a generator.
    let world = fresh()
    #expect(!world.toggleGeneratorAt(Point(-500, -500)))
    #expect(world.generators.isEmpty)
  }

  @Test("tapping a generator again turns it back into a plain block")
  func toggles() {
    // Without this, undo is the only way out of a mistap -- and the tap that
    // made it is the same tap that should take it back.
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.generators.count == 1)
    #expect(world.toggleGeneratorAt(Point(0, 0)))
    #expect(world.generators.isEmpty)
    #expect(world.walls.count == 2, "the block itself should still be there")
  }

  @Test("marking a block on a map that already has a goal aims it there")
  func inheritsTheGoal() {
    // One tap is enough on a map with a goal on it. Otherwise the first thing
    // every new generator would need is a trip to the goal tool.
    let world = fresh()
    #expect(world.setGoalAt(Point(650, 0)))
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.generators[0].generator!.goal == world.walls[0].id)
  }

  /// The one thing a generator being a wall makes somebody decide: nobody can
  /// stand *in* a wall, so which side do they come out of?
  @Test("people come out on the side the goal is on")
  func emitsOnTheGoalSide() async {
    let world = fresh()                       // the goal wall is east, at x 600
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.setGoalAt(Point(650, 0)))
    await world.navReady()

    for _ in 0..<120 { world.stepOnce() }
    #expect(world.agents.count > 0, "the door never opened")
    // Every one of them appeared east of the door's own middle, which is the
    // way its goal lies -- and none inside it.
    let source = world.generators[0]
    for i in 0..<world.agents.count {
      #expect(Double(world.agents.x[i]) > 0, "somebody came out of the far side")
      #expect(!wallContains(source, Point(Double(world.agents.x[i]),
                                        Double(world.agents.y[i]))),
              "somebody is standing inside the generator")
    }
  }

  @Test("a generator blocks the crowd, because it is a wall")
  func doorsBlock() async {
    // The whole reason for the rewrite: a generator is part of the map rather
    // than a decal on it. Asked directly -- can anybody be in it, and does
    // navigation know about it -- rather than by walking somebody past it,
    // which would be a test about congestion wearing a test about geometry.
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    await world.navReady()
    let door = world.generators[0]

    // The brush cannot put anybody inside it, at any size.
    #expect(world.pedestrianBlock(Point(0, 0), 1).isEmpty)
    #expect(world.pedestrianBlock(Point(0, 0), 3).isEmpty)
    // And the visibility graph carries it, so the crowd routes around it and
    // `Behaviour.insideAnyWall` refuses to step into it.
    #expect(world.nav.obstacles.contains { $0.wallId == door.id })
  }

  /// Reset means the same demand again, not merely an empty queue: `Arrivals`
  /// is a hash of the beat, so replaying needs the beat put back.
  @Test("reset puts every door back to the top of its schedule")
  func resetRewindsSchedules() async {
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.setGoalAt(Point(650, 0)))
    await world.navReady()
    for _ in 0..<300 { world.stepOnce() }
    #expect(world.generators[0].generator!.beat > 0)

    world.resetPedestrians()
    #expect(world.generators[0].generator!.beat == 0)
    #expect(world.generators[0].generator!.owed == 0)
    #expect(world.generators[0].generator!.wait == 0)
  }

  @Test("the same door replays the same demand")
  func demandIsDeterministic() async {
    func run() async -> Int {
      let world = fresh()
      mark(world, at: Point(0, 0))
      _ = world.setGoalAt(Point(650, 0))
      await world.navReady()
      for _ in 0..<400 { world.stepOnce() }
      return world.agents.count
    }
    let a = await run()
    let b = await run()
    #expect(a == b)
    #expect(a > 0)
  }

  @Test("a lasso catches a door, and a goal then applies to it alone")
  func lassoPicksDoors() {
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(mark(world, at: Point(300, 0)))

    #expect(world.selectPedestriansIn(rectanglePolygon(Point(-100, -100), Point(100, 100))) == 1)
    #expect(world.generators[0].selected)
    #expect(!world.generators[1].selected)

    #expect(world.setGoalAt(Point(650, 0)))
    #expect(world.generators[0].generator!.goal == world.walls[0].id)
    #expect(world.generators[1].generator!.goal == -1, "the goal reached a door nobody picked")
  }

  @Test("undo takes a door back with it")
  func undoRemovesDoors() {
    let world = fresh()
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.generators.count == 1)
    world.undo()
    #expect(world.generators.isEmpty)
  }

  /// The queue is what makes a burst look like a burst: a clump lands whole and
  /// leaves at whatever rate the doorway can pass. Without a ceiling it would
  /// grow for as long as a jam lasts and then empty into the first gap.
  @Test("the queue behind a blocked door is capped")
  func queueIsCapped() async {
    let world = fresh()
    world.settings.generatorRate = 20
    #expect(mark(world, at: Point(0, 0)))
    #expect(world.setGoalAt(Point(650, 0)))
    await world.navReady()
    for _ in 0..<600 { world.stepOnce() }
    #expect(world.generators[0].generator!.owed <= QUEUE_MAX)
  }
}


/// Telling a door which way out.
///
/// A door is a wall, so nobody ever walks *through* one: the only way a crowd
/// reaches the wrong side of a doorway is by **appearing** there. The goal's
/// own side is the default answer and is arithmetic; what it cannot know is
/// which way round the block the crowd is wanted, so a door can be told
/// outright, and that one direction is the only thing stored.
@MainActor
@Suite("A door told which face to use")
struct DoorFaceTests {
  private func fresh() -> WalkyWorld {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.addWallShape([rectanglePolygon(Point(600, -80), Point(700, 80))], nil)
    return world
  }

  /// A door at the origin, aimed at the goal wall in the east.
  private func aimed(_ world: WalkyWorld, half: Double = 39) {
    world.addWallShape([rectanglePolygon(Point(-half, -half), Point(half, half))], nil)
    _ = world.toggleGeneratorAt(Point(0, 0))
    _ = world.setGoalAt(Point(650, 0))
  }

  /// The face whose normal points that way.
  private func face(_ world: WalkyWorld, _ facing: Point) -> WalkyWorld.DoorStep {
    let faces = world.doorFaces(world.generators[0])
    return faces.max { a, b in
      (a.facing.x * facing.x + a.facing.y * facing.y)
        < (b.facing.x * facing.x + b.facing.y * facing.y)
    }!
  }

  /// Choosing one, the way a click does it: pick the door, then click the face.
  @discardableResult
  private func choose(_ world: WalkyWorld, _ facing: Point) -> Bool {
    world.pickDoor(world.generators.first)
    return world.chooseDoorFace(at: face(world, facing).face)
  }

  // MARK: - The block's four sides

  @Test("a block offers its four sides, at its own edges")
  func fourSides() {
    let world = fresh()
    aimed(world, half: 39)
    let faces = world.doorFaces(world.generators[0])
    #expect(faces.count == 4)

    // A 78-unit square at the origin: each face sits 39 out and reaches 39
    // either way across.
    for step in faces {
      #expect(abs(jsHypot(step.face.x, step.face.y) - 39) < 1e-9)
      #expect(abs(step.half - 39) < 1e-9)
    }
    // And the four point four different ways.
    let normals = Set(faces.map { "\(jsRound($0.facing.x)),\(jsRound($0.facing.y))" })
    #expect(normals.count == 4)
  }

  @Test("a block drawn on a turned map gets its own axes, not the world's")
  func turnedBlockKeepsItsAxes() {
    let world = fresh()
    // A rectangle whose sides run at 30 degrees.
    let angle = 30.0 * Double.pi / 180
    let (c, s) = (jsCos(angle), jsSin(angle))
    let corners = [Point(-60, -30), Point(60, -30), Point(60, 30), Point(-60, 30)]
      .map { Point($0.x * c - $0.y * s, $0.x * s + $0.y * c) }
    world.addWallShape([corners], nil)
    _ = world.toggleGeneratorAt(Point(0, 0))

    let faces = world.doorFaces(world.generators[0])
    #expect(faces.count == 4)
    // The long side runs at 30 degrees, so a face normal is perpendicular to
    // it -- at 120 -- and not along any world axis.
    let along = faces.contains { abs($0.facing.x - c) < 1e-6 && abs($0.facing.y - s) < 1e-6 }
    #expect(along, "the faces should follow the block, not the map")
  }

  @Test("a block with no area has no sides to offer")
  func degenerateBlockHasNone() {
    let world = fresh()
    // Three points on one line: the hull collapses to two.
    world.addWallShape([[Point(0, 0), Point(40, 0), Point(80, 0)]], nil)
    _ = world.toggleGeneratorAt(Point(40, 0))
    guard let door = world.generators.first else { return }
    #expect(world.doorFaces(door).isEmpty)
  }

  @Test("the faces are there before the door is aimed anywhere")
  func facesWithoutAGoal() {
    let world = fresh()
    world.addWallShape([rectanglePolygon(Point(-39, -39), Point(39, 39))], nil)
    _ = world.toggleGeneratorAt(Point(0, 0))
    // Which way out is a fact about the block; the goal only decides when
    // nobody has said.
    #expect(world.doorFaces(world.generators[0]).count == 4)
  }

  // MARK: - What the crowd does about it

  @Test("choosing a face sends them out of it")
  func chosenFaceIsWhereTheyAppear() async {
    let world = fresh()
    aimed(world)
    await world.navReady()
    // The goal is east, so east is where they would appear by default.
    #expect(try! #require(world.mouthDirection(world.generators[0])).x > 0.9)

    #expect(choose(world, Point(-1, 0)))
    for _ in 0..<120 { world.stepOnce() }

    #expect(world.agents.count > 0, "the door never opened")
    // Where each of them *appeared*: by 120 ticks the first are walking east
    // again, towards the goal.
    for i in 0..<world.agents.count {
      #expect(Double(world.agents.originX[i]) < 0, "somebody used another face")
    }
  }

  /// The anti-fallback test, and the most valuable one here.
  ///
  /// A door told which way out must not quietly use another face when that one
  /// is full: `pedestrianBlock` comes back empty whenever the doorstep is
  /// merely *occupied*, which for a busy door is the normal state, so a
  /// fallback would fire under exactly the congestion the choice exists to
  /// prevent. The queue waits instead.
  @Test("a chosen face that is full queues rather than using another")
  func fullFaceQueues() async {
    let world = fresh()
    aimed(world)
    choose(world, Point(-1, 0))
    // And now the west doorstep is built over.
    world.addWallShape([rectanglePolygon(Point(-220, -220), Point(-40, 220))], nil)
    await world.navReady()

    for _ in 0..<600 { world.stepOnce() }
    #expect(world.agents.count == 0, "somebody came out of a face nobody chose")
    #expect(world.generators[0].generator!.owed > 0, "the queue should be backing up")
  }

  /// The regression test against `middle`/`burstAt` ever being reached by
  /// geometry: a face built out of walls would move the door's middle, and the
  /// door's middle is what its whole arrival schedule is hashed on.
  @Test("choosing a face does not change the door's schedule")
  func demandIsUntouched() async {
    func run(chosen: Bool) async -> (beat: Double, made: Int) {
      let world = fresh()
      aimed(world)
      await world.navReady()
      if chosen { choose(world, Point(-1, 0)) }
      for _ in 0..<400 { world.stepOnce() }
      return (world.generators[0].generator!.beat, world.agents.count)
    }
    let derived = await run(chosen: false)
    let told = await run(chosen: true)
    #expect(derived.beat == told.beat)
    #expect(derived.made > 0 && told.made > 0)
  }

  // MARK: - The interaction

  @Test("clicking the face it already uses gives it back to the goal")
  func clickingTheChosenFaceClearsIt() {
    let world = fresh()
    aimed(world)
    #expect(choose(world, Point(-1, 0)))
    #expect(world.generators[0].generator!.outFacing != nil)

    #expect(choose(world, Point(-1, 0)))
    #expect(world.generators[0].generator!.outFacing == nil)
  }

  @Test("choosing another face moves the crowd to it")
  func choosingAnotherMovesIt() {
    let world = fresh()
    aimed(world)
    choose(world, Point(-1, 0))
    choose(world, Point(0, 1))
    let out = try! #require(world.generators[0].generator!.outFacing)
    #expect(out.y > 0.9)
  }

  @Test("nothing is offered until the door has been clicked")
  func nothingIsOfferedUntilPicked() {
    let world = fresh()
    aimed(world)
    let west = face(world, Point(-1, 0))
    #expect(world.doorFace(at: west.face) == nil)
    #expect(!world.chooseDoorFace(at: west.face))

    world.pickDoor(world.generators.first)
    #expect(world.doorFace(at: west.face) != nil)
    // Arming a tool takes the offer away: the click is the tool's.
    world.setTool(.wall)
    #expect(world.pickedDoor == nil)
  }

  /// The face is a control, so its reach is sized on the glass: a target that
  /// shrank with the zoom would be unclickable on the floor plan this is for.
  @Test("a face is clicked where it is drawn, at any zoom")
  func faceIsScreenSized() {
    let world = fresh()
    aimed(world)
    world.pickDoor(world.generators.first)
    let east = face(world, Point(1, 0))
    let outside = Point(east.face.x + 40, east.face.y)

    world.viewport.zoomLevel = 0
    #expect(world.doorFace(at: outside) == nil, "40 world units is outside a 12pt reach")
    world.viewport.zoomLevel = 20            // zoomed out: a point is worth more
    #expect(world.doorFace(at: outside) != nil)
  }

  @Test("the mark stands on the block, where the mouth stands clear of it")
  func faceIsFlush() {
    let world = fresh()
    aimed(world, half: 39)
    let east = face(world, Point(1, 0))
    #expect(abs(east.face.x - 39) < 1e-9)
    #expect(abs(east.half - 39) < 1e-9)
    // The mouth is where people *appear*, three bodies further out.
    #expect(east.at.x > east.face.x + 30)
  }

  // MARK: - What it costs and what it survives

  @Test("choosing a face is one undo, and moves no geometry")
  func oneUndoAndNoGeometry() {
    let world = fresh()
    aimed(world)
    let door = world.generators[0]
    let polygons = door.polygons
    let hull = door.hull
    choose(world, Point(-1, 0))

    // Not one wall corner moved, which is what makes the 2.1s navigation
    // rebuild unnecessary -- and the whole reason the face is stored on the
    // generator rather than built out of walls.
    #expect(world.generators[0].polygons == polygons)
    #expect(world.generators[0].hull == hull)

    world.undo()
    #expect(world.generators[0].generator!.outFacing == nil)
  }

  @Test("reset puts the queue back and leaves the face chosen")
  func resetKeepsTheChosenFace() async {
    let world = fresh()
    aimed(world)
    await world.navReady()
    choose(world, Point(-1, 0))
    for _ in 0..<300 { world.stepOnce() }

    world.resetPedestrians()
    #expect(world.generators[0].generator!.beat == 0)
    #expect(world.generators[0].generator!.outFacing != nil)
  }

  @Test("un-marking a door forgets which face it used")
  func unmarkingForgetsTheFace() {
    let world = fresh()
    aimed(world)
    choose(world, Point(-1, 0))

    #expect(world.toggleGeneratorAt(Point(0, 0)))     // no longer a door
    #expect(world.toggleGeneratorAt(Point(0, 0)))     // and a door again
    #expect(world.generators[0].generator!.outFacing == nil)
  }
}

