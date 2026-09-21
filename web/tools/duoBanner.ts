/**
 * Draws the iPhone Duo announcement card: public/images/duo-banner.png, 1200x630.
 *
 * Run with:  npm run dev  ->  open /tools/duoBanner.html  ->  Save
 *
 * 1200x630 because that is the one rectangle every timeline crops least badly:
 * X, LinkedIn, Facebook, Mastodon and Slack all read the same `og:image`, and a
 * 1.91:1 card is what they expect. Nothing important goes in the outer 5%,
 * because some of them trim it and a preview is glanced at two inches wide.
 *
 * WHY A CANVAS IN A BROWSER, and not a node script: the same reason
 * tools/ogImage.ts gives at length. The app's face is Google Sans Flex, which
 * ships as woff2, which fontconfig cannot read -- so a rasteriser falls through
 * to whatever the machine has and the wordmark goes out in the wrong face. A
 * browser loads the real file and `fillText` draws with it.
 *
 * WHY A PHOTOGRAPH, where og.png draws a real simulation frame: the subject
 * here is a shape, not a map. What is being announced is that the app knows
 * what to do when the screen bends, and no amount of rendered crowd says that.
 * The picture has to show a phone that is physically folded.
 */
import { BACKGROUND, WHITE, toCss, withAlpha } from '../src/palette.ts';

const WIDTH = 1200;
const HEIGHT = 630;

/** The app's stack, from --wk-font-family in ui/theme.ts. */
const FAMILY = "'Google Sans Flex', system-ui, -apple-system, sans-serif";

/**
 * The hand, bled off the bottom.
 *
 * Drawn at the card's full height, which crops the forearm and keeps the phone
 * -- the only part anyone reads at preview size. The source is 1554x1746, so
 * height 630 makes it 561 wide; that is arithmetic rather than a number picked
 * to look right.
 *
 * Nudged down by 22 so the bleed is off one edge rather than two. Flush at the
 * top, the phone's rounded corner was shaved by a few pixels, which reads as a
 * mistake; falling off the bottom only reads as a crop.
 */
const PHOTO = '/images/duo-in-hand.webp';
const PHOTO_W = 1554;
const PHOTO_H = 1746;

function drawPhoto(ctx: CanvasRenderingContext2D, image: HTMLImageElement): void {
  const height = HEIGHT;
  const width = Math.round((PHOTO_W / PHOTO_H) * height);
  ctx.drawImage(image, WIDTH - width - 40, 22, width, height);
}

/**
 * The words, left, on the half the photograph leaves.
 *
 * Two lines and no third. A card is read in the half second before somebody
 * scrolls past it, and the second line already says the only thing this
 * release is: the app is ready for a phone that folds.
 */
function drawWords(ctx: CanvasRenderingContext2D): void {
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';

  ctx.font = `500 22px ${FAMILY}`;
  ctx.letterSpacing = '2px';
  ctx.fillStyle = withAlpha(WHITE, 0.55);
  ctx.fillText('PEDESTRIAN SIMULATOR', 72, 250);

  // The weights are the face's own axis -- it is variable from 100 to 1000 --
  // so 700 is a real cut rather than a browser thickening 400 on its own.
  ctx.font = `700 92px ${FAMILY}`;
  ctx.letterSpacing = '-2px';
  ctx.fillStyle = toCss(WHITE);
  ctx.fillText('Walky.', 72, 350);

  ctx.font = `400 46px ${FAMILY}`;
  ctx.letterSpacing = '-0.5px';
  ctx.fillStyle = withAlpha(WHITE, 0.78);
  ctx.fillText('Ready for iPhone Duo.', 72, 412);

  ctx.font = `400 25px ${FAMILY}`;
  ctx.letterSpacing = '0px';
  ctx.fillStyle = withAlpha(WHITE, 0.5);
  ctx.fillText('walky.ch', 72, 470);
}

/** The path build/ogWriter.ts listens on. A mismatch shows up as a 404 on Save. */
const ENDPOINT = '/__walky/duo-banner.png';

function toBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('no blob'))), 'image/png');
  });
}

/**
 * Loads the app's own typeface into this page.
 *
 * Awaited rather than fired off, and allowed to throw: a canvas whose font has
 * not arrived draws in the fallback face without a word of complaint, which is
 * the exact failure this page exists to end.
 */
async function loadFont(): Promise<void> {
  const face = new FontFace(
    'Google Sans Flex',
    "url('/fonts/google-sans-flex-latin.woff2') format('woff2')",
    { weight: '100 1000' },
  );
  await face.load();
  document.fonts.add(face);
}

/**
 * Awaited, and allowed to throw, for the same reason the font is: a `drawImage`
 * of an image that has not decoded draws nothing at all, silently, and the card
 * would go out as words on an empty rectangle.
 */
function loadPhoto(): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`could not load ${PHOTO}`));
    image.src = PHOTO;
  });
}

const canvas = document.querySelector<HTMLCanvasElement>('#card')!;
const saveButton = document.querySelector<HTMLButtonElement>('#save')!;
const status = document.querySelector<HTMLParagraphElement>('#status')!;

async function main(): Promise<void> {
  const ctx = canvas.getContext('2d')!;
  const [, photo] = await Promise.all([loadFont(), loadPhoto()]);

  ctx.fillStyle = toCss(BACKGROUND);
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  drawPhoto(ctx, photo);
  drawWords(ctx);

  status.textContent = 'Drawn.';
  saveButton.disabled = false;

  saveButton.addEventListener('click', async () => {
    saveButton.disabled = true;
    const response = await fetch(ENDPOINT, { method: 'POST', body: await toBlob(canvas) });
    status.textContent = response.ok
      ? `Saved: ${await response.text()}`
      : `Save failed: ${response.status} ${await response.text()}`;
    saveButton.disabled = false;
  });
}

main().catch((error: unknown) => {
  status.textContent = String(error);
});
