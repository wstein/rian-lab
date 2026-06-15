fn calc(a: i64, b: i64) -> bool {
    match (a, b) {
        (a, b) => a * b + a - b > a && a != b,
    }
}
