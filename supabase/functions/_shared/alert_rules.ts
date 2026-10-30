// Spec 11 alert rules: pure functions, no I/O, no logging, no clock (now is a parameter).
// The types below are the spec 11 Contract. They are local on purpose: spec 08's types.ts does not exist yet.

export type ConditionKind =
  | "phoneSilent"
  | "monitoringOff"
  | "noActiveDevice"
  | "shopifyReconnect"
  | "reviewWaiting";
export type EventKind = "syncFailed";
export type AlertKind = ConditionKind | EventKind;
export type AlertStatus = "open" | "resolved";

export const CONDITION_KINDS: readonly ConditionKind[] = [
  "phoneSilent",
  "monitoringOff",
  "noActiveDevice",
  "shopifyReconnect",
  "reviewWaiting",
];

/** Never TrxID, amounts, payer numbers or SMS text. syncFailed holds orderRef and syncId only. */
export interface AlertDetails {
  orderRef?: string;
  syncId?: string;
}

/** Times are ISO 8601 UTC strings. */
export interface Alert {
  id: string;
  merchantId: string;
  kind: AlertKind;
  status: AlertStatus;
  openedAt: string;
  lastSentAt: string | null;
  sendCount: number;
  resolvedAt: string | null;
  details: AlertDetails;
}

export interface AlertInput {
  merchantId: string;
  activeDeviceCount: number;
  newestDeviceSeenAt: string | null;
  anyDeviceProblem: boolean;
  storeActive: boolean;
  storeConnectedAt: string | null;
  storeReconnectNeeded: boolean;
  pendingClaimCount: number;
  reviewWaitingCount: number;
}

/**
 * open: open a new alert of this kind and send its first email.
 * remind: send an email for this open alert (a reminder, or a retry when no email was sent yet).
 * resolve: mark resolved; sendFixed -> send the "fixed" email.
 */
export type Action =
  | { type: "open"; kind: ConditionKind }
  | { type: "remind"; alertId: string }
  | { type: "resolve"; alertId: string; sendFixed: boolean };

const MIN = 60 * 1000;
const HOUR = 60 * MIN;

export const SILENT_MS = 15 * MIN;
export const SILENT_WITH_PENDING_MS = 5 * MIN;
export const SEEN_RECENTLY_MS = 5 * MIN;
export const NO_DEVICE_AFTER_MS = 30 * MIN;

/** Reminder interval and the most emails one open alert may send (the first email counts). */
export const REMINDERS: Readonly<
  Record<ConditionKind, { intervalMs: number; maxEmails: number }>
> = {
  phoneSilent: { intervalMs: 2 * HOUR, maxEmails: 6 },
  monitoringOff: { intervalMs: 6 * HOUR, maxEmails: 4 },
  noActiveDevice: { intervalMs: 6 * HOUR, maxEmails: 4 },
  shopifyReconnect: { intervalMs: 24 * HOUR, maxEmails: 7 },
  reviewWaiting: { intervalMs: 24 * HOUR, maxEmails: 7 },
};

export function isConditionKind(kind: string): kind is ConditionKind {
  return (CONDITION_KINDS as readonly string[]).includes(kind);
}

function time(iso: string): number {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) throw new RangeError("invalid time");
  return t;
}

function count(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError("count must be a whole, non-negative number");
  }
  return value;
}

/** Milliseconds since iso, or null when there is no time. */
function age(iso: string | null, now: number): number | null {
  return iso === null ? null : now - time(iso);
}

/** Whether the problem is present now (opens an alert when none is open). */
function shouldOpen(
  kind: ConditionKind,
  input: AlertInput,
  now: number,
  phoneSilentOpen: boolean,
): boolean {
  switch (kind) {
    case "phoneSilent": {
      const seen = age(input.newestDeviceSeenAt, now);
      if (count(input.activeDeviceCount) === 0 || seen === null) return false;
      return seen > SILENT_MS ||
        (seen > SILENT_WITH_PENDING_MS && count(input.pendingClaimCount) > 0);
    }
    case "monitoringOff":
      return input.anyDeviceProblem && !phoneSilentOpen;
    case "noActiveDevice": {
      const connected = age(input.storeConnectedAt, now);
      return input.storeActive && count(input.activeDeviceCount) === 0 &&
        connected !== null && connected > NO_DEVICE_AFTER_MS;
    }
    case "shopifyReconnect":
      return input.storeReconnectNeeded;
    case "reviewWaiting":
      return count(input.reviewWaitingCount) > 0;
  }
}

/** Whether the problem is gone (resolves an open alert). */
function shouldClear(
  kind: ConditionKind,
  input: AlertInput,
  now: number,
): boolean {
  switch (kind) {
    case "phoneSilent": {
      const seen = age(input.newestDeviceSeenAt, now);
      return seen !== null && seen <= SEEN_RECENTLY_MS;
    }
    case "monitoringOff":
      return !input.anyDeviceProblem;
    case "noActiveDevice":
      return count(input.activeDeviceCount) > 0;
    case "shopifyReconnect":
      return !input.storeReconnectNeeded;
    case "reviewWaiting":
      return count(input.reviewWaitingCount) === 0;
  }
}

/** An open alert is emailed when none was sent yet (retry), or when the interval passed, until the limit. */
function dueEmail(alert: Alert, now: number): boolean {
  const { intervalMs, maxEmails } = REMINDERS[alert.kind as ConditionKind];
  if (count(alert.sendCount) >= maxEmails) return false;
  if (alert.lastSentAt === null) return true;
  return now - time(alert.lastSentAt) >= intervalMs;
}

/**
 * Decides what to do for one merchant. openAlerts may hold any of the merchant's alerts; resolved alerts, event
 * alerts and other merchants' alerts are ignored. At most one action per kind.
 */
export function decide(
  input: AlertInput,
  openAlerts: readonly Alert[],
  nowIso: string,
): Action[] {
  const now = time(nowIso);
  const open = new Map<ConditionKind, Alert>();
  for (const alert of openAlerts) {
    if (
      alert.status === "open" && alert.merchantId === input.merchantId &&
      isConditionKind(alert.kind) && !open.has(alert.kind)
    ) {
      open.set(alert.kind, alert);
    }
  }

  const actions: Action[] = [];
  let phoneSilentOpen = false;
  // phoneSilent first: whether it is open after this check decides whether monitoringOff may open.
  for (const kind of CONDITION_KINDS) {
    const alert = open.get(kind);
    if (alert === undefined) {
      if (shouldOpen(kind, input, now, phoneSilentOpen)) {
        actions.push({ type: "open", kind });
        if (kind === "phoneSilent") phoneSilentOpen = true;
      }
    } else if (shouldClear(kind, input, now)) {
      actions.push({
        type: "resolve",
        alertId: alert.id,
        sendFixed: kind === "phoneSilent" && count(alert.sendCount) > 0,
      });
    } else {
      if (kind === "phoneSilent") phoneSilentOpen = true;
      if (dueEmail(alert, now)) {
        actions.push({ type: "remind", alertId: alert.id });
      }
    }
  }
  return actions;
}
