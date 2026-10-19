// Pure rules of the real-time alert worker (alert.ts), kept free of RPC so they can be unit-tested.

export type Severity = "critical" | "warning" | "info";
export type Alert = { at: string; id: string; severity: Severity; state: "raised" | "resolved" | "event"; message: string };

/** One alert per condition id: raised once while the condition holds, resolved once when it clears.
 *  One-off happenings (a pause, a held credit) are `event`s and always pass. */
export class AlertBook {
  private active = new Map<string, Severity>();

  raise(id: string, severity: Severity, message: string, now = new Date()): Alert | undefined {
    if (this.active.has(id)) return undefined;
    this.active.set(id, severity);
    return { at: now.toISOString(), id, severity, state: "raised", message };
  }

  resolve(id: string, message: string, now = new Date()): Alert | undefined {
    const severity = this.active.get(id);
    if (!severity) return undefined;
    this.active.delete(id);
    return { at: now.toISOString(), id, severity, state: "resolved", message };
  }

  event(id: string, severity: Severity, message: string, now = new Date()): Alert {
    return { at: now.toISOString(), id, severity, state: "event", message };
  }

  isActive(id: string) {
    return this.active.has(id);
  }
}

/** The bridge invariant: what is minted on the other chains can never exceed what backs it on the home chain.
 *  In flight is always locked >= minted (lock before mint, burn before unlock), so minted > locked is never benign. */
export function supplyBroken(locked: bigint, quarantinedAtHome: bigint, minted: bigint) {
  return minted > locked - quarantinedAtHome;
}

/** A destination accepted (PacketVerified) `verified` for a nonce; `sent` is what the source really sent (if any). */
export function forgedVerification(sent: string | undefined, verified: string) {
  return !sent || sent.toLowerCase() !== verified.toLowerCase();
}

/** Seconds a packet may stay undelivered before it is reported as stuck. */
export function isStuck(firstSeenMs: number, nowMs: number, stuckSeconds: number) {
  return nowMs - firstSeenMs >= stuckSeconds * 1000;
}

const ICON: Record<Severity, string> = { critical: "🚨", warning: "⚠️", info: "ℹ️" };

export function formatAlert(a: Alert) {
  const tag = a.state === "resolved" ? "✅ RESOLVED" : `${ICON[a.severity]} ${a.severity.toUpperCase()}`;
  return `${tag} ${a.id}: ${a.message}`;
}
