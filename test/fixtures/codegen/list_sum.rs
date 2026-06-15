fn sum(xs: &[i64]) -> i64 {
    match xs {
        [] => 0,
        [h, t @ ..] => { let h = h.clone(); h + sum(t) },
    }
}
