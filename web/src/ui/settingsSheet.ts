import type { Settings } from '../state/model';
import { MAP_FILE_MIME } from '../state/mapFile';
import { isAppShell, TOUCH } from './appShell';
import {
  SLIDERS, buildSlider, buildToggle, installControls,
  type ChangeHandler, type ToggleSpec,
} from './controls';
import { injectStyle } from './theme';

/**
 * The overlays gui/GUISettings could draw, which is all this group has ever
 * been: they are the ones you turn on to see why the crowd is doing what it is
 * doing, and they are no use to anyone who is not asking that. show3DEffect is
 * gone with the fake-3D.
 *
 * Arrival sound used to be the seventh row here, for no better reason than
 * being the seventh switch. It is a preference, not an overlay, so it has gone
 * to live with the pedestrians it belongs to.
 */
const DEBUG_TOGGLES: ToggleSpec[] = [
  { key: 'showConvexHull', label: 'Convex hulls' },
  { key: 'showConvexParts', label: 'Convex parts' },
  { key: 'showVisibleLines', label: 'Visibility rays' },
  { key: 'showLineToTarget', label: 'Path to goal' },
  { key: 'showPersonalSpace', label: 'Space rings' },
  { key: 'showDebug', label: 'Debug info' },
];

/** A pedestrian plops when it arrives; see plops.ts. */
const SOUND_TOGGLE: ToggleSpec = { key: 'sound', label: 'Arrival sound' };

/*
 * Two sliders, where there were seven.
 *
 * Speed, brush size, preferred space and the two text axes all left, because
 * the contextual panel already offers each of them at the moment it matters --
 * beside the tool in your hand, with the map still in front of you. A second
 * copy in here was the worse of the two: further away, and behind a modal that
 * covers the thing you are adjusting. These are the two nothing else offers.
 */
const PEDESTRIAN_SLIDERS: (keyof Settings)[] = ['pedestrianRadius'];
const DRAWING_SLIDERS: (keyof Settings)[] = ['borderThickness'];

/**
 * The settings, in Material Design 3's vocabulary rather than iOS's.
 *
 * The web app is not the iOS port, and Material -- not Human Interface
 * Guidelines -- is the design language built for the web: it already has a
 * defined type scale, a list component, and colour *roles* (primary,
 * surface, on-surface, outline) rather than one accent bolted onto a borrowed
 * grey. Walky's own colour stays Walky's colour throughout -- these roles are
 * seeded from the accent the path to a goal is drawn in (see theme.ts), not
 * from Material's baseline purple -- but the shapes, the type and the
 * elevation are Material's.
 *
 * Scoped deliberately to this one surface: `.wk-sheet` carries its own colour
 * tokens and overrides the switch/slider/button looks controls.ts defines,
 * rather than editing those globally. The toolbar and the per-tool contextual
 * panel elsewhere in the app are untouched -- this is a redesign of the
 * settings screen, not a reskin of the whole app.
 */
