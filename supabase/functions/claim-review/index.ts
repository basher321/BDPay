// Spec 09 claim-review: reads the request, calls the core handler, writes the response. No logic here.
import { depsFromEnv } from "../_shared/store_factory.ts";
import { serveFunction } from "../_shared/http.ts";
import { FN, handle } from "../_shared/claim_review.ts";

Deno.serve(
  serveFunction(FN, handle, () => depsFromEnv((k) => Deno.env.get(k))),
);
