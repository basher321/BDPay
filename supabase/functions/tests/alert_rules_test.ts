import assert from "node:assert/strict";
import {
  type Action,
  type Alert,
  type AlertInput,
  type ConditionKind,
  decide,
  REMINDERS,
} from "../_shared/alert_rules.ts";

const NOW = "2026-10-30T06:00:00.000Z";
const MIN = 60 * 1000;
const HOUR = 60 * MIN;

const at = (ms: number) => new Date(Date.parse(NOW) + ms).toISOString();
const ago = (ms: number) => at(-ms);

/** A healthy merchant: one phone seen just now, no store, nothing waiting. */
function input(over: Partial<AlertInput> = {}): AlertInput {
  return {
    merchantId: "m1",
    activeDeviceCount: 1,
    newestDeviceSeenAt: ago(1 * MIN),
    anyDeviceProblem: false,
    storeActive: false,
    storeConnectedAt: null,
    storeReconnectNeeded: false,
    pendingClaimCount: 0,
    reviewWaitingCount: 0,
    ...over,
  };
}

function alert(kind: Alert["kind"], over: Partial<Alert> = {}): Alert {
  return {
    id: `a-${kind}`,
    merchantId: "m1",
    kind,
    status: "open",
    openedAt: ago(1 * HOUR),
    lastSentAt: ago(1 * MIN),
    sendCount: 1,
    resolvedAt: null,
    details: {},
    ...over,
  };
}

const opens = (actions: Action[]) =>
  actions.filter((a) => a.type === "open").map((a) => a.kind);

/**
 * A tiny in-memory run of alerts-check for one merchant: opens, reminders and resolves are applied, and every
 * email "sent" is recorded. mailOk(t) says whether the provider works at minute t.
 */
function simulate(
  timeline: (minute: number) => Partial<AlertInput>,
  minutes: number,
  mailOk: (minute: number) => boolean = () => true,
  stepMinutes = 5,
) {
  const alerts: Alert[] = [];
  const mails: { minute: number; kind: string; fixed: boolean }[] = [];
  let next = 1;
  for (let m = 0; m <= minutes; m += stepMinutes) {
    const now = at(m * MIN);
    const send = (a: Alert, fixed: boolean) => {
      if (!mailOk(m)) return;
      mails.push({ minute: m, kind: a.kind, fixed });
      if (!fixed) {
        a.lastSentAt = now;
        a.sendCount += 1;
      }
    };
    // The phone is healthy (seen now) unless the timeline says otherwise.
    const actions = decide(
      input({ newestDeviceSeenAt: now, ...timeline(m) }),
      alerts.filter((a) => a.status === "open"),
      now,
    );
    for (const action of actions) {
      if (action.type === "open") {
        assert.ok(
          !alerts.some((a) => a.status === "open" && a.kind === action.kind),
          `duplicate open ${action.kind} at minute ${m}`,
        );
        const a = alert(action.kind, {
          id: `a${next++}`,
          openedAt: now,
          lastSentAt: null,
          sendCount: 0,
        });
        alerts.push(a);
        send(a, false);
      } else {
        const a = alerts.find((x) => x.id === action.alertId)!;
        if (action.type === "remind") send(a, false);
        else {
          a.status = "resolved";
          a.resolvedAt = now;
          if (action.sendFixed) send(a, true);
        }
      }
    }
  }
  return { alerts, mails };
}

// --- phoneSilent ---

Deno.test("edge: phone silent 16 minutes, no pending claims -> phoneSilent opens", () => {
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: ago(16 * MIN) }), [], NOW),
    [{ type: "open", kind: "phoneSilent" }],
  );
});

Deno.test("edge: silent 16 minutes in a run -> exactly 1 email", () => {
  // Seen at minute 0, silent from then on; checks every 5 minutes until minute 30.
  const { alerts, mails } = simulate(() => ({ newestDeviceSeenAt: NOW }), 30);
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].kind, "phoneSilent");
  assert.deepEqual(mails, [{ minute: 20, kind: "phoneSilent", fixed: false }]);
});

