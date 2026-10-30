// Spec 08 device-heartbeat (signed): updates lastSeenAt and appVersion.

import { checkDeviceRequest } from "./device_auth.ts";
import {
  type AppRelease,
  type Deps,
  isObject,
  parseJson,
  readBody,
  replier,
} from "./http.ts";

export const FN = "device-heartbeat";

interface HeartbeatBody {
  appVersion: string;
  smsPermission: boolean;
  batteryOptimizationOff: boolean;
  monitoring: boolean;
  queueCount: number;
}

function readHeartbeat(v: unknown): HeartbeatBody | null {
  if (!isObject(v)) return null;
  const { appVersion, smsPermission, batteryOptimizationOff, monitoring } = v;
  if (
    typeof appVersion !== "string" || appVersion.trim() === "" ||
    appVersion.length > 50
  ) return null;
  if (
    typeof smsPermission !== "boolean" ||
    typeof batteryOptimizationOff !== "boolean" ||
    typeof monitoring !== "boolean"
  ) return null;
  if (!Number.isSafeInteger(v.queueCount) || (v.queueCount as number) < 0) {
    return null;
  }
  return {
    appVersion: appVersion.trim(),
    smsPermission,
    batteryOptimizationOff,
    monitoring,
    queueCount: v.queueCount as number,
  };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const reply = replier(FN, req, deps.log);
  if (req.method !== "POST") return reply.fail(405, "methodNotAllowed");
  const raw = await readBody(req);
  if (raw === null) return reply.fail(413, "tooLarge");
  const auth = await checkDeviceRequest(
    FN,
    req.headers,
    raw,
    deps.store,
    deps.now(),
  );
  if (!auth.ok) return reply.fail(auth.status, auth.code);
  const { device } = auth;
  const body = readHeartbeat(parseJson(raw));
  if (body === null) return reply.fail(400, "badRequest", device.merchantId);

  const nowIso = new Date(deps.now()).toISOString();
  await deps.store.updateDevice(device.id, {
    lastSeenAt: nowIso,
    appVersion: body.appVersion,
  });
  // "Every successful write that changes a device writes an audit entry" (spec text; plan D75 unanswered).
  await deps.store.writeAudit({
    merchantId: device.merchantId,
    actorType: "device",
    actorId: device.id,
    action: "device.heartbeat",
    entity: "device",
    entityId: device.id,
    data: { appVersion: body.appVersion },
  });
  const rules = await deps.store.getParserRules();
  // Spec 15: the update notice; both fields or neither (plan 15 D218). Older apps ignore them.
  const release = deps.release === undefined ? {} : {
    latestAppVersion: deps.release.latestAppVersion,
    appDownloadUrl: deps.release.appDownloadUrl,
  };
  return reply.ok(
    { serverTime: nowIso, rulesVersion: rules.version, ...release },
    device.merchantId,
  );
}

/**
 * Spec 15: LATEST_APP_VERSION and APP_DOWNLOAD_URL from the environment (read by the caller and passed in).
 * Both must be set and valid - "major.minor.patch" and an https URL - or the notice is left out (plan 15 D218).
 */
export function releaseFromEnv(
  get: (name: string) => string | undefined,
): AppRelease | undefined {
  const version = get("LATEST_APP_VERSION")?.trim() ?? "";
  const url = get("APP_DOWNLOAD_URL")?.trim() ?? "";
  if (!/^\d{1,4}\.\d{1,4}\.\d{1,4}$/.test(version)) return undefined;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return undefined;
  }
  if (
    parsed.protocol !== "https:" || parsed.username !== "" ||
    parsed.password !== ""
  ) return undefined;
  return { latestAppVersion: version, appDownloadUrl: parsed.href };
}
