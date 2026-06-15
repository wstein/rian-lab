function get(a0, a1) {
  { if (a0[0] === "None") { const d = a1; return d; } }
  { if (a0[0] === "Some") { const v = a0[1]; return v; } }
  throw new Error("get: no clause matched");
}
