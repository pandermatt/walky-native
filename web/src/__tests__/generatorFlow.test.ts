import { describe, it, expect } from 'vitest';
import { Agents } from '../sim/agents';
import {
  GENERATOR_CELLS, generatorMouth, makeGenerator, makeWall, mouthDirection, rectanglePolygon, wallMiddle,
} from '../state/model';

/**
 * What separates the flow from the crowd.
 *
 * A generator's pedestrians are the run rather than the map: they are marked on
 * the way in and taken off the map the moment they arrive, so a door left running
 * does not slowly bury the goal it is aimed at.
 */
describe('generator pedestrians', () => {
  it('are marked as the run\'s, where a painted one is not', () => {
    const agents = new Agents(8);
    agents.add([10, 10]);
    agents.addSpawned([20, 20], 7, [1, 2, 3]);
    expect([...agents.spawned.slice(0, 2)]).toEqual([0, 1]);
    expect(agents.goal[1]).toBe(7);
  });

  it('go when they arrive, and take the painted crowd nowhere with them', () => {
    const agents = new Agents(8);
    const painted = agents.add([10, 10]);
    agents.addSpawned([20, 20], 7, [1, 2, 3]);
    agents.addSpawned([30, 30], 7, [1, 2, 3]);
    agents.arrived[painted] = 1;
    agents.arrived[1] = 1;
    agents.arrived[2] = 1;

    expect(agents.removeArrivedSpawned()).toBe(2);
    expect(agents.count).toBe(1);
    expect([agents.x[0], agents.y[0]]).toEqual([10, 10]);
  });

  it('stay while they are still walking', () => {
    const agents = new Agents(8);
    agents.addSpawned([20, 20], 7, [1, 2, 3]);
    expect(agents.removeArrivedSpawned()).toBe(0);
    expect(agents.count).toBe(1);
  });

  /**
   * removeAt swaps the last agent down into the freed slot, so a removal loop
   * that walked upwards would step straight over whatever landed behind it.
   */
  it('are all taken however they are interleaved with the crowd', () => {
    const agents = new Agents(16);
    for (let i = 0; i < 10; i++) {
      if (i % 2 === 0) agents.add([i, 0]);
      else agents.addSpawned([i, 0], 7, [1, 2, 3]);
      agents.arrived[i] = 1;
    }
    expect(agents.removeArrivedSpawned()).toBe(5);
    expect(agents.count).toBe(5);
    expect([...agents.spawned.slice(0, 5)]).toEqual([0, 0, 0, 0, 0]);
  });

  it('are cleared outright by Reset, having no starting line to go back to', () => {
    const agents = new Agents(8);
    agents.add([10, 10]);
    agents.addSpawned([20, 20], 7, [1, 2, 3]);
    expect(agents.removeSpawned()).toBe(1);
    expect(agents.count).toBe(1);
    expect(agents.spawned[0]).toBe(0);
  });

  it('survive undo as what they are', () => {
    const agents = new Agents(8);
    agents.add([10, 10]);
    agents.addSpawned([20, 20], 7, [1, 2, 3]);
    const snap = agents.snapshot();
    agents.removeSpawned();
    agents.restore(snap);
    expect(agents.count).toBe(2);
    expect([...agents.spawned.slice(0, 2)]).toEqual([0, 1]);
  });
});

describe('a generator', () => {
  it('starts unpinned, which is what stops it emitting into nowhere', () => {
    const g = makeGenerator(5);
    expect(g.goal).toBe(-1);
    expect(g.owed).toBe(0);
    expect(g.rate).toBe(5);
  });
});

describe('a door\'s mouth', () => {
  const box = (x: number, y: number, w = 10, h = 10) => makeWall([rectanglePolygon([x, y], [x + w, y + h])]);

  it('is nowhere in particular, and nobody comes out, while it is aimed at nothing', () => {
    const wall = box(0, 0);
    wall.generator = makeGenerator(4);
    expect(mouthDirection(wall, [wall])).toBeNull();
    expect(generatorMouth(wall, [wall], 13)).toEqual(wallMiddle(wall));
  });

  it('faces the goal it is pinned to', () => {
    const wall = box(0, 0);
    const goal = box(0, 100);
    wall.generator = makeGenerator(4);
    wall.generator.goal = goal.id;
    const dir = mouthDirection(wall, [wall, goal]);
    expect(dir?.[0]).toBeCloseTo(0);
    expect(dir?.[1]).toBeCloseTo(1);
  });

  it('stands clear of the wall by the door block\'s own half-width', () => {
    const wall = box(0, 0);
    const goal = box(0, 1000);
    wall.generator = makeGenerator(4);
    wall.generator.goal = goal.id;
    const r = 13;
    const [mx, my] = generatorMouth(wall, [wall, goal], r);
    const [wx, wy] = wallMiddle(wall);
    expect(mx).toBeCloseTo(wx);
    // Reach out of the wall's own half-height (5) plus the block's own
    // half-width (GENERATOR_CELLS * r).
    expect(my).toBeCloseTo(wy + 5 + GENERATOR_CELLS * r);
  });

  it('is overridden by an explicit facing, whatever the goal says', () => {
    const wall = box(0, 0);
    const goal = box(0, 100);
    wall.generator = makeGenerator(4);
    wall.generator.goal = goal.id;
    wall.generator.outFacing = [-1, 0];
    expect(mouthDirection(wall, [wall, goal])).toEqual([-1, 0]);
  });
});
