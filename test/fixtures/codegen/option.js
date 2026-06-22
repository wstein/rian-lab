function get(a0, a1) {
  { if (a0.$ === "None") { const d = a1; return d; } }
  { if (a0.$ === "Some") { const v = a0._0; return v; } }
  throw new Error("get: no clause matched");
}
