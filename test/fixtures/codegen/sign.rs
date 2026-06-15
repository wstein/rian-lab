fn sign(n: i64) -> i64 {
    match n {
        0 => 0,
        n if n > 0 => 1,
        _ => -1,
    }
}
