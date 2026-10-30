// Spec 12a: the shared Store contract suite against PgStore on a LOCAL database only (BDPAY_TEST_DB=1; in CI the
// throwaway Supabase on the runner). Each test makes its own user and merchant; nothing is ever deleted.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { PgStore } from "../../_shared/pg_store.ts";
import type { AuditEntry, Wallet } from "../../_shared/types.ts";
import { assertLocal, testDbEnabled } from "../integration/local_guard.ts";
import { runContract } from "./contract.ts";
import { randomHex, randomWalletNumber, type StoreMaker } from "./makers.ts";

function pgMaker(): Promise<StoreMaker> {
  const url = assertLocal(Deno.env.get("SUPABASE_URL")).origin; // never a remote database
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const store = PgStore.fromEnv(url, key, (m) => console.error(m));
  const must = <T>(r: { data: T | null; error: unknown }): T => {
    if (r.error || r.data === null) throw new Error("test setup failed");
    return r.data;
  };
  return Promise.resolve({
    name: "PgStore",
    store,
    async newMerchant() {
      const email = `t-${crypto.randomUUID()}@bdpay.test`;
      const created = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
      });
      const user = created.data.user;
      if (created.error || user === null) throw new Error("test setup failed");
      const businessName = `Contract ${randomHex(3)}`;
      const m = must(
        await admin.from("merchants").insert({
          owner_id: user.id,
          business_name: businessName,
        }).select("id")
          .single(),
      ) as { id: string };
      return { merchantId: m.id, userId: user.id, email, businessName };
    },
    async addWallet(merchantId, fields = {}) {
      const operator = fields.operator ?? "bkash";
      const row = must(
        await admin.from("wallets").insert({
          merchant_id: merchantId,
          operator,
          wallet_number: randomWalletNumber(),
          account_type: "merchant",
          sim_slot: fields.simSlot ?? "unknown",
          is_active: fields.isActive ?? true,
        }).select("*").single(),
      ) as Record<string, unknown>;
      return {
        id: row.id,
        merchantId,
        operator,
        walletNumber: row.wallet_number,
        accountType: "merchant",
        simSlot: row.sim_slot,
        isActive: row.is_active,
      } as Wallet;
    },
    async readAudit(merchantId) {
      const rows = must(
        await admin.from("audit_log").select("*").eq("merchant_id", merchantId)
          .neq("action", "session.status")
          .order("created_at"),
      ) as Record<string, unknown>[];
      return rows.map((r) =>
        ({
          merchantId: r.merchant_id,
          actorType: r.actor_type,
          actorId: r.actor_id,
          action: r.action,
          entity: r.entity,
          entityId: r.entity_id,
          data: r.data,
        }) as AuditEntry
      );
    },
    async newStoreId(merchantId) {
      const s = must(
        await admin.from("stores").insert({
          merchant_id: merchantId,
          shop_domain: `t-${randomHex(6)}.myshopify.com`,
        }).select("id").single(),
      ) as { id: string };
      return s.id;
    },
  });
}

runContract("PgStore", pgMaker, !testDbEnabled());
