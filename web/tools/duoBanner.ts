/**
 * Draws the iPhone Duo announcement card: public/images/duo-banner.png, 3840x2160.
 *
 * Run with:  npm run dev  ->  open /tools/duoBanner.html  ->  Save
 *
 * 16:9 at 4K, where this started as a 1200x630 `og:image`. Those are two
 * different jobs and this is now the second one: a picture somebody posts, and
 * that a timeline will re-encode, a retina display will show at 2x and a slide
 * may put on a wall. 1.91:1 is the ratio a link preview wants and nothing else
 * does; 16:9 is what every other surface is shaped like. Nothing important goes
 * in the outer 5% either way, because some of them trim it and most people
 * glance at it two inches wide.
 *
 * The composition is written in 1200x675 units and the context is scaled on the
 * way out, so every number below is still a number you can hold in your head
 * next to a 1200-wide card. SCALE is the only place the resolution lives.
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
 * The picture has to show a phone that is physically folded -- and this one
 * shows the half of it that is hardest to explain in words: closed, on the
 * outer display, with the bar stood up the side where the system put it.
 */
import { BACKGROUND, WHITE, toCss, withAlpha } from '../src/palette.ts';

/** Design units. Everything below is written in these. */
const WIDTH = 1200;
const HEIGHT = 675;

/**
 * Design units to output pixels. 3.2 makes it exactly 3840x2160.
 *
 * A whole-number-ish factor rather than a canvas authored at 4K: text hinting,
 * letter spacing and the 40-unit margins were all chosen at this size, and
 * rewriting them three times larger is three chances to get one wrong.
 */
const SCALE = 3.2;

/** The app's stack, from --wk-font-family in ui/theme.ts. */
const FAMILY = "'Google Sans Flex', system-ui, -apple-system, sans-serif";

/**
 * The hand, bled off the bottom.
 *
 * Drawn at the card's full height and pushed down by TOP_INSET, so the bleed is
 * off one edge rather than two -- flush at the top, the phone's rounded corner
 * gets shaved by a few pixels, which reads as a mistake, where falling off the
 * bottom only reads as a crop. The source is 1554x1746, so the width is
 * arithmetic rather than a number picked to look right.
 */
const PHOTO = '/images/duo-in-hand.webp';
const PHOTO_W = 1554;
const PHOTO_H = 1746;
const TOP_INSET = 54;

function drawPhoto(ctx: CanvasRenderingContext2D, image: HTMLImageElement): void {
  const height = HEIGHT;
  const width = Math.round((PHOTO_W / PHOTO_H) * height);
  ctx.drawImage(image, WIDTH - width - 40, TOP_INSET, width, height);
}

/** Left margin for every line of type, and the left edge of the button. */
const MARGIN = 72;

/**
 * The words, left, on the half the photograph leaves.
 *
 * Two lines and no third. A card is read in the half second before somebody
 * scrolls past it, and the second line already says the only thing this
 * release is: the app is ready for a phone that folds. The button underneath
 * is not a third line -- it is the thing to do about the first two.
 */
function drawWords(ctx: CanvasRenderingContext2D): void {
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';

  ctx.font = `500 22px ${FAMILY}`;
  ctx.letterSpacing = '2px';
  ctx.fillStyle = withAlpha(WHITE, 0.55);
  ctx.fillText('PEDESTRIAN SIMULATOR', MARGIN, 250);

  // The weights are the face's own axis -- it is variable from 100 to 1000 --
  // so 700 is a real cut rather than a browser thickening 400 on its own.
  ctx.font = `700 92px ${FAMILY}`;
  ctx.letterSpacing = '-2px';
  ctx.fillStyle = toCss(WHITE);
  ctx.fillText('Walky.', MARGIN, 352);

  ctx.font = `400 46px ${FAMILY}`;
  ctx.letterSpacing = '-0.5px';
  ctx.fillStyle = withAlpha(WHITE, 0.78);
  ctx.fillText('Ready for iPhone Duo.', MARGIN, 414);
}

/** The button's box, in design units. */
const BUTTON_Y = 460;
const BUTTON_H = 60;
const BUTTON_PAD = 32;

/**
 * "Download now!", as a filled pill rather than one more line of type.
 *
 * White on the dark ground, because that is the highest contrast available and
 * a call to action that has to survive re-encoding by a timeline should not be
 * spending any of it on colour. The shape is the point as much as the words:
 * at the size a card is actually seen, a pill reads as a thing to press before
 * anybody has read what it says.
 *
 * Sized from `measureText` rather than a guessed width -- the face is variable
 * and the string is translatable, and a pill with the "!" hanging out of it is
 * worse than no pill.
 */
function drawButton(ctx: CanvasRenderingContext2D): number {
  const label = 'Download now!';
  ctx.font = `600 27px ${FAMILY}`;
  ctx.letterSpacing = '0px';
  const width = Math.round(ctx.measureText(label).width) + BUTTON_PAD * 2;

  ctx.fillStyle = toCss(WHITE);
  ctx.beginPath();
  ctx.roundRect(MARGIN, BUTTON_Y, width, BUTTON_H, BUTTON_H / 2);
  ctx.fill();

  // Middled by hand rather than with `textBaseline: 'middle'`, which centres
  // the font's em box and leaves a capital-and-descender string sitting high.
  ctx.fillStyle = toCss(BACKGROUND);
  ctx.fillText(label, MARGIN + BUTTON_PAD, BUTTON_Y + BUTTON_H / 2 + 9);

  return width;
}

/** The address, beside the button on the baseline the button's text sits on. */
function drawAddress(ctx: CanvasRenderingContext2D, buttonWidth: number): void {
  ctx.font = `400 25px ${FAMILY}`;
  ctx.letterSpacing = '0px';
  ctx.fillStyle = withAlpha(WHITE, 0.5);
  ctx.fillText('walky.ch', MARGIN + buttonWidth + 28, BUTTON_Y + BUTTON_H / 2 + 9);
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
  canvas.width = WIDTH * SCALE;
  canvas.height = HEIGHT * SCALE;

  const ctx = canvas.getContext('2d')!;
  const [, photo] = await Promise.all([loadFont(), loadPhoto()]);

  // One scale for the whole card, set before anything is drawn, so every
  // coordinate above is a design unit and none of them multiply by hand.
  ctx.scale(SCALE, SCALE);

  ctx.fillStyle = toCss(BACKGROUND);
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  drawPhoto(ctx, photo);
  drawWords(ctx);
  drawAddress(ctx, drawButton(ctx));

  status.textContent = `Drawn at ${canvas.width}x${canvas.height}.`;
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
