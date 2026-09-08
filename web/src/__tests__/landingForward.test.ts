import { describe, expect, it } from 'vitest';
import { forwardTarget } from '../landing/forward';
import { LINK_KEY, LINK_PREFIX } from '../state/shareLink';

const PAYLOAD = 'AQIDBA';

/**
 * The landing page took the root from the app, and the root is where every
 * share link made before that move points. These are the cases that decide
 * whether those links still open a map.
 */
describe('forwardTarget', () => {
  it('sends a map that arrived at the root on to the app, payload intact', () => {
    const hash = `${LINK_PREFIX}${PAYLOAD}`;
    expect(forwardTarget(hash)).toBe(`./demo/${hash}`);
  });

  it('leaves an ordinary visit alone', () => {
    expect(forwardTarget('')).toBeNull();
    expect(forwardTarget('#')).toBeNull();
    expect(forwardTarget('#main')).toBeNull();
  });

  // The fragment is `&`-separated key=value so that a second key can be added
  // later without breaking a link already pasted somewhere. A forward that only
  // recognised a fragment starting with the map key would drop those.
  it('finds the map beside another key, and carries the whole fragment across', () => {
    const hash = `#x=1&${LINK_KEY}=${PAYLOAD}`;
    expect(forwardTarget(hash)).toBe(`./demo/${hash}`);
  });

  // An empty payload is not a map -- decoding it would only produce an error
  // toast on the far side, so the visitor stays on the page they asked for.
  it('does not forward an empty payload', () => {
    expect(forwardTarget(LINK_PREFIX)).toBeNull();
  });
});