Deno.test("phone silent exactly 15 minutes, no pending -> nothing", () => {
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: ago(15 * MIN) }), [], NOW),
    [],
  );
});

Deno.test("edge: silent 6 minutes with 2 pending claims -> opens early", () => {
  assert.deepEqual(
    decide(
      input({ newestDeviceSeenAt: ago(6 * MIN), pendingClaimCount: 2 }),
      [],
      NOW,
    ),
    [{ type: "open", kind: "phoneSilent" }],
  );
});

Deno.test("silent 4 minutes with pending claims, or 6 minutes without -> nothing", () => {
  assert.deepEqual(
    decide(
      input({ newestDeviceSeenAt: ago(4 * MIN), pendingClaimCount: 2 }),
      [],
      NOW,
    ),
    [],
  );
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: ago(6 * MIN) }), [], NOW),
    [],
  );
});

Deno.test("no active device -> never phoneSilent", () => {
  assert.deepEqual(
    decide(
      input({ activeDeviceCount: 0, newestDeviceSeenAt: ago(3 * HOUR) }),
      [],
      NOW,
    ),
    [],
  );
});

Deno.test("active device that never sent a heartbeat (seen null) -> no phoneSilent", () => {
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: null, pendingClaimCount: 3 }), [], NOW),
    [],
  );
});

Deno.test("edge: two phones, one silent and one fine -> no phoneSilent (newest seen is recent)", () => {
  // The store reports the newest seen time over all active devices.
  assert.deepEqual(
    decide(
      input({
        activeDeviceCount: 2,
        newestDeviceSeenAt: ago(2 * MIN),
        pendingClaimCount: 1,
      }),
      [],
      NOW,
    ),
    [],
  );
});

Deno.test("edge: phone back after 3 hours -> resolved with one fixed email", () => {
  const { alerts, mails } = simulate(
    (m) => ({ newestDeviceSeenAt: m < 180 ? NOW : at(m * MIN) }),
    200,
  );
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].status, "resolved");
  assert.equal(alerts[0].resolvedAt, at(180 * MIN));
  assert.deepEqual(mails.filter((x) => x.fixed), [
    { minute: 180, kind: "phoneSilent", fixed: true },
  ]);
  // Opened at minute 20, reminded 2 hours later at 140.
  assert.deepEqual(mails.filter((x) => !x.fixed).map((x) => x.minute), [
    20,
    140,
  ]);
});

Deno.test("phoneSilent clears only when seen within 5 minutes", () => {
  const open = [alert("phoneSilent")];
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: ago(5 * MIN) }), open, NOW),
    [{ type: "resolve", alertId: "a-phoneSilent", sendFixed: true }],
  );
  // 6 minutes: not cleared, not due for a reminder.
  assert.deepEqual(
    decide(input({ newestDeviceSeenAt: ago(6 * MIN) }), open, NOW),
    [],
  );
});

Deno.test("edge: phone flaps -> a new alert each time, never two open", () => {
  // Silent from 0, back at 30, silent again from 50 (20 minutes later), back at 100.
  const seen = (m: number) =>
    m < 30 ? NOW : m < 50 ? at(m * MIN) : m < 100 ? at(50 * MIN) : at(m * MIN);
  const { alerts, mails } = simulate(
    (m) => ({ newestDeviceSeenAt: seen(m) }),
    110,
  );
  assert.equal(alerts.length, 2);
  assert.ok(alerts.every((a) => a.kind === "phoneSilent"));
  assert.ok(alerts.every((a) => a.status === "resolved"));
  assert.deepEqual(mails, [
    { minute: 20, kind: "phoneSilent", fixed: false },
    { minute: 30, kind: "phoneSilent", fixed: true },
    { minute: 70, kind: "phoneSilent", fixed: false },
    { minute: 100, kind: "phoneSilent", fixed: true },
  ]);
});

