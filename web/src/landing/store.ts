/**
 * The App Store listing, and the check that keeps its copies honest.
 *
 * Split out of main.ts for the same reason forward.ts is: main.ts reads
 * `location` at module scope, so importing it from a test drags a browser
 * global into Node. This module is a constant and a function, and both can be
 * checked without a DOM.
 */

/**
 * On the store the app is called **Walky Go** -- `Walky` was taken -- so the
 * page says both names, and this is the link behind every one of them.
 *
 * No country code. Apple 301s a locale-less listing URL to whichever storefront
 * the visitor's account is in; pinning `/ch/` would send everyone else through a
 * redirect to be told the app is not available in Switzerland's store.
 *
 * The HTML carries this same href literally, so the buttons work before any of
 * this module runs. That is two copies of one URL, which is exactly the
 * arrangement that rots silently -- `checkStoreLinks` and landingMeta.test.ts
 * are the two things that stop it.
 */
export const APP_STORE_URL = 'https://apps.apple.com/app/id6811090126';

/**
 * Shouts in the console if the markup and the constant have drifted apart.
 *
 * Dev only: in the build this is three dead lines, and shipping a console
 * warning to visitors helps nobody. The test is the real guard; this is what
 * catches it while somebody is still editing the page.
 */
export function checkStoreLinks(): void {
  if (!import.meta.env.DEV) return;
  for (const link of document.querySelectorAll<HTMLAnchorElement>('[data-store-link]')) {
    if (link.href !== APP_STORE_URL) {
      console.warn(`App Store link is ${link.href}, APP_STORE_URL is ${APP_STORE_URL}`);
    }
  }
}
