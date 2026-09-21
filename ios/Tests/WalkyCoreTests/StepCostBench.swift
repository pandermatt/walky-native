import Foundation
import Testing

@testable import WalkyCore
@testable import WalkySim

/// What one tick costs, with nothing drawn.
///
/// Off by default -- it is a measurement, not an assertion, and a suite that
/// takes a second longer on every run to print numbers nobody read is a suite
/// people stop running:
///
///     WALKY_BENCH=1 swift test -c release --filter StepCostBench
///
/// **Run it in release or the number is meaningless.** Measured on this machine,
/// debug is about seventeen times slower: 4,000 agents cost 187 ms/tick built
/// debug and 10.8 ms/tick built release. That gap is larger than any rendering
/// change could be, and it is the first thing to rule out when the app feels
/// slow -- an in-app FPS readout from a debug build is measuring the build, not
/// the code.
///
/// Two maps on purpose. `open` is one wall, which is also the goal: the crowd
/// can see it from anywhere, so `Navigation.nextWaypoint` takes its cheap
/// direct-visibility branch and the visibility graph stays at a handful of
/// nodes. That isolates the crowd cost -- and it is *not* what a hand-drawn map
/// looks like. `maze` puts obstacles between the crowd and the goal, so
/// pedestrians have to route around them: `nextWaypoint` falls to its
/// all-nodes scan, and every `isVisible` is a segment test against every wall
/// group. The TypeScript bench made this choice deliberately
/// (`web/bench/simulation.ts:31-33`); the Swift one did not, which is why its
/// numbers looked flattering.
@MainActor
@Suite("Step cost", .enabled(if: ProcessInfo.processInfo.environment["WALKY_BENCH"] != nil))
struct StepCostBench {
  /// The goal bar every scenario walks to.
  private static func addGoal(_ world: WalkyWorld) {
    world.addWallShape([rectanglePolygon(Point(-40, 600), Point(400, 660))], nil)
  }

  /// Obstacles between the crowd and the goal, in two staggered rows with gaps,
  /// so the route is genuinely around something rather than through it.
  private static func addMaze(_ world: WalkyWorld) {
    for row in 0..<2 {
      let y = 120.0 + Double(row) * 180
      for col in 0..<6 {
        let x = -360.0 + Double(col) * 130 + (row == 1 ? 65 : 0)
        world.addWallShape([rectanglePolygon(Point(x, y), Point(x + 80, y + 60))], nil)
      }
    }
  }

  /// A city around the crowd, which is what an import is.
  ///
  /// `open` and `maze` are 1 and 13 walls, and at those sizes the tick is all
  /// crowd -- which is why they report almost the same number and why they
  /// cannot see a change to anything that scales with the *map*. A forced 600m
  /// import is 225 walls and 3,393 graph nodes, and the costs that hurt there
  /// are the per-agent scans over every obstacle and every node.
  ///
  /// A ring rather than a field: the blocks go everywhere except the plaza the
  /// crowd is standing in, so nobody starts inside a building (the bench adds
  /// agents through `agents.add`, which does not clear them out) while the
  /// obstacle list and the visibility graph are the size a real map makes them.
  private static func addTown(_ world: WalkyWorld) {
    // Clear of the largest crowd this bench places -- 4,000 at an 18px pitch
    // is 64 a side, so x [-300, 834] and y [-320, 814] -- and of the goal.
    let plaza = (minX: -420.0, maxX: 960.0, minY: -440.0, maxY: 940.0)
    for gx in -8...8 {
      for gy in -8...8 {
        let x = Double(gx) * 260, y = Double(gy) * 260
        if x + 120 > plaza.minX && x < plaza.maxX
            && y + 90 > plaza.minY && y < plaza.maxY { continue }
        world.addWallShape([rectanglePolygon(Point(x, y), Point(x + 120, y + 90))], nil)
      }
    }
  }

  private static func crowd(_ world: WalkyWorld, _ count: Int) {
    let side = Int(Double(count).squareRoot()) + 1
    for i in 0..<count {
      let x = Double((i % side) * 18) - 300
      let y = Double((i / side) * 18) - 320
      _ = world.agents.add(Point(x, y), (255, 200, 0))
    }
  }

