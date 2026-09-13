import Testing
@testable import WalkySim

/// Ports the retreat half of `agentsSnapshot.test.ts`.
///
/// A retreat is per-tick working state, so none of the ways a crowd is put back
/// may leave one half-walked: a pedestrian restored mid-retreat would come back
/// white, walking away from a goal it no longer remembers giving up on. The
/// behaviour itself is held to V8 by the `crush` and `counterflow` fixtures.
@Suite("A retreat does not survive being put back")
struct RetreatStateTests {

  /// A crowd with the middle one part-way through giving up.
  private func fleeing() -> Agents {
    let agents = Agents(8)
    agents.add(Point(10, 20), (255, 0, 0))
    agents.add(Point(30, 40), (0, 255, 0))
    agents.add(Point(50, 60), (0, 0, 255))
    for i in 0..<3 { agents.setGoal(i, 7, (1, 2, 3)) }
    agents.crush[1] = 40
    agents.fleeLeft[1] = 120
    agents.refugeX[1] = -400
    agents.refugeY[1] = -400
    agents.surrenders = 1
    return agents
  }

  private func expectCleared(_ agents: Agents) {
    for i in 0..<agents.count {
      #expect(agents.fleeLeft[i] == 0)
      #expect(agents.crush[i] == 0)
    }
  }

  @Test("undo clears it")
  func undo() {
    let agents = fleeing()
    agents.restore(agents.snapshot())
    expectCleared(agents)
    #expect(agents.surrenders == 0)
  }

  @Test("reset clears it")
  func reset() {
    let agents = fleeing()
    agents.resetPositions([7: (1, 2, 3)]) { (9, 9, 9) }
    expectCleared(agents)
    #expect(agents.surrenders == 0)
  }

  @Test("erasing a pedestrian moves the retreat with the one that fills the slot")
  func erase() {
    // removeAt swaps the last agent down, so every field has to travel together.
    let agents = fleeing()
    agents.fleeLeft[2] = 90
    agents.refugeX[2] = 11
    agents.refugeY[2] = 22
    agents.removeAt(0)
    #expect(agents.count == 2)
    #expect(agents.fleeLeft[0] == 90)
    #expect(agents.refugeX[0] == 11 && agents.refugeY[0] == 22)
    #expect(agents.fleeLeft[1] == 120)
    #expect(agents.refugeX[1] == -400 && agents.refugeY[1] == -400)
  }

  @Test("losing the goal ends the retreat, so nothing is left white")
  func loseGoal() {
    let agents = fleeing()
    agents.clearGoal(7)
    expectCleared(agents)
  }
}