export const SHEET_CSS = `
/*
 * The settings, as one sheet on every device -- the mechanics below are
 * unchanged from before this rework: a <dialog> opened with showModal(), for
 * the dimmed backdrop, the focus trap, Escape, and the top layer that keeps
 * two from ever being open at once. Only the look is new.
 */
.wk-sheet {
  /*
   * Material 3's colour roles, seeded from Walky's own accent (--wk-accent /
   * --wk-accent-text, see theme.ts) rather than replaced by Material's
   * baseline purple. The neutral surfaces are Material's own reference
   * values for a light scheme -- a hand-tinted neutral toward a saturated
   * yellow-orange reads muddy, and the point of dynamic colour is that the
   * *primary* carries the brand, not that every grey does.
   */
  --md-primary: var(--wk-accent-text);
  --md-on-primary: #FFFFFF;
  --md-primary-container: var(--wk-accent-tint);
  --md-on-primary-container: var(--wk-accent-text);
  --md-surface: #FFFBFE;
  --md-surface-container: #F3EDF7;
  --md-surface-container-high: #ECE6F0;
  --md-on-surface: #1C1B1F;
  --md-on-surface-variant: #49454F;
  --md-outline: #79747E;
  --md-outline-variant: #C4C6D0;
  /* Material's own error role, for the one note that ever needs it. */
  --md-error: #B3261E;

  position: fixed; inset: 0; margin: auto;
  box-sizing: border-box; padding: 0; border: 0;
  width: min(420px, calc(100vw - 32px));
  max-width: none;
  height: fit-content;
  max-height: min(680px, 82vh);
  /* Material's extra-large shape, for a full-screen dialog's corners. */
  border-radius: 28px;
  overflow: hidden;
  background: var(--md-surface); color: var(--md-on-surface);
  font: 14px/1.43 var(--wk-font-family);
}
.wk-sheet, .wk-sheet * { box-sizing: border-box; }
.wk-sheet[open] { display: flex; flex-direction: column; }

/*
 * Presented and dismissed the way a sheet is -- see settingsSheet.ts's open()
 * and close() for why the exit is staged through .wk-leaving rather than
 * closed outright.
 */
.wk-sheet {
  opacity: 0; transform: scale(.96);
  transition:
    opacity .28s ease,
    transform .28s cubic-bezier(.32, .72, 0, 1),
    display .28s allow-discrete;
}
.wk-sheet[open] { opacity: 1; transform: scale(1); }
.wk-sheet[open].wk-leaving { opacity: 0; transform: scale(.96); }
@starting-style {
  .wk-sheet[open] { opacity: 0; transform: scale(.96); }
}
.wk-sheet::backdrop {
  background: rgba(0, 0, 0, 0);
  transition: background-color .28s ease, display .28s allow-discrete;
}
.wk-sheet[open]::backdrop { background: rgba(0, 0, 0, .4); }
.wk-sheet[open].wk-leaving::backdrop { background: rgba(0, 0, 0, 0); }
@starting-style {
  .wk-sheet[open]::backdrop { background: rgba(0, 0, 0, 0); }
}
@media (prefers-reduced-motion: reduce) {
  .wk-sheet, .wk-sheet::backdrop { transition: none; }
  .wk-sheet, .wk-sheet[open].wk-leaving { transform: none; opacity: 1; }
}

/*
 * The top app bar: Material's own chrome for a full-screen dialog -- a
 * leading close button, a title beside it, on the sheet's own surface tone.
 * iOS's oversized left-aligned display title is gone; a top app bar names
 * the screen without pretending to be its subject.
 */
.wk-sheet .head {
  flex: 0 0 auto;
  display: flex; align-items: center; gap: 4px;
  padding: calc(8px + env(safe-area-inset-top, 0px))
           calc(12px + env(safe-area-inset-right, 0px)) 8px
           calc(4px + env(safe-area-inset-left, 0px));
  background: var(--md-surface);
}
.wk-sheet .head h2 {
  margin: 0; padding: 0 4px;
  font-size: 22px; font-weight: 600; line-height: 28px; letter-spacing: 0;
}
.wk-sheet .head .close {
  flex: 0 0 auto;
  width: 40px; height: 40px; margin: 0;
  display: grid; place-items: center;
  border-radius: 999px; color: var(--md-on-surface-variant);
}
.wk-sheet .head .close:hover { background: color-mix(in srgb, var(--md-on-surface) 8%, transparent); }
.wk-sheet .head .close svg { width: 24px; height: 24px; }

.wk-sheet .body {
  flex: 1 1 auto; min-height: 0; overflow-y: auto;
  touch-action: pan-y; overscroll-behavior: contain;
  padding: 4px calc(16px + env(safe-area-inset-right, 0px))
           calc(24px + env(safe-area-inset-bottom, 0px))
           calc(16px + env(safe-area-inset-left, 0px));
}

/*
 * A section: Material's grouped-list convention -- a surface-container block,
 * rows divided by a hairline in --md-outline-variant, list-item metrics
 * throughout (a 56px row is Material's one-line list item).
 */
.wk-sheet .group {
  background: var(--md-surface-container); border-radius: 16px;
  margin-bottom: 8px; overflow: hidden;
}
.wk-sheet .group > * { position: relative; margin: 0; padding: 0 16px; min-height: 56px; }
.wk-sheet .group > * + *::before {
  content: ''; position: absolute; left: 16px; right: 16px; top: 0;
  height: 1px; background: var(--md-outline-variant);
}
.wk-sheet .row { min-height: 56px; display: flex; align-items: center; }

/* Material's label-large: what names a group of list items. */
.wk-sheet .group-title {
  margin: 20px 0 8px; padding: 0 16px;
  font-size: 12px; font-weight: 600; line-height: 16px; letter-spacing: .5px;
  text-transform: uppercase;
  color: var(--md-primary);
}
.wk-sheet .body > .group-title:first-child { margin-top: 8px; }

/* Material's body-medium, in on-surface-variant: a sentence under a group. */
.wk-sheet .group:has(+ .note) { margin-bottom: 4px; }
.wk-sheet .note {
  margin: 0 0 8px; padding: 0 16px;
  font-size: 12px; line-height: 16px; color: var(--md-on-surface-variant); min-height: 16px;
}
.wk-sheet .note + .group-title { margin-top: 4px; }
.wk-sheet .note.error { color: var(--md-error); }

/*
 * Buttons: Material's text-button and filled-button roles. A row that acts --
 * "Open…", "Copy link" -- reads as a Material list item whose whole row is
 * the tap target, in the primary colour a text button wears.
 */
.wk-sheet button.row {
  width: 100%; padding: 0 16px; border: 0; background: none;
  /* controls.ts's .row is row-reverse, for a toggle's switch; a lone label in
     a reversed row still sits at its start, which is the row's right edge.
     This one is a button with nothing to reverse against. */
  flex-direction: row; justify-content: flex-start;
  font: 500 14px/20px var(--wk-font-family); letter-spacing: .1px;
  color: var(--md-primary); text-align: left; cursor: pointer;
}
.wk-sheet button.row:active { background: color-mix(in srgb, var(--md-primary) 12%, transparent); }
.wk-sheet button.row:focus-visible {
  outline: 2px solid var(--md-primary); outline-offset: -2px;
}
.wk-sheet button.row:disabled { color: var(--md-outline); cursor: default; }

/* The head's own close button, and Done -- both Material icon/text buttons. */
.wk-sheet .head button:focus-visible {
  outline: 2px solid var(--md-primary); outline-offset: 2px;
}

/*
 * A control row's own label: Material's body-large, the type a one-line list
 * item's text wears.
 */
.wk-sheet .row label { flex: 1; font-size: 16px; line-height: 24px; color: var(--md-on-surface); }

/*
 * The switch, Material's shape rather than iOS's: an outlined track that
 * fills to --md-primary when on, and a thumb that grows to meet it -- the
 * detail that reads as "Material" from across a room.
 */
.wk-sheet input[type=checkbox] {
  appearance: none; -webkit-appearance: none;
  flex: 0 0 auto; width: 52px; height: 32px; margin: 0; padding: 0;
  border-radius: 999px; background: var(--md-surface-container-high);
  box-shadow: inset 0 0 0 2px var(--md-outline);
  cursor: pointer; transition: background-color .15s ease, box-shadow .15s ease;
  position: relative;
}
.wk-sheet input[type=checkbox]::after {
  content: ''; position: absolute; top: 50%; left: 6px;
  width: 16px; height: 16px; margin-top: -8px;
  border-radius: 50%; background: var(--md-outline);
  transition: transform .15s ease, width .15s ease, height .15s ease,
    margin-top .15s ease, left .15s ease, background-color .15s ease;
}
.wk-sheet input[type=checkbox]:checked {
  background: var(--md-primary); box-shadow: none;
}
.wk-sheet input[type=checkbox]:checked::after {
  left: 6px; width: 24px; height: 24px; margin-top: -12px;
  background: var(--md-on-primary);
  transform: translateX(20px);
}
.wk-sheet input[type=checkbox]:focus-visible {
  outline: 2px solid var(--md-primary); outline-offset: 2px;
}

/* The slider: a filled --md-primary track and a taller Material-sized thumb. */
.wk-sheet input[type=range] {
  appearance: none; -webkit-appearance: none;
  width: 100%; height: 28px; margin: 0; background: none; cursor: pointer;
}
.wk-sheet input[type=range]:focus-visible {
  outline: 2px solid var(--md-primary); outline-offset: 2px;
}
.wk-sheet input[type=range]::-webkit-slider-runnable-track {
  height: 4px; border-radius: 2px;
  background: linear-gradient(
    to right,
    var(--md-primary) 0 var(--fill, 0%),
    var(--md-surface-container-high) var(--fill, 0%) 100%
  );
  box-shadow: inset 0 0 0 1px var(--md-outline-variant);
}
.wk-sheet input[type=range]::-webkit-slider-thumb {
  appearance: none; -webkit-appearance: none;
  width: 20px; height: 20px; margin-top: -8px;
  border-radius: 50%; background: var(--md-primary);
  box-shadow: 0 1px 2px rgba(0, 0, 0, .2);
}
.wk-sheet input[type=range]::-moz-range-track {
  height: 4px; border-radius: 2px; background: var(--md-surface-container-high);
}
.wk-sheet input[type=range]::-moz-range-progress {
  height: 4px; border-radius: 2px; background: var(--md-primary);
}
.wk-sheet input[type=range]::-moz-range-thumb {
  width: 20px; height: 20px; border: 0; border-radius: 50%; background: var(--md-primary);
  box-shadow: 0 1px 2px rgba(0, 0, 0, .2);
}
/* A slider is taller than a one-line row, so it takes its own vertical room
   rather than the fixed 56px a row centres its content in. */
.wk-sheet .group > .slider { min-height: 0; padding: 12px 16px; }
.wk-sheet .slider .top { color: var(--md-on-surface); font-size: 16px; }
.wk-sheet .slider .val { color: var(--md-on-surface-variant); }

@media (prefers-reduced-motion: reduce) {
  .wk-sheet input[type=checkbox],
  .wk-sheet input[type=checkbox]::after { transition: none; }
}

/*
 * The name at the foot of it, Material's body/label pairing instead of iOS's
 * footnote-under-a-name arrangement.
 */
.wk-sheet .about {
  padding: 24px 16px 0; text-align: center; color: var(--md-on-surface-variant);
}
.wk-sheet .about .name {
  margin: 0; font-size: 16px; font-weight: 600; color: var(--md-on-surface);
}
.wk-sheet .about .version { margin: 2px 0 0; font-size: 12px; }
.wk-sheet .about .credit { margin: 10px 0 0; font-size: 12px; line-height: 1.5; }
.wk-sheet .about .legal { margin: 14px 0 0; font-size: 12px; }
.wk-sheet .about a { color: var(--md-primary); text-decoration: none; }
.wk-sheet .about .credit a { text-decoration: underline; white-space: nowrap; }
.wk-sheet .about a:focus-visible {
  outline: 2px solid var(--md-primary); outline-offset: 2px;
  border-radius: 3px;
}

/*
 * Installed on a phone, the sheet is the screen: there is no browser chrome
 * around it to leave room for, and a card floating in the middle of a phone
 * would be a card with nothing behind it.
 */
@media ${TOUCH} {
  html[data-standalone] .wk-sheet {
    inset: 0; margin: 0;
    width: 100%; height: 100%; max-height: none;
    border-radius: 0;
    opacity: 1; transform: translateY(100%);
    transition:
      transform .32s cubic-bezier(.32, .72, 0, 1),
      display .32s allow-discrete;
  }
  html[data-standalone] .wk-sheet[open] { transform: translateY(0); }
  html[data-standalone] .wk-sheet[open].wk-leaving { transform: translateY(100%); }
  @starting-style {
    html[data-standalone] .wk-sheet[open] { transform: translateY(100%); }
  }
  @media (prefers-reduced-motion: reduce) {
    html[data-standalone] .wk-sheet { transition: none; }
    html[data-standalone] .wk-sheet,
    html[data-standalone] .wk-sheet[open].wk-leaving { transform: none; }
  }
}
`;

