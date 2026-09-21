import { describe, expect, it } from 'vitest';
import {
  APP_SHELL, buildPrecacheList, LANDING_SHELL, SW_FILE, shellFor, shellForUrl,
} from '../../build/precache';

describe('buildPrecacheList', () => {
  it('keeps every emitted asset so nothing is fetched on first offline load', () => {
    const files = buildPrecacheList(
      ['index.html', 'assets/main-a1b2c3.js', 'assets/main-d4e5f6.css'],
      ['icons/start.png', 'images/icon-192.png', 'manifest.webmanifest'],
    );
    expect(files).toEqual([
      'assets/main-a1b2c3.js',
      'assets/main-d4e5f6.css',
      'icons/start.png',
      'images/icon-192.png',
      'index.html',
      'manifest.webmanifest',
    ]);
  });

  it('leaves the worker out of its own manifest', () => {
    expect(buildPrecacheList([SW_FILE, 'index.html'], [])).toEqual(['index.html']);
  });

  it('drops host control files and source maps, which no page requests', () => {
    const files = buildPrecacheList(
      ['index.html', 'assets/main-a1b2c3.js.map'],
      ['_headers', '_redirects', '.DS_Store'],
    );
    expect(files).toEqual(['index.html']);
  });

  it('drops the crawler files, so a lastmod date cannot retire every worker', () => {
    const files = buildPrecacheList(['index.html'], ['robots.txt', 'sitemap.xml']);
    expect(files).toEqual(['index.html']);
  });

  it('drops the link-preview card, which only scrapers ever fetch', () => {
    const files = buildPrecacheList(['index.html'], ['images/og.png', 'images/icon.png']);
    expect(files).toEqual(['images/icon.png', 'index.html']);
  });

  it('normalises leading slashes and deduplicates', () => {
    expect(buildPrecacheList(['./index.html', '/index.html'], ['index.html']))
      .toEqual(['index.html']);
  });
});

describe('shellFor', () => {
  it('answers the root and anything unrecognised with the landing page', () => {
    expect(shellFor('')).toBe(LANDING_SHELL);
    expect(shellFor('/')).toBe(LANDING_SHELL);
    expect(shellFor('index.html')).toBe(LANDING_SHELL);
    expect(shellFor('somewhere/else')).toBe(LANDING_SHELL);
  });

  it('answers the demo tree with the app, however the path is spelt', () => {
    expect(shellFor('demo')).toBe(APP_SHELL);
    expect(shellFor('demo/')).toBe(APP_SHELL);
    expect(shellFor('/demo/')).toBe(APP_SHELL);
    expect(shellFor('demo/index.html')).toBe(APP_SHELL);
  });

  // A prefix match would send this to the app, and the app is not what is
  // there. The rule reads a whole path segment for that reason.
  it('does not treat a path merely starting with the letters as the app', () => {
    expect(shellFor('demonstration')).toBe(LANDING_SHELL);
    expect(shellFor('demos/one')).toBe(LANDING_SHELL);
  });

  it('precaches both shells, since either can answer a navigation offline', () => {
    const files = buildPrecacheList([LANDING_SHELL, APP_SHELL, SW_FILE], []);
    expect(files).toEqual([APP_SHELL, LANDING_SHELL]);
  });
});

/**
 * The half of the rule the worker cannot check for itself. Walky is built with a
 * relative base so that it can be served from a subpath, and under one the app's
 * page is `/somewhere/demo/` -- which has to reduce to `demo/` before the rule
 * above ever sees it.
 */
describe('shellForUrl', () => {
  const root = new URL('https://walky.ch/');
  const subpath = new URL('https://example.test/somewhere/');

  it('picks the shell for a deployment at the origin root', () => {
    expect(shellForUrl('https://walky.ch/', root)).toBe(LANDING_SHELL);
    expect(shellForUrl('https://walky.ch/demo/', root)).toBe(APP_SHELL);
  });

  it('reduces a subpath deployment before reading the path', () => {
    expect(shellForUrl('https://example.test/somewhere/', subpath)).toBe(LANDING_SHELL);
    expect(shellForUrl('https://example.test/somewhere/demo/', subpath)).toBe(APP_SHELL);
    // The prefix is the deployment's, not the app's: a `demo` above the root is
    // somebody else's directory.
    expect(shellForUrl('https://example.test/demo/', subpath)).toBe(LANDING_SHELL);
  });

  // A shared map rides in the fragment and a cache-buster in the query; neither
  // says anything about which page is being asked for.
  it('ignores the query and the fragment', () => {
    expect(shellForUrl('https://walky.ch/demo/#m=AQID', root)).toBe(APP_SHELL);
    expect(shellForUrl('https://walky.ch/?utm_source=x', root)).toBe(LANDING_SHELL);
  });
});
