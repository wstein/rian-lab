function sum(a0) {
  { if (a0.length === 0) { return 0; } }
  { if (a0.length >= 1) { const h = a0[0]; const t = a0.slice(1); return (h + sum(t)); } }
  throw new Error("sum: no clause matched");
}
