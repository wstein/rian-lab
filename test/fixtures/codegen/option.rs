#[derive(Clone, Debug, PartialEq)]
enum Opt {
    None,
    Some(i64),
}

fn get(o: &Opt, d: i64) -> i64 {
    match (o, d) {
        (Opt::None, d) => d,
        (Opt::Some(v), _) => v,
    }
}
