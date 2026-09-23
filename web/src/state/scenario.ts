import { BLACK, WHITE, type RGB } from '../palette';
import type { Point } from '../sim/geometry';
import {
  DEFAULT_SETTINGS, SETTING_RANGES, generatorSquare, makeGenerator, makeLabel, makeWall,
  type Label, type NumericSetting, type Settings, type Wall,
} from './model';

/**
 * A snapshot of everything on the map, as plain JSON.
 *
 * Exists so a scenario can be handed to someone else verbatim -- notably to
 * reproduce a case where pedestrians get stuck, which depends on the exact
 * positions, goals and settings involved and is otherwise near-impossible to
 * describe. Also the basis for saving and loading, and for the shared link.
 *
 * Version 2 added the pedestrian colour and dropped the trees. The colour
 * matters now that a snapshot can be opened again rather than only read: a
 * pedestrian takes the colour of the goal it is heading for, so a snapshot
 * without it describes a map that looks different from the one it was taken of.
 * Version 3 added the border flag, for the same reason: a frame reopened as an
 * ordinary wall would swallow every outline on the map. Version 4 added the
 * labels: a map that says which door is which is a different map from one that
 * does not. Version 5 added the generators, and the flag saying which
 * pedestrians came out of one -- a flow reopened as a standing crowd is a
 * different map again. Version 6 moved a generator onto the wall it belongs
 * to, ported from the iOS port: a door is a wall with people coming out of it,
 * not a block that happens to stand near one.
 */
export const SCENARIO_VERSION = 6;

/**
 * A pedestrian as it is stored: where it is, where it started, and what it is
 * doing. Everything else about an agent -- its waypoint, its step budget, its
 * distance to the goal -- is recomputed from the map on the next tick.
 */
export interface SerializedAgent {
  x: number;
  y: number;
  originX: number;
  originY: number;
  /** Goal wall id, or -1 when unassigned. */
  goal: number;
  arrived: boolean;
  color: RGB;
  /**
   * Whether a generator let this one out; see Agents.spawned. Optional, and read
   * with a default: a payload written before generators existed describes a map
   * where every pedestrian was painted by hand.
   */
  spawned?: boolean;
}

/**
 * A generator as it is stored: where the block is, how fast it lets people out,
 * and where they are headed. Its footprint is derived from the pedestrian radius
 * and its emission counter belongs to the run, so neither travels.
 */
export interface SerializedGenerator {
  at: Point;
  rate: number;
  /** Goal wall id, or -1 when unassigned. */
  goal: number;
  color: RGB;
}

/**
 * A generator as it rides on the wall it belongs to: how fast it lets people
 * out, where they are headed, and the exit side it has been told to use, if
 * any. Its emission point is derived from the wall's own geometry rather than
 * stored, so it is not here either -- see model.generatorMouth.
 */
export interface SerializedWallGenerator {
  rate: number;
  /** Goal wall id, or -1 when unassigned. */
  goal: number;
  color: RGB;
  outFacing?: Point;
}

/**
 * A pedestrian in the JSON report, which adds a fact the map alone does not
 * carry: whether there is currently any route from where it stands.
 *
 * Derived from the navigation graph rather than stored, so it is written out for
 * a reader and never read back in.
 */
export interface ReportedAgent extends SerializedAgent {
  /** Set when the pedestrian has no route: the thing worth looking at. */
  stuck: boolean;
}

/** A label as it is stored: where the word sits, the word, and how big it is. */
export interface SerializedLabel {
  at: Point;
  text: string;
  /** World-unit height and font weight, as the sliders were set when it was written. */
  size: number;
  weight: number;
}

export interface SerializedWall {
  id: number;
  polygons: Point[][];
  color: RGB;
  isGoal: boolean;
  /** Whether this wall is a border frame; see Wall.isBorder. */
  isBorder: boolean;
  /** Present when this wall is a door; see model.Wall.generator. */
  generator?: SerializedWallGenerator;
}

/**
 * Everything a map *is*: what a shared link carries and what an import restores.
 *
 * The report below adds a timestamp, a summary and the stuck flags. Those are
 * descriptive or derived -- a link that carried them would be claiming the
 * sender's clock and the sender's navigation graph as facts about the recipient's
 * map -- so the codec encodes this narrower type and nothing else.
 */
export interface ScenarioCore {
  version: number;
  settings: Settings;
  view: { targetX: number; targetY: number; zoomLevel: number };
  walls: SerializedWall[];
  agents: SerializedAgent[];
  /**
   * Optional, and read with a default everywhere: a payload written before
   * labels existed has no field here, and that is a map with nothing written on
   * it rather than a map that failed to load.
   */
  labels?: SerializedLabel[];
  /**
   * Free-standing generators, from before a door was a wall. Never written by
   * this app any more -- see SerializedWall.generator -- but still read, so a
   * map saved by an older build, or a legacy link, still opens with its doors
   * intact; see buildWorld.
   */
  generators?: SerializedGenerator[];
}

