/**
 * Which files the service worker precaches, kept free of Node imports so it can
 * be unit tested next to the rest of the simulation.
 *
 * The offline guarantee is only as good as this list: anything the app can ask
 * for at runtime and that is missing here is a blank icon -- or a blank page --
 * the first time someone opens Walky on a plane.
 */

/** The service worker's own filename in the build output. */
export const SW_FILE = 'sw.js';

/**
 * Files the host consumes rather than serves, or that no browser ever requests.
 * `_headers` and `_redirects` are Cloudflare Pages control files.
 *
 * `robots.txt` and `sitemap.xml` are crawler files. No page ever fetches them,
 * so precaching them buys nothing offline and costs twice: two entries in every
 * client's cache, and a new worker version every time a `lastmod` date moves.
 *
 * `og.png` is the link-preview card. It is 300KB, no page has ever shown it,
 * and the only things that fetch it are Slack's and X's scrapers -- which are
 * not the browser and never see this cache. Precaching it made every offline
 * install pay for a picture none of its users can reach.
 */
const SKIP = new Set([
  '_headers', '_redirects', '.DS_Store', 'robots.txt', 'sitemap.xml', 'og.png',
]);

const stripLeadingSlash = (path: string) => path.replace(/^\.?\//, '');

/**
 * @param bundleFiles paths Rollup emitted, relative to the output directory.
 * @param publicFiles paths copied verbatim from `public/`, relative to it.
 * @returns a sorted, deduplicated list of output-relative paths to precache.
 */
export function buildPrecacheList(
  bundleFiles: Iterable<string>,
  publicFiles: Iterable<string>,
): string[] {
  const out = new Set<string>();
  for (const raw of [...bundleFiles, ...publicFiles]) {
    const path = stripLeadingSlash(raw);
    // The worker is fetched by the browser's own update check, never through
    // the cache; precaching it would pin the version that is trying to retire.
    if (!path || path === SW_FILE || path.endsWith('.map')) continue;
    if (SKIP.has(path.split('/').pop() ?? '')) continue;
    out.add(path);
  }
  return [...out].sort();
}

/** The landing page's shell, and the app's. */
export const LANDING_SHELL = 'index.html';
export const APP_SHELL = 'demo/index.html';

/**
 * Which shell answers a navigation.
 *
 * The worker used to serve one page on the premise that there was one page.
 * There are two now: a landing page at the root and the app under /demo, built
 * as separate Rollup inputs and precached as separate files. Getting this wrong
 * offline is not subtle -- it is the app opening to a marketing page, or a
 * shared map opening to a black canvas with nothing on it.
 *
 * `path` is deployment-relative. The match is on a whole path segment rather
 * than a prefix: `demonstration` starts with the same four letters and is not
 * the app.
 */
export function shellFor(path: string): string {
  const first = stripLeadingSlash(path).split('/')[0];
  return first === 'demo' ? APP_SHELL : LANDING_SHELL;
}

/**
 * The same answer for a whole request URL, given where the app is deployed.
 *
 * The reduction is the half that is easy to get wrong and impossible to see
 * going wrong: Walky can be served from a subpath -- `base` is './' so that it
 * can -- and under `/somewhere/` the app's own page is `/somewhere/demo/`,
 * which has to come back as `demo/` before the rule above reads it. Here rather
 * than in the worker so that it is covered by the suite instead of by a deploy.
 *
 * @param url  the navigation's URL.
 * @param base the deployment root, as the worker derives it from its own URL.
 */
export function shellForUrl(url: string | URL, base: URL): string {
  return shellFor(new URL(url).pathname.slice(base.pathname.length));
}
