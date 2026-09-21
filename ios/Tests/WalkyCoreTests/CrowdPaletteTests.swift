import Testing

@testable import WalkyCore

/// The palette is *derived* -- six accents put through `javaDarker` until they
/// clear a contrast bar -- and the whole argument for deriving it rather than
/// writing down twenty-four colours is that a derivation can be checked. These
/// are that check.
@Suite("Crowd palette")
struct CrowdPaletteTests {
  @Test("every colour reads against the ground it was derived for")
  func legibleEverywhere() {
    for ground in Grounds.all {
      for color in CrowdPalette.on(ground) {
        let ratio = contrastRatio(color, ground.background)
        #expect(ratio >= CrowdPalette.minimumContrast,
                "\(toHex(color)) on \(ground.label) is \(ratio)")
      }
    }
  }

  /// The claim the `legible` doc comment makes, as an assertion: the dark
  /// grounds need no darkening at all, and Paper is the only one that does.
  @Test("only Paper darkens anything")
  func paperIsTheOnlyOneThatDarkens() {
    let plain = Accents.all.map { $0.color }
    for ground in [Grounds.classic, Grounds.midnight, Grounds.blueprint] {
      #expect(CrowdPalette.on(ground).map { toHex($0) } == plain.map { toHex($0) },
              "\(ground.label) darkened an accent it did not need to")
    }
    let paper = CrowdPalette.on(Grounds.paper)
    // Orange twice, teal/lime/sky once, magenta and rust not at all.
    #expect(toHex(paper[0]) == toHex(shadowOf(Accents.orange.color)))
    #expect(toHex(paper[1]) == toHex(javaDarker(Accents.teal.color)))
    #expect(toHex(paper[3]) == toHex(Accents.magenta.color))
    #expect(toHex(paper[5]) == toHex(Accents.rust.color))
  }

  /// `restyled` traces a colour back to its accent through a shared table, so
  /// two different accents landing on the same colour under different grounds
  /// would silently swap a crowd's hue. Six accents over four grounds is 24
  /// entries; they must be 24 distinct colours per accent-index.
  @Test("no two accents collide across grounds")
  func noCollisions() {
    var owner: [String: Int] = [:]
    for ground in Grounds.all {
      for (i, color) in CrowdPalette.on(ground).enumerated() {
        let key = toHex(color)
        #expect(owner[key] ?? i == i, "\(key) is both accent \(owner[key]!) and \(i)")
        owner[key] = i
      }
    }
  }

  @Test("a colour restyles to the same accent on another ground")
  func restylesByAccent() {
    for ground in Grounds.all {
      for (i, color) in CrowdPalette.on(ground).enumerated() {
        for other in Grounds.all {
          #expect(CrowdPalette.restyled(color, to: other).map { toHex($0) }
                  == toHex(CrowdPalette.on(other)[i]))
        }
      }
    }
  }

  /// The guard that keeps restyling off somebody else's map.
  @Test("a colour from outside the palette is left alone")
  func foreignColoursAreNotOurs() {
    #expect(CrowdPalette.restyled(GENERATOR_GREY, to: Grounds.paper) == nil)
    #expect(CrowdPalette.restyled((1, 2, 3), to: Grounds.paper) == nil)
    #expect(CrowdPalette.restyled(WHITE, to: Grounds.classic) == nil)
  }

  /// The point of the whole exercise: the renderer batches fills by colour, and
  /// a crowd has to collapse to a handful of batches rather than one per body.
  @MainActor
  @Test("a placed crowd wears at most six colours")
  func aCrowdBatches() {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.addPedestrians(Point(0, 0), cells: 20)
    #expect(world.agents.count > 100)
    #expect(Set(world.agents.color[0..<world.agents.count]).count <= 6)
  }

  @MainActor
  @Test("switching ground repaints the crowd and leaves imports alone")
  func restyleMovesOnlyOurs() {
    let world = WalkyWorld()
    world.settings.defaults = nil
    world.settings.groundId = Grounds.classic.id
    world.addPedestrians(Point(0, 0), cells: 8)
    world.addWallShape([rectanglePolygon(Point(300, 300), Point(360, 360))],
                       WallOptions(color: (1, 2, 3)))

    world.restyle(to: Grounds.paper)
    let paper = Set(CrowdPalette.on(Grounds.paper).map { packRgb($0) })
    for i in 0..<world.agents.count {
      #expect(paper.contains(world.agents.color[i]))
    }
    #expect(toHex(world.walls.last!.color) == toHex((1, 2, 3)))
  }
}
