function fib(a0) {
  { if (a0 === 0) { return 0; } }
  { if (a0 === 1) { return 1; } }
  { const n = a0; return (fib((n - 1)) + fib((n - 2))); }
}