// --- fixed email ---

Deno.test("fixed email only after a sent phoneSilent email", () => {
  const back = input({ newestDeviceSeenAt: ago(1 * MIN) });
  assert.deepEqual(
    decide(
      back,
      [alert("phoneSilent", { sendCount: 0, lastSentAt: null })],
      NOW,
    ),
    [{ type: "resolve", alertId: "a-phoneSilent", sendFixed: false }],
  );
  assert.deepEqual(
    decide(back, [alert("phoneSilent", { sendCount: 1 })], NOW),
    [{ type: "resolve", alertId: "a-phoneSilent", sendFixed: true }],
  );
});

Deno.test("other kinds never send a fixed email", () => {
  const sent = { sendCount: 3, lastSentAt: ago(1 * MIN) };
  const actions = decide(
    input({ activeDeviceCount: 1 }),
    [
      alert("monitoringOff", sent),
      alert("noActiveDevice", sent),
      alert("shopifyReconnect", sent),
      alert("reviewWaiting", sent),
    ],
    NOW,
  );
  assert.equal(actions.length, 4);
  for (const a of actions) {
    assert.equal(a.type, "resolve");
    assert.equal(a.type === "resolve" && a.sendFixed, false);
  }
});

// --- monitoringOff ---

Deno.test("monitoringOff opens when anyDeviceProblem, clears when false", () => {
  assert.deepEqual(decide(input({ anyDeviceProblem: true }), [], NOW), [
    { type: "open", kind: "monitoringOff" },
  ]);
  assert.deepEqual(decide(input(), [alert("monitoringOff")], NOW), [
    { type: "resolve", alertId: "a-monitoringOff", sendFixed: false },
  ]);
});

Deno.test("monitoringOff does not open while phoneSilent is open", () => {
  const problem = input({
    anyDeviceProblem: true,
    newestDeviceSeenAt: ago(10 * MIN),
  });
  assert.deepEqual(decide(problem, [alert("phoneSilent")], NOW), []);
});

Deno.test("monitoringOff does not open in the same check that opens phoneSilent", () => {
  const actions = decide(
    input({ anyDeviceProblem: true, newestDeviceSeenAt: ago(20 * MIN) }),
    [],
    NOW,
  );
  assert.deepEqual(opens(actions), ["phoneSilent"]);
});

Deno.test("monitoringOff opens in the same check that resolves phoneSilent", () => {
  const actions = decide(
    input({ anyDeviceProblem: true, newestDeviceSeenAt: ago(1 * MIN) }),
    [alert("phoneSilent")],
    NOW,
  );
  assert.deepEqual(actions, [
    { type: "resolve", alertId: "a-phoneSilent", sendFixed: true },
    { type: "open", kind: "monitoringOff" },
  ]);
});

// --- noActiveDevice ---

Deno.test("edge: Shopify connected 10 minutes ago, no phone -> nothing; at 31 minutes noActiveDevice", () => {
  const brandNew = (connected: number) =>
    input({
      activeDeviceCount: 0,
      newestDeviceSeenAt: null,
      storeActive: true,
      storeConnectedAt: ago(connected),
    });
  assert.deepEqual(decide(brandNew(10 * MIN), [], NOW), []);
  assert.deepEqual(decide(brandNew(30 * MIN), [], NOW), []);
  assert.deepEqual(decide(brandNew(31 * MIN), [], NOW), [
    { type: "open", kind: "noActiveDevice" },
  ]);
});

Deno.test("noActiveDevice needs an active store and a connected time", () => {
  const noPhone = { activeDeviceCount: 0, newestDeviceSeenAt: null };
  assert.deepEqual(
    decide(
      input({
        ...noPhone,
        storeActive: false,
        storeConnectedAt: ago(2 * HOUR),
      }),
      [],
      NOW,
    ),
    [],
  );
  assert.deepEqual(
    decide(
      input({ ...noPhone, storeActive: true, storeConnectedAt: null }),
      [],
      NOW,
    ),
    [],
  );
});

