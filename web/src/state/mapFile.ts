import {
  FLAG_DEFLATED,
  bodyFlags, decodeScenarioBody, encodeScenario, encodeScenarioBody,
  readHeader, scenarioHeader,
} from './codec';
import { MAX_BODY_BYTES, hasCompression, through } from './compress';
import type { ScenarioCore } from './scenario';

/**
 * A map as a `.walky` file: the same bytes a share link carries, without the
 * base64 a URL fragment forces on them. Ported from iOS's `MapFile`, which is
 * what makes a `.walky` file openable by the web app in the first place -- the
 * codec on both sides is the one this was ported from.
 */

/** The `.walky` file's own MIME type, for a Blob and a download link's accept. */
export const MAP_FILE_MIME = 'application/x-walky-map';

/**
 * A `.walky` file's bytes back into a map. `decodeLink` minus the base64 and
 * the fragment: the body may still be deflated, exactly as a link's can be.
 */
export async function decodeMapFile(bytes: Uint8Array): Promise<ScenarioCore> {
  const { flags, body } = readHeader(bytes);
  if ((flags & FLAG_DEFLATED) === 0) return decodeScenarioBody(body, flags);
  const inflated = await through(body, new DecompressionStream('deflate-raw'), MAX_BODY_BYTES);
  return decodeScenarioBody(inflated, flags);
}

/**
 * A map as the bytes to write to a `.walky` file. Deflated only when that
 * actually comes out shorter, for the same reason encodeLink is: the codec's
 * own varints and deltas have already taken most of the redundancy out.
 */
export async function encodeMapFile(core: ScenarioCore): Promise<Uint8Array> {
  const raw = encodeScenario(core);
  if (!hasCompression()) return raw;
  try {
    const body = encodeScenarioBody(core);
    const deflated = await through(body, new CompressionStream('deflate-raw'), MAX_BODY_BYTES);
    if (deflated.length + 3 >= raw.length) return raw;
    const out = new Uint8Array(deflated.length + 3);
    out.set(scenarioHeader(FLAG_DEFLATED | bodyFlags(core)), 0);
    out.set(deflated, 3);
    return out;
  } catch {
    // Compression is an optimisation. Failing at it is not a reason to fail at
    // saving.
    return raw;
  }
}

/**
 * A name for the file, ported from iOS's `MapFile.suggestedName`: what the map
 * has in it, in the fewest words that say so.
 */
export function suggestedMapFileName(core: ScenarioCore): string {
  const walls = core.walls.length;
  const agents = core.agents.length;
  if (walls === 0 && agents === 0) return 'Empty map';
  const many = (n: number, noun: string) => `${n} ${noun}${n === 1 ? '' : 's'}`;
  const parts: string[] = [];
  if (walls > 0) parts.push(many(walls, 'wall'));
  if (agents > 0) parts.push(many(agents, 'pedestrian'));
  return parts.join(', ');
}
