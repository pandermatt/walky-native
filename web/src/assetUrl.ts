/**
 * Where the app's own files are, from a page that is no longer at the root.
 *
 * The toolbar icons, the typeface and the manifest are copied verbatim out of
 * public/ and served from the deployment root. Every reference to them used to
 * be written relative to the document -- `./icons/start.png` -- which was
 * correct while the app WAS the root page, and which quietly became a 404 the
 * day the landing page took the root and the app moved to /demo/.
 *
 * The fix is not to write them from the root instead: `/icons/start.png` would
 * agree with walky.ch and disagree with any deployment under a subpath, which
 * is the whole reason vite.config.ts sets `base` to './'. So the root is
 * derived from the document, one level up, and that one level is stated here
 * rather than in each of the three places that asks.
 *
 * document.baseURI rather than location.href: a fragment or a query does not
 * change where the assets are, and baseURI is already the URL the browser
 * resolves the page's own relative hrefs against.
 */

/**
 * One of those files, as an absolute URL.
 *
 * The root is worked out per call rather than once at module scope, so that
 * importing anything that reaches this file does not itself require a document
 * -- the chrome's stylesheets are plain strings checked by a test suite that
 * runs in Node, and a `document.baseURI` evaluated on import would take that
 * away.
 */
export function asset(path: string): string {
  return new URL(path, new URL('../', document.baseURI)).href;
}
