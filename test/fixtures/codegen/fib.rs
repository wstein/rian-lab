fn fib(n: i64) -> i64 {
    match n {
        0 => 0,
        1 => 1,
        n => fib(n - 1) + fib(n - 2),
    }
}
