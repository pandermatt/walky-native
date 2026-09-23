import { describe, it, expect } from 'vitest';
import { GeneratorTool } from '../tools/generatorTool';
import { DEFAULT_SETTINGS } from '../state/model';
import type { Point } from '../sim/geometry';
import type { PointerInfo, ToolContext, ToolId } from '../tools/types';

interface Recorded {
  /** Points the tool asked to mark as a door. */
  marked: Point[];
  messages: string[];
  /** Tool the context was asked to arm; null is "nothing armed". */
  armed: (ToolId | null)[];
}

/** A context with a single wall, the square from [0,0] to [100,100]. */
function stubContext(): { ctx: ToolContext; rec: Recorded } {
  const onWall = (p: Point) => p[0] >= 0 && p[0] <= 100 && p[1] >= 0 && p[1] <= 100;
  const rec: Recorded = { marked: [], messages: [], armed: [] };
  const ctx = {
    addWall: () => true,
    addWallShape: () => true,
    settings: () => DEFAULT_SETTINGS,
    pedestrianBlock: () => [],
    addPedestrians: () => {},
    toggleGeneratorAt: (at: Point) => {
      if (!onWall(at)) return false;
      rec.marked.push(at);
      return true;
    },
    setGoalAt: () => false,
    selectPedestrianAt: () => {},
    selectPedestriansIn: () => {},
    clearSelection: () => {},
    selectionCount: () => 0,
    deactivateTool: () => rec.armed.push(null),
    activateTool: (id: ToolId) => rec.armed.push(id),
    notify: (message: string) => rec.messages.push(message),
    panBy: () => {},
    requestRender: () => {},
    colorAt: () => null,
    agentPositions: () => [],
    worldPerPixel: () => 1,
    eraseTargetAt: () => null,
    eraseAt: () => false,
    editTextAt: () => {},
  } satisfies ToolContext;
  return { ctx, rec };
}

function at(world: Point): PointerInfo {
  return { world, screen: world, dxScreen: 0, dyScreen: 0, shiftKey: false, buttons: 1 };
}

describe('GeneratorTool', () => {
  it('marks the wall it is clicked on, then steps off the tool', () => {
    const { ctx, rec } = stubContext();
    new GeneratorTool().onPointerDown(at([50, 50]), ctx);
    expect(rec.marked).toEqual([[50, 50]]);
    expect(rec.armed).toEqual([null]);
  });

  it('says so on a click that lands on no wall', () => {
    const { ctx, rec } = stubContext();
    new GeneratorTool().onPointerDown(at([500, 500]), ctx);
    expect(rec.marked).toEqual([]);
    expect(rec.messages).toHaveLength(1);
    expect(rec.messages[0]).toMatch(/wall/);
  });

  it('keeps the tool after a miss, so the next click can land', () => {
    const { ctx, rec } = stubContext();
    const tool = new GeneratorTool();
    tool.onPointerDown(at([500, 500]), ctx);
    expect(rec.armed).toEqual([]);

    tool.onPointerDown(at([50, 50]), ctx);
    expect(rec.marked).toEqual([[50, 50]]);
    expect(rec.armed).toEqual([null]);
  });

  it('ignores anything but the left button', () => {
    const { ctx, rec } = stubContext();
    new GeneratorTool().onPointerDown({ ...at([50, 50]), buttons: 2 }, ctx);
    expect(rec.marked).toEqual([]);
  });

  it('shows a target ghost at the pointer, no shape of its own', () => {
    const tool = new GeneratorTool();
    expect(tool.preview().cursorGhost).toBeNull();

    tool.onPointerMove(at([10, 10]));
    expect(tool.preview().cursorGhost).toEqual({ kind: 'target', at: [10, 10], size: 10 });
  });

  it('forgets the preview when it is put down', () => {
    const tool = new GeneratorTool();
    tool.onPointerMove(at([10, 10]));
    tool.cancel();
    expect(tool.preview().cursorGhost).toBeNull();
  });
});
