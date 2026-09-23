import { describe, expect, it } from 'vitest';
import { decodeMapFile, encodeMapFile, suggestedMapFileName } from '../state/mapFile';
import { ScenarioLinkError } from '../state/codec';
import { DEFAULT_SETTINGS } from '../state/model';
import { SCENARIO_VERSION, type ScenarioCore, type SerializedAgent } from '../state/scenario';
import type { Point } from '../sim/geometry';

function core(over: Partial<ScenarioCore> = {}): ScenarioCore {
  return {
    version: SCENARIO_VERSION,
    settings: { ...DEFAULT_SETTINGS },
    view: { targetX: 0, targetY: 0, zoomLevel: 0 },
    walls: [],
    agents: [],
    labels: [],
    generators: [],
    ...over,
  };
}

function agent(x: number, y: number, over: Partial<SerializedAgent> = {}): SerializedAgent {
  return { x, y, originX: x, originY: y, goal: -1, arrived: false, color: [10, 200, 240], spawned: false, ...over };
}

function box(x: number, y: number): Point[] {
  return [[x, y], [x + 40, y], [x + 40, y + 30], [x, y + 30]];
}

describe('a .walky file', () => {
  it('round trips a map, unlike a link, without any base64 or fragment', async () => {
    const before = core({
      walls: [{ id: 1, polygons: [box(0, 0)], color: [200, 30, 90], isGoal: true, isBorder: false }],
      agents: [agent(10, 10, { goal: 1, color: [200, 30, 90] })],
    });
    const bytes = await encodeMapFile(before);
    const after = await decodeMapFile(bytes);
    expect(after.walls).toEqual(before.walls);
    expect(after.agents).toEqual(before.agents);
  });

  it('is exactly the bytes a link carries, once the base64 is stripped', async () => {
    const { encodeLink } = await import('../state/shareLink');
    const scenario = core({ walls: [{ id: 1, polygons: [box(0, 0)], color: [1, 2, 3], isGoal: false, isBorder: false }] });
    const link = await encodeLink(scenario);
    const { base64UrlToBytes } = await import('../state/codec');
    const payload = link.slice(link.indexOf('=') + 1);
    const fromLink = base64UrlToBytes(payload);
    const fromFile = await encodeMapFile(scenario);
    expect([...fromFile]).toEqual([...fromLink]);
  });

  it('deflates a large map when that comes out smaller', async () => {
    const agents: SerializedAgent[] = Array.from({ length: 1500 }, (_, i) =>
      agent(40 + (i % 50) * 26, 40 + Math.floor(i / 50) * 26, { goal: 1, color: [255, 190, 0] }));
    const scenario = core({
      walls: [{ id: 1, polygons: [box(0, 0)], color: [1, 2, 3], isGoal: true, isBorder: false }],
      agents,
    });
    const raw = await encodeMapFile(scenario);
    // FLAG_DEFLATED is bit 1 of the third byte.
    expect(raw[2] & 1).toBe(1);
    expect(await decodeMapFile(raw)).toEqual(scenario);
  });

  it('refuses bytes that are not a Walky payload, with a message fit to show', async () => {
    await expect(decodeMapFile(new Uint8Array([1, 2, 3]))).rejects.toThrow(ScenarioLinkError);
  });

  it('names itself after what is on the map', () => {
    expect(suggestedMapFileName(core())).toBe('Empty map');
    expect(suggestedMapFileName(core({
      walls: [{ id: 1, polygons: [box(0, 0)], color: [1, 2, 3], isGoal: false, isBorder: false }],
    }))).toBe('1 wall');
    expect(suggestedMapFileName(core({
      walls: [
        { id: 1, polygons: [box(0, 0)], color: [1, 2, 3], isGoal: false, isBorder: false },
        { id: 2, polygons: [box(50, 0)], color: [1, 2, 3], isGoal: false, isBorder: false },
      ],
      agents: [agent(0, 0, { color: [1, 2, 3] })],
    }))).toBe('2 walls, 1 pedestrian');
  });
});
