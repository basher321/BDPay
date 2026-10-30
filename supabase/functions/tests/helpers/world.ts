// Test helper: a FakeStore world with a fixed clock, a recording logger and registered devices.

import { FakeStore } from "../../_shared/fake_store.ts";
import type { Deps, LogEntry } from "../../_shared/http.ts";
import { type Matcher, NoopMatcher } from "../../_shared/matcher.ts";
import type { Device, DeviceStatus, SmsRecord } from "../../_shared/types.ts";
import { FakeUserVerifier } from "../../_shared/user_auth.ts";
import { type DeviceKey, newDeviceKey } from "./device_signer.ts";

export const T0 = Date.parse("2026-10-30T06:00:00.000Z");
export const MIN = 60 * 1000;
export const USER_TOKEN = "token-owner-m1";
export const NO_MERCHANT_TOKEN = "token-no-merchant";

/** Records every stored SMS it is called with. */
export class SpyMatcher implements Matcher {
  readonly calls: SmsRecord[] = [];
  private readonly inner = new NoopMatcher();
  onSmsStored(sms: SmsRecord) {
    this.calls.push(sms);
    return this.inner.onSmsStored(sms);
  }
}

export interface World {
  deps: Deps;
  store: FakeStore;
  matcher: SpyMatcher;
  logs: LogEntry[];
  clock: { now: number };
}

export function world(): World {
  const clock = { now: T0 };
  const now = () => clock.now;
  const store = new FakeStore(now);
  store.addOwner("user-m1", "m1");
  store.addOwner("user-m2", "m2");
  const logs: LogEntry[] = [];
  const matcher = new SpyMatcher();
  const users = new FakeUserVerifier(
    new Map([
      [USER_TOKEN, "user-m1"],
      ["token-owner-m2", "user-m2"],
      [NO_MERCHANT_TOKEN, "user-nobody"],
    ]),
  );
  return {
    deps: { store, users, matcher, now, log: (e) => logs.push(e) },
    store,
    matcher,
    logs,
    clock,
  };
}

export async function addDevice(
  store: FakeStore,
  merchantId = "m1",
  status: DeviceStatus = "active",
): Promise<{ device: Device; key: DeviceKey }> {
  const key = await newDeviceKey();
  const device = await store.createDevice({
    merchantId,
    name: "Shop phone",
    installId: crypto.randomUUID(),
    publicKeySpki: key.publicKeySpki,
    status,
    appVersion: "1.0.0",
    androidVersion: "14",
    lastSeenAt: new Date(T0).toISOString(),
  });
  return { device, key };
}