/** Distinguishes our history entry from anyone else's; see open() and close(). */
let sequence = 0;

/**
 * An outbound link for the footer.
 *
 * A new tab rather than this one, because leaving is not what someone reading
 * the credits asked for: the simulation they were running is in this tab, and a
 * scenario lives in the URL, so navigating away is how you lose it. The `rel` is
 * belt and braces -- `target="_blank"` implies `noopener` in every engine that
 * ships today, and `_headers` already sends `Referrer-Policy: no-referrer` -- but
 * it costs nothing and does not depend on either staying true.
 */
function link(text: string, href: string): HTMLAnchorElement {
  const a = document.createElement('a');
  a.href = href;
  a.textContent = text;
  a.target = '_blank';
  a.rel = 'noopener noreferrer';
  return a;
}

/** Material's "close" glyph -- an X, drawn rather than fetched, so the sheet needs no icon asset. */
function closeIcon(): SVGSVGElement {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 -960 960 960');
  svg.setAttribute('fill', 'currentColor');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', 'm256-200-56-56 224-224-224-224 56-56 224 224 224-224 56 56-224 224 224 224-56 56-224-224-224 224Z');
  svg.appendChild(path);
  return svg;
}

/**
 * The settings, as a modal sheet.
 *
 * showModal() is doing most of the work here. It puts the sheet in the top
 * layer, dims what is behind it, traps focus inside it and makes the rest of the
 * app inert -- so "never two open at once" stops being something the app tries
 * to arrange and becomes something it cannot violate. The toolbar is
 * untappable while the sheet is up, which is also what retires the old race
 * between a re-open and an in-flight history.back().
 */
