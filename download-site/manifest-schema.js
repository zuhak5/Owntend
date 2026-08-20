export * from "./manifest-schema-v5.js";

if (typeof window !== "undefined") {
  import("./abi-downloads.js").catch(() => {});
}
