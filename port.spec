# port.spec — lib/rian porting decisions (ADR-0075). `Placeholder = RianType`.
# Applied program-wide: one decision per shared placeholder re-resolves every site.
#   mix rian.port_analysis lib/rian -o PORT-ANALYSIS.md --spec port.spec

# ── proposed sums (named from the Core node families) ──
Sum1 = Expr   # the E* nodes (ENum, ECall, EIf, …)
Sum2 = Pat    # the P* nodes (PVar, PCtor, PList, …)

# ── high-leverage threaded context types (uncomment once you've named them) ──
# Unk0078 = Ic      # Check inference context — 112 sites (annotate/bind_tvar/…)
# Unk0439 = Store   # Infer union-find store — 101 sites (app/call_sig/…)
# Unk0010 = Prog    # Beam program IR — 91 sites (compile_ir/funcs_of/…)
