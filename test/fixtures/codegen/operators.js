function calc(a0, a1) {
  { const a = a0; const b = a1; return (((((a * b) + a) - b) > a) && (a !== b)); }
  throw new Error("calc: no clause matched");
}
