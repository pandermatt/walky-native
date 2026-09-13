/**
 * The simulation the landing page runs behind its headline.
 *
 * A still would have been cheaper, and there is already a good one --
 * public/images/og.png, drawn by tools/ogImage.ts. But the claim the hero makes
 * is that a crowd finds its own way through a room, and a picture of a crowd
 * cannot make it: what the reader has to see is a hundred dots choosing, queuing
 * at a gap and fanning out past a corner. So this is the real model, stepped in
 * a rAF loop, and every dot on the page is a dot the same code puts on the map
 * under /demo.
 *
 * WHAT IS BORROWED AND WHAT IS NOT.
 *
 * The construction is ogImage.ts's, one line at a time -- makeWall,
 * rectanglePolygon, Navigation.rebuild, Agents.add/setGoal, and the three
 * settings read out of DEFAULT_SETTINGS rather than transcribed next to it,
 * because a transcription drifts (personalSpace was renamed and its default
 * moved from 30 to 40 while a copy sat in that file looking correct).
 *
 * The scenario itself is not shared with it, deliberately. The card is composed
 * for 1200x630 and for being glanced at two inches wide in a link preview; this
 * is a taller frame that has to still read after fifteen seconds of motion and
 * then loop without the seam showing. Two compositions, two jobs. Sharing a
 * builder between them would also mean editing ogImage.ts, and the PNG it wrote
 * is a browser render committed to the repository -- there is no way to prove
 * after the fact that a rebuild came back the same, so the file it was drawn by
 * is left alone.
 *
 * WHAT IS DELIBERATELY NOT DRAWN: every diagnostic the app can switch on. The
 * dashed hulls, the visibility rays, the personal-space rings, the routes. Those
 * are settings a reader turns on to understand a map they are working on, and
 * nobody's first sight of Walky is their working map. Same argument ogImage.ts
 * makes, for the same reason.
 */
import { Agents } from '../sim/agents';
import { Navigation } from '../sim/navigation';
import { SpatialHash } from '../sim/spatialHash';
import { DEFAULT_SETTINGS, makeWall, rectanglePolygon, type Wall } from '../state/model';
import type { RGB } from '../palette';

/**
 * Read from DEFAULT_SETTINGS rather than copied out of it, for the reason the
 * file header gives.
 */
export const RADIUS = DEFAULT_SETTINGS.pedestrianRadius;
const PERSONAL = DEFAULT_SETTINGS.personalSpace;
const SPEED = DEFAULT_SETTINGS.speed;

/**
 * The world rectangle the hero frames.
 *
 * Fixed rather than fitted to the geometry: the crowd moves, so a fitted frame
 * would breathe in and out under the headline for the whole animation.
 */
export const FRAME = { x: -40, y: -40, w: 1440, h: 1080 };

/**
 * Wall colours.
 *
 * From tools/brand.ts, so the hero, the share card and the app icons agree on
 * what Walky looks like -- and every one of them is legal under
 * randomBrightColor's rule (one channel in 150-255, the other two free), so a
 * wall really could come out this colour in the app.
 */
const MAGENTA: RGB = [196, 25, 192];
const TEAL: RGB = [41, 214, 168];
const LIME: RGB = [168, 214, 66];
const RUST: RGB = [214, 66, 39];
const SKY: RGB = [66, 158, 214];

export interface HeroScene {
  walls: Wall[];
  agents: Agents;
  nav: Navigation;
  hash: SpatialHash;
  /** One tick of the same model the app runs. */
  step(): void;
}

/**
 * Two walls leaving a gap, an L the crowd has to walk around, and two goals.
 *
 * The gap is the point of the composition: a crowd that walks straight at a
 * target shows nothing a still could not, and a crowd pressed against a
 * bottleneck shows the whole model at once -- queueing, giving way, and the
 * shape a room forces on a hundred independent decisions.
 *
 * The L is there so the frame holds a wall that is not convex, which the crowd
 * has to route around; the two goals are there so the crowd carries two colours
 * and fans out past it instead of converging on one point.
 */
function buildWorld(): { walls: Wall[]; nav: Navigation; goals: Wall[] } {
  // The two walls run off the top and bottom of the frame rather than ending
  // inside it: a room that stops where the picture does reads as a diagram, and
  // one that carries on past the edge reads as a room.
  const gapTop = makeWall([rectanglePolygon([480, -120], [580, 400])], { color: RUST });
  const gapBottom = makeWall([rectanglePolygon([480, 650], [580, 1140])], { color: SKY });

  const detour = makeWall([[
    [780, 360], [1010, 360], [1010, 450], [880, 450], [880, 690], [780, 690],
  ]], { color: LIME });

  const goalUpper = makeWall([rectanglePolygon([1180, 140], [1330, 300])], { color: MAGENTA });
  const goalLower = makeWall([rectanglePolygon([1180, 720], [1330, 880])], { color: TEAL });
  goalUpper.isGoal = true;
  goalLower.isGoal = true;

  const walls = [gapTop, gapBottom, detour, goalUpper, goalLower];
  const nav = new Navigation();
  nav.rebuild(walls, RADIUS);
  return { walls, nav, goals: [goalUpper, goalLower] };
}

/**
 * The crowd, painted the way the pedestrian brush paints one: shoulder to
 * shoulder, and left to sort itself out.
 *
 * A packed block breaks its own formation within a second of being let go, which
 * is why nothing here jitters the start to stop it marching in rows -- the model
 * does that on its own, and watching it happen is half of what the hero is for.
 */
function buildCrowd(goals: Wall[]): Agents {
  const agents = new Agents();
  const pitch = 2 * RADIUS;
  // Tall and narrow rather than square: the block has to span most of the
  // frame's height for the funnel to be the thing you notice, and every column
  // added to its width is another lap of queueing before the loop can restart.
  const cols = 8;
  const rows = 20;
  for (let i = 0; i < cols; i++) {
    for (let j = 0; j < rows; j++) {
      const k = agents.add([60 + i * pitch, 250 + j * pitch]);
      // Split by row so both goals pull from the full height of the block and
      // the two colours interleave on the way to the gap.
      const goal = goals[j % 2];
      agents.setGoal(k, goal.id, goal.color);
    }
  }
  return agents;
}

/** A fresh scene, its crowd back at the start line. */
export function buildHeroScene(): HeroScene {
  const { walls, nav, goals } = buildWorld();
  const agents = buildCrowd(goals);
  const hash = new SpatialHash();
  return {
    walls,
    agents,
    nav,
    hash,
    step: () => agents.step(nav, hash, SPEED, RADIUS, PERSONAL),
  };
}

/**
 * How far in the still is taken when the reader has asked for no motion.
 *
 * Far enough that the block has opened out and packed against the bottleneck
 * with the leaders already blackened at the goals, and not so far that everyone
 * has arrived and the picture is a field of black dots. The same frame the
 * animation passes through, held rather than played.
 */
export const STILL_TICKS = 560;

/**
 * The longest a run is allowed to go before the loop gives up on it.
 *
 * This crowd finishes in about 2150 ticks, and the last of it arrives within a
 * couple of hundred of the rest. The cap is not for that -- it is for the run
 * that does not finish. Behaviour leans on Math.random to break ties and to
 * shake a pinned pedestrian loose, so every loop draws a slightly different
 * crowd, and one of them eventually strands somebody in a corner. Without a cap
 * the hero would then hold that frame for as long as the tab is open.
 */
export const MAX_TICKS = 3200;