export class SettingsSheet {
  private root: HTMLDialogElement;
  private syncers: (() => void)[] = [];
  /** The footnote under the Map group: whichever of Open/Save/Copy link answered last. */
  private mapNote: HTMLParagraphElement;
  /** The footnote under the Show group's "Copy map to clipboard". */
  private debugNote: HTMLParagraphElement;
  private fileInput: HTMLInputElement;
  /**
   * The id of the history entry we pushed, or null when we have none.
   *
   * A token rather than a flag: a popstate carries the state of the entry it
   * landed on, so comparing it against ours answers "is our entry still the
   * current one" exactly, where a boolean could only say that one existed.
   */
  private entry: number | null = null;
  /** Set while the sheet is animating out; see close(). */
  private leaving = false;
  /** Whatever had focus when the sheet opened, to give it back on the way out. */
  private opener: HTMLElement | null = null;
  private exitTimer = 0;

  constructor(
    private settings: Settings,
    onChange: ChangeHandler,
    private onCopyLink: () => Promise<string>,
    private onCopyMap: () => Promise<string>,
    /** Reads a `.walky` file's bytes and replaces the map with it, or throws. */
    private onImportFile: (bytes: Uint8Array) => Promise<string>,
    /** The map as `.walky` bytes, ready to save, with a name to suggest for it. */
    private onExportFile: () => Promise<{ bytes: Uint8Array; name: string }>,
    /** Told whenever the sheet opens or closes, by whatever route. */
    private onOpened: () => void = () => {},
    private onClosed: () => void = () => {},
  ) {
    installControls();
    injectStyle('sheet', SHEET_CSS);

    this.root = document.createElement('dialog');
    this.root.className = 'wk-panel wk-sheet';

    const head = document.createElement('header');
    head.className = 'head';
    const done = document.createElement('button');
    done.type = 'button';
    done.className = 'close';
    done.setAttribute('aria-label', 'Close settings');
    done.appendChild(closeIcon());
    done.addEventListener('click', () => this.close());
    const title = document.createElement('h2');
    title.id = 'wk-sheet-title';
    title.textContent = 'Settings';
    this.root.setAttribute('aria-labelledby', title.id);
    head.append(done, title);

    const body = document.createElement('div');
    body.className = 'body';
    this.root.append(head, body);

    /*
     * Each run of controls is a grouped card under its name, the way a
     * Material list groups itself -- the container's own shape says what a
     * dividing rule used to say, and the name says which of these lists you
     * are in.
     */
    let groups = 0;
    const group = (title: string) => {
      const heading = document.createElement('h3');
      heading.className = 'group-title';
      heading.id = `wk-sheet-group-${++groups}`;
      heading.textContent = title;
      const section = document.createElement('section');
      section.className = 'group';
      section.setAttribute('aria-labelledby', heading.id);
      body.append(heading, section);
      return section;
    };

    const sliders = (into: HTMLElement, keys: (keyof Settings)[]) => {
      for (const key of keys) {
        const spec = SLIDERS[key as string];
        if (!spec) continue;
        const { el, sync } = buildSlider(spec, settings, onChange);
        this.syncers.push(sync);
        into.appendChild(el);
      }
    };

    const toggle = (into: HTMLElement, spec: ToggleSpec) => {
      const { el, sync } = buildToggle(spec, settings, onChange);
      this.syncers.push(sync);
      into.appendChild(el);
    };

    const note = (className = 'note') => {
      const el = document.createElement('p');
      el.className = className;
      el.setAttribute('role', 'status');
      return el;
    };

    /**
     * A row button that puts something in front of the user and says what
     * happened underneath -- "Copy link to this map" and "Copy map to
     * clipboard" both work this way already; Open and Save use the same shape.
     *
     * `busy` is shared across every row this button is built for -- rather than
     * per button -- because it is the async work that is slow, and only one of
     * these can be running at a time regardless of which row started it.
     */
    let busy = false;
    const action = (label: string, into: HTMLElement, into2: HTMLParagraphElement, run: () => Promise<string>) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'row';
      button.textContent = label;
      button.addEventListener('click', async () => {
        if (busy) return;
        busy = true;
        button.disabled = true;
        into2.classList.remove('error');
        try {
          into2.textContent = await run();
        } catch (err) {
          into2.classList.add('error');
          into2.textContent = err instanceof Error ? err.message : 'That could not be read.';
        } finally {
          busy = false;
          button.disabled = false;
        }
      });
      into.appendChild(button);
      return button;
    };