  /// Best of several runs, not the mean.
  ///
  /// One run of sixty ticks varies by about 20% here -- 4,000 agents measured
  /// 11.36, 13.70 and 12.84 ms on three consecutive runs of the same binary --
  /// which is far too loose to see the small wins this bench exists to guide.
  /// Timing noise is one-sided: the scheduler can only ever add time, so the
  /// fastest run is the closest to the code's own cost, while a mean mostly
  /// reports what else the machine was doing.
  private static func msPerTick(_ build: () -> WalkyWorld) -> Double {
    var best = Double.infinity
    for _ in 0..<5 {
      let world = build()
      // Warm the navigation graph first: the first tick after a goal is marked
      // pays for a Dijkstra the rest do not.
      for _ in 0..<10 { world.stepOnce() }
      let started = Date()
      let ticks = 60
      for _ in 0..<ticks { world.stepOnce() }
      best = min(best, Date().timeIntervalSince(started) * 1000 / Double(ticks))
    }
    return best
  }

  @Test("one tick, by crowd size and map")
  func stepCost() {
    print("  agents        open              maze              town        town/open")
    for count in [500, 1000, 2000, 4000] {
      var results: [Double] = []
      for map in ["open", "maze", "town"] {
        results.append(Self.msPerTick {
          let world = WalkyWorld()
          world.settings.defaults = nil
          Self.addGoal(world)
          if map == "maze" { Self.addMaze(world) }
          if map == "town" { Self.addTown(world) }
          Self.crowd(world, count)
          _ = world.setGoalAt(Point(180, 630))
          world.play(true)
          return world
        })
      }
      let open = results[0], maze = results[1], town = results[2]
      print(String(format: "  %6d  %7.2f ms %5.0f/s  %7.2f ms %5.0f/s  %7.2f ms %5.0f/s   %4.1fx",
                   count, open, 1000 / open, maze, 1000 / maze, town, 1000 / town,
                   town / open))
    }
  }
}

/// What one stroke of the pedestrian brush costs on a map with walls on it.
///
///     WALKY_BENCH=1 swift test -c release --filter BrushCostBench
///
/// Release only, for the reason `StepCostBench` gives at length.
///
/// The map is what makes this bench mean anything: 200 blocks is the order of a
/// real import (the README's Zurich row is 225 walls, 1,947 corners), and the
/// cost being measured is per *placed dot*, not per tick. Painting is the one
/// gesture that commits a full world edit on every pointer event, so whatever
/// one call costs here is paid sixty times a second while a finger moves.
@MainActor
@Suite("Brush cost", .enabled(if: ProcessInfo.processInfo.environment["WALKY_BENCH"] != nil))
struct BrushCostBench {
  /// A grid of blocks, the shape an imported neighbourhood has.
  private static func town(_ world: WalkyWorld, blocks: Int) {
    let side = Int(Double(blocks).squareRoot()) + 1
    for i in 0..<blocks {
      let x = Double((i % side) * 220) - 2000
      let y = Double((i / side) * 220) - 2000
      world.addWallShape([rectanglePolygon(Point(x, y), Point(x + 120, y + 90))], nil)
    }
  }

  /// Milliseconds per `addPedestrians`, best of five strokes.
  ///
  /// A stroke rather than one call, because the cost grows as the crowd does:
  /// `checkpoint` copies every agent placed so far, so the hundredth dot of a
  /// drag is dearer than the first, and the average over a stroke is what a
  /// hand actually feels.
  private static func msPerDot(blocks: Int, dots: Int) -> Double {
    var best = Double.infinity
    for _ in 0..<5 {
      let world = WalkyWorld()
      world.settings.defaults = nil
      town(world, blocks: blocks)
      world.rebuildNavNow()

      let started = Date()
      for i in 0..<dots {
        // Along a lane between the blocks, as a drag would travel.
        _ = world.addPedestrians(Point(-1900 + Double(i) * 12, -1850), cells: 3)
      }
      best = min(best, Date().timeIntervalSince(started) * 1000 / Double(dots))
    }
    return best
  }

