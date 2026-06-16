# Port Analysis — Elixir → Rian

**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the
`REVIEW` sections and record decisions in a `port.spec` (feedback loop not yet
wired). Regenerate to diff against source — do not hand-edit this file.

## Summary

- modules: 45 · type slots: 3041 · auto-filled: 709 (23%) · holes: 2332
- structs seen: 49 · proposed sums: 2 · distinct error idioms: 33

## 1. Inferred signatures — AUTO (high confidence, type-check-validated)

| function | signature | return reach |
|---|---|---|
| `beam_func/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `core_list_tail/1` | `(T) T forall T` | ✓ all 4 |
| `load_program/1` | `(String) Vec(Symbol)` | ✓ all 4 |
| `union_t/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `beam_legal!/1` | `(Symbol) Symbol` | ✓ all 4 |
| `borrowed/1` | `(String) String` | ✓ all 4 |
| `copy?/1` | `(String) Bool` | ✓ all 4 |
| `owned/1` | `(String) String` | ✓ all 4 |
| `rust_name/1` | `(String) String` | ✓ all 4 |
| `rust_param/2` | `(Symbol, String) String` | ✓ all 4 |
| `rust_scalar/1` | `(String) String` | ✓ all 4 |
| `concretize/1` | `(T) T forall T` | ✓ all 4 |
| `conservative/1` | `(T) T forall T` | ✓ all 4 |
| `debottom/1` | `(T) T forall T` | ✓ all 4 |
| `deplaceholder/1` | `(String) String` | ✓ all 4 |
| `float_mantissa/1` | `(Int53) Int53` | ✓ all 4 |
| `int_float_join/2` | `(Int53, Int53) String` | ✓ all 4 |
| `join/2` | `(T, T) T forall T` | ✓ all 4 |
| `ordinal_base/1` | `(String) String` | ✓ all 4 |
| `unify/2` | `(T, T) T forall T` | ✓ all 4 |
| `wildcard?/1` | `(String) Bool` | ✓ all 4 |
| `dispatch/1` | `(Vec(String)) Int53` | ✓ all 4 |
| `usage/1` | `(T) T forall T` | ✓ all 4 |
| `truthy!/1` | `(T) T forall T` | ✓ all 4 |
| `block_seps/5` | `(Vec(T), Int53, Int53, Int53, Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `inject_stdlib/1` | `(T) T forall T` | ✓ all 4 |
| `skip_nl/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
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
| `concat_chain/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `compile/1` | `(String) String` | ✓ all 4 |
| `cp_expr/2` | `(String, Bool) String` | ✓ all 4 |
| `int_typeof/1` | `(Bool) String` | ✓ all 4 |
| `js_fresh/2` | `(String, Int53) String` | ✓ all 4 |
| `js_op/1` | `(String) String` | ✓ all 4 |
| `js_str_cp/1` | `(Int53) String` | ✓ all 4 |
| `compile/1` | `(String) String` | ✓ all 4 |
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
| `coerce_ret/2` | `(String, String) String` | ✓ all 4 |
| `flatten_concat/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `head_word?/1` | `(Vec(Int53)) Bool` | ✓ all 4 |
| `join_doc/2` | `(String, String) String` | ✓ all 4 |
| `owned_rtype?/1` | `(String) Bool` | ✓ all 4 |
| `owned_value_type?/1` | `(String) Bool` | ✓ all 4 |
| `prim_ex/1` | `(String) String` | ✓ all 4 |
| `rust_char_lit/1` | `(Int53) String` | ✓ all 4 |
| `str_lit_cp/1` | `(Int53) String` | ✓ all 4 |
| `tail_expr/1` | `(T) T forall T` | ✓ all 4 |
| `word_char?/1` | `(Int53) Bool` | ✓ all 4 |
| `flush/2` | `(T, Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `leading_spaces/1` | `(String) Int53` | ✓ all 4 |
| `to_snake/1` | `(Symbol | String) Symbol | String` | ✓ all 4 |
| `after_paren/2` | `(Vec(T), Int53) Vec(T) forall T` | ✓ all 4 |
| `expect_rbracket/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `expect_rparen/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `parse_body/1` | `(T) T forall T` | ✓ all 4 |
| `parse_sexpr/1` | `(String) String` | ✓ all 4 |
| `with_prelude/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `names/0` | `() Vec(String)` | ✓ all 4 |
| `normalize/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `overflow_ops/0` | `() Vec(String)` | ✓ all 4 |
| `targets/0` | `() Vec(Symbol)` | ✓ all 4 |
| `validate_default/1` | `(Option(T)) Option(T) forall T` | ✓ all 4 |
| `longest_common_prefix/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `split_entries/1` | `(String) Vec(String)` | ✓ all 4 |
| `vocabulary/0` | `() Vec(String)` | ✓ all 4 |
| `add/1` | `(String) Symbol` | ✓ all 4 |
| `dedup_consecutive/1` | `(Vec(Vec(Vec(T)))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `path/0` | `() String` | ✓ all 4 |
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
  pub def body_seq(p0 Option(Unk0017), s Map(String, Unk0016)) Vec(Tuple(Option(Unk0013), Unk0014)) := …

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

  # Beam.pascal?/1
  pub def pascal?(s Unk0046) Bool := …

  # Beam.pat_form/1
  pub def pat_form(p0 Sum2) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.pat_vars/2
  pub def pat_vars(p0 Sum2, acc Map(String, Unk0016)) Map(String, Unk0016) := …

  # Beam.ranges_of/1
  pub def ranges_of(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Beam.remote_call/4
  pub def remote_call(mod Unk0047, fun String, args Vec(Option(Unk0017)), scope Map(String, Unk0016)) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.spec_form/2
  pub def spec_form(p0 Unk0006, tctx Unk0028) Unk0034 := …

  # Beam.stmt_form/2
  pub def stmt_form(p0 Unk0048, s Map(String, Unk0016)) Tuple(Tuple(Option(Unk0013), Unk0014), Map(String, Unk0016)) := …

  # Beam.str_form/1
  pub def str_form(s Unk0049) Tuple(Option(Unk0013), Unk0014) := …

  # Beam.struct_form/2
  pub def struct_form(p0 Map(Unk0009, Vec(Unk0010)), tctx Unk0028) Unk0005 := …

  # Beam.structs_of/1
  pub def structs_of(p0 Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Beam.sum_form/2
  pub def sum_form(variants Unk0050, tctx Unk0028) Unk0051 := …

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
  pub def with_form(p0 Vec(Unk0052), body Option(Unk0017), _els Vec(Unk0026), s Map(String, Unk0016), _d Int53) Tuple(Option(Unk0013), Unk0014) := …

  # CLI.check/1
  pub def check(files Vec(Unk0053)) Int53 := …

  # CLI.diff/1
  pub def diff(files Vec(Unk0053)) Unk0054 := …

  # CLI.each/2
  pub def each(files Unk0055, fun Fn(Unk0056, Unk0057)) Unk0058 := …

  # CLI.in_place/1
  pub def in_place(file Unk0053) Unk0059 := …

  # CLI.main/1
  pub def main(argv Vec(String)) Unk0060 := …

  # CLI.print_diff/3
  pub def print_diff(file Unk0053, src Unk0061, out Unk0062) Vec(Unk0063) := …

  # CLI.read/1
  pub def read(file Unk0053) Tuple(Unk0064, String) := …

  # CLI.to_stdout/1
  pub def to_stdout(file Unk0053) Unk0065 := …

  # CLI.unified_diff/3
  pub def unified_diff(file Unk0053, old Unk0061, new Unk0062) String := …

  # Capability.count_block/3
  pub def count_block(p0 Vec(Unk0066), _bound Unk0067, acc Unk0068) Unk0068 := …

  # Capability.count_uses/1
  pub def count_uses(ast Unk0069) Unk0068 := …

  # Capability.count_uses/2
  pub def count_uses(p0 Unk0069, bound Unk0067) Unk0068 := …

  # Capability.lin_check/2
  pub def lin_check(env Map(Unk0071, Unk0070), ast Unk0069) Tuple(Unk0072, Vec(Unk0073)) := …

  # Capability.lin_check_block/3
  pub def lin_check_block(env Map(Unk0074, Unk0075), bindings Vec(Unk0076), final Unk0069) Tuple(Unk0072, Vec(Unk0073)) := …

  # Capability.max_merge/2
  pub def max_merge(a Unk0068, b Unk0068) Unk0068 := …

  # Capability.merge/2
  pub def merge(a Unk0068, b Unk0068) Unk0068 := …

  # Capability.pat_vars/1
  pub def pat_vars(p0 Unk0077) Unk0078 := …

  # Capability.verdict/2
  pub def verdict(env Map(Unk0071, Unk0070), uses Unk0068) Tuple(Unk0072, Vec(Unk0073)) := …

  # Check.abstract_cast_ret/3
  pub def abstract_cast_ret(ht Vec(Unk0079), cn Unk0080, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0082) := …

  # Check.abstract_op_type/4
  pub def abstract_op_type(op Unk0083, lt Vec(Unk0079), rt Vec(Unk0079), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0084 := …

  # Check.adoptable_int?/1
  pub def adoptable_int?(t Vec(Unk0079)) Bool := …

  # Check.all_types/1
  pub def all_types(prog Map(Unk0085, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Type) := …

  # Check.ann_each/3
  pub def ann_each(nodes Vec(Option(Unk0017)), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.ann_stmts/3
  pub def ann_stmts(p0 Vec(Unk0087), _env Map(Unk0086, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.annotate/3
  pub def annotate(ast Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.arith_type/4
  pub def arith_type(l Sum1, r Sum1, lt Vec(Unk0079), rt Vec(Unk0079)) Unk0088 := …

  # Check.assignable?/2
  pub def assignable?(t Vec(Unk0079), t Vec(Unk0079)) Bool := …

  # Check.bind_mismatch/5
  pub def bind_mismatch(name Unk0089, ann Vec(Unk0079), e Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0090) := …

  # Check.bind_tvar/4
  pub def bind_tvar(_p Unk0091, p1 Unk0091, _tvars Unk0092, acc Map(Unk0093, Vec(Unk0079))) Map(Unk0093, Vec(Unk0079)) := …

  # Check.body_literal_adopts?/2
  pub def body_literal_adopts?(p0 Option(Unk0017), ret Vec(Unk0079)) Bool := …

  # Check.branch_join/1
  pub def branch_join(typed Vec(Tuple(Unk0094, Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.build_fn/2
  pub def build_fn(args Vec(Unk0095), ret Vec(Unk0079)) String := …

  # Check.call_bound_error/5
  pub def call_bound_error(g Vec(Unk0079), args Vec(Option(Unk0017)), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0096) := …

  # Check.call_name/1
  pub def call_name(p0 Unk0097) Vec(Unk0098) := …

  # Check.called_ret/2
  pub def called_ret(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), f Vec(Unk0079)) Vec(Unk0079) := …

  # Check.called_ret_with/4
  pub def called_ret_with(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), f Vec(Unk0079), args_ast Vec(Option(Unk0017)), env Map(Unk0086, Vec(Unk0079))) Vec(Unk0079) := …

  # Check.check/1
  pub def check(src String) Unk0099 := …

  # Check.check_bind_stmts/3
  pub def check_bind_stmts(p0 Vec(Unk0100), _env Map(Unk0086, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0090) := …

  # Check.check_binds/2
  pub def check_binds(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0101 := …

  # Check.check_bounds/2
  pub def check_bounds(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0102 := …

  # Check.check_error_set/2
  pub def check_error_set(p0 Unk0103, p1 Unk0104) Tuple(Unk0105, String) := …

  # Check.check_external_caps/1
  pub def check_external_caps(p0 Func) Tuple(Unk0106, String) := …

  # Check.check_func/3
  pub def check_func(p0 Unk0107, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), eset Unk0104) Unk0108 := …

  # Check.check_labels/1
  pub def check_labels(p0 Func) Unk0109 := …

  # Check.check_numeric_mix/2
  pub def check_numeric_mix(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0110 := …

  # Check.check_program/1
  pub def check_program(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0111 := …

  # Check.check_return/2
  pub def check_return(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0112 := …

  # Check.clause_env/3
  pub def clause_env(pats Unk0113, params Unk0114, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Map(Unk0086, Vec(Unk0079)) := …

  # Check.comp_str/1
  pub def comp_str(p0 Unk0115) String := …

  # Check.concrete_type?/1
  pub def concrete_type?(p0 Vec(Unk0079)) Bool := …

  # Check.concretize/1
  pub def concretize(t String) Vec(Unk0079) := …

  # Check.conservative/1
  pub def conservative(p0 Vec(Unk0079)) Vec(Unk0079) := …

  # Check.const_int/1
  pub def const_int(p0 Option(Unk0017)) Tuple(Unk0116, Unk0117) := …

  # Check.ctor_type/2
  pub def ctor_type(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), name Vec(Unk0079)) Vec(Unk0079) := …

  # Check.ctor_types/2
  pub def ctor_types(types Vec(Type), prog Map(Unk0118, Vec(Unk0119))) Map(Unk0120, Unk0121) := …

  # Check.debottom/1
  pub def debottom(p0 Unk0122) Unk0122 := …

  # Check.declared_set/2
  pub def declared_set(ret Unk0123, tsets Map(Unk0124, Vec(Unk0124))) Tuple(Unk0124, Unk0125) := …

  # Check.deplaceholder/1
  pub def deplaceholder(p0 String) Vec(Unk0079) := …

  # Check.direct_tags/1
  pub def direct_tags(f Unk0126) Unk0127 := …

  # Check.error_sets/1
  pub def error_sets(types Vec(Type)) Map(Unk0124, Vec(Unk0124)) := …

  # Check.error_tags/1
  pub def error_tags(p0 Vec(Unk0128)) Vec(Option(Unk0129)) := …

  # Check.fbound_table/1
  pub def fbound_table(funcs Vec(Unk0130)) Unk0131 := …

  # Check.first_bound_violation/4
  pub def first_bound_violation(g Vec(Unk0079), bounds Unk0132, subs Map(Unk0093, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0096) := …

  # Check.fixpoint/2
  pub def fixpoint(facts Unk0133, table Map(Unk0134, Unk0135)) Map(Unk0134, Unk0135) := …

  # Check.float_type?/1
  pub def float_type?(t Vec(Unk0079)) Bool := …

  # Check.fn_parts/1
  pub def fn_parts(p0 String) Unk0136 := …

  # Check.fn_ret/1
  pub def fn_ret(ft Vec(Unk0079)) Option(Unk0082) := …

  # Check.fn_type?/1
  pub def fn_type?(p0 Vec(Unk0079)) Bool := …

  # Check.fsig/1
  pub def fsig(f Unk0137) Unk0138 := …

  # Check.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Check.generic_ret?/2
  pub def generic_ret?(_ret Unk0139, p1 Vec(Unk0140)) Bool := …

  # Check.has_tvar?/1
  pub def has_tvar?(s Vec(Unk0079)) Bool := …

  # Check.impl_table/1
  pub def impl_table(prog Map(Unk0141, Vec(Unk0142))) Unk0143 := …

  # Check.infer/3
  pub def infer(ast Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.infer_block/4
  pub def infer_block(p0 Vec(Unk0144), _env Map(Unk0086, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), value Vec(Unk0079)) Vec(Unk0079) := …

  # Check.infer_tail/3
  pub def infer_tail(p0 Option(Unk0017), _env Map(Unk0086, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.inner_of/1
  pub def inner_of(p0 Unk0091) Unk0091 := …

  # Check.instantiate_ret/2
  pub def instantiate_ret(p0 Unk0145, arg_types Vec(Vec(Unk0079))) Vec(Unk0079) := …

  # Check.int_float_join/2
  pub def int_float_join(exact_bits Int53, fb Int53) Option(Unk0146) := …

  # Check.int_lit_expr?/1
  pub def int_lit_expr?(p0 Sum1) Bool := …

  # Check.int_literal?/1
  pub def int_literal?(n Unk0147) Bool := …

  # Check.int_type?/1
  pub def int_type?(t Vec(Unk0079)) Bool := …

  # Check.join/2
  pub def join(t Vec(Unk0079), t Vec(Unk0079)) Option(Unk0146) := …

  # Check.join_all/1
  pub def join_all(types Vec(Unk0148)) Vec(Unk0079) := …

  # Check.kind_prefix/1
  pub def kind_prefix(p0 Unk0149) String := …

  # Check.label_error/1
  pub def label_error(p0 Option(Unk0017)) Tuple(Unk0150, String) := …

  # Check.label_error_children/1
  pub def label_error_children(node Option(Unk0017)) Tuple(Unk0150, String) := …

  # Check.list_elem/1
  pub def list_elem(p0 Vec(Unk0079)) Unk0151 := …

  # Check.list_elems/1
  pub def list_elems(p0 Option(Unk0017)) Vec(Unk0152) := …

  # Check.list_of/1
  pub def list_of(p0 Vec(Unk0079)) String := …

  # Check.lit_expr_adopts?/2
  pub def lit_expr_adopts?(p0 Option(Unk0017), ret Vec(Unk0079)) Bool := …

  # Check.lit_range_error/3
  pub def lit_range_error(expr Option(Unk0017), p1 String, name Unk0089) Option(Unk0153) := …

  # Check.literal_adopts?/2
  pub def literal_adopts?(p0 Sum1, ann Vec(Unk0079)) Bool := …

  # Check.literal_ordinal/2
  pub def literal_ordinal(p0 Sum1, p1 String) Tuple(Unk0154, Int53) := …

  # Check.missing_impl/5
  pub def missing_impl(g Vec(Unk0079), tvar Unk0155, ty Vec(Unk0079), protos Unk0156, impls Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0157) := …

  # Check.mixed_num?/2
  pub def mixed_num?(lt Vec(Unk0079), rt Vec(Unk0079)) Bool := …

  # Check.narrow/4
  pub def narrow(p0 Sum2, type Vec(Unk0079), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), env Map(Unk0086, Vec(Unk0079))) Map(Unk0086, Vec(Unk0079)) := …

  # Check.num_bits/2
  pub def num_bits(kind Unk0158, w Unk0159) Option(Unk0160) := …

  # Check.num_join/2
  pub def num_join(p0 Unk0161, p1 Unk0162) Option(Unk0146) := …

  # Check.num_kind/1
  pub def num_kind(p0 Vec(Unk0079)) Option(Unk0160) := …

  # Check.num_lub/2
  pub def num_lub(x Vec(Unk0079), y Vec(Unk0079)) Unk0163 := …

  # Check.num_mix?/2
  pub def num_mix?(p0 Unk0164, k Unk0165) Bool := …

  # Check.num_mix_error/5
  pub def num_mix_error(op Unk0166, l Option(Unk0017), r Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0167 := …

  # Check.num_widens?/2
  pub def num_widens?(p0 Unk0168, p1 Unk0169) Bool := …

  # Check.oor_scan/5
  pub def oor_scan(p0 Option(Unk0017), ty String, lo Unk0170, hi Unk0171, n Unk0089) Tuple(Unk0172, String) := …

  # Check.opaque_table/1
  pub def opaque_table(prog Map(Unk0173, Vec(Unk0174))) Unk0175 := …

  # Check.parametric_join/2
  pub def parametric_join(p0 Vec(Unk0079), _ Vec(Unk0079)) Option(Unk0146) := …

  # Check.parse_parametric/1
  pub def parse_parametric(s Vec(Unk0079)) Tuple(String, Vec(String)) := …

  # Check.pascal?/1
  pub def pascal?(s Unk0176) Bool := …

  # Check.produced_set/2
  pub def produced_set(f Unk0126, table Map(Unk0177, Unk0178)) Unk0179 := …

  # Check.program_ic/1
  pub def program_ic(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))) := …

  # Check.propagated_callees/1
  pub def propagated_callees(f Unk0126) Unk0180 := …

  # Check.range_base/2
  pub def range_base(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), n Vec(Unk0079)) Option(Unk0181) := …

  # Check.range_bind/6
  pub def range_bind(name Unk0089, ann Vec(Unk0079), p2 Unk0182, ce Sum1, env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0183) := …

  # Check.range_table/1
  pub def range_table(prog Map(Unk0184, Vec(Unk0185))) Unk0186 := …

  # Check.resolve_range/2
  pub def resolve_range(t Vec(Unk0079), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.scan_bound_calls/4
  pub def scan_bound_calls(p0 Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0187) := …

  # Check.scan_num_mix/3
  pub def scan_num_mix(p0 Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0188) := …

  # Check.scan_num_mix_children/3
  pub def scan_num_mix_children(node Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0188) := …

  # Check.solve_error_sets/2
  pub def solve_error_sets(funcs Vec(Unk0189), tsets Map(Unk0124, Vec(Unk0124))) Map(Unk0134, Unk0135) := …

  # Check.tag_name/1
  pub def tag_name(p0 Unk0190) Option(Unk0129) := …

  # Check.type_table/1
  pub def type_table(types Vec(Type)) Unk0191 := …

  # Check.uint_signed_join/2
  pub def uint_signed_join(u Unk0192, i Unk0192) String := …

  # Check.unify/2
  pub def unify(t Vec(Unk0079), t Vec(Unk0079)) Vec(Unk0079) := …

  # Check.walk_children/4
  pub def walk_children(node Option(Unk0017), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0187) := …

  # Check.with_callees/1
  pub def with_callees(p0 Vec(Unk0193)) Vec(Unk0098) := …

  # Comptime.eval/1
  pub def eval(p0 Unk0194) Tuple(Unk0195, String) := …

  # Comptime.fold/1
  pub def fold(p0 Option(Unk0017)) Tuple(Unk0196, String) := …

  # Comptime.int_div/3
  pub def int_div(_a Unk0197, p1 Int53, _op Fn(Unk0199, Unk0198, Unk0200)) Tuple(Unk0201, Int53) := …

  # Core.first_unsupported/2
  pub def first_unsupported(node Unk0202, unsup Map(Unk0203, Option(Unk0204))) Option(Unk0204) := …

  # Core.from_arm/1
  pub def from_arm(p0 Unk0205) Unk0206 := …

  # Core.from_expr/1
  pub def from_expr(p0 Option(Unk0017)) Option(Unk0017) := …

  # Core.from_pairs/1
  pub def from_pairs(pairs Vec(Unk0207)) Vec(Tuple(Unk0208, Option(Unk0017))) := …

  # Core.from_pat/1
  pub def from_pat(p0 Sum2) Sum2 := …

  # Core.from_stmt/1
  pub def from_stmt(p0 Unk0209) Tuple(Unk0210, Option(Unk0017)) := …

  # Core.from_tail/1
  pub def from_tail(p0 Unk0211) Option(Unk0017) := …

  # Core.reject_unsupported!/4
  pub def reject_unsupported!(funcs Vec(Unk0212), unsup Map(Unk0203, Option(Unk0204)), target Symbol, exception Symbol) Symbol := …

  # Cst.build/1
  pub def build(tokens Vec(Unk0213)) Unk0214 := …

  # Cst.open/4
  pub def open(open_tok Unk0213, close Unk0215, rest Vec(Unk0213), acc Vec(Tuple(Unk0216, Unk0213))) Tuple(Vec(Tuple(Unk0216, Unk0213)), Vec(Unk0217)) := …

  # Cst.seq/2
  pub def seq(p0 Vec(Unk0213), acc Vec(Tuple(Unk0216, Unk0213))) Tuple(Vec(Tuple(Unk0216, Unk0213)), Vec(Unk0217)) := …

  # Decl.all_impl_decls/1
  pub def all_impl_decls(decls Vec(Unk0218)) Vec(Unk0219) := …

  # Decl.all_impls/1
  pub def all_impls(decls Vec(Unk0218)) Vec(Unk0220) := …

  # Decl.all_protocols/1
  pub def all_protocols(decls Vec(Unk0218)) Vec(Unk0219) := …

  # Decl.assemble/3
  pub def assemble(decls Vec(Unk0221), aliases Unk0222, p2 Unk0223) Unk0224 := …

  # Decl.attach_doc/2
  pub def attach_doc(p0 Tuple(Unk0226, Map(Unk0225, Bool)), doc Bool) Tuple(Unk0226, Map(Unk0225, Bool)) := …

  # Decl.attach_external/3
  pub def attach_external(p0 Unk0227, target Unk0228, spec Unk0229) Tuple(Unk0226, Map(Unk0225, Bool)) := …

  # Decl.attach_targets/2
  pub def attach_targets(p0 Unk0230, targets Unk0231) Tuple(Unk0226, Map(Unk0225, Bool)) := …

  # Decl.balanced_parens/1
  pub def balanced_parens(p0 Vec(Unk0232)) Tuple(Vec(Unk0232), Vec(Unk0232)) := …

  # Decl.block_seps/5
  pub def block_seps(p0 Vec(Unk0233), _d Int53, _w Int53, _p Int53, acc Vec(Unk0233)) Vec(Unk0233) := …

  # Decl.build_func/1
  pub def build_func(p0 Vec(Unk0234)) Func := …

  # Decl.calls_show_float?/1
  pub def calls_show_float?(p0 Vec(Unk0235)) Bool := …

  # Decl.clause/2
  pub def clause(p0 Unk0236, _arity Unk0237) Clause := …

  # Decl.clause_env/2
  pub def clause_env(p0 Clause, params Unk0238) Map(Unk0086, Vec(Unk0079)) := …

  # Decl.collapse_parens/1
  pub def collapse_parens(s Unk0239) Unk0240 := …

  # Decl.collect_aliases/1
  pub def collect_aliases(decls Vec(Unk0218)) Unk0241 := …

  # Decl.collect_macros/1
  pub def collect_macros(decls Vec(Unk0218)) Map(Unk0243, Unk0242) := …

  # Decl.compile/1
  pub def compile(src String) Vec(Tuple(String, Unk0244)) := …

  # Decl.compile_beam/1
  pub def compile_beam(src String) Vec(Tuple(Unk0245, Unk0244)) := …

  # Decl.decl_boundary?/1
  pub def decl_boundary?(p0 Vec(Vec(Unk0232))) Bool := …

  # Decl.decl_kw?/1
  pub def decl_kw?(p0 Vec(Vec(Unk0232))) Bool := …

  # Decl.def_raw/4
  pub def def_raw(name Unk0246, params Unk0247, head_rev Vec(Vec(Unk0232)), body Option(Unk0248)) Unk0249 := …

  # Decl.detok_block/1
  pub def detok_block(tokens Unk0250) Option(Unk0248) := …

  # Decl.extract_parens/1
  pub def extract_parens(str Unk0251) Unk0252 := …

  # Decl.field/1
  pub def field(f Unk0253) Field := …

  # Decl.fields/1
  pub def fields(inside Unk0254) Vec(Unk0255) := …

  # Decl.impl_struct/3
  pub def impl_struct(proto Unk0256, type Unk0257, inner Unk0258) Unk0259 := …

  # Decl.in_scope/2
  pub def in_scope(decls Vec(Unk0218), f Fn(Unk0260, Unk0261)) Vec(Unk0219) := …

  # Decl.inject_stdlib/1
  pub def inject_stdlib(prog Tuple(Unk0263, Vec(Unk0262))) Tuple(Unk0263, Vec(Unk0262)) := …

  # Decl.line_continues?/2
  pub def line_continues?(p0 Vec(Vec(Unk0232)), _rest Vec(Vec(Unk0232))) Bool := …

  # Decl.lower_meta/3
  pub def lower_meta(funcs Vec(Unk0264), decls Vec(Unk0218), targets Option(Unk0265)) Vec(Unk0266) := …

  # Decl.macro_param_names/1
  pub def macro_param_names(pstr Unk0267) Unk0268 := …

  # Decl.mark_pub/1
  pub def mark_pub(p0 Unk0269) Tuple(Unk0226, Map(Unk0225, Bool)) := …

  # Decl.mark_test/1
  pub def mark_test(p0 Unk0270) Tuple(Unk0226, Map(Unk0225, Bool)) := …

  # Decl.meta_clause/5
  pub def meta_clause(p0 Unk0271, _env Map(Unk0243, Unk0242), _p Bool, _params Unk0238, _show Unk0272) Unk0273 := …

  # Decl.needs_show_float?/1
  pub def needs_show_float?(prog Tuple(Unk0263, Vec(Unk0262))) Bool := …

  # Decl.nz/1
  pub def nz(s String) Option(Unk0274) := …

  # Decl.param/1
  pub def param(p Unk0275) Unk0276 := …

  # Decl.parse/1
  pub def parse(src String) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Decl.parse_abstract/4
  pub def parse_abstract(head Unk0277, body_toks Unk0278, pub? Unk0279, doc Unk0280) Opaque := …

  # Decl.parse_abstract_members/1
  pub def parse_abstract_members(toks Unk0278) Unk0281 := …

  # Decl.parse_alias/1
  pub def parse_alias(text Unk0277) Tuple(Unk0282, Unk0283) := …

  # Decl.parse_assoc_binding/1
  pub def parse_assoc_binding(t Unk0284) Tuple(Unk0285, Option(Unk0286)) := …

  # Decl.parse_binder/1
  pub def parse_binder(b Unk0287) Tuple(Unk0289, Vec(Unk0288)) := …

  # Decl.parse_binders/1
  pub def parse_binders(binders Unk0290) Vec(Unk0291) := …

  # Decl.parse_bounds/1
  pub def parse_bounds(text Unk0292) Unk0293 := …

  # Decl.parse_cast_rule/1
  pub def parse_cast_rule(p0 Unk0294) Unk0295 := …

  # Decl.parse_const/3
  pub def parse_const(text Unk0277, pub? Unk0296, doc Unk0297) Const := …

  # Decl.parse_external/1
  pub def parse_external(p0 Vec(Unk0298)) Tuple(Unk0300, Unk0299) := …

  # Decl.parse_head/1
  pub def parse_head(head String) Unk0301 := …

  # Decl.parse_op_rule/1
  pub def parse_op_rule(p0 Unk0294) Unk0302 := …

  # Decl.parse_opaque/3
  pub def parse_opaque(text Unk0277, pub? Unk0303, doc Unk0304) Opaque := …

  # Decl.parse_ordinal/1
  pub def parse_ordinal(p0 Unk0305) Tuple(Unk0306, Unk0307) := …

  # Decl.parse_params/1
  pub def parse_params(str Unk0308) Vec(Unk0309) := …

  # Decl.parse_range/3
  pub def parse_range(text Unk0277, pub? Unk0310, doc Unk0311) Range := …

  # Decl.parse_struct/3
  pub def parse_struct(text Unk0251, pub? Unk0312, doc Unk0313) Struct := …

  # Decl.parse_targets/1
  pub def parse_targets(toks Unk0314) Unk0231 := …

  # Decl.parse_type/3
  pub def parse_type(rest Unk0277, pub? Unk0315, doc Unk0316) Type := …

  # Decl.parse_use/1
  pub def parse_use(text Unk0317) Use := …

  # Decl.proto_method_traits/1
  pub def proto_method_traits(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0318 := …

  # Decl.protocol_defs/4
  pub def protocol_defs(decls Vec(Unk0221), types Unk0319, structs Unk0320, targets Unk0321) Vec(Unk0322) := …

  # Decl.protocol_struct/2
  pub def protocol_struct(name Unk0323, inner Unk0324) Unk0325 := …

  # Decl.protocol_unit/3
  pub def protocol_unit(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Tuple(String, Unk0244)) := …

  # Decl.req_ret/1
  pub def req_ret(p0 Unk0326) Unk0327 := …

  # Decl.skip_nl/1
  pub def skip_nl(p0 Vec(Unk0232)) Vec(Vec(Unk0232)) := …

  # Decl.split2/2
  pub def split2(str Unk0328, sep Unk0329) Tuple(Unk0330, Unk0331) := …

  # Decl.split_decls/1
  pub def split_decls(p0 Vec(Vec(Unk0232))) Vec(Unk0332) := …

  # Decl.split_forall/1
  pub def split_forall(head Unk0333) Unk0334 := …

  # Decl.split_once/2
  pub def split_once(str Unk0277, sep String) Tuple(Unk0336, Unk0335) := …

  # Decl.split_top/2
  pub def split_top(str Unk0337, sep String) Unk0338 := …

  # Decl.strip_type_params/1
  pub def strip_type_params(name Unk0339) Unk0282 := …

  # Decl.subst_const/2
  pub def subst_const(p0 Unk0340, aliases Unk0222) Const := …

  # Decl.subst_fields/2
  pub def subst_fields(fs Vec(Unk0341), aliases Unk0342) Vec(Field) := …

  # Decl.subst_func/2
  pub def subst_func(p0 Unk0343, aliases Unk0222) Func := …

  # Decl.subst_struct/2
  pub def subst_struct(p0 Unk0344, aliases Unk0222) Struct := …

  # Decl.subst_type/2
  pub def subst_type(p0 Unk0345, aliases Unk0222) Type := …

  # Decl.subst_type_str/2
  pub def subst_type_str(type Unk0346, aliases Vec(Unk0347)) Unk0346 := …

  # Decl.subst_variant/2
  pub def subst_variant(p0 Unk0348, aliases Unk0349) Variant := …

  # Decl.take_block/3
  pub def take_block(p0 Vec(Vec(Unk0232)), depth Int53, acc Vec(Vec(Unk0232))) Tuple(Vec(Vec(Unk0232)), Vec(Vec(Unk0232))) := …

  # Decl.take_decl/1
  pub def take_decl(p0 Vec(Vec(Unk0232))) Tuple(Tuple(Unk0226, Map(Unk0225, Bool)), Vec(Unk0232)) := …

  # Decl.take_def/1
  pub def take_def(p0 Vec(Vec(Unk0232))) Tuple(Unk0249, Vec(Vec(Unk0232))) := …

  # Decl.take_head/4
  pub def take_head(name Unk0246, params Unk0247, p2 Vec(Vec(Unk0232)), head Vec(Vec(Unk0232))) Tuple(Unk0249, Vec(Vec(Unk0232))) := …

  # Decl.take_line/2
  pub def take_line(tokens Vec(Vec(Unk0232)), acc Vec(Vec(Unk0232))) Tuple(Vec(Vec(Unk0232)), Vec(Vec(Unk0232))) := …

  # Decl.take_line/3
  pub def take_line(p0 Vec(Vec(Unk0232)), acc Vec(Vec(Unk0232)), _depth Int53) Tuple(Vec(Vec(Unk0232)), Vec(Vec(Unk0232))) := …

  # Decl.take_mod_body/2
  pub def take_mod_body(p0 Vec(Unk0232), acc Vec(Unk0350)) Tuple(Vec(Unk0350), Vec(Unk0232)) := …

  # Decl.take_parens/3
  pub def take_parens(p0 Vec(Unk0232), p1 Int53, acc Vec(Unk0232)) Tuple(Vec(Unk0232), Vec(Unk0232)) := …

  # Decl.take_type/2
  pub def take_type(p0 Vec(Vec(Unk0232)), acc Vec(Vec(Unk0232))) Tuple(Vec(Vec(Unk0232)), Vec(Vec(Unk0232))) := …

  # Decl.take_until_do/2
  pub def take_until_do(p0 Vec(Vec(Unk0232)), acc Vec(Vec(Unk0232))) Tuple(Vec(Vec(Unk0232)), Unk0351) := …

  # Decl.variant/1
  pub def variant(v Unk0251) Variant := …

  # Doc.concat/1
  pub def concat(docs Vec(Tuple(Unk0352, String))) Tuple(Unk0352, String) := …

  # Doc.concat/2
  pub def concat(a Tuple(Unk0352, String), b Tuple(Unk0352, String)) Tuple(Unk0352, String) := …

  # Doc.do_render/5
  pub def do_render(_w Int53, _k Int53, p2 Vec(Unk0353), p3 Vec(Unk0354), out Vec(String)) Vec(String) := …

  # Doc.empty/0
  pub def empty() Tuple(Unk0352, String) := …

  # Doc.fits?/2
  pub def fits?(w Int53, _work Vec(Unk0353)) Bool := …

  # Doc.flat_string/1
  pub def flat_string(p0 Unk0354) String := …

  # Doc.flush_suffix/2
  pub def flush_suffix(p0 Vec(Unk0354), out Vec(String)) Vec(String) := …

  # Doc.group/2
  pub def group(doc Tuple(Unk0352, String), p1 Bool) Unk0355 := …

  # Doc.hardline/0
  pub def hardline() Tuple(Unk0352, String) := …

  # Doc.if_break/2
  pub def if_break(broken Tuple(Unk0352, String), flat Tuple(Unk0352, String)) Tuple(Unk0352, String) := …

  # Doc.join/2
  pub def join(_sep Tuple(Unk0352, String), p1 Vec(Tuple(Unk0352, String))) Tuple(Unk0352, String) := …

  # Doc.line/0
  pub def line() Tuple(Unk0352, String) := …

  # Doc.line_suffix/1
  pub def line_suffix(doc Tuple(Unk0352, String)) Tuple(Unk0352, String) := …

  # Doc.must_break?/1
  pub def must_break?(p0 Tuple(Unk0352, String)) Bool := …

  # Doc.nest/2
  pub def nest(n Vec(Unk0356), doc Tuple(Unk0352, String)) Tuple(Unk0352, String) := …

  # Doc.render/2
  pub def render(doc Tuple(Unk0352, String), width Int53) String := …

  # Doc.softline/0
  pub def softline() Tuple(Unk0352, String) := …

  # Doc.text/1
  pub def text(s String) Tuple(Unk0352, String) := …

  # Doctest.augment/2
  pub def augment(src String, examples Vec(Unk0357)) String := …

  # Doctest.extract/1
  pub def extract(src String) Vec(Unk0357) := …

  # Doctest.exunit_cases/2
  pub def exunit_cases(src String, mod Unk0358) Unk0359 := …

  # Doctest.fences/1
  pub def fences(md Unk0360) Unk0361 := …

  # Doctest.module_doc_strings/1
  pub def module_doc_strings(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Unk0362) := …

  # Doctest.pairs/1
  pub def pairs(p0 Unk0363) Vec(Unk0364) := …

  # Doctest.run/2
  pub def run(src String, p1 Unk0365) Vec(Unk0366) := …

  # Doctest.run_markdown/1
  pub def run_markdown(md Unk0367) Unk0368 := …

  # Exhaustiveness.add_range/4
  pub def add_range(env Tuple(Unk0369, Map(String, String)), type_name String, lo Unk0370, hi Unk0371) Tuple(Unk0369, Map(String, String)) := …

  # Exhaustiveness.add_type/3
  pub def add_type(env Tuple(Unk0369, Map(String, String)), type_name String, variants Vec(Tuple(String, Unk0372))) Tuple(Unk0369, Map(String, String)) := …

  # Exhaustiveness.analyze/3
  pub def analyze(arms Vec(Unk0373), n Int53, env Map(Unk0374, Unk0375)) Unk0376 := …

  # Exhaustiveness.arity/2
  pub def arity(_env Map(Unk0374, Unk0375), p1 Unk0377) Int53 := …

  # Exhaustiveness.base_env/0
  pub def base_env() Tuple(Unk0369, Map(String, String)) := …

  # Exhaustiveness.body_core/1
  pub def body_core(body Option(Unk0017)) Option(Unk0017) := …

  # Exhaustiveness.check_case_bodies!/2
  pub def check_case_bodies!(funcs Unk0378, env Unk0379) Unk0380 := …

  # Exhaustiveness.check_match!/3
  pub def check_match!(core Unk0381, env Map(Unk0374, Unk0375), where Unk0382) Unk0383 := …

  # Exhaustiveness.check_one_case!/3
  pub def check_one_case!(p0 Sum1, env Map(Unk0374, Unk0375), where Unk0382) Unk0384 := …

  # Exhaustiveness.collect_cases/2
  pub def collect_cases(p0 Vec(Unk0385), acc Vec(Unk0386)) Vec(Unk0386) := …

  # Exhaustiveness.collect_children/2
  pub def collect_children(struct Vec(Unk0385), acc Vec(Unk0386)) Vec(Unk0386) := …

  # Exhaustiveness.default/1
  pub def default(rows Vec(Unk0387)) Vec(Unk0387) := …

  # Exhaustiveness.head_ctors/1
  pub def head_ctors(rows Vec(Unk0387)) Vec(Unk0388) := …

  # Exhaustiveness.missing_head/2
  pub def missing_head(_env Map(Unk0374, Unk0375), p1 Vec(Unk0388)) Unk0389 := …

  # Exhaustiveness.pascal/1
  pub def pascal(c Unk0390) String := …

  # Exhaustiveness.program_env/3
  pub def program_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0391), ranges Vec(Unk0392)) Tuple(Unk0369, Map(String, String)) := …

  # Exhaustiveness.render/1
  pub def render(p0 Vec(Unk0393)) String := …

  # Exhaustiveness.signature/2
  pub def signature(_env Map(Unk0374, Unk0375), p1 Vec(Unk0388)) Tuple(Unk0394, Vec(Unk0395)) := …

  # Exhaustiveness.specialize/3
  pub def specialize(rows Vec(Unk0387), c Unk0377, env Map(Unk0374, Unk0375)) Vec(Unk0387) := …

  # Exhaustiveness.useful?/3
  pub def useful?(rows Vec(Unk0387), p1 Vec(Unk0396), _env Map(Unk0374, Unk0375)) Bool := …

  # Exhaustiveness.witness/3
  pub def witness(rows Vec(Unk0387), p1 Int53, _env Map(Unk0374, Unk0375)) Tuple(Unk0397, Vec(Unk0389)) := …

  # Fixpoint.check/4
  pub def check(mod Unk0398, corpus Vec(String), project Unk0399, p3 Unk0400) Unk0401 := …

  # Format.apply_node/3
  pub def apply_node(p0 Option(Unk0402), base Vec(Unk0356), st Vec(Vec(Unk0356))) Vec(Vec(Unk0356)) := …

  # Format.bd/3
  pub def bd(p0 Vec(Option(Unk0402)), _prev Option(Unk0402), _rf Bool) Tuple(Unk0352, String) := …

  # Format.blank?/1
  pub def blank?(p0 Option(Unk0402)) Bool := …

  # Format.block_head?/2
  pub def block_head?(p0 Vec(Option(Unk0402)), next Vec(Option(Unk0402))) Bool := …

  # Format.boundary?/1
  pub def boundary?(p0 Vec(Option(Unk0402))) Bool := …

  # Format.boundary_tok?/1
  pub def boundary_tok?(p0 Tuple(Unk0403, String)) Bool := …

  # Format.chain?/1
  pub def chain?(nodes Vec(Option(Unk0402))) Bool := …

  # Format.chain_body/2
  pub def chain_body(nodes Vec(Option(Unk0402)), prev Option(Unk0402)) Tuple(Unk0352, String) := …

  # Format.chain_doc/1
  pub def chain_doc(nodes Vec(Option(Unk0402))) Tuple(Unk0352, String) := …

  # Format.chain_link?/2
  pub def chain_link?(a Vec(Option(Unk0402)), b Option(Unk0402)) Bool := …

  # Format.chain_tail/2
  pub def chain_tail(p0 Vec(Option(Unk0402)), _level Unk0404) Tuple(Unk0352, String) := …

  # Format.chunk_on_comma/3
  pub def chunk_on_comma(p0 Vec(Unk0405), cur Vec(Unk0405), acc Vec(Vec(Unk0405))) Vec(Vec(Unk0405)) := …

  # Format.closer_lead?/1
  pub def closer_lead?(p0 Tuple(Unk0403, String)) Bool := …

  # Format.comment_only?/1
  pub def comment_only?(line Option(Unk0402)) Bool := …

  # Format.cons_group?/1
  pub def cons_group?(inner Vec(Unk0406)) Bool := …

  # Format.cont_lead?/1
  pub def cont_lead?(p0 Tuple(Unk0403, String)) Bool := …

  # Format.decl_kw?/1
  pub def decl_kw?(p0 Tuple(Unk0403, String)) Bool := …

  # Format.declaration_line?/1
  pub def declaration_line?(p0 Vec(Option(Unk0402))) Bool := …

  # Format.ends_with_comment?/1
  pub def ends_with_comment?(line Vec(Option(Unk0402))) Bool := …

  # Format.finish_items/2
  pub def finish_items(cur Vec(Unk0405), acc Vec(Vec(Unk0405))) Vec(Vec(Unk0405)) := …

  # Format.format_result/1
  pub def format_result(src String) Tuple(Unk0407, Unk0408) := …

  # Format.group_doc/4
  pub def group_doc(open Unk0409, inner Vec(Unk0406), close Unk0409, reflow? Bool) Tuple(Unk0352, String) := …

  # Format.has_comment?/1
  pub def has_comment?(nodes Vec(Unk0406)) Bool := …

  # Format.has_tok?/2
  pub def has_tok?(line Vec(Tuple(Unk0411, Tuple(Unk0410, String))), t Tuple(Unk0410, String)) Bool := …

  # Format.head_tok/1
  pub def head_tok(p0 Option(Unk0402)) Tuple(Unk0403, String) := …

  # Format.indent_and_render/4
  pub def indent_and_render(p0 Vec(Option(Unk0402)), _stack Vec(Vec(Unk0356)), _cont Int53, acc Vec(String)) Vec(String) := …

  # Format.lead_adjust/1
  pub def lead_adjust(p0 Vec(Option(Unk0402))) Int53 := …

  # Format.leading_wrap_op?/1
  pub def leading_wrap_op?(p0 Vec(Option(Unk0402))) Bool := …

  # Format.leaf/1
  pub def leaf(p0 Unk0409) String := …

  # Format.line_doc/1
  pub def line_doc(nodes Vec(Option(Unk0402))) Tuple(Unk0352, String) := …

  # Format.ll/3
  pub def ll(p0 Vec(Unk0412), cur Vec(Unk0412), acc Vec(Vec(Unk0412))) Vec(Vec(Unk0412)) := …

  # Format.logical_lines/1
  pub def logical_lines(nodes Vec(Unk0412)) Vec(Vec(Unk0412)) := …

  # Format.magic_comma?/1
  pub def magic_comma?(inner Vec(Unk0406)) Bool := …

  # Format.mark/1
  pub def mark(nodes Option(Unk0402)) Vec(Option(Unk0402)) := …

  # Format.mark/3
  pub def mark(p0 Option(Unk0402), _prev Option(Unk0402), acc Vec(Option(Unk0402))) Vec(Option(Unk0402)) := …

  # Format.merge_chains/1
  pub def merge_chains(p0 Vec(Vec(Option(Unk0402)))) Vec(Vec(Option(Unk0402))) := …

  # Format.next_code_line/1
  pub def next_code_line(p0 Vec(Option(Unk0402))) Option(Unk0402) := …

  # Format.node_doc/2
  pub def node_doc(p0 Option(Unk0402), _rf Bool) Tuple(Unk0352, String) := …

  # Format.pop/1
  pub def pop(p0 Vec(Vec(Unk0356))) Vec(Vec(Unk0356)) := …

  # Format.push/2
  pub def push(base Vec(Unk0356), st Vec(Vec(Unk0356))) Vec(Vec(Unk0356)) := …

  # Format.render_line/2
  pub def render_line(nodes Vec(Option(Unk0402)), base Vec(Unk0356)) String := …

  # Format.space?/2
  pub def space?(_prev Tuple(Unk0403, String), p1 Tuple(Unk0403, String)) Bool := …

  # Format.split_items/1
  pub def split_items(nodes Vec(Unk0406)) Vec(Vec(Option(Unk0402))) := …

  # Format.split_level/1
  pub def split_level(nodes Vec(Option(Unk0402))) Unk0404 := …

  # Format.split_node?/2
  pub def split_node?(p0 Option(Unk0402), level Unk0404) Bool := …

  # Format.squeeze_blanks/1
  pub def squeeze_blanks(lines Unk0413) Unk0414 := …

  # Format.tail_tok/1
  pub def tail_tok(p0 Option(Unk0402)) Tuple(Unk0403, String) := …

  # Format.take_until_level/3
  pub def take_until_level(p0 Vec(Option(Unk0402)), _level Unk0404, acc Vec(Option(Unk0402))) Tuple(Vec(Option(Unk0402)), Vec(Option(Unk0402))) := …

  # Format.trailing_comma?/1
  pub def trailing_comma?(inner Vec(Unk0406)) Bool := …

  # Format.trailing_op?/1
  pub def trailing_op?(line Vec(Option(Unk0402))) Bool := …

  # Format.trailing_wrap_op?/1
  pub def trailing_wrap_op?(line Vec(Option(Unk0402))) Bool := …

  # Format.update_stack/4
  pub def update_stack(line Vec(Option(Unk0402)), rest Vec(Option(Unk0402)), base Vec(Unk0356), stack Vec(Vec(Unk0356))) Vec(Vec(Unk0356)) := …

  # Format.value_end?/1
  pub def value_end?(p0 Option(Unk0402)) Bool := …

  # Format.value_end_tok?/1
  pub def value_end_tok?(p0 Tuple(Unk0403, String)) Bool := …

  # Format.wrap_op_node?/1
  pub def wrap_op_node?(p0 Unk0415) Bool := …

  # Format.wrap_op_tok?/1
  pub def wrap_op_tok?(p0 Tuple(Unk0403, String)) Bool := …

  # Formatting.apply_edits/2
  pub def apply_edits(text String, edits Unk0416) String := …

  # Formatting.bump_del/3
  pub def bump_del(cur Unk0417, old Unk0418, n Int53) Unk0419 := …

  # Formatting.bump_ins/3
  pub def bump_ins(cur Unk0420, old Unk0418, ls Vec(Unk0421)) Unk0422 := …

  # Formatting.clamp/3
  pub def clamp(n Int53, lo Int53, hi Unk0423) Int53 := …

  # Formatting.edit/1
  pub def edit(p0 Unk0424) Unk0425 := …

  # Formatting.flush/2
  pub def flush(p0 Unk0426, acc Vec(Unk0426)) Vec(Unk0426) := …

  # Formatting.formatting/1
  pub def formatting(text String) Vec(Unk0427) := …

  # Formatting.hunks/2
  pub def hunks(old String, new String) Vec(Unk0427) := …

  # Formatting.range_formatting/3
  pub def range_formatting(text String, start_line Int53, end_line Int53) Vec(Unk0428) := …

  # Formatting.start_hunk/1
  pub def start_hunk(old Unk0418) Unk0429 := …

  # Formatting.to_hunks/1
  pub def to_hunks(diff Vec(Unk0430)) Vec(Unk0426) := …

  # FormsEquiv.abstract_code/1
  pub def abstract_code(beam Unk0431) Unk0432 := …

  # FormsEquiv.alpha_rename/1
  pub def alpha_rename(form Unk0433) Unk0434 := …

  # FormsEquiv.bool_clause/1
  pub def bool_clause(p0 Unk0435) Tuple(Unk0436, Unk0437) := …

  # FormsEquiv.bool_clause_pair/1
  pub def bool_clause_pair(p0 Vec(Unk0435)) Tuple(Unk0435, Unk0435) := …

  # FormsEquiv.canon_bool_case/1
  pub def canon_bool_case(p0 Vec(Unk0438)) Vec(Unk0438) := …

  # FormsEquiv.diff/2
  pub def diff(a Unk0439, b Unk0439) Tuple(Unk0441, Vec(Unk0440)) := …

  # FormsEquiv.equivalent?/2
  pub def equivalent?(a Unk0439, b Unk0439) Bool := …

  # FormsEquiv.fold_neg_literal/1
  pub def fold_neg_literal(p0 Vec(Unk0442)) Vec(Unk0442) := …

  # FormsEquiv.key/1
  pub def key(p0 Unk0443) Tuple(Unk0444, Unk0445) := …

  # FormsEquiv.normalize/1
  pub def normalize(beam Unk0439) Unk0446 := …

  # FormsEquiv.user_function?/1
  pub def user_function?(p0 Unk0447) Bool := …

  # FormsEquiv.verified?/2
  pub def verified?(oracle Unk0439, port Unk0439) Bool := …

  # FormsEquiv.verify/2
  pub def verify(oracle Unk0439, port Unk0439) Vec(Unk0448) := …

  # FormsEquiv.walk_rename/2
  pub def walk_rename(p0 Unk0433, map Map(Unk0450, Unk0449)) Tuple(Unk0433, Map(Unk0450, Unk0449)) := …

  # FormsEquiv.zero_anno/1
  pub def zero_anno(tuple Vec(Unk0451)) Vec(Unk0451) := …

  # History.dedup_consecutive/1
  pub def dedup_consecutive(p0 Vec(Vec(Unk0452))) Vec(Vec(Unk0452)) := …

  # History.load/0
  pub def load() Vec(Unk0453) := …

  # Infer.app/2
  pub def app(head String, args Vec(Option(Unk0454))) Option(Unk0454) := …

  # Infer.app1/2
  pub def app1(head String, s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.apply_spec_terms/4
  pub def apply_spec_terms(p0 Unk0459, _pvars Unk0460, _rvar Option(Unk0454), store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))) := …

  # Infer.bind/3
  pub def bind(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), id Unk0458, t Tuple(Unk0457, Unk0456)) Unk0461 := …

  # Infer.bind_checked/3
  pub def bind_checked(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), i Unk0458, t Tuple(Unk0457, Unk0456)) Tuple(Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), Unk0462) := …

  # Infer.bind_params/3
  pub def bind_params(args Unk0463, pvars Unk0464, store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Unk0465 := …

  # Infer.build_ctx/2
  pub def build_ctx(stdlib_map Unk0466, p1 Unk0467) Unk0468 := …

  # Infer.build_ledger/2
  pub def build_ledger(params Unk0469, ret String) Vec(Tuple(String, Unk0470)) := …

  # Infer.call_sig/6
  pub def call_sig(ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), key Unk0473, args Vec(Bool), env Map(String, Option(Unk0454)), _outer Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.case_arm/1
  pub def case_arm(p0 Unk0474) Tuple(Unk0475, Option(Unk0476)) := …

  # Infer.clear_xmod/0
  pub def clear_xmod() Unk0477 := …

  # Infer.cluster_name/2
  pub def cluster_name(clusters Map(Tuple(Unk0471, Int53), Unk0459), struct String) String := …

  # Infer.collect_specs/1
  pub def collect_specs(stmts Vec(String)) Map(Tuple(Unk0471, Int53), Unk0459) := …

  # Infer.con/1
  pub def con(name String) Option(Unk0454) := …

  # Infer.do_unify/3
  pub def do_unify(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), t Tuple(Unk0457, Unk0456), t Tuple(Unk0457, Unk0456)) Tuple(Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), Unk0462) := …

  # Infer.free_vars/2
  pub def free_vars(store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), t Option(Unk0454)) Vec(Unk0478) := …

  # Infer.fresh/1
  pub def fresh(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.fresh_n/2
  pub def fresh_n(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), k Int53) Tuple(Vec(Unk0479), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.fresh_num/1
  pub def fresh_num(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.freshen_tvars/2
  pub def freshen_tvars(tvars Vec(Unk0480), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Map(Unk0480, Unk0481), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen/4
  pub def gen(n Bool, _env Map(String, Option(Unk0454)), _ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen_args_then_fresh/4
  pub def gen_args_then_fresh(args Vec(Bool), env Map(String, Option(Unk0454)), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen_block/4
  pub def gen_block(p0 Vec(Bool), _env Map(String, Option(Unk0454)), _ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen_cons/5
  pub def gen_cons(h Bool, t Bool, env Map(String, Option(Unk0454)), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen_pat/4
  pub def gen_pat(p0 Vec(Unk0482), pv Option(Unk0454), env Map(String, Option(Unk0454)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Map(String, Option(Unk0454)), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.gen_pat_cons/5
  pub def gen_pat_cons(h Vec(Unk0482), t Vec(Unk0482), pv Option(Unk0454), env Map(String, Option(Unk0454)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Map(String, Option(Unk0454)), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.generalize_map/3
  pub def generalize_map(pvars Unk0483, rvar Option(Unk0454), store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Map(Unk0485, Unk0484) := …

  # Infer.hole_or/2
  pub def hole_or(p0 Unk0486, h Unk0486) Unk0486 := …

  # Infer.hole_sig?/1
  pub def hole_sig?(p0 Unk0487) Bool := …

  # Infer.infer_group/2
  pub def infer_group(p0 Unk0488, ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459))) Unk0487 := …

  # Infer.instantiate/5
  pub def instantiate(p0 Unk0489, args Vec(Bool), env Map(String, Option(Unk0454)), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.load_prelude_sigs/0
  pub def load_prelude_sigs() Unk0490 := …

  # Infer.mark_num/2
  pub def mark_num(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), t Option(Unk0454)) Tuple(Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), Unk0491) := …

  # Infer.max_ph/1
  pub def max_ph(p0 Vec(Unk0492)) Int53 := …

  # Infer.maybe_tuple/4
  pub def maybe_tuple(elems Vec(Unk0493), env Map(String, Option(Unk0454)), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Option(Unk0454), Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) := …

  # Infer.mod_name/1
  pub def mod_name(p0 Unk0494) String := …

  # Infer.num_conflict?/3
  pub def num_conflict?(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), i Unk0458, t Tuple(Unk0457, Unk0456)) Bool := …

  # Infer.numeric_con?/1
  pub def numeric_con?(p0 Tuple(Unk0457, Unk0456)) Bool := …

  # Infer.occurs?/3
  pub def occurs?(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), i Unk0458, t Tuple(Unk0457, Unk0456)) Bool := …

  # Infer.ok_payload/3
  pub def ok_payload(tail_pairs Vec(Unk0495), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), store Unk0496) Unk0497 := …

  # Infer.parse_type/2
  pub def parse_type(str Unk0498, fmap Map(Unk0499, Unk0500)) Option(Unk0454) := …

  # Infer.prelude_sigs/0
  pub def prelude_sigs() Unk0490 := …

  # Infer.prime_xmod/2
  pub def prime_xmod(modules Unk0501, stdlib_map Unk0502) Unk0503 := …

  # Infer.put_slot/3
  pub def put_slot(sig Tuple(Unk0504, String), p1 String, ts String) Unk0505 := …

  # Infer.render/3
  pub def render(store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), gmap Map(Unk0485, Unk0484), t Option(Unk0454)) String := …

  # Infer.render_wp/3
  pub def render_wp(store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), unk_names Map(Unk0506, String), t Option(Unk0454)) String := …

  # Infer.resolve/2
  pub def resolve(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), p1 Option(Unk0454)) Tuple(Unk0457, Unk0456) := …

  # Infer.resolve_program/2
  pub def resolve_program(sigvars Vec(Unk0507), store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Unk0508 := …

  # Infer.resolve_struct_params/4
  pub def resolve_struct_params(args Unk0509, pvars Unk0510, ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))) := …

  # Infer.result_analysis/3
  pub def result_analysis(clause_envs Vec(Unk0511), ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), store Unk0496) Unk0512 := …

  # Infer.result_tag/1
  pub def result_tag(p0 Unk0513) Tuple(Unk0515, Unk0514) := …

  # Infer.seed_spec/6
  pub def seed_spec(ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), name Unk0471, arity Int53, pvars Unk0460, rvar Option(Unk0454), store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))) := …

  # Infer.sig_of/1
  pub def sig_of(f Unk0516) Unk0517 := …

  # Infer.sigvar_call/5
  pub def sigvar_call(ctx Map(Unk0472, Map(Tuple(Unk0471, Int53), Unk0459)), key Unk0518, args Unk0519, env Map(String, Option(Unk0454)), s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456)))) Unk0520 := …

  # Infer.slot_sig/3
  pub def slot_sig(p0 String, ts String, _ Vec(Unk0521)) Unk0522 := …

  # Infer.spec_pair/1
  pub def spec_pair(p0 Unk0523) Tuple(Tuple(Unk0525, Unk0526), Unk0524) := …

  # Infer.spec_str/1
  pub def spec_str(p0 Unk0527) String := …

  # Infer.store_new/0
  pub def store_new() Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))) := …

  # Infer.translate_spec/1
  pub def translate_spec(p0 Vec(Unk0528)) Option(Unk0454) := …

  # Infer.tvar?/1
  pub def tvar?(s Unk0499) Unk0529 := …

  # Infer.tvar_name/1
  pub def tvar_name(i Unk0530) Unk0531 := …

  # Infer.unify/3
  pub def unify(s Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), a Option(Unk0454), b Option(Unk0454)) Tuple(Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), Unk0462) := …

  # Infer.union_spec/2
  pub def union_spec(a Vec(Unk0528), b Vec(Unk0528)) Option(Unk0454) := …

  # Infer.unk_vars/2
  pub def unk_vars(store Tuple(Unk0455, Map(Unk0458, Tuple(Unk0457, Unk0456))), v Option(Unk0454)) Vec(Unk0532) := …

  # Infer.vec_spec/1
  pub def vec_spec(elem Unk0528) Option(Unk0454) := …

  # Infer.whole_program/4
  pub def whole_program(modules Vec(Tuple(String, Vec(Unk0533))), stdlib Unk0534, p2 Unk0535, p3 Unk0536) Unk0508 := …

  # Infer.xmod_cache/0
  pub def xmod_cache() Unk0537 := …

  # Interp.concat_chain/1
  pub def concat_chain(parts Vec(Tuple(Unk0538, String))) Tuple(Unk0538, String) := …

  # Interp.int_type?/1
  pub def int_type?(t Vec(Unk0079)) Bool := …

  # Interp.resolve/4
  pub def resolve(p0 Tuple(Unk0196, String), env Map(Unk0086, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), show Unk0272) Option(Unk0017) := …

  # Interp.resolve_part/4
  pub def resolve_part(p0 Unk0539, _env Map(Unk0086, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), _show Unk0272) Tuple(Unk0540, Unk0541) := …

  # Interp.stringify/3
  pub def stringify(expr Option(Unk0017), p1 Vec(Unk0079), _show Unk0272) Tuple(Unk0540, Unk0541) := …

  # JS.all_funcs/1
  pub def all_funcs(prog Map(Unk0542, Vec(Unk0543))) Vec(Unk0543) := …

  # JS.arm_return/3
  pub def arm_return(body Unk0544, p1 Unk0545, i53 Bool) String := …

  # JS.bind_lines/1
  pub def bind_lines(binds Vec(Unk0546)) Vec(String) := …

  # JS.block_return/2
  pub def block_return(p0 Vec(Unk0547), i53 Bool) String := …

  # JS.branch_js/2
  pub def branch_js(p0 Sum1, i53 Bool) String := …

  # JS.case_arm_js/2
  pub def case_arm_js(p0 Unk0548, i53 Bool) String := …

  # JS.clause_js/2
  pub def clause_js(p0 Unk0549, i53 Bool) String := …

  # JS.clause_return/3
  pub def clause_return(src Option(Unk0017), params Vec(Unk0550), i53 Bool) String := …

  # JS.cp_lit/2
  pub def cp_lit(cp Unk0551, i53 Bool) String := …

  # JS.dispatcher_js/5
  pub def dispatcher_js(proto Unk0552, method Unk0553, impl_types Vec(Unk0554), reg Unk0555, i53 Bool) String := …

  # JS.expr_js/2
  pub def expr_js(p0 Sum1, i53 Bool) String := …

  # JS.float?/1
  pub def float?(n Unk0556) Bool := …

  # JS.function_js/2
  pub def function_js(p0 Unk0212, _i53 Bool) String := …

  # JS.guarded_return/4
  pub def guarded_return(body Option(Unk0017), p1 Unk0557, params Vec(Unk0550), i53 Bool) String := …

  # JS.js_atom/1
  pub def js_atom(name Unk0558) String := …

  # JS.js_guard!/4
  pub def js_guard!(type String, proto Unk0559, reg Unk0560, i53 Unk0561) Unk0562 := …

  # JS.js_number_int?/1
  pub def js_number_int?(t Unk0563) Bool := …

  # JS.js_str/1
  pub def js_str(s Unk0558) String := …

  # JS.lit_js/2
  pub def lit_js(v Unk0558, i53 Bool) String := …

  # JS.mangle/3
  pub def mangle(proto Unk0564, type Unk0565, method Unk0566) String := …

  # JS.match_elems/3
  pub def match_elems(es Unk0567, acc String, i53 Bool) Unk0568 := …

  # JS.num_js/2
  pub def num_js(n Unk0556, i53 Bool) String := …

  # JS.paren/2
  pub def paren(e Unk0569, i53 Unk0570) String := …

  # JS.pascal?/1
  pub def pascal?(s Unk0571) Bool := …

  # JS.pat_match/3
  pub def pat_match(p0 Sum2, _acc String, _i53 Bool) Tuple(Vec(String), Vec(Tuple(Unk0572, String))) := …

  # JS.program_number_mode?/1
  pub def program_number_mode?(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Bool := …

  # JS.protocol_dispatchers_js/2
  pub def protocol_dispatchers_js(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))), i53 Bool) String := …

  # JS.reject_mixed_int_mode!/1
  pub def reject_mixed_int_mode!(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0573 := …

  # JS.reject_wide_int!/2
  pub def reject_wide_int!(name Unk0574, p1 Unk0575) Unk0576 := …

  # JS.stmt_js/2
  pub def stmt_js(p0 Unk0577, i53 Bool) String := …

  # JS.stmt_return/2
  pub def stmt_return(p0 Unk0578, i53 Unk0579) String := …

  # JS.struct_name_set/1
  pub def struct_name_set(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0580 := …

  # JS.sum_ctor_map/1
  pub def sum_ctor_map(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0581 := …

  # JS.sum_guard_js/1
  pub def sum_guard_js(ctors Vec(Unk0582)) String := …

  # JVM.all_funcs/1
  pub def all_funcs(prog Map(Unk0584, Vec(Unk0583))) Vec(Unk0583) := …

  # JVM.all_types/1
  pub def all_types(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # JVM.bind_str/1
  pub def bind_str(p0 Vec(Unk0585)) String := …

  # JVM.block_value/1
  pub def block_value(p0 Vec(Unk0547)) String := …

  # JVM.branch_kt/1
  pub def branch_kt(p0 Sum1) String := …

  # JVM.case_arms/2
  pub def case_arms(arms Unk0586, acc String) Tuple(Vec(Unk0588), Unk0587) := …

  # JVM.clause_lines/1
  pub def clause_lines(p0 Vec(Unk0589)) Tuple(String, Bool) := …

  # JVM.clause_match/1
  pub def clause_match(pats Unk0590) Unk0591 := …

  # JVM.clause_value/2
  pub def clause_value(src Option(Unk0017), params Vec(Unk0550)) String := …

  # JVM.closed_or_cond/3
  pub def closed_or_cond(p0 Vec(Unk0592), line String, _rest Vec(Unk0589)) Tuple(String, Bool) := …

  # JVM.expr_kt/1
  pub def expr_kt(p0 Sum1) String := …

  # JVM.function_kt/1
  pub def function_kt(p0 Unk0593) String := …

  # JVM.guarded_arm/2
  pub def guarded_arm(body_kt String, p1 Unk0594) String := …

  # JVM.guarded_return/3
  pub def guarded_return(body Unk0595, p1 Unk0596, params Vec(Unk0597)) String := …

  # JVM.kotlin_module/2
  pub def kotlin_module(src String, p1 Unk0598) String := …

  # JVM.kt_str/1
  pub def kt_str(s Unk0599) String := …

  # JVM.kt_type/1
  pub def kt_type(p0 String) Unk0600 := …

  # JVM.lit_kt/1
  pub def lit_kt(v Unk0599) String := …

  # JVM.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Tuple(Vec(String), Vec(Tuple(Unk0601, String))) := …

  # JVM.prepend_if/3
  pub def prepend_if(tests Vec(Unk0592), line String, rest Vec(Unk0589)) Tuple(String, Bool) := …

  # JVM.run_or_cond/3
  pub def run_or_cond(p0 Vec(Unk0592), line String, rest Vec(Unk0589)) Tuple(String, Bool) := …

  # JVM.stmt_kt/1
  pub def stmt_kt(p0 Unk0602) String := …

  # JVM.stmt_value/1
  pub def stmt_value(p0 Unk0603) String := …

  # JVM.sum_decl/1
  pub def sum_decl(t Unk0604) String := …

  # JVM.to_jar/3
  pub def to_jar(src String, jar_path String, p2 Unk0605) Unk0606 := …

  # JVM.variant_decl/2
  pub def variant_decl(p0 Unk0607, tname Unk0608) String := …

  # Lexer.binify/1
  pub def binify(acc Vec(String)) Unk0609 := …

  # Lexer.capture_hole/3
  pub def capture_hole(p0 String, _d Int53, _acc Vec(String)) Tuple(Unk0609, Unk0610) := …

  # Lexer.char_escape/1
  pub def char_escape(p0 Unk0611) Tuple(Int53, Unk0612) := …

  # Lexer.close_char/1
  pub def close_char(p0 String) Unk0613 := …

  # Lexer.collapse_nl/1
  pub def collapse_nl(tokens Unk0614) Unk0615 := …

  # Lexer.detokenize/2
  pub def detokenize(tokens Unk0616, p1 String) String := …

  # Lexer.escape_str/1
  pub def escape_str(s Unk0617) String := …

  # Lexer.expr_tokens/1
  pub def expr_tokens(src String) Vec(Vec(Vec(Unk0618))) := …

  # Lexer.lex/2
  pub def lex(str String, acc Vec(Tuple(Unk0619, String))) Unk0620 := …

  # Lexer.lex_char/1
  pub def lex_char(p0 String) Tuple(Unk0621, Unk0613) := …

  # Lexer.lex_parts/3
  pub def lex_parts(p0 String, _lit Vec(String), _parts Vec(Tuple(Unk0622, Unk0609))) Tuple(Vec(Tuple(Unk0622, Unk0609)), Unk0623) := …

  # Lexer.lex_string_token/1
  pub def lex_string_token(str String) Tuple(Tuple(Unk0625, Vec(Unk0624)), Unk0626) := …

  # Lexer.parse_hex!/1
  pub def parse_hex!(hex Unk0612) Int53 := …

  # Lexer.punct/1
  pub def punct(str String) Option(Unk0627) := …

  # Lexer.string_token/1
  pub def string_token(parts Vec(Unk0624)) Tuple(Unk0625, Vec(Unk0624)) := …

  # Lexer.strip_trivia/1
  pub def strip_trivia(tokens Unk0628) Unk0629 := …

  # Lexer.take_comment/1
  pub def take_comment(str String) Tuple(Unk0630, String) := …

  # Lexer.take_hex/2
  pub def take_hex(str Unk0631, max Int53) Tuple(String, Unk0631) := …

  # Lexer.take_hex/3
  pub def take_hex(p0 Unk0631, max Int53, acc String) Tuple(String, Unk0631) := …

  # Lexer.tok_str/2
  pub def tok_str(p0 Unk0632, nl_as String) String := …

  # Lexer.tokenize/1
  pub def tokenize(src String) Unk0633 := …

  # Lexer.tokenize_trivia/1
  pub def tokenize_trivia(src String) Unk0620 := …

  # Lexer.word/1
  pub def word(w String) Tuple(Unk0619, String) := …

  # Livebook.eval/1
  pub def eval(source String) Unk0634 := …

  # Livebook.output/1
  pub def output(p0 Vec(String)) Unk0634 := …

  # Livebook.run/2
  pub def run(session Unk0635, source String) Tuple(Unk0636, Unk0635) := …

  # Livebook.session_pid/0
  pub def session_pid() Unk0637 := …

  # Lower.add_list_elem_vars/2
  pub def add_list_elem_vars(acc Unk0638, p1 Unk0639) Unk0638 := …

  # Lower.add_var/2
  pub def add_var(acc Unk0638, p1 Unk0640) Unk0638 := …

  # Lower.all_pat_vars/1
  pub def all_pat_vars(p0 Sum2) Vec(Unk0641) := …

  # Lower.arm_rebinds/3
  pub def arm_rebinds(pats Unk0642, iso Unk0643, used Unk0644) Vec(Unk0645) := …

  # Lower.assoc/1
  pub def assoc(op String) Unk0646 := …

  # Lower.body_ast/2
  pub def body_ast(src Unk0647, ctx Unk0648) Unk0649 := …

  # Lower.borrow_arg/5
  pub def borrow_arg(a Tuple(Unk0196, String), pt String, funs Map(Unk0650, Unk0651), borrowed Bool, ec Unk0652) Unk0653 := …

  # Lower.borrow_value/2
  pub def borrow_value(p0 Tuple(Unk0196, String), _borrowed Bool) Tuple(Unk0196, String) := …

  # Lower.borrowed_in_pat/2
  pub def borrowed_in_pat(p0 Sum2, p1 Bool) Vec(Unk0654) := …

  # Lower.borrowed_vars/2
  pub def borrowed_vars(params Unk0655, pats Unk0656) Option(Unk0657) := …

  # Lower.build_env/3
  pub def build_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0658), ranges Vec(Unk0659)) Unk0660 := …

  # Lower.build_meta/1
  pub def build_meta(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0661 := …

  # Lower.build_struct_meta/1
  pub def build_struct_meta(structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0662 := …

  # Lower.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Lower.case_guard/3
  pub def case_guard(p0 Option(Unk0017), _ Unk0663, _ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.catchall_pat?/1
  pub def catchall_pat?(p0 Sum2) Bool := …

  # Lower.char_vars/2
  pub def char_vars(params Unk0666, pats Unk0667) Unk0668 := …

  # Lower.check!/2
  pub def check!(p0 Map(Unk0669, Vec(Unk0010)), _env Unk0660) Unk0670 := …

  # Lower.coerce_string_ast/2
  pub def coerce_string_ast(p0 Option(Unk0017), ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.coerce_string_branch/2
  pub def coerce_string_branch(p0 Option(Unk0017), ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.collect_ids/2
  pub def collect_ids(p0 Vec(Unk0671), acc Unk0644) Unk0644 := …

  # Lower.collect_owned_field_vars/3
  pub def collect_owned_field_vars(p0 Unk0672, ctx Map(Unk0674, Unk0673), acc Unk0675) Unk0675 := …

  # Lower.compile/5
  pub def compile(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0669, Vec(Unk0010)), p2 Unk0676, p3 Unk0677, p4 Unk0318) Unk0244 := …

  # Lower.compile_beam/4
  pub def compile_beam(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0669, Vec(Unk0010)), p2 Unk0678, p3 Unk0679) Unk0244 := …

  # Lower.compile_elixir/4
  pub def compile_elixir(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0669, Vec(Unk0010)), p2 Unk0680, p3 Unk0681) Unk0244 := …

  # Lower.compile_module/1
  pub def compile_module(p0 Unk0682) Unk0244 := …

  # Lower.compile_module_beam/1
  pub def compile_module_beam(p0 Unk0683) Unk0244 := …

  # Lower.cons_tail_names/1
  pub def cons_tail_names(p0 Sum2) Vec(Unk0684) := …

  # Lower.cons_tail_rebinds/1
  pub def cons_tail_rebinds(p0 Sum2) Vec(String) := …

  # Lower.const_set/1
  pub def const_set(consts Vec(Unk0685)) Unk0686 := …

  # Lower.core_pat_ex/1
  pub def core_pat_ex(surface Sum2) String := …

  # Lower.core_pat_rs/2
  pub def core_pat_rs(surface Sum2, meta Unk0687) String := …

  # Lower.core_pat_vars/1
  pub def core_pat_vars(p0 Sum2) Vec(Unk0688) := …

  # Lower.ctx/4
  pub def ctx(meta Unk0661, smeta Unk0662, cset Unk0686, p3 Unk0689) Map(Unk0674, Unk0673) := …

  # Lower.deref_ids/2
  pub def deref_ids(ast Tuple(Unk0690, String), p1 Vec(Unk0691)) Tuple(Unk0690, String) := …

  # Lower.disp/2
  pub def disp(p0 String, p1 Unk0663) String := …

  # Lower.elixir_clauses/3
  pub def elixir_clauses(func Map(Unk0669, Vec(Unk0010)), ctx Unk0692, def_kw String) String := …

  # Lower.emit/3
  pub def emit(p0 Option(Unk0017), _t Unk0663, _ec Tuple(Unk0664, Unk0665)) Tuple(String, Int53) := …

  # Lower.emit_ast/2
  pub def emit_ast(ast Option(Unk0017), target Unk0663) Unk0693 := …

  # Lower.emit_block/3
  pub def emit_block(p0 Sum1, p1 Unk0663, _ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.emit_ctx/1
  pub def emit_ctx(p0 Unk0694) Tuple(Unk0696, Unk0695) := …

  # Lower.emit_expr/2
  pub def emit_expr(src String, target Unk0663) Unk0697 := …

  # Lower.enum_generics/2
  pub def enum_generics(name Unk0698, parametric Map(Unk0698, Vec(Unk0699))) String := …

  # Lower.ex_const/2
  pub def ex_const(c Unk0685, ctx Unk0692) String := …

  # Lower.ex_doc/2
  pub def ex_doc(p0 Vec(Unk0010), _attr String) String := …

  # Lower.ex_struct/1
  pub def ex_struct(s Unk0700) String := …

  # Lower.ex_typespec/1
  pub def ex_typespec(t Map(Unk0701, Vec(Unk0010))) String := …

  # Lower.ex_use/1
  pub def ex_use(p0 Unk0702) String := …

  # Lower.flatten_concat/1
  pub def flatten_concat(p0 Sum1) Vec(Sum1) := …

  # Lower.fn_all_tvars/3
  pub def fn_all_tvars(func Map(Unk0669, Vec(Unk0010)), pinst Unk0703, ec Tuple(Unk0705, Unk0704)) Vec(Unk0010) := …

  # Lower.guard_kw/1
  pub def guard_kw(p0 Unk0663) String := …

  # Lower.guard_str/4
  pub def guard_str(c Map(Unk0706, String), target Unk0663, ec Tuple(Unk0664, Unk0665), p3 Unk0707) String := …

  # Lower.impl_param/2
  pub def impl_param(p0 Unk0708, rust_type String) String := …

  # Lower.infer_concrete_params/3
  pub def infer_concrete_params(func Map(Unk0669, Vec(Unk0010)), params Vec(Unk0709), ec Tuple(Unk0705, Unk0704)) Vec(String) := …

  # Lower.infer_tvar_binding/2
  pub def infer_tvar_binding(p0 Unk0710, ec Unk0711) Unk0712 := …

  # Lower.insert_borrows/4
  pub def insert_borrows(p0 Option(Unk0017), funs Map(Unk0650, Unk0651), ec Unk0652, borrowed Bool) Tuple(Unk0196, String) := …

  # Lower.iso_cons_positions/1
  pub def iso_cons_positions(func Map(Unk0669, Vec(Unk0010))) Unk0643 := …

  # Lower.list_rpat?/1
  pub def list_rpat?(p0 Unk0713) Bool := …

  # Lower.member_scan/3
  pub def member_scan(p0 Vec(Unk0714), _name Vec(Unk0715), _prev Bool) Bool := …

  # Lower.module_elixir/1
  pub def module_elixir(p0 Unk0716) String := …

  # Lower.module_rust/1
  pub def module_rust(p0 Unk0717) String := …

  # Lower.ofb/3
  pub def ofb(p0 Vec(Unk0718), ctx Map(Unk0674, Unk0673), acc Unk0675) Unk0675 := …

  # Lower.owned_arg?/2
  pub def owned_arg?(p0 Tuple(Unk0196, String), _funs Map(Unk0650, Unk0651)) Bool := …

  # Lower.owned_field_binders/2
  pub def owned_field_binders(ast Vec(Unk0718), ctx Map(Unk0674, Unk0673)) Unk0675 := …

  # Lower.owned_field_var?/2
  pub def owned_field_var?(p0 Tuple(Unk0196, String), ec Unk0652) Bool := …

  # Lower.owned_scrut?/2
  pub def owned_scrut?(p0 Unk0719, _ctx Map(Unk0674, Unk0673)) Bool := …

  # Lower.owned_str_arg/1
  pub def owned_str_arg(s Unk0720) Unk0721 := …

  # Lower.p/4
  pub def p(node Option(Unk0017), ctx Int53, t Unk0663, ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.pair_inst/2
  pub def pair_inst(func Map(Unk0669, Vec(Unk0010)), ec Tuple(Unk0705, Unk0704)) Unk0703 := …

  # Lower.param_rtypes/2
  pub def param_rtypes(name Unk0650, funs Map(Unk0650, Unk0651)) Vec(String) := …

  # Lower.parametric_param_map/1
  pub def parametric_param_map(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0722 := …

  # Lower.parametric_used?/2
  pub def parametric_used?(func Map(Unk0669, Vec(Unk0010)), name Unk0723) Bool := …

  # Lower.pascal?/1
  pub def pascal?(s Unk0724) Bool := …

  # Lower.pat_ex/1
  pub def pat_ex(p0 Sum2) String := …

  # Lower.pat_rs/2
  pub def pat_rs(p0 Sum2, _ Unk0687) String := …

  # Lower.pipe_to_call/2
  pub def pipe_to_call(l Unk0725, p1 Sum1) Sum1 := …

  # Lower.proto_method_traits/1
  pub def proto_method_traits(protocols Vec(Map(Unk0009, Vec(Unk0010)))) Unk0726 := …

  # Lower.pub_sig_type_names/1
  pub def pub_sig_type_names(funcs Unk0727) Unk0728 := …

  # Lower.ref_type/2
  pub def ref_type(p0 String, self_repr Unk0729) String := …

  # Lower.resolve_consts/2
  pub def resolve_consts(p0 Option(Unk0017), cset Unk0730) Tuple(Unk0196, String) := …

  # Lower.resolve_rust_pats/2
  pub def resolve_rust_pats(p0 Option(Unk0017), meta Unk0687) Tuple(Unk0196, String) := …

  # Lower.resolve_structs/2
  pub def resolve_structs(p0 Option(Unk0017), smeta Unk0731) Tuple(Unk0196, String) := …

  # Lower.resolve_variants/2
  pub def resolve_variants(p0 Option(Unk0017), meta Map(Unk0732, Option(Unk0733))) Tuple(Unk0196, String) := …

  # Lower.rest_pat_rs/1
  pub def rest_pat_rs(p0 Sum2) String := …

  # Lower.result_parts/1
  pub def result_parts(ret String) Tuple(Unk0734, String) := …

  # Lower.result_payload/3
  pub def result_payload(val Option(Unk0017), string? Bool, ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.rewrite_proto_calls/2
  pub def rewrite_proto_calls(p0 Vec(Unk0735), methods Unk0736) Vec(Unk0735) := …

  # Lower.rpat/1
  pub def rpat(p0 Sum2) String := …

  # Lower.rs_doc/2
  pub def rs_doc(p0 Vec(Unk0010), _prefix String) String := …

  # Lower.rust_arm_body/2
  pub def rust_arm_body(p0 Sum1, s String) String := …

  # Lower.rust_case/4
  pub def rust_case(scrut Option(Unk0017), arms Vec(Unk0737), body_fn Fn(Option(Unk0017), String), ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.rust_const/2
  pub def rust_const(c Unk0685, ctx Map(Unk0674, Unk0673)) String := …

  # Lower.rust_enum/3
  pub def rust_enum(t Map(Unk0009, Vec(Unk0010)), p1 String, p2 Unk0722) String := …

  # Lower.rust_fn/4
  pub def rust_fn(p0 Map(Unk0669, Vec(Unk0010)), _ctx Map(Unk0674, Unk0673), vis String, _base_ec Tuple(Unk0696, Unk0695)) String := …

  # Lower.rust_generics/1
  pub def rust_generics(p0 Unk0738) String := …

  # Lower.rust_impl/4
  pub def rust_impl(p0 Map(Unk0009, Vec(Unk0010)), protocols Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0674, Unk0673), base_ec Tuple(Unk0696, Unk0695)) String := …

  # Lower.rust_impl_method/6
  pub def rust_impl_method(method Unk0739, sig Unk0740, rust_type String, c Map(Unk0674, Unk0673), copy_recv? Bool, base_ec Tuple(Unk0696, Unk0695)) String := …

  # Lower.rust_lit_type/1
  pub def rust_lit_type(p0 Unk0741) String := …

  # Lower.rust_owned_elem/2
  pub def rust_owned_elem(p0 Option(Unk0017), ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.rust_program/1
  pub def rust_program(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) String := …

  # Lower.rust_proto_body/3
  pub def rust_proto_body(src Unk0742, c Map(Unk0743, Unk0744), ec Unk0745) Unk0746 := …

  # Lower.rust_protocols/4
  pub def rust_protocols(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0747 := …

  # Lower.rust_scrut/2
  pub def rust_scrut(params Unk0748, iso Unk0643) String := …

  # Lower.rust_struct/2
  pub def rust_struct(s Unk0749, p1 Unk0750) String := …

  # Lower.rust_total_shim?/1
  pub def rust_total_shim?(func Map(Unk0669, Vec(Unk0010))) Bool := …

  # Lower.rust_trait/1
  pub def rust_trait(p0 Unk0751) String := …

  # Lower.rust_use/1
  pub def rust_use(p0 Unk0752) String := …

  # Lower.rustify_parametric/2
  pub def rustify_parametric(rust_type String, pinst Vec(Unk0753)) String := …

  # Lower.scalar_literal?/1
  pub def scalar_literal?(p0 Tuple(Unk0196, String)) Bool := …

  # Lower.sig_param/2
  pub def sig_param(p String, self_repr Unk0754) String := …

  # Lower.slice_binders/2
  pub def slice_binders(params Unk0755, pats Vec(Sum2)) Unk0675 := …

  # Lower.slice_elem_vars/1
  pub def slice_elem_vars(p0 Sum2) Vec(Unk0756) := …

  # Lower.slice_var?/2
  pub def slice_var?(p0 Sum1, ec Tuple(Unk0664, Unk0665)) Bool := …

  # Lower.str_lit/1
  pub def str_lit(s Unk0757) String := …

  # Lower.strip_prefix/2
  pub def strip_prefix(rest Vec(Unk0758), p1 Vec(Unk0715)) Tuple(Unk0759, Vec(Unk0758)) := …

  # Lower.struct_pairs/4
  pub def struct_pairs(name Unk0760, labels Vec(Unk0761), args Vec(Option(Unk0017)), smeta Unk0731) Unk0762 := …

  # Lower.subst_assoc/2
  pub def subst_assoc(t String, assoc_rust Vec(Unk0763)) String := …

  # Lower.tail_expr/1
  pub def tail_expr(p0 Unk0764) Unk0764 := …

  # Lower.tail_slice_id?/2
  pub def tail_slice_id?(p0 Option(Unk0017), ec Tuple(Unk0664, Unk0665)) Bool := …

  # Lower.to_elixir/4
  pub def to_elixir(func Map(Unk0669, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), p2 Unk0765, p3 Unk0662) Unk0766 := …

  # Lower.to_rust/6
  pub def to_rust(func Map(Unk0669, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), meta Unk0661, p3 Unk0767, p4 Unk0662, p5 Unk0768) Unk0769 := …

  # Lower.trait_impl_block/4
  pub def trait_impl_block(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0674, Unk0673), base_ec Tuple(Unk0696, Unk0695)) String := …

  # Lower.trait_params/2
  pub def trait_params(param_str String, self_repr Unk0754) String := …

  # Lower.tuple_or_one/2
  pub def tuple_or_one(p0 Vec(Sum2), f Fn(Sum2, String)) String := …

  # Lower.tvar_name?/1
  pub def tvar_name?(t Unk0770) Bool := …

  # Lower.type_idents/1
  pub def type_idents(p0 Unk0771) Vec(Unk0772) := …

  # Lower.type_param_tvars/1
  pub def type_param_tvars(t Unk0773) Unk0774 := …

  # Lower.used_ids/1
  pub def used_ids(ast Vec(Unk0671)) Unk0644 := …

  # Lower.user_type?/2
  pub def user_type?(t Unk0775, ctx Map(Unk0674, Unk0673)) Bool := …

  # Lower.variant_info/2
  pub def variant_info(meta Map(Unk0732, Option(Unk0733)), name Unk0724) Option(Unk0733) := …

  # Lower.variant_lit/2
  pub def variant_lit(info Option(Unk0733), pairs Vec(Unk0776)) Tuple(Unk0196, String) := …

  # Lower.variant_pairs/3
  pub def variant_pairs(info Option(Unk0733), args Vec(Option(Unk0017)), meta Map(Unk0732, Option(Unk0733))) Vec(Unk0776) := …

  # Lower.widen_char_arith/2
  pub def widen_char_arith(p0 Option(Unk0017), cvars Unk0777) Tuple(Unk0196, String) := …

  # Lower.with_chain_rs/4
  pub def with_chain_rs(p0 Vec(Unk0778), body String, _else_rs String, _ec Tuple(Unk0664, Unk0665)) String := …

  # Lower.word_member?/2
  pub def word_member?(str Unk0779, name Unk0723) Bool := …

  # Lower.word_scan/4
  pub def word_scan(p0 Vec(Unk0780), _name Vec(Unk0715), _repl String, _prev Bool) String := …

  # Lower.wrap_char/2
  pub def wrap_char(p0 Tuple(Unk0196, String), _cvars Unk0777) Tuple(Unk0196, String) := …

  # Macro.binders_here/1
  pub def binders_here(p0 Vec(Unk0781)) Vec(Unk0782) := …

  # Macro.build_env/1
  pub def build_env(defs Unk0783) Map(Unk0243, Unk0242) := …

  # Macro.check_portable!/2
  pub def check_portable!(name Unk0784, tmpl Option(Unk0017)) Unk0785 := …

  # Macro.collect_binders/1
  pub def collect_binders(node Vec(Unk0781)) Vec(Unk0782) := …

  # Macro.do_expand/4
  pub def do_expand(_env Map(Unk0243, Unk0242), _ast Option(Unk0017), d Int53, _p Bool) Tuple(Unk0196, String) := …

  # Macro.expand/3
  pub def expand(env Map(Unk0243, Unk0242), ast Option(Unk0017), p2 Vec(Tuple(Unk0786, Bool))) Option(Unk0017) := …

  # Macro.freshen/2
  pub def freshen(tmpl Vec(Unk0781), params Unk0787) Tuple(Unk0196, Vec(Unk0788)) := …

  # Macro.introduces_failable_bind?/1
  pub def introduces_failable_bind?(node Option(Unk0017)) Bool := …

  # Macro.map_node/2
  pub def map_node(p0 Option(Unk0017), f Fn(Option(Unk0017), Tuple(Unk0196, String))) Tuple(Unk0196, String) := …

  # Macro.rename/2
  pub def rename(p0 Vec(Unk0781), ren Map(Unk0789, Vec(Unk0788))) Tuple(Unk0196, Vec(Unk0788)) := …

  # Macro.substitute/2
  pub def substitute(p0 Tuple(Unk0196, Vec(Unk0788)), subst Map(Unk0790, Option(Unk0017))) Option(Unk0017) := …

  # Macro.walk_for_with/1
  pub def walk_for_with(p0 Option(Unk0017)) Tuple(Unk0196, String) := …

  # Opaque.do_erase/2
  pub def do_erase(prog Unk0791, ctx Tuple(Unk0793, Unk0792)) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase/1
  pub def erase(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase_clause/3
  pub def erase_clause(p0 Unk0794, _ctx Unk0795, _env Unk0796) Clause := …

  # Opaque.erase_const/2
  pub def erase_const(p0 Unk0797, p1 Unk0798) Const := …

  # Opaque.erase_ctx/1
  pub def erase_ctx(all Vec(Unk0799)) Tuple(Unk0793, Unk0792) := …

  # Opaque.erase_func/2
  pub def erase_func(p0 Unk0800, p1 Tuple(Unk0793, Unk0792)) Func := …

  # Opaque.erase_mod/2
  pub def erase_mod(p0 Unk0801, ctx Tuple(Unk0793, Unk0792)) Mod := …

  # Opaque.erase_struct/2
  pub def erase_struct(p0 Unk0802, p1 Tuple(Unk0793, Unk0792)) Struct := …

  # Opaque.erase_type/2
  pub def erase_type(p0 Unk0803, p1 Tuple(Unk0793, Unk0792)) Type := …

  # Opaque.erase_variant/2
  pub def erase_variant(p0 Unk0804, names Unk0805) Variant := …

  # Opaque.opaques/1
  pub def opaques(prog Map(Unk0806, Vec(Unk0799))) Vec(Unk0799) := …

  # Opaque.strip/3
  pub def strip(p0 Vec(Unk0807), p1 Unk0808, env Map(Unk0086, Vec(Unk0079))) Vec(Unk0807) := …

  # Opaque.strip_into/3
  pub def strip_into(ast Vec(Unk0807), ctx Unk0808, env Map(Unk0086, Vec(Unk0079))) Vec(Unk0807) := …

  # Opaque.subst/2
  pub def subst(p0 Option(Unk0809), _names Unk0810) Option(Unk0809) := …

  # Opaque.subst_fix/4
  pub def subst_fix(type Option(Unk0809), _names Unk0810, _re Unk0811, p3 Int53) Option(Unk0809) := …

  # PatternLower.add_struct/3
  pub def add_struct(env Tuple(Unk0369, Map(String, String)), name String, fields Vec(String)) Tuple(Unk0369, Map(String, String)) := …

  # PatternLower.lower/2
  pub def lower(pat Sum2, env Map(Unk0374, Unk0375)) Tuple(Unk0812, Bool) := …

  # PatternLower.lower_clause/2
  pub def lower_clause(p0 Unk0813, env Map(Unk0374, Unk0375)) Unk0373 := …

  # PatternLower.lower_list/3
  pub def lower_list(p0 Vec(Sum2), p1 Sum2, _env Map(Unk0374, Unk0375)) Tuple(Unk0812, Bool) := …

  # PatternLower.lower_many/2
  pub def lower_many(ps Vec(Sum2), env Map(Unk0374, Unk0375)) Unk0814 := …

  # PortAnalysis.analyze/1
  pub def analyze(sources Unk0815) Unk0816 := …

  # PortAnalysis.case_arm_sets/1
  pub def case_arm_sets(ast Unk0817) Vec(Unk0818) := …

  # PortAnalysis.clause_head_sets/1
  pub def clause_head_sets(ast Unk0817) Vec(Unk0818) := …

  # PortAnalysis.cluster_sums/1
  pub def cluster_sums(sets Vec(Unk0819)) Unk0535 := …

  # PortAnalysis.collect_errors/2
  pub def collect_errors(ast Unk0820, acc Unk0821) Unk0821 := …

  # PortAnalysis.collect_groups/1
  pub def collect_groups(p0 Unk0822) Vec(Unk0533) := …

  # PortAnalysis.collect_structs/2
  pub def collect_structs(ast Unk0823, acc Unk0824) Unk0824 := …

  # PortAnalysis.dispatch_sets/1
  pub def dispatch_sets(ast Unk0817) Vec(Unk0819) := …

  # PortAnalysis.error_proposal/1
  pub def error_proposal(p0 Unk0825) Unk0826 := …

  # PortAnalysis.error_shape/1
  pub def error_shape(p0 Unk0827) Tuple(Unk0828, Option(Unk0829)) := …

  # PortAnalysis.errors_section/1
  pub def errors_section(data Unk0830) String := …

  # PortAnalysis.head_name_pats/1
  pub def head_name_pats(p0 Unk0831) Tuple(Unk0833, Vec(Unk0832)) := …

  # PortAnalysis.holes_section/1
  pub def holes_section(data Unk0830) String := …

  # PortAnalysis.module_name/1
  pub def module_name(p0 Unk0834) String := …

  # PortAnalysis.module_report/3
  pub def module_report(file Unk0835, ast Unk0834, src Unk0836) Unk0837 := …

  # PortAnalysis.module_stmts/1
  pub def module_stmts(p0 Unk0838) Vec(String) := …

  # PortAnalysis.needs_review?/1
  pub def needs_review?(p0 Unk0839) Bool := …

  # PortAnalysis.param_name_index/1
  pub def param_name_index(mods_groups Vec(Tuple(String, Vec(Unk0533)))) Unk0840 := …

  # PortAnalysis.parse/1
  pub def parse(src Unk0841) Option(Unk0842) := …

  # PortAnalysis.pascal/1
  pub def pascal(atom_str Unk0843) Unk0844 := …

  # PortAnalysis.pattern_structs/1
  pub def pattern_structs(p0 Unk0845) Vec(Unk0846) := …

  # PortAnalysis.reach_note/1
  pub def reach_note(type Unk0847) Unk0848 := …

  # PortAnalysis.short/1
  pub def short(p0 Unk0849) String := …

  # PortAnalysis.sigs_section/1
  pub def sigs_section(data Unk0830) String := …

  # PortAnalysis.src_of/2
  pub def src_of(sources Unk0815, file Unk0850) Unk0836 := …

  # PortAnalysis.summary_section/1
  pub def summary_section(data Unk0830) String := …

  # PortAnalysis.sums_section/1
  pub def sums_section(data Unk0830) String := …

  # PortAnalysis.to_markdown/1
  pub def to_markdown(data Unk0830) Unk0851 := …

  # Pratt.after_paren/2
  pub def after_paren(tokens Vec(Unk0852), p1 Int53) Vec(Unk0852) := …

  # Pratt.assoc/1
  pub def assoc(op Option(Unk0853)) Unk0854 := …

  # Pratt.bp/1
  pub def bp(op Option(Unk0853)) Tuple(Int53, Int53) := …

  # Pratt.climb/3
  pub def climb(lhs Option(Unk0855), tokens Vec(Vec(Vec(Unk0618))), min_bp Int53) Tuple(Option(Unk0855), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.collect_dots/2
  pub def collect_dots(node Tuple(Unk0856, Unk0857), p1 Vec(Vec(Unk0618))) Tuple(Tuple(Unk0856, Unk0857), Vec(Vec(Unk0618))) := …

  # Pratt.desugar_prop/2
  pub def desugar_prop(stmts Vec(Tuple(Unk0859, Unk0858)), depth Int53) Tuple(Unk0860, Vec(Tuple(Unk0859, Unk0858))) := …

  # Pratt.desugar_propagation/1
  pub def desugar_propagation(stmts Vec(Tuple(Unk0859, Unk0858))) Tuple(Unk0860, Vec(Tuple(Unk0859, Unk0858))) := …

  # Pratt.expect_kw/2
  pub def expect_kw(p0 Vec(Vec(Vec(Unk0618))), k String) Vec(Vec(Vec(Unk0618))) := …

  # Pratt.expect_op/2
  pub def expect_op(p0 Vec(Vec(Vec(Unk0618))), o String) Vec(Vec(Vec(Unk0618))) := …

  # Pratt.expect_rbracket/1
  pub def expect_rbracket(p0 Vec(Vec(Vec(Unk0618)))) Vec(Vec(Vec(Unk0618))) := …

  # Pratt.expect_rparen/1
  pub def expect_rparen(p0 Vec(Vec(Vec(Unk0618)))) Vec(Vec(Vec(Unk0618))) := …

  # Pratt.finish_arg/2
  pub def finish_arg(a Unk0861, p1 Vec(Vec(Vec(Unk0618)))) Tuple(Vec(Unk0861), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.here/1
  pub def here(p0 Vec(Unk0862)) String := …

  # Pratt.int_of/1
  pub def int_of(n Unk0863) Vec(Tuple(Unk0865, Unk0864)) := …

  # Pratt.lambda_ahead?/1
  pub def lambda_ahead?(p0 Vec(Unk0852)) Bool := …

  # Pratt.level/1
  pub def level(op Option(Unk0853)) Unk0866 := …

  # Pratt.opinfo/1
  pub def opinfo(op Option(Unk0853)) Unk0867 := …

  # Pratt.parse/1
  pub def parse(ast String) Option(Unk0017) := …

  # Pratt.parse_args/1
  pub def parse_args(p0 Vec(Vec(Vec(Vec(Unk0618))))) Tuple(Vec(Unk0861), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.parse_arms/2
  pub def parse_arms(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Unk0868)) Tuple(Vec(Unk0868), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_block/1
  pub def parse_block(tokens Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0860, Vec(Tuple(Unk0859, Unk0858))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_body/1
  pub def parse_body(ast Option(Unk0017)) Option(Unk0017) := …

  # Pratt.parse_capture/1
  pub def parse_capture(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_case/1
  pub def parse_case(tokens Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_expr/2
  pub def parse_expr(tokens Vec(Vec(Vec(Unk0618))), min_bp Int53) Tuple(Option(Unk0855), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_if/1
  pub def parse_if(tokens Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_lambda/1
  pub def parse_lambda(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_list/2
  pub def parse_list(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Unk0870)) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_map/2
  pub def parse_map(p0 Vec(Vec(Vec(Vec(Unk0618)))), acc Vec(Tuple(Unk0865, Unk0864))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.parse_param/1
  pub def parse_param(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0871, Option(Unk0872)), Vec(Vec(Unk0618))) := …

  # Pratt.parse_params/1
  pub def parse_params(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Vec(Unk0873), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_pat/1
  pub def parse_pat(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0874, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_pat_args/2
  pub def parse_pat_args(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Unk0875)) Tuple(Vec(Unk0875), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_pat_fields/2
  pub def parse_pat_fields(p0 Vec(Vec(Vec(Vec(Unk0618)))), acc Vec(Tuple(Unk0876, Unk0877))) Tuple(Vec(Tuple(Unk0876, Unk0877)), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.parse_pat_list/2
  pub def parse_pat_list(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Unk0878)) Tuple(Tuple(Unk0874, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_pat_map/2
  pub def parse_pat_map(p0 Vec(Vec(Vec(Vec(Unk0618)))), acc Vec(Tuple(Unk0865, Unk0864))) Tuple(Tuple(Unk0874, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.parse_pat_tuple/2
  pub def parse_pat_tuple(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Tuple(Unk0865, Unk0864))) Tuple(Tuple(Unk0874, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_path/1
  pub def parse_path(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0856, Unk0857), Vec(Vec(Unk0618))) := …

  # Pratt.parse_pats/1
  pub def parse_pats(str String) Vec(Unk0879) := …

  # Pratt.parse_pats/2
  pub def parse_pats(tokens Vec(Vec(Vec(Unk0618))), acc Vec(Unk0879)) Vec(Unk0879) := …

  # Pratt.parse_postfix/2
  pub def parse_postfix(node Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), p1 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_prefix/1
  pub def parse_prefix(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_primary/1
  pub def parse_primary(p0 Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_stmt/1
  pub def parse_stmt(p0 Vec(Vec(Vec(Vec(Unk0618))))) Tuple(Tuple(Unk0880, Unk0881), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_stmts/2
  pub def parse_stmts(p0 Vec(Vec(Vec(Vec(Unk0618)))), acc Vec(Unk0882)) Tuple(Vec(Unk0882), Vec(Vec(Vec(Vec(Unk0618))))) := …

  # Pratt.parse_tuple/2
  pub def parse_tuple(p0 Vec(Vec(Vec(Unk0618))), acc Vec(Tuple(Unk0865, Unk0864))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_type/1
  pub def parse_type(p0 Vec(Vec(Vec(Unk0618)))) Tuple(String, Vec(Vec(Unk0618))) := …

  # Pratt.parse_type_args/2
  pub def parse_type_args(tokens Vec(Vec(Vec(Unk0618))), acc Vec(Unk0883)) Tuple(Vec(Unk0883), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_with/1
  pub def parse_with(tokens Vec(Vec(Vec(Unk0618)))) Tuple(Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.parse_with_clauses/2
  pub def parse_with_clauses(tokens Vec(Vec(Vec(Unk0618))), acc Vec(Tuple(Unk0885, Unk0884))) Tuple(Vec(Tuple(Unk0885, Unk0884)), Vec(Vec(Vec(Unk0618)))) := …

  # Pratt.pascal?/1
  pub def pascal?(s Unk0886) Bool := …

  # Pratt.peek_infix/1
  pub def peek_infix(p0 Vec(Vec(Vec(Unk0618)))) Option(Unk0853) := …

  # Pratt.same_level_root?/2
  pub def same_level_root?(p0 Option(Unk0855), op Option(Unk0853)) Bool := …

  # Pratt.sexpr/1
  pub def sexpr(p0 Option(Unk0017)) String := …

  # Pratt.sexpr_pat/1
  pub def sexpr_pat(p0 Unk0887) String := …

  # Pratt.sexpr_stmt/1
  pub def sexpr_stmt(p0 Unk0888) String := …

  # Pratt.str_interp/1
  pub def str_interp(parts Vec(Unk0889)) Tuple(Unk0869, Vec(Tuple(Unk0865, Unk0864))) := …

  # Pratt.tok_desc/1
  pub def tok_desc(p0 Unk0862) String := …

  # Prelude.with_prelude/1
  pub def with_prelude(types Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Type) := …

  # Prim.normalize/1
  pub def normalize(p0 String) Option(Unk0017) := …

  # Protocol.check_assoc!/2
  pub def check_assoc!(protocols Vec(Unk0219), impl_decls Vec(Unk0219)) Unk0890 := …

  # Protocol.check_impl/3
  pub def check_impl(p0 Unk0891, protocols Unk0892, reg Unk0893) Unk0894 := …

  # Protocol.check_no_overlap/3
  pub def check_no_overlap(impls Vec(Unk0895), reg Unk0893, targets Unk0896) Unk0897 := …

  # Protocol.dispatcher/4
  pub def dispatcher(proto Unk0898, sig Unk0899, impls Vec(Unk0895), reg Unk0893) Vec(Unk0900) := …

  # Protocol.dispatcher_params/2
  pub def dispatcher_params(sig_params Unk0901, vars Vec(String)) Unk0902 := …

  # Protocol.expand/5
  pub def expand(protocols Unk0892, impls Vec(Unk0895), p2 Unk0319, p3 Unk0320, p4 Unk0321) Vec(Unk0322) := …

  # Protocol.guard_for!/3
  pub def guard_for!(type String, proto Unk0898, reg Unk0893) Unk0903 := …

  # Protocol.impl_methods/2
  pub def impl_methods(p0 Unk0895, protocols Unk0892) Vec(Unk0322) := …

  # Protocol.mangle/3
  pub def mangle(proto Unk0904, type Unk0905, method Unk0906) String := …

  # Protocol.param_type/1
  pub def param_type(p Unk0907) Unk0908 := …

  # Protocol.registry/2
  pub def registry(types Unk0909, structs Vec(Unk0910)) Unk0893 := …

  # Protocol.runtime_dispatch_target?/1
  pub def runtime_dispatch_target?(p0 Unk0896) Bool := …

  # Protocol.subst_self/2
  pub def subst_self(p0 Unk0911, _type Unk0912) Option(Unk0913) := …

  # Protocol.sum_guard/1
  pub def sum_guard(variants Unk0914) String := …

  # Protocol.tag_disjunction/2
  pub def tag_disjunction(variants Vec(Unk0915), lhs Unk0916) String := …

  # Range.check/3
  pub def check(lo Unk0917, hi Unk0918, a Sum1) Sum1 := …

  # Range.expand_of/2
  pub def expand_of(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Range.lit/1
  pub def lit(n Unk0919) Sum1 := …

  # Range.table/1
  pub def table(ranges Vec(Map(Unk0009, Vec(Unk0010)))) Map(Unk0018, Unk0019) := …

  # Range.walk/2
  pub def walk(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Reach.all_emittable?/2
  pub def all_emittable?(f Map(Unk0921, Vec(Unk0920)), pctx Unk0922) Bool := …

  # Reach.all_funcs/1
  pub def all_funcs(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Reach.analyze/1
  pub def analyze(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0923 := …

  # Reach.atom_prim_blocker/0
  pub def atom_prim_blocker() Unk0924 := …

  # Reach.bare_atom_blocker/0
  pub def bare_atom_blocker() Unk0924 := …

  # Reach.build_default/0
  pub def build_default() Option(Unk0925) := …

  # Reach.builder_tail_ok?/2
  pub def builder_tail_ok?(f Map(Unk0921, Vec(Unk0920)), generics Unk0926) Bool := …

  # Reach.check_contracts/2
  pub def check_contracts(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), p1 Option(Unk0925)) Tuple(Unk0927, String) := …

  # Reach.classify/3
  pub def classify(p0 Sum1, _modnames Unk0928, p2 Tuple(Vec(Unk0924), Unk0929)) Tuple(Vec(Unk0924), Unk0929) := …

  # Reach.collect_ctors/2
  pub def collect_ctors(p0 Sum1, ctors Map(Unk0931, Unk0930)) Vec(Tuple(Unk0933, Unk0932)) := …

  # Reach.conc_erl?/2
  pub def conc_erl?(m String, fun Unk0934) Bool := …

  # Reach.contract_message/1
  pub def contract_message(violations Vec(Unk0935)) String := …

  # Reach.core/2
  pub def core(src Unk0936, parser Fn(Unk0937, Unk0938)) Sum1 := …

  # Reach.ctor_aligned?/2
  pub def ctor_aligned?(p0 Tuple(Unk0933, Unk0932), f Map(Unk0921, Vec(Unk0920))) Bool := …

  # Reach.deep/1
  pub def deep(t Vec(Unk0939)) Vec(Unk0940) := …

  # Reach.emittable_parametric?/1
  pub def emittable_parametric?(t Unk0941) Unk0942 := …

  # Reach.ffi/2
  pub def ffi(construct String, conc? Bool) Unk0924 := …

  # Reach.find_atom_ordering/1
  pub def find_atom_ordering(p0 Vec(Unk0939)) Vec(Unk0940) := …

  # Reach.fixpoint/2
  pub def fixpoint(facts Unk0943, table Map(Unk0945, Unk0944)) Map(Unk0945, Unk0944) := …

  # Reach.fn_type_blocker/0
  pub def fn_type_blocker() Unk0924 := …

  # Reach.func_symbol_violations/1
  pub def func_symbol_violations(f Unk0946) Vec(Unk0940) := …

  # Reach.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.gate!/2
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), default Option(Unk0925)) Symbol := …

  # Reach.int_blocker/0
  pub def int_blocker() Unk0924 := …

  # Reach.js_wide_int?/1
  pub def js_wide_int?(t Unk0947) Bool := …

  # Reach.mix_default/0
  pub def mix_default() Unk0948 := …

  # Reach.parametric_blocker/0
  pub def parametric_blocker() Unk0924 := …

  # Reach.parametric_constructions/2
  pub def parametric_constructions(f Map(Unk0921, Vec(Unk0920)), ctors Map(Unk0931, Unk0930)) Vec(Tuple(Unk0933, Unk0932)) := …

  # Reach.parametric_ctx/2
  pub def parametric_ctx(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), funs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0922 := …

  # Reach.parametric_rs_ok?/2
  pub def parametric_rs_ok?(f Map(Unk0921, Vec(Unk0920)), pctx Unk0922) Bool := …

  # Reach.parametric_type?/1
  pub def parametric_type?(t Unk0949) Bool := …

  # Reach.pascal?/1
  pub def pascal?(s Unk0950) Bool := …

  # Reach.ref_blocker/0
  pub def ref_blocker() Unk0924 := …

  # Reach.result_value_blocker/0
  pub def result_value_blocker() Unk0924 := …

  # Reach.scan/3
  pub def scan(p0 Sum1, modnames Unk0928, p2 Tuple(Vec(Unk0924), Unk0929)) Tuple(Vec(Unk0924), Unk0929) := …

  # Reach.scan_func/3
  pub def scan_func(f Map(Unk0921, Vec(Unk0920)), modnames Unk0928, pctx Unk0922) Tuple(Vec(Unk0924), Unk0929) := …

  # Reach.sig_idents/1
  pub def sig_idents(f Map(Unk0952, Vec(Unk0951))) Unk0953 := …

  # Reach.sig_uses_fn_type?/1
  pub def sig_uses_fn_type?(f Map(Unk0921, Vec(Unk0920))) Bool := …

  # Reach.symbol_lint!/1
  pub def symbol_lint!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.tail_calls_generic?/2
  pub def tail_calls_generic?(p0 Unk0954, generics Unk0926) Bool := …

  # Reach.tvar?/1
  pub def tvar?(t Unk0955) Unk0956 := …

  # Reach.type_has_tvar?/1
  pub def type_has_tvar?(t Unk0957) Bool := …

  # Reach.type_idents/1
  pub def type_idents(t Unk0957) Vec(Unk0958) := …

  # Reach.uses_parametric?/2
  pub def uses_parametric?(f Map(Unk0921, Vec(Unk0920)), names Unk0959) Bool := …

  # Reach.validate_default/1
  pub def validate_default(p0 Option(Unk0925)) Option(Unk0925) := …

  # Reach.wide_prim_blocker/0
  pub def wide_prim_blocker() Unk0924 := …

  # Reach.width_blocker/0
  pub def width_blocker() Unk0924 := …

  # Repl.accumulate_line/2
  pub def accumulate_line(line String, p1 Unk0960) Tuple(Vec(String), String) := …

  # Repl.bind_env/2
  pub def bind_env(binds Vec(Unk0961), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Map(Unk0086, Option(Unk0962)) := …

  # Repl.bind_with_type/4
  pub def bind_with_type(s Session, input String, name String, type Option(Unk0962)) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.candidate_pool/2
  pub def candidate_pool(p0 Unk0964, _s Session) Vec(Unk0965) := …

  # Repl.common_prefix/2
  pub def common_prefix(a Unk0966, b Unk0967) String := …

  # Repl.common_prefix/3
  pub def common_prefix(p0 Unk0966, p1 Unk0967, acc String) String := …

  # Repl.complete/2
  pub def complete(before_cursor String, p1 Unk0968) Tuple(Vec(Unk0969), String) := …

  # Repl.continuation/2
  pub def continuation(_word String, p1 Vec(Unk0969)) String := …

  # Repl.decl_names/1
  pub def decl_names(input String) Unk0970 := …

  # Repl.describe/1
  pub def describe(p0 Unk0971) Unk0972 := …

  # Repl.eval/2
  pub def eval(p0 Unk0973, input String) Unk0974 := …

  # Repl.eval_bind/4
  pub def eval_bind(s Session, input String, name String, rhs Option(Unk0017)) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.eval_decl/2
  pub def eval_decl(s Tuple(Unk0975, Vec(Tuple(Unk0970, Unk0976))), input String) Tuple(Tuple(Unk0977, Unk0970), Unk0978) := …

  # Repl.eval_expr/2
  pub def eval_expr(s Session, input String) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.eval_stmt/2
  pub def eval_stmt(s Session, input String) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.flush_entries/1
  pub def flush_entries(p0 Unk0979) Vec(Unk0980) := …

  # Repl.infer_or_unknown/3
  pub def infer_or_unknown(ast Option(Unk0017), env Map(Unk0086, Option(Unk0962)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0962) := …

  # Repl.info/1
  pub def info(p0 Session) Unk0981 := …

  # Repl.longest_common_prefix/1
  pub def longest_common_prefix(p0 Vec(Unk0982)) Unk0982 := …

  # Repl.program/3
  pub def program(units Vec(Tuple(Unk0970, Unk0976)), binds Vec(Tuple(String, Unk0983)), expr_src String) String := …

  # Repl.reload/2
  pub def reload(s Tuple(Unk0975, Vec(Tuple(Unk0970, Unk0976))), src String) Symbol := …

  # Repl.render/1
  pub def render(p0 Unk0984) String := …

  # Repl.run/4
  pub def run(s Session, binds Vec(Tuple(String, Unk0983)), units Vec(Tuple(Unk0970, Unk0976)), expr_src String) Tuple(Unk0985, Unk0986) := …

  # Repl.safe_decl/1
  pub def safe_decl(units Vec(Tuple(Unk0970, Unk0976))) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Repl.safe_infer/3
  pub def safe_infer(ast Option(Unk0017), env Map(Unk0086, Option(Unk0962)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0962) := …

  # Repl.safe_infer_input/3
  pub def safe_infer_input(input String, env Map(Unk0086, Option(Unk0962)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0962) := …

  # Repl.safe_parse_body/1
  pub def safe_parse_body(input String) Tuple(Unk0987, Option(Unk0017)) := …

  # Repl.scan_count/2
  pub def scan_count(input String, regex Unk0988) Unk0989 := …

  # Repl.session_ic/1
  pub def session_ic(p0 Session) Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))) := …

  # Repl.type_of/2
  pub def type_of(p0 Unk0990, input String) Option(Unk0962) := …

  # Repl.units_src/1
  pub def units_src(units Vec(Tuple(Unk0970, Unk0976))) String := …

  # SelfHost.badge/1
  pub def badge(p0 Unk0991) String := …

  # SelfHost.composition/0
  pub def composition() Unk0992 := …

  # SelfHost.count/1
  pub def count(status Unk0993) Int53 := …

  # SelfHost.evidence/1
  pub def evidence(p0 Unk0994) String := …

  # SelfHost.external_host_calls/1
  pub def external_host_calls(prog Map(Unk0995, Vec(Map(Unk0997, Vec(Unk0996))))) Vec(Unk0998) := …

  # SelfHost.ffi_ledger/0
  pub def ffi_ledger() Unk0999 := …

  # SelfHost.passes/0
  pub def passes() Unk1000 := …

  # SelfHost.sibling_compose_call?/2
  pub def sibling_compose_call?(construct Unk1001, siblings Unk1002) Bool := …

  # SelfHost.stages/0
  pub def stages() Unk1003 := …

  # SelfHost.status_markdown/1
  pub def status_markdown(stages Vec(Unk1004)) String := …

  # Shadow.ded_bind/5
  pub def ded_bind(n Unk1005, t Bool, e Vec(Unk1006), p3 Unk1007, fresh Fn(Unk1010, Unk1008, Unk1009)) Unk1011 := …

  # Shadow.ded_block/4
  pub def ded_block(stmts Vec(Unk1012), r Map(Unk1014, Unk1013), ver Unk1015, fresh Fn(Unk1010, Unk1008, Unk1009)) Vec(Unk0547) := …

  # Shadow.ded_expr/3
  pub def ded_expr(p0 Vec(Unk1006), r Map(Unk1014, Unk1013), _fresh Fn(Unk1010, Unk1008, Unk1009)) Vec(Unk1006) := …

  # Shadow.dedup/3
  pub def dedup(stmts Vec(Unk1012), params Vec(Unk0550), fresh Fn(Unk1010, Unk1008, Unk1009)) Vec(Unk0547) := …

  # Shadow.pat_var_names/1
  pub def pat_var_names(p0 Sum2) Vec(Unk1016) := …

  # ShowStdlib.module/0
  pub def module() Unk0262 := …

  # Test.run/2
  pub def run(src String, p1 Unk1017) Unk1018 := …

  # Tour.build_cell/1
  pub def build_cell(p0 Unk1019) Unk1020 := …

  # Tour.build_reach_example/1
  pub def build_reach_example(p0 Unk1021) Unk1022 := …

  # Tour.elixir_module/1
  pub def elixir_module(src String) Unk1023 := …

  # Tour.encode/2
  pub def encode(map Vec(Unk1024), indent Int53) String := …

  # Tour.encode_string/1
  pub def encode_string(s Vec(Unk1024)) String := …

  # Tour.generate/0
  pub def generate() Unk1025 := …

  # Tour.reach_map/1
  pub def reach_map(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk1026 := …

  # Transpile.add_clause/2
  pub def add_clause(open Tuple(Unk1027, Vec(Unk1028)), clause Unk1028) Option(Unk1029) := …

  # Transpile.build_clause/2
  pub def build_clause(head Unk1030, kw Unk1031) Unk1028 := …

  # Transpile.case_arm/1
  pub def case_arm(p0 Unk1032) String := …

  # Transpile.classify/1
  pub def classify(p0 String) Tuple(Unk1033, String) := …

  # Transpile.close_group/2
  pub def close_group(acc Vec(Unk1034), p1 Unk1034) Vec(Unk1034) := …

  # Transpile.def_groups/1
  pub def def_groups(stmts Vec(String)) Vec(Unk1034) := …

  # Transpile.escape/1
  pub def escape(s Unk1035) Unk1036 := …

  # Transpile.escape_lit/1
  pub def escape_lit(s Unk1037) String := …

  # Transpile.flush/2
  pub def flush(p0 Unk1038, _sigmap Map(Tuple(Unk1040, Unk1039), Bool)) Vec(String) := …

  # Transpile.hole_sig?/1
  pub def hole_sig?(p0 Unk1041) Bool := …

  # Transpile.infer_program/1
  pub def infer_program(ast Unk1042) Tuple(Unk1043, Vec(String)) := …

  # Transpile.infer_report/1
  pub def infer_report(source Unk1044) Unk1045 := …

  # Transpile.infer_sigs/1
  pub def infer_sigs(p0 Unk1042) Unk1043 := …

  # Transpile.inferred/1
  pub def inferred(source Unk0836) Tuple(Unk1043, Vec(String)) := …

  # Transpile.max_placeholder/1
  pub def max_placeholder(p0 Vec(Unk1046)) Int53 := …

  # Transpile.mod_str/1
  pub def mod_str(p0 Unk1047) String := …

  # Transpile.module_groups/1
  pub def module_groups(src Unk1048) Tuple(String, Unk1049) := …

  # Transpile.moduledoc_lines/1
  pub def moduledoc_lines(text Unk1050) Vec(String) := …

  # Transpile.name_str/1
  pub def name_str(n Unk1051) Unk1052 := …

  # Transpile.new_group/3
  pub def new_group(vis Unk1053, clause Unk1028, doc Option(Unk1054)) Option(Unk1029) := …

  # Transpile.one_line/1
  pub def one_line(s Unk1055) Unk1056 := …

  # Transpile.prime_xmod/1
  pub def prime_xmod(sources Unk1057) Unk1058 := …

  # Transpile.rank/1
  pub def rank(entries Unk1059) Unk1060 := …

  # Transpile.render_clause/2
  pub def render_clause(kw String, c Unk1061) String := …

  # Transpile.render_items/2
  pub def render_items(stmts Vec(String), sigmap Map(Tuple(Unk1040, Unk1039), Bool)) Vec(String) := …

  # Transpile.same_group?/3
  pub def same_group?(open Unk1062, vis Unk1063, clause Unk1028) Bool := …

  # Transpile.short_name/1
  pub def short_name(p0 Unk1047) String := …

  # Transpile.sibling_module?/2
  pub def sibling_module?(p0 Unk1064, m String) Bool := …

  # Transpile.simple?/1
  pub def simple?(p0 Vec(Unk1065)) Bool := …

  # Transpile.snippet/1
  pub def snippet(node Unk1047) String := …

  # Transpile.stdlib_map/0
  pub def stdlib_map() Unk0534 := …

  # Transpile.string_part/1
  pub def string_part(s Unk1037) Tuple(Unk1066, String) := …

  # Transpile.string_parts/1
  pub def string_parts(segments Unk1067) Unk1068 := …

  # Transpile.subst_ph/2
  pub def subst_ph(p0 Vec(Unk1069), ps Unk1070) Vec(Unk1069) := …

  # Transpile.toplevel/3
  pub def toplevel(p0 Unk1071, sigmap Unk1072, types Vec(String)) Vec(String) := …

  # Transpile.transpile/2
  pub def transpile(source Unk1073, p1 Unk1074) Unk1075 := …

  # Transpile.transpile_with_stats/2
  pub def transpile_with_stats(source Unk1073, p1 Unk1076) Tuple(Unk1075, Unk1077) := …

  # Transpile.underscore_var/1
  pub def underscore_var(name Unk1078) String := …

  # Transpile.var?/1
  pub def var?(p0 Unk1079) Bool := …

  # Transpile.var_name/1
  pub def var_name(p0 Unk1047) String := …
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
| `Unk0009` | 74 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.compile/5:p0`, `Lower.compile_beam/4:p0`, `Lower.compile_elixir/4:p0`, `Lower.parametric_param_map/1:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0010` | 92 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.check!/2:p0`, `Lower.compile/5:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p0`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p0`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.ex_doc/2:p0`, `Lower.ex_typespec/1:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.fn_all_tvars/3:ret`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_param_map/1:p0`, `Lower.parametric_used?/2:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rs_doc/2:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p0`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0011` | 3 | `Beam.beam_for/5:ret`, `Beam.compile/2:ret`, `Beam.compile_ir/2:ret` |
| `Unk0012` | 2 | `Beam.beam_func/1:p0`, `Beam.beam_func/1:ret` |
| `Unk0013` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0014` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0015` | 1 | `Beam.bin_seg/1:ret` |
| `Unk0016` | 18 | `Beam.bind_var/2:p1`, `Beam.bind_var/2:ret`, `Beam.block_forms/2:p1`, `Beam.body_forms/3:p1`, `Beam.body_seq/2:p1`, `Beam.bump_var/1:p0`, `Beam.bump_var/1:ret`, `Beam.else_dispatch/3:p2`, `Beam.expr_form/2:p1`, `Beam.guard_form/2:p1`, `Beam.i64_overflow/4:p3`, `Beam.pat_vars/2:p1`, `Beam.pat_vars/2:ret`, `Beam.remote_call/4:p3`, `Beam.stmt_form/2:p1`, `Beam.stmt_form/2:ret`, `Beam.var_atom/1:ret`, `Beam.with_form/5:p3` |
| `Unk0017` | 84 | `Beam.body_forms/3:p0`, `Beam.body_seq/2:p0`, `Beam.cons/3:p2`, `Beam.expr_form/2:p0`, `Beam.guard_core/1:ret`, `Beam.guard_form/2:p0`, `Beam.i64_overflow/4:p1`, `Beam.i64_overflow/4:p2`, `Beam.remote_call/4:p2`, `Beam.with_form/5:p1`, `Check.ann_each/3:p0`, `Check.annotate/3:p0`, `Check.bind_mismatch/5:p2`, `Check.body_literal_adopts?/2:p0`, `Check.call_bound_error/5:p1`, `Check.called_ret_with/4:p2`, `Check.const_int/1:p0`, `Check.infer/3:p0`, `Check.infer_tail/3:p0`, `Check.label_error/1:p0`, `Check.label_error_children/1:p0`, `Check.list_elems/1:p0`, `Check.lit_expr_adopts?/2:p0`, `Check.lit_range_error/3:p0`, `Check.num_mix_error/5:p1`, `Check.num_mix_error/5:p2`, `Check.oor_scan/5:p0`, `Check.scan_bound_calls/4:p0`, `Check.scan_num_mix/3:p0`, `Check.scan_num_mix_children/3:p0`, `Check.walk_children/4:p0`, `Comptime.fold/1:p0`, `Core.from_expr/1:p0`, `Core.from_expr/1:ret`, `Core.from_pairs/1:ret`, `Core.from_stmt/1:ret`, `Core.from_tail/1:ret`, `Exhaustiveness.body_core/1:p0`, `Exhaustiveness.body_core/1:ret`, `Interp.resolve/4:ret`, `Interp.stringify/3:p0`, `JS.clause_return/3:p0`, `JS.guarded_return/4:p0`, `JVM.clause_value/2:p0`, `Lower.case_guard/3:p0`, `Lower.coerce_string_ast/2:p0`, `Lower.coerce_string_branch/2:p0`, `Lower.emit/3:p0`, `Lower.emit_ast/2:p0`, `Lower.insert_borrows/4:p0`, `Lower.p/4:p0`, `Lower.resolve_consts/2:p0`, `Lower.resolve_rust_pats/2:p0`, `Lower.resolve_structs/2:p0`, `Lower.resolve_variants/2:p0`, `Lower.result_payload/3:p0`, `Lower.rust_case/4:p0`, `Lower.rust_case/4:p2`, `Lower.rust_owned_elem/2:p0`, `Lower.struct_pairs/4:p2`, `Lower.tail_slice_id?/2:p0`, `Lower.variant_pairs/3:p1`, `Lower.widen_char_arith/2:p0`, `Macro.check_portable!/2:p1`, `Macro.do_expand/4:p1`, `Macro.expand/3:p1`, `Macro.expand/3:ret`, `Macro.introduces_failable_bind?/1:p0`, `Macro.map_node/2:p0`, `Macro.map_node/2:p1`, `Macro.substitute/2:p1`, `Macro.substitute/2:ret`, `Macro.walk_for_with/1:p0`, `Pratt.parse/1:ret`, `Pratt.parse_body/1:p0`, `Pratt.parse_body/1:ret`, `Pratt.sexpr/1:p0`, `Prim.normalize/1:ret`, `Range.expand_of/2:p0`, `Range.walk/2:p0`, `Repl.eval_bind/4:p3`, `Repl.infer_or_unknown/3:p0`, `Repl.safe_infer/3:p0`, `Repl.safe_parse_body/1:ret` |
| `Unk0018` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0019` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0020` | 1 | `Beam.clause_form/2:p0` |
| `Unk0021` | 1 | `Beam.clause_form/2:ret` |
| `Unk0022` | 21 | `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.load_ir/2:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Doctest.module_doc_strings/1:p0`, `Lower.rust_program/1:p0`, `Opaque.erase/1:p0`, `Reach.all_funcs/1:p0`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
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
| `Unk0046` | 1 | `Beam.pascal?/1:p0` |
| `Unk0047` | 1 | `Beam.remote_call/4:p0` |
| `Unk0048` | 1 | `Beam.stmt_form/2:p0` |
| `Unk0049` | 1 | `Beam.str_form/1:p0` |
| `Unk0050` | 1 | `Beam.sum_form/2:p0` |
| `Unk0051` | 1 | `Beam.sum_form/2:ret` |
| `Unk0052` | 1 | `Beam.with_form/5:p0` |
| `Unk0053` | 7 | `CLI.check/1:p0`, `CLI.diff/1:p0`, `CLI.in_place/1:p0`, `CLI.print_diff/3:p0`, `CLI.read/1:p0`, `CLI.to_stdout/1:p0`, `CLI.unified_diff/3:p0` |
| `Unk0054` | 1 | `CLI.diff/1:ret` |
| `Unk0055` | 1 | `CLI.each/2:p0` |
| `Unk0056` | 1 | `CLI.each/2:p1` |
| `Unk0057` | 1 | `CLI.each/2:p1` |
| `Unk0058` | 1 | `CLI.each/2:ret` |
| `Unk0059` | 1 | `CLI.in_place/1:ret` |
| `Unk0060` | 1 | `CLI.main/1:ret` |
| `Unk0061` | 2 | `CLI.print_diff/3:p1`, `CLI.unified_diff/3:p1` |
| `Unk0062` | 2 | `CLI.print_diff/3:p2`, `CLI.unified_diff/3:p2` |
| `Unk0063` | 1 | `CLI.print_diff/3:ret` |
| `Unk0064` | 1 | `CLI.read/1:ret` |
| `Unk0065` | 1 | `CLI.to_stdout/1:ret` |
| `Unk0066` | 1 | `Capability.count_block/3:p0` |
| `Unk0067` | 2 | `Capability.count_block/3:p1`, `Capability.count_uses/2:p1` |
| `Unk0068` | 11 | `Capability.count_block/3:p2`, `Capability.count_block/3:ret`, `Capability.count_uses/1:ret`, `Capability.count_uses/2:ret`, `Capability.max_merge/2:p0`, `Capability.max_merge/2:p1`, `Capability.max_merge/2:ret`, `Capability.merge/2:p0`, `Capability.merge/2:p1`, `Capability.merge/2:ret`, `Capability.verdict/2:p1` |
| `Unk0069` | 4 | `Capability.count_uses/1:p0`, `Capability.count_uses/2:p0`, `Capability.lin_check/2:p1`, `Capability.lin_check_block/3:p2` |
| `Unk0070` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0071` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0072` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0073` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0074` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0075` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0076` | 1 | `Capability.lin_check_block/3:p1` |
| `Unk0077` | 1 | `Capability.pat_vars/1:p0` |
| `Unk0078` | 1 | `Capability.pat_vars/1:ret` |
| `Unk0079` | 136 | `Check.abstract_cast_ret/3:p0`, `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p1`, `Check.abstract_op_type/4:p2`, `Check.abstract_op_type/4:p3`, `Check.adoptable_int?/1:p0`, `Check.ann_each/3:p1`, `Check.ann_each/3:p2`, `Check.ann_each/3:ret`, `Check.ann_stmts/3:p1`, `Check.ann_stmts/3:p2`, `Check.ann_stmts/3:ret`, `Check.annotate/3:p1`, `Check.annotate/3:p2`, `Check.annotate/3:ret`, `Check.arith_type/4:p2`, `Check.arith_type/4:p3`, `Check.assignable?/2:p0`, `Check.assignable?/2:p1`, `Check.bind_mismatch/5:p1`, `Check.bind_mismatch/5:p3`, `Check.bind_mismatch/5:p4`, `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.body_literal_adopts?/2:p1`, `Check.branch_join/1:p0`, `Check.branch_join/1:ret`, `Check.build_fn/2:p1`, `Check.call_bound_error/5:p0`, `Check.call_bound_error/5:p2`, `Check.call_bound_error/5:p3`, `Check.call_bound_error/5:p4`, `Check.called_ret/2:p0`, `Check.called_ret/2:p1`, `Check.called_ret/2:ret`, `Check.called_ret_with/4:p0`, `Check.called_ret_with/4:p1`, `Check.called_ret_with/4:p3`, `Check.called_ret_with/4:ret`, `Check.check_bind_stmts/3:p1`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.clause_env/3:ret`, `Check.concrete_type?/1:p0`, `Check.concretize/1:ret`, `Check.conservative/1:p0`, `Check.conservative/1:ret`, `Check.ctor_type/2:p0`, `Check.ctor_type/2:p1`, `Check.ctor_type/2:ret`, `Check.deplaceholder/1:ret`, `Check.first_bound_violation/4:p0`, `Check.first_bound_violation/4:p2`, `Check.first_bound_violation/4:p3`, `Check.float_type?/1:p0`, `Check.fn_ret/1:p0`, `Check.fn_type?/1:p0`, `Check.has_tvar?/1:p0`, `Check.infer/3:p1`, `Check.infer/3:p2`, `Check.infer/3:ret`, `Check.infer_block/4:p1`, `Check.infer_block/4:p2`, `Check.infer_block/4:p3`, `Check.infer_block/4:ret`, `Check.infer_tail/3:p1`, `Check.infer_tail/3:p2`, `Check.infer_tail/3:ret`, `Check.instantiate_ret/2:p1`, `Check.instantiate_ret/2:ret`, `Check.int_type?/1:p0`, `Check.join/2:p0`, `Check.join/2:p1`, `Check.join_all/1:ret`, `Check.list_elem/1:p0`, `Check.list_of/1:p0`, `Check.lit_expr_adopts?/2:p1`, `Check.literal_adopts?/2:p1`, `Check.missing_impl/5:p0`, `Check.missing_impl/5:p2`, `Check.missing_impl/5:p4`, `Check.mixed_num?/2:p0`, `Check.mixed_num?/2:p1`, `Check.narrow/4:p1`, `Check.narrow/4:p2`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_kind/1:p0`, `Check.num_lub/2:p0`, `Check.num_lub/2:p1`, `Check.num_mix_error/5:p3`, `Check.num_mix_error/5:p4`, `Check.parametric_join/2:p0`, `Check.parametric_join/2:p1`, `Check.parse_parametric/1:p0`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_base/2:p1`, `Check.range_bind/6:p1`, `Check.range_bind/6:p4`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p0`, `Check.resolve_range/2:p1`, `Check.resolve_range/2:ret`, `Check.scan_bound_calls/4:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_bound_calls/4:p3`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p1`, `Check.scan_num_mix_children/3:p2`, `Check.unify/2:p0`, `Check.unify/2:p1`, `Check.unify/2:ret`, `Check.walk_children/4:p1`, `Check.walk_children/4:p2`, `Check.walk_children/4:p3`, `Decl.clause_env/2:ret`, `Interp.int_type?/1:p0`, `Interp.resolve/4:p1`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p1`, `Interp.resolve_part/4:p2`, `Interp.stringify/3:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0080` | 1 | `Check.abstract_cast_ret/3:p1` |
| `Unk0081` | 38 | `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p3`, `Check.ann_each/3:p2`, `Check.ann_stmts/3:p2`, `Check.annotate/3:p2`, `Check.bind_mismatch/5:p4`, `Check.call_bound_error/5:p3`, `Check.called_ret/2:p0`, `Check.called_ret_with/4:p0`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.ctor_type/2:p0`, `Check.first_bound_violation/4:p3`, `Check.infer/3:p2`, `Check.infer_block/4:p2`, `Check.infer_tail/3:p2`, `Check.narrow/4:p2`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p2`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0082` | 2 | `Check.abstract_cast_ret/3:ret`, `Check.fn_ret/1:ret` |
| `Unk0083` | 1 | `Check.abstract_op_type/4:p0` |
| `Unk0084` | 1 | `Check.abstract_op_type/4:ret` |
| `Unk0085` | 1 | `Check.all_types/1:p0` |
| `Unk0086` | 28 | `Check.ann_each/3:p1`, `Check.ann_stmts/3:p1`, `Check.annotate/3:p1`, `Check.bind_mismatch/5:p3`, `Check.call_bound_error/5:p2`, `Check.called_ret_with/4:p3`, `Check.check_bind_stmts/3:p1`, `Check.clause_env/3:ret`, `Check.infer/3:p1`, `Check.infer_block/4:p1`, `Check.infer_tail/3:p1`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.range_bind/6:p4`, `Check.scan_bound_calls/4:p1`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix_children/3:p1`, `Check.walk_children/4:p1`, `Decl.clause_env/2:ret`, `Interp.resolve/4:p1`, `Interp.resolve_part/4:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.safe_infer/3:p1`, `Repl.safe_infer_input/3:p1` |
| `Unk0087` | 1 | `Check.ann_stmts/3:p0` |
| `Unk0088` | 1 | `Check.arith_type/4:ret` |
| `Unk0089` | 4 | `Check.bind_mismatch/5:p0`, `Check.lit_range_error/3:p2`, `Check.oor_scan/5:p4`, `Check.range_bind/6:p0` |
| `Unk0090` | 2 | `Check.bind_mismatch/5:ret`, `Check.check_bind_stmts/3:ret` |
| `Unk0091` | 4 | `Check.bind_tvar/4:p0`, `Check.bind_tvar/4:p1`, `Check.inner_of/1:p0`, `Check.inner_of/1:ret` |
| `Unk0092` | 1 | `Check.bind_tvar/4:p2` |
| `Unk0093` | 3 | `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.first_bound_violation/4:p2` |
| `Unk0094` | 1 | `Check.branch_join/1:p0` |
| `Unk0095` | 1 | `Check.build_fn/2:p0` |
| `Unk0096` | 2 | `Check.call_bound_error/5:ret`, `Check.first_bound_violation/4:ret` |
| `Unk0097` | 1 | `Check.call_name/1:p0` |
| `Unk0098` | 2 | `Check.call_name/1:ret`, `Check.with_callees/1:ret` |
| `Unk0099` | 1 | `Check.check/1:ret` |
| `Unk0100` | 1 | `Check.check_bind_stmts/3:p0` |
| `Unk0101` | 1 | `Check.check_binds/2:ret` |
| `Unk0102` | 1 | `Check.check_bounds/2:ret` |
| `Unk0103` | 1 | `Check.check_error_set/2:p0` |
| `Unk0104` | 2 | `Check.check_error_set/2:p1`, `Check.check_func/3:p2` |
| `Unk0105` | 1 | `Check.check_error_set/2:ret` |
| `Unk0106` | 1 | `Check.check_external_caps/1:ret` |
| `Unk0107` | 1 | `Check.check_func/3:p0` |
| `Unk0108` | 1 | `Check.check_func/3:ret` |
| `Unk0109` | 1 | `Check.check_labels/1:ret` |
| `Unk0110` | 1 | `Check.check_numeric_mix/2:ret` |
| `Unk0111` | 1 | `Check.check_program/1:ret` |
| `Unk0112` | 1 | `Check.check_return/2:ret` |
| `Unk0113` | 1 | `Check.clause_env/3:p0` |
| `Unk0114` | 1 | `Check.clause_env/3:p1` |
| `Unk0115` | 1 | `Check.comp_str/1:p0` |
| `Unk0116` | 1 | `Check.const_int/1:ret` |
| `Unk0117` | 1 | `Check.const_int/1:ret` |
| `Unk0118` | 1 | `Check.ctor_types/2:p1` |
| `Unk0119` | 1 | `Check.ctor_types/2:p1` |
| `Unk0120` | 1 | `Check.ctor_types/2:ret` |
| `Unk0121` | 1 | `Check.ctor_types/2:ret` |
| `Unk0122` | 2 | `Check.debottom/1:p0`, `Check.debottom/1:ret` |
| `Unk0123` | 1 | `Check.declared_set/2:p0` |
| `Unk0124` | 4 | `Check.declared_set/2:p1`, `Check.declared_set/2:ret`, `Check.error_sets/1:ret`, `Check.solve_error_sets/2:p1` |
| `Unk0125` | 1 | `Check.declared_set/2:ret` |
| `Unk0126` | 3 | `Check.direct_tags/1:p0`, `Check.produced_set/2:p0`, `Check.propagated_callees/1:p0` |
| `Unk0127` | 1 | `Check.direct_tags/1:ret` |
| `Unk0128` | 1 | `Check.error_tags/1:p0` |
| `Unk0129` | 2 | `Check.error_tags/1:ret`, `Check.tag_name/1:ret` |
| `Unk0130` | 1 | `Check.fbound_table/1:p0` |
| `Unk0131` | 1 | `Check.fbound_table/1:ret` |
| `Unk0132` | 1 | `Check.first_bound_violation/4:p1` |
| `Unk0133` | 1 | `Check.fixpoint/2:p0` |
| `Unk0134` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0135` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0136` | 1 | `Check.fn_parts/1:ret` |
| `Unk0137` | 1 | `Check.fsig/1:p0` |
| `Unk0138` | 1 | `Check.fsig/1:ret` |
| `Unk0139` | 1 | `Check.generic_ret?/2:p0` |
| `Unk0140` | 1 | `Check.generic_ret?/2:p1` |
| `Unk0141` | 1 | `Check.impl_table/1:p0` |
| `Unk0142` | 1 | `Check.impl_table/1:p0` |
| `Unk0143` | 1 | `Check.impl_table/1:ret` |
| `Unk0144` | 1 | `Check.infer_block/4:p0` |
| `Unk0145` | 1 | `Check.instantiate_ret/2:p0` |
| `Unk0146` | 4 | `Check.int_float_join/2:ret`, `Check.join/2:ret`, `Check.num_join/2:ret`, `Check.parametric_join/2:ret` |
| `Unk0147` | 1 | `Check.int_literal?/1:p0` |
| `Unk0148` | 1 | `Check.join_all/1:p0` |
| `Unk0149` | 1 | `Check.kind_prefix/1:p0` |
| `Unk0150` | 2 | `Check.label_error/1:ret`, `Check.label_error_children/1:ret` |
| `Unk0151` | 1 | `Check.list_elem/1:ret` |
| `Unk0152` | 1 | `Check.list_elems/1:ret` |
| `Unk0153` | 1 | `Check.lit_range_error/3:ret` |
| `Unk0154` | 1 | `Check.literal_ordinal/2:ret` |
| `Unk0155` | 1 | `Check.missing_impl/5:p1` |
| `Unk0156` | 1 | `Check.missing_impl/5:p3` |
| `Unk0157` | 1 | `Check.missing_impl/5:ret` |
| `Unk0158` | 1 | `Check.num_bits/2:p0` |
| `Unk0159` | 1 | `Check.num_bits/2:p1` |
| `Unk0160` | 2 | `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0161` | 1 | `Check.num_join/2:p0` |
| `Unk0162` | 1 | `Check.num_join/2:p1` |
| `Unk0163` | 1 | `Check.num_lub/2:ret` |
| `Unk0164` | 1 | `Check.num_mix?/2:p0` |
| `Unk0165` | 1 | `Check.num_mix?/2:p1` |
| `Unk0166` | 1 | `Check.num_mix_error/5:p0` |
| `Unk0167` | 1 | `Check.num_mix_error/5:ret` |
| `Unk0168` | 1 | `Check.num_widens?/2:p0` |
| `Unk0169` | 1 | `Check.num_widens?/2:p1` |
| `Unk0170` | 1 | `Check.oor_scan/5:p2` |
| `Unk0171` | 1 | `Check.oor_scan/5:p3` |
| `Unk0172` | 1 | `Check.oor_scan/5:ret` |
| `Unk0173` | 1 | `Check.opaque_table/1:p0` |
| `Unk0174` | 1 | `Check.opaque_table/1:p0` |
| `Unk0175` | 1 | `Check.opaque_table/1:ret` |
| `Unk0176` | 1 | `Check.pascal?/1:p0` |
| `Unk0177` | 1 | `Check.produced_set/2:p1` |
| `Unk0178` | 1 | `Check.produced_set/2:p1` |
| `Unk0179` | 1 | `Check.produced_set/2:ret` |
| `Unk0180` | 1 | `Check.propagated_callees/1:ret` |
| `Unk0181` | 1 | `Check.range_base/2:ret` |
| `Unk0182` | 1 | `Check.range_bind/6:p2` |
| `Unk0183` | 1 | `Check.range_bind/6:ret` |
| `Unk0184` | 1 | `Check.range_table/1:p0` |
| `Unk0185` | 1 | `Check.range_table/1:p0` |
| `Unk0186` | 1 | `Check.range_table/1:ret` |
| `Unk0187` | 2 | `Check.scan_bound_calls/4:ret`, `Check.walk_children/4:ret` |
| `Unk0188` | 2 | `Check.scan_num_mix/3:ret`, `Check.scan_num_mix_children/3:ret` |
| `Unk0189` | 1 | `Check.solve_error_sets/2:p0` |
| `Unk0190` | 1 | `Check.tag_name/1:p0` |
| `Unk0191` | 1 | `Check.type_table/1:ret` |
| `Unk0192` | 2 | `Check.uint_signed_join/2:p0`, `Check.uint_signed_join/2:p1` |
| `Unk0193` | 1 | `Check.with_callees/1:p0` |
| `Unk0194` | 1 | `Comptime.eval/1:p0` |
| `Unk0195` | 1 | `Comptime.eval/1:ret` |
| `Unk0196` | 24 | `Comptime.fold/1:ret`, `Interp.resolve/4:p0`, `Lower.borrow_arg/5:p0`, `Lower.borrow_value/2:p0`, `Lower.borrow_value/2:ret`, `Lower.insert_borrows/4:ret`, `Lower.owned_arg?/2:p0`, `Lower.owned_field_var?/2:p0`, `Lower.resolve_consts/2:ret`, `Lower.resolve_rust_pats/2:ret`, `Lower.resolve_structs/2:ret`, `Lower.resolve_variants/2:ret`, `Lower.scalar_literal?/1:p0`, `Lower.variant_lit/2:ret`, `Lower.widen_char_arith/2:ret`, `Lower.wrap_char/2:p0`, `Lower.wrap_char/2:ret`, `Macro.do_expand/4:ret`, `Macro.freshen/2:ret`, `Macro.map_node/2:p1`, `Macro.map_node/2:ret`, `Macro.rename/2:ret`, `Macro.substitute/2:p0`, `Macro.walk_for_with/1:ret` |
| `Unk0197` | 1 | `Comptime.int_div/3:p0` |
| `Unk0198` | 1 | `Comptime.int_div/3:p2` |
| `Unk0199` | 1 | `Comptime.int_div/3:p2` |
| `Unk0200` | 1 | `Comptime.int_div/3:p2` |
| `Unk0201` | 1 | `Comptime.int_div/3:ret` |
| `Unk0202` | 1 | `Core.first_unsupported/2:p0` |
| `Unk0203` | 2 | `Core.first_unsupported/2:p1`, `Core.reject_unsupported!/4:p1` |
| `Unk0204` | 3 | `Core.first_unsupported/2:p1`, `Core.first_unsupported/2:ret`, `Core.reject_unsupported!/4:p1` |
| `Unk0205` | 1 | `Core.from_arm/1:p0` |
| `Unk0206` | 1 | `Core.from_arm/1:ret` |
| `Unk0207` | 1 | `Core.from_pairs/1:p0` |
| `Unk0208` | 1 | `Core.from_pairs/1:ret` |
| `Unk0209` | 1 | `Core.from_stmt/1:p0` |
| `Unk0210` | 1 | `Core.from_stmt/1:ret` |
| `Unk0211` | 1 | `Core.from_tail/1:p0` |
| `Unk0212` | 2 | `Core.reject_unsupported!/4:p0`, `JS.function_js/2:p0` |
| `Unk0213` | 8 | `Cst.build/1:p0`, `Cst.open/4:p0`, `Cst.open/4:p2`, `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p0`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0214` | 1 | `Cst.build/1:ret` |
| `Unk0215` | 1 | `Cst.open/4:p1` |
| `Unk0216` | 4 | `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0217` | 2 | `Cst.open/4:ret`, `Cst.seq/2:ret` |
| `Unk0218` | 7 | `Decl.all_impl_decls/1:p0`, `Decl.all_impls/1:p0`, `Decl.all_protocols/1:p0`, `Decl.collect_aliases/1:p0`, `Decl.collect_macros/1:p0`, `Decl.in_scope/2:p0`, `Decl.lower_meta/3:p1` |
| `Unk0219` | 5 | `Decl.all_impl_decls/1:ret`, `Decl.all_protocols/1:ret`, `Decl.in_scope/2:ret`, `Protocol.check_assoc!/2:p0`, `Protocol.check_assoc!/2:p1` |
| `Unk0220` | 1 | `Decl.all_impls/1:ret` |
| `Unk0221` | 2 | `Decl.assemble/3:p0`, `Decl.protocol_defs/4:p0` |
| `Unk0222` | 5 | `Decl.assemble/3:p1`, `Decl.subst_const/2:p1`, `Decl.subst_func/2:p1`, `Decl.subst_struct/2:p1`, `Decl.subst_type/2:p1` |
| `Unk0223` | 1 | `Decl.assemble/3:p2` |
| `Unk0224` | 1 | `Decl.assemble/3:ret` |
| `Unk0225` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0226` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0227` | 1 | `Decl.attach_external/3:p0` |
| `Unk0228` | 1 | `Decl.attach_external/3:p1` |
| `Unk0229` | 1 | `Decl.attach_external/3:p2` |
| `Unk0230` | 1 | `Decl.attach_targets/2:p0` |
| `Unk0231` | 2 | `Decl.attach_targets/2:p1`, `Decl.parse_targets/1:ret` |
| `Unk0232` | 37 | `Decl.balanced_parens/1:p0`, `Decl.balanced_parens/1:ret`, `Decl.decl_boundary?/1:p0`, `Decl.decl_kw?/1:p0`, `Decl.def_raw/4:p2`, `Decl.line_continues?/2:p0`, `Decl.line_continues?/2:p1`, `Decl.skip_nl/1:p0`, `Decl.skip_nl/1:ret`, `Decl.split_decls/1:p0`, `Decl.take_block/3:p0`, `Decl.take_block/3:p2`, `Decl.take_block/3:ret`, `Decl.take_decl/1:p0`, `Decl.take_decl/1:ret`, `Decl.take_def/1:p0`, `Decl.take_def/1:ret`, `Decl.take_head/4:p2`, `Decl.take_head/4:p3`, `Decl.take_head/4:ret`, `Decl.take_line/2:p0`, `Decl.take_line/2:p1`, `Decl.take_line/2:ret`, `Decl.take_line/3:p0`, `Decl.take_line/3:p1`, `Decl.take_line/3:ret`, `Decl.take_mod_body/2:p0`, `Decl.take_mod_body/2:ret`, `Decl.take_parens/3:p0`, `Decl.take_parens/3:p2`, `Decl.take_parens/3:ret`, `Decl.take_type/2:p0`, `Decl.take_type/2:p1`, `Decl.take_type/2:ret`, `Decl.take_until_do/2:p0`, `Decl.take_until_do/2:p1`, `Decl.take_until_do/2:ret` |
| `Unk0233` | 3 | `Decl.block_seps/5:p0`, `Decl.block_seps/5:p4`, `Decl.block_seps/5:ret` |
| `Unk0234` | 1 | `Decl.build_func/1:p0` |
| `Unk0235` | 1 | `Decl.calls_show_float?/1:p0` |
| `Unk0236` | 1 | `Decl.clause/2:p0` |
| `Unk0237` | 1 | `Decl.clause/2:p1` |
| `Unk0238` | 2 | `Decl.clause_env/2:p1`, `Decl.meta_clause/5:p3` |
| `Unk0239` | 1 | `Decl.collapse_parens/1:p0` |
| `Unk0240` | 1 | `Decl.collapse_parens/1:ret` |
| `Unk0241` | 1 | `Decl.collect_aliases/1:ret` |
| `Unk0242` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0243` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0244` | 8 | `Decl.compile/1:ret`, `Decl.compile_beam/1:ret`, `Decl.protocol_unit/3:ret`, `Lower.compile/5:ret`, `Lower.compile_beam/4:ret`, `Lower.compile_elixir/4:ret`, `Lower.compile_module/1:ret`, `Lower.compile_module_beam/1:ret` |
| `Unk0245` | 1 | `Decl.compile_beam/1:ret` |
| `Unk0246` | 2 | `Decl.def_raw/4:p0`, `Decl.take_head/4:p0` |
| `Unk0247` | 2 | `Decl.def_raw/4:p1`, `Decl.take_head/4:p1` |
| `Unk0248` | 2 | `Decl.def_raw/4:p3`, `Decl.detok_block/1:ret` |
| `Unk0249` | 3 | `Decl.def_raw/4:ret`, `Decl.take_def/1:ret`, `Decl.take_head/4:ret` |
| `Unk0250` | 1 | `Decl.detok_block/1:p0` |
| `Unk0251` | 3 | `Decl.extract_parens/1:p0`, `Decl.parse_struct/3:p0`, `Decl.variant/1:p0` |
| `Unk0252` | 1 | `Decl.extract_parens/1:ret` |
| `Unk0253` | 1 | `Decl.field/1:p0` |
| `Unk0254` | 1 | `Decl.fields/1:p0` |
| `Unk0255` | 1 | `Decl.fields/1:ret` |
| `Unk0256` | 1 | `Decl.impl_struct/3:p0` |
| `Unk0257` | 1 | `Decl.impl_struct/3:p1` |
| `Unk0258` | 1 | `Decl.impl_struct/3:p2` |
| `Unk0259` | 1 | `Decl.impl_struct/3:ret` |
| `Unk0260` | 1 | `Decl.in_scope/2:p1` |
| `Unk0261` | 1 | `Decl.in_scope/2:p1` |
| `Unk0262` | 4 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0`, `ShowStdlib.module/0:ret` |
| `Unk0263` | 3 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0` |
| `Unk0264` | 1 | `Decl.lower_meta/3:p0` |
| `Unk0265` | 1 | `Decl.lower_meta/3:p2` |
| `Unk0266` | 1 | `Decl.lower_meta/3:ret` |
| `Unk0267` | 1 | `Decl.macro_param_names/1:p0` |
| `Unk0268` | 1 | `Decl.macro_param_names/1:ret` |
| `Unk0269` | 1 | `Decl.mark_pub/1:p0` |
| `Unk0270` | 1 | `Decl.mark_test/1:p0` |
| `Unk0271` | 1 | `Decl.meta_clause/5:p0` |
| `Unk0272` | 4 | `Decl.meta_clause/5:p4`, `Interp.resolve/4:p3`, `Interp.resolve_part/4:p3`, `Interp.stringify/3:p2` |
| `Unk0273` | 1 | `Decl.meta_clause/5:ret` |
| `Unk0274` | 1 | `Decl.nz/1:ret` |
| `Unk0275` | 1 | `Decl.param/1:p0` |
| `Unk0276` | 1 | `Decl.param/1:ret` |
| `Unk0277` | 7 | `Decl.parse_abstract/4:p0`, `Decl.parse_alias/1:p0`, `Decl.parse_const/3:p0`, `Decl.parse_opaque/3:p0`, `Decl.parse_range/3:p0`, `Decl.parse_type/3:p0`, `Decl.split_once/2:p0` |
| `Unk0278` | 2 | `Decl.parse_abstract/4:p1`, `Decl.parse_abstract_members/1:p0` |
| `Unk0279` | 1 | `Decl.parse_abstract/4:p2` |
| `Unk0280` | 1 | `Decl.parse_abstract/4:p3` |
| `Unk0281` | 1 | `Decl.parse_abstract_members/1:ret` |
| `Unk0282` | 2 | `Decl.parse_alias/1:ret`, `Decl.strip_type_params/1:ret` |
| `Unk0283` | 1 | `Decl.parse_alias/1:ret` |
| `Unk0284` | 1 | `Decl.parse_assoc_binding/1:p0` |
| `Unk0285` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0286` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0287` | 1 | `Decl.parse_binder/1:p0` |
| `Unk0288` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0289` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0290` | 1 | `Decl.parse_binders/1:p0` |
| `Unk0291` | 1 | `Decl.parse_binders/1:ret` |
| `Unk0292` | 1 | `Decl.parse_bounds/1:p0` |
| `Unk0293` | 1 | `Decl.parse_bounds/1:ret` |
| `Unk0294` | 2 | `Decl.parse_cast_rule/1:p0`, `Decl.parse_op_rule/1:p0` |
| `Unk0295` | 1 | `Decl.parse_cast_rule/1:ret` |
| `Unk0296` | 1 | `Decl.parse_const/3:p1` |
| `Unk0297` | 1 | `Decl.parse_const/3:p2` |
| `Unk0298` | 1 | `Decl.parse_external/1:p0` |
| `Unk0299` | 1 | `Decl.parse_external/1:ret` |
| `Unk0300` | 1 | `Decl.parse_external/1:ret` |
| `Unk0301` | 1 | `Decl.parse_head/1:ret` |
| `Unk0302` | 1 | `Decl.parse_op_rule/1:ret` |
| `Unk0303` | 1 | `Decl.parse_opaque/3:p1` |
| `Unk0304` | 1 | `Decl.parse_opaque/3:p2` |
| `Unk0305` | 1 | `Decl.parse_ordinal/1:p0` |
| `Unk0306` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0307` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0308` | 1 | `Decl.parse_params/1:p0` |
| `Unk0309` | 1 | `Decl.parse_params/1:ret` |
| `Unk0310` | 1 | `Decl.parse_range/3:p1` |
| `Unk0311` | 1 | `Decl.parse_range/3:p2` |
| `Unk0312` | 1 | `Decl.parse_struct/3:p1` |
| `Unk0313` | 1 | `Decl.parse_struct/3:p2` |
| `Unk0314` | 1 | `Decl.parse_targets/1:p0` |
| `Unk0315` | 1 | `Decl.parse_type/3:p1` |
| `Unk0316` | 1 | `Decl.parse_type/3:p2` |
| `Unk0317` | 1 | `Decl.parse_use/1:p0` |
| `Unk0318` | 2 | `Decl.proto_method_traits/1:ret`, `Lower.compile/5:p4` |
| `Unk0319` | 2 | `Decl.protocol_defs/4:p1`, `Protocol.expand/5:p2` |
| `Unk0320` | 2 | `Decl.protocol_defs/4:p2`, `Protocol.expand/5:p3` |
| `Unk0321` | 2 | `Decl.protocol_defs/4:p3`, `Protocol.expand/5:p4` |
| `Unk0322` | 3 | `Decl.protocol_defs/4:ret`, `Protocol.expand/5:ret`, `Protocol.impl_methods/2:ret` |
| `Unk0323` | 1 | `Decl.protocol_struct/2:p0` |
| `Unk0324` | 1 | `Decl.protocol_struct/2:p1` |
| `Unk0325` | 1 | `Decl.protocol_struct/2:ret` |
| `Unk0326` | 1 | `Decl.req_ret/1:p0` |
| `Unk0327` | 1 | `Decl.req_ret/1:ret` |
| `Unk0328` | 1 | `Decl.split2/2:p0` |
| `Unk0329` | 1 | `Decl.split2/2:p1` |
| `Unk0330` | 1 | `Decl.split2/2:ret` |
| `Unk0331` | 1 | `Decl.split2/2:ret` |
| `Unk0332` | 1 | `Decl.split_decls/1:ret` |
| `Unk0333` | 1 | `Decl.split_forall/1:p0` |
| `Unk0334` | 1 | `Decl.split_forall/1:ret` |
| `Unk0335` | 1 | `Decl.split_once/2:ret` |
| `Unk0336` | 1 | `Decl.split_once/2:ret` |
| `Unk0337` | 1 | `Decl.split_top/2:p0` |
| `Unk0338` | 1 | `Decl.split_top/2:ret` |
| `Unk0339` | 1 | `Decl.strip_type_params/1:p0` |
| `Unk0340` | 1 | `Decl.subst_const/2:p0` |
| `Unk0341` | 1 | `Decl.subst_fields/2:p0` |
| `Unk0342` | 1 | `Decl.subst_fields/2:p1` |
| `Unk0343` | 1 | `Decl.subst_func/2:p0` |
| `Unk0344` | 1 | `Decl.subst_struct/2:p0` |
| `Unk0345` | 1 | `Decl.subst_type/2:p0` |
| `Unk0346` | 2 | `Decl.subst_type_str/2:p0`, `Decl.subst_type_str/2:ret` |
| `Unk0347` | 1 | `Decl.subst_type_str/2:p1` |
| `Unk0348` | 1 | `Decl.subst_variant/2:p0` |
| `Unk0349` | 1 | `Decl.subst_variant/2:p1` |
| `Unk0350` | 2 | `Decl.take_mod_body/2:p1`, `Decl.take_mod_body/2:ret` |
| `Unk0351` | 1 | `Decl.take_until_do/2:ret` |
| `Unk0352` | 30 | `Doc.concat/1:p0`, `Doc.concat/1:ret`, `Doc.concat/2:p0`, `Doc.concat/2:p1`, `Doc.concat/2:ret`, `Doc.empty/0:ret`, `Doc.group/2:p0`, `Doc.hardline/0:ret`, `Doc.if_break/2:p0`, `Doc.if_break/2:p1`, `Doc.if_break/2:ret`, `Doc.join/2:p0`, `Doc.join/2:p1`, `Doc.join/2:ret`, `Doc.line/0:ret`, `Doc.line_suffix/1:p0`, `Doc.line_suffix/1:ret`, `Doc.must_break?/1:p0`, `Doc.nest/2:p1`, `Doc.nest/2:ret`, `Doc.render/2:p0`, `Doc.softline/0:ret`, `Doc.text/1:ret`, `Format.bd/3:ret`, `Format.chain_body/2:ret`, `Format.chain_doc/1:ret`, `Format.chain_tail/2:ret`, `Format.group_doc/4:ret`, `Format.line_doc/1:ret`, `Format.node_doc/2:ret` |
| `Unk0353` | 2 | `Doc.do_render/5:p2`, `Doc.fits?/2:p1` |
| `Unk0354` | 3 | `Doc.do_render/5:p3`, `Doc.flat_string/1:p0`, `Doc.flush_suffix/2:p0` |
| `Unk0355` | 1 | `Doc.group/2:ret` |
| `Unk0356` | 14 | `Doc.nest/2:p0`, `Format.apply_node/3:p1`, `Format.apply_node/3:p2`, `Format.apply_node/3:ret`, `Format.indent_and_render/4:p1`, `Format.pop/1:p0`, `Format.pop/1:ret`, `Format.push/2:p0`, `Format.push/2:p1`, `Format.push/2:ret`, `Format.render_line/2:p1`, `Format.update_stack/4:p2`, `Format.update_stack/4:p3`, `Format.update_stack/4:ret` |
| `Unk0357` | 2 | `Doctest.augment/2:p1`, `Doctest.extract/1:ret` |
| `Unk0358` | 1 | `Doctest.exunit_cases/2:p1` |
| `Unk0359` | 1 | `Doctest.exunit_cases/2:ret` |
| `Unk0360` | 1 | `Doctest.fences/1:p0` |
| `Unk0361` | 1 | `Doctest.fences/1:ret` |
| `Unk0362` | 1 | `Doctest.module_doc_strings/1:ret` |
| `Unk0363` | 1 | `Doctest.pairs/1:p0` |
| `Unk0364` | 1 | `Doctest.pairs/1:ret` |
| `Unk0365` | 1 | `Doctest.run/2:p1` |
| `Unk0366` | 1 | `Doctest.run/2:ret` |
| `Unk0367` | 1 | `Doctest.run_markdown/1:p0` |
| `Unk0368` | 1 | `Doctest.run_markdown/1:ret` |
| `Unk0369` | 8 | `Exhaustiveness.add_range/4:p0`, `Exhaustiveness.add_range/4:ret`, `Exhaustiveness.add_type/3:p0`, `Exhaustiveness.add_type/3:ret`, `Exhaustiveness.base_env/0:ret`, `Exhaustiveness.program_env/3:ret`, `PatternLower.add_struct/3:p0`, `PatternLower.add_struct/3:ret` |
| `Unk0370` | 1 | `Exhaustiveness.add_range/4:p2` |
| `Unk0371` | 1 | `Exhaustiveness.add_range/4:p3` |
| `Unk0372` | 1 | `Exhaustiveness.add_type/3:p2` |
| `Unk0373` | 2 | `Exhaustiveness.analyze/3:p0`, `PatternLower.lower_clause/2:ret` |
| `Unk0374` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0375` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0376` | 1 | `Exhaustiveness.analyze/3:ret` |
| `Unk0377` | 2 | `Exhaustiveness.arity/2:p1`, `Exhaustiveness.specialize/3:p1` |
| `Unk0378` | 1 | `Exhaustiveness.check_case_bodies!/2:p0` |
| `Unk0379` | 1 | `Exhaustiveness.check_case_bodies!/2:p1` |
| `Unk0380` | 1 | `Exhaustiveness.check_case_bodies!/2:ret` |
| `Unk0381` | 1 | `Exhaustiveness.check_match!/3:p0` |
| `Unk0382` | 2 | `Exhaustiveness.check_match!/3:p2`, `Exhaustiveness.check_one_case!/3:p2` |
| `Unk0383` | 1 | `Exhaustiveness.check_match!/3:ret` |
| `Unk0384` | 1 | `Exhaustiveness.check_one_case!/3:ret` |
| `Unk0385` | 2 | `Exhaustiveness.collect_cases/2:p0`, `Exhaustiveness.collect_children/2:p0` |
| `Unk0386` | 4 | `Exhaustiveness.collect_cases/2:p1`, `Exhaustiveness.collect_cases/2:ret`, `Exhaustiveness.collect_children/2:p1`, `Exhaustiveness.collect_children/2:ret` |
| `Unk0387` | 7 | `Exhaustiveness.default/1:p0`, `Exhaustiveness.default/1:ret`, `Exhaustiveness.head_ctors/1:p0`, `Exhaustiveness.specialize/3:p0`, `Exhaustiveness.specialize/3:ret`, `Exhaustiveness.useful?/3:p0`, `Exhaustiveness.witness/3:p0` |
| `Unk0388` | 3 | `Exhaustiveness.head_ctors/1:ret`, `Exhaustiveness.missing_head/2:p1`, `Exhaustiveness.signature/2:p1` |
| `Unk0389` | 2 | `Exhaustiveness.missing_head/2:ret`, `Exhaustiveness.witness/3:ret` |
| `Unk0390` | 1 | `Exhaustiveness.pascal/1:p0` |
| `Unk0391` | 1 | `Exhaustiveness.program_env/3:p1` |
| `Unk0392` | 1 | `Exhaustiveness.program_env/3:p2` |
| `Unk0393` | 1 | `Exhaustiveness.render/1:p0` |
| `Unk0394` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0395` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0396` | 1 | `Exhaustiveness.useful?/3:p1` |
| `Unk0397` | 1 | `Exhaustiveness.witness/3:ret` |
| `Unk0398` | 1 | `Fixpoint.check/4:p0` |
| `Unk0399` | 1 | `Fixpoint.check/4:p2` |
| `Unk0400` | 1 | `Fixpoint.check/4:p3` |
| `Unk0401` | 1 | `Fixpoint.check/4:ret` |
| `Unk0402` | 46 | `Format.apply_node/3:p0`, `Format.bd/3:p0`, `Format.bd/3:p1`, `Format.blank?/1:p0`, `Format.block_head?/2:p0`, `Format.block_head?/2:p1`, `Format.boundary?/1:p0`, `Format.chain?/1:p0`, `Format.chain_body/2:p0`, `Format.chain_body/2:p1`, `Format.chain_doc/1:p0`, `Format.chain_link?/2:p0`, `Format.chain_link?/2:p1`, `Format.chain_tail/2:p0`, `Format.comment_only?/1:p0`, `Format.declaration_line?/1:p0`, `Format.ends_with_comment?/1:p0`, `Format.head_tok/1:p0`, `Format.indent_and_render/4:p0`, `Format.lead_adjust/1:p0`, `Format.leading_wrap_op?/1:p0`, `Format.line_doc/1:p0`, `Format.mark/1:p0`, `Format.mark/1:ret`, `Format.mark/3:p0`, `Format.mark/3:p1`, `Format.mark/3:p2`, `Format.mark/3:ret`, `Format.merge_chains/1:p0`, `Format.merge_chains/1:ret`, `Format.next_code_line/1:p0`, `Format.next_code_line/1:ret`, `Format.node_doc/2:p0`, `Format.render_line/2:p0`, `Format.split_items/1:ret`, `Format.split_level/1:p0`, `Format.split_node?/2:p0`, `Format.tail_tok/1:p0`, `Format.take_until_level/3:p0`, `Format.take_until_level/3:p2`, `Format.take_until_level/3:ret`, `Format.trailing_op?/1:p0`, `Format.trailing_wrap_op?/1:p0`, `Format.update_stack/4:p0`, `Format.update_stack/4:p1`, `Format.value_end?/1:p0` |
| `Unk0403` | 10 | `Format.boundary_tok?/1:p0`, `Format.closer_lead?/1:p0`, `Format.cont_lead?/1:p0`, `Format.decl_kw?/1:p0`, `Format.head_tok/1:ret`, `Format.space?/2:p0`, `Format.space?/2:p1`, `Format.tail_tok/1:ret`, `Format.value_end_tok?/1:p0`, `Format.wrap_op_tok?/1:p0` |
| `Unk0404` | 4 | `Format.chain_tail/2:p1`, `Format.split_level/1:ret`, `Format.split_node?/2:p1`, `Format.take_until_level/3:p1` |
| `Unk0405` | 7 | `Format.chunk_on_comma/3:p0`, `Format.chunk_on_comma/3:p1`, `Format.chunk_on_comma/3:p2`, `Format.chunk_on_comma/3:ret`, `Format.finish_items/2:p0`, `Format.finish_items/2:p1`, `Format.finish_items/2:ret` |
| `Unk0406` | 6 | `Format.cons_group?/1:p0`, `Format.group_doc/4:p1`, `Format.has_comment?/1:p0`, `Format.magic_comma?/1:p0`, `Format.split_items/1:p0`, `Format.trailing_comma?/1:p0` |
| `Unk0407` | 1 | `Format.format_result/1:ret` |
| `Unk0408` | 1 | `Format.format_result/1:ret` |
| `Unk0409` | 3 | `Format.group_doc/4:p0`, `Format.group_doc/4:p2`, `Format.leaf/1:p0` |
| `Unk0410` | 2 | `Format.has_tok?/2:p0`, `Format.has_tok?/2:p1` |
| `Unk0411` | 1 | `Format.has_tok?/2:p0` |
| `Unk0412` | 6 | `Format.ll/3:p0`, `Format.ll/3:p1`, `Format.ll/3:p2`, `Format.ll/3:ret`, `Format.logical_lines/1:p0`, `Format.logical_lines/1:ret` |
| `Unk0413` | 1 | `Format.squeeze_blanks/1:p0` |
| `Unk0414` | 1 | `Format.squeeze_blanks/1:ret` |
| `Unk0415` | 1 | `Format.wrap_op_node?/1:p0` |
| `Unk0416` | 1 | `Formatting.apply_edits/2:p1` |
| `Unk0417` | 1 | `Formatting.bump_del/3:p0` |
| `Unk0418` | 3 | `Formatting.bump_del/3:p1`, `Formatting.bump_ins/3:p1`, `Formatting.start_hunk/1:p0` |
| `Unk0419` | 1 | `Formatting.bump_del/3:ret` |
| `Unk0420` | 1 | `Formatting.bump_ins/3:p0` |
| `Unk0421` | 1 | `Formatting.bump_ins/3:p2` |
| `Unk0422` | 1 | `Formatting.bump_ins/3:ret` |
| `Unk0423` | 1 | `Formatting.clamp/3:p2` |
| `Unk0424` | 1 | `Formatting.edit/1:p0` |
| `Unk0425` | 1 | `Formatting.edit/1:ret` |
| `Unk0426` | 4 | `Formatting.flush/2:p0`, `Formatting.flush/2:p1`, `Formatting.flush/2:ret`, `Formatting.to_hunks/1:ret` |
| `Unk0427` | 2 | `Formatting.formatting/1:ret`, `Formatting.hunks/2:ret` |
| `Unk0428` | 1 | `Formatting.range_formatting/3:ret` |
| `Unk0429` | 1 | `Formatting.start_hunk/1:ret` |
| `Unk0430` | 1 | `Formatting.to_hunks/1:p0` |
| `Unk0431` | 1 | `FormsEquiv.abstract_code/1:p0` |
| `Unk0432` | 1 | `FormsEquiv.abstract_code/1:ret` |
| `Unk0433` | 3 | `FormsEquiv.alpha_rename/1:p0`, `FormsEquiv.walk_rename/2:p0`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0434` | 1 | `FormsEquiv.alpha_rename/1:ret` |
| `Unk0435` | 3 | `FormsEquiv.bool_clause/1:p0`, `FormsEquiv.bool_clause_pair/1:p0`, `FormsEquiv.bool_clause_pair/1:ret` |
| `Unk0436` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0437` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0438` | 2 | `FormsEquiv.canon_bool_case/1:p0`, `FormsEquiv.canon_bool_case/1:ret` |
| `Unk0439` | 9 | `FormsEquiv.diff/2:p0`, `FormsEquiv.diff/2:p1`, `FormsEquiv.equivalent?/2:p0`, `FormsEquiv.equivalent?/2:p1`, `FormsEquiv.normalize/1:p0`, `FormsEquiv.verified?/2:p0`, `FormsEquiv.verified?/2:p1`, `FormsEquiv.verify/2:p0`, `FormsEquiv.verify/2:p1` |
| `Unk0440` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0441` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0442` | 2 | `FormsEquiv.fold_neg_literal/1:p0`, `FormsEquiv.fold_neg_literal/1:ret` |
| `Unk0443` | 1 | `FormsEquiv.key/1:p0` |
| `Unk0444` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0445` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0446` | 1 | `FormsEquiv.normalize/1:ret` |
| `Unk0447` | 1 | `FormsEquiv.user_function?/1:p0` |
| `Unk0448` | 1 | `FormsEquiv.verify/2:ret` |
| `Unk0449` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0450` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0451` | 2 | `FormsEquiv.zero_anno/1:p0`, `FormsEquiv.zero_anno/1:ret` |
| `Unk0452` | 2 | `History.dedup_consecutive/1:p0`, `History.dedup_consecutive/1:ret` |
| `Unk0453` | 1 | `History.load/0:ret` |
| `Unk0454` | 42 | `Infer.app/2:p1`, `Infer.app/2:ret`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p2`, `Infer.call_sig/6:p3`, `Infer.call_sig/6:ret`, `Infer.con/1:ret`, `Infer.free_vars/2:p1`, `Infer.fresh/1:ret`, `Infer.fresh_num/1:ret`, `Infer.gen/4:p1`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p1`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p1`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p2`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p1`, `Infer.gen_pat/4:p2`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p2`, `Infer.gen_pat_cons/5:p3`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p1`, `Infer.instantiate/5:p2`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p1`, `Infer.maybe_tuple/4:p1`, `Infer.maybe_tuple/4:ret`, `Infer.parse_type/2:ret`, `Infer.render/3:p2`, `Infer.render_wp/3:p2`, `Infer.resolve/2:p1`, `Infer.seed_spec/6:p4`, `Infer.sigvar_call/5:p3`, `Infer.translate_spec/1:ret`, `Infer.unify/3:p1`, `Infer.unify/3:p2`, `Infer.union_spec/2:ret`, `Infer.unk_vars/2:p1`, `Infer.vec_spec/1:ret` |
| `Unk0455` | 55 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.occurs?/3:p0`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0456` | 63 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p2`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p2`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p2`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve/2:ret`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0457` | 63 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p2`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p2`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p2`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve/2:ret`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0458` | 59 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p1`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p1`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p1`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p1`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0459` | 17 | `Infer.apply_spec_terms/4:p0`, `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/1:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0460` | 2 | `Infer.apply_spec_terms/4:p1`, `Infer.seed_spec/6:p3` |
| `Unk0461` | 1 | `Infer.bind/3:ret` |
| `Unk0462` | 3 | `Infer.bind_checked/3:ret`, `Infer.do_unify/3:ret`, `Infer.unify/3:ret` |
| `Unk0463` | 1 | `Infer.bind_params/3:p0` |
| `Unk0464` | 1 | `Infer.bind_params/3:p1` |
| `Unk0465` | 1 | `Infer.bind_params/3:ret` |
| `Unk0466` | 1 | `Infer.build_ctx/2:p0` |
| `Unk0467` | 1 | `Infer.build_ctx/2:p1` |
| `Unk0468` | 1 | `Infer.build_ctx/2:ret` |
| `Unk0469` | 1 | `Infer.build_ledger/2:p0` |
| `Unk0470` | 1 | `Infer.build_ledger/2:ret` |
| `Unk0471` | 17 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/1:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.seed_spec/6:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0472` | 14 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0473` | 1 | `Infer.call_sig/6:p1` |
| `Unk0474` | 1 | `Infer.case_arm/1:p0` |
| `Unk0475` | 1 | `Infer.case_arm/1:ret` |
| `Unk0476` | 1 | `Infer.case_arm/1:ret` |
| `Unk0477` | 1 | `Infer.clear_xmod/0:ret` |
| `Unk0478` | 1 | `Infer.free_vars/2:ret` |
| `Unk0479` | 1 | `Infer.fresh_n/2:ret` |
| `Unk0480` | 2 | `Infer.freshen_tvars/2:p0`, `Infer.freshen_tvars/2:ret` |
| `Unk0481` | 1 | `Infer.freshen_tvars/2:ret` |
| `Unk0482` | 3 | `Infer.gen_pat/4:p0`, `Infer.gen_pat_cons/5:p0`, `Infer.gen_pat_cons/5:p1` |
| `Unk0483` | 1 | `Infer.generalize_map/3:p0` |
| `Unk0484` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0485` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0486` | 3 | `Infer.hole_or/2:p0`, `Infer.hole_or/2:p1`, `Infer.hole_or/2:ret` |
| `Unk0487` | 2 | `Infer.hole_sig?/1:p0`, `Infer.infer_group/2:ret` |
| `Unk0488` | 1 | `Infer.infer_group/2:p0` |
| `Unk0489` | 1 | `Infer.instantiate/5:p0` |
| `Unk0490` | 2 | `Infer.load_prelude_sigs/0:ret`, `Infer.prelude_sigs/0:ret` |
| `Unk0491` | 1 | `Infer.mark_num/2:ret` |
| `Unk0492` | 1 | `Infer.max_ph/1:p0` |
| `Unk0493` | 1 | `Infer.maybe_tuple/4:p0` |
| `Unk0494` | 1 | `Infer.mod_name/1:p0` |
| `Unk0495` | 1 | `Infer.ok_payload/3:p0` |
| `Unk0496` | 2 | `Infer.ok_payload/3:p2`, `Infer.result_analysis/3:p2` |
| `Unk0497` | 1 | `Infer.ok_payload/3:ret` |
| `Unk0498` | 1 | `Infer.parse_type/2:p0` |
| `Unk0499` | 2 | `Infer.parse_type/2:p1`, `Infer.tvar?/1:p0` |
| `Unk0500` | 1 | `Infer.parse_type/2:p1` |
| `Unk0501` | 1 | `Infer.prime_xmod/2:p0` |
| `Unk0502` | 1 | `Infer.prime_xmod/2:p1` |
| `Unk0503` | 1 | `Infer.prime_xmod/2:ret` |
| `Unk0504` | 1 | `Infer.put_slot/3:p0` |
| `Unk0505` | 1 | `Infer.put_slot/3:ret` |
| `Unk0506` | 1 | `Infer.render_wp/3:p1` |
| `Unk0507` | 1 | `Infer.resolve_program/2:p0` |
| `Unk0508` | 2 | `Infer.resolve_program/2:ret`, `Infer.whole_program/4:ret` |
| `Unk0509` | 1 | `Infer.resolve_struct_params/4:p0` |
| `Unk0510` | 1 | `Infer.resolve_struct_params/4:p1` |
| `Unk0511` | 1 | `Infer.result_analysis/3:p0` |
| `Unk0512` | 1 | `Infer.result_analysis/3:ret` |
| `Unk0513` | 1 | `Infer.result_tag/1:p0` |
| `Unk0514` | 1 | `Infer.result_tag/1:ret` |
| `Unk0515` | 1 | `Infer.result_tag/1:ret` |
| `Unk0516` | 1 | `Infer.sig_of/1:p0` |
| `Unk0517` | 1 | `Infer.sig_of/1:ret` |
| `Unk0518` | 1 | `Infer.sigvar_call/5:p1` |
| `Unk0519` | 1 | `Infer.sigvar_call/5:p2` |
| `Unk0520` | 1 | `Infer.sigvar_call/5:ret` |
| `Unk0521` | 1 | `Infer.slot_sig/3:p2` |
| `Unk0522` | 1 | `Infer.slot_sig/3:ret` |
| `Unk0523` | 1 | `Infer.spec_pair/1:p0` |
| `Unk0524` | 1 | `Infer.spec_pair/1:ret` |
| `Unk0525` | 1 | `Infer.spec_pair/1:ret` |
| `Unk0526` | 1 | `Infer.spec_pair/1:ret` |
| `Unk0527` | 1 | `Infer.spec_str/1:p0` |
| `Unk0528` | 4 | `Infer.translate_spec/1:p0`, `Infer.union_spec/2:p0`, `Infer.union_spec/2:p1`, `Infer.vec_spec/1:p0` |
| `Unk0529` | 1 | `Infer.tvar?/1:ret` |
| `Unk0530` | 1 | `Infer.tvar_name/1:p0` |
| `Unk0531` | 1 | `Infer.tvar_name/1:ret` |
| `Unk0532` | 1 | `Infer.unk_vars/2:ret` |
| `Unk0533` | 3 | `Infer.whole_program/4:p0`, `PortAnalysis.collect_groups/1:ret`, `PortAnalysis.param_name_index/1:p0` |
| `Unk0534` | 2 | `Infer.whole_program/4:p1`, `Transpile.stdlib_map/0:ret` |
| `Unk0535` | 2 | `Infer.whole_program/4:p2`, `PortAnalysis.cluster_sums/1:ret` |
| `Unk0536` | 1 | `Infer.whole_program/4:p3` |
| `Unk0537` | 1 | `Infer.xmod_cache/0:ret` |
| `Unk0538` | 2 | `Interp.concat_chain/1:p0`, `Interp.concat_chain/1:ret` |
| `Unk0539` | 1 | `Interp.resolve_part/4:p0` |
| `Unk0540` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0541` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0542` | 1 | `JS.all_funcs/1:p0` |
| `Unk0543` | 2 | `JS.all_funcs/1:p0`, `JS.all_funcs/1:ret` |
| `Unk0544` | 1 | `JS.arm_return/3:p0` |
| `Unk0545` | 1 | `JS.arm_return/3:p1` |
| `Unk0546` | 1 | `JS.bind_lines/1:p0` |
| `Unk0547` | 4 | `JS.block_return/2:p0`, `JVM.block_value/1:p0`, `Shadow.ded_block/4:ret`, `Shadow.dedup/3:ret` |
| `Unk0548` | 1 | `JS.case_arm_js/2:p0` |
| `Unk0549` | 1 | `JS.clause_js/2:p0` |
| `Unk0550` | 4 | `JS.clause_return/3:p1`, `JS.guarded_return/4:p2`, `JVM.clause_value/2:p1`, `Shadow.dedup/3:p1` |
| `Unk0551` | 1 | `JS.cp_lit/2:p0` |
| `Unk0552` | 1 | `JS.dispatcher_js/5:p0` |
| `Unk0553` | 1 | `JS.dispatcher_js/5:p1` |
| `Unk0554` | 1 | `JS.dispatcher_js/5:p2` |
| `Unk0555` | 1 | `JS.dispatcher_js/5:p3` |
| `Unk0556` | 2 | `JS.float?/1:p0`, `JS.num_js/2:p0` |
| `Unk0557` | 1 | `JS.guarded_return/4:p1` |
| `Unk0558` | 3 | `JS.js_atom/1:p0`, `JS.js_str/1:p0`, `JS.lit_js/2:p0` |
| `Unk0559` | 1 | `JS.js_guard!/4:p1` |
| `Unk0560` | 1 | `JS.js_guard!/4:p2` |
| `Unk0561` | 1 | `JS.js_guard!/4:p3` |
| `Unk0562` | 1 | `JS.js_guard!/4:ret` |
| `Unk0563` | 1 | `JS.js_number_int?/1:p0` |
| `Unk0564` | 1 | `JS.mangle/3:p0` |
| `Unk0565` | 1 | `JS.mangle/3:p1` |
| `Unk0566` | 1 | `JS.mangle/3:p2` |
| `Unk0567` | 1 | `JS.match_elems/3:p0` |
| `Unk0568` | 1 | `JS.match_elems/3:ret` |
| `Unk0569` | 1 | `JS.paren/2:p0` |
| `Unk0570` | 1 | `JS.paren/2:p1` |
| `Unk0571` | 1 | `JS.pascal?/1:p0` |
| `Unk0572` | 1 | `JS.pat_match/3:ret` |
| `Unk0573` | 1 | `JS.reject_mixed_int_mode!/1:ret` |
| `Unk0574` | 1 | `JS.reject_wide_int!/2:p0` |
| `Unk0575` | 1 | `JS.reject_wide_int!/2:p1` |
| `Unk0576` | 1 | `JS.reject_wide_int!/2:ret` |
| `Unk0577` | 1 | `JS.stmt_js/2:p0` |
| `Unk0578` | 1 | `JS.stmt_return/2:p0` |
| `Unk0579` | 1 | `JS.stmt_return/2:p1` |
| `Unk0580` | 1 | `JS.struct_name_set/1:ret` |
| `Unk0581` | 1 | `JS.sum_ctor_map/1:ret` |
| `Unk0582` | 1 | `JS.sum_guard_js/1:p0` |
| `Unk0583` | 2 | `JVM.all_funcs/1:p0`, `JVM.all_funcs/1:ret` |
| `Unk0584` | 1 | `JVM.all_funcs/1:p0` |
| `Unk0585` | 1 | `JVM.bind_str/1:p0` |
| `Unk0586` | 1 | `JVM.case_arms/2:p0` |
| `Unk0587` | 1 | `JVM.case_arms/2:ret` |
| `Unk0588` | 1 | `JVM.case_arms/2:ret` |
| `Unk0589` | 4 | `JVM.clause_lines/1:p0`, `JVM.closed_or_cond/3:p2`, `JVM.prepend_if/3:p2`, `JVM.run_or_cond/3:p2` |
| `Unk0590` | 1 | `JVM.clause_match/1:p0` |
| `Unk0591` | 1 | `JVM.clause_match/1:ret` |
| `Unk0592` | 3 | `JVM.closed_or_cond/3:p0`, `JVM.prepend_if/3:p0`, `JVM.run_or_cond/3:p0` |
| `Unk0593` | 1 | `JVM.function_kt/1:p0` |
| `Unk0594` | 1 | `JVM.guarded_arm/2:p1` |
| `Unk0595` | 1 | `JVM.guarded_return/3:p0` |
| `Unk0596` | 1 | `JVM.guarded_return/3:p1` |
| `Unk0597` | 1 | `JVM.guarded_return/3:p2` |
| `Unk0598` | 1 | `JVM.kotlin_module/2:p1` |
| `Unk0599` | 2 | `JVM.kt_str/1:p0`, `JVM.lit_kt/1:p0` |
| `Unk0600` | 1 | `JVM.kt_type/1:ret` |
| `Unk0601` | 1 | `JVM.pat_match/2:ret` |
| `Unk0602` | 1 | `JVM.stmt_kt/1:p0` |
| `Unk0603` | 1 | `JVM.stmt_value/1:p0` |
| `Unk0604` | 1 | `JVM.sum_decl/1:p0` |
| `Unk0605` | 1 | `JVM.to_jar/3:p2` |
| `Unk0606` | 1 | `JVM.to_jar/3:ret` |
| `Unk0607` | 1 | `JVM.variant_decl/2:p0` |
| `Unk0608` | 1 | `JVM.variant_decl/2:p1` |
| `Unk0609` | 4 | `Lexer.binify/1:ret`, `Lexer.capture_hole/3:ret`, `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0610` | 1 | `Lexer.capture_hole/3:ret` |
| `Unk0611` | 1 | `Lexer.char_escape/1:p0` |
| `Unk0612` | 2 | `Lexer.char_escape/1:ret`, `Lexer.parse_hex!/1:p0` |
| `Unk0613` | 2 | `Lexer.close_char/1:ret`, `Lexer.lex_char/1:ret` |
| `Unk0614` | 1 | `Lexer.collapse_nl/1:p0` |
| `Unk0615` | 1 | `Lexer.collapse_nl/1:ret` |
| `Unk0616` | 1 | `Lexer.detokenize/2:p0` |
| `Unk0617` | 1 | `Lexer.escape_str/1:p0` |
| `Unk0618` | 75 | `Lexer.expr_tokens/1:ret`, `Pratt.climb/3:p1`, `Pratt.climb/3:ret`, `Pratt.collect_dots/2:p1`, `Pratt.collect_dots/2:ret`, `Pratt.expect_kw/2:p0`, `Pratt.expect_kw/2:ret`, `Pratt.expect_op/2:p0`, `Pratt.expect_op/2:ret`, `Pratt.expect_rbracket/1:p0`, `Pratt.expect_rbracket/1:ret`, `Pratt.expect_rparen/1:p0`, `Pratt.expect_rparen/1:ret`, `Pratt.finish_arg/2:p1`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:p0`, `Pratt.parse_args/1:ret`, `Pratt.parse_arms/2:p0`, `Pratt.parse_arms/2:ret`, `Pratt.parse_block/1:p0`, `Pratt.parse_block/1:ret`, `Pratt.parse_capture/1:p0`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:p0`, `Pratt.parse_case/1:ret`, `Pratt.parse_expr/2:p0`, `Pratt.parse_expr/2:ret`, `Pratt.parse_if/1:p0`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:p0`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:p0`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p0`, `Pratt.parse_map/2:ret`, `Pratt.parse_param/1:p0`, `Pratt.parse_param/1:ret`, `Pratt.parse_params/1:p0`, `Pratt.parse_params/1:ret`, `Pratt.parse_pat/1:p0`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_args/2:p0`, `Pratt.parse_pat_args/2:ret`, `Pratt.parse_pat_fields/2:p0`, `Pratt.parse_pat_fields/2:ret`, `Pratt.parse_pat_list/2:p0`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p0`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p0`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_path/1:p0`, `Pratt.parse_path/1:ret`, `Pratt.parse_pats/2:p0`, `Pratt.parse_postfix/2:p1`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:p0`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:p0`, `Pratt.parse_primary/1:ret`, `Pratt.parse_stmt/1:p0`, `Pratt.parse_stmt/1:ret`, `Pratt.parse_stmts/2:p0`, `Pratt.parse_stmts/2:ret`, `Pratt.parse_tuple/2:p0`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_type/1:p0`, `Pratt.parse_type/1:ret`, `Pratt.parse_type_args/2:p0`, `Pratt.parse_type_args/2:ret`, `Pratt.parse_with/1:p0`, `Pratt.parse_with/1:ret`, `Pratt.parse_with_clauses/2:p0`, `Pratt.parse_with_clauses/2:ret`, `Pratt.peek_infix/1:p0` |
| `Unk0619` | 2 | `Lexer.lex/2:p1`, `Lexer.word/1:ret` |
| `Unk0620` | 2 | `Lexer.lex/2:ret`, `Lexer.tokenize_trivia/1:ret` |
| `Unk0621` | 1 | `Lexer.lex_char/1:ret` |
| `Unk0622` | 2 | `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0623` | 1 | `Lexer.lex_parts/3:ret` |
| `Unk0624` | 3 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:p0`, `Lexer.string_token/1:ret` |
| `Unk0625` | 2 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:ret` |
| `Unk0626` | 1 | `Lexer.lex_string_token/1:ret` |
| `Unk0627` | 1 | `Lexer.punct/1:ret` |
| `Unk0628` | 1 | `Lexer.strip_trivia/1:p0` |
| `Unk0629` | 1 | `Lexer.strip_trivia/1:ret` |
| `Unk0630` | 1 | `Lexer.take_comment/1:ret` |
| `Unk0631` | 4 | `Lexer.take_hex/2:p0`, `Lexer.take_hex/2:ret`, `Lexer.take_hex/3:p0`, `Lexer.take_hex/3:ret` |
| `Unk0632` | 1 | `Lexer.tok_str/2:p0` |
| `Unk0633` | 1 | `Lexer.tokenize/1:ret` |
| `Unk0634` | 2 | `Livebook.eval/1:ret`, `Livebook.output/1:ret` |
| `Unk0635` | 2 | `Livebook.run/2:p0`, `Livebook.run/2:ret` |
| `Unk0636` | 1 | `Livebook.run/2:ret` |
| `Unk0637` | 1 | `Livebook.session_pid/0:ret` |
| `Unk0638` | 4 | `Lower.add_list_elem_vars/2:p0`, `Lower.add_list_elem_vars/2:ret`, `Lower.add_var/2:p0`, `Lower.add_var/2:ret` |
| `Unk0639` | 1 | `Lower.add_list_elem_vars/2:p1` |
| `Unk0640` | 1 | `Lower.add_var/2:p1` |
| `Unk0641` | 1 | `Lower.all_pat_vars/1:ret` |
| `Unk0642` | 1 | `Lower.arm_rebinds/3:p0` |
| `Unk0643` | 3 | `Lower.arm_rebinds/3:p1`, `Lower.iso_cons_positions/1:ret`, `Lower.rust_scrut/2:p1` |
| `Unk0644` | 4 | `Lower.arm_rebinds/3:p2`, `Lower.collect_ids/2:p1`, `Lower.collect_ids/2:ret`, `Lower.used_ids/1:ret` |
| `Unk0645` | 1 | `Lower.arm_rebinds/3:ret` |
| `Unk0646` | 1 | `Lower.assoc/1:ret` |
| `Unk0647` | 1 | `Lower.body_ast/2:p0` |
| `Unk0648` | 1 | `Lower.body_ast/2:p1` |
| `Unk0649` | 1 | `Lower.body_ast/2:ret` |
| `Unk0650` | 5 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p0`, `Lower.param_rtypes/2:p1` |
| `Unk0651` | 4 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p1` |
| `Unk0652` | 3 | `Lower.borrow_arg/5:p4`, `Lower.insert_borrows/4:p2`, `Lower.owned_field_var?/2:p1` |
| `Unk0653` | 1 | `Lower.borrow_arg/5:ret` |
| `Unk0654` | 1 | `Lower.borrowed_in_pat/2:ret` |
| `Unk0655` | 1 | `Lower.borrowed_vars/2:p0` |
| `Unk0656` | 1 | `Lower.borrowed_vars/2:p1` |
| `Unk0657` | 1 | `Lower.borrowed_vars/2:ret` |
| `Unk0658` | 1 | `Lower.build_env/3:p1` |
| `Unk0659` | 1 | `Lower.build_env/3:p2` |
| `Unk0660` | 2 | `Lower.build_env/3:ret`, `Lower.check!/2:p1` |
| `Unk0661` | 3 | `Lower.build_meta/1:ret`, `Lower.ctx/4:p0`, `Lower.to_rust/6:p2` |
| `Unk0662` | 4 | `Lower.build_struct_meta/1:ret`, `Lower.ctx/4:p1`, `Lower.to_elixir/4:p3`, `Lower.to_rust/6:p4` |
| `Unk0663` | 9 | `Lower.case_guard/3:p1`, `Lower.disp/2:p1`, `Lower.emit/3:p1`, `Lower.emit_ast/2:p1`, `Lower.emit_block/3:p1`, `Lower.emit_expr/2:p1`, `Lower.guard_kw/1:p0`, `Lower.guard_str/4:p1`, `Lower.p/4:p2` |
| `Unk0664` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0665` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0666` | 1 | `Lower.char_vars/2:p0` |
| `Unk0667` | 1 | `Lower.char_vars/2:p1` |
| `Unk0668` | 1 | `Lower.char_vars/2:ret` |
| `Unk0669` | 14 | `Lower.check!/2:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_used?/2:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_rust/6:p0` |
| `Unk0670` | 1 | `Lower.check!/2:ret` |
| `Unk0671` | 2 | `Lower.collect_ids/2:p0`, `Lower.used_ids/1:p0` |
| `Unk0672` | 1 | `Lower.collect_owned_field_vars/3:p0` |
| `Unk0673` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0674` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0675` | 6 | `Lower.collect_owned_field_vars/3:p2`, `Lower.collect_owned_field_vars/3:ret`, `Lower.ofb/3:p2`, `Lower.ofb/3:ret`, `Lower.owned_field_binders/2:ret`, `Lower.slice_binders/2:ret` |
| `Unk0676` | 1 | `Lower.compile/5:p2` |
| `Unk0677` | 1 | `Lower.compile/5:p3` |
| `Unk0678` | 1 | `Lower.compile_beam/4:p2` |
| `Unk0679` | 1 | `Lower.compile_beam/4:p3` |
| `Unk0680` | 1 | `Lower.compile_elixir/4:p2` |
| `Unk0681` | 1 | `Lower.compile_elixir/4:p3` |
| `Unk0682` | 1 | `Lower.compile_module/1:p0` |
| `Unk0683` | 1 | `Lower.compile_module_beam/1:p0` |
| `Unk0684` | 1 | `Lower.cons_tail_names/1:ret` |
| `Unk0685` | 3 | `Lower.const_set/1:p0`, `Lower.ex_const/2:p0`, `Lower.rust_const/2:p0` |
| `Unk0686` | 2 | `Lower.const_set/1:ret`, `Lower.ctx/4:p2` |
| `Unk0687` | 3 | `Lower.core_pat_rs/2:p1`, `Lower.pat_rs/2:p1`, `Lower.resolve_rust_pats/2:p1` |
| `Unk0688` | 1 | `Lower.core_pat_vars/1:ret` |
| `Unk0689` | 1 | `Lower.ctx/4:p3` |
| `Unk0690` | 2 | `Lower.deref_ids/2:p0`, `Lower.deref_ids/2:ret` |
| `Unk0691` | 1 | `Lower.deref_ids/2:p1` |
| `Unk0692` | 2 | `Lower.elixir_clauses/3:p1`, `Lower.ex_const/2:p1` |
| `Unk0693` | 1 | `Lower.emit_ast/2:ret` |
| `Unk0694` | 1 | `Lower.emit_ctx/1:p0` |
| `Unk0695` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0696` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0697` | 1 | `Lower.emit_expr/2:ret` |
| `Unk0698` | 2 | `Lower.enum_generics/2:p0`, `Lower.enum_generics/2:p1` |
| `Unk0699` | 1 | `Lower.enum_generics/2:p1` |
| `Unk0700` | 1 | `Lower.ex_struct/1:p0` |
| `Unk0701` | 1 | `Lower.ex_typespec/1:p0` |
| `Unk0702` | 1 | `Lower.ex_use/1:p0` |
| `Unk0703` | 2 | `Lower.fn_all_tvars/3:p1`, `Lower.pair_inst/2:ret` |
| `Unk0704` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0705` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0706` | 1 | `Lower.guard_str/4:p0` |
| `Unk0707` | 1 | `Lower.guard_str/4:p3` |
| `Unk0708` | 1 | `Lower.impl_param/2:p0` |
| `Unk0709` | 1 | `Lower.infer_concrete_params/3:p1` |
| `Unk0710` | 1 | `Lower.infer_tvar_binding/2:p0` |
| `Unk0711` | 1 | `Lower.infer_tvar_binding/2:p1` |
| `Unk0712` | 1 | `Lower.infer_tvar_binding/2:ret` |
| `Unk0713` | 1 | `Lower.list_rpat?/1:p0` |
| `Unk0714` | 1 | `Lower.member_scan/3:p0` |
| `Unk0715` | 3 | `Lower.member_scan/3:p1`, `Lower.strip_prefix/2:p1`, `Lower.word_scan/4:p1` |
| `Unk0716` | 1 | `Lower.module_elixir/1:p0` |
| `Unk0717` | 1 | `Lower.module_rust/1:p0` |
| `Unk0718` | 2 | `Lower.ofb/3:p0`, `Lower.owned_field_binders/2:p0` |
| `Unk0719` | 1 | `Lower.owned_scrut?/2:p0` |
| `Unk0720` | 1 | `Lower.owned_str_arg/1:p0` |
| `Unk0721` | 1 | `Lower.owned_str_arg/1:ret` |
| `Unk0722` | 2 | `Lower.parametric_param_map/1:ret`, `Lower.rust_enum/3:p2` |
| `Unk0723` | 2 | `Lower.parametric_used?/2:p1`, `Lower.word_member?/2:p1` |
| `Unk0724` | 2 | `Lower.pascal?/1:p0`, `Lower.variant_info/2:p1` |
| `Unk0725` | 1 | `Lower.pipe_to_call/2:p0` |
| `Unk0726` | 1 | `Lower.proto_method_traits/1:ret` |
| `Unk0727` | 1 | `Lower.pub_sig_type_names/1:p0` |
| `Unk0728` | 1 | `Lower.pub_sig_type_names/1:ret` |
| `Unk0729` | 1 | `Lower.ref_type/2:p1` |
| `Unk0730` | 1 | `Lower.resolve_consts/2:p1` |
| `Unk0731` | 2 | `Lower.resolve_structs/2:p1`, `Lower.struct_pairs/4:p3` |
| `Unk0732` | 3 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0733` | 6 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_info/2:ret`, `Lower.variant_lit/2:p0`, `Lower.variant_pairs/3:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0734` | 1 | `Lower.result_parts/1:ret` |
| `Unk0735` | 2 | `Lower.rewrite_proto_calls/2:p0`, `Lower.rewrite_proto_calls/2:ret` |
| `Unk0736` | 1 | `Lower.rewrite_proto_calls/2:p1` |
| `Unk0737` | 1 | `Lower.rust_case/4:p1` |
| `Unk0738` | 1 | `Lower.rust_generics/1:p0` |
| `Unk0739` | 1 | `Lower.rust_impl_method/6:p0` |
| `Unk0740` | 1 | `Lower.rust_impl_method/6:p1` |
| `Unk0741` | 1 | `Lower.rust_lit_type/1:p0` |
| `Unk0742` | 1 | `Lower.rust_proto_body/3:p0` |
| `Unk0743` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0744` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0745` | 1 | `Lower.rust_proto_body/3:p2` |
| `Unk0746` | 1 | `Lower.rust_proto_body/3:ret` |
| `Unk0747` | 1 | `Lower.rust_protocols/4:ret` |
| `Unk0748` | 1 | `Lower.rust_scrut/2:p0` |
| `Unk0749` | 1 | `Lower.rust_struct/2:p0` |
| `Unk0750` | 1 | `Lower.rust_struct/2:p1` |
| `Unk0751` | 1 | `Lower.rust_trait/1:p0` |
| `Unk0752` | 1 | `Lower.rust_use/1:p0` |
| `Unk0753` | 1 | `Lower.rustify_parametric/2:p1` |
| `Unk0754` | 2 | `Lower.sig_param/2:p1`, `Lower.trait_params/2:p1` |
| `Unk0755` | 1 | `Lower.slice_binders/2:p0` |
| `Unk0756` | 1 | `Lower.slice_elem_vars/1:ret` |
| `Unk0757` | 1 | `Lower.str_lit/1:p0` |
| `Unk0758` | 2 | `Lower.strip_prefix/2:p0`, `Lower.strip_prefix/2:ret` |
| `Unk0759` | 1 | `Lower.strip_prefix/2:ret` |
| `Unk0760` | 1 | `Lower.struct_pairs/4:p0` |
| `Unk0761` | 1 | `Lower.struct_pairs/4:p1` |
| `Unk0762` | 1 | `Lower.struct_pairs/4:ret` |
| `Unk0763` | 1 | `Lower.subst_assoc/2:p1` |
| `Unk0764` | 2 | `Lower.tail_expr/1:p0`, `Lower.tail_expr/1:ret` |
| `Unk0765` | 1 | `Lower.to_elixir/4:p2` |
| `Unk0766` | 1 | `Lower.to_elixir/4:ret` |
| `Unk0767` | 1 | `Lower.to_rust/6:p3` |
| `Unk0768` | 1 | `Lower.to_rust/6:p5` |
| `Unk0769` | 1 | `Lower.to_rust/6:ret` |
| `Unk0770` | 1 | `Lower.tvar_name?/1:p0` |
| `Unk0771` | 1 | `Lower.type_idents/1:p0` |
| `Unk0772` | 1 | `Lower.type_idents/1:ret` |
| `Unk0773` | 1 | `Lower.type_param_tvars/1:p0` |
| `Unk0774` | 1 | `Lower.type_param_tvars/1:ret` |
| `Unk0775` | 1 | `Lower.user_type?/2:p0` |
| `Unk0776` | 2 | `Lower.variant_lit/2:p1`, `Lower.variant_pairs/3:ret` |
| `Unk0777` | 2 | `Lower.widen_char_arith/2:p1`, `Lower.wrap_char/2:p1` |
| `Unk0778` | 1 | `Lower.with_chain_rs/4:p0` |
| `Unk0779` | 1 | `Lower.word_member?/2:p0` |
| `Unk0780` | 1 | `Lower.word_scan/4:p0` |
| `Unk0781` | 4 | `Macro.binders_here/1:p0`, `Macro.collect_binders/1:p0`, `Macro.freshen/2:p0`, `Macro.rename/2:p0` |
| `Unk0782` | 2 | `Macro.binders_here/1:ret`, `Macro.collect_binders/1:ret` |
| `Unk0783` | 1 | `Macro.build_env/1:p0` |
| `Unk0784` | 1 | `Macro.check_portable!/2:p0` |
| `Unk0785` | 1 | `Macro.check_portable!/2:ret` |
| `Unk0786` | 1 | `Macro.expand/3:p2` |
| `Unk0787` | 1 | `Macro.freshen/2:p1` |
| `Unk0788` | 4 | `Macro.freshen/2:ret`, `Macro.rename/2:p1`, `Macro.rename/2:ret`, `Macro.substitute/2:p0` |
| `Unk0789` | 1 | `Macro.rename/2:p1` |
| `Unk0790` | 1 | `Macro.substitute/2:p1` |
| `Unk0791` | 1 | `Opaque.do_erase/2:p0` |
| `Unk0792` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0793` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0794` | 1 | `Opaque.erase_clause/3:p0` |
| `Unk0795` | 1 | `Opaque.erase_clause/3:p1` |
| `Unk0796` | 1 | `Opaque.erase_clause/3:p2` |
| `Unk0797` | 1 | `Opaque.erase_const/2:p0` |
| `Unk0798` | 1 | `Opaque.erase_const/2:p1` |
| `Unk0799` | 3 | `Opaque.erase_ctx/1:p0`, `Opaque.opaques/1:p0`, `Opaque.opaques/1:ret` |
| `Unk0800` | 1 | `Opaque.erase_func/2:p0` |
| `Unk0801` | 1 | `Opaque.erase_mod/2:p0` |
| `Unk0802` | 1 | `Opaque.erase_struct/2:p0` |
| `Unk0803` | 1 | `Opaque.erase_type/2:p0` |
| `Unk0804` | 1 | `Opaque.erase_variant/2:p0` |
| `Unk0805` | 1 | `Opaque.erase_variant/2:p1` |
| `Unk0806` | 1 | `Opaque.opaques/1:p0` |
| `Unk0807` | 4 | `Opaque.strip/3:p0`, `Opaque.strip/3:ret`, `Opaque.strip_into/3:p0`, `Opaque.strip_into/3:ret` |
| `Unk0808` | 2 | `Opaque.strip/3:p1`, `Opaque.strip_into/3:p1` |
| `Unk0809` | 4 | `Opaque.subst/2:p0`, `Opaque.subst/2:ret`, `Opaque.subst_fix/4:p0`, `Opaque.subst_fix/4:ret` |
| `Unk0810` | 2 | `Opaque.subst/2:p1`, `Opaque.subst_fix/4:p1` |
| `Unk0811` | 1 | `Opaque.subst_fix/4:p2` |
| `Unk0812` | 2 | `PatternLower.lower/2:ret`, `PatternLower.lower_list/3:ret` |
| `Unk0813` | 1 | `PatternLower.lower_clause/2:p0` |
| `Unk0814` | 1 | `PatternLower.lower_many/2:ret` |
| `Unk0815` | 2 | `PortAnalysis.analyze/1:p0`, `PortAnalysis.src_of/2:p0` |
| `Unk0816` | 1 | `PortAnalysis.analyze/1:ret` |
| `Unk0817` | 3 | `PortAnalysis.case_arm_sets/1:p0`, `PortAnalysis.clause_head_sets/1:p0`, `PortAnalysis.dispatch_sets/1:p0` |
| `Unk0818` | 2 | `PortAnalysis.case_arm_sets/1:ret`, `PortAnalysis.clause_head_sets/1:ret` |
| `Unk0819` | 2 | `PortAnalysis.cluster_sums/1:p0`, `PortAnalysis.dispatch_sets/1:ret` |
| `Unk0820` | 1 | `PortAnalysis.collect_errors/2:p0` |
| `Unk0821` | 2 | `PortAnalysis.collect_errors/2:p1`, `PortAnalysis.collect_errors/2:ret` |
| `Unk0822` | 1 | `PortAnalysis.collect_groups/1:p0` |
| `Unk0823` | 1 | `PortAnalysis.collect_structs/2:p0` |
| `Unk0824` | 2 | `PortAnalysis.collect_structs/2:p1`, `PortAnalysis.collect_structs/2:ret` |
| `Unk0825` | 1 | `PortAnalysis.error_proposal/1:p0` |
| `Unk0826` | 1 | `PortAnalysis.error_proposal/1:ret` |
| `Unk0827` | 1 | `PortAnalysis.error_shape/1:p0` |
| `Unk0828` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0829` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0830` | 6 | `PortAnalysis.errors_section/1:p0`, `PortAnalysis.holes_section/1:p0`, `PortAnalysis.sigs_section/1:p0`, `PortAnalysis.summary_section/1:p0`, `PortAnalysis.sums_section/1:p0`, `PortAnalysis.to_markdown/1:p0` |
| `Unk0831` | 1 | `PortAnalysis.head_name_pats/1:p0` |
| `Unk0832` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0833` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0834` | 2 | `PortAnalysis.module_name/1:p0`, `PortAnalysis.module_report/3:p1` |
| `Unk0835` | 1 | `PortAnalysis.module_report/3:p0` |
| `Unk0836` | 3 | `PortAnalysis.module_report/3:p2`, `PortAnalysis.src_of/2:ret`, `Transpile.inferred/1:p0` |
| `Unk0837` | 1 | `PortAnalysis.module_report/3:ret` |
| `Unk0838` | 1 | `PortAnalysis.module_stmts/1:p0` |
| `Unk0839` | 1 | `PortAnalysis.needs_review?/1:p0` |
| `Unk0840` | 1 | `PortAnalysis.param_name_index/1:ret` |
| `Unk0841` | 1 | `PortAnalysis.parse/1:p0` |
| `Unk0842` | 1 | `PortAnalysis.parse/1:ret` |
| `Unk0843` | 1 | `PortAnalysis.pascal/1:p0` |
| `Unk0844` | 1 | `PortAnalysis.pascal/1:ret` |
| `Unk0845` | 1 | `PortAnalysis.pattern_structs/1:p0` |
| `Unk0846` | 1 | `PortAnalysis.pattern_structs/1:ret` |
| `Unk0847` | 1 | `PortAnalysis.reach_note/1:p0` |
| `Unk0848` | 1 | `PortAnalysis.reach_note/1:ret` |
| `Unk0849` | 1 | `PortAnalysis.short/1:p0` |
| `Unk0850` | 1 | `PortAnalysis.src_of/2:p1` |
| `Unk0851` | 1 | `PortAnalysis.to_markdown/1:ret` |
| `Unk0852` | 3 | `Pratt.after_paren/2:p0`, `Pratt.after_paren/2:ret`, `Pratt.lambda_ahead?/1:p0` |
| `Unk0853` | 6 | `Pratt.assoc/1:p0`, `Pratt.bp/1:p0`, `Pratt.level/1:p0`, `Pratt.opinfo/1:p0`, `Pratt.peek_infix/1:ret`, `Pratt.same_level_root?/2:p1` |
| `Unk0854` | 1 | `Pratt.assoc/1:ret` |
| `Unk0855` | 4 | `Pratt.climb/3:p0`, `Pratt.climb/3:ret`, `Pratt.parse_expr/2:ret`, `Pratt.same_level_root?/2:p0` |
| `Unk0856` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0857` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0858` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0859` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0860` | 3 | `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0861` | 3 | `Pratt.finish_arg/2:p0`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:ret` |
| `Unk0862` | 2 | `Pratt.here/1:p0`, `Pratt.tok_desc/1:p0` |
| `Unk0863` | 1 | `Pratt.int_of/1:p0` |
| `Unk0864` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0865` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0866` | 1 | `Pratt.level/1:ret` |
| `Unk0867` | 1 | `Pratt.opinfo/1:ret` |
| `Unk0868` | 2 | `Pratt.parse_arms/2:p1`, `Pratt.parse_arms/2:ret` |
| `Unk0869` | 13 | `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0870` | 1 | `Pratt.parse_list/2:p1` |
| `Unk0871` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0872` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0873` | 1 | `Pratt.parse_params/1:ret` |
| `Unk0874` | 4 | `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:ret` |
| `Unk0875` | 2 | `Pratt.parse_pat_args/2:p1`, `Pratt.parse_pat_args/2:ret` |
| `Unk0876` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0877` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0878` | 1 | `Pratt.parse_pat_list/2:p1` |
| `Unk0879` | 3 | `Pratt.parse_pats/1:ret`, `Pratt.parse_pats/2:p1`, `Pratt.parse_pats/2:ret` |
| `Unk0880` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0881` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0882` | 2 | `Pratt.parse_stmts/2:p1`, `Pratt.parse_stmts/2:ret` |
| `Unk0883` | 2 | `Pratt.parse_type_args/2:p1`, `Pratt.parse_type_args/2:ret` |
| `Unk0884` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0885` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0886` | 1 | `Pratt.pascal?/1:p0` |
| `Unk0887` | 1 | `Pratt.sexpr_pat/1:p0` |
| `Unk0888` | 1 | `Pratt.sexpr_stmt/1:p0` |
| `Unk0889` | 1 | `Pratt.str_interp/1:p0` |
| `Unk0890` | 1 | `Protocol.check_assoc!/2:ret` |
| `Unk0891` | 1 | `Protocol.check_impl/3:p0` |
| `Unk0892` | 3 | `Protocol.check_impl/3:p1`, `Protocol.expand/5:p0`, `Protocol.impl_methods/2:p1` |
| `Unk0893` | 5 | `Protocol.check_impl/3:p2`, `Protocol.check_no_overlap/3:p1`, `Protocol.dispatcher/4:p3`, `Protocol.guard_for!/3:p2`, `Protocol.registry/2:ret` |
| `Unk0894` | 1 | `Protocol.check_impl/3:ret` |
| `Unk0895` | 4 | `Protocol.check_no_overlap/3:p0`, `Protocol.dispatcher/4:p2`, `Protocol.expand/5:p1`, `Protocol.impl_methods/2:p0` |
| `Unk0896` | 2 | `Protocol.check_no_overlap/3:p2`, `Protocol.runtime_dispatch_target?/1:p0` |
| `Unk0897` | 1 | `Protocol.check_no_overlap/3:ret` |
| `Unk0898` | 2 | `Protocol.dispatcher/4:p0`, `Protocol.guard_for!/3:p1` |
| `Unk0899` | 1 | `Protocol.dispatcher/4:p1` |
| `Unk0900` | 1 | `Protocol.dispatcher/4:ret` |
| `Unk0901` | 1 | `Protocol.dispatcher_params/2:p0` |
| `Unk0902` | 1 | `Protocol.dispatcher_params/2:ret` |
| `Unk0903` | 1 | `Protocol.guard_for!/3:ret` |
| `Unk0904` | 1 | `Protocol.mangle/3:p0` |
| `Unk0905` | 1 | `Protocol.mangle/3:p1` |
| `Unk0906` | 1 | `Protocol.mangle/3:p2` |
| `Unk0907` | 1 | `Protocol.param_type/1:p0` |
| `Unk0908` | 1 | `Protocol.param_type/1:ret` |
| `Unk0909` | 1 | `Protocol.registry/2:p0` |
| `Unk0910` | 1 | `Protocol.registry/2:p1` |
| `Unk0911` | 1 | `Protocol.subst_self/2:p0` |
| `Unk0912` | 1 | `Protocol.subst_self/2:p1` |
| `Unk0913` | 1 | `Protocol.subst_self/2:ret` |
| `Unk0914` | 1 | `Protocol.sum_guard/1:p0` |
| `Unk0915` | 1 | `Protocol.tag_disjunction/2:p0` |
| `Unk0916` | 1 | `Protocol.tag_disjunction/2:p1` |
| `Unk0917` | 1 | `Range.check/3:p0` |
| `Unk0918` | 1 | `Range.check/3:p1` |
| `Unk0919` | 1 | `Range.lit/1:p0` |
| `Unk0920` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0921` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0922` | 4 | `Reach.all_emittable?/2:p1`, `Reach.parametric_ctx/2:ret`, `Reach.parametric_rs_ok?/2:p1`, `Reach.scan_func/3:p2` |
| `Unk0923` | 1 | `Reach.analyze/1:ret` |
| `Unk0924` | 15 | `Reach.atom_prim_blocker/0:ret`, `Reach.bare_atom_blocker/0:ret`, `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.ffi/2:ret`, `Reach.fn_type_blocker/0:ret`, `Reach.int_blocker/0:ret`, `Reach.parametric_blocker/0:ret`, `Reach.ref_blocker/0:ret`, `Reach.result_value_blocker/0:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret`, `Reach.wide_prim_blocker/0:ret`, `Reach.width_blocker/0:ret` |
| `Unk0925` | 5 | `Reach.build_default/0:ret`, `Reach.check_contracts/2:p1`, `Reach.gate!/2:p1`, `Reach.validate_default/1:p0`, `Reach.validate_default/1:ret` |
| `Unk0926` | 2 | `Reach.builder_tail_ok?/2:p1`, `Reach.tail_calls_generic?/2:p1` |
| `Unk0927` | 1 | `Reach.check_contracts/2:ret` |
| `Unk0928` | 3 | `Reach.classify/3:p1`, `Reach.scan/3:p1`, `Reach.scan_func/3:p1` |
| `Unk0929` | 5 | `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret` |
| `Unk0930` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0931` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0932` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0933` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0934` | 1 | `Reach.conc_erl?/2:p1` |
| `Unk0935` | 1 | `Reach.contract_message/1:p0` |
| `Unk0936` | 1 | `Reach.core/2:p0` |
| `Unk0937` | 1 | `Reach.core/2:p1` |
| `Unk0938` | 1 | `Reach.core/2:p1` |
| `Unk0939` | 2 | `Reach.deep/1:p0`, `Reach.find_atom_ordering/1:p0` |
| `Unk0940` | 3 | `Reach.deep/1:ret`, `Reach.find_atom_ordering/1:ret`, `Reach.func_symbol_violations/1:ret` |
| `Unk0941` | 1 | `Reach.emittable_parametric?/1:p0` |
| `Unk0942` | 1 | `Reach.emittable_parametric?/1:ret` |
| `Unk0943` | 1 | `Reach.fixpoint/2:p0` |
| `Unk0944` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0945` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0946` | 1 | `Reach.func_symbol_violations/1:p0` |
| `Unk0947` | 1 | `Reach.js_wide_int?/1:p0` |
| `Unk0948` | 1 | `Reach.mix_default/0:ret` |
| `Unk0949` | 1 | `Reach.parametric_type?/1:p0` |
| `Unk0950` | 1 | `Reach.pascal?/1:p0` |
| `Unk0951` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0952` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0953` | 1 | `Reach.sig_idents/1:ret` |
| `Unk0954` | 1 | `Reach.tail_calls_generic?/2:p0` |
| `Unk0955` | 1 | `Reach.tvar?/1:p0` |
| `Unk0956` | 1 | `Reach.tvar?/1:ret` |
| `Unk0957` | 2 | `Reach.type_has_tvar?/1:p0`, `Reach.type_idents/1:p0` |
| `Unk0958` | 1 | `Reach.type_idents/1:ret` |
| `Unk0959` | 1 | `Reach.uses_parametric?/2:p1` |
| `Unk0960` | 1 | `Repl.accumulate_line/2:p1` |
| `Unk0961` | 1 | `Repl.bind_env/2:p0` |
| `Unk0962` | 9 | `Repl.bind_env/2:ret`, `Repl.bind_with_type/4:p3`, `Repl.infer_or_unknown/3:p1`, `Repl.infer_or_unknown/3:ret`, `Repl.safe_infer/3:p1`, `Repl.safe_infer/3:ret`, `Repl.safe_infer_input/3:p1`, `Repl.safe_infer_input/3:ret`, `Repl.type_of/2:ret` |
| `Unk0963` | 4 | `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:ret`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:ret` |
| `Unk0964` | 1 | `Repl.candidate_pool/2:p0` |
| `Unk0965` | 1 | `Repl.candidate_pool/2:ret` |
| `Unk0966` | 2 | `Repl.common_prefix/2:p0`, `Repl.common_prefix/3:p0` |
| `Unk0967` | 2 | `Repl.common_prefix/2:p1`, `Repl.common_prefix/3:p1` |
| `Unk0968` | 1 | `Repl.complete/2:p1` |
| `Unk0969` | 2 | `Repl.complete/2:ret`, `Repl.continuation/2:p1` |
| `Unk0970` | 8 | `Repl.decl_names/1:ret`, `Repl.eval_decl/2:p0`, `Repl.eval_decl/2:ret`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0971` | 1 | `Repl.describe/1:p0` |
| `Unk0972` | 1 | `Repl.describe/1:ret` |
| `Unk0973` | 1 | `Repl.eval/2:p0` |
| `Unk0974` | 1 | `Repl.eval/2:ret` |
| `Unk0975` | 2 | `Repl.eval_decl/2:p0`, `Repl.reload/2:p0` |
| `Unk0976` | 6 | `Repl.eval_decl/2:p0`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0977` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0978` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0979` | 1 | `Repl.flush_entries/1:p0` |
| `Unk0980` | 1 | `Repl.flush_entries/1:ret` |
| `Unk0981` | 1 | `Repl.info/1:ret` |
| `Unk0982` | 2 | `Repl.longest_common_prefix/1:p0`, `Repl.longest_common_prefix/1:ret` |
| `Unk0983` | 2 | `Repl.program/3:p1`, `Repl.run/4:p1` |
| `Unk0984` | 1 | `Repl.render/1:p0` |
| `Unk0985` | 1 | `Repl.run/4:ret` |
| `Unk0986` | 1 | `Repl.run/4:ret` |
| `Unk0987` | 1 | `Repl.safe_parse_body/1:ret` |
| `Unk0988` | 1 | `Repl.scan_count/2:p1` |
| `Unk0989` | 1 | `Repl.scan_count/2:ret` |
| `Unk0990` | 1 | `Repl.type_of/2:p0` |
| `Unk0991` | 1 | `SelfHost.badge/1:p0` |
| `Unk0992` | 1 | `SelfHost.composition/0:ret` |
| `Unk0993` | 1 | `SelfHost.count/1:p0` |
| `Unk0994` | 1 | `SelfHost.evidence/1:p0` |
| `Unk0995` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0996` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0997` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0998` | 1 | `SelfHost.external_host_calls/1:ret` |
| `Unk0999` | 1 | `SelfHost.ffi_ledger/0:ret` |
| `Unk1000` | 1 | `SelfHost.passes/0:ret` |
| `Unk1001` | 1 | `SelfHost.sibling_compose_call?/2:p0` |
| `Unk1002` | 1 | `SelfHost.sibling_compose_call?/2:p1` |
| `Unk1003` | 1 | `SelfHost.stages/0:ret` |
| `Unk1004` | 1 | `SelfHost.status_markdown/1:p0` |
| `Unk1005` | 1 | `Shadow.ded_bind/5:p0` |
| `Unk1006` | 3 | `Shadow.ded_bind/5:p2`, `Shadow.ded_expr/3:p0`, `Shadow.ded_expr/3:ret` |
| `Unk1007` | 1 | `Shadow.ded_bind/5:p3` |
| `Unk1008` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1009` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1010` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1011` | 1 | `Shadow.ded_bind/5:ret` |
| `Unk1012` | 2 | `Shadow.ded_block/4:p0`, `Shadow.dedup/3:p0` |
| `Unk1013` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk1014` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk1015` | 1 | `Shadow.ded_block/4:p2` |
| `Unk1016` | 1 | `Shadow.pat_var_names/1:ret` |
| `Unk1017` | 1 | `Test.run/2:p1` |
| `Unk1018` | 1 | `Test.run/2:ret` |
| `Unk1019` | 1 | `Tour.build_cell/1:p0` |
| `Unk1020` | 1 | `Tour.build_cell/1:ret` |
| `Unk1021` | 1 | `Tour.build_reach_example/1:p0` |
| `Unk1022` | 1 | `Tour.build_reach_example/1:ret` |
| `Unk1023` | 1 | `Tour.elixir_module/1:ret` |
| `Unk1024` | 2 | `Tour.encode/2:p0`, `Tour.encode_string/1:p0` |
| `Unk1025` | 1 | `Tour.generate/0:ret` |
| `Unk1026` | 1 | `Tour.reach_map/1:ret` |
| `Unk1027` | 1 | `Transpile.add_clause/2:p0` |
| `Unk1028` | 5 | `Transpile.add_clause/2:p0`, `Transpile.add_clause/2:p1`, `Transpile.build_clause/2:ret`, `Transpile.new_group/3:p1`, `Transpile.same_group?/3:p2` |
| `Unk1029` | 2 | `Transpile.add_clause/2:ret`, `Transpile.new_group/3:ret` |
| `Unk1030` | 1 | `Transpile.build_clause/2:p0` |
| `Unk1031` | 1 | `Transpile.build_clause/2:p1` |
| `Unk1032` | 1 | `Transpile.case_arm/1:p0` |
| `Unk1033` | 1 | `Transpile.classify/1:ret` |
| `Unk1034` | 4 | `Transpile.close_group/2:p0`, `Transpile.close_group/2:p1`, `Transpile.close_group/2:ret`, `Transpile.def_groups/1:ret` |
| `Unk1035` | 1 | `Transpile.escape/1:p0` |
| `Unk1036` | 1 | `Transpile.escape/1:ret` |
| `Unk1037` | 2 | `Transpile.escape_lit/1:p0`, `Transpile.string_part/1:p0` |
| `Unk1038` | 1 | `Transpile.flush/2:p0` |
| `Unk1039` | 2 | `Transpile.flush/2:p1`, `Transpile.render_items/2:p1` |
| `Unk1040` | 2 | `Transpile.flush/2:p1`, `Transpile.render_items/2:p1` |
| `Unk1041` | 1 | `Transpile.hole_sig?/1:p0` |
| `Unk1042` | 2 | `Transpile.infer_program/1:p0`, `Transpile.infer_sigs/1:p0` |
| `Unk1043` | 3 | `Transpile.infer_program/1:ret`, `Transpile.infer_sigs/1:ret`, `Transpile.inferred/1:ret` |
| `Unk1044` | 1 | `Transpile.infer_report/1:p0` |
| `Unk1045` | 1 | `Transpile.infer_report/1:ret` |
| `Unk1046` | 1 | `Transpile.max_placeholder/1:p0` |
| `Unk1047` | 4 | `Transpile.mod_str/1:p0`, `Transpile.short_name/1:p0`, `Transpile.snippet/1:p0`, `Transpile.var_name/1:p0` |
| `Unk1048` | 1 | `Transpile.module_groups/1:p0` |
| `Unk1049` | 1 | `Transpile.module_groups/1:ret` |
| `Unk1050` | 1 | `Transpile.moduledoc_lines/1:p0` |
| `Unk1051` | 1 | `Transpile.name_str/1:p0` |
| `Unk1052` | 1 | `Transpile.name_str/1:ret` |
| `Unk1053` | 1 | `Transpile.new_group/3:p0` |
| `Unk1054` | 1 | `Transpile.new_group/3:p2` |
| `Unk1055` | 1 | `Transpile.one_line/1:p0` |
| `Unk1056` | 1 | `Transpile.one_line/1:ret` |
| `Unk1057` | 1 | `Transpile.prime_xmod/1:p0` |
| `Unk1058` | 1 | `Transpile.prime_xmod/1:ret` |
| `Unk1059` | 1 | `Transpile.rank/1:p0` |
| `Unk1060` | 1 | `Transpile.rank/1:ret` |
| `Unk1061` | 1 | `Transpile.render_clause/2:p1` |
| `Unk1062` | 1 | `Transpile.same_group?/3:p0` |
| `Unk1063` | 1 | `Transpile.same_group?/3:p1` |
| `Unk1064` | 1 | `Transpile.sibling_module?/2:p0` |
| `Unk1065` | 1 | `Transpile.simple?/1:p0` |
| `Unk1066` | 1 | `Transpile.string_part/1:ret` |
| `Unk1067` | 1 | `Transpile.string_parts/1:p0` |
| `Unk1068` | 1 | `Transpile.string_parts/1:ret` |
| `Unk1069` | 2 | `Transpile.subst_ph/2:p0`, `Transpile.subst_ph/2:ret` |
| `Unk1070` | 1 | `Transpile.subst_ph/2:p1` |
| `Unk1071` | 1 | `Transpile.toplevel/3:p0` |
| `Unk1072` | 1 | `Transpile.toplevel/3:p1` |
| `Unk1073` | 2 | `Transpile.transpile/2:p0`, `Transpile.transpile_with_stats/2:p0` |
| `Unk1074` | 1 | `Transpile.transpile/2:p1` |
| `Unk1075` | 2 | `Transpile.transpile/2:ret`, `Transpile.transpile_with_stats/2:ret` |
| `Unk1076` | 1 | `Transpile.transpile_with_stats/2:p1` |
| `Unk1077` | 1 | `Transpile.transpile_with_stats/2:ret` |
| `Unk1078` | 1 | `Transpile.underscore_var/1:p0` |
| `Unk1079` | 1 | `Transpile.var?/1:p0` |

## 3. Proposed sum-type groupings — REVIEW (heuristic from dispatch co-occurrence)

Structs clustered by co-occurrence in multi-clause heads + `case` arms. This is
the non-local decision a human cannot make from a single draft file. Confirm or
split each cluster; ambiguous structs (bridging two clusters) are merged here and
may need splitting.

**Cluster 1** (co-occur in dispatch) — propose `type <NAME?> := EAtom | EBin | EBlock | ECall | ECapArg | ECapture | ECaptureNamed | ECase | EChar | EConstRef | EDot | EId | EIf | ELambda | EList | EMap | ENum | EStr | EStruct | ETuple | EUnary | EVariant | EWith`
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
  - [ ] human: name the sum, confirm membership, set field types/reach

**Cluster 2** (co-occur in dispatch) — propose `type <NAME?> := PAs | PAtom | PChar | PCtor | PList | PLit | PMap | PPin | PStruct | PTuple | PVar | PWild`
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
  - [ ] human: name the sum, confirm membership, set field types/reach

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
| `list()` (expr) | 2 | **NEEDS DECISION** | — |
| `_reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `contract_message(vs)` (expr) | 1 | **NEEDS DECISION** | — |
| `"cannot read: #{:file.format_e` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: range `#{ann}` is ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: body has type `#{b` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{op}`: no implicit Int↔Floa` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: binding declared `` (expr) | 1 | **NEEDS DECISION** | — |
| `{:__aliases__, _, parts}` (expr) | 1 | **NEEDS DECISION** | — |
| `tag` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"`<~` is in-place mutation of ` (expr) | 1 | **NEEDS DECISION** | — |
| `x` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"`#{f.name}`: returns error(s)` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an `@external` par` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: literal #{v} is ou` (expr) | 1 | **NEEDS DECISION** | — |
| `parts |> List.last() |> to_str` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{f}(…)`: labeled arguments ` (expr) | 1 | **NEEDS DECISION** | — |
| `bad` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"unsupported in comptime: #{in` (expr) | 1 | **NEEDS DECISION** | — |
| `"operator `#{op}` not allowed ` (expr) | 1 | **NEEDS DECISION** | — |
| `{:already_started, pid}` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{g}` requires `#{tvar}: #{p` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{n}`: literal #{v} is out o` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{x}` is not a compile-time ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: value of type `#{t` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an integer literal` (expr) | 1 | **NEEDS DECISION** | — |

