function sign(a0) {
  { if (a0 === 0) { return 0; } }
  { const n = a0; if ((n > 0)) { return 1; } }
  { return -1; }
  throw new Error("sign: no clause matched");
}
