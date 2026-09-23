import { ScenarioLinkError } from './codec';

/**
 * The deflate-raw plumbing a map's bytes pass through, shared by shareLink.ts
 * (which wraps the result in base64url for a URL fragment) and mapFile.ts
 * (which writes the same bytes straight to a `.walky` file). Neither carries
 * its own copy: the codec that reads one has to read the other, so the
 * transform between them belongs in one place.
 */

/**
 * What an inflated body is allowed to come to.
 *
 * Deflate is the one step here that can turn a small input into a large output,
 * so the cap the codec applies to counts has to be matched by a cap on the bytes
 * those counts are read from -- otherwise a kilobyte of crafted zeroes becomes
 * hundreds of megabytes before the first count is ever checked.
 */
export const MAX_BODY_BYTES = 1 << 20;

export function hasCompression(): boolean {
  return typeof CompressionStream !== 'undefined' && typeof DecompressionStream !== 'undefined';
}

export async function through(
  bytes: Uint8Array,
  stream: TransformStream<BufferSource, Uint8Array>,
  limit: number,
): Promise<Uint8Array> {
  const source = new Blob([bytes as BlobPart]).stream() as unknown as ReadableStream<BufferSource>;
  const reader = source.pipeThrough(stream).getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    // Checked per chunk rather than at the end, so a bomb is abandoned while it
    // is still small rather than after it has been held in full.
    if (total > limit) {
      await reader.cancel();
      throw new ScenarioLinkError('that unpacks to more than Walky can hold');
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) { out.set(chunk, at); at += chunk.length; }
  return out;
}