    this.mapNote = note();
    this.debugNote = note();

    // A hidden file input, triggered by the "Open…" row -- the platform's own
    // picker, which is what "Open" means on every OS this runs on.
    this.fileInput = document.createElement('input');
    this.fileInput.type = 'file';
    this.fileInput.accept = '.walky';
    this.fileInput.hidden = true;
    this.fileInput.addEventListener('change', () => void this.openChosenFile());
    this.root.appendChild(this.fileInput);

    /*
     * Map, first: getting a map in or out is the one thing in here you come
     * to Settings specifically to do -- everything else is a value you adjust
     * while you are already looking at something. Opening, saving and sharing
     * are one category -- the map's own coming and going -- so they share one
     * group and one footnote rather than the three each used to answer to.
     */
    const mapGroup = group('Map');
    action('Open…', mapGroup, this.mapNote, () => this.openFile());
    action('Save as .walky…', mapGroup, this.mapNote, () => this.saveFile());
    action('Copy link to this map', mapGroup, this.mapNote, () => this.onCopyLink());
    body.appendChild(this.mapNote);
    body.appendChild(note('note'));
    const hint = body.lastElementChild as HTMLParagraphElement;
    hint.textContent = 'You can also drag a .walky file onto the map to open it.';

    // The crowd itself: how big one of them is, and whether you hear it arrive.
    const pedestrians = group('Crowd');
    sliders(pedestrians, PEDESTRIAN_SLIDERS);
    toggle(pedestrians, SOUND_TOGGLE);

