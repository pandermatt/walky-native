import type { Point } from '../sim/geometry';
import { EMPTY_PREVIEW, type PointerInfo, type Tool, type ToolContext, type ToolPreview } from './types';

/**
 * Marks a wall as a door: somewhere people come out of, from
 * controller/MarkGeneratorToolMouseListener.
 *
 * Ports the iOS port's move of the generator tool from placing a new square
 * block to marking an existing shape -- exactly as the goal tool does. Any
 * block on the map can be a door, the same way any block can be a goal: draw a
 * shape with the tools that draw shapes, then say what it is. A door is a wall
 * with people coming out of it, not a second way of making walls that only
 * this tool knew about.
 *
 * Tapping a wall that is already a door un-marks it -- whatever it had already
 * let out goes on walking, since a door that has closed behind them is what
 * happens to people.
 *
 * A click that lands on no wall says so and changes nothing: there is no
 * ground to mark, the way there is no ground to make a goal.
 */
export class GeneratorTool implements Tool {
  readonly id = 'generator' as const;
  readonly cursor = 'crosshair';
  private mouse: Point | null = null;

  onPointerDown(e: PointerInfo, ctx: ToolContext): void {
    if (e.buttons !== 1) return;
    if (!ctx.toggleGeneratorAt(e.world)) {
      ctx.notify('No wall there — click a wall to make it a door.');
      return;
    }
    // Marking a door completes the gesture, exactly as marking a goal does:
    // step off the tool so the next click cannot mark another one by accident.
    ctx.deactivateTool();
  }

  onPointerMove(e: PointerInfo): void {
    this.mouse = e.world;
  }

  cancel(): void {
    this.mouse = null;
  }

  preview(): ToolPreview {
    if (!this.mouse) return EMPTY_PREVIEW;
    return { ...EMPTY_PREVIEW, cursorGhost: { kind: 'target', at: this.mouse, size: 10 } };
  }
}
