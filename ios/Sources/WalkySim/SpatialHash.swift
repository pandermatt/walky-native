import Foundation

/// Uniform grid over agent positions, rebuilt each tick by counting sort into
/// flat arrays. Ports `src/sim/spatialHash.ts`.
///
/// `query` writes into a buffer owned by this object and returns how many it
/// found, rather than returning a slice. That mirrors the JS, which hands back
/// a subarray view valid only until the next query -- and it matters: this is
/// the hottest allocation site in the program, and returning an `ArraySlice`
/// would copy-on-write on every neighbour lookup of every agent every tick.
public final class SpatialHash {
  private var cellSize: Double = 1
  private var cols = 1
  private var rows = 1
  private var minX: Double = 0
  private var minY: Double = 0
  /// Start of each cell's slice in `items`, length cols*rows + 1.
  private var cellStart = [Int32](repeating: 0, count: 2)
  private var items = [Int32]()
  private var cursor = [Int32](repeating: 0, count: 1)

  /// Scratch reused by `query`, so a lookup allocates nothing.
  public private(set) var results = [Int32](repeating: 0, count: 64)
  /// How many of `results` the last `query` filled.
  public private(set) var resultCount = 0

  public init() {}

  /// The world rectangle the grid covers, which is the crowd's own bounding box
  /// -- outside it there is nobody, by construction.
  ///
  /// `Navigation.recost` uses it to leave alone the edges no pedestrian is
  /// anywhere near, which on a map larger than its crowd is most of them.
  public var occupiedBounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    (minX, minY, minX + Double(cols) * cellSize, minY + Double(rows) * cellSize)
  }

  public func build(_ x: [Float], _ y: [Float], _ count: Int, _ cellSize: Double) {
    self.cellSize = jsMax(1, cellSize)

    if count == 0 {
      cols = 1; rows = 1
      minX = 0; minY = 0
      if cellStart.count < 2 { cellStart = [Int32](repeating: 0, count: 2) }
      for i in 0..<cellStart.count { cellStart[i] = 0 }
      return
    }

    var lowX = Double.infinity, lowY = Double.infinity
    var highX = -Double.infinity, highY = -Double.infinity
    for i in 0..<count {
      let xi = Double(x[i]), yi = Double(y[i])
      if xi < lowX { lowX = xi }
      if xi > highX { highX = xi }
      if yi < lowY { lowY = yi }
      if yi > highY { highY = yi }
    }
    minX = lowX
    minY = lowY
    cols = Swift.max(1, Int(((highX - lowX) / self.cellSize).rounded(.down)) + 1)
    rows = Swift.max(1, Int(((highY - lowY) / self.cellSize).rounded(.down)) + 1)

    let cellCount = cols * rows
    if cellStart.count < cellCount + 1 { cellStart = [Int32](repeating: 0, count: cellCount + 1) }
    if cursor.count < cellCount { cursor = [Int32](repeating: 0, count: cellCount) }
    if items.count < count { items = [Int32](repeating: 0, count: count) }
    for i in 0...cellCount { cellStart[i] = 0 }

    // Counting sort: tally, prefix-sum, scatter.
    for i in 0..<count { cellStart[cellOf(Double(x[i]), Double(y[i])) + 1] += 1 }
    for c in 0..<cellCount { cellStart[c + 1] += cellStart[c] }
    for c in 0..<cellCount { cursor[c] = cellStart[c] }
    for i in 0..<count {
      let c = cellOf(Double(x[i]), Double(y[i]))
      items[Int(cursor[c])] = Int32(i)
      cursor[c] += 1
    }
  }

  /// Indices within `radius` of (px, py), excluding `self`. Returns the count;
  /// the indices are in `results[0..<count]` until the next query.
  @discardableResult
  /// How many agents lie within `radius` of a point, stopping once the answer
  /// is past `limit`.
  ///
  /// `query` cannot do this: it fills `results` with every match, so a caller
  /// that only wants to know "more than three?" pays for all of them. The
  /// refuge fan asks that question sixty-five times per crushed pedestrian per
  /// tick, and paying it in full was an **8x regression on the whole
  /// simulation** -- 1,000 agents at 22.3 ms/tick against 2.9 ms without it
  /// (`StepCostBench`, release).
  ///
  /// `skip` is a per-agent flag array; an agent is counted only where its flag
  /// is zero. It takes one rather than a closure because this is the hottest
  /// loop in the program and the filter is always the same question.
  ///
  /// The distance test is `query`'s, to the same inclusive bound, so the count
  /// is what `query` would have returned -- and a count over the limit is a
  /// count nobody reads, only compares.
  /// `query`'s count with none of its list. The third copy of the cell walk in
  /// this file, and the last.
  ///
  /// `Navigation.recost` samples every edge of the visibility graph and reads
  /// nothing but the number each sample returns -- and on an imported map that
  /// is not a small loop. Measured: 3,224 nodes is 691,838 edges, and one
  /// recost cost **82.8 ms**. It runs on `simTicks % RECOST_TICKS`, so that is
  /// not a cost spread over the tick but a freeze once every two seconds, which
  /// is the kind of thing a steady frame rate cannot hide.
  ///
  /// Not `countWithin` with an infinite limit, because that skips agents whose
  /// `arrived` flag is set and `query` counts them. The answer has to be the
  /// one `query` gave.
  public func countNear(_ px: Double, _ py: Double, _ radius: Double, _ selfIndex: Int,
                        _ x: [Float], _ y: [Float]) -> Int {
    let r2 = radius * radius
    let reach = Swift.max(1, Int((radius / cellSize).rounded(.up)))
    let cx = Int(((px - minX) / cellSize).rounded(.down))
    let cy = Int(((py - minY) / cellSize).rounded(.down))

    // Clamped rather than tested inside the loop, which is not a tidy-up.
    //
    // The grid spans the crowd's bounding box and nothing else (see `build`),
    // and `recost` samples edges across the whole *map* -- so on an imported
    // town most samples are nowhere near anybody, and each one was still
    // running a (2*reach+1)^2 loop to reject every cell on a bounds check. The
    // clamp makes an empty overlap cost nothing at all, which is the common
    // case rather than the rare one.
    let y0 = Swift.max(0, cy - reach), y1 = Swift.min(rows - 1, cy + reach)
    let x0 = Swift.max(0, cx - reach), x1 = Swift.min(cols - 1, cx + reach)
    if y0 > y1 || x0 > x1 { return 0 }

    var n = 0
    for gy in y0...y1 {
      let row = gy * cols
      for gx in x0...x1 {
        let cell = row + gx
        var k = Int(cellStart[cell])
        let end = Int(cellStart[cell + 1])
        while k < end {
          defer { k += 1 }
          let j = Int(items[k])
          if j == selfIndex { continue }
          let dx = Double(x[j]) - px
          let dy = Double(y[j]) - py
          if dx * dx + dy * dy > r2 { continue }
          n += 1
        }
      }
    }
    return n
  }

  public func countWithin(_ px: Double, _ py: Double, _ radius: Double, _ selfIndex: Int,
                          _ x: [Float], _ y: [Float], skip: [UInt8],
                          limit: Double) -> Double {
    var count: Double = 0
    let r2 = radius * radius
    let reach = Swift.max(1, Int((radius / cellSize).rounded(.up)))
    let cx = Int(((px - minX) / cellSize).rounded(.down))
    let cy = Int(((py - minY) / cellSize).rounded(.down))

    var gy = cy - reach
    while gy <= cy + reach {
      defer { gy += 1 }
      if gy < 0 || gy >= rows { continue }
      var gx = cx - reach
      while gx <= cx + reach {
        defer { gx += 1 }
        if gx < 0 || gx >= cols { continue }
        let cell = gy * cols + gx
        var k = Int(cellStart[cell])
        let end = Int(cellStart[cell + 1])
        while k < end {
          defer { k += 1 }
          let j = Int(items[k])
          if j == selfIndex { continue }
          if skip[j] != 0 { continue }
          let dx = Double(x[j]) - px
          let dy = Double(y[j]) - py
          if dx * dx + dy * dy > r2 { continue }
          count += 1
          if count > limit { return count }
        }
      }
    }
    return count
  }

  public func query(_ px: Double, _ py: Double, _ radius: Double, _ selfIndex: Int,
                    _ x: [Float], _ y: [Float]) -> Int {
    var n = 0
    let r2 = radius * radius
    let reach = Swift.max(1, Int((radius / cellSize).rounded(.up)))
    let cx = Int(((px - minX) / cellSize).rounded(.down))
    let cy = Int(((py - minY) / cellSize).rounded(.down))

    var gy = cy - reach
    while gy <= cy + reach {
      defer { gy += 1 }
      if gy < 0 || gy >= rows { continue }
      var gx = cx - reach
      while gx <= cx + reach {
        defer { gx += 1 }
        if gx < 0 || gx >= cols { continue }
        let cell = gy * cols + gx
        var k = Int(cellStart[cell])
        let end = Int(cellStart[cell + 1])
        while k < end {
          defer { k += 1 }
          let j = Int(items[k])
          if j == selfIndex { continue }
          let dx = Double(x[j]) - px
          let dy = Double(y[j]) - py
          if dx * dx + dy * dy > r2 { continue }
          if n == results.count {
            results.append(contentsOf: [Int32](repeating: 0, count: results.count))
          }
          results[n] = Int32(j)
          n += 1
        }
      }
    }
    resultCount = n
    return n
  }

  private func cellOf(_ px: Double, _ py: Double) -> Int {
    let gx = Int(jsMin(Double(cols - 1), jsMax(0, ((px - minX) / cellSize).rounded(.down))))
    let gy = Int(jsMin(Double(rows - 1), jsMax(0, ((py - minY) / cellSize).rounded(.down))))
    return gy * cols + gx
  }
}