    sliders(group('Drawing'), DRAWING_SLIDERS);

    const debug = group('Show');
    for (const spec of DEBUG_TOGGLES) toggle(debug, spec);
    action('Copy map to clipboard', debug, this.debugNote, () => this.onCopyMap());
    body.appendChild(this.debugNote);

    body.appendChild(this.buildAbout());

    // The sheet is a modal in the top layer, so it belongs to the document
    // rather than to the panels column it used to share with the contextual
    // panel. Out of #stage it also means a click on it can never reach the
    // canvas tools, which is what swallowPointerEvents was for.
    document.body.appendChild(this.root);

    // Escape, and the back gesture on Android, both arrive as `cancel`. Taking
    // it over means every way out leaves by the same door -- otherwise the
    // browser would close the dialog behind our back and our history entry
    // would be stranded on the stack.
    this.root.addEventListener('cancel', (ev) => {
      ev.preventDefault();
      this.close();
    });

    // A click on the backdrop. The dialog *is* the card, so "did you hit the
    // element" is not the question -- the question is whether the point was
    // inside its box, which is false only for the backdrop. Guarding on the
    // target first keeps a keyboard-activated click, which reports (0, 0), from
    // reading as a click in the far corner.
    this.root.addEventListener('click', (ev) => {
      if (ev.target !== this.root) return;
      const box = this.root.getBoundingClientRect();
      const inside = ev.clientX >= box.left && ev.clientX <= box.right
        && ev.clientY >= box.top && ev.clientY <= box.bottom;
      if (!inside) this.close();
    });

