/**
 * The landing page: a scroll reveal, one live simulation, and
 * one redirect that keeps every share link ever pasted anywhere working.
 *
 * None of the app is imported here beyond the model the hero runs -- no deck.gl,
 * no App, no chrome. The renderer is the expensive half of the bundle and this
 * page draws a hundred circles on a 2D context, so it pays for the simulation
 * and nothing else.
 */
import './landing.css';
import { unpackRgb } from '../sim/agents';
import { toCss, WHITE } from '../palette';
import { buildHeroScene, FRAME, MAX_TICKS, RADIUS, STILL_TICKS } from './heroScene';
import { forwardTarget } from './forward';
import { checkStoreLinks } from './store';

/* ─────────────────────────────────────────────────────────────────────────────
   Share links that predate the move
   ───────────────────────────────────────────────────────────────────────────── */

const forward = forwardTarget(location.hash);
if (forward) {
  // replace, not assign: the landing page should not sit in the back stack
  // between the link somebody clicked and the map it opens.
  location.replace(forward);
}

/* ─────────────────────────────────────────────────────────────────────────────
   Reveal
   ───────────────────────────────────────────────────────────────────────────── */

/** Fades each section in as it arrives. Once per element -- it is not a toy. */
function installReveal(): void {
  const targets = document.querySelectorAll('.reveal');
  if (!('IntersectionObserver' in window)) {
    targets.forEach((el) => el.classList.add('is-visible'));
    return;
  }
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    },
    { rootMargin: '0px 0px -10% 0px' },
  );
  targets.forEach((el) => observer.observe(el));
}

/* ─────────────────────────────────────────────────────────────────────────────
   The hero simulation
   ───────────────────────────────────────────────────────────────────────────── */

/**
 * Hairlines that read at full size disappear in a hero scaled to a phone, so
 * the white ring around a pedestrian is lifted by this much. It is the one place
 * the drawing departs from what the app draws, and it is about being looked at
 * small -- the same allowance ogImage.ts makes for a link preview.
 */
const STROKE_BOOST = 1.5;

/**
 * How long the crowd is left standing at the goals before the scene restarts.
 *
 * A loop that cuts the instant the last dot blackens reads as a glitch; a beat
 * of stillness reads as an ending. Frames, at whatever rate the display runs --
 * about a second and a half at 60Hz, and gracefully shorter on a slower one.
 */
const HOLD_FRAMES = 90;

/**
 * The crowd, drawn the way render/scene.ts draws it with every diagnostic off:
 * wall polygons filled, then a pedestrian as a dot in its goal's colour inside a
 * white ring.
 */
function installHero(): void {
  const canvas = document.querySelector<HTMLCanvasElement>('[data-hero-canvas]');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  let scene = buildHeroScene();
  let ticks = 0;
  let held = 0;

  /**
   * Sizes the backing store to the device's pixels rather than to CSS ones, so
   * a hundred circles on a 3x display are circles rather than a mosaic.
   */
  const resize = () => {
    const rect = canvas.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
  };

  const draw = () => {
    const { width, height } = canvas;
    if (width === 0 || height === 0) return;

    // Cover, not contain: the frame is a window onto a room, and letterboxing it
    // would put two grey bars inside a card that is already a rounded rectangle.
    const scale = Math.max(width / FRAME.w, height / FRAME.h);
    const offsetX = (width - FRAME.w * scale) / 2;
    const offsetY = (height - FRAME.h * scale) / 2;

    // The app's ground, derived rather than picked; drawn rather than left to
    // the CSS behind, so a resize between frames never shows the card's corner.
    ctx.fillStyle = '#1E1E1E';
    ctx.fillRect(0, 0, width, height);

    ctx.save();
    ctx.translate(offsetX, offsetY);
    ctx.scale(scale, scale);
    ctx.translate(-FRAME.x, -FRAME.y);

    for (const wall of scene.walls) {
      ctx.fillStyle = toCss(wall.color);
      for (const polygon of wall.polygons) {
        ctx.beginPath();
        polygon.forEach(([x, y], i) => (i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)));
        ctx.closePath();
        ctx.fill();
      }
    }

    const { agents } = scene;
    ctx.strokeStyle = toCss(WHITE);
    ctx.lineWidth = STROKE_BOOST / scale;
    for (let i = 0; i < agents.count; i++) {
      ctx.fillStyle = toCss(unpackRgb(agents.color[i]));
      ctx.beginPath();
      ctx.arc(agents.x[i], agents.y[i], RADIUS, 0, 2 * Math.PI);
      ctx.fill();
      ctx.stroke();
    }

    ctx.restore();
  };

  // Redrawn as well as resized: changing the backing store's dimensions clears
  // it, so a card that is not redrawn goes black the moment the window moves.
  // In the animated case the next frame would repaint it anyway, but not while
  // the hero is scrolled out of view or the crowd is being held at the end.
  new ResizeObserver(() => { resize(); draw(); }).observe(canvas);
  resize();

  // Somebody who has asked for no motion gets the scene held at the frame the
  // animation passes through, not a blank card and not a moving one.
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    for (let t = 0; t < STILL_TICKS; t++) scene.step();
    draw();
    return;
  }

  // Paused while the hero is off screen. A landing page that keeps a core busy
  // stepping a crowd nobody is looking at is a laptop fan in the footer.
  let onScreen = true;
  new IntersectionObserver(
    ([entry]) => { onScreen = entry.isIntersecting; },
    { threshold: 0 },
  ).observe(canvas);

  // Never cancelled: the loop lives as long as the page does, and the two gates
  // below already stop it doing any work when nobody is watching.
  const tick = () => {
    requestAnimationFrame(tick);
    if (!onScreen || document.hidden) return;

    if (scene.agents.allArrived || ticks >= MAX_TICKS) {
      // The hold, then a fresh crowd back at the start line. A loop that cuts
      // the instant the last dot blackens reads as a glitch.
      if (++held > HOLD_FRAMES) {
        scene = buildHeroScene();
        ticks = 0;
        held = 0;
      }
    } else {
      scene.step();
      ticks++;
    }
    draw();
  };
  requestAnimationFrame(tick);
}

/* ───────────────────────────────────────────────────────────────────────────── */

if (!forward) {
  checkStoreLinks();
  installReveal();
  installHero();
}