/** A core plus the descriptive extras the JSON report carries. */
export interface Scenario extends ScenarioCore {
  created: string;
  agents: ReportedAgent[];
  /** Quick read on the state of the run, so a report is legible at a glance. */
  summary: {
    walls: number;
    goals: number;
    agents: number;
    arrived: number;
    stuck: number;
    labels: number;
    generators: number;
  };
}

const round = (v: number) => Math.round(v * 100) / 100;

/** A number from a payload, or the default when it is not one. */
const number = (v: unknown, fallback: number) => (
  typeof v === 'number' && Number.isFinite(v) ? v : fallback
);

export interface ScenarioInput {
  settings: Settings;
  view: { targetX: number; targetY: number; zoomLevel: number };
  walls: Wall[];
  agents: SerializedAgent[];
  labels: Label[];
}

/** The map itself, with every coordinate rounded to two decimals. */
export function serializeCore(input: ScenarioInput): ScenarioCore {
  return {
    version: SCENARIO_VERSION,
    settings: { ...input.settings },
    view: {
      targetX: round(input.view.targetX),
      targetY: round(input.view.targetY),
      zoomLevel: input.view.zoomLevel,
    },
    walls: input.walls.map((w) => ({
      id: w.id,
      polygons: w.polygons.map((poly) => poly.map(([x, y]) => [round(x), round(y)] as Point)),
      color: w.color,
      isGoal: w.isGoal,
      isBorder: w.isBorder,
      generator: w.generator ? {
        rate: w.generator.rate,
        goal: w.generator.goal,
        color: w.generator.color,
        outFacing: w.generator.outFacing,
      } : undefined,
    })),
    agents: input.agents.map((a) => ({
      x: round(a.x),
      y: round(a.y),
      originX: round(a.originX),
      originY: round(a.originY),
      goal: a.goal,
      arrived: a.arrived,
      color: a.color,
      spawned: a.spawned === true,
    })),
    labels: input.labels.map((l) => ({
      at: [round(l.at[0]), round(l.at[1])] as Point,
      text: l.text,
      size: l.size,
      weight: l.weight,
    })),
  };
}

/**
 * The report: the map, plus when it was taken, which pedestrians are stuck, and
 * a summary line.
 *
 * `stuck` comes in per agent because only the caller holds the navigation graph
 * that can answer it.
 */
export function serializeScenario(input: ScenarioInput & { stuck: boolean[] }): Scenario {
  const core = serializeCore(input);
  const agents: ReportedAgent[] = core.agents.map((a, i) => ({ ...a, stuck: input.stuck[i] === true }));
  return {
    ...core,
    created: new Date().toISOString(),
    agents,
    summary: {
      walls: core.walls.length,
      goals: core.walls.filter((w) => w.isGoal).length,
      agents: agents.length,
      arrived: agents.filter((a) => a.arrived).length,
      stuck: agents.filter((a) => a.stuck).length,
      labels: core.labels?.length ?? 0,
      generators: core.walls.filter((w) => w.generator).length,
    },
  };
}

export function scenarioToJson(scenario: Scenario): string {
  return JSON.stringify(scenario, null, 2);
}

/**
 * Settings from an untrusted source, made legal.
 *
 * A link is typed, pasted and truncated by hand, so nothing in it can be taken
 * at its word. The ranges are the sliders' own, read from the model so that
 * loading a map does not depend on a control existing.
 *
 * Idempotent: clamping a clamped scenario changes nothing. That is what makes it
 * safe to call from more than one import path.
 */
export function clampSettings(input: Partial<Settings> | null | undefined): Settings {
  const out = { ...DEFAULT_SETTINGS };
  if (!input) return out;
  for (const key of Object.keys(DEFAULT_SETTINGS) as (keyof Settings)[]) {
    const value = input[key];
    const fallback = DEFAULT_SETTINGS[key];
    if (typeof fallback === 'boolean') {
      if (typeof value === 'boolean') (out[key] as boolean) = value;
      continue;
    }
    if (typeof value !== 'number' || !Number.isFinite(value)) continue;
    const range = SETTING_RANGES[key as NumericSetting];
    const clamped = range ? Math.min(range.max, Math.max(range.min, value)) : value;
    // Snapped to the slider's own grid rather than to whole numbers: speed
    // moved to metres per second with a step of 0.05, and rounding it to an
    // integer would quietly rewrite every loaded map's pace. The rounding
    // guards the same thing it always did -- a link is untrusted input, and
    // 1.30000000000004 is not a value a slider can hold.
    const step = range?.step ?? 1;
    // toFixed sands off the float grit of fractional steps: 12 * 0.05 is
    // 0.6000000000000001, and that is not a number to show beside a slider.
    (out[key] as number) = Number((Math.round(clamped / step) * step).toFixed(4));
  }
  return out;
}

/** A pedestrian ready to be put back, with its goal already pointing at a live wall. */
export interface RestoredAgent {
  x: number;
  y: number;
  originX: number;
  originY: number;
  /** The id of a wall that exists now, or -1. */
  goal: number;
  arrived: boolean;
  color: RGB;
  /** Whether a generator let it out, and so whether it goes when it arrives. */
  spawned: boolean;
}

