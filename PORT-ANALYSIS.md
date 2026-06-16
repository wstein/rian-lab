# Port Analysis — Elixir → Rian

**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the
`REVIEW` sections and record decisions in a `port.spec` — `mix rian.port_analysis
--spec port.spec` applies them program-wide (one decision per *shared* placeholder
re-resolves every site). Regenerate to diff against source — do not hand-edit this file.

## Summary

- modules: 47 · type slots: 3114 · auto-filled: 848 (27%) · holes: 2266
- structs seen: 49 · proposed sums: 2 · distinct error idioms: 33
- port.spec decisions applied: 0 · placeholders remaining: 1069

## 1. Inferred signatures — AUTO (high confidence, type-check-validated)

| function | signature | return reach |
|---|---|---|
| `beam_func/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `cap_arity/1` | `(ECapArg) Int53` | ✓ all 4 |
| `cap_arity_list/1` | `(Vec(ECapArg)) Int53` | ✓ all 4 |
| `core_list_tail/1` | `(T) T forall T` | ✓ all 4 |
| `load_program/1` | `(String) Vec(Symbol)` | ✓ all 4 |
| `pat_vars/2` | `(PVar, Map(T, U)) Map(T, U) forall T, U` | ✓ all 4 |
| `union_t/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `beam_legal!/1` | `(Symbol) Symbol` | ✓ all 4 |
| `borrowed/1` | `(String) String` | ✓ all 4 |
| `copy?/1` | `(String) Bool` | ✓ all 4 |
| `owned/1` | `(String) String` | ✓ all 4 |
| `rust_name/1` | `(String) String` | ✓ all 4 |
| `rust_param/2` | `(Symbol, String) String` | ✓ all 4 |
| `rust_scalar/1` | `(String) String` | ✓ all 4 |
| `assignable?/2` | `(Ty, Ty) Bool` | ✓ all 4 |
| `concretize/1` | `(T) T forall T` | ✓ all 4 |
| `conservative/1` | `(T) T forall T` | ✓ all 4 |
| `debottom/1` | `(T) T forall T` | ✓ all 4 |
| `deplaceholder/1` | `(String) String` | ✓ all 4 |
| `float_mantissa/1` | `(Int53) Int53` | ✓ all 4 |
| `int_float_join/2` | `(Int53, Int53) String` | ✓ all 4 |
| `int_lit_expr?/1` | `(ENum) Bool` | ✓ all 4 |
| `join/2` | `(Ty, Ty) Ty` | ✓ all 4 |
| `ordinal_base/1` | `(String) String` | ✓ all 4 |
| `unify/2` | `(Ty, Ty) Ty` | ✓ all 4 |
| `wildcard?/1` | `(String) Bool` | ✓ all 4 |
| `dispatch/1` | `(Vec(String)) Int53` | ✓ all 4 |
| `usage/1` | `(T) T forall T` | ✓ all 4 |
| `truthy!/1` | `(T) T forall T` | ✓ all 4 |
| `block_seps/5` | `(Vec(T), Int53, Int53, Int53, Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `inject_stdlib/1` | `(T) T forall T` | ✓ all 4 |
| `skip_nl/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `fences/1` | `(String) Vec(String)` | ✓ all 4 |
| `load_lexer/2` | `(String, Symbol) Symbol` | ✓ all 4 |
| `chunk_on_comma/3` | `(Vec(T), Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `collapse_runs/2` | `(Vec(String), Vec(String)) Vec(String)` | ✓ all 4 |
| `finish_items/2` | `(Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `format/1` | `(String) String` | ✓ all 4 |
| `ll/3` | `(Vec(T), Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `logical_lines/1` | `(Vec(T)) Vec(Vec(T)) forall T` | ✓ all 4 |
| `merge_chains/1` | `(Vec(Vec(Vec(T)))) Vec(Vec(Vec(T))) forall T` | ✓ all 4 |
| `next_code_line/1` | `(Vec(Option(T))) Option(T) forall T` | ✓ all 4 |
| `pop/1` | `(Vec(Vec(T))) Vec(T) forall T` | ✓ all 4 |
| `push/2` | `(Int53, Vec(Int53)) Vec(Int53)` | ✓ all 4 |
| `format_stdin/0` | `() Int53` | ✓ all 4 |
| `run/1` | `(Vec(String)) Int53` | ✓ all 4 |
| `usage/0` | `() Int53` | ✓ all 4 |
| `concat/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `concat/2` | `(T, T) T forall T` | ✓ all 4 |
| `canon_bool_case/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `fold_neg_literal/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `zero_anno/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `fill_returns/1` | `(T) T forall T` | ✓ all 4 |
| `fixpoint/1` | `(T) T forall T` | ✓ all 4 |
| `inferable?/1` | `(Func) Bool` | ✓ all 4 |
| `untyped_ret?/1` | `(Func) Bool` | ✓ all 4 |
| `concat_chain/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `branch_js/2` | `(EBlock, Bool) String` | ✓ all 4 |
| `compile/1` | `(String) String` | ✓ all 4 |
| `cp_expr/2` | `(String, Bool) String` | ✓ all 4 |
| `expr_js/2` | `(ENum, Bool) String` | ✓ all 4 |
| `int_typeof/1` | `(Bool) String` | ✓ all 4 |
| `js_fresh/2` | `(String, Int53) String` | ✓ all 4 |
| `js_op/1` | `(String) String` | ✓ all 4 |
| `js_str_cp/1` | `(Int53) String` | ✓ all 4 |
| `branch_kt/1` | `(EBlock) String` | ✓ all 4 |
| `compile/1` | `(String) String` | ✓ all 4 |
| `expr_kt/1` | `(ENum) String` | ✓ all 4 |
| `float_repr_helper/0` | `() String` | ✓ all 4 |
| `kt_fresh/2` | `(String, Int53) String` | ✓ all 4 |
| `kt_op/1` | `(String) String` | ✓ all 4 |
| `kt_str_cp/1` | `(Int53) String` | ✓ all 4 |
| `num_kt/1` | `(String) String` | ✓ all 4 |
| `char_source/1` | `(Int53) String` | ✓ all 4 |
| `cp!/1` | `(T) T forall T` | ✓ all 4 |
| `norm_num/1` | `(T) T forall T` | ✓ all 4 |
| `str_cp_source/1` | `(Int53) String` | ✓ all 4 |
| `reset/0` | `() Symbol` | ✓ all 4 |
| `cap_arity/1` | `(ECapArg) Int53` | ✓ all 4 |
| `catchall_pat?/1` | `(PWild) Bool` | ✓ all 4 |
| `coerce_ret/2` | `(String, String) String` | ✓ all 4 |
| `cons_tail_rebinds/1` | `(PList) Vec(String)` | ✓ all 4 |
| `flatten_concat/1` | `(EBin) Vec(EBin)` | ✓ all 4 |
| `head_word?/1` | `(Vec(Int53)) Bool` | ✓ all 4 |
| `join_doc/2` | `(String, String) String` | ✓ all 4 |
| `owned_rtype?/1` | `(String) Bool` | ✓ all 4 |
| `owned_value_type?/1` | `(String) Bool` | ✓ all 4 |
| `pat_ex/1` | `(PWild) String` | ✓ all 4 |
| `prim_ex/1` | `(String) String` | ✓ all 4 |
| `rest_pat_rs/1` | `(PVar) String` | ✓ all 4 |
| `rust_arm_body/2` | `(EBlock, String) String` | ✓ all 4 |
| `rust_char_lit/1` | `(Int53) String` | ✓ all 4 |
| `str_lit_cp/1` | `(Int53) String` | ✓ all 4 |
| `tail_expr/1` | `(T) T forall T` | ✓ all 4 |
| `word_char?/1` | `(Int53) Bool` | ✓ all 4 |
| `flush/2` | `(T, Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `leading_spaces/1` | `(String) Int53` | ✓ all 4 |
| `to_snake/1` | `(Symbol | String) Symbol | String` | ✓ all 4 |
| `reach_note/1` | `(String) String` | ✓ all 4 |
| `after_paren/2` | `(Vec(T), Int53) Vec(T) forall T` | ✓ all 4 |
| `expect_rbracket/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `expect_rparen/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `parse_body/1` | `(T) T forall T` | ✓ all 4 |
| `parse_sexpr/1` | `(String) String` | ✓ all 4 |
| `types/0` | `() Vec(Type)` | ✓ all 4 |
| `with_prelude/1` | `(Vec(Type)) Vec(Type)` | ✓ all 4 |
| `names/0` | `() Vec(String)` | ✓ all 4 |
| `normalize/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `overflow_ops/0` | `() Vec(String)` | ✓ all 4 |
| `targets/0` | `() Vec(Target)` | ✓ all 4 |
| `validate_default/1` | `(Option(T)) Option(T) forall T` | ✓ all 4 |
| `longest_common_prefix/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `new/0` | `() Session` | ✓ all 4 |
| `split_entries/1` | `(String) Vec(String)` | ✓ all 4 |
| `vocabulary/0` | `() Vec(String)` | ✓ all 4 |
| `add/1` | `(String) Symbol` | ✓ all 4 |
| `dedup_consecutive/1` | `(Vec(Vec(Vec(T)))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `path/0` | `() String` | ✓ all 4 |
| `count/1` | `(Status) Int53` | ✓ all 4 |
| `evidence_files/0` | `() Vec(String)` | ✓ all 4 |
| `ffi_in_file/1` | `(String) Vec(String)` | ✓ all 4 |
| `percent/0` | `() Int53` | ✓ all 4 |
| `selfhost_files/0` | `() Vec(String)` | ✓ all 4 |
| `selfhost_module_names/0` | `() Vec(String)` | ✓ all 4 |
| `status_markdown/0` | `() String` | ✓ all 4 |
| `compile!/2` | `(String, Symbol) Symbol` | ✓ all 4 |
| `default_mod/1` | `(String) Symbol` | ✓ all 4 |
| `js/1` | `(String) String` | ✓ all 4 |
| `run_one/2` | `(Symbol, String) Bool` | ✓ all 4 |
| `rust/1` | `(String) String` | ✓ all 4 |
| `tests/1` | `(String) Vec(String)` | ✓ all 4 |
| `to_json/0` | `() String` | ✓ all 4 |
| `block_stmts/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `close_group/2` | `(Vec(T), T) Vec(T) forall T` | ✓ all 4 |
| `expr/1` | `(Bool) String` | ✓ all 4 |
| `indent/1` | `(String) String` | ✓ all 4 |
| `interp_inner/1` | `(Bool) String` | ✓ all 4 |
| `pat/1` | `(Bool) String` | ✓ all 4 |
| `render_body/1` | `(Bool) String` | ✓ all 4 |
| `stmt/1` | `(Bool) String` | ✓ all 4 |
| `body_of/1` | `(T) T forall T` | ✓ all 4 |
| `clear_xmod/0` | `() Bool` | ✓ all 4 |
| `hole_or/2` | `(T, T) T forall T` | ✓ all 4 |
| `tails/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `split_top_commas/1` | `(String) Vec(String)` | ✓ all 4 |

## 2. Declarations to complete — REVIEW (whole-program inferred)

Each function with a residual unknown, as an **editable Rian signature**:
concrete types are inferred, structs resolve to their proposed `SumN` (§3), and
a genuine unknown is a **shared `Unk####`** — the *same* logical type carries one
name across the whole program (linked through the call graph), so you replace
each `Unk####` **once** and it propagates to every site in the index below.

```rian
  # Application.maybe_register_smart_cell/0
  pub def maybe_register_smart_cell() Unk0001 := …

  # Application.start/2
  pub def start(_type Unk0002, _args Unk0003) Unk0004 := …

  # Beam.any_t/0
  pub def any_t() Unk0005 := …

  # Beam.arity/1
  pub def arity(p0 Unk0006) Unk0007 := …

  # Beam.beam_for/5
  pub def beam_for(module Symbol, funcs Vec(Unk0008), ranges Vec(Map(Unk0009, Vec(Unk0010))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0011 := …

  # Beam.beam_func/1
  pub def beam_func(p0 Unk0012) Vec(Unk0012) := …

  # Beam.bin_seg/1
  pub def bin_seg(form Tuple(Option(Unk0013), Unk0014)) Unk0015 := …

  # Beam.bind_var/2
  pub def bind_var(n String, s Map(String, Unk0016)) Tuple(Unk0016, Map(String, Unk0016)) := …

  # Beam.block_forms/2
  pub def block_forms(p0 Sum1, _s Map(String, Unk0016)) Vec(Tuple(Option(Unk0013), Unk0014)) := …

  # Beam.body_forms/3
  pub def body_forms(src Option(Unk0017), scope Map(String, Unk0016), rtable Map(Unk0018, Unk0019)) Vec(Tuple(Option(Unk0013), Unk0014)) := …

  # Beam.body_seq/2
  pub def body_seq(p0 Sum1, s Map(String, Unk0016)) Vec(Tuple(Option(Unk0013), Unk0014)) := …

  # Beam.bump_var/1
  pub def bump_var(cur Unk0016) Unk0016 := …

  # Beam.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Beam.cap_arity_list/1
  pub def cap_arity_list(es Vec(Sum1)) Int53 := …

  # Beam.clause_form/2
  pub def clause_form(p0 Unk0020, rtable Map(Unk0018, Unk0019)) Unk0021 := …

  # Beam.compile/2
  pub def compile(src String, module Symbol) Unk0011 := …

  # Beam.compile_ir/2
  pub def compile_ir(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), module Symbol) Unk0011 := …

  # Beam.compile_program/1
  pub def compile_program(src String) Unk0023 := …

  # Beam.compile_program_ir/1
  pub def compile_program_ir(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0024 := …

  # Beam.cons/3
  pub def cons(p0 Vec(Unk0025), tail Tuple(Option(Unk0013), Unk0014), _f Fn(Option(Unk0017), Tuple(Option(Unk0013), Unk0014))) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.core_list_tail/1
  pub def core_list_tail(p0 Tuple(Option(Unk0013), Unk0014)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.else_dispatch/3
  pub def else_dispatch(p0 Vec(Unk0026), catch_var String, _s Map(String, Unk0016)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.erl_op/1
  pub def erl_op(p0 String) Unk0027 := …

  # Beam.expr_form/2
  pub def expr_form(p0 Option(Unk0017), _s Map(String, Unk0016)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.fn_form/2
  pub def fn_form(t String, tctx Unk0028) Unk0029 := …

  # Beam.fun_ref/3
  pub def fun_ref(mod Unk0030, fun Unk0031, arity Unk0032) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.funcs_of/1
  pub def funcs_of(p0 Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Unk0008) := …

  # Beam.function_form/2
  pub def function_form(p0 Unk0006, rtable Map(Unk0018, Unk0019)) Unk0034 := …

  # Beam.guard_core/1
  pub def guard_core(p0 String) Option(Unk0017) := …

  # Beam.guard_form/2
  pub def guard_form(p0 Option(Unk0017), _scope Map(String, Unk0016)) Vec(Vec(Tuple(Option(Unk0013), Unk0014))) := …

  # Beam.i64_overflow/4
  pub def i64_overflow(kind Unk0035, a Option(Unk0017), b Option(Unk0017), s Map(String, Unk0016)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.i64_project/2
  pub def i64_project(p0 Unk0035, sv Unk0036) Unk0037 := …

  # Beam.int_t/0
  pub def int_t() Unk0038 := …

  # Beam.load/2
  pub def load(src String, module Symbol) Tuple(Unk0039, Symbol) := …

  # Beam.load_aux_mods/1
  pub def load_aux_mods(p0 Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0040 := …

  # Beam.load_ir/2
  pub def load_ir(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), module Symbol) Tuple(Unk0041, Symbol) := …

  # Beam.load_program_ir/1
  pub def load_program_ir(prog Unk0042) Vec(Symbol) := …

  # Beam.map_field_pat/1
  pub def map_field_pat(p0 Unk0043) Unk0044 := …

  # Beam.num_form/1
  pub def num_form(n Unk0045) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.pat_form/1
  pub def pat_form(p0 Sum2) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.pat_vars/2
  pub def pat_vars(p0 Sum2, acc Map(String, Unk0016)) Map(String, Unk0016) := …

  # Beam.ranges_of/1
  pub def ranges_of(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Beam.remote_call/4
  pub def remote_call(mod Unk0046, fun String, args Vec(Option(Unk0017)), scope Map(String, Unk0016)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.spec_form/2
  pub def spec_form(p0 Unk0006, tctx Unk0028) Unk0034 := …

  # Beam.stmt_form/2
  pub def stmt_form(p0 Unk0047, s Map(String, Unk0016)) Tuple(Tuple(Option(Unk0013), Unk0014), Map(String, Unk0016)) := …

  # Beam.str_form/1
  pub def str_form(s Unk0048) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.struct_form/2
  pub def struct_form(p0 Map(Unk0009, Vec(Unk0010)), tctx Unk0028) Unk0005 := …

  # Beam.structs_of/1
  pub def structs_of(p0 Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Beam.sum_form/2
  pub def sum_form(variants Unk0049, tctx Unk0028) Unk0050 := …

  # Beam.type_attrs/3
  pub def type_attrs(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010))), tctx Unk0028) Vec(Unk0034) := …

  # Beam.type_ctx/3
  pub def type_ctx(types Vec(Map(Unk0009, Vec(Unk0010))), ranges Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0028 := …

  # Beam.type_form/2
  pub def type_form(p0 String, _tctx Unk0028) Unk0005 := …

  # Beam.types_of/1
  pub def types_of(p0 Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Beam.union_t/1
  pub def union_t(p0 Vec(Unk0005)) Unk0005 := …

  # Beam.var_atom/1
  pub def var_atom(p0 String) Unk0016 := …

  # Beam.var_form/1
  pub def var_form(x String) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.with_form/5
  pub def with_form(p0 Vec(Unk0051), body Sum1, _els Vec(Unk0026), s Map(String, Unk0016), _d Int53) Tuple(Option(Unk0013), Unk0014) := …

  # CLI.check/1
  pub def check(files Vec(Unk0052)) Int53 := …

  # CLI.diff/1
  pub def diff(files Vec(Unk0052)) Unk0053 := …

  # CLI.each/2
  pub def each(files Unk0054, fun Fn(Unk0055, Unk0056)) Unk0057 := …

  # CLI.in_place/1
  pub def in_place(file Unk0052) Unk0058 := …

  # CLI.main/1
  pub def main(argv Vec(String)) Unk0059 := …

  # CLI.print_diff/3
  pub def print_diff(file Unk0052, src Unk0060, out Unk0061) Vec(Unk0062) := …

  # CLI.read/1
  pub def read(file Unk0052) Tuple(Unk0063, String) := …

  # CLI.to_stdout/1
  pub def to_stdout(file Unk0052) Unk0064 := …

  # CLI.unified_diff/3
  pub def unified_diff(file Unk0052, old Unk0060, new Unk0061) String := …

  # Capability.count_block/3
  pub def count_block(p0 Vec(Unk0065), _bound Unk0066, acc Unk0067) Unk0067 := …

  # Capability.count_uses/1
  pub def count_uses(ast Unk0068) Unk0067 := …

  # Capability.count_uses/2
  pub def count_uses(p0 Unk0068, bound Unk0066) Unk0067 := …

  # Capability.lin_check/2
  pub def lin_check(env Map(Unk0070, Unk0069), ast Unk0068) Tuple(Unk0071, Vec(Unk0072)) := …

  # Capability.lin_check_block/3
  pub def lin_check_block(env Map(Unk0074, Unk0073), bindings Vec(Unk0075), final Unk0068) Tuple(Unk0071, Vec(Unk0072)) := …

  # Capability.max_merge/2
  pub def max_merge(a Unk0067, b Unk0067) Unk0067 := …

  # Capability.merge/2
  pub def merge(a Unk0067, b Unk0067) Unk0067 := …

  # Capability.pat_vars/1
  pub def pat_vars(p0 Unk0076) Unk0077 := …

  # Capability.verdict/2
  pub def verdict(env Map(Unk0070, Unk0069), uses Unk0067) Tuple(Unk0071, Vec(Unk0072)) := …

  # Check.abstract_cast_ret/3
  pub def abstract_cast_ret(ht Vec(Unk0078), cn Unk0079, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.abstract_op_type/4
  pub def abstract_op_type(op String, lt Vec(Unk0078), rt Vec(Unk0078), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0081 := …

  # Check.all_types/1
  pub def all_types(prog Map(Unk0082, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Type) := …

  # Check.ann_each/3
  pub def ann_each(nodes Vec(Option(Unk0017)), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.ann_stmts/3
  pub def ann_stmts(p0 Vec(Unk0083), _env Map(String, Vec(Unk0078)), _ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.annotate/3
  pub def annotate(ast Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.arith_type/4
  pub def arith_type(l Option(Unk0017), r Option(Unk0017), lt Vec(Unk0078), rt Vec(Unk0078)) Unk0084 := …

  # Check.assignable?/2
  pub def assignable?(t Vec(Unk0078), t String) Bool := …

  # Check.bind_mismatch/5
  pub def bind_mismatch(name Unk0085, ann String, e Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0086) := …

  # Check.bind_tvar/4
  pub def bind_tvar(_p Unk0087, p1 Unk0087, _tvars Unk0088, acc Map(Unk0089, Vec(Unk0078))) Map(Unk0089, Vec(Unk0078)) := …

  # Check.body_literal_adopts?/2
  pub def body_literal_adopts?(p0 Option(Unk0017), ret String) Bool := …

  # Check.branch_join/1
  pub def branch_join(typed Vec(Tuple(Option(Unk0017), Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.build_fn/2
  pub def build_fn(args Vec(Unk0090), ret Vec(Unk0078)) String := …

  # Check.call_bound_error/5
  pub def call_bound_error(g String, args Vec(Option(Unk0017)), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078))), fbounds Map(String, Vec(Unk0078))) Option(Unk0091) := …

  # Check.call_name/1
  pub def call_name(p0 Unk0092) Vec(Unk0093) := …

  # Check.called_ret/2
  pub def called_ret(ic Map(Unk0080, Map(String, Vec(Unk0078))), f String) Vec(Unk0078) := …

  # Check.called_ret_with/4
  pub def called_ret_with(ic Map(Unk0080, Map(String, Vec(Unk0078))), f String, args_ast Vec(Option(Unk0017)), env Map(String, Vec(Unk0078))) Vec(Unk0078) := …

  # Check.check/1
  pub def check(src String) Unk0094 := …

  # Check.check_bind_stmts/3
  pub def check_bind_stmts(p0 Vec(Unk0095), _env Map(String, Vec(Unk0078)), _ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0086) := …

  # Check.check_binds/2
  pub def check_binds(p0 Func, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0096 := …

  # Check.check_bounds/2
  pub def check_bounds(p0 Func, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0097 := …

  # Check.check_error_set/2
  pub def check_error_set(p0 Unk0098, p1 Unk0099) Tuple(Unk0100, String) := …

  # Check.check_external_caps/1
  pub def check_external_caps(p0 Func) Tuple(Unk0101, String) := …

  # Check.check_func/3
  pub def check_func(p0 Unk0102, ic Map(Unk0080, Map(String, Vec(Unk0078))), eset Unk0099) Unk0103 := …

  # Check.check_labels/1
  pub def check_labels(p0 Func) Unk0104 := …

  # Check.check_numeric_mix/2
  pub def check_numeric_mix(p0 Func, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0105 := …

  # Check.check_program/1
  pub def check_program(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0106 := …

  # Check.check_return/2
  pub def check_return(p0 Func, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0107 := …

  # Check.clause_env/3
  pub def clause_env(pats Unk0108, params Unk0109, ic Map(Unk0080, Map(String, Vec(Unk0078)))) Map(String, Vec(Unk0078)) := …

  # Check.comp_str/1
  pub def comp_str(p0 Unk0110) String := …

  # Check.concrete_type?/1
  pub def concrete_type?(p0 Vec(Unk0078)) Bool := …

  # Check.const_int/1
  pub def const_int(p0 Option(Unk0017)) Tuple(Unk0112, Unk0111) := …

  # Check.ctor_type/2
  pub def ctor_type(ic Map(Unk0080, Map(String, Vec(Unk0078))), name String) Vec(Unk0078) := …

  # Check.ctor_types/2
  pub def ctor_types(types Vec(Type), prog Map(Unk0113, Vec(Unk0114))) Map(Unk0116, Unk0115) := …

  # Check.debottom/1
  pub def debottom(p0 Unk0117) Unk0117 := …

  # Check.declared_set/2
  pub def declared_set(ret Unk0118, tsets Map(Unk0119, Vec(Unk0119))) Tuple(Unk0119, Unk0120) := …

  # Check.direct_tags/1
  pub def direct_tags(f Unk0121) Unk0122 := …

  # Check.error_sets/1
  pub def error_sets(types Vec(Type)) Map(Unk0119, Vec(Unk0119)) := …

  # Check.error_tags/1
  pub def error_tags(p0 Vec(Unk0123)) Vec(Option(Unk0124)) := …

  # Check.fbound_table/1
  pub def fbound_table(funcs Vec(Unk0125)) Unk0126 := …

  # Check.first_bound_violation/4
  pub def first_bound_violation(g String, bounds Unk0127, subs Map(Unk0089, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0091) := …

  # Check.fixpoint/2
  pub def fixpoint(facts Unk0128, table Map(Unk0129, Unk0130)) Map(Unk0129, Unk0130) := …

  # Check.fn_parts/1
  pub def fn_parts(p0 String) Unk0131 := …

  # Check.fn_ret/1
  pub def fn_ret(ft Vec(Unk0078)) Vec(Unk0078) := …

  # Check.fsig/1
  pub def fsig(f Unk0132) Unk0133 := …

  # Check.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Check.generic_ret?/2
  pub def generic_ret?(_ret String, p1 Vec(Unk0134)) Bool := …

  # Check.has_tvar?/1
  pub def has_tvar?(s Vec(Unk0078)) Bool := …

  # Check.impl_table/1
  pub def impl_table(prog Map(Unk0136, Vec(Unk0135))) Unk0137 := …

  # Check.infer/3
  pub def infer(ast Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.infer_block/4
  pub def infer_block(p0 Vec(Unk0138), _env Map(String, Vec(Unk0078)), _ic Map(Unk0080, Map(String, Vec(Unk0078))), value Vec(Unk0078)) Vec(Unk0078) := …

  # Check.infer_return_type/2
  pub def infer_return_type(p0 Func, ic Map(Unk0080, Map(String, Vec(Unk0078)))) String := …

  # Check.infer_tail/3
  pub def infer_tail(p0 Option(Unk0017), _env Map(String, Vec(Unk0078)), _ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.inner_of/1
  pub def inner_of(p0 Unk0087) Unk0087 := …

  # Check.instantiate_ret/2
  pub def instantiate_ret(p0 Unk0139, arg_types Vec(Vec(Unk0078))) Vec(Unk0078) := …

  # Check.int_lit_expr?/1
  pub def int_lit_expr?(p0 Option(Unk0017)) Bool := …

  # Check.int_literal?/1
  pub def int_literal?(n Unk0140) Bool := …

  # Check.join/2
  pub def join(t String, t String) Option(Unk0141) := …

  # Check.join_all/1
  pub def join_all(types Vec(Vec(Unk0078))) String := …

  # Check.kind_prefix/1
  pub def kind_prefix(p0 Unk0142) String := …

  # Check.label_error/1
  pub def label_error(p0 Option(Unk0017)) Tuple(Unk0143, String) := …

  # Check.label_error_children/1
  pub def label_error_children(node Option(Unk0017)) Tuple(Unk0143, String) := …

  # Check.list_elem/1
  pub def list_elem(p0 Vec(Unk0078)) Unk0144 := …

  # Check.list_elems/1
  pub def list_elems(p0 Option(Unk0017)) Vec(Unk0145) := …

  # Check.lit_expr_adopts?/2
  pub def lit_expr_adopts?(p0 Option(Unk0017), ret String) Bool := …

  # Check.lit_range_error/3
  pub def lit_range_error(expr Option(Unk0017), p1 String, name Unk0085) Option(Unk0146) := …

  # Check.literal_adopts?/2
  pub def literal_adopts?(p0 Sum1, ann String) Bool := …

  # Check.literal_ordinal/2
  pub def literal_ordinal(p0 Option(Unk0017), p1 String) Tuple(Unk0147, Int53) := …

  # Check.missing_impl/5
  pub def missing_impl(g String, tvar Unk0148, ty Vec(Unk0078), protos Unk0149, impls Map(String, Vec(Unk0078))) Option(Unk0150) := …

  # Check.narrow/4
  pub def narrow(p0 Sum2, type Vec(Unk0078), _ic Map(Unk0080, Map(String, Vec(Unk0078))), env Map(String, Vec(Unk0078))) Map(String, Vec(Unk0078)) := …

  # Check.num_bits/2
  pub def num_bits(kind Unk0151, w Unk0152) Tuple(Unk0151, Unk0153) := …

  # Check.num_join/2
  pub def num_join(p0 Unk0154, p1 Unk0155) String := …

  # Check.num_kind/1
  pub def num_kind(p0 String) Tuple(Unk0151, Unk0153) := …

  # Check.num_lub/2
  pub def num_lub(x String, y String) Unk0156 := …

  # Check.num_mix?/2
  pub def num_mix?(p0 Unk0157, k Unk0158) Bool := …

  # Check.num_mix_error/5
  pub def num_mix_error(op Unk0159, l Option(Unk0017), r Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0160 := …

  # Check.num_widens?/2
  pub def num_widens?(p0 Unk0161, p1 Unk0162) Bool := …

  # Check.oor_scan/5
  pub def oor_scan(p0 Option(Unk0017), ty String, lo Unk0163, hi Unk0164, n Unk0085) Option(Unk0146) := …

  # Check.opaque_table/1
  pub def opaque_table(prog Map(Unk0166, Vec(Unk0165))) Unk0167 := …

  # Check.ordinal_base/1
  pub def ordinal_base(p0 Vec(Unk0078)) String := …

  # Check.pascal?/1
  pub def pascal?(s Unk0168) Bool := …

  # Check.produced_set/2
  pub def produced_set(f Unk0121, table Map(Unk0170, Unk0169)) Unk0171 := …

  # Check.program_ic/1
  pub def program_ic(p0 Map(Unk0022, Vec(Func))) Map(Unk0080, Map(String, Vec(Unk0078))) := …

  # Check.propagated_callees/1
  pub def propagated_callees(f Unk0121) Unk0172 := …

  # Check.range_base/2
  pub def range_base(ic Map(Unk0080, Map(String, Vec(Unk0078))), n String) Option(Unk0173) := …

  # Check.range_bind/6
  pub def range_bind(name Unk0085, ann String, p2 Unk0174, ce Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0175) := …

  # Check.range_table/1
  pub def range_table(prog Map(Unk0177, Vec(Unk0176))) Unk0178 := …

  # Check.resolve_range/2
  pub def resolve_range(t Vec(Unk0078), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Check.scan_bound_calls/4
  pub def scan_bound_calls(p0 Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078))), fbounds Map(String, Vec(Unk0078))) Option(Unk0179) := …

  # Check.scan_num_mix/3
  pub def scan_num_mix(p0 Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0180) := …

  # Check.scan_num_mix_children/3
  pub def scan_num_mix_children(node Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0180) := …

  # Check.solve_error_sets/2
  pub def solve_error_sets(funcs Vec(Unk0181), tsets Map(Unk0119, Vec(Unk0119))) Map(Unk0129, Unk0130) := …

  # Check.tag_name/1
  pub def tag_name(p0 Unk0182) Option(Unk0124) := …

  # Check.type_table/1
  pub def type_table(types Vec(Type)) Unk0183 := …

  # Check.uint_signed_join/2
  pub def uint_signed_join(u Unk0184, i Unk0184) String := …

  # Check.walk_children/4
  pub def walk_children(node Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078))), fbounds Map(String, Vec(Unk0078))) Option(Unk0179) := …

  # Check.with_callees/1
  pub def with_callees(p0 Vec(Unk0185)) Vec(Unk0093) := …

  # Comptime.eval/1
  pub def eval(p0 Unk0186) Tuple(Unk0187, String) := …

  # Comptime.fold/1
  pub def fold(p0 Option(Unk0017)) Tuple(Unk0188, String) := …

  # Comptime.int_div/3
  pub def int_div(_a Unk0189, p1 Int53, _op Fn(Unk0192, Unk0191, Unk0190)) Tuple(Unk0193, Int53) := …

  # Core.first_unsupported/2
  pub def first_unsupported(node Unk0194, unsup Map(Unk0196, Option(Unk0195))) Option(Unk0195) := …

  # Core.from_arm/1
  pub def from_arm(p0 Unk0197) Unk0198 := …

  # Core.from_expr/1
  pub def from_expr(p0 Option(Unk0017)) Option(Unk0017) := …

  # Core.from_pairs/1
  pub def from_pairs(pairs Vec(Unk0199)) Vec(Tuple(Unk0200, Option(Unk0017))) := …

  # Core.from_pat/1
  pub def from_pat(p0 Sum2) Sum2 := …

  # Core.from_stmt/1
  pub def from_stmt(p0 Unk0201) Tuple(Unk0202, Option(Unk0017)) := …

  # Core.from_tail/1
  pub def from_tail(p0 Unk0203) Option(Unk0017) := …

  # Core.reject_unsupported!/4
  pub def reject_unsupported!(funcs Vec(Unk0204), unsup Map(Unk0196, Option(Unk0195)), target Symbol, exception Symbol) Symbol := …

  # Cst.build/1
  pub def build(tokens Vec(Unk0205)) Unk0206 := …

  # Cst.open/4
  pub def open(open_tok Unk0205, close Unk0207, rest Vec(Unk0205), acc Vec(Tuple(Unk0208, Unk0205))) Tuple(Vec(Tuple(Unk0208, Unk0205)), Vec(Unk0209)) := …

  # Cst.seq/2
  pub def seq(p0 Vec(Unk0205), acc Vec(Tuple(Unk0208, Unk0205))) Tuple(Vec(Tuple(Unk0208, Unk0205)), Vec(Unk0209)) := …

  # Decl.all_impl_decls/1
  pub def all_impl_decls(decls Vec(Unk0210)) Vec(Unk0211) := …

  # Decl.all_impls/1
  pub def all_impls(decls Vec(Unk0210)) Vec(Unk0212) := …

  # Decl.all_protocols/1
  pub def all_protocols(decls Vec(Unk0210)) Vec(Unk0211) := …

  # Decl.assemble/3
  pub def assemble(decls Vec(Unk0213), aliases Unk0214, p2 Unk0215) Unk0216 := …

  # Decl.attach_doc/2
  pub def attach_doc(p0 Tuple(Unk0217, Map(Unk0218, Bool)), doc Bool) Tuple(Unk0217, Map(Unk0218, Bool)) := …

  # Decl.attach_external/3
  pub def attach_external(p0 Unk0219, target Unk0220, spec Unk0221) Tuple(Unk0217, Map(Unk0218, Bool)) := …

  # Decl.attach_targets/2
  pub def attach_targets(p0 Unk0222, targets Unk0223) Tuple(Unk0217, Map(Unk0218, Bool)) := …

  # Decl.balanced_parens/1
  pub def balanced_parens(p0 Vec(Vec(Unk0224))) Tuple(Vec(Unk0224), Vec(Unk0224)) := …

  # Decl.block_seps/5
  pub def block_seps(p0 Vec(Unk0225), _d Int53, _w Int53, _p Int53, acc Vec(Unk0225)) Vec(Unk0225) := …

  # Decl.build_func/1
  pub def build_func(p0 Vec(Unk0226)) Func := …

  # Decl.calls_show_float?/1
  pub def calls_show_float?(p0 Vec(Unk0227)) Bool := …

  # Decl.clause/2
  pub def clause(p0 Unk0228, _arity Unk0229) Clause := …

  # Decl.clause_env/2
  pub def clause_env(p0 Clause, params Unk0230) Map(String, Vec(Unk0078)) := …

  # Decl.collapse_parens/1
  pub def collapse_parens(s Unk0231) Unk0232 := …

  # Decl.collect_aliases/1
  pub def collect_aliases(decls Vec(Unk0210)) Unk0233 := …

  # Decl.collect_macros/1
  pub def collect_macros(decls Vec(Unk0210)) Map(Unk0235, Unk0234) := …

  # Decl.compile/1
  pub def compile(src String) Vec(Tuple(String, Unk0236)) := …

  # Decl.compile_beam/1
  pub def compile_beam(src String) Vec(Tuple(Unk0237, Unk0236)) := …

  # Decl.decl_boundary?/1
  pub def decl_boundary?(p0 Vec(Vec(Unk0224))) Bool := …

  # Decl.decl_kw?/1
  pub def decl_kw?(p0 Vec(Vec(Unk0224))) Bool := …

  # Decl.def_raw/4
  pub def def_raw(name Unk0238, params Unk0239, head_rev Vec(Vec(Unk0224)), body Option(Unk0240)) Unk0241 := …

  # Decl.detok_block/1
  pub def detok_block(tokens Unk0242) Option(Unk0240) := …

  # Decl.extract_parens/1
  pub def extract_parens(str Unk0243) Unk0244 := …

  # Decl.field/1
  pub def field(f Unk0245) Field := …

  # Decl.fields/1
  pub def fields(inside Unk0246) Vec(Unk0247) := …

  # Decl.impl_struct/3
  pub def impl_struct(proto Unk0248, type Unk0249, inner Unk0250) Unk0251 := …

  # Decl.in_scope/2
  pub def in_scope(decls Vec(Unk0210), f Fn(Unk0252, Unk0253)) Vec(Unk0211) := …

  # Decl.inject_stdlib/1
  pub def inject_stdlib(prog Tuple(Unk0255, Vec(Unk0254))) Tuple(Unk0255, Vec(Unk0254)) := …

  # Decl.line_continues?/2
  pub def line_continues?(p0 Vec(Vec(Unk0224)), _rest Vec(Vec(Unk0224))) Bool := …

  # Decl.lower_meta/3
  pub def lower_meta(funcs Vec(Unk0256), decls Vec(Unk0210), targets Option(Unk0257)) Vec(Unk0258) := …

  # Decl.macro_param_names/1
  pub def macro_param_names(pstr Unk0259) Unk0260 := …

  # Decl.mark_pub/1
  pub def mark_pub(p0 Unk0261) Tuple(Unk0217, Map(Unk0218, Bool)) := …

  # Decl.mark_test/1
  pub def mark_test(p0 Unk0262) Tuple(Unk0217, Map(Unk0218, Bool)) := …

  # Decl.meta_clause/5
  pub def meta_clause(p0 Unk0263, _env Map(Unk0235, Unk0234), _p Bool, _params Unk0230, _show Unk0264) Unk0265 := …

  # Decl.needs_show_float?/1
  pub def needs_show_float?(prog Tuple(Unk0255, Vec(Unk0254))) Bool := …

  # Decl.nz/1
  pub def nz(s String) Option(Unk0266) := …

  # Decl.param/1
  pub def param(p Unk0267) Unk0268 := …

  # Decl.parse/1
  pub def parse(src String) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Decl.parse_abstract/4
  pub def parse_abstract(head Unk0269, body_toks Unk0270, pub? Unk0271, doc Unk0272) Opaque := …

  # Decl.parse_abstract_members/1
  pub def parse_abstract_members(toks Unk0270) Unk0273 := …

  # Decl.parse_alias/1
  pub def parse_alias(text Unk0269) Tuple(Unk0275, Unk0274) := …

  # Decl.parse_assoc_binding/1
  pub def parse_assoc_binding(t Unk0276) Tuple(Unk0278, Option(Unk0277)) := …

  # Decl.parse_binder/1
  pub def parse_binder(b Unk0279) Tuple(Unk0280, Vec(Unk0281)) := …

  # Decl.parse_binders/1
  pub def parse_binders(binders Unk0282) Vec(Unk0283) := …

  # Decl.parse_bounds/1
  pub def parse_bounds(text Unk0284) Unk0285 := …

  # Decl.parse_cast_rule/1
  pub def parse_cast_rule(p0 Unk0286) Unk0287 := …

  # Decl.parse_const/3
  pub def parse_const(text Unk0269, pub? Unk0288, doc Unk0289) Const := …

  # Decl.parse_external/1
  pub def parse_external(p0 Vec(Unk0290)) Tuple(Unk0292, Unk0291) := …

  # Decl.parse_head/1
  pub def parse_head(head String) Unk0293 := …

  # Decl.parse_op_rule/1
  pub def parse_op_rule(p0 Unk0286) Unk0294 := …

  # Decl.parse_opaque/3
  pub def parse_opaque(text Unk0269, pub? Unk0295, doc Unk0296) Opaque := …

  # Decl.parse_ordinal/1
  pub def parse_ordinal(p0 Unk0297) Tuple(Unk0299, Unk0298) := …

  # Decl.parse_params/1
  pub def parse_params(str Unk0300) Vec(Unk0301) := …

  # Decl.parse_range/3
  pub def parse_range(text Unk0269, pub? Unk0302, doc Unk0303) Range := …

  # Decl.parse_struct/3
  pub def parse_struct(text Unk0243, pub? Unk0304, doc Unk0305) Struct := …

  # Decl.parse_targets/1
  pub def parse_targets(toks Unk0306) Unk0223 := …

  # Decl.parse_type/3
  pub def parse_type(rest Unk0269, pub? Unk0307, doc Unk0308) Type := …

  # Decl.parse_use/1
  pub def parse_use(text Unk0309) Use := …

  # Decl.proto_method_traits/1
  pub def proto_method_traits(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0310 := …

  # Decl.protocol_defs/4
  pub def protocol_defs(decls Vec(Unk0213), types Unk0311, structs Unk0312, targets Unk0313) Vec(Unk0314) := …

  # Decl.protocol_struct/2
  pub def protocol_struct(name Unk0315, inner Unk0316) Unk0317 := …

  # Decl.protocol_unit/3
  pub def protocol_unit(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Tuple(String, Unk0236)) := …

  # Decl.req_ret/1
  pub def req_ret(p0 Unk0318) Option(Unk0319) := …

  # Decl.skip_nl/1
  pub def skip_nl(p0 Vec(Unk0224)) Vec(Vec(Unk0224)) := …

  # Decl.split2/2
  pub def split2(str Unk0320, sep Unk0321) Tuple(Unk0322, Unk0323) := …

  # Decl.split_decls/1
  pub def split_decls(p0 Vec(Vec(Unk0224))) Vec(Unk0324) := …

  # Decl.split_forall/1
  pub def split_forall(head Unk0325) Unk0326 := …

  # Decl.split_once/2
  pub def split_once(str Unk0269, sep String) Tuple(Unk0328, Unk0327) := …

  # Decl.split_top/2
  pub def split_top(str Unk0329, sep String) Unk0330 := …

  # Decl.strip_type_params/1
  pub def strip_type_params(name Unk0331) Unk0275 := …

  # Decl.subst_const/2
  pub def subst_const(p0 Unk0332, aliases Unk0214) Const := …

  # Decl.subst_fields/2
  pub def subst_fields(fs Vec(Unk0333), aliases Unk0334) Vec(Field) := …

  # Decl.subst_func/2
  pub def subst_func(p0 Unk0335, aliases Unk0214) Func := …

  # Decl.subst_struct/2
  pub def subst_struct(p0 Unk0336, aliases Unk0214) Struct := …

  # Decl.subst_type/2
  pub def subst_type(p0 Unk0337, aliases Unk0214) Type := …

  # Decl.subst_type_str/2
  pub def subst_type_str(type Unk0338, aliases Vec(Unk0339)) Unk0338 := …

  # Decl.subst_variant/2
  pub def subst_variant(p0 Unk0340, aliases Unk0341) Variant := …

  # Decl.take_block/3
  pub def take_block(p0 Vec(Vec(Unk0224)), depth Int53, acc Vec(Vec(Unk0224))) Tuple(Vec(Vec(Unk0224)), Vec(Vec(Unk0224))) := …

  # Decl.take_decl/1
  pub def take_decl(p0 Vec(Vec(Unk0224))) Tuple(Tuple(Unk0217, Map(Unk0218, Bool)), Vec(Unk0224)) := …

  # Decl.take_def/1
  pub def take_def(p0 Vec(Vec(Unk0224))) Tuple(Unk0241, Vec(Vec(Unk0224))) := …

  # Decl.take_head/4
  pub def take_head(name Unk0238, params Unk0239, p2 Vec(Vec(Unk0224)), head Vec(Vec(Unk0224))) Tuple(Unk0241, Vec(Vec(Unk0224))) := …

  # Decl.take_line/2
  pub def take_line(tokens Vec(Vec(Unk0224)), acc Vec(Vec(Unk0224))) Tuple(Vec(Vec(Unk0224)), Vec(Vec(Unk0224))) := …

  # Decl.take_line/3
  pub def take_line(p0 Vec(Vec(Unk0224)), acc Vec(Vec(Unk0224)), _depth Int53) Tuple(Vec(Vec(Unk0224)), Vec(Vec(Unk0224))) := …

  # Decl.take_mod_body/2
  pub def take_mod_body(p0 Vec(Unk0224), acc Vec(Unk0342)) Tuple(Vec(Unk0342), Vec(Unk0224)) := …

  # Decl.take_parens/3
  pub def take_parens(p0 Vec(Unk0224), p1 Int53, acc Vec(Unk0224)) Tuple(Vec(Unk0224), Vec(Unk0224)) := …

  # Decl.take_type/2
  pub def take_type(p0 Vec(Vec(Unk0224)), acc Vec(Vec(Unk0224))) Tuple(Vec(Vec(Unk0224)), Vec(Vec(Unk0224))) := …

  # Decl.take_until_do/2
  pub def take_until_do(p0 Vec(Vec(Unk0224)), acc Vec(Vec(Unk0224))) Tuple(Vec(Vec(Unk0224)), Unk0343) := …

  # Decl.variant/1
  pub def variant(v Unk0243) Variant := …

  # Doc.concat/1
  pub def concat(docs Vec(Tuple(Unk0344, String))) Tuple(Unk0344, String) := …

  # Doc.concat/2
  pub def concat(a Tuple(Unk0344, String), b Tuple(Unk0344, String)) Tuple(Unk0344, String) := …

  # Doc.do_render/5
  pub def do_render(_w Int53, _k Int53, p2 Vec(Unk0345), p3 Vec(Unk0346), out Vec(String)) Vec(String) := …

  # Doc.empty/0
  pub def empty() Tuple(Unk0344, String) := …

  # Doc.fits?/2
  pub def fits?(w Int53, _work Vec(Unk0345)) Bool := …

  # Doc.flat_string/1
  pub def flat_string(p0 Unk0346) String := …

  # Doc.flush_suffix/2
  pub def flush_suffix(p0 Vec(Unk0346), out Vec(String)) Vec(String) := …

  # Doc.group/2
  pub def group(doc Tuple(Unk0344, String), p1 Bool) Unk0347 := …

  # Doc.hardline/0
  pub def hardline() Tuple(Unk0344, String) := …

  # Doc.if_break/2
  pub def if_break(broken Tuple(Unk0344, String), flat Tuple(Unk0344, String)) Tuple(Unk0344, String) := …

  # Doc.join/2
  pub def join(_sep Tuple(Unk0344, String), p1 Vec(Tuple(Unk0344, String))) Tuple(Unk0344, String) := …

  # Doc.line/0
  pub def line() Tuple(Unk0344, String) := …

  # Doc.line_suffix/1
  pub def line_suffix(doc Tuple(Unk0344, String)) Tuple(Unk0344, String) := …

  # Doc.must_break?/1
  pub def must_break?(p0 Tuple(Unk0344, String)) Bool := …

  # Doc.nest/2
  pub def nest(n Vec(Unk0348), doc Tuple(Unk0344, String)) Tuple(Unk0344, String) := …

  # Doc.render/2
  pub def render(doc Tuple(Unk0344, String), width Int53) String := …

  # Doc.softline/0
  pub def softline() Tuple(Unk0344, String) := …

  # Doc.text/1
  pub def text(s String) Tuple(Unk0344, String) := …

  # Doctest.augment/2
  pub def augment(src String, examples Vec(Unk0349)) String := …

  # Doctest.extract/1
  pub def extract(src String) Vec(Unk0349) := …

  # Doctest.exunit_cases/2
  pub def exunit_cases(src String, mod Unk0350) Unk0351 := …

  # Doctest.module_doc_strings/1
  pub def module_doc_strings(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Unk0352) := …

  # Doctest.pairs/1
  pub def pairs(p0 Unk0353) Vec(Unk0354) := …

  # Doctest.run/2
  pub def run(src String, p1 Unk0355) Vec(Unk0356) := …

  # Doctest.run_markdown/1
  pub def run_markdown(md String) Unk0357 := …

  # Exhaustiveness.add_range/4
  pub def add_range(env Tuple(Unk0358, Map(String, String)), type_name String, lo Int53, hi Int53) Tuple(Unk0358, Map(String, String)) := …

  # Exhaustiveness.add_type/3
  pub def add_type(env Tuple(Unk0358, Map(String, String)), type_name String, variants Vec(Tuple(String, Unk0359))) Tuple(Unk0358, Map(String, String)) := …

  # Exhaustiveness.analyze/3
  pub def analyze(arms Vec(Unk0360), n Int53, env Map(Unk0361, Unk0362)) Unk0363 := …

  # Exhaustiveness.arity/2
  pub def arity(_env Map(Unk0361, Unk0362), p1 Unk0364) Int53 := …

  # Exhaustiveness.base_env/0
  pub def base_env() Tuple(Unk0358, Map(String, String)) := …

  # Exhaustiveness.body_core/1
  pub def body_core(body Option(Unk0017)) Option(Unk0017) := …

  # Exhaustiveness.check_case_bodies!/2
  pub def check_case_bodies!(funcs Unk0365, env Unk0366) Unk0367 := …

  # Exhaustiveness.check_match!/3
  pub def check_match!(core Unk0368, env Map(Unk0361, Unk0362), where Unk0369) Unk0370 := …

  # Exhaustiveness.check_one_case!/3
  pub def check_one_case!(p0 Sum1, env Map(Unk0361, Unk0362), where Unk0369) Unk0371 := …

  # Exhaustiveness.collect_cases/2
  pub def collect_cases(p0 Vec(Unk0372), acc Vec(Unk0373)) Vec(Unk0373) := …

  # Exhaustiveness.collect_children/2
  pub def collect_children(struct Vec(Unk0372), acc Vec(Unk0373)) Vec(Unk0373) := …

  # Exhaustiveness.default/1
  pub def default(rows Vec(Unk0374)) Vec(Unk0374) := …

  # Exhaustiveness.head_ctors/1
  pub def head_ctors(rows Vec(Unk0374)) Vec(Unk0375) := …

  # Exhaustiveness.missing_head/2
  pub def missing_head(_env Map(Unk0361, Unk0362), p1 Vec(Unk0375)) Unk0376 := …

  # Exhaustiveness.pascal/1
  pub def pascal(c Unk0377) String := …

  # Exhaustiveness.program_env/3
  pub def program_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0378), ranges Vec(Unk0379)) Tuple(Unk0358, Map(String, String)) := …

  # Exhaustiveness.render/1
  pub def render(p0 Vec(Unk0380)) String := …

  # Exhaustiveness.signature/2
  pub def signature(_env Map(Unk0361, Unk0362), p1 Vec(Unk0375)) Tuple(Unk0382, Vec(Unk0381)) := …

  # Exhaustiveness.specialize/3
  pub def specialize(rows Vec(Unk0374), c Unk0364, env Map(Unk0361, Unk0362)) Vec(Unk0374) := …

  # Exhaustiveness.useful?/3
  pub def useful?(rows Vec(Unk0374), p1 Vec(Unk0383), _env Map(Unk0361, Unk0362)) Bool := …

  # Exhaustiveness.witness/3
  pub def witness(rows Vec(Unk0374), p1 Int53, _env Map(Unk0361, Unk0362)) Tuple(Unk0384, Vec(Unk0376)) := …

  # Fixpoint.check/4
  pub def check(mod Symbol, corpus Vec(String), project Unk0385, p3 Unk0386) Unk0387 := …

  # Format.apply_node/3
  pub def apply_node(p0 Option(Unk0388), base Vec(Unk0348), st Vec(Vec(Unk0348))) Vec(Vec(Unk0348)) := …

  # Format.bd/3
  pub def bd(p0 Vec(Option(Unk0388)), _prev Option(Unk0388), _rf Bool) Tuple(Unk0344, String) := …

  # Format.blank?/1
  pub def blank?(p0 Vec(Option(Unk0388))) Bool := …

  # Format.block_head?/2
  pub def block_head?(p0 Vec(Option(Unk0388)), next Vec(Vec(Option(Unk0388)))) Bool := …

  # Format.boundary?/1
  pub def boundary?(p0 Vec(Option(Unk0388))) Bool := …

  # Format.boundary_tok?/1
  pub def boundary_tok?(p0 Tuple(Unk0389, String)) Bool := …

  # Format.chain?/1
  pub def chain?(nodes Vec(Option(Unk0388))) Bool := …

  # Format.chain_body/2
  pub def chain_body(nodes Vec(Option(Unk0388)), prev Option(Unk0388)) Tuple(Unk0344, String) := …

  # Format.chain_doc/1
  pub def chain_doc(nodes Vec(Option(Unk0388))) Tuple(Unk0344, String) := …

  # Format.chain_link?/2
  pub def chain_link?(a Vec(Option(Unk0388)), b Option(Unk0388)) Bool := …

  # Format.chain_tail/2
  pub def chain_tail(p0 Vec(Option(Unk0388)), _level Unk0390) Tuple(Unk0344, String) := …

  # Format.chunk_on_comma/3
  pub def chunk_on_comma(p0 Vec(Unk0391), cur Vec(Unk0391), acc Vec(Vec(Unk0391))) Vec(Vec(Unk0391)) := …

  # Format.closer_lead?/1
  pub def closer_lead?(p0 Tuple(Unk0389, String)) Bool := …

  # Format.comment_only?/1
  pub def comment_only?(line Vec(Option(Unk0388))) Bool := …

  # Format.cons_group?/1
  pub def cons_group?(inner Vec(Unk0392)) Bool := …

  # Format.cont_lead?/1
  pub def cont_lead?(p0 Tuple(Unk0389, String)) Bool := …

  # Format.decl_kw?/1
  pub def decl_kw?(p0 Tuple(Unk0389, String)) Bool := …

  # Format.declaration_line?/1
  pub def declaration_line?(p0 Vec(Option(Unk0388))) Bool := …

  # Format.ends_with_comment?/1
  pub def ends_with_comment?(line Vec(Option(Unk0388))) Bool := …

  # Format.finish_items/2
  pub def finish_items(cur Vec(Unk0391), acc Vec(Vec(Unk0391))) Vec(Vec(Unk0391)) := …

  # Format.format_result/1
  pub def format_result(src String) Tuple(Unk0393, Unk0394) := …

  # Format.group_doc/4
  pub def group_doc(open Unk0395, inner Vec(Unk0392), close Unk0395, reflow? Bool) Tuple(Unk0344, String) := …

  # Format.has_comment?/1
  pub def has_comment?(nodes Vec(Unk0392)) Bool := …

  # Format.has_tok?/2
  pub def has_tok?(line Vec(Tuple(Unk0397, Tuple(Unk0396, String))), t Tuple(Unk0396, String)) Bool := …

  # Format.head_tok/1
  pub def head_tok(p0 Option(Unk0388)) Tuple(Unk0389, String) := …

  # Format.indent_and_render/4
  pub def indent_and_render(p0 Vec(Vec(Option(Unk0388))), _stack Vec(Vec(Unk0348)), _cont Int53, acc Vec(String)) Vec(String) := …

  # Format.lead_adjust/1
  pub def lead_adjust(p0 Vec(Option(Unk0388))) Int53 := …

  # Format.leading_wrap_op?/1
  pub def leading_wrap_op?(p0 Vec(Option(Unk0388))) Bool := …

  # Format.leaf/1
  pub def leaf(p0 Unk0395) String := …

  # Format.line_doc/1
  pub def line_doc(nodes Vec(Option(Unk0388))) Tuple(Unk0344, String) := …

  # Format.ll/3
  pub def ll(p0 Vec(Unk0398), cur Vec(Unk0398), acc Vec(Vec(Unk0398))) Vec(Vec(Unk0398)) := …

  # Format.logical_lines/1
  pub def logical_lines(nodes Vec(Unk0398)) Vec(Vec(Unk0398)) := …

  # Format.magic_comma?/1
  pub def magic_comma?(inner Vec(Unk0392)) Bool := …

  # Format.mark/1
  pub def mark(nodes Vec(Option(Unk0388))) Vec(Option(Unk0388)) := …

  # Format.mark/3
  pub def mark(p0 Vec(Option(Unk0388)), _prev Option(Unk0388), acc Vec(Option(Unk0388))) Vec(Option(Unk0388)) := …

  # Format.merge_chains/1
  pub def merge_chains(p0 Vec(Vec(Option(Unk0388)))) Vec(Vec(Option(Unk0388))) := …

  # Format.next_code_line/1
  pub def next_code_line(p0 Vec(Vec(Option(Unk0388)))) Vec(Option(Unk0388)) := …

  # Format.node_doc/2
  pub def node_doc(p0 Option(Unk0388), _rf Bool) Tuple(Unk0344, String) := …

  # Format.pop/1
  pub def pop(p0 Vec(Vec(Unk0348))) Vec(Vec(Unk0348)) := …

  # Format.push/2
  pub def push(base Vec(Unk0348), st Vec(Vec(Unk0348))) Vec(Vec(Unk0348)) := …

  # Format.render_line/2
  pub def render_line(nodes Vec(Option(Unk0388)), base Vec(Unk0348)) String := …

  # Format.space?/2
  pub def space?(_prev Tuple(Unk0389, String), p1 Tuple(Unk0389, String)) Bool := …

  # Format.split_items/1
  pub def split_items(nodes Vec(Unk0392)) Vec(Vec(Option(Unk0388))) := …

  # Format.split_level/1
  pub def split_level(nodes Vec(Option(Unk0388))) Unk0390 := …

  # Format.split_node?/2
  pub def split_node?(p0 Option(Unk0388), level Unk0390) Bool := …

  # Format.squeeze_blanks/1
  pub def squeeze_blanks(lines Unk0399) Unk0400 := …

  # Format.tail_tok/1
  pub def tail_tok(p0 Option(Unk0388)) Tuple(Unk0389, String) := …

  # Format.take_until_level/3
  pub def take_until_level(p0 Vec(Option(Unk0388)), _level Unk0390, acc Vec(Option(Unk0388))) Tuple(Vec(Option(Unk0388)), Vec(Option(Unk0388))) := …

  # Format.trailing_comma?/1
  pub def trailing_comma?(inner Vec(Unk0392)) Bool := …

  # Format.trailing_op?/1
  pub def trailing_op?(line Vec(Option(Unk0388))) Bool := …

  # Format.trailing_wrap_op?/1
  pub def trailing_wrap_op?(line Vec(Option(Unk0388))) Bool := …

  # Format.update_stack/4
  pub def update_stack(line Vec(Option(Unk0388)), rest Vec(Vec(Option(Unk0388))), base Vec(Unk0348), stack Vec(Vec(Unk0348))) Vec(Vec(Unk0348)) := …

  # Format.value_end?/1
  pub def value_end?(p0 Option(Unk0388)) Bool := …

  # Format.value_end_tok?/1
  pub def value_end_tok?(p0 Tuple(Unk0389, String)) Bool := …

  # Format.wrap_op_node?/1
  pub def wrap_op_node?(p0 Unk0401) Bool := …

  # Format.wrap_op_tok?/1
  pub def wrap_op_tok?(p0 Tuple(Unk0389, String)) Bool := …

  # Formatting.apply_edits/2
  pub def apply_edits(text String, edits Unk0402) String := …

  # Formatting.bump_del/3
  pub def bump_del(cur Unk0403, old Unk0404, n Int53) Unk0405 := …

  # Formatting.bump_ins/3
  pub def bump_ins(cur Unk0406, old Unk0404, ls Vec(Unk0407)) Unk0408 := …

  # Formatting.clamp/3
  pub def clamp(n Int53, lo Int53, hi Unk0409) Int53 := …

  # Formatting.edit/1
  pub def edit(p0 Unk0410) Unk0411 := …

  # Formatting.flush/2
  pub def flush(p0 Unk0412, acc Vec(Unk0412)) Vec(Unk0412) := …

  # Formatting.formatting/1
  pub def formatting(text String) Vec(Unk0413) := …

  # Formatting.hunks/2
  pub def hunks(old String, new String) Vec(Unk0413) := …

  # Formatting.range_formatting/3
  pub def range_formatting(text String, start_line Int53, end_line Int53) Vec(Unk0414) := …

  # Formatting.start_hunk/1
  pub def start_hunk(old Unk0404) Unk0415 := …

  # Formatting.to_hunks/1
  pub def to_hunks(diff Vec(Unk0416)) Vec(Unk0412) := …

  # FormsEquiv.abstract_code/1
  pub def abstract_code(beam String) Unk0417 := …

  # FormsEquiv.alpha_rename/1
  pub def alpha_rename(form Unk0418) Unk0419 := …

  # FormsEquiv.bool_clause/1
  pub def bool_clause(p0 Unk0420) Tuple(Unk0422, Unk0421) := …

  # FormsEquiv.bool_clause_pair/1
  pub def bool_clause_pair(p0 Vec(Unk0420)) Tuple(Unk0420, Unk0420) := …

  # FormsEquiv.canon_bool_case/1
  pub def canon_bool_case(p0 Vec(Unk0423)) Vec(Unk0423) := …

  # FormsEquiv.diff/2
  pub def diff(a Unk0424, b Unk0424) Tuple(Unk0426, Vec(Unk0425)) := …

  # FormsEquiv.equivalent?/2
  pub def equivalent?(a Unk0424, b Unk0424) Bool := …

  # FormsEquiv.fold_neg_literal/1
  pub def fold_neg_literal(p0 Vec(Unk0427)) Vec(Unk0427) := …

  # FormsEquiv.key/1
  pub def key(p0 Unk0428) Tuple(Unk0429, Unk0430) := …

  # FormsEquiv.normalize/1
  pub def normalize(beam Unk0424) Unk0431 := …

  # FormsEquiv.user_function?/1
  pub def user_function?(p0 Unk0432) Bool := …

  # FormsEquiv.verified?/2
  pub def verified?(oracle Unk0424, port Unk0424) Bool := …

  # FormsEquiv.verify/2
  pub def verify(oracle Unk0424, port Unk0424) Vec(Unk0433) := …

  # FormsEquiv.walk_rename/2
  pub def walk_rename(p0 Unk0418, map Map(Unk0434, Unk0435)) Tuple(Unk0418, Map(Unk0434, Unk0435)) := …

  # FormsEquiv.zero_anno/1
  pub def zero_anno(tuple Vec(Unk0436)) Vec(Unk0436) := …

  # History.dedup_consecutive/1
  pub def dedup_consecutive(p0 Vec(Vec(Unk0437))) Vec(Vec(Unk0437)) := …

  # History.load/0
  pub def load() Vec(Unk0438) := …

  # Infer.app/2
  pub def app(head String, args Vec(Tuple(Unk0439, String))) Tuple(Unk0439, String) := …

  # Infer.app1/2
  pub def app1(head String, s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.apply_spec_terms/4
  pub def apply_spec_terms(p0 Unk0442, _pvars Unk0443, _rvar Tuple(Unk0439, String), store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))) := …

  # Infer.bind/3
  pub def bind(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), id Unk0440, t Tuple(Unk0439, String)) Unk0444 := …

  # Infer.bind_checked/3
  pub def bind_checked(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), i Unk0440, t Tuple(Unk0439, String)) Tuple(Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), Unk0445) := …

  # Infer.bind_params/4
  pub def bind_params(args Unk0446, pvars Unk0447, ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Unk0450 := …

  # Infer.build_ctx/2
  pub def build_ctx(stdlib_map Unk0451, p1 Unk0452) Unk0453 := …

  # Infer.build_ledger/2
  pub def build_ledger(params Unk0454, ret String) Vec(Tuple(String, Unk0455)) := …

  # Infer.call_sig/6
  pub def call_sig(ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), key Unk0456, args Vec(Bool), env Map(String, Tuple(Unk0439, String)), _outer Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.case_arm/1
  pub def case_arm(p0 Unk0457) Tuple(Unk0459, Option(Unk0458)) := …

  # Infer.cluster_name/2
  pub def cluster_name(clusters Map(Tuple(Unk0448, Int53), Unk0442), struct String) String := …

  # Infer.collect_specs/2
  pub def collect_specs(stmts Vec(String), type_env Map(Unk0460, Tuple(Unk0439, String))) Map(Tuple(Unk0448, Int53), Unk0442) := …

  # Infer.collect_types/2
  pub def collect_types(stmts Vec(String), mod_name String) Tuple(Unk0461, Vec(Unk0462)) := …

  # Infer.con/1
  pub def con(name String) Tuple(Unk0439, String) := …

  # Infer.do_unify/3
  pub def do_unify(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), t Tuple(Unk0439, String), t Tuple(Unk0439, String)) Tuple(Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), Unk0445) := …

  # Infer.free_vars/2
  pub def free_vars(store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), t Tuple(Unk0439, String)) Vec(Unk0463) := …

  # Infer.fresh/1
  pub def fresh(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.fresh_n/2
  pub def fresh_n(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), k Int53) Tuple(Vec(Unk0464), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.fresh_num/1
  pub def fresh_num(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.freshen_tvars/2
  pub def freshen_tvars(tvars Vec(Unk0465), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Map(Unk0465, Unk0466), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen/4
  pub def gen(n Bool, _env Map(String, Tuple(Unk0439, String)), _ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen_args_then_fresh/4
  pub def gen_args_then_fresh(args Vec(Bool), env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen_block/4
  pub def gen_block(p0 Vec(Bool), _env Map(String, Tuple(Unk0439, String)), _ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen_cons/5
  pub def gen_cons(h Bool, t Bool, env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen_pat/5
  pub def gen_pat(p0 Vec(Unk0467), pv Tuple(Unk0439, String), env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Map(String, Tuple(Unk0439, String)), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.gen_pat_cons/6
  pub def gen_pat_cons(h Vec(Unk0467), t Vec(Unk0467), pv Tuple(Unk0439, String), env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Map(String, Tuple(Unk0439, String)), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.generalize_map/3
  pub def generalize_map(pvars Unk0468, rvar Tuple(Unk0439, String), store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Map(Unk0469, Unk0470) := …

  # Infer.hole_or/2
  pub def hole_or(p0 Unk0471, h Unk0471) Unk0471 := …

  # Infer.hole_sig?/1
  pub def hole_sig?(p0 Unk0472) Bool := …

  # Infer.infer_group/2
  pub def infer_group(p0 Unk0473, ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442))) Unk0472 := …

  # Infer.instantiate/5
  pub def instantiate(p0 Unk0474, args Vec(Bool), env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.load_prelude_sigs/0
  pub def load_prelude_sigs() Unk0475 := …

  # Infer.mark_num/2
  pub def mark_num(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), t Tuple(Unk0439, String)) Tuple(Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), Unk0476) := …

  # Infer.max_ph/1
  pub def max_ph(p0 Vec(Unk0477)) Int53 := …

  # Infer.maybe_tuple/4
  pub def maybe_tuple(elems Vec(Unk0478), env Map(String, Tuple(Unk0439, String)), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Tuple(Unk0439, String), Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) := …

  # Infer.mod_name/1
  pub def mod_name(p0 Unk0479) String := …

  # Infer.num_conflict?/3
  pub def num_conflict?(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), i Unk0440, t Tuple(Unk0439, String)) Bool := …

  # Infer.numeric_con?/1
  pub def numeric_con?(p0 Tuple(Unk0439, String)) Bool := …

  # Infer.occurs?/3
  pub def occurs?(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), i Unk0440, t Tuple(Unk0439, String)) Bool := …

  # Infer.ok_payload/3
  pub def ok_payload(tail_pairs Vec(Unk0480), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), store Unk0481) Unk0482 := …

  # Infer.parse_type/2
  pub def parse_type(str String, fmap Map(Unk0484, Unk0483)) Tuple(Unk0439, String) := …

  # Infer.pascal/1
  pub def pascal(name Unk0485) String := …

  # Infer.prelude_sigs/0
  pub def prelude_sigs() Unk0475 := …

  # Infer.prime_xmod/2
  pub def prime_xmod(modules Unk0486, stdlib_map Unk0487) Unk0488 := …

  # Infer.put_slot/3
  pub def put_slot(sig Tuple(Unk0489, String), p1 String, ts String) Unk0490 := …

  # Infer.render/3
  pub def render(store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), gmap Map(Unk0469, Unk0470), t Tuple(Unk0439, String)) String := …

  # Infer.render_wp/3
  pub def render_wp(store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), unk_names Map(Unk0491, String), t Tuple(Unk0439, String)) String := …

  # Infer.resolve/2
  pub def resolve(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), p1 Tuple(Unk0439, String)) Tuple(Unk0439, String) := …

  # Infer.resolve_program/2
  pub def resolve_program(sigvars Vec(Unk0492), store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Unk0493 := …

  # Infer.resolve_struct_params/4
  pub def resolve_struct_params(args Unk0494, pvars Unk0495, ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))) := …

  # Infer.result_analysis/3
  pub def result_analysis(clause_envs Vec(Unk0496), ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), store Unk0481) Unk0497 := …

  # Infer.result_tag/1
  pub def result_tag(p0 Unk0498) Tuple(Unk0499, Unk0500) := …

  # Infer.seed_spec/6
  pub def seed_spec(ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), name Unk0448, arity Int53, pvars Unk0443, rvar Tuple(Unk0439, String), store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))) := …

  # Infer.sig_of/1
  pub def sig_of(f Unk0501) Unk0502 := …

  # Infer.sigvar_call/5
  pub def sigvar_call(ctx Map(Unk0449, Map(Tuple(Unk0448, Int53), Unk0442)), key Unk0503, args Unk0504, env Map(String, Tuple(Unk0439, String)), s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String)))) Unk0505 := …

  # Infer.slot_sig/3
  pub def slot_sig(p0 String, ts String, _ Vec(Unk0506)) Unk0507 := …

  # Infer.spec_pair/2
  pub def spec_pair(p0 Unk0508, type_env Map(Unk0460, Tuple(Unk0439, String))) Tuple(Tuple(Unk0509, Unk0510), Unk0511) := …

  # Infer.spec_str/1
  pub def spec_str(p0 Unk0512) String := …

  # Infer.store_new/0
  pub def store_new() Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))) := …

  # Infer.translate_spec/2
  pub def translate_spec(p0 Vec(Unk0513), _e Map(Unk0460, Tuple(Unk0439, String))) Tuple(Unk0439, String) := …

  # Infer.translate_type/2
  pub def translate_type(p0 Unk0514, mod_name String) Tuple(Unk0439, String) := …

  # Infer.tvar?/1
  pub def tvar?(s Unk0484) Unk0515 := …

  # Infer.tvar_name/1
  pub def tvar_name(i Unk0516) Unk0517 := …

  # Infer.type_pair/2
  pub def type_pair(p0 Unk0518, mod_name String) Tuple(Unk0519, Tuple(Unk0439, String)) := …

  # Infer.unify/3
  pub def unify(s Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), a Tuple(Unk0439, String), b Tuple(Unk0439, String)) Tuple(Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), Unk0445) := …

  # Infer.union_spec/3
  pub def union_spec(a Vec(Unk0513), b Vec(Unk0513), e Map(Unk0460, Tuple(Unk0439, String))) Tuple(Unk0439, String) := …

  # Infer.unk_vars/2
  pub def unk_vars(store Tuple(Unk0441, Map(Unk0440, Tuple(Unk0439, String))), v Tuple(Unk0439, String)) Vec(Unk0520) := …

  # Infer.vec_spec/2
  pub def vec_spec(elem Unk0513, e Map(Unk0460, Tuple(Unk0439, String))) Tuple(Unk0439, String) := …

  # Infer.whole_program/4
  pub def whole_program(modules Vec(Tuple(String, Vec(Unk0521))), stdlib Unk0522, p2 Unk0523, p3 Unk0524) Unk0493 := …

  # Infer.xmod_cache/0
  pub def xmod_cache() Unk0525 := …

  # InferLocal.all_funcs/1
  pub def all_funcs(prog Map(Unk0022, Vec(Func))) Vec(Func) := …

  # InferLocal.fill_funcs/2
  pub def fill_funcs(funcs Vec(Func), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Unk0526 := …

  # InferLocal.fill_returns/1
  pub def fill_returns(prog Map(Unk0022, Vec(Func))) Map(Unk0022, Vec(Func)) := …

  # InferLocal.fixpoint/1
  pub def fixpoint(prog Map(Unk0022, Vec(Func))) Map(Unk0022, Vec(Func)) := …

  # InferLocal.pass/2
  pub def pass(prog Map(Unk0022, Vec(Func)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Tuple(Unk0527, Bool) := …

  # Interp.concat_chain/1
  pub def concat_chain(parts Vec(Tuple(Unk0528, String))) Tuple(Unk0528, String) := …

  # Interp.int_type?/1
  pub def int_type?(t Vec(Unk0078)) Bool := …

  # Interp.resolve/4
  pub def resolve(p0 Tuple(Unk0188, String), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078))), show Unk0264) Option(Unk0017) := …

  # Interp.resolve_part/4
  pub def resolve_part(p0 Unk0529, _env Map(String, Vec(Unk0078)), _ic Map(Unk0080, Map(String, Vec(Unk0078))), _show Unk0264) Tuple(Unk0531, Unk0530) := …

  # Interp.stringify/3
  pub def stringify(expr Option(Unk0017), p1 Vec(Unk0078), _show Unk0264) Tuple(Unk0531, Unk0530) := …

  # JS.all_funcs/1
  pub def all_funcs(prog Map(Unk0533, Vec(Unk0532))) Vec(Unk0532) := …

  # JS.arm_return/3
  pub def arm_return(body Unk0534, p1 Unk0535, i53 Bool) String := …

  # JS.bind_lines/1
  pub def bind_lines(binds Vec(Unk0536)) Vec(String) := …

  # JS.block_return/2
  pub def block_return(p0 Vec(Unk0537), i53 Bool) String := …

  # JS.branch_js/2
  pub def branch_js(p0 Sum1, i53 Bool) String := …

  # JS.case_arm_js/2
  pub def case_arm_js(p0 Unk0538, i53 Bool) String := …

  # JS.clause_js/2
  pub def clause_js(p0 Unk0539, i53 Bool) String := …

  # JS.clause_return/3
  pub def clause_return(src Option(Unk0017), params Vec(Unk0540), i53 Bool) String := …

  # JS.cp_lit/2
  pub def cp_lit(cp Unk0541, i53 Bool) String := …

  # JS.dispatcher_js/5
  pub def dispatcher_js(proto Unk0542, method Unk0543, impl_types Vec(Unk0544), reg Unk0545, i53 Bool) String := …

  # JS.expr_js/2
  pub def expr_js(p0 Sum1, i53 Bool) String := …

  # JS.float?/1
  pub def float?(n Unk0546) Bool := …

  # JS.function_js/2
  pub def function_js(p0 Unk0204, _i53 Bool) String := …

  # JS.guarded_return/4
  pub def guarded_return(body Option(Unk0017), p1 Unk0547, params Vec(Unk0540), i53 Bool) String := …

  # JS.js_atom/1
  pub def js_atom(name Unk0548) String := …

  # JS.js_guard!/4
  pub def js_guard!(type String, proto Unk0549, reg Unk0550, i53 Unk0551) Unk0552 := …

  # JS.js_number_int?/1
  pub def js_number_int?(t Unk0553) Bool := …

  # JS.js_str/1
  pub def js_str(s Unk0548) String := …

  # JS.lit_js/2
  pub def lit_js(v Unk0548, i53 Bool) String := …

  # JS.mangle/3
  pub def mangle(proto Unk0554, type Unk0555, method Unk0556) String := …

  # JS.match_elems/3
  pub def match_elems(es Unk0557, acc String, i53 Bool) Unk0558 := …

  # JS.num_js/2
  pub def num_js(n Unk0546, i53 Bool) String := …

  # JS.paren/2
  pub def paren(e Unk0559, i53 Unk0560) String := …

  # JS.pat_match/3
  pub def pat_match(p0 Sum2, _acc String, _i53 Bool) Tuple(Vec(String), Vec(Tuple(Unk0561, String))) := …

  # JS.program_number_mode?/1
  pub def program_number_mode?(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Bool := …

  # JS.protocol_dispatchers_js/2
  pub def protocol_dispatchers_js(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))), i53 Bool) String := …

  # JS.reject_mixed_int_mode!/1
  pub def reject_mixed_int_mode!(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0562 := …

  # JS.reject_wide_int!/2
  pub def reject_wide_int!(name Unk0563, p1 Unk0564) Unk0565 := …

  # JS.stmt_js/2
  pub def stmt_js(p0 Unk0566, i53 Bool) String := …

  # JS.stmt_return/2
  pub def stmt_return(p0 Unk0567, i53 Unk0568) String := …

  # JS.struct_name_set/1
  pub def struct_name_set(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0569 := …

  # JS.sum_ctor_map/1
  pub def sum_ctor_map(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0570 := …

  # JS.sum_guard_js/1
  pub def sum_guard_js(ctors Vec(Unk0571)) String := …

  # JVM.all_funcs/1
  pub def all_funcs(prog Map(Unk0573, Vec(Unk0572))) Vec(Unk0572) := …

  # JVM.all_types/1
  pub def all_types(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # JVM.bind_str/1
  pub def bind_str(p0 Vec(Unk0574)) String := …

  # JVM.block_value/1
  pub def block_value(p0 Vec(Unk0537)) String := …

  # JVM.branch_kt/1
  pub def branch_kt(p0 Sum1) String := …

  # JVM.case_arms/2
  pub def case_arms(arms Unk0575, acc String) Tuple(Vec(Unk0576), Unk0577) := …

  # JVM.clause_lines/1
  pub def clause_lines(p0 Vec(Unk0578)) Tuple(String, Bool) := …

  # JVM.clause_match/1
  pub def clause_match(pats Unk0579) Unk0580 := …

  # JVM.clause_value/2
  pub def clause_value(src Option(Unk0017), params Vec(Unk0540)) String := …

  # JVM.closed_or_cond/3
  pub def closed_or_cond(p0 Vec(Unk0581), line String, _rest Vec(Unk0578)) Tuple(String, Bool) := …

  # JVM.expr_kt/1
  pub def expr_kt(p0 Sum1) String := …

  # JVM.function_kt/1
  pub def function_kt(p0 Unk0582) String := …

  # JVM.guarded_arm/2
  pub def guarded_arm(body_kt String, p1 Unk0583) String := …

  # JVM.guarded_return/3
  pub def guarded_return(body Unk0584, p1 Unk0585, params Vec(Unk0586)) String := …

  # JVM.kotlin_module/2
  pub def kotlin_module(src String, p1 Unk0587) String := …

  # JVM.kt_str/1
  pub def kt_str(s Unk0588) String := …

  # JVM.kt_type/1
  pub def kt_type(p0 String) Unk0589 := …

  # JVM.lit_kt/1
  pub def lit_kt(v Unk0588) String := …

  # JVM.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Tuple(Vec(String), Vec(Tuple(Unk0590, String))) := …

  # JVM.prepend_if/3
  pub def prepend_if(tests Vec(Unk0581), line String, rest Vec(Unk0578)) Tuple(String, Bool) := …

  # JVM.run_or_cond/3
  pub def run_or_cond(p0 Vec(Unk0581), line String, rest Vec(Unk0578)) Tuple(String, Bool) := …

  # JVM.stmt_kt/1
  pub def stmt_kt(p0 Unk0591) String := …

  # JVM.stmt_value/1
  pub def stmt_value(p0 Unk0592) String := …

  # JVM.sum_decl/1
  pub def sum_decl(t Unk0593) String := …

  # JVM.to_jar/3
  pub def to_jar(src String, jar_path String, p2 Unk0594) Unk0595 := …

  # JVM.variant_decl/2
  pub def variant_decl(p0 Unk0596, tname Unk0597) String := …

  # Lexer.binify/1
  pub def binify(acc Vec(String)) Unk0598 := …

  # Lexer.capture_hole/3
  pub def capture_hole(p0 String, _d Int53, _acc Vec(String)) Tuple(Unk0598, Unk0599) := …

  # Lexer.char_escape/1
  pub def char_escape(p0 Unk0600) Tuple(Int53, Unk0601) := …

  # Lexer.close_char/1
  pub def close_char(p0 String) Unk0602 := …

  # Lexer.collapse_nl/1
  pub def collapse_nl(tokens Unk0603) Unk0604 := …

  # Lexer.detokenize/2
  pub def detokenize(tokens Unk0605, p1 String) String := …

  # Lexer.escape_str/1
  pub def escape_str(s Unk0606) String := …

  # Lexer.expr_tokens/1
  pub def expr_tokens(src String) Vec(Vec(Vec(Unk0607))) := …

  # Lexer.lex/2
  pub def lex(str String, acc Vec(Tuple(Unk0608, String))) Unk0609 := …

  # Lexer.lex_char/1
  pub def lex_char(p0 String) Tuple(Unk0610, Unk0602) := …

  # Lexer.lex_parts/3
  pub def lex_parts(p0 String, _lit Vec(String), _parts Vec(Tuple(Unk0611, Unk0598))) Tuple(Vec(Tuple(Unk0611, Unk0598)), Unk0612) := …

  # Lexer.lex_string_token/1
  pub def lex_string_token(str String) Tuple(Tuple(Unk0615, Vec(Unk0614)), Unk0613) := …

  # Lexer.parse_hex!/1
  pub def parse_hex!(hex Unk0601) Int53 := …

  # Lexer.punct/1
  pub def punct(str String) Option(Unk0616) := …

  # Lexer.string_token/1
  pub def string_token(parts Vec(Unk0614)) Tuple(Unk0615, Vec(Unk0614)) := …

  # Lexer.strip_trivia/1
  pub def strip_trivia(tokens Unk0617) Unk0618 := …

  # Lexer.take_comment/1
  pub def take_comment(str String) Tuple(Unk0619, String) := …

  # Lexer.take_hex/2
  pub def take_hex(str Unk0620, max Int53) Tuple(String, Unk0620) := …

  # Lexer.take_hex/3
  pub def take_hex(p0 Unk0620, max Int53, acc String) Tuple(String, Unk0620) := …

  # Lexer.tok_str/2
  pub def tok_str(p0 Unk0621, nl_as String) String := …

  # Lexer.tokenize/1
  pub def tokenize(src String) Unk0622 := …

  # Lexer.tokenize_trivia/1
  pub def tokenize_trivia(src String) Unk0609 := …

  # Lexer.word/1
  pub def word(w String) Tuple(Unk0608, String) := …

  # Livebook.eval/1
  pub def eval(source String) Unk0623 := …

  # Livebook.output/1
  pub def output(p0 Vec(String)) Unk0623 := …

  # Livebook.run/2
  pub def run(session Unk0624, source String) Tuple(Unk0625, Unk0624) := …

  # Livebook.session_pid/0
  pub def session_pid() Unk0626 := …

  # Lower.add_list_elem_vars/2
  pub def add_list_elem_vars(acc Unk0627, p1 Unk0628) Unk0627 := …

  # Lower.add_var/2
  pub def add_var(acc Unk0627, p1 Unk0629) Unk0627 := …

  # Lower.all_pat_vars/1
  pub def all_pat_vars(p0 Sum2) Vec(Unk0630) := …

  # Lower.arm_rebinds/3
  pub def arm_rebinds(pats Unk0631, iso Unk0632, used Unk0633) Vec(Unk0634) := …

  # Lower.assoc/1
  pub def assoc(op String) Unk0635 := …

  # Lower.body_ast/2
  pub def body_ast(src Unk0636, ctx Unk0637) Unk0638 := …

  # Lower.borrow_arg/5
  pub def borrow_arg(a Tuple(Unk0188, String), pt String, funs Map(Unk0639, Unk0640), borrowed Bool, ec Unk0641) Unk0642 := …

  # Lower.borrow_value/2
  pub def borrow_value(p0 Tuple(Unk0188, String), _borrowed Bool) Tuple(Unk0188, String) := …

  # Lower.borrowed_in_pat/2
  pub def borrowed_in_pat(p0 Sum2, p1 Bool) Vec(Unk0643) := …

  # Lower.borrowed_vars/2
  pub def borrowed_vars(params Unk0644, pats Unk0645) Option(Unk0646) := …

  # Lower.build_env/3
  pub def build_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0647), ranges Vec(Unk0648)) Unk0649 := …

  # Lower.build_meta/1
  pub def build_meta(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0650 := …

  # Lower.build_struct_meta/1
  pub def build_struct_meta(structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0651 := …

  # Lower.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Lower.case_guard/3
  pub def case_guard(p0 Option(Unk0017), _ Symbol, _ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.catchall_pat?/1
  pub def catchall_pat?(p0 Sum2) Bool := …

  # Lower.char_vars/2
  pub def char_vars(params Unk0654, pats Unk0655) Unk0656 := …

  # Lower.check!/2
  pub def check!(p0 Map(Unk0657, Vec(Unk0010)), _env Unk0649) Unk0658 := …

  # Lower.coerce_string_ast/2
  pub def coerce_string_ast(p0 Sum1, ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.coerce_string_branch/2
  pub def coerce_string_branch(p0 Sum1, ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.collect_ids/2
  pub def collect_ids(p0 Vec(Unk0659), acc Unk0633) Unk0633 := …

  # Lower.collect_owned_field_vars/3
  pub def collect_owned_field_vars(p0 Unk0660, ctx Map(Unk0662, Unk0661), acc Unk0663) Unk0663 := …

  # Lower.compile/5
  pub def compile(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0657, Vec(Unk0010)), p2 Unk0664, p3 Unk0665, p4 Unk0310) Unk0236 := …

  # Lower.compile_beam/4
  pub def compile_beam(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0657, Vec(Unk0010)), p2 Unk0666, p3 Unk0667) Unk0236 := …

  # Lower.compile_elixir/4
  pub def compile_elixir(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0657, Vec(Unk0010)), p2 Unk0668, p3 Unk0669) Unk0236 := …

  # Lower.compile_module/1
  pub def compile_module(p0 Unk0670) Unk0236 := …

  # Lower.compile_module_beam/1
  pub def compile_module_beam(p0 Unk0671) Unk0236 := …

  # Lower.cons_tail_names/1
  pub def cons_tail_names(p0 Sum2) Vec(Unk0672) := …

  # Lower.cons_tail_rebinds/1
  pub def cons_tail_rebinds(p0 Sum2) Vec(String) := …

  # Lower.const_set/1
  pub def const_set(consts Vec(Unk0673)) Unk0674 := …

  # Lower.core_pat_ex/1
  pub def core_pat_ex(surface Sum2) String := …

  # Lower.core_pat_rs/2
  pub def core_pat_rs(surface Sum2, meta Unk0675) String := …

  # Lower.core_pat_vars/1
  pub def core_pat_vars(p0 Sum2) Vec(Unk0676) := …

  # Lower.ctx/4
  pub def ctx(meta Unk0650, smeta Unk0651, cset Unk0674, p3 Unk0677) Map(Unk0662, Unk0661) := …

  # Lower.deref_ids/2
  pub def deref_ids(ast Tuple(Unk0678, String), p1 Vec(Unk0679)) Tuple(Unk0678, String) := …

  # Lower.elixir_clauses/3
  pub def elixir_clauses(func Map(Unk0657, Vec(Unk0010)), ctx Unk0680, def_kw String) String := …

  # Lower.emit/3
  pub def emit(p0 Option(Unk0017), _t Symbol, _ec Tuple(Unk0652, Unk0653)) Tuple(String, Int53) := …

  # Lower.emit_ast/2
  pub def emit_ast(ast Option(Unk0017), target Symbol) Unk0681 := …

  # Lower.emit_block/3
  pub def emit_block(p0 Sum1, p1 Symbol, _ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.emit_ctx/1
  pub def emit_ctx(p0 Unk0682) Tuple(Unk0684, Unk0683) := …

  # Lower.emit_expr/2
  pub def emit_expr(src String, target Symbol) Unk0685 := …

  # Lower.enum_generics/2
  pub def enum_generics(name Unk0686, parametric Map(Unk0686, Vec(Unk0687))) String := …

  # Lower.ex_const/2
  pub def ex_const(c Unk0673, ctx Unk0680) String := …

  # Lower.ex_doc/2
  pub def ex_doc(p0 Vec(Unk0010), _attr String) String := …

  # Lower.ex_struct/1
  pub def ex_struct(s Unk0688) String := …

  # Lower.ex_typespec/1
  pub def ex_typespec(t Map(Unk0689, Vec(Unk0010))) String := …

  # Lower.ex_use/1
  pub def ex_use(p0 Unk0690) String := …

  # Lower.flatten_concat/1
  pub def flatten_concat(p0 Sum1) Vec(Sum1) := …

  # Lower.fn_all_tvars/3
  pub def fn_all_tvars(func Map(Unk0657, Vec(Unk0010)), pinst Unk0691, ec Tuple(Unk0693, Unk0692)) Vec(Unk0010) := …

  # Lower.guard_str/4
  pub def guard_str(c Map(Unk0694, String), target Symbol, ec Tuple(Unk0652, Unk0653), p3 Unk0695) String := …

  # Lower.impl_param/2
  pub def impl_param(p0 Unk0696, rust_type String) String := …

  # Lower.infer_concrete_params/3
  pub def infer_concrete_params(func Map(Unk0657, Vec(Unk0010)), params Vec(Unk0697), ec Tuple(Unk0693, Unk0692)) Vec(String) := …

  # Lower.infer_tvar_binding/2
  pub def infer_tvar_binding(p0 Unk0698, ec Unk0699) Unk0700 := …

  # Lower.insert_borrows/4
  pub def insert_borrows(p0 Option(Unk0017), funs Map(Unk0639, Unk0640), ec Unk0641, borrowed Bool) Tuple(Unk0188, String) := …

  # Lower.iso_cons_positions/1
  pub def iso_cons_positions(func Map(Unk0657, Vec(Unk0010))) Unk0632 := …

  # Lower.list_rpat?/1
  pub def list_rpat?(p0 Unk0701) Bool := …

  # Lower.member_scan/3
  pub def member_scan(p0 Vec(Unk0702), _name Vec(Unk0703), _prev Bool) Bool := …

  # Lower.module_elixir/1
  pub def module_elixir(p0 Unk0704) String := …

  # Lower.module_rust/1
  pub def module_rust(p0 Unk0705) String := …

  # Lower.ofb/3
  pub def ofb(p0 Vec(Unk0706), ctx Map(Unk0662, Unk0661), acc Unk0663) Unk0663 := …

  # Lower.owned_arg?/2
  pub def owned_arg?(p0 Tuple(Unk0188, String), _funs Map(Unk0639, Unk0640)) Bool := …

  # Lower.owned_field_binders/2
  pub def owned_field_binders(ast Vec(Unk0706), ctx Map(Unk0662, Unk0661)) Unk0663 := …

  # Lower.owned_field_var?/2
  pub def owned_field_var?(p0 Tuple(Unk0188, String), ec Unk0641) Bool := …

  # Lower.owned_scrut?/2
  pub def owned_scrut?(p0 Unk0707, _ctx Map(Unk0662, Unk0661)) Bool := …

  # Lower.owned_str_arg/1
  pub def owned_str_arg(s Unk0708) Unk0709 := …

  # Lower.p/4
  pub def p(node Option(Unk0017), ctx Int53, t Symbol, ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.pair_inst/2
  pub def pair_inst(func Map(Unk0657, Vec(Unk0010)), ec Tuple(Unk0693, Unk0692)) Unk0691 := …

  # Lower.param_rtypes/2
  pub def param_rtypes(name Unk0639, funs Map(Unk0639, Unk0640)) Vec(String) := …

  # Lower.parametric_param_map/1
  pub def parametric_param_map(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0710 := …

  # Lower.parametric_used?/2
  pub def parametric_used?(func Map(Unk0657, Vec(Unk0010)), name Unk0711) Bool := …

  # Lower.pascal?/1
  pub def pascal?(s Unk0712) Bool := …

  # Lower.pat_ex/1
  pub def pat_ex(p0 Sum2) String := …

  # Lower.pat_rs/2
  pub def pat_rs(p0 Sum2, _ Unk0675) String := …

  # Lower.pipe_to_call/2
  pub def pipe_to_call(l Unk0713, p1 Sum1) Option(Unk0017) := …

  # Lower.proto_method_traits/1
  pub def proto_method_traits(protocols Vec(Map(Unk0009, Vec(Unk0010)))) Unk0714 := …

  # Lower.pub_sig_type_names/1
  pub def pub_sig_type_names(funcs Unk0715) Unk0716 := …

  # Lower.ref_type/2
  pub def ref_type(p0 String, self_repr Unk0717) String := …

  # Lower.resolve_consts/2
  pub def resolve_consts(p0 Option(Unk0017), cset Unk0718) Tuple(Unk0188, String) := …

  # Lower.resolve_rust_pats/2
  pub def resolve_rust_pats(p0 Option(Unk0017), meta Unk0675) Tuple(Unk0188, String) := …

  # Lower.resolve_structs/2
  pub def resolve_structs(p0 Option(Unk0017), smeta Unk0719) Tuple(Unk0188, String) := …

  # Lower.resolve_variants/2
  pub def resolve_variants(p0 Option(Unk0017), meta Map(Unk0720, Option(Unk0721))) Tuple(Unk0188, String) := …

  # Lower.rest_pat_rs/1
  pub def rest_pat_rs(p0 Sum2) String := …

  # Lower.result_parts/1
  pub def result_parts(ret String) Tuple(Unk0722, String) := …

  # Lower.result_payload/3
  pub def result_payload(val Option(Unk0017), string? Bool, ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.rewrite_proto_calls/2
  pub def rewrite_proto_calls(p0 Vec(Unk0723), methods Unk0724) Vec(Unk0723) := …

  # Lower.rpat/1
  pub def rpat(p0 Sum2) String := …

  # Lower.rs_doc/2
  pub def rs_doc(p0 Vec(Unk0010), _prefix String) String := …

  # Lower.rust_arm_body/2
  pub def rust_arm_body(p0 Option(Unk0017), s String) String := …

  # Lower.rust_case/4
  pub def rust_case(scrut Option(Unk0017), arms Vec(Unk0725), body_fn Fn(Option(Unk0017), String), ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.rust_const/2
  pub def rust_const(c Unk0673, ctx Map(Unk0662, Unk0661)) String := …

  # Lower.rust_enum/3
  pub def rust_enum(t Map(Unk0009, Vec(Unk0010)), p1 String, p2 Unk0710) String := …

  # Lower.rust_fn/4
  pub def rust_fn(p0 Map(Unk0657, Vec(Unk0010)), _ctx Map(Unk0662, Unk0661), vis String, _base_ec Tuple(Unk0684, Unk0683)) String := …

  # Lower.rust_generics/1
  pub def rust_generics(p0 Unk0726) String := …

  # Lower.rust_impl/4
  pub def rust_impl(p0 Map(Unk0009, Vec(Unk0010)), protocols Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0662, Unk0661), base_ec Tuple(Unk0684, Unk0683)) String := …

  # Lower.rust_impl_method/6
  pub def rust_impl_method(method Unk0727, sig Unk0728, rust_type String, c Map(Unk0662, Unk0661), copy_recv? Bool, base_ec Tuple(Unk0684, Unk0683)) String := …

  # Lower.rust_lit_type/1
  pub def rust_lit_type(p0 Unk0729) String := …

  # Lower.rust_owned_elem/2
  pub def rust_owned_elem(p0 Option(Unk0017), ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.rust_program/1
  pub def rust_program(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) String := …

  # Lower.rust_proto_body/3
  pub def rust_proto_body(src Unk0730, c Map(Unk0732, Unk0731), ec Unk0733) Unk0734 := …

  # Lower.rust_protocols/4
  pub def rust_protocols(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0735 := …

  # Lower.rust_scrut/2
  pub def rust_scrut(params Unk0736, iso Unk0632) String := …

  # Lower.rust_struct/2
  pub def rust_struct(s Unk0737, p1 Unk0738) String := …

  # Lower.rust_total_shim?/1
  pub def rust_total_shim?(func Map(Unk0657, Vec(Unk0010))) Bool := …

  # Lower.rust_trait/1
  pub def rust_trait(p0 Unk0739) String := …

  # Lower.rust_use/1
  pub def rust_use(p0 Unk0740) String := …

  # Lower.rustify_parametric/2
  pub def rustify_parametric(rust_type String, pinst Vec(Unk0741)) String := …

  # Lower.scalar_literal?/1
  pub def scalar_literal?(p0 Tuple(Unk0188, String)) Bool := …

  # Lower.sig_param/2
  pub def sig_param(p String, self_repr Unk0742) String := …

  # Lower.slice_binders/2
  pub def slice_binders(params Unk0743, pats Vec(Sum2)) Unk0663 := …

  # Lower.slice_elem_vars/1
  pub def slice_elem_vars(p0 Sum2) Vec(Unk0744) := …

  # Lower.slice_var?/2
  pub def slice_var?(p0 Sum1, ec Tuple(Unk0652, Unk0653)) Bool := …

  # Lower.str_lit/1
  pub def str_lit(s Unk0745) String := …

  # Lower.strip_prefix/2
  pub def strip_prefix(rest Vec(Unk0746), p1 Vec(Unk0703)) Tuple(Unk0747, Vec(Unk0746)) := …

  # Lower.struct_pairs/4
  pub def struct_pairs(name Unk0748, labels Vec(Unk0749), args Vec(Option(Unk0017)), smeta Unk0719) Unk0750 := …

  # Lower.subst_assoc/2
  pub def subst_assoc(t String, assoc_rust Vec(Unk0751)) String := …

  # Lower.tail_expr/1
  pub def tail_expr(p0 Unk0752) Unk0752 := …

  # Lower.tail_slice_id?/2
  pub def tail_slice_id?(p0 Option(Unk0017), ec Tuple(Unk0652, Unk0653)) Bool := …

  # Lower.to_elixir/4
  pub def to_elixir(func Map(Unk0657, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), p2 Unk0753, p3 Unk0651) Unk0754 := …

  # Lower.to_rust/6
  pub def to_rust(func Map(Unk0657, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), meta Unk0650, p3 Unk0755, p4 Unk0651, p5 Unk0756) Unk0757 := …

  # Lower.trait_impl_block/4
  pub def trait_impl_block(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0662, Unk0661), base_ec Tuple(Unk0684, Unk0683)) String := …

  # Lower.trait_params/2
  pub def trait_params(param_str String, self_repr Unk0742) String := …

  # Lower.tuple_or_one/2
  pub def tuple_or_one(p0 Vec(Sum2), f Fn(Sum2, String)) String := …

  # Lower.tvar_name?/1
  pub def tvar_name?(t Unk0758) Bool := …

  # Lower.type_idents/1
  pub def type_idents(p0 Unk0759) Vec(Unk0760) := …

  # Lower.type_param_tvars/1
  pub def type_param_tvars(t Unk0761) Unk0762 := …

  # Lower.used_ids/1
  pub def used_ids(ast Option(Unk0017)) Unk0633 := …

  # Lower.user_type?/2
  pub def user_type?(t Unk0763, ctx Map(Unk0662, Unk0661)) Bool := …

  # Lower.variant_info/2
  pub def variant_info(meta Map(Unk0720, Option(Unk0721)), name Unk0712) Option(Unk0721) := …

  # Lower.variant_lit/2
  pub def variant_lit(info Option(Unk0721), pairs Vec(Unk0764)) Tuple(Unk0188, String) := …

  # Lower.variant_pairs/3
  pub def variant_pairs(info Option(Unk0721), args Vec(Option(Unk0017)), meta Map(Unk0720, Option(Unk0721))) Vec(Unk0764) := …

  # Lower.widen_char_arith/2
  pub def widen_char_arith(p0 Option(Unk0017), cvars Unk0765) Tuple(Unk0188, String) := …

  # Lower.with_chain_rs/4
  pub def with_chain_rs(p0 Vec(Unk0766), body String, _else_rs String, _ec Tuple(Unk0652, Unk0653)) String := …

  # Lower.word_member?/2
  pub def word_member?(str Unk0767, name Unk0711) Bool := …

  # Lower.word_scan/4
  pub def word_scan(p0 Vec(Unk0768), _name Vec(Unk0703), _repl String, _prev Bool) String := …

  # Lower.wrap_char/2
  pub def wrap_char(p0 Tuple(Unk0188, String), _cvars Unk0765) Tuple(Unk0188, String) := …

  # Macro.binders_here/1
  pub def binders_here(p0 Vec(Unk0769)) Vec(Unk0770) := …

  # Macro.build_env/1
  pub def build_env(defs Unk0771) Map(Unk0235, Unk0234) := …

  # Macro.check_portable!/2
  pub def check_portable!(name Unk0772, tmpl Option(Unk0017)) Unk0773 := …

  # Macro.collect_binders/1
  pub def collect_binders(node Vec(Unk0769)) Vec(Unk0770) := …

  # Macro.do_expand/4
  pub def do_expand(_env Map(Unk0235, Unk0234), _ast Option(Unk0017), d Int53, _p Bool) Tuple(Unk0188, String) := …

  # Macro.expand/3
  pub def expand(env Map(Unk0235, Unk0234), ast Option(Unk0017), p2 Vec(Tuple(Unk0774, Bool))) Option(Unk0017) := …

  # Macro.freshen/2
  pub def freshen(tmpl Vec(Unk0769), params Unk0775) Tuple(Unk0188, Vec(Unk0776)) := …

  # Macro.introduces_failable_bind?/1
  pub def introduces_failable_bind?(node Option(Unk0017)) Bool := …

  # Macro.map_node/2
  pub def map_node(p0 Option(Unk0017), f Fn(Option(Unk0017), Tuple(Unk0188, String))) Tuple(Unk0188, String) := …

  # Macro.rename/2
  pub def rename(p0 Vec(Unk0769), ren Map(Unk0777, Vec(Unk0776))) Tuple(Unk0188, Vec(Unk0776)) := …

  # Macro.substitute/2
  pub def substitute(p0 Tuple(Unk0188, Vec(Unk0776)), subst Map(Unk0778, Option(Unk0017))) Option(Unk0017) := …

  # Macro.walk_for_with/1
  pub def walk_for_with(p0 Option(Unk0017)) Tuple(Unk0188, String) := …

  # Opaque.do_erase/2
  pub def do_erase(prog Unk0779, ctx Tuple(Unk0780, Unk0781)) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase/1
  pub def erase(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase_clause/3
  pub def erase_clause(p0 Unk0782, _ctx Unk0783, _env Unk0784) Clause := …

  # Opaque.erase_const/2
  pub def erase_const(p0 Unk0785, p1 Unk0786) Const := …

  # Opaque.erase_ctx/1
  pub def erase_ctx(all Vec(Unk0787)) Tuple(Unk0780, Unk0781) := …

  # Opaque.erase_func/2
  pub def erase_func(p0 Unk0788, p1 Tuple(Unk0780, Unk0781)) Func := …

  # Opaque.erase_mod/2
  pub def erase_mod(p0 Unk0789, ctx Tuple(Unk0780, Unk0781)) Mod := …

  # Opaque.erase_struct/2
  pub def erase_struct(p0 Unk0790, p1 Tuple(Unk0780, Unk0781)) Struct := …

  # Opaque.erase_type/2
  pub def erase_type(p0 Unk0791, p1 Tuple(Unk0780, Unk0781)) Type := …

  # Opaque.erase_variant/2
  pub def erase_variant(p0 Unk0792, names Unk0793) Variant := …

  # Opaque.opaques/1
  pub def opaques(prog Map(Unk0794, Vec(Unk0787))) Vec(Unk0787) := …

  # Opaque.strip/3
  pub def strip(p0 Vec(Unk0795), p1 Unk0796, env Map(String, Vec(Unk0078))) Vec(Unk0795) := …

  # Opaque.strip_into/3
  pub def strip_into(ast Vec(Unk0795), ctx Unk0796, env Map(String, Vec(Unk0078))) Vec(Unk0795) := …

  # Opaque.subst/2
  pub def subst(p0 Option(Unk0797), _names Unk0798) Option(Unk0797) := …

  # Opaque.subst_fix/4
  pub def subst_fix(type Option(Unk0797), _names Unk0798, _re Unk0799, p3 Int53) Option(Unk0797) := …

  # PatternLower.add_struct/3
  pub def add_struct(env Tuple(Unk0358, Map(String, String)), name String, fields Vec(String)) Tuple(Unk0358, Map(String, String)) := …

  # PatternLower.lower/2
  pub def lower(pat Sum2, env Map(Unk0361, Unk0362)) Tuple(Unk0800, Bool) := …

  # PatternLower.lower_clause/2
  pub def lower_clause(p0 Unk0801, env Map(Unk0361, Unk0362)) Unk0360 := …

  # PatternLower.lower_list/3
  pub def lower_list(p0 Vec(Sum2), p1 Sum2, _env Map(Unk0361, Unk0362)) Tuple(Unk0800, Bool) := …

  # PatternLower.lower_many/2
  pub def lower_many(ps Vec(Sum2), env Map(Unk0361, Unk0362)) Unk0802 := …

  # PortAnalysis.analyze/1
  pub def analyze(sources Unk0803) Unk0804 := …

  # PortAnalysis.case_arm_sets/1
  pub def case_arm_sets(ast Unk0805) Vec(Unk0806) := …

  # PortAnalysis.clause_head_sets/1
  pub def clause_head_sets(ast Unk0805) Vec(Unk0806) := …

  # PortAnalysis.cluster_sums/1
  pub def cluster_sums(sets Vec(Unk0807)) Unk0523 := …

  # PortAnalysis.collect_errors/2
  pub def collect_errors(ast Unk0808, acc Unk0809) Unk0809 := …

  # PortAnalysis.collect_groups/1
  pub def collect_groups(p0 Unk0810) Vec(Unk0521) := …

  # PortAnalysis.collect_structs/2
  pub def collect_structs(ast Unk0811, acc Unk0812) Unk0812 := …

  # PortAnalysis.decision_stats/2
  pub def decision_stats(data Unk0813, subs Map(String, Unk0814)) Tuple(Int53, Int53) := …

  # PortAnalysis.dispatch_sets/1
  pub def dispatch_sets(ast Unk0805) Vec(Unk0807) := …

  # PortAnalysis.error_proposal/1
  pub def error_proposal(p0 Unk0815) Unk0816 := …

  # PortAnalysis.error_shape/1
  pub def error_shape(p0 Unk0817) Tuple(Unk0818, Option(Unk0819)) := …

  # PortAnalysis.errors_section/1
  pub def errors_section(data Unk0813) String := …

  # PortAnalysis.head_name_pats/1
  pub def head_name_pats(p0 Unk0820) Tuple(Unk0821, Vec(Unk0822)) := …

  # PortAnalysis.holes_section/2
  pub def holes_section(data Unk0813, subs Map(Unk0823, Unk0823)) String := …

  # PortAnalysis.module_name/1
  pub def module_name(p0 Unk0824) String := …

  # PortAnalysis.module_report/3
  pub def module_report(file Unk0825, ast Unk0824, src String) Unk0826 := …

  # PortAnalysis.module_stmts/1
  pub def module_stmts(p0 Unk0827) Vec(String) := …

  # PortAnalysis.needs_review?/1
  pub def needs_review?(p0 Unk0828) Bool := …

  # PortAnalysis.param_name_index/1
  pub def param_name_index(mods_groups Vec(Tuple(String, Vec(Unk0521)))) Unk0829 := …

  # PortAnalysis.parse/1
  pub def parse(src Unk0830) Option(Unk0831) := …

  # PortAnalysis.pascal/1
  pub def pascal(atom_str Unk0832) Unk0833 := …

  # PortAnalysis.pattern_structs/1
  pub def pattern_structs(p0 Unk0834) Vec(Unk0835) := …

  # PortAnalysis.short/1
  pub def short(p0 Unk0836) String := …

  # PortAnalysis.sigs_section/2
  pub def sigs_section(data Unk0813, subs Map(Unk0823, Unk0823)) String := …

  # PortAnalysis.src_of/2
  pub def src_of(sources Unk0803, file Unk0837) String := …

  # PortAnalysis.summary_section/2
  pub def summary_section(data Unk0813, subs Map(String, Unk0814)) String := …

  # PortAnalysis.sums_section/2
  pub def sums_section(data Unk0813, subs Map(String, Unk0838)) String := …

  # PortAnalysis.to_markdown/2
  pub def to_markdown(data Unk0813, p1 Unk0839) Unk0840 := …

  # PortSpec.apply_subs/2
  pub def apply_subs(str String, subs Map(Unk0823, Unk0823)) String := …

  # PortSpec.load/1
  pub def load(p0 Unk0841) Unk0842 := …

  # PortSpec.parse/1
  pub def parse(text String) Unk0842 := …

  # PortSpec.placeholders/1
  pub def placeholders(str Unk0843) Vec(String) := …

  # PortSpec.template/2
  pub def template(data Unk0844, p1 Unk0845) String := …

  # Pratt.after_paren/2
  pub def after_paren(tokens Vec(Unk0846), p1 Int53) Vec(Unk0846) := …

  # Pratt.assoc/1
  pub def assoc(op String) Unk0847 := …

  # Pratt.climb/3
  pub def climb(lhs Option(Unk0848), tokens Vec(Vec(Vec(Unk0607))), min_bp Int53) Tuple(Option(Unk0848), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.collect_dots/2
  pub def collect_dots(node Tuple(Unk0849, Unk0850), p1 Vec(Vec(Unk0607))) Tuple(Tuple(Unk0849, Unk0850), Vec(Vec(Unk0607))) := …

  # Pratt.desugar_prop/2
  pub def desugar_prop(stmts Vec(Tuple(Unk0852, Unk0851)), depth Int53) Tuple(Unk0853, Vec(Tuple(Unk0852, Unk0851))) := …

  # Pratt.desugar_propagation/1
  pub def desugar_propagation(stmts Vec(Tuple(Unk0852, Unk0851))) Tuple(Unk0853, Vec(Tuple(Unk0852, Unk0851))) := …

  # Pratt.expect_kw/2
  pub def expect_kw(p0 Vec(Vec(Vec(Unk0607))), k String) Vec(Vec(Vec(Unk0607))) := …

  # Pratt.expect_op/2
  pub def expect_op(p0 Vec(Vec(Vec(Unk0607))), o String) Vec(Vec(Vec(Unk0607))) := …

  # Pratt.expect_rbracket/1
  pub def expect_rbracket(p0 Vec(Vec(Vec(Unk0607)))) Vec(Vec(Vec(Unk0607))) := …

  # Pratt.expect_rparen/1
  pub def expect_rparen(p0 Vec(Vec(Vec(Unk0607)))) Vec(Vec(Vec(Unk0607))) := …

  # Pratt.finish_arg/2
  pub def finish_arg(a Unk0854, p1 Vec(Vec(Vec(Unk0607)))) Tuple(Vec(Unk0854), Vec(Vec(Vec(Vec(Unk0607))))) := …

  # Pratt.here/1
  pub def here(p0 Vec(Unk0855)) String := …

  # Pratt.int_of/1
  pub def int_of(n Unk0856) Vec(Tuple(Unk0857, Unk0858)) := …

  # Pratt.lambda_ahead?/1
  pub def lambda_ahead?(p0 Vec(Unk0846)) Bool := …

  # Pratt.level/1
  pub def level(op String) Unk0859 := …

  # Pratt.opinfo/1
  pub def opinfo(op String) Unk0860 := …

  # Pratt.parse/1
  pub def parse(ast String) Option(Unk0017) := …

  # Pratt.parse_args/1
  pub def parse_args(p0 Vec(Vec(Vec(Vec(Unk0607))))) Tuple(Vec(Unk0854), Vec(Vec(Vec(Vec(Unk0607))))) := …

  # Pratt.parse_arms/2
  pub def parse_arms(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Unk0861)) Tuple(Vec(Unk0861), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_block/1
  pub def parse_block(tokens Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0853, Vec(Tuple(Unk0852, Unk0851))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_body/1
  pub def parse_body(ast Option(Unk0017)) Option(Unk0017) := …

  # Pratt.parse_capture/1
  pub def parse_capture(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_case/1
  pub def parse_case(tokens Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_expr/2
  pub def parse_expr(tokens Vec(Vec(Vec(Unk0607))), min_bp Int53) Tuple(Option(Unk0848), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_if/1
  pub def parse_if(tokens Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_lambda/1
  pub def parse_lambda(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_list/2
  pub def parse_list(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Unk0863)) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_map/2
  pub def parse_map(p0 Vec(Vec(Vec(Vec(Unk0607)))), acc Vec(Tuple(Unk0857, Unk0858))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Vec(Unk0607))))) := …

  # Pratt.parse_param/1
  pub def parse_param(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0865, Option(Unk0864)), Vec(Vec(Unk0607))) := …

  # Pratt.parse_params/1
  pub def parse_params(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Vec(Unk0866), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat/1
  pub def parse_pat(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0867, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat_args/2
  pub def parse_pat_args(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Unk0868)) Tuple(Vec(Unk0868), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat_fields/2
  pub def parse_pat_fields(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Tuple(Unk0870, Unk0869))) Tuple(Vec(Tuple(Unk0870, Unk0869)), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat_list/2
  pub def parse_pat_list(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Unk0871)) Tuple(Tuple(Unk0867, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat_map/2
  pub def parse_pat_map(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Tuple(Unk0857, Unk0858))) Tuple(Tuple(Unk0867, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_pat_tuple/2
  pub def parse_pat_tuple(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Tuple(Unk0857, Unk0858))) Tuple(Tuple(Unk0867, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_path/1
  pub def parse_path(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0849, Unk0850), Vec(Vec(Unk0607))) := …

  # Pratt.parse_pats/1
  pub def parse_pats(str String) Vec(Unk0872) := …

  # Pratt.parse_pats/2
  pub def parse_pats(tokens Vec(Vec(Vec(Unk0607))), acc Vec(Unk0872)) Vec(Unk0872) := …

  # Pratt.parse_postfix/2
  pub def parse_postfix(node Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), p1 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_prefix/1
  pub def parse_prefix(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_primary/1
  pub def parse_primary(p0 Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_stmt/1
  pub def parse_stmt(p0 Vec(Vec(Vec(Vec(Unk0607))))) Tuple(Tuple(Unk0873, Unk0874), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_stmts/2
  pub def parse_stmts(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Unk0875)) Tuple(Vec(Unk0875), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_tuple/2
  pub def parse_tuple(p0 Vec(Vec(Vec(Unk0607))), acc Vec(Tuple(Unk0857, Unk0858))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_type/1
  pub def parse_type(p0 Vec(Vec(Vec(Unk0607)))) Tuple(String, Vec(Vec(Unk0607))) := …

  # Pratt.parse_type_args/2
  pub def parse_type_args(tokens Vec(Vec(Unk0607)), acc Vec(Unk0876)) Tuple(Vec(Unk0876), Vec(Vec(Unk0607))) := …

  # Pratt.parse_with/1
  pub def parse_with(tokens Vec(Vec(Vec(Unk0607)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.parse_with_clauses/2
  pub def parse_with_clauses(tokens Vec(Vec(Vec(Unk0607))), acc Vec(Tuple(Unk0878, Unk0877))) Tuple(Vec(Tuple(Unk0878, Unk0877)), Vec(Vec(Vec(Unk0607)))) := …

  # Pratt.pascal?/1
  pub def pascal?(s Unk0879) Bool := …

  # Pratt.peek_infix/1
  pub def peek_infix(p0 Vec(Vec(Vec(Unk0607)))) String := …

  # Pratt.same_level_root?/2
  pub def same_level_root?(p0 Option(Unk0848), op String) Bool := …

  # Pratt.sexpr/1
  pub def sexpr(p0 Option(Unk0017)) String := …

  # Pratt.sexpr_pat/1
  pub def sexpr_pat(p0 Unk0880) String := …

  # Pratt.sexpr_stmt/1
  pub def sexpr_stmt(p0 Unk0881) String := …

  # Pratt.str_interp/1
  pub def str_interp(parts Vec(Unk0882)) Tuple(Unk0862, Vec(Tuple(Unk0857, Unk0858))) := …

  # Pratt.tok_desc/1
  pub def tok_desc(p0 Unk0855) String := …

  # Prelude.with_prelude/1
  pub def with_prelude(types Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Type) := …

  # Prim.normalize/1
  pub def normalize(p0 String) Option(Unk0017) := …

  # Protocol.check_assoc!/2
  pub def check_assoc!(protocols Vec(Unk0211), impl_decls Vec(Unk0211)) Unk0883 := …

  # Protocol.check_impl/3
  pub def check_impl(p0 Unk0884, protocols Unk0885, reg Unk0886) Unk0887 := …

  # Protocol.check_no_overlap/3
  pub def check_no_overlap(impls Vec(Unk0888), reg Unk0886, targets Unk0889) Unk0890 := …

  # Protocol.dispatcher/4
  pub def dispatcher(proto Unk0891, sig Unk0892, impls Vec(Unk0888), reg Unk0886) Vec(Unk0893) := …

  # Protocol.dispatcher_params/2
  pub def dispatcher_params(sig_params Unk0894, vars Vec(String)) Unk0895 := …

  # Protocol.expand/5
  pub def expand(protocols Unk0885, impls Vec(Unk0888), p2 Unk0311, p3 Unk0312, p4 Unk0313) Vec(Unk0314) := …

  # Protocol.guard_for!/3
  pub def guard_for!(type String, proto Unk0891, reg Unk0886) Unk0896 := …

  # Protocol.impl_methods/2
  pub def impl_methods(p0 Unk0888, protocols Unk0885) Vec(Unk0314) := …

  # Protocol.mangle/3
  pub def mangle(proto Unk0897, type Unk0898, method Unk0899) String := …

  # Protocol.param_type/1
  pub def param_type(p Unk0900) Unk0901 := …

  # Protocol.registry/2
  pub def registry(types Unk0902, structs Vec(Unk0903)) Unk0886 := …

  # Protocol.runtime_dispatch_target?/1
  pub def runtime_dispatch_target?(p0 Unk0889) Bool := …

  # Protocol.subst_self/2
  pub def subst_self(p0 Unk0904, _type Unk0905) Option(Unk0906) := …

  # Protocol.sum_guard/1
  pub def sum_guard(variants Unk0907) String := …

  # Protocol.tag_disjunction/2
  pub def tag_disjunction(variants Vec(Unk0908), lhs Unk0909) String := …

  # Range.check/3
  pub def check(lo Unk0910, hi Unk0911, a Sum1) Sum1 := …

  # Range.expand_of/2
  pub def expand_of(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Range.lit/1
  pub def lit(n Unk0912) Sum1 := …

  # Range.table/1
  pub def table(ranges Vec(Map(Unk0009, Vec(Unk0010)))) Map(Unk0018, Unk0019) := …

  # Range.walk/2
  pub def walk(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Reach.all_emittable?/2
  pub def all_emittable?(f Map(Unk0913, Vec(Unk0914)), pctx Unk0915) Bool := …

  # Reach.all_funcs/1
  pub def all_funcs(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Reach.analyze/1
  pub def analyze(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0916 := …

  # Reach.atom_prim_blocker/0
  pub def atom_prim_blocker() Unk0917 := …

  # Reach.bare_atom_blocker/0
  pub def bare_atom_blocker() Unk0917 := …

  # Reach.build_default/0
  pub def build_default() Option(Unk0918) := …

  # Reach.builder_tail_ok?/2
  pub def builder_tail_ok?(f Map(Unk0913, Vec(Unk0914)), generics Unk0919) Bool := …

  # Reach.check_contracts/2
  pub def check_contracts(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), p1 Option(Unk0918)) Tuple(Unk0920, String) := …

  # Reach.classify/3
  pub def classify(p0 Sum1, _modnames Unk0921, p2 Tuple(Vec(Unk0917), Unk0922)) Tuple(Vec(Unk0917), Unk0922) := …

  # Reach.collect_ctors/2
  pub def collect_ctors(p0 Sum1, ctors Map(Unk0924, Unk0923)) Vec(Tuple(Unk0925, Vec(Sum1))) := …

  # Reach.conc_erl?/2
  pub def conc_erl?(m String, fun Unk0926) Bool := …

  # Reach.contract_message/1
  pub def contract_message(violations Vec(Unk0927)) String := …

  # Reach.core/2
  pub def core(src Unk0928, parser Fn(Unk0929, Unk0930)) Sum1 := …

  # Reach.ctor_aligned?/2
  pub def ctor_aligned?(p0 Tuple(Unk0925, Vec(Sum1)), f Map(Unk0913, Vec(Unk0914))) Bool := …

  # Reach.deep/1
  pub def deep(t Option(Unk0017)) Vec(Unk0931) := …

  # Reach.emittable_parametric?/1
  pub def emittable_parametric?(t Unk0932) Unk0933 := …

  # Reach.ffi/2
  pub def ffi(construct String, conc? Bool) Unk0917 := …

  # Reach.find_atom_ordering/1
  pub def find_atom_ordering(p0 Option(Unk0017)) Vec(Unk0931) := …

  # Reach.fixpoint/2
  pub def fixpoint(facts Unk0934, table Map(Unk0935, Unk0936)) Map(Unk0935, Unk0936) := …

  # Reach.fn_type_blocker/0
  pub def fn_type_blocker() Unk0917 := …

  # Reach.func_symbol_violations/1
  pub def func_symbol_violations(f Unk0937) Vec(Unk0931) := …

  # Reach.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.gate!/2
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), default Option(Unk0918)) Symbol := …

  # Reach.int_blocker/0
  pub def int_blocker() Unk0917 := …

  # Reach.js_wide_int?/1
  pub def js_wide_int?(t Unk0938) Bool := …

  # Reach.mix_default/0
  pub def mix_default() Unk0939 := …

  # Reach.parametric_blocker/0
  pub def parametric_blocker() Unk0917 := …

  # Reach.parametric_constructions/2
  pub def parametric_constructions(f Map(Unk0913, Vec(Unk0914)), ctors Map(Unk0924, Unk0923)) Vec(Tuple(Unk0925, Vec(Sum1))) := …

  # Reach.parametric_ctx/2
  pub def parametric_ctx(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), funs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0915 := …

  # Reach.parametric_rs_ok?/2
  pub def parametric_rs_ok?(f Map(Unk0913, Vec(Unk0914)), pctx Unk0915) Bool := …

  # Reach.parametric_type?/1
  pub def parametric_type?(t Unk0940) Bool := …

  # Reach.pascal?/1
  pub def pascal?(s Unk0941) Bool := …

  # Reach.ref_blocker/0
  pub def ref_blocker() Unk0917 := …

  # Reach.result_value_blocker/0
  pub def result_value_blocker() Unk0917 := …

  # Reach.scan/3
  pub def scan(p0 Sum1, modnames Unk0921, p2 Tuple(Vec(Unk0917), Unk0922)) Tuple(Vec(Unk0917), Unk0922) := …

  # Reach.scan_func/3
  pub def scan_func(f Map(Unk0913, Vec(Unk0914)), modnames Unk0921, pctx Unk0915) Tuple(Vec(Unk0917), Unk0922) := …

  # Reach.sig_idents/1
  pub def sig_idents(f Map(Unk0942, Vec(Unk0943))) Unk0944 := …

  # Reach.sig_uses_fn_type?/1
  pub def sig_uses_fn_type?(f Map(Unk0913, Vec(Unk0914))) Bool := …

  # Reach.symbol_lint!/1
  pub def symbol_lint!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.tail_calls_generic?/2
  pub def tail_calls_generic?(p0 Unk0945, generics Unk0919) Bool := …

  # Reach.tvar?/1
  pub def tvar?(t Unk0946) Unk0947 := …

  # Reach.type_has_tvar?/1
  pub def type_has_tvar?(t Unk0948) Bool := …

  # Reach.type_idents/1
  pub def type_idents(t Unk0948) Vec(Unk0949) := …

  # Reach.uses_parametric?/2
  pub def uses_parametric?(f Map(Unk0913, Vec(Unk0914)), names Unk0950) Bool := …

  # Reach.validate_default/1
  pub def validate_default(p0 Option(Unk0918)) Option(Unk0918) := …

  # Reach.wide_prim_blocker/0
  pub def wide_prim_blocker() Unk0917 := …

  # Reach.width_blocker/0
  pub def width_blocker() Unk0917 := …

  # Repl.accumulate_line/2
  pub def accumulate_line(line String, p1 Unk0951) Tuple(Vec(String), String) := …

  # Repl.bind_env/2
  pub def bind_env(binds Vec(Unk0952), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Map(String, Vec(Unk0078)) := …

  # Repl.bind_with_type/4
  pub def bind_with_type(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), input String, name String, type Option(Unk0955)) Tuple(Tuple(Unk0956, String), Tuple(Unk0954, Vec(Tuple(String, Unk0953)))) := …

  # Repl.candidate_pool/2
  pub def candidate_pool(p0 Unk0957, _s Session) Vec(Unk0958) := …

  # Repl.common_prefix/2
  pub def common_prefix(a Unk0959, b Unk0960) String := …

  # Repl.common_prefix/3
  pub def common_prefix(p0 Unk0959, p1 Unk0960, acc String) String := …

  # Repl.complete/2
  pub def complete(before_cursor String, p1 Session) Tuple(Vec(Unk0961), String) := …

  # Repl.continuation/2
  pub def continuation(_word String, p1 Vec(Unk0961)) String := …

  # Repl.describe/1
  pub def describe(p0 Session) Unk0962 := …

  # Repl.eval/2
  pub def eval(p0 Session, input String) Unk0963 := …

  # Repl.eval_bind/4
  pub def eval_bind(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), input String, name String, rhs Option(Unk0017)) Tuple(Tuple(Unk0956, String), Tuple(Unk0954, Vec(Tuple(String, Unk0953)))) := …

  # Repl.eval_decl/2
  pub def eval_decl(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), input String) Tuple(Tuple(Unk0965, String), Unk0964) := …

  # Repl.eval_expr/2
  pub def eval_expr(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), input Option(Unk0017)) Tuple(Tuple(Unk0956, String), Tuple(Unk0954, Vec(Tuple(String, Unk0953)))) := …

  # Repl.eval_stmt/2
  pub def eval_stmt(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), input String) Tuple(Tuple(Unk0956, String), Tuple(Unk0954, Vec(Tuple(String, Unk0953)))) := …

  # Repl.flush_entries/1
  pub def flush_entries(p0 Unk0966) Vec(Unk0967) := …

  # Repl.infer_or_unknown/3
  pub def infer_or_unknown(ast Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Vec(Unk0078) := …

  # Repl.info/1
  pub def info(p0 Session) Unk0968 := …

  # Repl.longest_common_prefix/1
  pub def longest_common_prefix(p0 Vec(Unk0969)) Unk0969 := …

  # Repl.program/3
  pub def program(units Vec(Tuple(String, Unk0953)), binds Vec(Tuple(String, Unk0953)), expr_src String) String := …

  # Repl.reload/2
  pub def reload(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), src String) Symbol := …

  # Repl.render/1
  pub def render(p0 Unk0970) String := …

  # Repl.run/4
  pub def run(s Tuple(Unk0954, Vec(Tuple(String, Unk0953))), binds Vec(Tuple(String, Unk0953)), units Vec(Tuple(String, Unk0953)), expr_src String) Tuple(Unk0972, Unk0971) := …

  # Repl.safe_decl/1
  pub def safe_decl(units Vec(Tuple(String, Unk0953))) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Repl.safe_infer/3
  pub def safe_infer(ast Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0955) := …

  # Repl.safe_infer_input/3
  pub def safe_infer_input(input Option(Unk0017), env Map(String, Vec(Unk0078)), ic Map(Unk0080, Map(String, Vec(Unk0078)))) Option(Unk0955) := …

  # Repl.safe_parse_body/1
  pub def safe_parse_body(input Option(Unk0017)) Tuple(Unk0973, Option(Unk0017)) := …

  # Repl.scan_count/2
  pub def scan_count(input String, regex Unk0974) Unk0975 := …

  # Repl.session_ic/1
  pub def session_ic(p0 Tuple(Unk0954, Vec(Tuple(String, Unk0953)))) Map(Unk0080, Map(String, Vec(Unk0078))) := …

  # Repl.type_of/2
  pub def type_of(p0 Session, input Option(Unk0017)) Option(Unk0955) := …

  # Repl.units_src/1
  pub def units_src(units Vec(Tuple(String, Unk0953))) String := …

  # SelfHost.badge/1
  pub def badge(p0 Unk0976) String := …

  # SelfHost.composition/0
  pub def composition() Unk0977 := …

  # SelfHost.evidence/1
  pub def evidence(p0 Unk0978) String := …

  # SelfHost.external_host_calls/1
  pub def external_host_calls(prog Map(Unk0981, Vec(Map(Unk0979, Vec(Unk0980))))) Vec(Unk0982) := …

  # SelfHost.ffi_ledger/0
  pub def ffi_ledger() Unk0983 := …

  # SelfHost.passes/0
  pub def passes() Unk0984 := …

  # SelfHost.sibling_compose_call?/2
  pub def sibling_compose_call?(construct Unk0985, siblings Unk0986) Bool := …

  # SelfHost.stages/0
  pub def stages() Unk0987 := …

  # SelfHost.status_markdown/1
  pub def status_markdown(stages Vec(Unk0988)) String := …

  # Shadow.ded_bind/5
  pub def ded_bind(n Unk0989, t Bool, e Vec(Unk0990), p3 Unk0991, fresh Fn(Unk0992, Unk0993, Unk0994)) Unk0995 := …

  # Shadow.ded_block/4
  pub def ded_block(stmts Vec(Unk0996), r Map(Unk0998, Unk0997), ver Unk0999, fresh Fn(Unk0992, Unk0993, Unk0994)) Vec(Unk0537) := …

  # Shadow.ded_expr/3
  pub def ded_expr(p0 Vec(Unk0990), r Map(Unk0998, Unk0997), _fresh Fn(Unk0992, Unk0993, Unk0994)) Vec(Unk0990) := …

  # Shadow.dedup/3
  pub def dedup(stmts Vec(Unk0996), params Vec(Unk0540), fresh Fn(Unk0992, Unk0993, Unk0994)) Vec(Unk0537) := …

  # Shadow.pat_var_names/1
  pub def pat_var_names(p0 Sum2) Vec(Unk1000) := …

  # ShowStdlib.module/0
  pub def module() Unk0254 := …

  # Test.run/2
  pub def run(src String, p1 Unk1001) Unk1002 := …

  # Tour.build_cell/1
  pub def build_cell(p0 Unk1003) Unk1004 := …

  # Tour.build_reach_example/1
  pub def build_reach_example(p0 Unk1005) Unk1006 := …

  # Tour.elixir_module/1
  pub def elixir_module(src String) Unk1007 := …

  # Tour.encode/2
  pub def encode(map Vec(Unk1008), indent Int53) String := …

  # Tour.encode_string/1
  pub def encode_string(s Vec(Unk1008)) String := …

  # Tour.generate/0
  pub def generate() Unk1009 := …

  # Tour.reach_map/1
  pub def reach_map(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk1010 := …

  # Transpile.add_clause/2
  pub def add_clause(open Tuple(Unk1012, Vec(Unk1011)), clause Unk1011) Option(Unk1013) := …

  # Transpile.build_clause/2
  pub def build_clause(head Unk1014, kw Unk1015) Unk1011 := …

  # Transpile.case_arm/1
  pub def case_arm(p0 Unk1016) String := …

  # Transpile.classify/1
  pub def classify(p0 String) Tuple(Unk1017, String) := …

  # Transpile.close_group/2
  pub def close_group(acc Vec(Unk1018), p1 Unk1018) Vec(Unk1018) := …

  # Transpile.def_groups/1
  pub def def_groups(stmts Vec(String)) Vec(Unk1018) := …

  # Transpile.escape/1
  pub def escape(s Unk1019) Unk1020 := …

  # Transpile.escape_lit/1
  pub def escape_lit(s Unk1021) String := …

  # Transpile.flush/2
  pub def flush(p0 Unk1022, _sigmap Map(Tuple(Unk1023, Unk1024), Bool)) Vec(String) := …

  # Transpile.hole_sig?/1
  pub def hole_sig?(p0 Unk1025) Bool := …

  # Transpile.infer_program/1
  pub def infer_program(p0 Unk1026) Tuple(Unk1027, Vec(String)) := …

  # Transpile.infer_report/1
  pub def infer_report(source String) Unk1028 := …

  # Transpile.infer_sigs/2
  pub def infer_sigs(p0 Unk1029, type_env Map(Unk0460, Tuple(Unk0439, String))) Unk1027 := …

  # Transpile.inferred/1
  pub def inferred(source String) Tuple(Unk1027, Vec(String)) := …

  # Transpile.max_placeholder/1
  pub def max_placeholder(p0 Vec(Unk1030)) Int53 := …

  # Transpile.mod_str/1
  pub def mod_str(p0 Unk1031) String := …

  # Transpile.module_groups/1
  pub def module_groups(src Unk1032) Tuple(String, Unk1033) := …

  # Transpile.moduledoc_lines/1
  pub def moduledoc_lines(text Unk1034) Vec(String) := …

  # Transpile.name_str/1
  pub def name_str(n Unk1035) Unk1036 := …

  # Transpile.new_group/3
  pub def new_group(vis Unk1037, clause Unk1011, doc Option(Unk1038)) Option(Unk1013) := …

  # Transpile.one_line/1
  pub def one_line(s Unk1039) Unk1040 := …

  # Transpile.prime_xmod/1
  pub def prime_xmod(sources Unk1041) Unk1042 := …

  # Transpile.rank/1
  pub def rank(entries Unk1043) Unk1044 := …

  # Transpile.render_body/1
  pub def render_body(p0 Bool) Option(Unk1045) := …

  # Transpile.render_clause/2
  pub def render_clause(kw String, c Unk1046) String := …

  # Transpile.render_items/3
  pub def render_items(stmts Vec(String), sigmap Map(Tuple(Unk1023, Unk1024), Bool), mod_name Unk1047) Vec(String) := …

  # Transpile.render_submodule/3
  pub def render_submodule(name Unk1047, body String, sigmap Map(Tuple(Unk1023, Unk1024), Bool)) Vec(String) := …

  # Transpile.same_group?/3
  pub def same_group?(open Unk1048, vis Unk1049, clause Unk1011) Bool := …

  # Transpile.short_name/1
  pub def short_name(p0 Unk1031) String := …

  # Transpile.sibling_module?/2
  pub def sibling_module?(p0 Unk1050, m String) Bool := …

  # Transpile.simple?/1
  pub def simple?(p0 Vec(Unk1051)) Bool := …

  # Transpile.snippet/1
  pub def snippet(node Unk1031) String := …

  # Transpile.stdlib_map/0
  pub def stdlib_map() Unk0522 := …

  # Transpile.string_part/1
  pub def string_part(s Unk1021) Tuple(Unk1052, String) := …

  # Transpile.string_parts/1
  pub def string_parts(segments Unk1053) Unk1054 := …

  # Transpile.struct_decl/2
  pub def struct_decl(mod_name Unk1047, fields Vec(Unk1055)) String := …

  # Transpile.struct_field?/1
  pub def struct_field?(a Unk1056) Bool := …

  # Transpile.struct_mod_noise?/1
  pub def struct_mod_noise?(p0 Unk1057) Bool := …

  # Transpile.subst_ph/2
  pub def subst_ph(p0 Vec(Unk1058), ps Unk1059) Vec(Unk1058) := …

  # Transpile.toplevel/3
  pub def toplevel(p0 Unk1060, sigmap Unk1061, types Vec(String)) Vec(String) := …

  # Transpile.transpile/2
  pub def transpile(source String, p1 Unk1062) Unk1063 := …

  # Transpile.transpile_with_stats/2
  pub def transpile_with_stats(source String, p1 Unk1064) Tuple(Unk1063, Unk1065) := …

  # Transpile.underscore_var/1
  pub def underscore_var(name Unk1066) String := …

  # Transpile.var?/1
  pub def var?(p0 Unk1067) Bool := …

  # Transpile.var_name/1
  pub def var_name(p0 Unk1031) String := …
```

### Placeholder index (replace once → applies to all sites)

| placeholder | sites | references |
|---|---|---|
| `Unk0001` | 1 | `Application.maybe_register_smart_cell/0:ret` |
| `Unk0002` | 1 | `Application.start/2:p0` |
| `Unk0003` | 1 | `Application.start/2:p1` |
| `Unk0004` | 1 | `Application.start/2:ret` |
| `Unk0005` | 5 | `Beam.any_t/0:ret`, `Beam.struct_form/2:ret`, `Beam.type_form/2:ret`, `Beam.union_t/1:p0`, `Beam.union_t/1:ret` |
| `Unk0006` | 3 | `Beam.arity/1:p0`, `Beam.function_form/2:p0`, `Beam.spec_form/2:p0` |
| `Unk0007` | 1 | `Beam.arity/1:ret` |
| `Unk0008` | 2 | `Beam.beam_for/5:p1`, `Beam.funcs_of/1:ret` |
| `Unk0009` | 73 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.compile/5:p0`, `Lower.compile_beam/4:p0`, `Lower.compile_elixir/4:p0`, `Lower.parametric_param_map/1:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0010` | 91 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.check!/2:p0`, `Lower.compile/5:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p0`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p0`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.ex_doc/2:p0`, `Lower.ex_typespec/1:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.fn_all_tvars/3:ret`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_param_map/1:p0`, `Lower.parametric_used?/2:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rs_doc/2:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p0`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0011` | 3 | `Beam.beam_for/5:ret`, `Beam.compile/2:ret`, `Beam.compile_ir/2:ret` |
| `Unk0012` | 2 | `Beam.beam_func/1:p0`, `Beam.beam_func/1:ret` |
| `Unk0013` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0014` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0015` | 1 | `Beam.bin_seg/1:ret` |
| `Unk0016` | 18 | `Beam.bind_var/2:p1`, `Beam.bind_var/2:ret`, `Beam.block_forms/2:p1`, `Beam.body_forms/3:p1`, `Beam.body_seq/2:p1`, `Beam.bump_var/1:p0`, `Beam.bump_var/1:ret`, `Beam.else_dispatch/3:p2`, `Beam.expr_form/2:p1`, `Beam.guard_form/2:p1`, `Beam.i64_overflow/4:p3`, `Beam.pat_vars/2:p1`, `Beam.pat_vars/2:ret`, `Beam.remote_call/4:p3`, `Beam.stmt_form/2:p1`, `Beam.stmt_form/2:ret`, `Beam.var_atom/1:ret`, `Beam.with_form/5:p3` |
| `Unk0017` | 95 | `Beam.body_forms/3:p0`, `Beam.cons/3:p2`, `Beam.expr_form/2:p0`, `Beam.guard_core/1:ret`, `Beam.guard_form/2:p0`, `Beam.i64_overflow/4:p1`, `Beam.i64_overflow/4:p2`, `Beam.remote_call/4:p2`, `Check.ann_each/3:p0`, `Check.annotate/3:p0`, `Check.arith_type/4:p0`, `Check.arith_type/4:p1`, `Check.bind_mismatch/5:p2`, `Check.body_literal_adopts?/2:p0`, `Check.branch_join/1:p0`, `Check.call_bound_error/5:p1`, `Check.called_ret_with/4:p2`, `Check.const_int/1:p0`, `Check.infer/3:p0`, `Check.infer_tail/3:p0`, `Check.int_lit_expr?/1:p0`, `Check.label_error/1:p0`, `Check.label_error_children/1:p0`, `Check.list_elems/1:p0`, `Check.lit_expr_adopts?/2:p0`, `Check.lit_range_error/3:p0`, `Check.literal_ordinal/2:p0`, `Check.num_mix_error/5:p1`, `Check.num_mix_error/5:p2`, `Check.oor_scan/5:p0`, `Check.range_bind/6:p3`, `Check.scan_bound_calls/4:p0`, `Check.scan_num_mix/3:p0`, `Check.scan_num_mix_children/3:p0`, `Check.walk_children/4:p0`, `Comptime.fold/1:p0`, `Core.from_expr/1:p0`, `Core.from_expr/1:ret`, `Core.from_pairs/1:ret`, `Core.from_stmt/1:ret`, `Core.from_tail/1:ret`, `Exhaustiveness.body_core/1:p0`, `Exhaustiveness.body_core/1:ret`, `Interp.resolve/4:ret`, `Interp.stringify/3:p0`, `JS.clause_return/3:p0`, `JS.guarded_return/4:p0`, `JVM.clause_value/2:p0`, `Lower.case_guard/3:p0`, `Lower.emit/3:p0`, `Lower.emit_ast/2:p0`, `Lower.insert_borrows/4:p0`, `Lower.p/4:p0`, `Lower.pipe_to_call/2:ret`, `Lower.resolve_consts/2:p0`, `Lower.resolve_rust_pats/2:p0`, `Lower.resolve_structs/2:p0`, `Lower.resolve_variants/2:p0`, `Lower.result_payload/3:p0`, `Lower.rust_arm_body/2:p0`, `Lower.rust_case/4:p0`, `Lower.rust_case/4:p2`, `Lower.rust_owned_elem/2:p0`, `Lower.struct_pairs/4:p2`, `Lower.tail_slice_id?/2:p0`, `Lower.used_ids/1:p0`, `Lower.variant_pairs/3:p1`, `Lower.widen_char_arith/2:p0`, `Macro.check_portable!/2:p1`, `Macro.do_expand/4:p1`, `Macro.expand/3:p1`, `Macro.expand/3:ret`, `Macro.introduces_failable_bind?/1:p0`, `Macro.map_node/2:p0`, `Macro.map_node/2:p1`, `Macro.substitute/2:p1`, `Macro.substitute/2:ret`, `Macro.walk_for_with/1:p0`, `Pratt.parse/1:ret`, `Pratt.parse_body/1:p0`, `Pratt.parse_body/1:ret`, `Pratt.sexpr/1:p0`, `Prim.normalize/1:ret`, `Range.expand_of/2:p0`, `Range.walk/2:p0`, `Reach.deep/1:p0`, `Reach.find_atom_ordering/1:p0`, `Repl.eval_bind/4:p3`, `Repl.eval_expr/2:p1`, `Repl.infer_or_unknown/3:p0`, `Repl.safe_infer/3:p0`, `Repl.safe_infer_input/3:p0`, `Repl.safe_parse_body/1:p0`, `Repl.safe_parse_body/1:ret`, `Repl.type_of/2:p1` |
| `Unk0018` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0019` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0020` | 1 | `Beam.clause_form/2:p0` |
| `Unk0021` | 1 | `Beam.clause_form/2:ret` |
| `Unk0022` | 27 | `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.load_ir/2:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Doctest.module_doc_strings/1:p0`, `InferLocal.all_funcs/1:p0`, `InferLocal.fill_returns/1:p0`, `InferLocal.fill_returns/1:ret`, `InferLocal.fixpoint/1:p0`, `InferLocal.fixpoint/1:ret`, `InferLocal.pass/2:p0`, `Lower.rust_program/1:p0`, `Opaque.erase/1:p0`, `Reach.all_funcs/1:p0`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0023` | 1 | `Beam.compile_program/1:ret` |
| `Unk0024` | 1 | `Beam.compile_program_ir/1:ret` |
| `Unk0025` | 1 | `Beam.cons/3:p0` |
| `Unk0026` | 2 | `Beam.else_dispatch/3:p0`, `Beam.with_form/5:p2` |
| `Unk0027` | 1 | `Beam.erl_op/1:ret` |
| `Unk0028` | 7 | `Beam.fn_form/2:p1`, `Beam.spec_form/2:p1`, `Beam.struct_form/2:p1`, `Beam.sum_form/2:p1`, `Beam.type_attrs/3:p2`, `Beam.type_ctx/3:ret`, `Beam.type_form/2:p1` |
| `Unk0029` | 1 | `Beam.fn_form/2:ret` |
| `Unk0030` | 1 | `Beam.fun_ref/3:p0` |
| `Unk0031` | 1 | `Beam.fun_ref/3:p1` |
| `Unk0032` | 1 | `Beam.fun_ref/3:p2` |
| `Unk0033` | 13 | `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.ranges_of/1:p0`, `Beam.structs_of/1:p0`, `Beam.types_of/1:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:ret` |
| `Unk0034` | 3 | `Beam.function_form/2:ret`, `Beam.spec_form/2:ret`, `Beam.type_attrs/3:ret` |
| `Unk0035` | 2 | `Beam.i64_overflow/4:p0`, `Beam.i64_project/2:p0` |
| `Unk0036` | 1 | `Beam.i64_project/2:p1` |
| `Unk0037` | 1 | `Beam.i64_project/2:ret` |
| `Unk0038` | 1 | `Beam.int_t/0:ret` |
| `Unk0039` | 1 | `Beam.load/2:ret` |
| `Unk0040` | 1 | `Beam.load_aux_mods/1:ret` |
| `Unk0041` | 1 | `Beam.load_ir/2:ret` |
| `Unk0042` | 1 | `Beam.load_program_ir/1:p0` |
| `Unk0043` | 1 | `Beam.map_field_pat/1:p0` |
| `Unk0044` | 1 | `Beam.map_field_pat/1:ret` |
| `Unk0045` | 1 | `Beam.num_form/1:p0` |
| `Unk0046` | 1 | `Beam.remote_call/4:p0` |
| `Unk0047` | 1 | `Beam.stmt_form/2:p0` |
| `Unk0048` | 1 | `Beam.str_form/1:p0` |
| `Unk0049` | 1 | `Beam.sum_form/2:p0` |
| `Unk0050` | 1 | `Beam.sum_form/2:ret` |
| `Unk0051` | 1 | `Beam.with_form/5:p0` |
| `Unk0052` | 7 | `CLI.check/1:p0`, `CLI.diff/1:p0`, `CLI.in_place/1:p0`, `CLI.print_diff/3:p0`, `CLI.read/1:p0`, `CLI.to_stdout/1:p0`, `CLI.unified_diff/3:p0` |
| `Unk0053` | 1 | `CLI.diff/1:ret` |
| `Unk0054` | 1 | `CLI.each/2:p0` |
| `Unk0055` | 1 | `CLI.each/2:p1` |
| `Unk0056` | 1 | `CLI.each/2:p1` |
| `Unk0057` | 1 | `CLI.each/2:ret` |
| `Unk0058` | 1 | `CLI.in_place/1:ret` |
| `Unk0059` | 1 | `CLI.main/1:ret` |
| `Unk0060` | 2 | `CLI.print_diff/3:p1`, `CLI.unified_diff/3:p1` |
| `Unk0061` | 2 | `CLI.print_diff/3:p2`, `CLI.unified_diff/3:p2` |
| `Unk0062` | 1 | `CLI.print_diff/3:ret` |
| `Unk0063` | 1 | `CLI.read/1:ret` |
| `Unk0064` | 1 | `CLI.to_stdout/1:ret` |
| `Unk0065` | 1 | `Capability.count_block/3:p0` |
| `Unk0066` | 2 | `Capability.count_block/3:p1`, `Capability.count_uses/2:p1` |
| `Unk0067` | 11 | `Capability.count_block/3:p2`, `Capability.count_block/3:ret`, `Capability.count_uses/1:ret`, `Capability.count_uses/2:ret`, `Capability.max_merge/2:p0`, `Capability.max_merge/2:p1`, `Capability.max_merge/2:ret`, `Capability.merge/2:p0`, `Capability.merge/2:p1`, `Capability.merge/2:ret`, `Capability.verdict/2:p1` |
| `Unk0068` | 4 | `Capability.count_uses/1:p0`, `Capability.count_uses/2:p0`, `Capability.lin_check/2:p1`, `Capability.lin_check_block/3:p2` |
| `Unk0069` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0070` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0071` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0072` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0073` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0074` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0075` | 1 | `Capability.lin_check_block/3:p1` |
| `Unk0076` | 1 | `Capability.pat_vars/1:p0` |
| `Unk0077` | 1 | `Capability.pat_vars/1:ret` |
| `Unk0078` | 112 | `Check.abstract_cast_ret/3:p0`, `Check.abstract_cast_ret/3:p2`, `Check.abstract_cast_ret/3:ret`, `Check.abstract_op_type/4:p1`, `Check.abstract_op_type/4:p2`, `Check.abstract_op_type/4:p3`, `Check.ann_each/3:p1`, `Check.ann_each/3:p2`, `Check.ann_each/3:ret`, `Check.ann_stmts/3:p1`, `Check.ann_stmts/3:p2`, `Check.ann_stmts/3:ret`, `Check.annotate/3:p1`, `Check.annotate/3:p2`, `Check.annotate/3:ret`, `Check.arith_type/4:p2`, `Check.arith_type/4:p3`, `Check.assignable?/2:p0`, `Check.bind_mismatch/5:p3`, `Check.bind_mismatch/5:p4`, `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.branch_join/1:p0`, `Check.branch_join/1:ret`, `Check.build_fn/2:p1`, `Check.call_bound_error/5:p2`, `Check.call_bound_error/5:p3`, `Check.call_bound_error/5:p4`, `Check.called_ret/2:p0`, `Check.called_ret/2:ret`, `Check.called_ret_with/4:p0`, `Check.called_ret_with/4:p3`, `Check.called_ret_with/4:ret`, `Check.check_bind_stmts/3:p1`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.clause_env/3:ret`, `Check.concrete_type?/1:p0`, `Check.ctor_type/2:p0`, `Check.ctor_type/2:ret`, `Check.first_bound_violation/4:p2`, `Check.first_bound_violation/4:p3`, `Check.fn_ret/1:p0`, `Check.fn_ret/1:ret`, `Check.has_tvar?/1:p0`, `Check.infer/3:p1`, `Check.infer/3:p2`, `Check.infer/3:ret`, `Check.infer_block/4:p1`, `Check.infer_block/4:p2`, `Check.infer_block/4:p3`, `Check.infer_block/4:ret`, `Check.infer_return_type/2:p1`, `Check.infer_tail/3:p1`, `Check.infer_tail/3:p2`, `Check.infer_tail/3:ret`, `Check.instantiate_ret/2:p1`, `Check.instantiate_ret/2:ret`, `Check.join_all/1:p0`, `Check.list_elem/1:p0`, `Check.missing_impl/5:p2`, `Check.missing_impl/5:p4`, `Check.narrow/4:p1`, `Check.narrow/4:p2`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.num_mix_error/5:p4`, `Check.ordinal_base/1:p0`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_bind/6:p4`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p0`, `Check.resolve_range/2:p1`, `Check.resolve_range/2:ret`, `Check.scan_bound_calls/4:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_bound_calls/4:p3`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p1`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p1`, `Check.walk_children/4:p2`, `Check.walk_children/4:p3`, `Decl.clause_env/2:ret`, `InferLocal.fill_funcs/2:p1`, `InferLocal.pass/2:p1`, `Interp.int_type?/1:p0`, `Interp.resolve/4:p1`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p1`, `Interp.resolve_part/4:p2`, `Interp.stringify/3:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:p1`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.infer_or_unknown/3:ret`, `Repl.safe_infer/3:p1`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p1`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0079` | 1 | `Check.abstract_cast_ret/3:p1` |
| `Unk0080` | 41 | `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p3`, `Check.ann_each/3:p2`, `Check.ann_stmts/3:p2`, `Check.annotate/3:p2`, `Check.bind_mismatch/5:p4`, `Check.call_bound_error/5:p3`, `Check.called_ret/2:p0`, `Check.called_ret_with/4:p0`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.ctor_type/2:p0`, `Check.first_bound_violation/4:p3`, `Check.infer/3:p2`, `Check.infer_block/4:p2`, `Check.infer_return_type/2:p1`, `Check.infer_tail/3:p2`, `Check.narrow/4:p2`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p2`, `InferLocal.fill_funcs/2:p1`, `InferLocal.pass/2:p1`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0081` | 1 | `Check.abstract_op_type/4:ret` |
| `Unk0082` | 1 | `Check.all_types/1:p0` |
| `Unk0083` | 1 | `Check.ann_stmts/3:p0` |
| `Unk0084` | 1 | `Check.arith_type/4:ret` |
| `Unk0085` | 4 | `Check.bind_mismatch/5:p0`, `Check.lit_range_error/3:p2`, `Check.oor_scan/5:p4`, `Check.range_bind/6:p0` |
| `Unk0086` | 2 | `Check.bind_mismatch/5:ret`, `Check.check_bind_stmts/3:ret` |
| `Unk0087` | 4 | `Check.bind_tvar/4:p0`, `Check.bind_tvar/4:p1`, `Check.inner_of/1:p0`, `Check.inner_of/1:ret` |
| `Unk0088` | 1 | `Check.bind_tvar/4:p2` |
| `Unk0089` | 3 | `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.first_bound_violation/4:p2` |
| `Unk0090` | 1 | `Check.build_fn/2:p0` |
| `Unk0091` | 2 | `Check.call_bound_error/5:ret`, `Check.first_bound_violation/4:ret` |
| `Unk0092` | 1 | `Check.call_name/1:p0` |
| `Unk0093` | 2 | `Check.call_name/1:ret`, `Check.with_callees/1:ret` |
| `Unk0094` | 1 | `Check.check/1:ret` |
| `Unk0095` | 1 | `Check.check_bind_stmts/3:p0` |
| `Unk0096` | 1 | `Check.check_binds/2:ret` |
| `Unk0097` | 1 | `Check.check_bounds/2:ret` |
| `Unk0098` | 1 | `Check.check_error_set/2:p0` |
| `Unk0099` | 2 | `Check.check_error_set/2:p1`, `Check.check_func/3:p2` |
| `Unk0100` | 1 | `Check.check_error_set/2:ret` |
| `Unk0101` | 1 | `Check.check_external_caps/1:ret` |
| `Unk0102` | 1 | `Check.check_func/3:p0` |
| `Unk0103` | 1 | `Check.check_func/3:ret` |
| `Unk0104` | 1 | `Check.check_labels/1:ret` |
| `Unk0105` | 1 | `Check.check_numeric_mix/2:ret` |
| `Unk0106` | 1 | `Check.check_program/1:ret` |
| `Unk0107` | 1 | `Check.check_return/2:ret` |
| `Unk0108` | 1 | `Check.clause_env/3:p0` |
| `Unk0109` | 1 | `Check.clause_env/3:p1` |
| `Unk0110` | 1 | `Check.comp_str/1:p0` |
| `Unk0111` | 1 | `Check.const_int/1:ret` |
| `Unk0112` | 1 | `Check.const_int/1:ret` |
| `Unk0113` | 1 | `Check.ctor_types/2:p1` |
| `Unk0114` | 1 | `Check.ctor_types/2:p1` |
| `Unk0115` | 1 | `Check.ctor_types/2:ret` |
| `Unk0116` | 1 | `Check.ctor_types/2:ret` |
| `Unk0117` | 2 | `Check.debottom/1:p0`, `Check.debottom/1:ret` |
| `Unk0118` | 1 | `Check.declared_set/2:p0` |
| `Unk0119` | 4 | `Check.declared_set/2:p1`, `Check.declared_set/2:ret`, `Check.error_sets/1:ret`, `Check.solve_error_sets/2:p1` |
| `Unk0120` | 1 | `Check.declared_set/2:ret` |
| `Unk0121` | 3 | `Check.direct_tags/1:p0`, `Check.produced_set/2:p0`, `Check.propagated_callees/1:p0` |
| `Unk0122` | 1 | `Check.direct_tags/1:ret` |
| `Unk0123` | 1 | `Check.error_tags/1:p0` |
| `Unk0124` | 2 | `Check.error_tags/1:ret`, `Check.tag_name/1:ret` |
| `Unk0125` | 1 | `Check.fbound_table/1:p0` |
| `Unk0126` | 1 | `Check.fbound_table/1:ret` |
| `Unk0127` | 1 | `Check.first_bound_violation/4:p1` |
| `Unk0128` | 1 | `Check.fixpoint/2:p0` |
| `Unk0129` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0130` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0131` | 1 | `Check.fn_parts/1:ret` |
| `Unk0132` | 1 | `Check.fsig/1:p0` |
| `Unk0133` | 1 | `Check.fsig/1:ret` |
| `Unk0134` | 1 | `Check.generic_ret?/2:p1` |
| `Unk0135` | 1 | `Check.impl_table/1:p0` |
| `Unk0136` | 1 | `Check.impl_table/1:p0` |
| `Unk0137` | 1 | `Check.impl_table/1:ret` |
| `Unk0138` | 1 | `Check.infer_block/4:p0` |
| `Unk0139` | 1 | `Check.instantiate_ret/2:p0` |
| `Unk0140` | 1 | `Check.int_literal?/1:p0` |
| `Unk0141` | 1 | `Check.join/2:ret` |
| `Unk0142` | 1 | `Check.kind_prefix/1:p0` |
| `Unk0143` | 2 | `Check.label_error/1:ret`, `Check.label_error_children/1:ret` |
| `Unk0144` | 1 | `Check.list_elem/1:ret` |
| `Unk0145` | 1 | `Check.list_elems/1:ret` |
| `Unk0146` | 2 | `Check.lit_range_error/3:ret`, `Check.oor_scan/5:ret` |
| `Unk0147` | 1 | `Check.literal_ordinal/2:ret` |
| `Unk0148` | 1 | `Check.missing_impl/5:p1` |
| `Unk0149` | 1 | `Check.missing_impl/5:p3` |
| `Unk0150` | 1 | `Check.missing_impl/5:ret` |
| `Unk0151` | 3 | `Check.num_bits/2:p0`, `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0152` | 1 | `Check.num_bits/2:p1` |
| `Unk0153` | 2 | `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0154` | 1 | `Check.num_join/2:p0` |
| `Unk0155` | 1 | `Check.num_join/2:p1` |
| `Unk0156` | 1 | `Check.num_lub/2:ret` |
| `Unk0157` | 1 | `Check.num_mix?/2:p0` |
| `Unk0158` | 1 | `Check.num_mix?/2:p1` |
| `Unk0159` | 1 | `Check.num_mix_error/5:p0` |
| `Unk0160` | 1 | `Check.num_mix_error/5:ret` |
| `Unk0161` | 1 | `Check.num_widens?/2:p0` |
| `Unk0162` | 1 | `Check.num_widens?/2:p1` |
| `Unk0163` | 1 | `Check.oor_scan/5:p2` |
| `Unk0164` | 1 | `Check.oor_scan/5:p3` |
| `Unk0165` | 1 | `Check.opaque_table/1:p0` |
| `Unk0166` | 1 | `Check.opaque_table/1:p0` |
| `Unk0167` | 1 | `Check.opaque_table/1:ret` |
| `Unk0168` | 1 | `Check.pascal?/1:p0` |
| `Unk0169` | 1 | `Check.produced_set/2:p1` |
| `Unk0170` | 1 | `Check.produced_set/2:p1` |
| `Unk0171` | 1 | `Check.produced_set/2:ret` |
| `Unk0172` | 1 | `Check.propagated_callees/1:ret` |
| `Unk0173` | 1 | `Check.range_base/2:ret` |
| `Unk0174` | 1 | `Check.range_bind/6:p2` |
| `Unk0175` | 1 | `Check.range_bind/6:ret` |
| `Unk0176` | 1 | `Check.range_table/1:p0` |
| `Unk0177` | 1 | `Check.range_table/1:p0` |
| `Unk0178` | 1 | `Check.range_table/1:ret` |
| `Unk0179` | 2 | `Check.scan_bound_calls/4:ret`, `Check.walk_children/4:ret` |
| `Unk0180` | 2 | `Check.scan_num_mix/3:ret`, `Check.scan_num_mix_children/3:ret` |
| `Unk0181` | 1 | `Check.solve_error_sets/2:p0` |
| `Unk0182` | 1 | `Check.tag_name/1:p0` |
| `Unk0183` | 1 | `Check.type_table/1:ret` |
| `Unk0184` | 2 | `Check.uint_signed_join/2:p0`, `Check.uint_signed_join/2:p1` |
| `Unk0185` | 1 | `Check.with_callees/1:p0` |
| `Unk0186` | 1 | `Comptime.eval/1:p0` |
| `Unk0187` | 1 | `Comptime.eval/1:ret` |
| `Unk0188` | 24 | `Comptime.fold/1:ret`, `Interp.resolve/4:p0`, `Lower.borrow_arg/5:p0`, `Lower.borrow_value/2:p0`, `Lower.borrow_value/2:ret`, `Lower.insert_borrows/4:ret`, `Lower.owned_arg?/2:p0`, `Lower.owned_field_var?/2:p0`, `Lower.resolve_consts/2:ret`, `Lower.resolve_rust_pats/2:ret`, `Lower.resolve_structs/2:ret`, `Lower.resolve_variants/2:ret`, `Lower.scalar_literal?/1:p0`, `Lower.variant_lit/2:ret`, `Lower.widen_char_arith/2:ret`, `Lower.wrap_char/2:p0`, `Lower.wrap_char/2:ret`, `Macro.do_expand/4:ret`, `Macro.freshen/2:ret`, `Macro.map_node/2:p1`, `Macro.map_node/2:ret`, `Macro.rename/2:ret`, `Macro.substitute/2:p0`, `Macro.walk_for_with/1:ret` |
| `Unk0189` | 1 | `Comptime.int_div/3:p0` |
| `Unk0190` | 1 | `Comptime.int_div/3:p2` |
| `Unk0191` | 1 | `Comptime.int_div/3:p2` |
| `Unk0192` | 1 | `Comptime.int_div/3:p2` |
| `Unk0193` | 1 | `Comptime.int_div/3:ret` |
| `Unk0194` | 1 | `Core.first_unsupported/2:p0` |
| `Unk0195` | 3 | `Core.first_unsupported/2:p1`, `Core.first_unsupported/2:ret`, `Core.reject_unsupported!/4:p1` |
| `Unk0196` | 2 | `Core.first_unsupported/2:p1`, `Core.reject_unsupported!/4:p1` |
| `Unk0197` | 1 | `Core.from_arm/1:p0` |
| `Unk0198` | 1 | `Core.from_arm/1:ret` |
| `Unk0199` | 1 | `Core.from_pairs/1:p0` |
| `Unk0200` | 1 | `Core.from_pairs/1:ret` |
| `Unk0201` | 1 | `Core.from_stmt/1:p0` |
| `Unk0202` | 1 | `Core.from_stmt/1:ret` |
| `Unk0203` | 1 | `Core.from_tail/1:p0` |
| `Unk0204` | 2 | `Core.reject_unsupported!/4:p0`, `JS.function_js/2:p0` |
| `Unk0205` | 8 | `Cst.build/1:p0`, `Cst.open/4:p0`, `Cst.open/4:p2`, `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p0`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0206` | 1 | `Cst.build/1:ret` |
| `Unk0207` | 1 | `Cst.open/4:p1` |
| `Unk0208` | 4 | `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0209` | 2 | `Cst.open/4:ret`, `Cst.seq/2:ret` |
| `Unk0210` | 7 | `Decl.all_impl_decls/1:p0`, `Decl.all_impls/1:p0`, `Decl.all_protocols/1:p0`, `Decl.collect_aliases/1:p0`, `Decl.collect_macros/1:p0`, `Decl.in_scope/2:p0`, `Decl.lower_meta/3:p1` |
| `Unk0211` | 5 | `Decl.all_impl_decls/1:ret`, `Decl.all_protocols/1:ret`, `Decl.in_scope/2:ret`, `Protocol.check_assoc!/2:p0`, `Protocol.check_assoc!/2:p1` |
| `Unk0212` | 1 | `Decl.all_impls/1:ret` |
| `Unk0213` | 2 | `Decl.assemble/3:p0`, `Decl.protocol_defs/4:p0` |
| `Unk0214` | 5 | `Decl.assemble/3:p1`, `Decl.subst_const/2:p1`, `Decl.subst_func/2:p1`, `Decl.subst_struct/2:p1`, `Decl.subst_type/2:p1` |
| `Unk0215` | 1 | `Decl.assemble/3:p2` |
| `Unk0216` | 1 | `Decl.assemble/3:ret` |
| `Unk0217` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0218` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0219` | 1 | `Decl.attach_external/3:p0` |
| `Unk0220` | 1 | `Decl.attach_external/3:p1` |
| `Unk0221` | 1 | `Decl.attach_external/3:p2` |
| `Unk0222` | 1 | `Decl.attach_targets/2:p0` |
| `Unk0223` | 2 | `Decl.attach_targets/2:p1`, `Decl.parse_targets/1:ret` |
| `Unk0224` | 37 | `Decl.balanced_parens/1:p0`, `Decl.balanced_parens/1:ret`, `Decl.decl_boundary?/1:p0`, `Decl.decl_kw?/1:p0`, `Decl.def_raw/4:p2`, `Decl.line_continues?/2:p0`, `Decl.line_continues?/2:p1`, `Decl.skip_nl/1:p0`, `Decl.skip_nl/1:ret`, `Decl.split_decls/1:p0`, `Decl.take_block/3:p0`, `Decl.take_block/3:p2`, `Decl.take_block/3:ret`, `Decl.take_decl/1:p0`, `Decl.take_decl/1:ret`, `Decl.take_def/1:p0`, `Decl.take_def/1:ret`, `Decl.take_head/4:p2`, `Decl.take_head/4:p3`, `Decl.take_head/4:ret`, `Decl.take_line/2:p0`, `Decl.take_line/2:p1`, `Decl.take_line/2:ret`, `Decl.take_line/3:p0`, `Decl.take_line/3:p1`, `Decl.take_line/3:ret`, `Decl.take_mod_body/2:p0`, `Decl.take_mod_body/2:ret`, `Decl.take_parens/3:p0`, `Decl.take_parens/3:p2`, `Decl.take_parens/3:ret`, `Decl.take_type/2:p0`, `Decl.take_type/2:p1`, `Decl.take_type/2:ret`, `Decl.take_until_do/2:p0`, `Decl.take_until_do/2:p1`, `Decl.take_until_do/2:ret` |
| `Unk0225` | 3 | `Decl.block_seps/5:p0`, `Decl.block_seps/5:p4`, `Decl.block_seps/5:ret` |
| `Unk0226` | 1 | `Decl.build_func/1:p0` |
| `Unk0227` | 1 | `Decl.calls_show_float?/1:p0` |
| `Unk0228` | 1 | `Decl.clause/2:p0` |
| `Unk0229` | 1 | `Decl.clause/2:p1` |
| `Unk0230` | 2 | `Decl.clause_env/2:p1`, `Decl.meta_clause/5:p3` |
| `Unk0231` | 1 | `Decl.collapse_parens/1:p0` |
| `Unk0232` | 1 | `Decl.collapse_parens/1:ret` |
| `Unk0233` | 1 | `Decl.collect_aliases/1:ret` |
| `Unk0234` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0235` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0236` | 8 | `Decl.compile/1:ret`, `Decl.compile_beam/1:ret`, `Decl.protocol_unit/3:ret`, `Lower.compile/5:ret`, `Lower.compile_beam/4:ret`, `Lower.compile_elixir/4:ret`, `Lower.compile_module/1:ret`, `Lower.compile_module_beam/1:ret` |
| `Unk0237` | 1 | `Decl.compile_beam/1:ret` |
| `Unk0238` | 2 | `Decl.def_raw/4:p0`, `Decl.take_head/4:p0` |
| `Unk0239` | 2 | `Decl.def_raw/4:p1`, `Decl.take_head/4:p1` |
| `Unk0240` | 2 | `Decl.def_raw/4:p3`, `Decl.detok_block/1:ret` |
| `Unk0241` | 3 | `Decl.def_raw/4:ret`, `Decl.take_def/1:ret`, `Decl.take_head/4:ret` |
| `Unk0242` | 1 | `Decl.detok_block/1:p0` |
| `Unk0243` | 3 | `Decl.extract_parens/1:p0`, `Decl.parse_struct/3:p0`, `Decl.variant/1:p0` |
| `Unk0244` | 1 | `Decl.extract_parens/1:ret` |
| `Unk0245` | 1 | `Decl.field/1:p0` |
| `Unk0246` | 1 | `Decl.fields/1:p0` |
| `Unk0247` | 1 | `Decl.fields/1:ret` |
| `Unk0248` | 1 | `Decl.impl_struct/3:p0` |
| `Unk0249` | 1 | `Decl.impl_struct/3:p1` |
| `Unk0250` | 1 | `Decl.impl_struct/3:p2` |
| `Unk0251` | 1 | `Decl.impl_struct/3:ret` |
| `Unk0252` | 1 | `Decl.in_scope/2:p1` |
| `Unk0253` | 1 | `Decl.in_scope/2:p1` |
| `Unk0254` | 4 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0`, `ShowStdlib.module/0:ret` |
| `Unk0255` | 3 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0` |
| `Unk0256` | 1 | `Decl.lower_meta/3:p0` |
| `Unk0257` | 1 | `Decl.lower_meta/3:p2` |
| `Unk0258` | 1 | `Decl.lower_meta/3:ret` |
| `Unk0259` | 1 | `Decl.macro_param_names/1:p0` |
| `Unk0260` | 1 | `Decl.macro_param_names/1:ret` |
| `Unk0261` | 1 | `Decl.mark_pub/1:p0` |
| `Unk0262` | 1 | `Decl.mark_test/1:p0` |
| `Unk0263` | 1 | `Decl.meta_clause/5:p0` |
| `Unk0264` | 4 | `Decl.meta_clause/5:p4`, `Interp.resolve/4:p3`, `Interp.resolve_part/4:p3`, `Interp.stringify/3:p2` |
| `Unk0265` | 1 | `Decl.meta_clause/5:ret` |
| `Unk0266` | 1 | `Decl.nz/1:ret` |
| `Unk0267` | 1 | `Decl.param/1:p0` |
| `Unk0268` | 1 | `Decl.param/1:ret` |
| `Unk0269` | 7 | `Decl.parse_abstract/4:p0`, `Decl.parse_alias/1:p0`, `Decl.parse_const/3:p0`, `Decl.parse_opaque/3:p0`, `Decl.parse_range/3:p0`, `Decl.parse_type/3:p0`, `Decl.split_once/2:p0` |
| `Unk0270` | 2 | `Decl.parse_abstract/4:p1`, `Decl.parse_abstract_members/1:p0` |
| `Unk0271` | 1 | `Decl.parse_abstract/4:p2` |
| `Unk0272` | 1 | `Decl.parse_abstract/4:p3` |
| `Unk0273` | 1 | `Decl.parse_abstract_members/1:ret` |
| `Unk0274` | 1 | `Decl.parse_alias/1:ret` |
| `Unk0275` | 2 | `Decl.parse_alias/1:ret`, `Decl.strip_type_params/1:ret` |
| `Unk0276` | 1 | `Decl.parse_assoc_binding/1:p0` |
| `Unk0277` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0278` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0279` | 1 | `Decl.parse_binder/1:p0` |
| `Unk0280` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0281` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0282` | 1 | `Decl.parse_binders/1:p0` |
| `Unk0283` | 1 | `Decl.parse_binders/1:ret` |
| `Unk0284` | 1 | `Decl.parse_bounds/1:p0` |
| `Unk0285` | 1 | `Decl.parse_bounds/1:ret` |
| `Unk0286` | 2 | `Decl.parse_cast_rule/1:p0`, `Decl.parse_op_rule/1:p0` |
| `Unk0287` | 1 | `Decl.parse_cast_rule/1:ret` |
| `Unk0288` | 1 | `Decl.parse_const/3:p1` |
| `Unk0289` | 1 | `Decl.parse_const/3:p2` |
| `Unk0290` | 1 | `Decl.parse_external/1:p0` |
| `Unk0291` | 1 | `Decl.parse_external/1:ret` |
| `Unk0292` | 1 | `Decl.parse_external/1:ret` |
| `Unk0293` | 1 | `Decl.parse_head/1:ret` |
| `Unk0294` | 1 | `Decl.parse_op_rule/1:ret` |
| `Unk0295` | 1 | `Decl.parse_opaque/3:p1` |
| `Unk0296` | 1 | `Decl.parse_opaque/3:p2` |
| `Unk0297` | 1 | `Decl.parse_ordinal/1:p0` |
| `Unk0298` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0299` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0300` | 1 | `Decl.parse_params/1:p0` |
| `Unk0301` | 1 | `Decl.parse_params/1:ret` |
| `Unk0302` | 1 | `Decl.parse_range/3:p1` |
| `Unk0303` | 1 | `Decl.parse_range/3:p2` |
| `Unk0304` | 1 | `Decl.parse_struct/3:p1` |
| `Unk0305` | 1 | `Decl.parse_struct/3:p2` |
| `Unk0306` | 1 | `Decl.parse_targets/1:p0` |
| `Unk0307` | 1 | `Decl.parse_type/3:p1` |
| `Unk0308` | 1 | `Decl.parse_type/3:p2` |
| `Unk0309` | 1 | `Decl.parse_use/1:p0` |
| `Unk0310` | 2 | `Decl.proto_method_traits/1:ret`, `Lower.compile/5:p4` |
| `Unk0311` | 2 | `Decl.protocol_defs/4:p1`, `Protocol.expand/5:p2` |
| `Unk0312` | 2 | `Decl.protocol_defs/4:p2`, `Protocol.expand/5:p3` |
| `Unk0313` | 2 | `Decl.protocol_defs/4:p3`, `Protocol.expand/5:p4` |
| `Unk0314` | 3 | `Decl.protocol_defs/4:ret`, `Protocol.expand/5:ret`, `Protocol.impl_methods/2:ret` |
| `Unk0315` | 1 | `Decl.protocol_struct/2:p0` |
| `Unk0316` | 1 | `Decl.protocol_struct/2:p1` |
| `Unk0317` | 1 | `Decl.protocol_struct/2:ret` |
| `Unk0318` | 1 | `Decl.req_ret/1:p0` |
| `Unk0319` | 1 | `Decl.req_ret/1:ret` |
| `Unk0320` | 1 | `Decl.split2/2:p0` |
| `Unk0321` | 1 | `Decl.split2/2:p1` |
| `Unk0322` | 1 | `Decl.split2/2:ret` |
| `Unk0323` | 1 | `Decl.split2/2:ret` |
| `Unk0324` | 1 | `Decl.split_decls/1:ret` |
| `Unk0325` | 1 | `Decl.split_forall/1:p0` |
| `Unk0326` | 1 | `Decl.split_forall/1:ret` |
| `Unk0327` | 1 | `Decl.split_once/2:ret` |
| `Unk0328` | 1 | `Decl.split_once/2:ret` |
| `Unk0329` | 1 | `Decl.split_top/2:p0` |
| `Unk0330` | 1 | `Decl.split_top/2:ret` |
| `Unk0331` | 1 | `Decl.strip_type_params/1:p0` |
| `Unk0332` | 1 | `Decl.subst_const/2:p0` |
| `Unk0333` | 1 | `Decl.subst_fields/2:p0` |
| `Unk0334` | 1 | `Decl.subst_fields/2:p1` |
| `Unk0335` | 1 | `Decl.subst_func/2:p0` |
| `Unk0336` | 1 | `Decl.subst_struct/2:p0` |
| `Unk0337` | 1 | `Decl.subst_type/2:p0` |
| `Unk0338` | 2 | `Decl.subst_type_str/2:p0`, `Decl.subst_type_str/2:ret` |
| `Unk0339` | 1 | `Decl.subst_type_str/2:p1` |
| `Unk0340` | 1 | `Decl.subst_variant/2:p0` |
| `Unk0341` | 1 | `Decl.subst_variant/2:p1` |
| `Unk0342` | 2 | `Decl.take_mod_body/2:p1`, `Decl.take_mod_body/2:ret` |
| `Unk0343` | 1 | `Decl.take_until_do/2:ret` |
| `Unk0344` | 30 | `Doc.concat/1:p0`, `Doc.concat/1:ret`, `Doc.concat/2:p0`, `Doc.concat/2:p1`, `Doc.concat/2:ret`, `Doc.empty/0:ret`, `Doc.group/2:p0`, `Doc.hardline/0:ret`, `Doc.if_break/2:p0`, `Doc.if_break/2:p1`, `Doc.if_break/2:ret`, `Doc.join/2:p0`, `Doc.join/2:p1`, `Doc.join/2:ret`, `Doc.line/0:ret`, `Doc.line_suffix/1:p0`, `Doc.line_suffix/1:ret`, `Doc.must_break?/1:p0`, `Doc.nest/2:p1`, `Doc.nest/2:ret`, `Doc.render/2:p0`, `Doc.softline/0:ret`, `Doc.text/1:ret`, `Format.bd/3:ret`, `Format.chain_body/2:ret`, `Format.chain_doc/1:ret`, `Format.chain_tail/2:ret`, `Format.group_doc/4:ret`, `Format.line_doc/1:ret`, `Format.node_doc/2:ret` |
| `Unk0345` | 2 | `Doc.do_render/5:p2`, `Doc.fits?/2:p1` |
| `Unk0346` | 3 | `Doc.do_render/5:p3`, `Doc.flat_string/1:p0`, `Doc.flush_suffix/2:p0` |
| `Unk0347` | 1 | `Doc.group/2:ret` |
| `Unk0348` | 14 | `Doc.nest/2:p0`, `Format.apply_node/3:p1`, `Format.apply_node/3:p2`, `Format.apply_node/3:ret`, `Format.indent_and_render/4:p1`, `Format.pop/1:p0`, `Format.pop/1:ret`, `Format.push/2:p0`, `Format.push/2:p1`, `Format.push/2:ret`, `Format.render_line/2:p1`, `Format.update_stack/4:p2`, `Format.update_stack/4:p3`, `Format.update_stack/4:ret` |
| `Unk0349` | 2 | `Doctest.augment/2:p1`, `Doctest.extract/1:ret` |
| `Unk0350` | 1 | `Doctest.exunit_cases/2:p1` |
| `Unk0351` | 1 | `Doctest.exunit_cases/2:ret` |
| `Unk0352` | 1 | `Doctest.module_doc_strings/1:ret` |
| `Unk0353` | 1 | `Doctest.pairs/1:p0` |
| `Unk0354` | 1 | `Doctest.pairs/1:ret` |
| `Unk0355` | 1 | `Doctest.run/2:p1` |
| `Unk0356` | 1 | `Doctest.run/2:ret` |
| `Unk0357` | 1 | `Doctest.run_markdown/1:ret` |
| `Unk0358` | 8 | `Exhaustiveness.add_range/4:p0`, `Exhaustiveness.add_range/4:ret`, `Exhaustiveness.add_type/3:p0`, `Exhaustiveness.add_type/3:ret`, `Exhaustiveness.base_env/0:ret`, `Exhaustiveness.program_env/3:ret`, `PatternLower.add_struct/3:p0`, `PatternLower.add_struct/3:ret` |
| `Unk0359` | 1 | `Exhaustiveness.add_type/3:p2` |
| `Unk0360` | 2 | `Exhaustiveness.analyze/3:p0`, `PatternLower.lower_clause/2:ret` |
| `Unk0361` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0362` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0363` | 1 | `Exhaustiveness.analyze/3:ret` |
| `Unk0364` | 2 | `Exhaustiveness.arity/2:p1`, `Exhaustiveness.specialize/3:p1` |
| `Unk0365` | 1 | `Exhaustiveness.check_case_bodies!/2:p0` |
| `Unk0366` | 1 | `Exhaustiveness.check_case_bodies!/2:p1` |
| `Unk0367` | 1 | `Exhaustiveness.check_case_bodies!/2:ret` |
| `Unk0368` | 1 | `Exhaustiveness.check_match!/3:p0` |
| `Unk0369` | 2 | `Exhaustiveness.check_match!/3:p2`, `Exhaustiveness.check_one_case!/3:p2` |
| `Unk0370` | 1 | `Exhaustiveness.check_match!/3:ret` |
| `Unk0371` | 1 | `Exhaustiveness.check_one_case!/3:ret` |
| `Unk0372` | 2 | `Exhaustiveness.collect_cases/2:p0`, `Exhaustiveness.collect_children/2:p0` |
| `Unk0373` | 4 | `Exhaustiveness.collect_cases/2:p1`, `Exhaustiveness.collect_cases/2:ret`, `Exhaustiveness.collect_children/2:p1`, `Exhaustiveness.collect_children/2:ret` |
| `Unk0374` | 7 | `Exhaustiveness.default/1:p0`, `Exhaustiveness.default/1:ret`, `Exhaustiveness.head_ctors/1:p0`, `Exhaustiveness.specialize/3:p0`, `Exhaustiveness.specialize/3:ret`, `Exhaustiveness.useful?/3:p0`, `Exhaustiveness.witness/3:p0` |
| `Unk0375` | 3 | `Exhaustiveness.head_ctors/1:ret`, `Exhaustiveness.missing_head/2:p1`, `Exhaustiveness.signature/2:p1` |
| `Unk0376` | 2 | `Exhaustiveness.missing_head/2:ret`, `Exhaustiveness.witness/3:ret` |
| `Unk0377` | 1 | `Exhaustiveness.pascal/1:p0` |
| `Unk0378` | 1 | `Exhaustiveness.program_env/3:p1` |
| `Unk0379` | 1 | `Exhaustiveness.program_env/3:p2` |
| `Unk0380` | 1 | `Exhaustiveness.render/1:p0` |
| `Unk0381` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0382` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0383` | 1 | `Exhaustiveness.useful?/3:p1` |
| `Unk0384` | 1 | `Exhaustiveness.witness/3:ret` |
| `Unk0385` | 1 | `Fixpoint.check/4:p2` |
| `Unk0386` | 1 | `Fixpoint.check/4:p3` |
| `Unk0387` | 1 | `Fixpoint.check/4:ret` |
| `Unk0388` | 46 | `Format.apply_node/3:p0`, `Format.bd/3:p0`, `Format.bd/3:p1`, `Format.blank?/1:p0`, `Format.block_head?/2:p0`, `Format.block_head?/2:p1`, `Format.boundary?/1:p0`, `Format.chain?/1:p0`, `Format.chain_body/2:p0`, `Format.chain_body/2:p1`, `Format.chain_doc/1:p0`, `Format.chain_link?/2:p0`, `Format.chain_link?/2:p1`, `Format.chain_tail/2:p0`, `Format.comment_only?/1:p0`, `Format.declaration_line?/1:p0`, `Format.ends_with_comment?/1:p0`, `Format.head_tok/1:p0`, `Format.indent_and_render/4:p0`, `Format.lead_adjust/1:p0`, `Format.leading_wrap_op?/1:p0`, `Format.line_doc/1:p0`, `Format.mark/1:p0`, `Format.mark/1:ret`, `Format.mark/3:p0`, `Format.mark/3:p1`, `Format.mark/3:p2`, `Format.mark/3:ret`, `Format.merge_chains/1:p0`, `Format.merge_chains/1:ret`, `Format.next_code_line/1:p0`, `Format.next_code_line/1:ret`, `Format.node_doc/2:p0`, `Format.render_line/2:p0`, `Format.split_items/1:ret`, `Format.split_level/1:p0`, `Format.split_node?/2:p0`, `Format.tail_tok/1:p0`, `Format.take_until_level/3:p0`, `Format.take_until_level/3:p2`, `Format.take_until_level/3:ret`, `Format.trailing_op?/1:p0`, `Format.trailing_wrap_op?/1:p0`, `Format.update_stack/4:p0`, `Format.update_stack/4:p1`, `Format.value_end?/1:p0` |
| `Unk0389` | 10 | `Format.boundary_tok?/1:p0`, `Format.closer_lead?/1:p0`, `Format.cont_lead?/1:p0`, `Format.decl_kw?/1:p0`, `Format.head_tok/1:ret`, `Format.space?/2:p0`, `Format.space?/2:p1`, `Format.tail_tok/1:ret`, `Format.value_end_tok?/1:p0`, `Format.wrap_op_tok?/1:p0` |
| `Unk0390` | 4 | `Format.chain_tail/2:p1`, `Format.split_level/1:ret`, `Format.split_node?/2:p1`, `Format.take_until_level/3:p1` |
| `Unk0391` | 7 | `Format.chunk_on_comma/3:p0`, `Format.chunk_on_comma/3:p1`, `Format.chunk_on_comma/3:p2`, `Format.chunk_on_comma/3:ret`, `Format.finish_items/2:p0`, `Format.finish_items/2:p1`, `Format.finish_items/2:ret` |
| `Unk0392` | 6 | `Format.cons_group?/1:p0`, `Format.group_doc/4:p1`, `Format.has_comment?/1:p0`, `Format.magic_comma?/1:p0`, `Format.split_items/1:p0`, `Format.trailing_comma?/1:p0` |
| `Unk0393` | 1 | `Format.format_result/1:ret` |
| `Unk0394` | 1 | `Format.format_result/1:ret` |
| `Unk0395` | 3 | `Format.group_doc/4:p0`, `Format.group_doc/4:p2`, `Format.leaf/1:p0` |
| `Unk0396` | 2 | `Format.has_tok?/2:p0`, `Format.has_tok?/2:p1` |
| `Unk0397` | 1 | `Format.has_tok?/2:p0` |
| `Unk0398` | 6 | `Format.ll/3:p0`, `Format.ll/3:p1`, `Format.ll/3:p2`, `Format.ll/3:ret`, `Format.logical_lines/1:p0`, `Format.logical_lines/1:ret` |
| `Unk0399` | 1 | `Format.squeeze_blanks/1:p0` |
| `Unk0400` | 1 | `Format.squeeze_blanks/1:ret` |
| `Unk0401` | 1 | `Format.wrap_op_node?/1:p0` |
| `Unk0402` | 1 | `Formatting.apply_edits/2:p1` |
| `Unk0403` | 1 | `Formatting.bump_del/3:p0` |
| `Unk0404` | 3 | `Formatting.bump_del/3:p1`, `Formatting.bump_ins/3:p1`, `Formatting.start_hunk/1:p0` |
| `Unk0405` | 1 | `Formatting.bump_del/3:ret` |
| `Unk0406` | 1 | `Formatting.bump_ins/3:p0` |
| `Unk0407` | 1 | `Formatting.bump_ins/3:p2` |
| `Unk0408` | 1 | `Formatting.bump_ins/3:ret` |
| `Unk0409` | 1 | `Formatting.clamp/3:p2` |
| `Unk0410` | 1 | `Formatting.edit/1:p0` |
| `Unk0411` | 1 | `Formatting.edit/1:ret` |
| `Unk0412` | 4 | `Formatting.flush/2:p0`, `Formatting.flush/2:p1`, `Formatting.flush/2:ret`, `Formatting.to_hunks/1:ret` |
| `Unk0413` | 2 | `Formatting.formatting/1:ret`, `Formatting.hunks/2:ret` |
| `Unk0414` | 1 | `Formatting.range_formatting/3:ret` |
| `Unk0415` | 1 | `Formatting.start_hunk/1:ret` |
| `Unk0416` | 1 | `Formatting.to_hunks/1:p0` |
| `Unk0417` | 1 | `FormsEquiv.abstract_code/1:ret` |
| `Unk0418` | 3 | `FormsEquiv.alpha_rename/1:p0`, `FormsEquiv.walk_rename/2:p0`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0419` | 1 | `FormsEquiv.alpha_rename/1:ret` |
| `Unk0420` | 3 | `FormsEquiv.bool_clause/1:p0`, `FormsEquiv.bool_clause_pair/1:p0`, `FormsEquiv.bool_clause_pair/1:ret` |
| `Unk0421` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0422` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0423` | 2 | `FormsEquiv.canon_bool_case/1:p0`, `FormsEquiv.canon_bool_case/1:ret` |
| `Unk0424` | 9 | `FormsEquiv.diff/2:p0`, `FormsEquiv.diff/2:p1`, `FormsEquiv.equivalent?/2:p0`, `FormsEquiv.equivalent?/2:p1`, `FormsEquiv.normalize/1:p0`, `FormsEquiv.verified?/2:p0`, `FormsEquiv.verified?/2:p1`, `FormsEquiv.verify/2:p0`, `FormsEquiv.verify/2:p1` |
| `Unk0425` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0426` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0427` | 2 | `FormsEquiv.fold_neg_literal/1:p0`, `FormsEquiv.fold_neg_literal/1:ret` |
| `Unk0428` | 1 | `FormsEquiv.key/1:p0` |
| `Unk0429` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0430` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0431` | 1 | `FormsEquiv.normalize/1:ret` |
| `Unk0432` | 1 | `FormsEquiv.user_function?/1:p0` |
| `Unk0433` | 1 | `FormsEquiv.verify/2:ret` |
| `Unk0434` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0435` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0436` | 2 | `FormsEquiv.zero_anno/1:p0`, `FormsEquiv.zero_anno/1:ret` |
| `Unk0437` | 2 | `History.dedup_consecutive/1:p0`, `History.dedup_consecutive/1:ret` |
| `Unk0438` | 1 | `History.load/0:ret` |
| `Unk0439` | 101 | `Infer.app/2:p1`, `Infer.app/2:ret`, `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p2`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p2`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p2`, `Infer.bind_checked/3:ret`, `Infer.bind_params/4:p3`, `Infer.call_sig/6:p3`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.collect_specs/2:p1`, `Infer.con/1:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.free_vars/2:p1`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p1`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p1`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p1`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p2`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/5:p1`, `Infer.gen_pat/5:p2`, `Infer.gen_pat/5:p4`, `Infer.gen_pat/5:ret`, `Infer.gen_pat_cons/6:p2`, `Infer.gen_pat_cons/6:p3`, `Infer.gen_pat_cons/6:p5`, `Infer.gen_pat_cons/6:ret`, `Infer.generalize_map/3:p1`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:p1`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p1`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p2`, `Infer.parse_type/2:ret`, `Infer.render/3:p0`, `Infer.render/3:p2`, `Infer.render_wp/3:p0`, `Infer.render_wp/3:p2`, `Infer.resolve/2:p0`, `Infer.resolve/2:p1`, `Infer.resolve/2:ret`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p4`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p3`, `Infer.sigvar_call/5:p4`, `Infer.spec_pair/2:p1`, `Infer.store_new/0:ret`, `Infer.translate_spec/2:p1`, `Infer.translate_spec/2:ret`, `Infer.translate_type/2:ret`, `Infer.type_pair/2:ret`, `Infer.unify/3:p0`, `Infer.unify/3:p1`, `Infer.unify/3:p2`, `Infer.unify/3:ret`, `Infer.union_spec/3:p2`, `Infer.union_spec/3:ret`, `Infer.unk_vars/2:p0`, `Infer.unk_vars/2:p1`, `Infer.vec_spec/2:p1`, `Infer.vec_spec/2:ret`, `Transpile.infer_sigs/2:p1` |
| `Unk0440` | 59 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p1`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p1`, `Infer.bind_checked/3:ret`, `Infer.bind_params/4:p3`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/5:p4`, `Infer.gen_pat/5:ret`, `Infer.gen_pat_cons/6:p5`, `Infer.gen_pat_cons/6:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p1`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p1`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0441` | 55 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:ret`, `Infer.bind_params/4:p3`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/5:p4`, `Infer.gen_pat/5:ret`, `Infer.gen_pat_cons/6:p5`, `Infer.gen_pat_cons/6:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.occurs?/3:p0`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0442` | 20 | `Infer.apply_spec_terms/4:p0`, `Infer.bind_params/4:p2`, `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/2:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.gen_pat/5:p3`, `Infer.gen_pat_cons/6:p4`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0443` | 2 | `Infer.apply_spec_terms/4:p1`, `Infer.seed_spec/6:p3` |
| `Unk0444` | 1 | `Infer.bind/3:ret` |
| `Unk0445` | 3 | `Infer.bind_checked/3:ret`, `Infer.do_unify/3:ret`, `Infer.unify/3:ret` |
| `Unk0446` | 1 | `Infer.bind_params/4:p0` |
| `Unk0447` | 1 | `Infer.bind_params/4:p1` |
| `Unk0448` | 20 | `Infer.bind_params/4:p2`, `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/2:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.gen_pat/5:p3`, `Infer.gen_pat_cons/6:p4`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.seed_spec/6:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0449` | 17 | `Infer.bind_params/4:p2`, `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.gen_pat/5:p3`, `Infer.gen_pat_cons/6:p4`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0450` | 1 | `Infer.bind_params/4:ret` |
| `Unk0451` | 1 | `Infer.build_ctx/2:p0` |
| `Unk0452` | 1 | `Infer.build_ctx/2:p1` |
| `Unk0453` | 1 | `Infer.build_ctx/2:ret` |
| `Unk0454` | 1 | `Infer.build_ledger/2:p0` |
| `Unk0455` | 1 | `Infer.build_ledger/2:ret` |
| `Unk0456` | 1 | `Infer.call_sig/6:p1` |
| `Unk0457` | 1 | `Infer.case_arm/1:p0` |
| `Unk0458` | 1 | `Infer.case_arm/1:ret` |
| `Unk0459` | 1 | `Infer.case_arm/1:ret` |
| `Unk0460` | 6 | `Infer.collect_specs/2:p1`, `Infer.spec_pair/2:p1`, `Infer.translate_spec/2:p1`, `Infer.union_spec/3:p2`, `Infer.vec_spec/2:p1`, `Transpile.infer_sigs/2:p1` |
| `Unk0461` | 1 | `Infer.collect_types/2:ret` |
| `Unk0462` | 1 | `Infer.collect_types/2:ret` |
| `Unk0463` | 1 | `Infer.free_vars/2:ret` |
| `Unk0464` | 1 | `Infer.fresh_n/2:ret` |
| `Unk0465` | 2 | `Infer.freshen_tvars/2:p0`, `Infer.freshen_tvars/2:ret` |
| `Unk0466` | 1 | `Infer.freshen_tvars/2:ret` |
| `Unk0467` | 3 | `Infer.gen_pat/5:p0`, `Infer.gen_pat_cons/6:p0`, `Infer.gen_pat_cons/6:p1` |
| `Unk0468` | 1 | `Infer.generalize_map/3:p0` |
| `Unk0469` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0470` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0471` | 3 | `Infer.hole_or/2:p0`, `Infer.hole_or/2:p1`, `Infer.hole_or/2:ret` |
| `Unk0472` | 2 | `Infer.hole_sig?/1:p0`, `Infer.infer_group/2:ret` |
| `Unk0473` | 1 | `Infer.infer_group/2:p0` |
| `Unk0474` | 1 | `Infer.instantiate/5:p0` |
| `Unk0475` | 2 | `Infer.load_prelude_sigs/0:ret`, `Infer.prelude_sigs/0:ret` |
| `Unk0476` | 1 | `Infer.mark_num/2:ret` |
| `Unk0477` | 1 | `Infer.max_ph/1:p0` |
| `Unk0478` | 1 | `Infer.maybe_tuple/4:p0` |
| `Unk0479` | 1 | `Infer.mod_name/1:p0` |
| `Unk0480` | 1 | `Infer.ok_payload/3:p0` |
| `Unk0481` | 2 | `Infer.ok_payload/3:p2`, `Infer.result_analysis/3:p2` |
| `Unk0482` | 1 | `Infer.ok_payload/3:ret` |
| `Unk0483` | 1 | `Infer.parse_type/2:p1` |
| `Unk0484` | 2 | `Infer.parse_type/2:p1`, `Infer.tvar?/1:p0` |
| `Unk0485` | 1 | `Infer.pascal/1:p0` |
| `Unk0486` | 1 | `Infer.prime_xmod/2:p0` |
| `Unk0487` | 1 | `Infer.prime_xmod/2:p1` |
| `Unk0488` | 1 | `Infer.prime_xmod/2:ret` |
| `Unk0489` | 1 | `Infer.put_slot/3:p0` |
| `Unk0490` | 1 | `Infer.put_slot/3:ret` |
| `Unk0491` | 1 | `Infer.render_wp/3:p1` |
| `Unk0492` | 1 | `Infer.resolve_program/2:p0` |
| `Unk0493` | 2 | `Infer.resolve_program/2:ret`, `Infer.whole_program/4:ret` |
| `Unk0494` | 1 | `Infer.resolve_struct_params/4:p0` |
| `Unk0495` | 1 | `Infer.resolve_struct_params/4:p1` |
| `Unk0496` | 1 | `Infer.result_analysis/3:p0` |
| `Unk0497` | 1 | `Infer.result_analysis/3:ret` |
| `Unk0498` | 1 | `Infer.result_tag/1:p0` |
| `Unk0499` | 1 | `Infer.result_tag/1:ret` |
| `Unk0500` | 1 | `Infer.result_tag/1:ret` |
| `Unk0501` | 1 | `Infer.sig_of/1:p0` |
| `Unk0502` | 1 | `Infer.sig_of/1:ret` |
| `Unk0503` | 1 | `Infer.sigvar_call/5:p1` |
| `Unk0504` | 1 | `Infer.sigvar_call/5:p2` |
| `Unk0505` | 1 | `Infer.sigvar_call/5:ret` |
| `Unk0506` | 1 | `Infer.slot_sig/3:p2` |
| `Unk0507` | 1 | `Infer.slot_sig/3:ret` |
| `Unk0508` | 1 | `Infer.spec_pair/2:p0` |
| `Unk0509` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0510` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0511` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0512` | 1 | `Infer.spec_str/1:p0` |
| `Unk0513` | 4 | `Infer.translate_spec/2:p0`, `Infer.union_spec/3:p0`, `Infer.union_spec/3:p1`, `Infer.vec_spec/2:p0` |
| `Unk0514` | 1 | `Infer.translate_type/2:p0` |
| `Unk0515` | 1 | `Infer.tvar?/1:ret` |
| `Unk0516` | 1 | `Infer.tvar_name/1:p0` |
| `Unk0517` | 1 | `Infer.tvar_name/1:ret` |
| `Unk0518` | 1 | `Infer.type_pair/2:p0` |
| `Unk0519` | 1 | `Infer.type_pair/2:ret` |
| `Unk0520` | 1 | `Infer.unk_vars/2:ret` |
| `Unk0521` | 3 | `Infer.whole_program/4:p0`, `PortAnalysis.collect_groups/1:ret`, `PortAnalysis.param_name_index/1:p0` |
| `Unk0522` | 2 | `Infer.whole_program/4:p1`, `Transpile.stdlib_map/0:ret` |
| `Unk0523` | 2 | `Infer.whole_program/4:p2`, `PortAnalysis.cluster_sums/1:ret` |
| `Unk0524` | 1 | `Infer.whole_program/4:p3` |
| `Unk0525` | 1 | `Infer.xmod_cache/0:ret` |
| `Unk0526` | 1 | `InferLocal.fill_funcs/2:ret` |
| `Unk0527` | 1 | `InferLocal.pass/2:ret` |
| `Unk0528` | 2 | `Interp.concat_chain/1:p0`, `Interp.concat_chain/1:ret` |
| `Unk0529` | 1 | `Interp.resolve_part/4:p0` |
| `Unk0530` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0531` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0532` | 2 | `JS.all_funcs/1:p0`, `JS.all_funcs/1:ret` |
| `Unk0533` | 1 | `JS.all_funcs/1:p0` |
| `Unk0534` | 1 | `JS.arm_return/3:p0` |
| `Unk0535` | 1 | `JS.arm_return/3:p1` |
| `Unk0536` | 1 | `JS.bind_lines/1:p0` |
| `Unk0537` | 4 | `JS.block_return/2:p0`, `JVM.block_value/1:p0`, `Shadow.ded_block/4:ret`, `Shadow.dedup/3:ret` |
| `Unk0538` | 1 | `JS.case_arm_js/2:p0` |
| `Unk0539` | 1 | `JS.clause_js/2:p0` |
| `Unk0540` | 4 | `JS.clause_return/3:p1`, `JS.guarded_return/4:p2`, `JVM.clause_value/2:p1`, `Shadow.dedup/3:p1` |
| `Unk0541` | 1 | `JS.cp_lit/2:p0` |
| `Unk0542` | 1 | `JS.dispatcher_js/5:p0` |
| `Unk0543` | 1 | `JS.dispatcher_js/5:p1` |
| `Unk0544` | 1 | `JS.dispatcher_js/5:p2` |
| `Unk0545` | 1 | `JS.dispatcher_js/5:p3` |
| `Unk0546` | 2 | `JS.float?/1:p0`, `JS.num_js/2:p0` |
| `Unk0547` | 1 | `JS.guarded_return/4:p1` |
| `Unk0548` | 3 | `JS.js_atom/1:p0`, `JS.js_str/1:p0`, `JS.lit_js/2:p0` |
| `Unk0549` | 1 | `JS.js_guard!/4:p1` |
| `Unk0550` | 1 | `JS.js_guard!/4:p2` |
| `Unk0551` | 1 | `JS.js_guard!/4:p3` |
| `Unk0552` | 1 | `JS.js_guard!/4:ret` |
| `Unk0553` | 1 | `JS.js_number_int?/1:p0` |
| `Unk0554` | 1 | `JS.mangle/3:p0` |
| `Unk0555` | 1 | `JS.mangle/3:p1` |
| `Unk0556` | 1 | `JS.mangle/3:p2` |
| `Unk0557` | 1 | `JS.match_elems/3:p0` |
| `Unk0558` | 1 | `JS.match_elems/3:ret` |
| `Unk0559` | 1 | `JS.paren/2:p0` |
| `Unk0560` | 1 | `JS.paren/2:p1` |
| `Unk0561` | 1 | `JS.pat_match/3:ret` |
| `Unk0562` | 1 | `JS.reject_mixed_int_mode!/1:ret` |
| `Unk0563` | 1 | `JS.reject_wide_int!/2:p0` |
| `Unk0564` | 1 | `JS.reject_wide_int!/2:p1` |
| `Unk0565` | 1 | `JS.reject_wide_int!/2:ret` |
| `Unk0566` | 1 | `JS.stmt_js/2:p0` |
| `Unk0567` | 1 | `JS.stmt_return/2:p0` |
| `Unk0568` | 1 | `JS.stmt_return/2:p1` |
| `Unk0569` | 1 | `JS.struct_name_set/1:ret` |
| `Unk0570` | 1 | `JS.sum_ctor_map/1:ret` |
| `Unk0571` | 1 | `JS.sum_guard_js/1:p0` |
| `Unk0572` | 2 | `JVM.all_funcs/1:p0`, `JVM.all_funcs/1:ret` |
| `Unk0573` | 1 | `JVM.all_funcs/1:p0` |
| `Unk0574` | 1 | `JVM.bind_str/1:p0` |
| `Unk0575` | 1 | `JVM.case_arms/2:p0` |
| `Unk0576` | 1 | `JVM.case_arms/2:ret` |
| `Unk0577` | 1 | `JVM.case_arms/2:ret` |
| `Unk0578` | 4 | `JVM.clause_lines/1:p0`, `JVM.closed_or_cond/3:p2`, `JVM.prepend_if/3:p2`, `JVM.run_or_cond/3:p2` |
| `Unk0579` | 1 | `JVM.clause_match/1:p0` |
| `Unk0580` | 1 | `JVM.clause_match/1:ret` |
| `Unk0581` | 3 | `JVM.closed_or_cond/3:p0`, `JVM.prepend_if/3:p0`, `JVM.run_or_cond/3:p0` |
| `Unk0582` | 1 | `JVM.function_kt/1:p0` |
| `Unk0583` | 1 | `JVM.guarded_arm/2:p1` |
| `Unk0584` | 1 | `JVM.guarded_return/3:p0` |
| `Unk0585` | 1 | `JVM.guarded_return/3:p1` |
| `Unk0586` | 1 | `JVM.guarded_return/3:p2` |
| `Unk0587` | 1 | `JVM.kotlin_module/2:p1` |
| `Unk0588` | 2 | `JVM.kt_str/1:p0`, `JVM.lit_kt/1:p0` |
| `Unk0589` | 1 | `JVM.kt_type/1:ret` |
| `Unk0590` | 1 | `JVM.pat_match/2:ret` |
| `Unk0591` | 1 | `JVM.stmt_kt/1:p0` |
| `Unk0592` | 1 | `JVM.stmt_value/1:p0` |
| `Unk0593` | 1 | `JVM.sum_decl/1:p0` |
| `Unk0594` | 1 | `JVM.to_jar/3:p2` |
| `Unk0595` | 1 | `JVM.to_jar/3:ret` |
| `Unk0596` | 1 | `JVM.variant_decl/2:p0` |
| `Unk0597` | 1 | `JVM.variant_decl/2:p1` |
| `Unk0598` | 4 | `Lexer.binify/1:ret`, `Lexer.capture_hole/3:ret`, `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0599` | 1 | `Lexer.capture_hole/3:ret` |
| `Unk0600` | 1 | `Lexer.char_escape/1:p0` |
| `Unk0601` | 2 | `Lexer.char_escape/1:ret`, `Lexer.parse_hex!/1:p0` |
| `Unk0602` | 2 | `Lexer.close_char/1:ret`, `Lexer.lex_char/1:ret` |
| `Unk0603` | 1 | `Lexer.collapse_nl/1:p0` |
| `Unk0604` | 1 | `Lexer.collapse_nl/1:ret` |
| `Unk0605` | 1 | `Lexer.detokenize/2:p0` |
| `Unk0606` | 1 | `Lexer.escape_str/1:p0` |
| `Unk0607` | 75 | `Lexer.expr_tokens/1:ret`, `Pratt.climb/3:p1`, `Pratt.climb/3:ret`, `Pratt.collect_dots/2:p1`, `Pratt.collect_dots/2:ret`, `Pratt.expect_kw/2:p0`, `Pratt.expect_kw/2:ret`, `Pratt.expect_op/2:p0`, `Pratt.expect_op/2:ret`, `Pratt.expect_rbracket/1:p0`, `Pratt.expect_rbracket/1:ret`, `Pratt.expect_rparen/1:p0`, `Pratt.expect_rparen/1:ret`, `Pratt.finish_arg/2:p1`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:p0`, `Pratt.parse_args/1:ret`, `Pratt.parse_arms/2:p0`, `Pratt.parse_arms/2:ret`, `Pratt.parse_block/1:p0`, `Pratt.parse_block/1:ret`, `Pratt.parse_capture/1:p0`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:p0`, `Pratt.parse_case/1:ret`, `Pratt.parse_expr/2:p0`, `Pratt.parse_expr/2:ret`, `Pratt.parse_if/1:p0`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:p0`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:p0`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p0`, `Pratt.parse_map/2:ret`, `Pratt.parse_param/1:p0`, `Pratt.parse_param/1:ret`, `Pratt.parse_params/1:p0`, `Pratt.parse_params/1:ret`, `Pratt.parse_pat/1:p0`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_args/2:p0`, `Pratt.parse_pat_args/2:ret`, `Pratt.parse_pat_fields/2:p0`, `Pratt.parse_pat_fields/2:ret`, `Pratt.parse_pat_list/2:p0`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p0`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p0`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_path/1:p0`, `Pratt.parse_path/1:ret`, `Pratt.parse_pats/2:p0`, `Pratt.parse_postfix/2:p1`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:p0`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:p0`, `Pratt.parse_primary/1:ret`, `Pratt.parse_stmt/1:p0`, `Pratt.parse_stmt/1:ret`, `Pratt.parse_stmts/2:p0`, `Pratt.parse_stmts/2:ret`, `Pratt.parse_tuple/2:p0`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_type/1:p0`, `Pratt.parse_type/1:ret`, `Pratt.parse_type_args/2:p0`, `Pratt.parse_type_args/2:ret`, `Pratt.parse_with/1:p0`, `Pratt.parse_with/1:ret`, `Pratt.parse_with_clauses/2:p0`, `Pratt.parse_with_clauses/2:ret`, `Pratt.peek_infix/1:p0` |
| `Unk0608` | 2 | `Lexer.lex/2:p1`, `Lexer.word/1:ret` |
| `Unk0609` | 2 | `Lexer.lex/2:ret`, `Lexer.tokenize_trivia/1:ret` |
| `Unk0610` | 1 | `Lexer.lex_char/1:ret` |
| `Unk0611` | 2 | `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0612` | 1 | `Lexer.lex_parts/3:ret` |
| `Unk0613` | 1 | `Lexer.lex_string_token/1:ret` |
| `Unk0614` | 3 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:p0`, `Lexer.string_token/1:ret` |
| `Unk0615` | 2 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:ret` |
| `Unk0616` | 1 | `Lexer.punct/1:ret` |
| `Unk0617` | 1 | `Lexer.strip_trivia/1:p0` |
| `Unk0618` | 1 | `Lexer.strip_trivia/1:ret` |
| `Unk0619` | 1 | `Lexer.take_comment/1:ret` |
| `Unk0620` | 4 | `Lexer.take_hex/2:p0`, `Lexer.take_hex/2:ret`, `Lexer.take_hex/3:p0`, `Lexer.take_hex/3:ret` |
| `Unk0621` | 1 | `Lexer.tok_str/2:p0` |
| `Unk0622` | 1 | `Lexer.tokenize/1:ret` |
| `Unk0623` | 2 | `Livebook.eval/1:ret`, `Livebook.output/1:ret` |
| `Unk0624` | 2 | `Livebook.run/2:p0`, `Livebook.run/2:ret` |
| `Unk0625` | 1 | `Livebook.run/2:ret` |
| `Unk0626` | 1 | `Livebook.session_pid/0:ret` |
| `Unk0627` | 4 | `Lower.add_list_elem_vars/2:p0`, `Lower.add_list_elem_vars/2:ret`, `Lower.add_var/2:p0`, `Lower.add_var/2:ret` |
| `Unk0628` | 1 | `Lower.add_list_elem_vars/2:p1` |
| `Unk0629` | 1 | `Lower.add_var/2:p1` |
| `Unk0630` | 1 | `Lower.all_pat_vars/1:ret` |
| `Unk0631` | 1 | `Lower.arm_rebinds/3:p0` |
| `Unk0632` | 3 | `Lower.arm_rebinds/3:p1`, `Lower.iso_cons_positions/1:ret`, `Lower.rust_scrut/2:p1` |
| `Unk0633` | 4 | `Lower.arm_rebinds/3:p2`, `Lower.collect_ids/2:p1`, `Lower.collect_ids/2:ret`, `Lower.used_ids/1:ret` |
| `Unk0634` | 1 | `Lower.arm_rebinds/3:ret` |
| `Unk0635` | 1 | `Lower.assoc/1:ret` |
| `Unk0636` | 1 | `Lower.body_ast/2:p0` |
| `Unk0637` | 1 | `Lower.body_ast/2:p1` |
| `Unk0638` | 1 | `Lower.body_ast/2:ret` |
| `Unk0639` | 5 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p0`, `Lower.param_rtypes/2:p1` |
| `Unk0640` | 4 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p1` |
| `Unk0641` | 3 | `Lower.borrow_arg/5:p4`, `Lower.insert_borrows/4:p2`, `Lower.owned_field_var?/2:p1` |
| `Unk0642` | 1 | `Lower.borrow_arg/5:ret` |
| `Unk0643` | 1 | `Lower.borrowed_in_pat/2:ret` |
| `Unk0644` | 1 | `Lower.borrowed_vars/2:p0` |
| `Unk0645` | 1 | `Lower.borrowed_vars/2:p1` |
| `Unk0646` | 1 | `Lower.borrowed_vars/2:ret` |
| `Unk0647` | 1 | `Lower.build_env/3:p1` |
| `Unk0648` | 1 | `Lower.build_env/3:p2` |
| `Unk0649` | 2 | `Lower.build_env/3:ret`, `Lower.check!/2:p1` |
| `Unk0650` | 3 | `Lower.build_meta/1:ret`, `Lower.ctx/4:p0`, `Lower.to_rust/6:p2` |
| `Unk0651` | 4 | `Lower.build_struct_meta/1:ret`, `Lower.ctx/4:p1`, `Lower.to_elixir/4:p3`, `Lower.to_rust/6:p4` |
| `Unk0652` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0653` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0654` | 1 | `Lower.char_vars/2:p0` |
| `Unk0655` | 1 | `Lower.char_vars/2:p1` |
| `Unk0656` | 1 | `Lower.char_vars/2:ret` |
| `Unk0657` | 14 | `Lower.check!/2:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_used?/2:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_rust/6:p0` |
| `Unk0658` | 1 | `Lower.check!/2:ret` |
| `Unk0659` | 1 | `Lower.collect_ids/2:p0` |
| `Unk0660` | 1 | `Lower.collect_owned_field_vars/3:p0` |
| `Unk0661` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0662` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0663` | 6 | `Lower.collect_owned_field_vars/3:p2`, `Lower.collect_owned_field_vars/3:ret`, `Lower.ofb/3:p2`, `Lower.ofb/3:ret`, `Lower.owned_field_binders/2:ret`, `Lower.slice_binders/2:ret` |
| `Unk0664` | 1 | `Lower.compile/5:p2` |
| `Unk0665` | 1 | `Lower.compile/5:p3` |
| `Unk0666` | 1 | `Lower.compile_beam/4:p2` |
| `Unk0667` | 1 | `Lower.compile_beam/4:p3` |
| `Unk0668` | 1 | `Lower.compile_elixir/4:p2` |
| `Unk0669` | 1 | `Lower.compile_elixir/4:p3` |
| `Unk0670` | 1 | `Lower.compile_module/1:p0` |
| `Unk0671` | 1 | `Lower.compile_module_beam/1:p0` |
| `Unk0672` | 1 | `Lower.cons_tail_names/1:ret` |
| `Unk0673` | 3 | `Lower.const_set/1:p0`, `Lower.ex_const/2:p0`, `Lower.rust_const/2:p0` |
| `Unk0674` | 2 | `Lower.const_set/1:ret`, `Lower.ctx/4:p2` |
| `Unk0675` | 3 | `Lower.core_pat_rs/2:p1`, `Lower.pat_rs/2:p1`, `Lower.resolve_rust_pats/2:p1` |
| `Unk0676` | 1 | `Lower.core_pat_vars/1:ret` |
| `Unk0677` | 1 | `Lower.ctx/4:p3` |
| `Unk0678` | 2 | `Lower.deref_ids/2:p0`, `Lower.deref_ids/2:ret` |
| `Unk0679` | 1 | `Lower.deref_ids/2:p1` |
| `Unk0680` | 2 | `Lower.elixir_clauses/3:p1`, `Lower.ex_const/2:p1` |
| `Unk0681` | 1 | `Lower.emit_ast/2:ret` |
| `Unk0682` | 1 | `Lower.emit_ctx/1:p0` |
| `Unk0683` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0684` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0685` | 1 | `Lower.emit_expr/2:ret` |
| `Unk0686` | 2 | `Lower.enum_generics/2:p0`, `Lower.enum_generics/2:p1` |
| `Unk0687` | 1 | `Lower.enum_generics/2:p1` |
| `Unk0688` | 1 | `Lower.ex_struct/1:p0` |
| `Unk0689` | 1 | `Lower.ex_typespec/1:p0` |
| `Unk0690` | 1 | `Lower.ex_use/1:p0` |
| `Unk0691` | 2 | `Lower.fn_all_tvars/3:p1`, `Lower.pair_inst/2:ret` |
| `Unk0692` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0693` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0694` | 1 | `Lower.guard_str/4:p0` |
| `Unk0695` | 1 | `Lower.guard_str/4:p3` |
| `Unk0696` | 1 | `Lower.impl_param/2:p0` |
| `Unk0697` | 1 | `Lower.infer_concrete_params/3:p1` |
| `Unk0698` | 1 | `Lower.infer_tvar_binding/2:p0` |
| `Unk0699` | 1 | `Lower.infer_tvar_binding/2:p1` |
| `Unk0700` | 1 | `Lower.infer_tvar_binding/2:ret` |
| `Unk0701` | 1 | `Lower.list_rpat?/1:p0` |
| `Unk0702` | 1 | `Lower.member_scan/3:p0` |
| `Unk0703` | 3 | `Lower.member_scan/3:p1`, `Lower.strip_prefix/2:p1`, `Lower.word_scan/4:p1` |
| `Unk0704` | 1 | `Lower.module_elixir/1:p0` |
| `Unk0705` | 1 | `Lower.module_rust/1:p0` |
| `Unk0706` | 2 | `Lower.ofb/3:p0`, `Lower.owned_field_binders/2:p0` |
| `Unk0707` | 1 | `Lower.owned_scrut?/2:p0` |
| `Unk0708` | 1 | `Lower.owned_str_arg/1:p0` |
| `Unk0709` | 1 | `Lower.owned_str_arg/1:ret` |
| `Unk0710` | 2 | `Lower.parametric_param_map/1:ret`, `Lower.rust_enum/3:p2` |
| `Unk0711` | 2 | `Lower.parametric_used?/2:p1`, `Lower.word_member?/2:p1` |
| `Unk0712` | 2 | `Lower.pascal?/1:p0`, `Lower.variant_info/2:p1` |
| `Unk0713` | 1 | `Lower.pipe_to_call/2:p0` |
| `Unk0714` | 1 | `Lower.proto_method_traits/1:ret` |
| `Unk0715` | 1 | `Lower.pub_sig_type_names/1:p0` |
| `Unk0716` | 1 | `Lower.pub_sig_type_names/1:ret` |
| `Unk0717` | 1 | `Lower.ref_type/2:p1` |
| `Unk0718` | 1 | `Lower.resolve_consts/2:p1` |
| `Unk0719` | 2 | `Lower.resolve_structs/2:p1`, `Lower.struct_pairs/4:p3` |
| `Unk0720` | 3 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0721` | 6 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_info/2:ret`, `Lower.variant_lit/2:p0`, `Lower.variant_pairs/3:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0722` | 1 | `Lower.result_parts/1:ret` |
| `Unk0723` | 2 | `Lower.rewrite_proto_calls/2:p0`, `Lower.rewrite_proto_calls/2:ret` |
| `Unk0724` | 1 | `Lower.rewrite_proto_calls/2:p1` |
| `Unk0725` | 1 | `Lower.rust_case/4:p1` |
| `Unk0726` | 1 | `Lower.rust_generics/1:p0` |
| `Unk0727` | 1 | `Lower.rust_impl_method/6:p0` |
| `Unk0728` | 1 | `Lower.rust_impl_method/6:p1` |
| `Unk0729` | 1 | `Lower.rust_lit_type/1:p0` |
| `Unk0730` | 1 | `Lower.rust_proto_body/3:p0` |
| `Unk0731` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0732` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0733` | 1 | `Lower.rust_proto_body/3:p2` |
| `Unk0734` | 1 | `Lower.rust_proto_body/3:ret` |
| `Unk0735` | 1 | `Lower.rust_protocols/4:ret` |
| `Unk0736` | 1 | `Lower.rust_scrut/2:p0` |
| `Unk0737` | 1 | `Lower.rust_struct/2:p0` |
| `Unk0738` | 1 | `Lower.rust_struct/2:p1` |
| `Unk0739` | 1 | `Lower.rust_trait/1:p0` |
| `Unk0740` | 1 | `Lower.rust_use/1:p0` |
| `Unk0741` | 1 | `Lower.rustify_parametric/2:p1` |
| `Unk0742` | 2 | `Lower.sig_param/2:p1`, `Lower.trait_params/2:p1` |
| `Unk0743` | 1 | `Lower.slice_binders/2:p0` |
| `Unk0744` | 1 | `Lower.slice_elem_vars/1:ret` |
| `Unk0745` | 1 | `Lower.str_lit/1:p0` |
| `Unk0746` | 2 | `Lower.strip_prefix/2:p0`, `Lower.strip_prefix/2:ret` |
| `Unk0747` | 1 | `Lower.strip_prefix/2:ret` |
| `Unk0748` | 1 | `Lower.struct_pairs/4:p0` |
| `Unk0749` | 1 | `Lower.struct_pairs/4:p1` |
| `Unk0750` | 1 | `Lower.struct_pairs/4:ret` |
| `Unk0751` | 1 | `Lower.subst_assoc/2:p1` |
| `Unk0752` | 2 | `Lower.tail_expr/1:p0`, `Lower.tail_expr/1:ret` |
| `Unk0753` | 1 | `Lower.to_elixir/4:p2` |
| `Unk0754` | 1 | `Lower.to_elixir/4:ret` |
| `Unk0755` | 1 | `Lower.to_rust/6:p3` |
| `Unk0756` | 1 | `Lower.to_rust/6:p5` |
| `Unk0757` | 1 | `Lower.to_rust/6:ret` |
| `Unk0758` | 1 | `Lower.tvar_name?/1:p0` |
| `Unk0759` | 1 | `Lower.type_idents/1:p0` |
| `Unk0760` | 1 | `Lower.type_idents/1:ret` |
| `Unk0761` | 1 | `Lower.type_param_tvars/1:p0` |
| `Unk0762` | 1 | `Lower.type_param_tvars/1:ret` |
| `Unk0763` | 1 | `Lower.user_type?/2:p0` |
| `Unk0764` | 2 | `Lower.variant_lit/2:p1`, `Lower.variant_pairs/3:ret` |
| `Unk0765` | 2 | `Lower.widen_char_arith/2:p1`, `Lower.wrap_char/2:p1` |
| `Unk0766` | 1 | `Lower.with_chain_rs/4:p0` |
| `Unk0767` | 1 | `Lower.word_member?/2:p0` |
| `Unk0768` | 1 | `Lower.word_scan/4:p0` |
| `Unk0769` | 4 | `Macro.binders_here/1:p0`, `Macro.collect_binders/1:p0`, `Macro.freshen/2:p0`, `Macro.rename/2:p0` |
| `Unk0770` | 2 | `Macro.binders_here/1:ret`, `Macro.collect_binders/1:ret` |
| `Unk0771` | 1 | `Macro.build_env/1:p0` |
| `Unk0772` | 1 | `Macro.check_portable!/2:p0` |
| `Unk0773` | 1 | `Macro.check_portable!/2:ret` |
| `Unk0774` | 1 | `Macro.expand/3:p2` |
| `Unk0775` | 1 | `Macro.freshen/2:p1` |
| `Unk0776` | 4 | `Macro.freshen/2:ret`, `Macro.rename/2:p1`, `Macro.rename/2:ret`, `Macro.substitute/2:p0` |
| `Unk0777` | 1 | `Macro.rename/2:p1` |
| `Unk0778` | 1 | `Macro.substitute/2:p1` |
| `Unk0779` | 1 | `Opaque.do_erase/2:p0` |
| `Unk0780` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0781` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0782` | 1 | `Opaque.erase_clause/3:p0` |
| `Unk0783` | 1 | `Opaque.erase_clause/3:p1` |
| `Unk0784` | 1 | `Opaque.erase_clause/3:p2` |
| `Unk0785` | 1 | `Opaque.erase_const/2:p0` |
| `Unk0786` | 1 | `Opaque.erase_const/2:p1` |
| `Unk0787` | 3 | `Opaque.erase_ctx/1:p0`, `Opaque.opaques/1:p0`, `Opaque.opaques/1:ret` |
| `Unk0788` | 1 | `Opaque.erase_func/2:p0` |
| `Unk0789` | 1 | `Opaque.erase_mod/2:p0` |
| `Unk0790` | 1 | `Opaque.erase_struct/2:p0` |
| `Unk0791` | 1 | `Opaque.erase_type/2:p0` |
| `Unk0792` | 1 | `Opaque.erase_variant/2:p0` |
| `Unk0793` | 1 | `Opaque.erase_variant/2:p1` |
| `Unk0794` | 1 | `Opaque.opaques/1:p0` |
| `Unk0795` | 4 | `Opaque.strip/3:p0`, `Opaque.strip/3:ret`, `Opaque.strip_into/3:p0`, `Opaque.strip_into/3:ret` |
| `Unk0796` | 2 | `Opaque.strip/3:p1`, `Opaque.strip_into/3:p1` |
| `Unk0797` | 4 | `Opaque.subst/2:p0`, `Opaque.subst/2:ret`, `Opaque.subst_fix/4:p0`, `Opaque.subst_fix/4:ret` |
| `Unk0798` | 2 | `Opaque.subst/2:p1`, `Opaque.subst_fix/4:p1` |
| `Unk0799` | 1 | `Opaque.subst_fix/4:p2` |
| `Unk0800` | 2 | `PatternLower.lower/2:ret`, `PatternLower.lower_list/3:ret` |
| `Unk0801` | 1 | `PatternLower.lower_clause/2:p0` |
| `Unk0802` | 1 | `PatternLower.lower_many/2:ret` |
| `Unk0803` | 2 | `PortAnalysis.analyze/1:p0`, `PortAnalysis.src_of/2:p0` |
| `Unk0804` | 1 | `PortAnalysis.analyze/1:ret` |
| `Unk0805` | 3 | `PortAnalysis.case_arm_sets/1:p0`, `PortAnalysis.clause_head_sets/1:p0`, `PortAnalysis.dispatch_sets/1:p0` |
| `Unk0806` | 2 | `PortAnalysis.case_arm_sets/1:ret`, `PortAnalysis.clause_head_sets/1:ret` |
| `Unk0807` | 2 | `PortAnalysis.cluster_sums/1:p0`, `PortAnalysis.dispatch_sets/1:ret` |
| `Unk0808` | 1 | `PortAnalysis.collect_errors/2:p0` |
| `Unk0809` | 2 | `PortAnalysis.collect_errors/2:p1`, `PortAnalysis.collect_errors/2:ret` |
| `Unk0810` | 1 | `PortAnalysis.collect_groups/1:p0` |
| `Unk0811` | 1 | `PortAnalysis.collect_structs/2:p0` |
| `Unk0812` | 2 | `PortAnalysis.collect_structs/2:p1`, `PortAnalysis.collect_structs/2:ret` |
| `Unk0813` | 7 | `PortAnalysis.decision_stats/2:p0`, `PortAnalysis.errors_section/1:p0`, `PortAnalysis.holes_section/2:p0`, `PortAnalysis.sigs_section/2:p0`, `PortAnalysis.summary_section/2:p0`, `PortAnalysis.sums_section/2:p0`, `PortAnalysis.to_markdown/2:p0` |
| `Unk0814` | 2 | `PortAnalysis.decision_stats/2:p1`, `PortAnalysis.summary_section/2:p1` |
| `Unk0815` | 1 | `PortAnalysis.error_proposal/1:p0` |
| `Unk0816` | 1 | `PortAnalysis.error_proposal/1:ret` |
| `Unk0817` | 1 | `PortAnalysis.error_shape/1:p0` |
| `Unk0818` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0819` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0820` | 1 | `PortAnalysis.head_name_pats/1:p0` |
| `Unk0821` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0822` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0823` | 3 | `PortAnalysis.holes_section/2:p1`, `PortAnalysis.sigs_section/2:p1`, `PortSpec.apply_subs/2:p1` |
| `Unk0824` | 2 | `PortAnalysis.module_name/1:p0`, `PortAnalysis.module_report/3:p1` |
| `Unk0825` | 1 | `PortAnalysis.module_report/3:p0` |
| `Unk0826` | 1 | `PortAnalysis.module_report/3:ret` |
| `Unk0827` | 1 | `PortAnalysis.module_stmts/1:p0` |
| `Unk0828` | 1 | `PortAnalysis.needs_review?/1:p0` |
| `Unk0829` | 1 | `PortAnalysis.param_name_index/1:ret` |
| `Unk0830` | 1 | `PortAnalysis.parse/1:p0` |
| `Unk0831` | 1 | `PortAnalysis.parse/1:ret` |
| `Unk0832` | 1 | `PortAnalysis.pascal/1:p0` |
| `Unk0833` | 1 | `PortAnalysis.pascal/1:ret` |
| `Unk0834` | 1 | `PortAnalysis.pattern_structs/1:p0` |
| `Unk0835` | 1 | `PortAnalysis.pattern_structs/1:ret` |
| `Unk0836` | 1 | `PortAnalysis.short/1:p0` |
| `Unk0837` | 1 | `PortAnalysis.src_of/2:p1` |
| `Unk0838` | 1 | `PortAnalysis.sums_section/2:p1` |
| `Unk0839` | 1 | `PortAnalysis.to_markdown/2:p1` |
| `Unk0840` | 1 | `PortAnalysis.to_markdown/2:ret` |
| `Unk0841` | 1 | `PortSpec.load/1:p0` |
| `Unk0842` | 2 | `PortSpec.load/1:ret`, `PortSpec.parse/1:ret` |
| `Unk0843` | 1 | `PortSpec.placeholders/1:p0` |
| `Unk0844` | 1 | `PortSpec.template/2:p0` |
| `Unk0845` | 1 | `PortSpec.template/2:p1` |
| `Unk0846` | 3 | `Pratt.after_paren/2:p0`, `Pratt.after_paren/2:ret`, `Pratt.lambda_ahead?/1:p0` |
| `Unk0847` | 1 | `Pratt.assoc/1:ret` |
| `Unk0848` | 4 | `Pratt.climb/3:p0`, `Pratt.climb/3:ret`, `Pratt.parse_expr/2:ret`, `Pratt.same_level_root?/2:p0` |
| `Unk0849` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0850` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0851` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0852` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0853` | 3 | `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0854` | 3 | `Pratt.finish_arg/2:p0`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:ret` |
| `Unk0855` | 2 | `Pratt.here/1:p0`, `Pratt.tok_desc/1:p0` |
| `Unk0856` | 1 | `Pratt.int_of/1:p0` |
| `Unk0857` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0858` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0859` | 1 | `Pratt.level/1:ret` |
| `Unk0860` | 1 | `Pratt.opinfo/1:ret` |
| `Unk0861` | 2 | `Pratt.parse_arms/2:p1`, `Pratt.parse_arms/2:ret` |
| `Unk0862` | 13 | `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0863` | 1 | `Pratt.parse_list/2:p1` |
| `Unk0864` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0865` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0866` | 1 | `Pratt.parse_params/1:ret` |
| `Unk0867` | 4 | `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:ret` |
| `Unk0868` | 2 | `Pratt.parse_pat_args/2:p1`, `Pratt.parse_pat_args/2:ret` |
| `Unk0869` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0870` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0871` | 1 | `Pratt.parse_pat_list/2:p1` |
| `Unk0872` | 3 | `Pratt.parse_pats/1:ret`, `Pratt.parse_pats/2:p1`, `Pratt.parse_pats/2:ret` |
| `Unk0873` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0874` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0875` | 2 | `Pratt.parse_stmts/2:p1`, `Pratt.parse_stmts/2:ret` |
| `Unk0876` | 2 | `Pratt.parse_type_args/2:p1`, `Pratt.parse_type_args/2:ret` |
| `Unk0877` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0878` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0879` | 1 | `Pratt.pascal?/1:p0` |
| `Unk0880` | 1 | `Pratt.sexpr_pat/1:p0` |
| `Unk0881` | 1 | `Pratt.sexpr_stmt/1:p0` |
| `Unk0882` | 1 | `Pratt.str_interp/1:p0` |
| `Unk0883` | 1 | `Protocol.check_assoc!/2:ret` |
| `Unk0884` | 1 | `Protocol.check_impl/3:p0` |
| `Unk0885` | 3 | `Protocol.check_impl/3:p1`, `Protocol.expand/5:p0`, `Protocol.impl_methods/2:p1` |
| `Unk0886` | 5 | `Protocol.check_impl/3:p2`, `Protocol.check_no_overlap/3:p1`, `Protocol.dispatcher/4:p3`, `Protocol.guard_for!/3:p2`, `Protocol.registry/2:ret` |
| `Unk0887` | 1 | `Protocol.check_impl/3:ret` |
| `Unk0888` | 4 | `Protocol.check_no_overlap/3:p0`, `Protocol.dispatcher/4:p2`, `Protocol.expand/5:p1`, `Protocol.impl_methods/2:p0` |
| `Unk0889` | 2 | `Protocol.check_no_overlap/3:p2`, `Protocol.runtime_dispatch_target?/1:p0` |
| `Unk0890` | 1 | `Protocol.check_no_overlap/3:ret` |
| `Unk0891` | 2 | `Protocol.dispatcher/4:p0`, `Protocol.guard_for!/3:p1` |
| `Unk0892` | 1 | `Protocol.dispatcher/4:p1` |
| `Unk0893` | 1 | `Protocol.dispatcher/4:ret` |
| `Unk0894` | 1 | `Protocol.dispatcher_params/2:p0` |
| `Unk0895` | 1 | `Protocol.dispatcher_params/2:ret` |
| `Unk0896` | 1 | `Protocol.guard_for!/3:ret` |
| `Unk0897` | 1 | `Protocol.mangle/3:p0` |
| `Unk0898` | 1 | `Protocol.mangle/3:p1` |
| `Unk0899` | 1 | `Protocol.mangle/3:p2` |
| `Unk0900` | 1 | `Protocol.param_type/1:p0` |
| `Unk0901` | 1 | `Protocol.param_type/1:ret` |
| `Unk0902` | 1 | `Protocol.registry/2:p0` |
| `Unk0903` | 1 | `Protocol.registry/2:p1` |
| `Unk0904` | 1 | `Protocol.subst_self/2:p0` |
| `Unk0905` | 1 | `Protocol.subst_self/2:p1` |
| `Unk0906` | 1 | `Protocol.subst_self/2:ret` |
| `Unk0907` | 1 | `Protocol.sum_guard/1:p0` |
| `Unk0908` | 1 | `Protocol.tag_disjunction/2:p0` |
| `Unk0909` | 1 | `Protocol.tag_disjunction/2:p1` |
| `Unk0910` | 1 | `Range.check/3:p0` |
| `Unk0911` | 1 | `Range.check/3:p1` |
| `Unk0912` | 1 | `Range.lit/1:p0` |
| `Unk0913` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0914` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0915` | 4 | `Reach.all_emittable?/2:p1`, `Reach.parametric_ctx/2:ret`, `Reach.parametric_rs_ok?/2:p1`, `Reach.scan_func/3:p2` |
| `Unk0916` | 1 | `Reach.analyze/1:ret` |
| `Unk0917` | 15 | `Reach.atom_prim_blocker/0:ret`, `Reach.bare_atom_blocker/0:ret`, `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.ffi/2:ret`, `Reach.fn_type_blocker/0:ret`, `Reach.int_blocker/0:ret`, `Reach.parametric_blocker/0:ret`, `Reach.ref_blocker/0:ret`, `Reach.result_value_blocker/0:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret`, `Reach.wide_prim_blocker/0:ret`, `Reach.width_blocker/0:ret` |
| `Unk0918` | 5 | `Reach.build_default/0:ret`, `Reach.check_contracts/2:p1`, `Reach.gate!/2:p1`, `Reach.validate_default/1:p0`, `Reach.validate_default/1:ret` |
| `Unk0919` | 2 | `Reach.builder_tail_ok?/2:p1`, `Reach.tail_calls_generic?/2:p1` |
| `Unk0920` | 1 | `Reach.check_contracts/2:ret` |
| `Unk0921` | 3 | `Reach.classify/3:p1`, `Reach.scan/3:p1`, `Reach.scan_func/3:p1` |
| `Unk0922` | 5 | `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret` |
| `Unk0923` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0924` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0925` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0926` | 1 | `Reach.conc_erl?/2:p1` |
| `Unk0927` | 1 | `Reach.contract_message/1:p0` |
| `Unk0928` | 1 | `Reach.core/2:p0` |
| `Unk0929` | 1 | `Reach.core/2:p1` |
| `Unk0930` | 1 | `Reach.core/2:p1` |
| `Unk0931` | 3 | `Reach.deep/1:ret`, `Reach.find_atom_ordering/1:ret`, `Reach.func_symbol_violations/1:ret` |
| `Unk0932` | 1 | `Reach.emittable_parametric?/1:p0` |
| `Unk0933` | 1 | `Reach.emittable_parametric?/1:ret` |
| `Unk0934` | 1 | `Reach.fixpoint/2:p0` |
| `Unk0935` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0936` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0937` | 1 | `Reach.func_symbol_violations/1:p0` |
| `Unk0938` | 1 | `Reach.js_wide_int?/1:p0` |
| `Unk0939` | 1 | `Reach.mix_default/0:ret` |
| `Unk0940` | 1 | `Reach.parametric_type?/1:p0` |
| `Unk0941` | 1 | `Reach.pascal?/1:p0` |
| `Unk0942` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0943` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0944` | 1 | `Reach.sig_idents/1:ret` |
| `Unk0945` | 1 | `Reach.tail_calls_generic?/2:p0` |
| `Unk0946` | 1 | `Reach.tvar?/1:p0` |
| `Unk0947` | 1 | `Reach.tvar?/1:ret` |
| `Unk0948` | 2 | `Reach.type_has_tvar?/1:p0`, `Reach.type_idents/1:p0` |
| `Unk0949` | 1 | `Reach.type_idents/1:ret` |
| `Unk0950` | 1 | `Reach.uses_parametric?/2:p1` |
| `Unk0951` | 1 | `Repl.accumulate_line/2:p1` |
| `Unk0952` | 1 | `Repl.bind_env/2:p0` |
| `Unk0953` | 18 | `Repl.bind_with_type/4:p0`, `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:p0`, `Repl.eval_bind/4:ret`, `Repl.eval_decl/2:p0`, `Repl.eval_expr/2:p0`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:p0`, `Repl.eval_stmt/2:ret`, `Repl.program/3:p0`, `Repl.program/3:p1`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.run/4:p1`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.session_ic/1:p0`, `Repl.units_src/1:p0` |
| `Unk0954` | 12 | `Repl.bind_with_type/4:p0`, `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:p0`, `Repl.eval_bind/4:ret`, `Repl.eval_decl/2:p0`, `Repl.eval_expr/2:p0`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:p0`, `Repl.eval_stmt/2:ret`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.session_ic/1:p0` |
| `Unk0955` | 4 | `Repl.bind_with_type/4:p3`, `Repl.safe_infer/3:ret`, `Repl.safe_infer_input/3:ret`, `Repl.type_of/2:ret` |
| `Unk0956` | 4 | `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:ret`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:ret` |
| `Unk0957` | 1 | `Repl.candidate_pool/2:p0` |
| `Unk0958` | 1 | `Repl.candidate_pool/2:ret` |
| `Unk0959` | 2 | `Repl.common_prefix/2:p0`, `Repl.common_prefix/3:p0` |
| `Unk0960` | 2 | `Repl.common_prefix/2:p1`, `Repl.common_prefix/3:p1` |
| `Unk0961` | 2 | `Repl.complete/2:ret`, `Repl.continuation/2:p1` |
| `Unk0962` | 1 | `Repl.describe/1:ret` |
| `Unk0963` | 1 | `Repl.eval/2:ret` |
| `Unk0964` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0965` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0966` | 1 | `Repl.flush_entries/1:p0` |
| `Unk0967` | 1 | `Repl.flush_entries/1:ret` |
| `Unk0968` | 1 | `Repl.info/1:ret` |
| `Unk0969` | 2 | `Repl.longest_common_prefix/1:p0`, `Repl.longest_common_prefix/1:ret` |
| `Unk0970` | 1 | `Repl.render/1:p0` |
| `Unk0971` | 1 | `Repl.run/4:ret` |
| `Unk0972` | 1 | `Repl.run/4:ret` |
| `Unk0973` | 1 | `Repl.safe_parse_body/1:ret` |
| `Unk0974` | 1 | `Repl.scan_count/2:p1` |
| `Unk0975` | 1 | `Repl.scan_count/2:ret` |
| `Unk0976` | 1 | `SelfHost.badge/1:p0` |
| `Unk0977` | 1 | `SelfHost.composition/0:ret` |
| `Unk0978` | 1 | `SelfHost.evidence/1:p0` |
| `Unk0979` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0980` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0981` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0982` | 1 | `SelfHost.external_host_calls/1:ret` |
| `Unk0983` | 1 | `SelfHost.ffi_ledger/0:ret` |
| `Unk0984` | 1 | `SelfHost.passes/0:ret` |
| `Unk0985` | 1 | `SelfHost.sibling_compose_call?/2:p0` |
| `Unk0986` | 1 | `SelfHost.sibling_compose_call?/2:p1` |
| `Unk0987` | 1 | `SelfHost.stages/0:ret` |
| `Unk0988` | 1 | `SelfHost.status_markdown/1:p0` |
| `Unk0989` | 1 | `Shadow.ded_bind/5:p0` |
| `Unk0990` | 3 | `Shadow.ded_bind/5:p2`, `Shadow.ded_expr/3:p0`, `Shadow.ded_expr/3:ret` |
| `Unk0991` | 1 | `Shadow.ded_bind/5:p3` |
| `Unk0992` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk0993` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk0994` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk0995` | 1 | `Shadow.ded_bind/5:ret` |
| `Unk0996` | 2 | `Shadow.ded_block/4:p0`, `Shadow.dedup/3:p0` |
| `Unk0997` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk0998` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk0999` | 1 | `Shadow.ded_block/4:p2` |
| `Unk1000` | 1 | `Shadow.pat_var_names/1:ret` |
| `Unk1001` | 1 | `Test.run/2:p1` |
| `Unk1002` | 1 | `Test.run/2:ret` |
| `Unk1003` | 1 | `Tour.build_cell/1:p0` |
| `Unk1004` | 1 | `Tour.build_cell/1:ret` |
| `Unk1005` | 1 | `Tour.build_reach_example/1:p0` |
| `Unk1006` | 1 | `Tour.build_reach_example/1:ret` |
| `Unk1007` | 1 | `Tour.elixir_module/1:ret` |
| `Unk1008` | 2 | `Tour.encode/2:p0`, `Tour.encode_string/1:p0` |
| `Unk1009` | 1 | `Tour.generate/0:ret` |
| `Unk1010` | 1 | `Tour.reach_map/1:ret` |
| `Unk1011` | 5 | `Transpile.add_clause/2:p0`, `Transpile.add_clause/2:p1`, `Transpile.build_clause/2:ret`, `Transpile.new_group/3:p1`, `Transpile.same_group?/3:p2` |
| `Unk1012` | 1 | `Transpile.add_clause/2:p0` |
| `Unk1013` | 2 | `Transpile.add_clause/2:ret`, `Transpile.new_group/3:ret` |
| `Unk1014` | 1 | `Transpile.build_clause/2:p0` |
| `Unk1015` | 1 | `Transpile.build_clause/2:p1` |
| `Unk1016` | 1 | `Transpile.case_arm/1:p0` |
| `Unk1017` | 1 | `Transpile.classify/1:ret` |
| `Unk1018` | 4 | `Transpile.close_group/2:p0`, `Transpile.close_group/2:p1`, `Transpile.close_group/2:ret`, `Transpile.def_groups/1:ret` |
| `Unk1019` | 1 | `Transpile.escape/1:p0` |
| `Unk1020` | 1 | `Transpile.escape/1:ret` |
| `Unk1021` | 2 | `Transpile.escape_lit/1:p0`, `Transpile.string_part/1:p0` |
| `Unk1022` | 1 | `Transpile.flush/2:p0` |
| `Unk1023` | 3 | `Transpile.flush/2:p1`, `Transpile.render_items/3:p1`, `Transpile.render_submodule/3:p2` |
| `Unk1024` | 3 | `Transpile.flush/2:p1`, `Transpile.render_items/3:p1`, `Transpile.render_submodule/3:p2` |
| `Unk1025` | 1 | `Transpile.hole_sig?/1:p0` |
| `Unk1026` | 1 | `Transpile.infer_program/1:p0` |
| `Unk1027` | 3 | `Transpile.infer_program/1:ret`, `Transpile.infer_sigs/2:ret`, `Transpile.inferred/1:ret` |
| `Unk1028` | 1 | `Transpile.infer_report/1:ret` |
| `Unk1029` | 1 | `Transpile.infer_sigs/2:p0` |
| `Unk1030` | 1 | `Transpile.max_placeholder/1:p0` |
| `Unk1031` | 4 | `Transpile.mod_str/1:p0`, `Transpile.short_name/1:p0`, `Transpile.snippet/1:p0`, `Transpile.var_name/1:p0` |
| `Unk1032` | 1 | `Transpile.module_groups/1:p0` |
| `Unk1033` | 1 | `Transpile.module_groups/1:ret` |
| `Unk1034` | 1 | `Transpile.moduledoc_lines/1:p0` |
| `Unk1035` | 1 | `Transpile.name_str/1:p0` |
| `Unk1036` | 1 | `Transpile.name_str/1:ret` |
| `Unk1037` | 1 | `Transpile.new_group/3:p0` |
| `Unk1038` | 1 | `Transpile.new_group/3:p2` |
| `Unk1039` | 1 | `Transpile.one_line/1:p0` |
| `Unk1040` | 1 | `Transpile.one_line/1:ret` |
| `Unk1041` | 1 | `Transpile.prime_xmod/1:p0` |
| `Unk1042` | 1 | `Transpile.prime_xmod/1:ret` |
| `Unk1043` | 1 | `Transpile.rank/1:p0` |
| `Unk1044` | 1 | `Transpile.rank/1:ret` |
| `Unk1045` | 1 | `Transpile.render_body/1:ret` |
| `Unk1046` | 1 | `Transpile.render_clause/2:p1` |
| `Unk1047` | 3 | `Transpile.render_items/3:p2`, `Transpile.render_submodule/3:p0`, `Transpile.struct_decl/2:p0` |
| `Unk1048` | 1 | `Transpile.same_group?/3:p0` |
| `Unk1049` | 1 | `Transpile.same_group?/3:p1` |
| `Unk1050` | 1 | `Transpile.sibling_module?/2:p0` |
| `Unk1051` | 1 | `Transpile.simple?/1:p0` |
| `Unk1052` | 1 | `Transpile.string_part/1:ret` |
| `Unk1053` | 1 | `Transpile.string_parts/1:p0` |
| `Unk1054` | 1 | `Transpile.string_parts/1:ret` |
| `Unk1055` | 1 | `Transpile.struct_decl/2:p1` |
| `Unk1056` | 1 | `Transpile.struct_field?/1:p0` |
| `Unk1057` | 1 | `Transpile.struct_mod_noise?/1:p0` |
| `Unk1058` | 2 | `Transpile.subst_ph/2:p0`, `Transpile.subst_ph/2:ret` |
| `Unk1059` | 1 | `Transpile.subst_ph/2:p1` |
| `Unk1060` | 1 | `Transpile.toplevel/3:p0` |
| `Unk1061` | 1 | `Transpile.toplevel/3:p1` |
| `Unk1062` | 1 | `Transpile.transpile/2:p1` |
| `Unk1063` | 2 | `Transpile.transpile/2:ret`, `Transpile.transpile_with_stats/2:ret` |
| `Unk1064` | 1 | `Transpile.transpile_with_stats/2:p1` |
| `Unk1065` | 1 | `Transpile.transpile_with_stats/2:ret` |
| `Unk1066` | 1 | `Transpile.underscore_var/1:p0` |
| `Unk1067` | 1 | `Transpile.var?/1:p0` |

## 3. Proposed sum-type groupings — REVIEW (heuristic from dispatch co-occurrence)

Structs clustered by co-occurrence in multi-clause heads + `case` arms. This is
the non-local decision a human cannot make from a single draft file. Confirm or
split each cluster; ambiguous structs (bridging two clusters) are merged here and
may need splitting.

**Cluster 1** (`Sum1`, co-occur in dispatch) — propose `type <NAME?> := EAtom | EBin | EBlock | ECall | ECapArg | ECapture | ECaptureNamed | ECase | EChar | EConstRef | EDot | EId | EIf | ELambda | EList | EMap | ENum | EStr | EStruct | ETuple | EUnary | EVariant | EWith`
  - `EAtom` { name }
  - `EBin` { left, op, right }
  - `EBlock` { stmts }
  - `ECall` { args, fun }
  - `ECapArg` { n }
  - `ECapture` { body }
  - `ECaptureNamed` { arity, path }
  - `ECase` { arms, scrut }
  - `EChar` { value }
  - `EConstRef` { name }
  - `EDot` { head, name }
  - `EId` { name }
  - `EIf` { cond, else, then }
  - `ELambda` { body, params }
  - `EList` { elems, tail }
  - `EMap` { pairs }
  - `ENum` { text }
  - `EStr` { value }
  - `EStruct` { name, pairs }
  - `ETuple` { elems }
  - `EUnary` { arg, op }
  - `EVariant` { ctor, enum, named, pairs }
  - `EWith` { body, clauses, els }
  - [ ] human: name the sum (`Sum1 = <Name>` in port.spec), confirm membership

**Cluster 2** (`Sum2`, co-occur in dispatch) — propose `type <NAME?> := PAs | PAtom | PChar | PCtor | PList | PLit | PMap | PPin | PStruct | PTuple | PVar | PWild`
  - `PAs` { name, pat }
  - `PAtom` { name }
  - `PChar` { value }
  - `PCtor` { args, ctor }
  - `PList` { elems, tail }
  - `PLit` { value }
  - `PMap` { pairs }
  - `PPin` { expr }
  - `PStruct` { fields, name }
  - `PTuple` { elems }
  - `PVar` { name }
  - `PWild` {  }
  - [ ] human: name the sum (`Sum2 = <Name>` in port.spec), confirm membership

**Standalone structs** (never dispatched): `Clause`, `Const`, `ELabel`, `Field`, `Func`, `Mod`, `Opaque`, `Param`, `Range`, `Session`, `Struct`, `Type`, `Use`, `Variant`

## 4. Error idioms — REVIEW (Elixir `{:error, _}` → Rian sum variant)

A Rian `Result` (`T | E`) needs a Capitalized sum variant; Elixir uses atoms/
strings/structs. Each distinct shape needs a human decision (atoms have a
proposed PascalCase variant; strings/structs/vars need a named variant).

| `{:error, X}` shape | count | proposed Rian variant | reach |
|---|---|---|---|
| `message` (var/propagation) | 7 | propagated `E` (no fixed tag) | — |
| `msg` (var/propagation) | 6 | propagated `E` (no fixed tag) | — |
| `"…"` (string) | 5 | **NEEDS DECISION** — name a variant | — |
| `Exception.message(e)` (expr) | 4 | **NEEDS DECISION** | — |
| `_` (var/propagation) | 3 | propagated `E` (no fixed tag) | — |
| `String.t()` (expr) | 3 | **NEEDS DECISION** | — |
| `reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `list()` (expr) | 2 | **NEEDS DECISION** | — |
| `_reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `"`<~` is in-place mutation of ` (expr) | 1 | **NEEDS DECISION** | — |
| `"cannot read: #{:file.format_e` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an `@external` par` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{n}`: literal #{v} is out o` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{f}(…)`: labeled arguments ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{f.name}`: returns error(s)` (expr) | 1 | **NEEDS DECISION** | — |
| `"unsupported in comptime: #{in` (expr) | 1 | **NEEDS DECISION** | — |
| `{:__aliases__, _, parts}` (expr) | 1 | **NEEDS DECISION** | — |
| `"operator `#{op}` not allowed ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{g}` requires `#{tvar}: #{p` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an integer literal` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{x}` is not a compile-time ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: range `#{ann}` is ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{op}`: no implicit Int↔Floa` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: body has type `#{b` (expr) | 1 | **NEEDS DECISION** | — |
| `bad` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"`#{name}`: binding declared `` (expr) | 1 | **NEEDS DECISION** | — |
| `x` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `parts |> List.last() |> to_str` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: value of type `#{t` (expr) | 1 | **NEEDS DECISION** | — |
| `contract_message(vs)` (expr) | 1 | **NEEDS DECISION** | — |
| `tag` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"`#{name}`: literal #{v} is ou` (expr) | 1 | **NEEDS DECISION** | — |
| `{:already_started, pid}` (expr) | 1 | **NEEDS DECISION** | — |