  /// What the *renderer* pays every time `worldRevision` moves.
  ///
  /// `RenderCache.refresh` is keyed on that revision, and rebuilding it runs
  /// `groupWalls` -- an all-pairs union-find with no bounding-box reject. It
  /// lives in the app target where no test can reach it, but `groupWalls` is
  /// `WalkyCore` and is the whole of the quadratic term, so timing it here is
  /// timing that rebuild.
  private static func msPerRegroup(blocks: Int) -> Double {
    let world = WalkyWorld()
    world.settings.defaults = nil
    town(world, blocks: blocks)
    var best = Double.infinity
    for _ in 0..<5 {
      let started = Date()
      for _ in 0..<10 { _ = groupWalls(world.walls) }
      best = min(best, Date().timeIntervalSince(started) * 1000 / 10)
    }
    return best
  }

  @Test("one placed dot, by how much map is under it")
  func brushCost() {
    print("  blocks      ms/dot     dots/s   groupWalls/rebuild")
    for blocks in [1, 50, 200] {
      let ms = Self.msPerDot(blocks: blocks, dots: 120)
      let regroup = Self.msPerRegroup(blocks: blocks)
      print(String(format: "  %6d  %9.3f ms %7.0f/s  %9.3f ms",
                   blocks, ms, 1000 / ms, regroup))
    }
  }
}

/// What the *map* costs, as against what the crowd costs.
///
///     WALKY_BENCH=1 swift test -c release --filter MapCostBench
///
/// Release only, for the reason `StepCostBench` gives at length.
///
/// `StepCostBench`'s three maps hold the crowd fixed and vary the obstacles a
/// little; this holds the crowd at 1,000 and varies the map by an order of
/// magnitude, because the costs that hurt on an import scale with the graph
/// rather than with the people. A forced 600m import is about 3,400 nodes,
/// which is the middle row.
///
/// The `recost` column is the one to watch, and it is reported on its own
/// rather than inside the tick because it does not run every tick: it runs on
/// `simTicks % RECOST_TICKS`, which is once every two seconds of simulated
/// time. An average over ticks would divide it away, and a freeze once every
/// two seconds is not something a frame rate can average out -- it is exactly
/// what "smooth in a game, stuttery here" describes.
@MainActor
@Suite("Map cost", .enabled(if: ProcessInfo.processInfo.environment["WALKY_BENCH"] != nil))
struct MapCostBench {
  /// A city with the crowd in a plaza in the middle of it, which is the shape
  /// of an import: the crowd occupies a small part of a large map. The blocks
  /// go everywhere except the plaza, so nobody starts inside a building -- the
  /// bench adds agents through `agents.add`, which does not clear them out.
  private static func town(_ world: WalkyWorld, half: Int) -> Int {
    let plaza = (minX: -420.0, maxX: 960.0, minY: -440.0, maxY: 940.0)
    var blocks = 0
    for gx in -half...half {
      for gy in -half...half {
        let x = Double(gx) * 260, y = Double(gy) * 260
        if x + 120 > plaza.minX && x < plaza.maxX
            && y + 90 > plaza.minY && y < plaza.maxY { continue }
        world.addWallShape([rectanglePolygon(Point(x, y), Point(x + 120, y + 90))], nil)
        blocks += 1
      }
    }
    return blocks
  }

  @Test("tick and recost, by how much map there is")
  func mapCost() {
    print("   walls   nodes     edges     ms/tick       recost")
    for half in [8, 14, 20] {
      let world = WalkyWorld()
      world.settings.defaults = nil
      world.addWallShape([rectanglePolygon(Point(-40, 600), Point(400, 660))], nil)
      let blocks = Self.town(world, half: half)
      for i in 0..<1000 {
        _ = world.agents.add(Point(Double((i % 32) * 18) - 300,
                                   Double((i / 32) * 18) - 320), (255, 200, 0))
      }
      _ = world.setGoalAt(Point(180, 630))
      world.play(true)
      for _ in 0..<10 { world.stepOnce() }

      var tick = Double.infinity
      for _ in 0..<3 {
        let started = Date()
        for _ in 0..<40 { world.stepOnce() }
        tick = Swift.min(tick, Date().timeIntervalSince(started) * 1000 / 40)
      }
      var recost = Double.infinity
      for _ in 0..<3 {
        let started = Date()
        world.nav.recost(world.hash, world.agents.x, world.agents.y, world.agents.count)
        recost = Swift.min(recost, Date().timeIntervalSince(started) * 1000)
      }
      print(String(format: "  %6d  %6d  %8d  %7.2f ms  %7.2f ms",
                   blocks, world.nav.graphNodeCount, world.nav.graphEdgeCount, tick, recost))
    }
  }
}
