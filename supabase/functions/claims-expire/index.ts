// Spec 09 claims-expire: reads the request, calls the core handler, writes the response. No logic here.
import { depsFromEnv } from "../_shared/store_factory.ts";
import { serveFunction } from "../_shared/http.ts";
import { FN, handle } from "../_shared/claims_expire.ts";

Deno.serve(
  serveFunction(FN, handle, () => depsFromEnv((k) => Deno.env.get(k))),
);
