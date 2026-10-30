// The spec 12a contract suite on FakeStore. Always runs.
import { runContract } from "./contract.ts";
import { fakeMaker } from "./makers.ts";

runContract("FakeStore", () => Promise.resolve(fakeMaker()));
