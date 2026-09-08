/**
 * Where a link carrying a map should actually go.
 *
 * The app lived at the root until the landing page did, so every Walky link
 * pasted anywhere before that move is `walky.ch/#m=...` -- and it now arrives at
 * a page that reads no fragment, where the map would be silently dropped. A
 * share link that used to work and stopped is the one kind of breakage a share
 * feature cannot afford, so the landing page forwards instead.
 *
 * Links made from here on need nothing: `shareUrl` builds from `location.href`,
 * so a map shared out of /demo already comes back as `/demo/#m=...`.
 *
 * A module of its own, and pure, so the rule can be tested without a document --
 * the same shape build/precache.ts is in for the same reason.
 */
import { readSharedPayload } from '../state/shareLink';

/**
 * @param hash a location fragment, with or without its leading `#`.
 * @returns the URL to send the visitor to, or null to stay on the page.
 */
export function forwardTarget(hash: string): string | null {
  // Handed straight to the app rather than re-encoded: the payload is opaque
  // here, and this page has no business deciding whether it is a valid map --
  // the decoder says so, with a message about what went wrong.
  return readSharedPayload(hash) === null ? null : `./demo/${hash}`;
}
