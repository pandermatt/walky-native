import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { APP_STORE_URL } from '../landing/store';

/**
 * The parts of index.html that no other test would notice were broken.
 *
 * Structured data fails silently by design: a trailing comma in the JSON-LD
 * makes Google drop the whole block, the page still renders, the build still
 * passes, and nothing says so until somebody thinks to check the rich-results
 * tool months later. Same for the App Store href -- it has to be written into
 * the markup so the button works before the module boots, which means the URL
 * exists twice and the copies can drift.
 */

const html = readFileSync(resolve(__dirname, '../../index.html'), 'utf8');

/** Every `<script type="application/ld+json">` body on the page. */
function jsonLdBlocks(): string[] {
  return [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map(
    (m) => m[1],
  );
}

describe('the landing page head', () => {
  it('carries structured data, and all of it parses', () => {
    const blocks = jsonLdBlocks();
    expect(blocks.length).toBeGreaterThan(0);
    for (const block of blocks) expect(() => JSON.parse(block)).not.toThrow();
  });

  it('names both the app and the page it is sold under', () => {
    const graph = JSON.parse(jsonLdBlocks()[0])['@graph'] as { '@type': string; name: string }[];
    const app = graph.find((node) => node['@type'] === 'MobileApplication');
    // Walky was taken on the App Store. Getting this wrong is the one error on
    // the page that makes a search for the listing's own name miss it.
    expect(app?.name).toBe('Walky Go');
    expect(graph.find((node) => node['@type'] === 'WebSite')?.name).toBe('Walky');
  });

  it('points every store link and the structured data at the same listing', () => {
    const hrefs = [...html.matchAll(/data-store-link\s+href="([^"]+)"/g)].map((m) => m[1]);
    // Hero, closing band, footer. A missing one is a dead end, not a wrong link.
    expect(hrefs).toHaveLength(3);
    for (const href of hrefs) expect(href).toBe(APP_STORE_URL);

    const graph = JSON.parse(jsonLdBlocks()[0])['@graph'] as { installUrl?: string }[];
    expect(graph.find((node) => node.installUrl)?.installUrl).toBe(APP_STORE_URL);
  });

  it('names every platform the listing actually sells to', () => {
    const graph = JSON.parse(jsonLdBlocks()[0])['@graph'] as { '@type': string; operatingSystem?: string }[];
    const os = graph.find((node) => node['@type'] === 'MobileApplication')?.operatingSystem ?? '';
    // Apple's own listing says iOS 17, iPadOS 17, and macOS 14 on an M1 or
    // later -- the iPhone app running on Apple Silicon, which App Store Connect
    // enables by default. The page claims Mac, so the data has to as well.
    expect(os).toMatch(/iOS 17/);
    expect(os).toMatch(/iPadOS 17/);
    expect(os).toMatch(/macOS 14/);
  });

  it('tells Safari which app the smart banner is for', () => {
    const id = APP_STORE_URL.match(/id(\d+)/)?.[1];
    expect(html).toContain(`<meta name="apple-itunes-app" content="app-id=${id}" />`);
  });
});
