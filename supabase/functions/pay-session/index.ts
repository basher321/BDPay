// Spec 09 pay-session: reads the request, calls the core handler, writes the response. No logic here.
import { depsFromEnv } from "../_shared/fake_store.ts";
import { serveFunction } from "../_shared/http.ts";
import { FN, handle } from "../_shared/pay_session.ts";

Deno.serve(
  serveFunction(FN, handle, () => depsFromEnv((k) => Deno.env.get(k))),
);