/**
 * The interesting half of loading a map: fresh walls, and every goal repointed
 * at them.
 *
 * Wall ids come from a module counter in model.ts that never resets, so an
 * imported wall gets an id that has never been used and cannot collide with
 * anything -- but that also means the ids in the payload are not the ids the map
 * will have, and every agent's goal has to be carried across. Doing it here,
 * away from the App, is what lets it be tested without a browser.
 *
 * Shapes with fewer than three points are dropped, matching what
 * App.addWallShape already refuses to accept from a tool.
 */
export function buildWorld(
  core: ScenarioCore,
): { walls: Wall[]; agents: RestoredAgent[]; labels: Label[] } {
  const walls: Wall[] = [];
  const idMap = new Map<number, number>();
  // Kept alongside `walls` so a generator can be attached to the wall it named,
  // by payload index, once every wall has a fresh id to repoint goals through --
  // a wall a shape filter dropped leaves a hole here rather than shifting every
  // index after it.
  const builtByIndex: (Wall | null)[] = [];
  core.walls.forEach((sw) => {
    const polygons = sw.polygons.filter((poly) => poly.length >= 3);
    if (polygons.length === 0) { builtByIndex.push(null); return; }
    // `=== true` rather than a plain read: a report written before the flag
    // existed simply has no field there, and that is an ordinary wall.
    const wall = makeWall(polygons, { color: sw.color, isBorder: sw.isBorder === true });
    wall.isGoal = sw.isGoal;
    walls.push(wall);
    idMap.set(sw.id, wall.id);
    builtByIndex.push(wall);
  });

  // A generator's goal repointed the way an agent's is, and for the same
  // reason: the ids in the payload are not the ids this map will have. One
  // whose goal did not survive is simply not pinned anywhere, which is a state
  // the map already has a meaning for -- it stands there and emits nothing.
  core.walls.forEach((sw, i) => {
    const wall = builtByIndex[i];
    if (!wall || !sw.generator) return;
    const goal = idMap.get(sw.generator.goal) ?? -1;
    wall.generator = {
      rate: number(sw.generator.rate, DEFAULT_SETTINGS.generatorRate),
      goal,
      color: goal >= 0 && sw.generator.color ? sw.generator.color : WHITE,
      owed: 0,
      beat: 0,
      wait: 0,
      outFacing: sw.generator.outFacing,
    };
  });

  const agents: RestoredAgent[] = core.agents.map((a) => {
    // A goal naming a wall that did not survive is simply no goal: an
    // unassigned pedestrian is a state the map already has a meaning for.
    const goal = idMap.get(a.goal) ?? -1;
    return {
      x: a.x,
      y: a.y,
      originX: a.originX,
      originY: a.originY,
      goal,
      // An arrived pedestrian is black, as markArrived makes it. Its stored
      // colour is whatever it wore on the way, which is not what it looks like now.
      color: a.arrived ? BLACK : a.color,
      arrived: a.arrived,
      spawned: a.spawned === true,
    };
  });

  const labels = (core.labels ?? [])
    .filter((l) => typeof l.text === 'string' && l.text !== '' && Array.isArray(l.at))
    // Fresh ids like the walls, and a style clamped like a slider's: a label out
    // of a link is untrusted input, and makeLabel holds both numbers to the same
    // ranges the controls offer. A payload missing either is one written by
    // hand, and takes the default rather than a zero-height or weightless word.
    .map((l) => makeLabel([l.at[0], l.at[1]], l.text, {
      size: number(l.size, DEFAULT_SETTINGS.labelSize),
      weight: number(l.weight, DEFAULT_SETTINGS.labelWeight),
    }));

  // Legacy: free-standing generators from a payload that predates a door being
  // a wall. Each becomes a small wall of its own, at the square block it used
  // to draw as -- a generator has nowhere else to live in this model, and this
  // is the one already sized to the crowd it lets out. Only when the payload
  // carries no wall-generator of its own: a file this app wrote always attaches
  // to a real wall, so this path is for an old saved map or link alone.
  if (!core.walls.some((sw) => sw.generator)) {
    const radius = core.settings?.pedestrianRadius ?? DEFAULT_SETTINGS.pedestrianRadius;
    for (const g of core.generators ?? []) {
      if (!Array.isArray(g.at) || g.at.length !== 2) continue;
      const wall = makeWall([generatorSquare([g.at[0], g.at[1]], radius)]);
      const goal = idMap.get(g.goal) ?? -1;
      wall.generator = {
        ...makeGenerator(number(g.rate, DEFAULT_SETTINGS.generatorRate)),
        goal,
        // Unpinned it keeps the white makeGenerator gave it; pinned it wears
        // its goal's colour, as everything else headed for a goal does.
        color: goal >= 0 && g.color ? g.color : WHITE,
      };
      walls.push(wall);
    }
  }

  return { walls, agents, labels };
}
