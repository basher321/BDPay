// Spec 08 sms-ingest: reads the request, calls the core handler, writes the response. No logic here.
import { depsFromEnv } from "../_shared/store_factory.ts";
import { serveFunction } from "../_shared/http.ts";
import { FN, handle } from "../_shared/ingest.ts";

Deno.serve(
  serveFunction(FN, handle, () => depsFromEnv((k) => Deno.env.get(k))),
);