Deno.test("noActiveDevice clears when a device is active", () => {
  assert.deepEqual(
    decide(
      input({ storeActive: true, storeConnectedAt: ago(2 * HOUR) }),
      [alert("noActiveDevice")],
      NOW,
    ),
    [{ type: "resolve", alertId: "a-noActiveDevice", sendFixed: false }],
  );
});

// --- shopifyReconnect and reviewWaiting ---

Deno.test("shopifyReconnect opens on storeReconnectNeeded, clears when false", () => {
  assert.deepEqual(decide(input({ storeReconnectNeeded: true }), [], NOW), [
    { type: "open", kind: "shopifyReconnect" },
  ]);
  assert.deepEqual(decide(input(), [alert("shopifyReconnect")], NOW), [
    { type: "resolve", alertId: "a-shopifyReconnect", sendFixed: false },
  ]);
});

Deno.test("reviewWaiting opens when reviewWaitingCount > 0, clears at 0", () => {
  assert.deepEqual(decide(input({ reviewWaitingCount: 2 }), [], NOW), [
    { type: "open", kind: "reviewWaiting" },
  ]);
  assert.deepEqual(decide(input(), [alert("reviewWaiting")], NOW), [
    { type: "resolve", alertId: "a-reviewWaiting", sendFixed: false },
  ]);
});

// --- reminders ---

const STILL_BAD: Record<ConditionKind, Partial<AlertInput>> = {
  phoneSilent: { newestDeviceSeenAt: ago(30 * HOUR) },
  monitoringOff: { anyDeviceProblem: true },
  noActiveDevice: {
    activeDeviceCount: 0,
    newestDeviceSeenAt: null,
    storeActive: true,
    storeConnectedAt: ago(1000 * HOUR),
  },
  shopifyReconnect: { storeReconnectNeeded: true },
  reviewWaiting: { reviewWaitingCount: 1 },
};

for (const kind of Object.keys(REMINDERS) as ConditionKind[]) {
  const { intervalMs, maxEmails } = REMINDERS[kind];

  Deno.test(`${kind}: reminder not before ${intervalMs / HOUR} h, sent at it`, () => {
    const bad = input(STILL_BAD[kind]);
    const early = alert(kind, { lastSentAt: ago(intervalMs - 1) });
    const due = alert(kind, { lastSentAt: ago(intervalMs) });
    assert.deepEqual(decide(bad, [early], NOW), []);
    assert.deepEqual(decide(bad, [due], NOW), [
      { type: "remind", alertId: `a-${kind}` },
    ]);
  });

  Deno.test(`${kind}: at most ${maxEmails} emails per open alert`, () => {
    const bad = input(STILL_BAD[kind]);
    const lastAllowed = alert(kind, {
      sendCount: maxEmails - 1,
      lastSentAt: ago(intervalMs),
    });
    const full = alert(kind, {
      sendCount: maxEmails,
      lastSentAt: ago(100 * intervalMs),
    });
    assert.deepEqual(decide(bad, [lastAllowed], NOW), [
      { type: "remind", alertId: `a-${kind}` },
    ]);
    assert.deepEqual(decide(bad, [full], NOW), []);
  });
}

Deno.test("phoneSilent over 2 days: 6 emails 2 hours apart, the 7th is not sent", () => {
  const { alerts, mails } = simulate(
    () => ({ newestDeviceSeenAt: NOW }),
    48 * 60,
  );
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].status, "open");
  assert.equal(alerts[0].sendCount, 6);
  assert.deepEqual(mails.map((x) => x.minute), [
    20,
    140,
    260,
    380,
    500,
    620,
  ]);
});

