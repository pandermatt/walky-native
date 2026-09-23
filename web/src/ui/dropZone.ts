import { injectStyle } from './theme';

/**
 * The window-wide hint that a `.walky` file dropped here will open.
 *
 * A full-screen overlay rather than a target painted on the canvas: the drop is
 * legal anywhere on the page, so the affordance has to say so, and a dashed box
 * around the whole window is what says "here" without also claiming some
 * narrower area is the only place that counts.
 *
 * Shown on `dragenter` and hidden on `dragleave`/`drop` -- counted, since a drag
 * crossing from the window into a child element fires a leave and a re-enter
 * the browser does not distinguish from actually leaving.
 */
const DROP_ZONE_CSS = `
.wk-dropzone {
  position: fixed; inset: 0; z-index: 2147483647;
  display: none;
  align-items: center; justify-content: center;
  background: rgba(0, 0, 0, .35);
  pointer-events: none;
}
.wk-dropzone.wk-active { display: flex; }
.wk-dropzone .card {
  margin: 24px;
  padding: 28px 36px;
  border-radius: var(--wk-r-card);
  border: 2px dashed var(--wk-accent);
  background: var(--wk-card);
  color: var(--wk-ink);
  font: 600 17px/1.35 var(--wk-font-family);
  text-align: center;
}
`;

/**
 * Wires window-wide drag-and-drop of a `.walky` file to a handler, showing the
 * hint overlay for the duration of the drag.
 *
 * Anything dropped is handed to `onFile` unfiltered -- by extension or by MIME
 * type, a browser's own idea of either is unreliable, and mapFile.decodeMapFile
 * is the actual arbiter of whether the bytes are a Walky map. Refusing here on
 * a guess would only mean refusing a real one with the wrong extension.
 */
export function installMapFileDrop(onFile: (file: File) => void): void {
  injectStyle('dropzone', DROP_ZONE_CSS);

  const zone = document.createElement('div');
  zone.className = 'wk-dropzone';
  const card = document.createElement('div');
  card.className = 'card';
  card.textContent = 'Drop a .walky file to open it';
  zone.appendChild(card);
  document.body.appendChild(zone);

  let depth = 0;

  window.addEventListener('dragenter', (ev) => {
    if (!ev.dataTransfer?.types.includes('Files')) return;
    depth++;
    zone.classList.add('wk-active');
  });

  window.addEventListener('dragover', (ev) => {
    if (!ev.dataTransfer?.types.includes('Files')) return;
    // Only this stops the browser opening the file as a navigation instead.
    ev.preventDefault();
  });

  window.addEventListener('dragleave', () => {
    depth = Math.max(0, depth - 1);
    if (depth === 0) zone.classList.remove('wk-active');
  });

  window.addEventListener('drop', (ev) => {
    if (!ev.dataTransfer?.types.includes('Files')) return;
    ev.preventDefault();
    depth = 0;
    zone.classList.remove('wk-active');
    const file = ev.dataTransfer.files[0];
    if (file) onFile(file);
  });
}