    // The back gesture is the way out an installed app offers besides the
    // button, and it needs an entry of ours to pop. Landing anywhere that is not
    // our entry means the sheet has been left.
    window.addEventListener('popstate', () => {
      if (this.entry === null) return;
      if (this.currentEntry() === this.entry) return;
      this.entry = null;
      this.close();
    });
  }

  /** The `walkySheet` token of the entry the browser is currently on, if any. */
  private currentEntry(): number | null {
    const state = history.state as { walkySheet?: number } | null;
    return typeof state?.walkySheet === 'number' ? state.walkySheet : null;
  }

  /** "Open…": hands off to the platform's own file picker. */
  private openFile(): Promise<string> {
    this.fileInput.value = '';
    this.fileInput.click();
    // The row's own note is answered by openChosenFile once a file is picked
    // (or not, if the picker is dismissed) -- there is nothing to say yet.
    return Promise.resolve('');
  }

  /** The file picker's answer, once there is one. */
  private async openChosenFile(): Promise<void> {
    const file = this.fileInput.files?.[0];
    if (!file) return;
    this.mapNote.classList.remove('error');
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      this.mapNote.textContent = await this.onImportFile(bytes);
      // Opening replaces the whole map; seeing it happen is worth more than
      // reading a note about it, so the sheet steps out of the way.
      this.close();
    } catch (err) {
      this.mapNote.classList.add('error');
      this.mapNote.textContent = err instanceof Error ? err.message : 'That file could not be read.';
    }
  }

  /** "Save as .walky…": a Blob, handed to the browser's own download. */
  private async saveFile(): Promise<string> {
    const { bytes, name } = await this.onExportFile();
    const blob = new Blob([bytes as BlobPart], { type: MAP_FILE_MIME });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${name}.walky`;
    a.click();
    URL.revokeObjectURL(a.href);
    return `Saved as ${name}.walky`;
  }

  private buildAbout(): HTMLElement {
    const about = document.createElement('footer');
    about.className = 'about';

    const name = document.createElement('p');
    name.className = 'name';
    name.textContent = 'Walky';

    const version = document.createElement('p');
    version.className = 'version';
    version.textContent = `Version ${__WALKY_APP_VERSION__}`;

    const credit = document.createElement('p');
    credit.className = 'credit';
    credit.append(
      'A revival of the 2016 original by ',
      link('Pascal Andermatt', 'https://pandermatt.ch/'),
      ' and ',
      link('Jan Huber', 'https://www.jan-huber.ch'),
      '.',
    );

    const legal = document.createElement('p');
    legal.className = 'legal';
    legal.append(link('Privacy Policy', 'https://pandermatt.ch/privacy-policy/'));

    about.append(name, version, credit, legal);
    return about;
  }

  open(): void {
    // Only reachable through window.__walky: while the sheet is leaving it is
    // still modal, so the toolbar that would ask for it is inert. Cutting the
    // exit short is nonetheless the right answer to being asked.
    if (this.leaving) this.finishExit();
    if (this.visible) return;
    this.opener = document.activeElement as HTMLElement | null;
    this.root.showModal();
    this.sync();
    if (isAppShell()) {
      // Same URL, so this is a history entry and not navigation: there is one
      // page here, and going back from it lands where you already are.
      this.entry = ++sequence;
      history.pushState({ walkySheet: this.entry }, '');
    }
    this.onOpened();
  }

  /**
   * The one way out, whichever route asked for it: Done, Escape, the backdrop,
   * or the back gesture.
   *
   * It starts the exit rather than finishing it -- the dialog stays open, and
   * therefore in the top layer, for as long as it is still moving. Everything
   * that is not the animation happens now, though: the button un-presses on the
   * press, not a third of a second later.
   */
  close(): void {
    if (!this.visible || this.leaving) return;
    this.leaving = true;
    const entry = this.entry;
    this.entry = null;
    this.root.classList.add('wk-leaving');
    this.onClosed();
    // Only when the entry we pushed is still the one the browser is on. Popping
    // otherwise would take a step someone else owns -- and when the pop is what
    // closed us in the first place, there is nothing left to unwind.
    if (entry !== null && this.currentEntry() === entry) history.back();

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      this.finishExit();
      return;
    }
    // transitionend is the signal; the timer is the promise that one arrives at
    // all, since an engine that ignored the transition would otherwise leave the
    // sheet open forever. The target check is because a control inside the sheet
    // has transitions of its own, and they bubble.
    this.root.addEventListener('transitionend', this.onExitEnd);
    this.exitTimer = window.setTimeout(() => this.finishExit(), 500);
  }

  private onExitEnd = (ev: TransitionEvent): void => {
    if (ev.target !== this.root) return;
    this.finishExit();
  };

  private finishExit(): void {
    if (!this.leaving) return;
    this.leaving = false;
    window.clearTimeout(this.exitTimer);
    this.root.removeEventListener('transitionend', this.onExitEnd);
    this.root.classList.remove('wk-leaving');
    this.mapNote.textContent = '';
    this.mapNote.classList.remove('error');
    this.debugNote.textContent = '';
    this.root.close();
    // Only now: a modal dialog holds focus, so handing it back before the close
    // would simply be refused.
    if (this.opener?.isConnected) this.opener.focus({ preventScroll: true });
    this.opener = null;
  }

  /** True from the moment it opens until it has finished animating away. */
  get visible(): boolean { return this.root.open; }

  /** Pull displayed values back from settings, after a change made elsewhere. */
  sync(): void {
    void this.settings;
    for (const s of this.syncers) s();
  }
}