Deno.test("reminder counts per kind over 10 days", () => {
  const expected: Record<ConditionKind, number> = {
    phoneSilent: 6,
    monitoringOff: 4,
    noActiveDevice: 4,
    shopifyReconnect: 7,
    reviewWaiting: 7,
  };
  const bad: Record<ConditionKind, (m: number) => Partial<AlertInput>> = {
    phoneSilent: () => ({ newestDeviceSeenAt: NOW }),
    monitoringOff: () => ({ anyDeviceProblem: true }),
    noActiveDevice: () => STILL_BAD.noActiveDevice,
    shopifyReconnect: () => ({ storeReconnectNeeded: true }),
    reviewWaiting: () => ({ reviewWaitingCount: 1 }),
  };
  for (const kind of Object.keys(expected) as ConditionKind[]) {
    const { mails } = simulate(bad[kind], 10 * 24 * 60, () => true, 30);
    assert.equal(mails.length, expected[kind], kind);
    const gaps = mails.slice(1).map((x, i) => x.minute - mails[i].minute);
    assert.ok(
      gaps.every((g) => g === REMINDERS[kind].intervalMs / MIN),
      `${kind} gaps ${gaps}`,
    );
  }
});

// --- failed email ---

Deno.test("edge: mail down -> alert stays open, retried on the next check, not a reminder", () => {
  // Provider down at minutes 20 and 25, back at 30.
  const { alerts, mails } = simulate(
    () => ({ newestDeviceSeenAt: NOW }),
    150,
    (m) => m >= 30,
  );
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].status, "open");
  // First email at 30 (the retry); the first reminder 2 hours after that, at 150.
  assert.deepEqual(mails.map((x) => x.minute), [30, 150]);
});

Deno.test("an open alert with no email sent yet -> email again on the next check", () => {
  assert.deepEqual(
    decide(
      input({ storeReconnectNeeded: true }),
      [alert("shopifyReconnect", { lastSentAt: null, sendCount: 0 })],
      NOW,
    ),
    [{ type: "remind", alertId: "a-shopifyReconnect" }],
  );
});

// --- input hygiene ---

Deno.test("resolved, event and other merchants' alerts are ignored", () => {
  const bad = input({ storeReconnectNeeded: true });
  assert.deepEqual(
    decide(
      bad,
      [
        alert("shopifyReconnect", { status: "resolved" }),
        alert("shopifyReconnect", { id: "other", merchantId: "m2" }),
        alert("syncFailed", { details: { orderRef: "#1045", syncId: "s1" } }),
      ],
      NOW,
    ),
    [{ type: "open", kind: "shopifyReconnect" }],
  );
});

Deno.test("at most one action per kind, even with two open alerts of a kind", () => {
  const actions = decide(
    input({ storeReconnectNeeded: true }),
    [
      alert("shopifyReconnect", { id: "x1", lastSentAt: null, sendCount: 0 }),
      alert("shopifyReconnect", { id: "x2", lastSentAt: null, sendCount: 0 }),
    ],
    NOW,
  );
  assert.deepEqual(actions, [{ type: "remind", alertId: "x1" }]);
});

Deno.test("everything wrong at once -> one open per kind, monitoringOff held back", () => {
  const actions = decide(
    input({
      newestDeviceSeenAt: ago(20 * MIN),
      anyDeviceProblem: true,
      storeActive: true,
      storeConnectedAt: ago(1 * HOUR),
      storeReconnectNeeded: true,
      pendingClaimCount: 1,
      reviewWaitingCount: 3,
    }),
    [],
    NOW,
  );
  assert.deepEqual(opens(actions), [
    "phoneSilent",
    "shopifyReconnect",
    "reviewWaiting",
  ]);
});

Deno.test("bad input is refused", () => {
  assert.throws(() => decide(input(), [], "not a time"), RangeError);
  assert.throws(
    () =>
      decide(
        input({ pendingClaimCount: -1, newestDeviceSeenAt: ago(6 * MIN) }),
        [],
        NOW,
      ),
    RangeError,
  );
  assert.throws(
    () => decide(input({ newestDeviceSeenAt: "yesterday" }), [], NOW),
    RangeError,
  );
});
