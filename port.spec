# port.spec — lib/rian porting decisions (ADR-0075). `Placeholder = RianType`.
# Applied program-wide: one decision per shared placeholder re-resolves every site.
#   mix rian.port_analysis lib/rian -o PORT-ANALYSIS.md --spec port.spec
#   mix rian.transpile     lib/rian -o drafts/          --spec port.spec

# ── proposed sums (named from the Core node families) ──
Sum1 = Expr        # the E* nodes (ENum, ECall, EIf, …)
Sum2 = Pat         # the P* nodes (PVar, PCtor, PList, …)

# ── threaded context types (identified from their call sites) ──
Unk0078 = Ic       # Check inference context (%{tdefs, funs, fsigs, …}), threaded through Check.*
Unk0388 = Doc      # Format Wadler doc — matches `type Doc := DText | DNest | …` (compiler/format.rian)
Unk0607 = Vec(Tok) # token stream — `Tok` per compiler/lexer.rian; Lexer/Pratt thread the list

# Not yet pinned — verify first (the whole-program unification may merge a list type
# with its element type at these, so confirm the role before naming):
#   Unk0439 (~101) Infer type-term/store   Unk0009/Unk0010 (~91/73) Beam IR collections
