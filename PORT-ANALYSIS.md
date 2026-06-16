# Port Analysis — Elixir → Rian

**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the
`REVIEW` sections and record decisions in a `port.spec` (feedback loop not yet
wired). Regenerate to diff against source — do not hand-edit this file.

## Summary

- modules: 45 · type slots: 3072 · auto-filled: 726 (24%) · holes: 2346
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
| `assignable?/2` | `(Ty, Ty) Bool` | ✓ all 4 |
| `concretize/1` | `(T) T forall T` | ✓ all 4 |
| `conservative/1` | `(T) T forall T` | ✓ all 4 |
| `debottom/1` | `(T) T forall T` | ✓ all 4 |
| `deplaceholder/1` | `(String) String` | ✓ all 4 |
| `float_mantissa/1` | `(Int53) Int53` | ✓ all 4 |
| `int_float_join/2` | `(Int53, Int53) String` | ✓ all 4 |
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
  pub def lin_check(env Map(Unk0070, Unk0071), ast Unk0069) Tuple(Unk0072, Vec(Unk0073)) := …

  # Capability.lin_check_block/3
  pub def lin_check_block(env Map(Unk0075, Unk0074), bindings Vec(Unk0076), final Unk0069) Tuple(Unk0072, Vec(Unk0073)) := …

  # Capability.max_merge/2
  pub def max_merge(a Unk0068, b Unk0068) Unk0068 := …

  # Capability.merge/2
  pub def merge(a Unk0068, b Unk0068) Unk0068 := …

  # Capability.pat_vars/1
  pub def pat_vars(p0 Unk0077) Unk0078 := …

  # Capability.verdict/2
  pub def verdict(env Map(Unk0070, Unk0071), uses Unk0068) Tuple(Unk0072, Vec(Unk0073)) := …

  # Check.abstract_cast_ret/3
  pub def abstract_cast_ret(ht Vec(Unk0079), cn Unk0080, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.abstract_op_type/4
  pub def abstract_op_type(op Unk0082, lt Vec(Unk0079), rt Vec(Unk0079), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0083 := …

  # Check.adoptable_int?/1
  pub def adoptable_int?(t Vec(Unk0079)) Bool := …

  # Check.all_types/1
  pub def all_types(prog Map(Unk0084, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Type) := …

  # Check.ann_each/3
  pub def ann_each(nodes Vec(Option(Unk0017)), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.ann_stmts/3
  pub def ann_stmts(p0 Vec(Unk0086), _env Map(Unk0085, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.annotate/3
  pub def annotate(ast Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.arith_type/4
  pub def arith_type(l Sum1, r Sum1, lt Vec(Unk0079), rt Vec(Unk0079)) Unk0087 := …

  # Check.assignable?/2
  pub def assignable?(t Vec(Unk0079), t Vec(Unk0079)) Bool := …

  # Check.bind_mismatch/5
  pub def bind_mismatch(name Unk0088, ann Vec(Unk0079), e Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0089) := …

  # Check.bind_tvar/4
  pub def bind_tvar(_p Unk0090, p1 Unk0090, _tvars Unk0091, acc Map(Unk0092, Vec(Unk0079))) Map(Unk0092, Vec(Unk0079)) := …

  # Check.body_literal_adopts?/2
  pub def body_literal_adopts?(p0 Option(Unk0017), ret Vec(Unk0079)) Bool := …

  # Check.branch_join/1
  pub def branch_join(typed Vec(Tuple(Unk0093, Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.build_fn/2
  pub def build_fn(args Vec(Unk0094), ret Vec(Unk0079)) String := …

  # Check.call_bound_error/5
  pub def call_bound_error(g Vec(Unk0079), args Vec(Option(Unk0017)), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0095) := …

  # Check.call_name/1
  pub def call_name(p0 Unk0096) Vec(Unk0097) := …

  # Check.called_ret/2
  pub def called_ret(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), f Vec(Unk0079)) Vec(Unk0079) := …

  # Check.called_ret_with/4
  pub def called_ret_with(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), f Vec(Unk0079), args_ast Vec(Option(Unk0017)), env Map(Unk0085, Vec(Unk0079))) Vec(Unk0079) := …

  # Check.check/1
  pub def check(src String) Unk0098 := …

  # Check.check_bind_stmts/3
  pub def check_bind_stmts(p0 Vec(Unk0099), _env Map(Unk0085, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0089) := …

  # Check.check_binds/2
  pub def check_binds(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0100 := …

  # Check.check_bounds/2
  pub def check_bounds(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0101 := …

  # Check.check_error_set/2
  pub def check_error_set(p0 Unk0102, p1 Unk0103) Tuple(Unk0104, String) := …

  # Check.check_external_caps/1
  pub def check_external_caps(p0 Func) Tuple(Unk0105, String) := …

  # Check.check_func/3
  pub def check_func(p0 Unk0106, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), eset Unk0103) Unk0107 := …

  # Check.check_labels/1
  pub def check_labels(p0 Func) Unk0108 := …

  # Check.check_numeric_mix/2
  pub def check_numeric_mix(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0109 := …

  # Check.check_program/1
  pub def check_program(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0110 := …

  # Check.check_return/2
  pub def check_return(p0 Func, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0111 := …

  # Check.clause_env/3
  pub def clause_env(pats Unk0112, params Unk0113, ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Map(Unk0085, Vec(Unk0079)) := …

  # Check.comp_str/1
  pub def comp_str(p0 Unk0114) String := …

  # Check.concrete_type?/1
  pub def concrete_type?(p0 Vec(Unk0079)) Bool := …

  # Check.const_int/1
  pub def const_int(p0 Option(Unk0017)) Tuple(Unk0116, Unk0115) := …

  # Check.ctor_type/2
  pub def ctor_type(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), name Vec(Unk0079)) Vec(Unk0079) := …

  # Check.ctor_types/2
  pub def ctor_types(types Vec(Type), prog Map(Unk0117, Vec(Unk0118))) Map(Unk0119, Unk0120) := …

  # Check.debottom/1
  pub def debottom(p0 Unk0121) Unk0121 := …

  # Check.declared_set/2
  pub def declared_set(ret Unk0122, tsets Map(Unk0123, Vec(Unk0123))) Tuple(Unk0123, Unk0124) := …

  # Check.direct_tags/1
  pub def direct_tags(f Unk0125) Unk0126 := …

  # Check.error_sets/1
  pub def error_sets(types Vec(Type)) Map(Unk0123, Vec(Unk0123)) := …

  # Check.error_tags/1
  pub def error_tags(p0 Vec(Unk0127)) Vec(Option(Unk0128)) := …

  # Check.fbound_table/1
  pub def fbound_table(funcs Vec(Unk0129)) Unk0130 := …

  # Check.first_bound_violation/4
  pub def first_bound_violation(g Vec(Unk0079), bounds Unk0131, subs Map(Unk0092, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0095) := …

  # Check.fixpoint/2
  pub def fixpoint(facts Unk0132, table Map(Unk0134, Unk0133)) Map(Unk0134, Unk0133) := …

  # Check.float_type?/1
  pub def float_type?(t Vec(Unk0079)) Bool := …

  # Check.fn_parts/1
  pub def fn_parts(p0 String) Unk0135 := …

  # Check.fn_ret/1
  pub def fn_ret(ft Vec(Unk0079)) Vec(Unk0079) := …

  # Check.fsig/1
  pub def fsig(f Unk0136) Unk0137 := …

  # Check.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Check.generic_ret?/2
  pub def generic_ret?(_ret Unk0138, p1 Vec(Unk0139)) Bool := …

  # Check.has_tvar?/1
  pub def has_tvar?(s Vec(Unk0079)) Bool := …

  # Check.impl_table/1
  pub def impl_table(prog Map(Unk0141, Vec(Unk0140))) Unk0142 := …

  # Check.infer/3
  pub def infer(ast Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.infer_block/4
  pub def infer_block(p0 Vec(Unk0143), _env Map(Unk0085, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), value Vec(Unk0079)) Vec(Unk0079) := …

  # Check.infer_tail/3
  pub def infer_tail(p0 Option(Unk0017), _env Map(Unk0085, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.inner_of/1
  pub def inner_of(p0 Unk0090) Unk0090 := …

  # Check.instantiate_ret/2
  pub def instantiate_ret(p0 Unk0144, arg_types Vec(Vec(Unk0079))) Vec(Unk0079) := …

  # Check.int_lit_expr?/1
  pub def int_lit_expr?(p0 Sum1) Bool := …

  # Check.int_literal?/1
  pub def int_literal?(n Unk0145) Bool := …

  # Check.int_type?/1
  pub def int_type?(t Vec(Unk0079)) Bool := …

  # Check.join/2
  pub def join(t String, t String) Option(Unk0146) := …

  # Check.join_all/1
  pub def join_all(types Vec(Unk0147)) Vec(Unk0079) := …

  # Check.kind_prefix/1
  pub def kind_prefix(p0 Unk0148) String := …

  # Check.label_error/1
  pub def label_error(p0 Option(Unk0017)) Tuple(Unk0149, String) := …

  # Check.label_error_children/1
  pub def label_error_children(node Option(Unk0017)) Tuple(Unk0149, String) := …

  # Check.list_elem/1
  pub def list_elem(p0 Vec(Unk0079)) Unk0150 := …

  # Check.list_elems/1
  pub def list_elems(p0 Option(Unk0017)) Vec(Unk0151) := …

  # Check.lit_expr_adopts?/2
  pub def lit_expr_adopts?(p0 Option(Unk0017), ret Vec(Unk0079)) Bool := …

  # Check.lit_range_error/3
  pub def lit_range_error(expr Option(Unk0017), p1 String, name Unk0088) Option(Unk0152) := …

  # Check.literal_adopts?/2
  pub def literal_adopts?(p0 Sum1, ann Vec(Unk0079)) Bool := …

  # Check.literal_ordinal/2
  pub def literal_ordinal(p0 Sum1, p1 String) Tuple(Unk0153, Int53) := …

  # Check.missing_impl/5
  pub def missing_impl(g Vec(Unk0079), tvar Unk0154, ty Vec(Unk0079), protos Unk0155, impls Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0156) := …

  # Check.narrow/4
  pub def narrow(p0 Sum2, type Vec(Unk0079), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), env Map(Unk0085, Vec(Unk0079))) Map(Unk0085, Vec(Unk0079)) := …

  # Check.num_bits/2
  pub def num_bits(kind Unk0157, w Unk0158) Option(Unk0159) := …

  # Check.num_join/2
  pub def num_join(p0 Unk0160, p1 Unk0161) String := …

  # Check.num_kind/1
  pub def num_kind(p0 String) Option(Unk0159) := …

  # Check.num_lub/2
  pub def num_lub(x String, y String) Unk0162 := …

  # Check.num_mix?/2
  pub def num_mix?(p0 Unk0163, k Unk0164) Bool := …

  # Check.num_mix_error/5
  pub def num_mix_error(op Unk0165, l Option(Unk0017), r Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Unk0166 := …

  # Check.num_widens?/2
  pub def num_widens?(p0 Unk0167, p1 Unk0168) Bool := …

  # Check.oor_scan/5
  pub def oor_scan(p0 Option(Unk0017), ty String, lo Unk0169, hi Unk0170, n Unk0088) Option(Unk0152) := …

  # Check.opaque_table/1
  pub def opaque_table(prog Map(Unk0172, Vec(Unk0171))) Unk0173 := …

  # Check.pascal?/1
  pub def pascal?(s Unk0174) Bool := …

  # Check.produced_set/2
  pub def produced_set(f Unk0125, table Map(Unk0175, Unk0176)) Unk0177 := …

  # Check.program_ic/1
  pub def program_ic(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))) := …

  # Check.propagated_callees/1
  pub def propagated_callees(f Unk0125) Unk0178 := …

  # Check.range_base/2
  pub def range_base(ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), n Vec(Unk0079)) Option(Unk0179) := …

  # Check.range_bind/6
  pub def range_bind(name Unk0088, ann Vec(Unk0079), p2 Unk0180, ce Sum1, env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0181) := …

  # Check.range_table/1
  pub def range_table(prog Map(Unk0183, Vec(Unk0182))) Unk0184 := …

  # Check.resolve_range/2
  pub def resolve_range(t Vec(Unk0079), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Check.scan_bound_calls/4
  pub def scan_bound_calls(p0 Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0185) := …

  # Check.scan_num_mix/3
  pub def scan_num_mix(p0 Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0186) := …

  # Check.scan_num_mix_children/3
  pub def scan_num_mix_children(node Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Option(Unk0186) := …

  # Check.solve_error_sets/2
  pub def solve_error_sets(funcs Vec(Unk0187), tsets Map(Unk0123, Vec(Unk0123))) Map(Unk0134, Unk0133) := …

  # Check.tag_name/1
  pub def tag_name(p0 Unk0188) Option(Unk0128) := …

  # Check.type_table/1
  pub def type_table(types Vec(Type)) Unk0189 := …

  # Check.uint_signed_join/2
  pub def uint_signed_join(u Unk0190, i Unk0190) String := …

  # Check.walk_children/4
  pub def walk_children(node Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), fbounds Map(Vec(Unk0079), Vec(Unk0079))) Option(Unk0185) := …

  # Check.with_callees/1
  pub def with_callees(p0 Vec(Unk0191)) Vec(Unk0097) := …

  # Comptime.eval/1
  pub def eval(p0 Unk0192) Tuple(Unk0193, String) := …

  # Comptime.fold/1
  pub def fold(p0 Option(Unk0017)) Tuple(Unk0194, String) := …

  # Comptime.int_div/3
  pub def int_div(_a Unk0195, p1 Int53, _op Fn(Unk0196, Unk0197, Unk0198)) Tuple(Unk0199, Int53) := …

  # Core.first_unsupported/2
  pub def first_unsupported(node Unk0200, unsup Map(Unk0202, Option(Unk0201))) Option(Unk0201) := …

  # Core.from_arm/1
  pub def from_arm(p0 Unk0203) Unk0204 := …

  # Core.from_expr/1
  pub def from_expr(p0 Option(Unk0017)) Option(Unk0017) := …

  # Core.from_pairs/1
  pub def from_pairs(pairs Vec(Unk0205)) Vec(Tuple(Unk0206, Option(Unk0017))) := …

  # Core.from_pat/1
  pub def from_pat(p0 Sum2) Sum2 := …

  # Core.from_stmt/1
  pub def from_stmt(p0 Unk0207) Tuple(Unk0208, Option(Unk0017)) := …

  # Core.from_tail/1
  pub def from_tail(p0 Unk0209) Option(Unk0017) := …

  # Core.reject_unsupported!/4
  pub def reject_unsupported!(funcs Vec(Unk0210), unsup Map(Unk0202, Option(Unk0201)), target Symbol, exception Symbol) Symbol := …

  # Cst.build/1
  pub def build(tokens Vec(Unk0211)) Unk0212 := …

  # Cst.open/4
  pub def open(open_tok Unk0211, close Unk0213, rest Vec(Unk0211), acc Vec(Tuple(Unk0214, Unk0211))) Tuple(Vec(Tuple(Unk0214, Unk0211)), Vec(Unk0215)) := …

  # Cst.seq/2
  pub def seq(p0 Vec(Unk0211), acc Vec(Tuple(Unk0214, Unk0211))) Tuple(Vec(Tuple(Unk0214, Unk0211)), Vec(Unk0215)) := …

  # Decl.all_impl_decls/1
  pub def all_impl_decls(decls Vec(Unk0216)) Vec(Unk0217) := …

  # Decl.all_impls/1
  pub def all_impls(decls Vec(Unk0216)) Vec(Unk0218) := …

  # Decl.all_protocols/1
  pub def all_protocols(decls Vec(Unk0216)) Vec(Unk0217) := …

  # Decl.assemble/3
  pub def assemble(decls Vec(Unk0219), aliases Unk0220, p2 Unk0221) Unk0222 := …

  # Decl.attach_doc/2
  pub def attach_doc(p0 Tuple(Unk0223, Map(Unk0224, Bool)), doc Bool) Tuple(Unk0223, Map(Unk0224, Bool)) := …

  # Decl.attach_external/3
  pub def attach_external(p0 Unk0225, target Unk0226, spec Unk0227) Tuple(Unk0223, Map(Unk0224, Bool)) := …

  # Decl.attach_targets/2
  pub def attach_targets(p0 Unk0228, targets Unk0229) Tuple(Unk0223, Map(Unk0224, Bool)) := …

  # Decl.balanced_parens/1
  pub def balanced_parens(p0 Vec(Unk0230)) Tuple(Vec(Unk0230), Vec(Unk0230)) := …

  # Decl.block_seps/5
  pub def block_seps(p0 Vec(Unk0231), _d Int53, _w Int53, _p Int53, acc Vec(Unk0231)) Vec(Unk0231) := …

  # Decl.build_func/1
  pub def build_func(p0 Vec(Unk0232)) Func := …

  # Decl.calls_show_float?/1
  pub def calls_show_float?(p0 Vec(Unk0233)) Bool := …

  # Decl.clause/2
  pub def clause(p0 Unk0234, _arity Unk0235) Clause := …

  # Decl.clause_env/2
  pub def clause_env(p0 Clause, params Unk0236) Map(Unk0085, Vec(Unk0079)) := …

  # Decl.collapse_parens/1
  pub def collapse_parens(s Unk0237) Unk0238 := …

  # Decl.collect_aliases/1
  pub def collect_aliases(decls Vec(Unk0216)) Unk0239 := …

  # Decl.collect_macros/1
  pub def collect_macros(decls Vec(Unk0216)) Map(Unk0240, Unk0241) := …

  # Decl.compile/1
  pub def compile(src String) Vec(Tuple(String, Unk0242)) := …

  # Decl.compile_beam/1
  pub def compile_beam(src String) Vec(Tuple(Unk0243, Unk0242)) := …

  # Decl.decl_boundary?/1
  pub def decl_boundary?(p0 Vec(Unk0230)) Bool := …

  # Decl.decl_kw?/1
  pub def decl_kw?(p0 Vec(Unk0230)) Bool := …

  # Decl.def_raw/4
  pub def def_raw(name Unk0244, params Unk0245, head_rev Vec(Unk0230), body Option(Unk0246)) Unk0247 := …

  # Decl.detok_block/1
  pub def detok_block(tokens Unk0248) Option(Unk0246) := …

  # Decl.extract_parens/1
  pub def extract_parens(str Unk0249) Unk0250 := …

  # Decl.field/1
  pub def field(f Unk0251) Field := …

  # Decl.fields/1
  pub def fields(inside Unk0252) Vec(Unk0253) := …

  # Decl.impl_struct/3
  pub def impl_struct(proto Unk0254, type Unk0255, inner Unk0256) Unk0257 := …

  # Decl.in_scope/2
  pub def in_scope(decls Vec(Unk0216), f Fn(Unk0259, Unk0258)) Vec(Unk0217) := …

  # Decl.inject_stdlib/1
  pub def inject_stdlib(prog Tuple(Unk0260, Vec(Unk0261))) Tuple(Unk0260, Vec(Unk0261)) := …

  # Decl.line_continues?/2
  pub def line_continues?(p0 Vec(Unk0230), _rest Vec(Unk0230)) Bool := …

  # Decl.lower_meta/3
  pub def lower_meta(funcs Vec(Unk0262), decls Vec(Unk0216), targets Option(Unk0263)) Vec(Unk0264) := …

  # Decl.macro_param_names/1
  pub def macro_param_names(pstr Unk0265) Unk0266 := …

  # Decl.mark_pub/1
  pub def mark_pub(p0 Unk0267) Tuple(Unk0223, Map(Unk0224, Bool)) := …

  # Decl.mark_test/1
  pub def mark_test(p0 Unk0268) Tuple(Unk0223, Map(Unk0224, Bool)) := …

  # Decl.meta_clause/5
  pub def meta_clause(p0 Unk0269, _env Map(Unk0240, Unk0241), _p Bool, _params Unk0236, _show Unk0270) Unk0271 := …

  # Decl.needs_show_float?/1
  pub def needs_show_float?(prog Tuple(Unk0260, Vec(Unk0261))) Bool := …

  # Decl.nz/1
  pub def nz(s String) Option(Unk0272) := …

  # Decl.param/1
  pub def param(p Unk0273) Unk0274 := …

  # Decl.parse/1
  pub def parse(src String) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Decl.parse_abstract/4
  pub def parse_abstract(head Unk0275, body_toks Unk0276, pub? Unk0277, doc Unk0278) Opaque := …

  # Decl.parse_abstract_members/1
  pub def parse_abstract_members(toks Unk0276) Unk0279 := …

  # Decl.parse_alias/1
  pub def parse_alias(text Unk0275) Tuple(Unk0280, Unk0281) := …

  # Decl.parse_assoc_binding/1
  pub def parse_assoc_binding(t Unk0282) Tuple(Unk0284, Option(Unk0283)) := …

  # Decl.parse_binder/1
  pub def parse_binder(b Unk0285) Tuple(Unk0286, Vec(Unk0287)) := …

  # Decl.parse_binders/1
  pub def parse_binders(binders Unk0288) Vec(Unk0289) := …

  # Decl.parse_bounds/1
  pub def parse_bounds(text Unk0290) Unk0291 := …

  # Decl.parse_cast_rule/1
  pub def parse_cast_rule(p0 Unk0292) Unk0293 := …

  # Decl.parse_const/3
  pub def parse_const(text Unk0275, pub? Unk0294, doc Unk0295) Const := …

  # Decl.parse_external/1
  pub def parse_external(p0 Vec(Unk0296)) Tuple(Unk0297, Unk0298) := …

  # Decl.parse_head/1
  pub def parse_head(head String) Unk0299 := …

  # Decl.parse_op_rule/1
  pub def parse_op_rule(p0 Unk0292) Unk0300 := …

  # Decl.parse_opaque/3
  pub def parse_opaque(text Unk0275, pub? Unk0301, doc Unk0302) Opaque := …

  # Decl.parse_ordinal/1
  pub def parse_ordinal(p0 Unk0303) Tuple(Unk0304, Unk0305) := …

  # Decl.parse_params/1
  pub def parse_params(str Unk0306) Vec(Unk0307) := …

  # Decl.parse_range/3
  pub def parse_range(text Unk0275, pub? Unk0308, doc Unk0309) Range := …

  # Decl.parse_struct/3
  pub def parse_struct(text Unk0249, pub? Unk0310, doc Unk0311) Struct := …

  # Decl.parse_targets/1
  pub def parse_targets(toks Unk0312) Unk0229 := …

  # Decl.parse_type/3
  pub def parse_type(rest Unk0275, pub? Unk0313, doc Unk0314) Type := …

  # Decl.parse_use/1
  pub def parse_use(text Unk0315) Use := …

  # Decl.proto_method_traits/1
  pub def proto_method_traits(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0316 := …

  # Decl.protocol_defs/4
  pub def protocol_defs(decls Vec(Unk0219), types Unk0317, structs Unk0318, targets Unk0319) Vec(Unk0320) := …

  # Decl.protocol_struct/2
  pub def protocol_struct(name Unk0321, inner Unk0322) Unk0323 := …

  # Decl.protocol_unit/3
  pub def protocol_unit(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Tuple(String, Unk0242)) := …

  # Decl.req_ret/1
  pub def req_ret(p0 Unk0324) Unk0325 := …

  # Decl.skip_nl/1
  pub def skip_nl(p0 Vec(Unk0230)) Vec(Unk0230) := …

  # Decl.split2/2
  pub def split2(str Unk0326, sep Unk0327) Tuple(Unk0329, Unk0328) := …

  # Decl.split_decls/1
  pub def split_decls(p0 Vec(Vec(Unk0230))) Vec(Unk0330) := …

  # Decl.split_forall/1
  pub def split_forall(head Unk0331) Unk0332 := …

  # Decl.split_once/2
  pub def split_once(str Unk0275, sep String) Tuple(Unk0333, Unk0334) := …

  # Decl.split_top/2
  pub def split_top(str Unk0335, sep String) Unk0336 := …

  # Decl.strip_type_params/1
  pub def strip_type_params(name Unk0337) Unk0280 := …

  # Decl.subst_const/2
  pub def subst_const(p0 Unk0338, aliases Unk0220) Const := …

  # Decl.subst_fields/2
  pub def subst_fields(fs Vec(Unk0339), aliases Unk0340) Vec(Field) := …

  # Decl.subst_func/2
  pub def subst_func(p0 Unk0341, aliases Unk0220) Func := …

  # Decl.subst_struct/2
  pub def subst_struct(p0 Unk0342, aliases Unk0220) Struct := …

  # Decl.subst_type/2
  pub def subst_type(p0 Unk0343, aliases Unk0220) Type := …

  # Decl.subst_type_str/2
  pub def subst_type_str(type Unk0344, aliases Vec(Unk0345)) Unk0344 := …

  # Decl.subst_variant/2
  pub def subst_variant(p0 Unk0346, aliases Unk0347) Variant := …

  # Decl.take_block/3
  pub def take_block(p0 Vec(Unk0230), depth Int53, acc Vec(Unk0230)) Tuple(Vec(Unk0230), Vec(Unk0230)) := …

  # Decl.take_decl/1
  pub def take_decl(p0 Vec(Vec(Unk0230))) Tuple(Tuple(Unk0223, Map(Unk0224, Bool)), Vec(Unk0230)) := …

  # Decl.take_def/1
  pub def take_def(p0 Vec(Unk0230)) Tuple(Unk0247, Vec(Unk0230)) := …

  # Decl.take_head/4
  pub def take_head(name Unk0244, params Unk0245, p2 Vec(Unk0230), head Vec(Unk0230)) Tuple(Unk0247, Vec(Unk0230)) := …

  # Decl.take_line/2
  pub def take_line(tokens Vec(Unk0230), acc Vec(Unk0230)) Tuple(Vec(Unk0230), Vec(Unk0230)) := …

  # Decl.take_line/3
  pub def take_line(p0 Vec(Unk0230), acc Vec(Unk0230), _depth Int53) Tuple(Vec(Unk0230), Vec(Unk0230)) := …

  # Decl.take_mod_body/2
  pub def take_mod_body(p0 Vec(Unk0230), acc Vec(Unk0348)) Tuple(Vec(Unk0348), Vec(Unk0230)) := …

  # Decl.take_parens/3
  pub def take_parens(p0 Vec(Unk0230), p1 Int53, acc Vec(Unk0230)) Tuple(Vec(Unk0230), Vec(Unk0230)) := …

  # Decl.take_type/2
  pub def take_type(p0 Vec(Vec(Unk0230)), acc Vec(Vec(Unk0230))) Tuple(Vec(Vec(Unk0230)), Vec(Vec(Unk0230))) := …

  # Decl.take_until_do/2
  pub def take_until_do(p0 Vec(Vec(Unk0230)), acc Vec(Vec(Unk0230))) Tuple(Vec(Vec(Unk0230)), Unk0349) := …

  # Decl.variant/1
  pub def variant(v Unk0249) Variant := …

  # Doc.concat/1
  pub def concat(docs Vec(Tuple(Unk0350, String))) Tuple(Unk0350, String) := …

  # Doc.concat/2
  pub def concat(a Tuple(Unk0350, String), b Tuple(Unk0350, String)) Tuple(Unk0350, String) := …

  # Doc.do_render/5
  pub def do_render(_w Int53, _k Int53, p2 Vec(Unk0351), p3 Vec(Unk0352), out Vec(String)) Vec(String) := …

  # Doc.empty/0
  pub def empty() Tuple(Unk0350, String) := …

  # Doc.fits?/2
  pub def fits?(w Int53, _work Vec(Unk0351)) Bool := …

  # Doc.flat_string/1
  pub def flat_string(p0 Unk0352) String := …

  # Doc.flush_suffix/2
  pub def flush_suffix(p0 Vec(Unk0352), out Vec(String)) Vec(String) := …

  # Doc.group/2
  pub def group(doc Tuple(Unk0350, String), p1 Bool) Unk0353 := …

  # Doc.hardline/0
  pub def hardline() Tuple(Unk0350, String) := …

  # Doc.if_break/2
  pub def if_break(broken Tuple(Unk0350, String), flat Tuple(Unk0350, String)) Tuple(Unk0350, String) := …

  # Doc.join/2
  pub def join(_sep Tuple(Unk0350, String), p1 Vec(Tuple(Unk0350, String))) Tuple(Unk0350, String) := …

  # Doc.line/0
  pub def line() Tuple(Unk0350, String) := …

  # Doc.line_suffix/1
  pub def line_suffix(doc Tuple(Unk0350, String)) Tuple(Unk0350, String) := …

  # Doc.must_break?/1
  pub def must_break?(p0 Tuple(Unk0350, String)) Bool := …

  # Doc.nest/2
  pub def nest(n Vec(Unk0354), doc Tuple(Unk0350, String)) Tuple(Unk0350, String) := …

  # Doc.render/2
  pub def render(doc Tuple(Unk0350, String), width Int53) String := …

  # Doc.softline/0
  pub def softline() Tuple(Unk0350, String) := …

  # Doc.text/1
  pub def text(s String) Tuple(Unk0350, String) := …

  # Doctest.augment/2
  pub def augment(src String, examples Vec(Unk0355)) String := …

  # Doctest.extract/1
  pub def extract(src String) Vec(Unk0355) := …

  # Doctest.exunit_cases/2
  pub def exunit_cases(src String, mod Unk0356) Unk0357 := …

  # Doctest.fences/1
  pub def fences(md Unk0358) Unk0359 := …

  # Doctest.module_doc_strings/1
  pub def module_doc_strings(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Unk0360) := …

  # Doctest.pairs/1
  pub def pairs(p0 Unk0361) Vec(Unk0362) := …

  # Doctest.run/2
  pub def run(src String, p1 Unk0363) Vec(Unk0364) := …

  # Doctest.run_markdown/1
  pub def run_markdown(md Unk0365) Unk0366 := …

  # Exhaustiveness.add_range/4
  pub def add_range(env Tuple(Unk0367, Map(String, String)), type_name String, lo Unk0368, hi Unk0369) Tuple(Unk0367, Map(String, String)) := …

  # Exhaustiveness.add_type/3
  pub def add_type(env Tuple(Unk0367, Map(String, String)), type_name String, variants Vec(Tuple(String, Unk0370))) Tuple(Unk0367, Map(String, String)) := …

  # Exhaustiveness.analyze/3
  pub def analyze(arms Vec(Unk0371), n Int53, env Map(Unk0373, Unk0372)) Unk0374 := …

  # Exhaustiveness.arity/2
  pub def arity(_env Map(Unk0373, Unk0372), p1 Unk0375) Int53 := …

  # Exhaustiveness.base_env/0
  pub def base_env() Tuple(Unk0367, Map(String, String)) := …

  # Exhaustiveness.body_core/1
  pub def body_core(body Option(Unk0017)) Option(Unk0017) := …

  # Exhaustiveness.check_case_bodies!/2
  pub def check_case_bodies!(funcs Unk0376, env Unk0377) Unk0378 := …

  # Exhaustiveness.check_match!/3
  pub def check_match!(core Unk0379, env Map(Unk0373, Unk0372), where Unk0380) Unk0381 := …

  # Exhaustiveness.check_one_case!/3
  pub def check_one_case!(p0 Sum1, env Map(Unk0373, Unk0372), where Unk0380) Unk0382 := …

  # Exhaustiveness.collect_cases/2
  pub def collect_cases(p0 Vec(Unk0383), acc Vec(Unk0384)) Vec(Unk0384) := …

  # Exhaustiveness.collect_children/2
  pub def collect_children(struct Vec(Unk0383), acc Vec(Unk0384)) Vec(Unk0384) := …

  # Exhaustiveness.default/1
  pub def default(rows Vec(Unk0385)) Vec(Unk0385) := …

  # Exhaustiveness.head_ctors/1
  pub def head_ctors(rows Vec(Unk0385)) Vec(Unk0386) := …

  # Exhaustiveness.missing_head/2
  pub def missing_head(_env Map(Unk0373, Unk0372), p1 Vec(Unk0386)) Unk0387 := …

  # Exhaustiveness.pascal/1
  pub def pascal(c Unk0388) String := …

  # Exhaustiveness.program_env/3
  pub def program_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0389), ranges Vec(Unk0390)) Tuple(Unk0367, Map(String, String)) := …

  # Exhaustiveness.render/1
  pub def render(p0 Vec(Unk0391)) String := …

  # Exhaustiveness.signature/2
  pub def signature(_env Map(Unk0373, Unk0372), p1 Vec(Unk0386)) Tuple(Unk0392, Vec(Unk0393)) := …

  # Exhaustiveness.specialize/3
  pub def specialize(rows Vec(Unk0385), c Unk0375, env Map(Unk0373, Unk0372)) Vec(Unk0385) := …

  # Exhaustiveness.useful?/3
  pub def useful?(rows Vec(Unk0385), p1 Vec(Unk0394), _env Map(Unk0373, Unk0372)) Bool := …

  # Exhaustiveness.witness/3
  pub def witness(rows Vec(Unk0385), p1 Int53, _env Map(Unk0373, Unk0372)) Tuple(Unk0395, Vec(Unk0387)) := …

  # Fixpoint.check/4
  pub def check(mod Symbol, corpus Vec(String), project Unk0396, p3 Unk0397) Unk0398 := …

  # Format.apply_node/3
  pub def apply_node(p0 Option(Unk0399), base Vec(Unk0354), st Vec(Vec(Unk0354))) Vec(Vec(Unk0354)) := …

  # Format.bd/3
  pub def bd(p0 Vec(Option(Unk0399)), _prev Option(Unk0399), _rf Bool) Tuple(Unk0350, String) := …

  # Format.blank?/1
  pub def blank?(p0 Option(Unk0399)) Bool := …

  # Format.block_head?/2
  pub def block_head?(p0 Vec(Option(Unk0399)), next Vec(Option(Unk0399))) Bool := …

  # Format.boundary?/1
  pub def boundary?(p0 Option(Unk0399)) Bool := …

  # Format.boundary_tok?/1
  pub def boundary_tok?(p0 Tuple(Unk0400, String)) Bool := …

  # Format.chain?/1
  pub def chain?(nodes Vec(Option(Unk0399))) Bool := …

  # Format.chain_body/2
  pub def chain_body(nodes Vec(Option(Unk0399)), prev Option(Unk0399)) Tuple(Unk0350, String) := …

  # Format.chain_doc/1
  pub def chain_doc(nodes Vec(Option(Unk0399))) Tuple(Unk0350, String) := …

  # Format.chain_link?/2
  pub def chain_link?(a Vec(Option(Unk0399)), b Option(Unk0399)) Bool := …

  # Format.chain_tail/2
  pub def chain_tail(p0 Vec(Option(Unk0399)), _level Unk0401) Tuple(Unk0350, String) := …

  # Format.chunk_on_comma/3
  pub def chunk_on_comma(p0 Vec(Unk0402), cur Vec(Unk0402), acc Vec(Vec(Unk0402))) Vec(Vec(Unk0402)) := …

  # Format.closer_lead?/1
  pub def closer_lead?(p0 Tuple(Unk0400, String)) Bool := …

  # Format.comment_only?/1
  pub def comment_only?(line Option(Unk0399)) Bool := …

  # Format.cons_group?/1
  pub def cons_group?(inner Vec(Unk0403)) Bool := …

  # Format.cont_lead?/1
  pub def cont_lead?(p0 Tuple(Unk0400, String)) Bool := …

  # Format.decl_kw?/1
  pub def decl_kw?(p0 Tuple(Unk0400, String)) Bool := …

  # Format.declaration_line?/1
  pub def declaration_line?(p0 Vec(Option(Unk0399))) Bool := …

  # Format.ends_with_comment?/1
  pub def ends_with_comment?(line Vec(Option(Unk0399))) Bool := …

  # Format.finish_items/2
  pub def finish_items(cur Vec(Unk0402), acc Vec(Vec(Unk0402))) Vec(Vec(Unk0402)) := …

  # Format.format_result/1
  pub def format_result(src String) Tuple(Unk0405, Unk0404) := …

  # Format.group_doc/4
  pub def group_doc(open Unk0406, inner Vec(Unk0403), close Unk0406, reflow? Bool) Tuple(Unk0350, String) := …

  # Format.has_comment?/1
  pub def has_comment?(nodes Vec(Unk0403)) Bool := …

  # Format.has_tok?/2
  pub def has_tok?(line Vec(Tuple(Unk0407, Tuple(Unk0408, String))), t Tuple(Unk0408, String)) Bool := …

  # Format.head_tok/1
  pub def head_tok(p0 Option(Unk0399)) Tuple(Unk0400, String) := …

  # Format.indent_and_render/4
  pub def indent_and_render(p0 Vec(Option(Unk0399)), _stack Vec(Vec(Unk0354)), _cont Int53, acc Vec(String)) Vec(String) := …

  # Format.lead_adjust/1
  pub def lead_adjust(p0 Vec(Option(Unk0399))) Int53 := …

  # Format.leading_wrap_op?/1
  pub def leading_wrap_op?(p0 Vec(Option(Unk0399))) Bool := …

  # Format.leaf/1
  pub def leaf(p0 Unk0406) String := …

  # Format.line_doc/1
  pub def line_doc(nodes Vec(Option(Unk0399))) Tuple(Unk0350, String) := …

  # Format.ll/3
  pub def ll(p0 Vec(Unk0409), cur Vec(Unk0409), acc Vec(Vec(Unk0409))) Vec(Vec(Unk0409)) := …

  # Format.logical_lines/1
  pub def logical_lines(nodes Vec(Unk0409)) Vec(Vec(Unk0409)) := …

  # Format.magic_comma?/1
  pub def magic_comma?(inner Vec(Unk0403)) Bool := …

  # Format.mark/1
  pub def mark(nodes Option(Unk0399)) Vec(Option(Unk0399)) := …

  # Format.mark/3
  pub def mark(p0 Option(Unk0399), _prev Option(Unk0399), acc Vec(Option(Unk0399))) Vec(Option(Unk0399)) := …

  # Format.merge_chains/1
  pub def merge_chains(p0 Vec(Vec(Option(Unk0399)))) Vec(Vec(Option(Unk0399))) := …

  # Format.next_code_line/1
  pub def next_code_line(p0 Vec(Option(Unk0399))) Option(Unk0399) := …

  # Format.node_doc/2
  pub def node_doc(p0 Option(Unk0399), _rf Bool) Tuple(Unk0350, String) := …

  # Format.pop/1
  pub def pop(p0 Vec(Vec(Unk0354))) Vec(Vec(Unk0354)) := …

  # Format.push/2
  pub def push(base Vec(Unk0354), st Vec(Vec(Unk0354))) Vec(Vec(Unk0354)) := …

  # Format.render_line/2
  pub def render_line(nodes Vec(Option(Unk0399)), base Vec(Unk0354)) String := …

  # Format.space?/2
  pub def space?(_prev Tuple(Unk0400, String), p1 Tuple(Unk0400, String)) Bool := …

  # Format.split_items/1
  pub def split_items(nodes Vec(Unk0403)) Vec(Vec(Option(Unk0399))) := …

  # Format.split_level/1
  pub def split_level(nodes Vec(Option(Unk0399))) Unk0401 := …

  # Format.split_node?/2
  pub def split_node?(p0 Option(Unk0399), level Unk0401) Bool := …

  # Format.squeeze_blanks/1
  pub def squeeze_blanks(lines Unk0410) Unk0411 := …

  # Format.tail_tok/1
  pub def tail_tok(p0 Option(Unk0399)) Tuple(Unk0400, String) := …

  # Format.take_until_level/3
  pub def take_until_level(p0 Vec(Option(Unk0399)), _level Unk0401, acc Vec(Option(Unk0399))) Tuple(Vec(Option(Unk0399)), Vec(Option(Unk0399))) := …

  # Format.trailing_comma?/1
  pub def trailing_comma?(inner Vec(Unk0403)) Bool := …

  # Format.trailing_op?/1
  pub def trailing_op?(line Vec(Option(Unk0399))) Bool := …

  # Format.trailing_wrap_op?/1
  pub def trailing_wrap_op?(line Vec(Option(Unk0399))) Bool := …

  # Format.update_stack/4
  pub def update_stack(line Vec(Option(Unk0399)), rest Vec(Option(Unk0399)), base Vec(Unk0354), stack Vec(Vec(Unk0354))) Vec(Vec(Unk0354)) := …

  # Format.value_end?/1
  pub def value_end?(p0 Option(Unk0399)) Bool := …

  # Format.value_end_tok?/1
  pub def value_end_tok?(p0 Tuple(Unk0400, String)) Bool := …

  # Format.wrap_op_node?/1
  pub def wrap_op_node?(p0 Unk0412) Bool := …

  # Format.wrap_op_tok?/1
  pub def wrap_op_tok?(p0 Tuple(Unk0400, String)) Bool := …

  # Formatting.apply_edits/2
  pub def apply_edits(text String, edits Unk0413) String := …

  # Formatting.bump_del/3
  pub def bump_del(cur Unk0414, old Unk0415, n Int53) Unk0416 := …

  # Formatting.bump_ins/3
  pub def bump_ins(cur Unk0417, old Unk0415, ls Vec(Unk0418)) Unk0419 := …

  # Formatting.clamp/3
  pub def clamp(n Int53, lo Int53, hi Unk0420) Int53 := …

  # Formatting.edit/1
  pub def edit(p0 Unk0421) Unk0422 := …

  # Formatting.flush/2
  pub def flush(p0 Unk0423, acc Vec(Unk0423)) Vec(Unk0423) := …

  # Formatting.formatting/1
  pub def formatting(text String) Vec(Unk0424) := …

  # Formatting.hunks/2
  pub def hunks(old String, new String) Vec(Unk0424) := …

  # Formatting.range_formatting/3
  pub def range_formatting(text String, start_line Int53, end_line Int53) Vec(Unk0425) := …

  # Formatting.start_hunk/1
  pub def start_hunk(old Unk0415) Unk0426 := …

  # Formatting.to_hunks/1
  pub def to_hunks(diff Vec(Unk0427)) Vec(Unk0423) := …

  # FormsEquiv.abstract_code/1
  pub def abstract_code(beam Unk0428) Unk0429 := …

  # FormsEquiv.alpha_rename/1
  pub def alpha_rename(form Unk0430) Unk0431 := …

  # FormsEquiv.bool_clause/1
  pub def bool_clause(p0 Unk0432) Tuple(Unk0434, Unk0433) := …

  # FormsEquiv.bool_clause_pair/1
  pub def bool_clause_pair(p0 Vec(Unk0432)) Tuple(Unk0432, Unk0432) := …

  # FormsEquiv.canon_bool_case/1
  pub def canon_bool_case(p0 Vec(Unk0435)) Vec(Unk0435) := …

  # FormsEquiv.diff/2
  pub def diff(a Unk0436, b Unk0436) Tuple(Unk0438, Vec(Unk0437)) := …

  # FormsEquiv.equivalent?/2
  pub def equivalent?(a Unk0436, b Unk0436) Bool := …

  # FormsEquiv.fold_neg_literal/1
  pub def fold_neg_literal(p0 Vec(Unk0439)) Vec(Unk0439) := …

  # FormsEquiv.key/1
  pub def key(p0 Unk0440) Tuple(Unk0441, Unk0442) := …

  # FormsEquiv.normalize/1
  pub def normalize(beam Unk0436) Unk0443 := …

  # FormsEquiv.user_function?/1
  pub def user_function?(p0 Unk0444) Bool := …

  # FormsEquiv.verified?/2
  pub def verified?(oracle Unk0436, port Unk0436) Bool := …

  # FormsEquiv.verify/2
  pub def verify(oracle Unk0436, port Unk0436) Vec(Unk0445) := …

  # FormsEquiv.walk_rename/2
  pub def walk_rename(p0 Unk0430, map Map(Unk0446, Unk0447)) Tuple(Unk0430, Map(Unk0446, Unk0447)) := …

  # FormsEquiv.zero_anno/1
  pub def zero_anno(tuple Vec(Unk0448)) Vec(Unk0448) := …

  # History.dedup_consecutive/1
  pub def dedup_consecutive(p0 Vec(Vec(Unk0449))) Vec(Vec(Unk0449)) := …

  # History.load/0
  pub def load() Vec(Unk0450) := …

  # Infer.app/2
  pub def app(head String, args Vec(Tuple(Unk0451, String))) Tuple(Unk0451, String) := …

  # Infer.app1/2
  pub def app1(head String, s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.apply_spec_terms/4
  pub def apply_spec_terms(p0 Unk0454, _pvars Unk0455, _rvar Tuple(Unk0451, String), store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))) := …

  # Infer.bind/3
  pub def bind(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), id Unk0453, t Tuple(Unk0451, String)) Unk0456 := …

  # Infer.bind_checked/3
  pub def bind_checked(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), i Unk0453, t Tuple(Unk0451, String)) Tuple(Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), Unk0457) := …

  # Infer.bind_params/3
  pub def bind_params(args Unk0458, pvars Unk0459, store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Unk0460 := …

  # Infer.build_ctx/2
  pub def build_ctx(stdlib_map Unk0461, p1 Unk0462) Unk0463 := …

  # Infer.build_ledger/2
  pub def build_ledger(params Unk0464, ret String) Vec(Tuple(String, Unk0465)) := …

  # Infer.call_sig/6
  pub def call_sig(ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), key Unk0468, args Vec(Bool), env Map(String, Tuple(Unk0451, String)), _outer Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.case_arm/1
  pub def case_arm(p0 Unk0469) Tuple(Unk0470, Option(Unk0471)) := …

  # Infer.clear_xmod/0
  pub def clear_xmod() Unk0472 := …

  # Infer.cluster_name/2
  pub def cluster_name(clusters Map(Tuple(Unk0467, Int53), Unk0454), struct String) String := …

  # Infer.collect_specs/2
  pub def collect_specs(stmts Vec(String), type_env Map(Unk0473, Tuple(Unk0451, String))) Map(Tuple(Unk0467, Int53), Unk0454) := …

  # Infer.collect_types/2
  pub def collect_types(stmts Vec(String), mod_name String) Tuple(Unk0475, Vec(Unk0474)) := …

  # Infer.con/1
  pub def con(name String) Tuple(Unk0451, String) := …

  # Infer.do_unify/3
  pub def do_unify(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), t Tuple(Unk0451, String), t Tuple(Unk0451, String)) Tuple(Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), Unk0457) := …

  # Infer.free_vars/2
  pub def free_vars(store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), t Tuple(Unk0451, String)) Vec(Unk0476) := …

  # Infer.fresh/1
  pub def fresh(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.fresh_n/2
  pub def fresh_n(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), k Int53) Tuple(Vec(Unk0477), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.fresh_num/1
  pub def fresh_num(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.freshen_tvars/2
  pub def freshen_tvars(tvars Vec(Unk0478), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Map(Unk0478, Unk0479), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen/4
  pub def gen(n Bool, _env Map(String, Tuple(Unk0451, String)), _ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen_args_then_fresh/4
  pub def gen_args_then_fresh(args Vec(Bool), env Map(String, Tuple(Unk0451, String)), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen_block/4
  pub def gen_block(p0 Vec(Bool), _env Map(String, Tuple(Unk0451, String)), _ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen_cons/5
  pub def gen_cons(h Bool, t Bool, env Map(String, Tuple(Unk0451, String)), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen_pat/4
  pub def gen_pat(p0 Vec(Unk0480), pv Tuple(Unk0451, String), env Map(String, Tuple(Unk0451, String)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Map(String, Tuple(Unk0451, String)), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.gen_pat_cons/5
  pub def gen_pat_cons(h Vec(Unk0480), t Vec(Unk0480), pv Tuple(Unk0451, String), env Map(String, Tuple(Unk0451, String)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Map(String, Tuple(Unk0451, String)), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.generalize_map/3
  pub def generalize_map(pvars Unk0481, rvar Tuple(Unk0451, String), store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Map(Unk0482, Unk0483) := …

  # Infer.hole_or/2
  pub def hole_or(p0 Unk0484, h Unk0484) Unk0484 := …

  # Infer.hole_sig?/1
  pub def hole_sig?(p0 Unk0485) Bool := …

  # Infer.infer_group/2
  pub def infer_group(p0 Unk0486, ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454))) Unk0485 := …

  # Infer.instantiate/5
  pub def instantiate(p0 Unk0487, args Vec(Bool), env Map(String, Tuple(Unk0451, String)), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.load_prelude_sigs/0
  pub def load_prelude_sigs() Unk0488 := …

  # Infer.mark_num/2
  pub def mark_num(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), t Tuple(Unk0451, String)) Tuple(Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), Unk0489) := …

  # Infer.max_ph/1
  pub def max_ph(p0 Vec(Unk0490)) Int53 := …

  # Infer.maybe_tuple/4
  pub def maybe_tuple(elems Vec(Unk0491), env Map(String, Tuple(Unk0451, String)), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Tuple(Unk0451, String), Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) := …

  # Infer.mod_name/1
  pub def mod_name(p0 Unk0492) String := …

  # Infer.num_conflict?/3
  pub def num_conflict?(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), i Unk0453, t Tuple(Unk0451, String)) Bool := …

  # Infer.numeric_con?/1
  pub def numeric_con?(p0 Tuple(Unk0451, String)) Bool := …

  # Infer.occurs?/3
  pub def occurs?(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), i Unk0453, t Tuple(Unk0451, String)) Bool := …

  # Infer.ok_payload/3
  pub def ok_payload(tail_pairs Vec(Unk0493), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), store Unk0494) Unk0495 := …

  # Infer.parse_type/2
  pub def parse_type(str Unk0496, fmap Map(Unk0498, Unk0497)) Tuple(Unk0451, String) := …

  # Infer.pascal/1
  pub def pascal(name Unk0499) String := …

  # Infer.prelude_sigs/0
  pub def prelude_sigs() Unk0488 := …

  # Infer.prime_xmod/2
  pub def prime_xmod(modules Unk0500, stdlib_map Unk0501) Unk0502 := …

  # Infer.put_slot/3
  pub def put_slot(sig Tuple(Unk0503, String), p1 String, ts String) Unk0504 := …

  # Infer.render/3
  pub def render(store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), gmap Map(Unk0482, Unk0483), t Tuple(Unk0451, String)) String := …

  # Infer.render_wp/3
  pub def render_wp(store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), unk_names Map(Unk0505, String), t Tuple(Unk0451, String)) String := …

  # Infer.resolve/2
  pub def resolve(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), p1 Tuple(Unk0451, String)) Tuple(Unk0451, String) := …

  # Infer.resolve_program/2
  pub def resolve_program(sigvars Vec(Unk0506), store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Unk0507 := …

  # Infer.resolve_struct_params/4
  pub def resolve_struct_params(args Unk0508, pvars Unk0509, ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))) := …

  # Infer.result_analysis/3
  pub def result_analysis(clause_envs Vec(Unk0510), ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), store Unk0494) Unk0511 := …

  # Infer.result_tag/1
  pub def result_tag(p0 Unk0512) Tuple(Unk0514, Unk0513) := …

  # Infer.seed_spec/6
  pub def seed_spec(ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), name Unk0467, arity Int53, pvars Unk0455, rvar Tuple(Unk0451, String), store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))) := …

  # Infer.sig_of/1
  pub def sig_of(f Unk0515) Unk0516 := …

  # Infer.sigvar_call/5
  pub def sigvar_call(ctx Map(Unk0466, Map(Tuple(Unk0467, Int53), Unk0454)), key Unk0517, args Unk0518, env Map(String, Tuple(Unk0451, String)), s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String)))) Unk0519 := …

  # Infer.slot_sig/3
  pub def slot_sig(p0 String, ts String, _ Vec(Unk0520)) Unk0521 := …

  # Infer.spec_pair/2
  pub def spec_pair(p0 Unk0522, type_env Map(Unk0473, Tuple(Unk0451, String))) Tuple(Tuple(Unk0525, Unk0523), Unk0524) := …

  # Infer.spec_str/1
  pub def spec_str(p0 Unk0526) String := …

  # Infer.store_new/0
  pub def store_new() Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))) := …

  # Infer.translate_spec/2
  pub def translate_spec(p0 Vec(Unk0527), _e Map(Unk0473, Tuple(Unk0451, String))) Tuple(Unk0451, String) := …

  # Infer.translate_type/2
  pub def translate_type(p0 Unk0528, mod_name String) Tuple(Unk0451, String) := …

  # Infer.tvar?/1
  pub def tvar?(s Unk0498) Unk0529 := …

  # Infer.tvar_name/1
  pub def tvar_name(i Unk0530) Unk0531 := …

  # Infer.type_pair/2
  pub def type_pair(p0 Unk0532, mod_name String) Tuple(Unk0533, Tuple(Unk0451, String)) := …

  # Infer.unify/3
  pub def unify(s Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), a Tuple(Unk0451, String), b Tuple(Unk0451, String)) Tuple(Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), Unk0457) := …

  # Infer.union_spec/3
  pub def union_spec(a Vec(Unk0527), b Vec(Unk0527), e Map(Unk0473, Tuple(Unk0451, String))) Tuple(Unk0451, String) := …

  # Infer.unk_vars/2
  pub def unk_vars(store Tuple(Unk0452, Map(Unk0453, Tuple(Unk0451, String))), v Tuple(Unk0451, String)) Vec(Unk0534) := …

  # Infer.vec_spec/2
  pub def vec_spec(elem Unk0527, e Map(Unk0473, Tuple(Unk0451, String))) Tuple(Unk0451, String) := …

  # Infer.whole_program/4
  pub def whole_program(modules Vec(Tuple(String, Vec(Unk0535))), stdlib Unk0536, p2 Unk0537, p3 Unk0538) Unk0507 := …

  # Infer.xmod_cache/0
  pub def xmod_cache() Unk0539 := …

  # Interp.concat_chain/1
  pub def concat_chain(parts Vec(Tuple(Unk0540, String))) Tuple(Unk0540, String) := …

  # Interp.int_type?/1
  pub def int_type?(t Vec(Unk0079)) Bool := …

  # Interp.resolve/4
  pub def resolve(p0 Tuple(Unk0194, String), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), show Unk0270) Option(Unk0017) := …

  # Interp.resolve_part/4
  pub def resolve_part(p0 Unk0541, _env Map(Unk0085, Vec(Unk0079)), _ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))), _show Unk0270) Tuple(Unk0543, Unk0542) := …

  # Interp.stringify/3
  pub def stringify(expr Option(Unk0017), p1 Vec(Unk0079), _show Unk0270) Tuple(Unk0543, Unk0542) := …

  # JS.all_funcs/1
  pub def all_funcs(prog Map(Unk0545, Vec(Unk0544))) Vec(Unk0544) := …

  # JS.arm_return/3
  pub def arm_return(body Unk0546, p1 Unk0547, i53 Bool) String := …

  # JS.bind_lines/1
  pub def bind_lines(binds Vec(Unk0548)) Vec(String) := …

  # JS.block_return/2
  pub def block_return(p0 Vec(Unk0549), i53 Bool) String := …

  # JS.branch_js/2
  pub def branch_js(p0 Sum1, i53 Bool) String := …

  # JS.case_arm_js/2
  pub def case_arm_js(p0 Unk0550, i53 Bool) String := …

  # JS.clause_js/2
  pub def clause_js(p0 Unk0551, i53 Bool) String := …

  # JS.clause_return/3
  pub def clause_return(src Option(Unk0017), params Vec(Unk0552), i53 Bool) String := …

  # JS.cp_lit/2
  pub def cp_lit(cp Unk0553, i53 Bool) String := …

  # JS.dispatcher_js/5
  pub def dispatcher_js(proto Unk0554, method Unk0555, impl_types Vec(Unk0556), reg Unk0557, i53 Bool) String := …

  # JS.expr_js/2
  pub def expr_js(p0 Sum1, i53 Bool) String := …

  # JS.float?/1
  pub def float?(n Unk0558) Bool := …

  # JS.function_js/2
  pub def function_js(p0 Unk0210, _i53 Bool) String := …

  # JS.guarded_return/4
  pub def guarded_return(body Option(Unk0017), p1 Unk0559, params Vec(Unk0552), i53 Bool) String := …

  # JS.js_atom/1
  pub def js_atom(name Unk0560) String := …

  # JS.js_guard!/4
  pub def js_guard!(type String, proto Unk0561, reg Unk0562, i53 Unk0563) Unk0564 := …

  # JS.js_number_int?/1
  pub def js_number_int?(t Unk0565) Bool := …

  # JS.js_str/1
  pub def js_str(s Unk0560) String := …

  # JS.lit_js/2
  pub def lit_js(v Unk0560, i53 Bool) String := …

  # JS.mangle/3
  pub def mangle(proto Unk0566, type Unk0567, method Unk0568) String := …

  # JS.match_elems/3
  pub def match_elems(es Unk0569, acc String, i53 Bool) Unk0570 := …

  # JS.num_js/2
  pub def num_js(n Unk0558, i53 Bool) String := …

  # JS.paren/2
  pub def paren(e Unk0571, i53 Unk0572) String := …

  # JS.pascal?/1
  pub def pascal?(s Unk0573) Bool := …

  # JS.pat_match/3
  pub def pat_match(p0 Sum2, _acc String, _i53 Bool) Tuple(Vec(String), Vec(Tuple(Unk0574, String))) := …

  # JS.program_number_mode?/1
  pub def program_number_mode?(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Bool := …

  # JS.protocol_dispatchers_js/2
  pub def protocol_dispatchers_js(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))), i53 Bool) String := …

  # JS.reject_mixed_int_mode!/1
  pub def reject_mixed_int_mode!(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0575 := …

  # JS.reject_wide_int!/2
  pub def reject_wide_int!(name Unk0576, p1 Unk0577) Unk0578 := …

  # JS.stmt_js/2
  pub def stmt_js(p0 Unk0579, i53 Bool) String := …

  # JS.stmt_return/2
  pub def stmt_return(p0 Unk0580, i53 Unk0581) String := …

  # JS.struct_name_set/1
  pub def struct_name_set(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0582 := …

  # JS.sum_ctor_map/1
  pub def sum_ctor_map(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0583 := …

  # JS.sum_guard_js/1
  pub def sum_guard_js(ctors Vec(Unk0584)) String := …

  # JVM.all_funcs/1
  pub def all_funcs(prog Map(Unk0586, Vec(Unk0585))) Vec(Unk0585) := …

  # JVM.all_types/1
  pub def all_types(prog Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # JVM.bind_str/1
  pub def bind_str(p0 Vec(Unk0587)) String := …

  # JVM.block_value/1
  pub def block_value(p0 Vec(Unk0549)) String := …

  # JVM.branch_kt/1
  pub def branch_kt(p0 Sum1) String := …

  # JVM.case_arms/2
  pub def case_arms(arms Unk0588, acc String) Tuple(Vec(Unk0589), Unk0590) := …

  # JVM.clause_lines/1
  pub def clause_lines(p0 Vec(Unk0591)) Tuple(String, Bool) := …

  # JVM.clause_match/1
  pub def clause_match(pats Unk0592) Unk0593 := …

  # JVM.clause_value/2
  pub def clause_value(src Option(Unk0017), params Vec(Unk0552)) String := …

  # JVM.closed_or_cond/3
  pub def closed_or_cond(p0 Vec(Unk0594), line String, _rest Vec(Unk0591)) Tuple(String, Bool) := …

  # JVM.expr_kt/1
  pub def expr_kt(p0 Sum1) String := …

  # JVM.function_kt/1
  pub def function_kt(p0 Unk0595) String := …

  # JVM.guarded_arm/2
  pub def guarded_arm(body_kt String, p1 Unk0596) String := …

  # JVM.guarded_return/3
  pub def guarded_return(body Unk0597, p1 Unk0598, params Vec(Unk0599)) String := …

  # JVM.kotlin_module/2
  pub def kotlin_module(src String, p1 Unk0600) String := …

  # JVM.kt_str/1
  pub def kt_str(s Unk0601) String := …

  # JVM.kt_type/1
  pub def kt_type(p0 String) Unk0602 := …

  # JVM.lit_kt/1
  pub def lit_kt(v Unk0601) String := …

  # JVM.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Tuple(Vec(String), Vec(Tuple(Unk0603, String))) := …

  # JVM.prepend_if/3
  pub def prepend_if(tests Vec(Unk0594), line String, rest Vec(Unk0591)) Tuple(String, Bool) := …

  # JVM.run_or_cond/3
  pub def run_or_cond(p0 Vec(Unk0594), line String, rest Vec(Unk0591)) Tuple(String, Bool) := …

  # JVM.stmt_kt/1
  pub def stmt_kt(p0 Unk0604) String := …

  # JVM.stmt_value/1
  pub def stmt_value(p0 Unk0605) String := …

  # JVM.sum_decl/1
  pub def sum_decl(t Unk0606) String := …

  # JVM.to_jar/3
  pub def to_jar(src String, jar_path String, p2 Unk0607) Unk0608 := …

  # JVM.variant_decl/2
  pub def variant_decl(p0 Unk0609, tname Unk0610) String := …

  # Lexer.binify/1
  pub def binify(acc Vec(String)) Unk0611 := …

  # Lexer.capture_hole/3
  pub def capture_hole(p0 String, _d Int53, _acc Vec(String)) Tuple(Unk0611, Unk0612) := …

  # Lexer.char_escape/1
  pub def char_escape(p0 Unk0613) Tuple(Int53, Unk0614) := …

  # Lexer.close_char/1
  pub def close_char(p0 String) Unk0615 := …

  # Lexer.collapse_nl/1
  pub def collapse_nl(tokens Unk0616) Unk0617 := …

  # Lexer.detokenize/2
  pub def detokenize(tokens Unk0618, p1 String) String := …

  # Lexer.escape_str/1
  pub def escape_str(s Unk0619) String := …

  # Lexer.expr_tokens/1
  pub def expr_tokens(src String) Vec(Vec(Vec(Unk0620))) := …

  # Lexer.lex/2
  pub def lex(str String, acc Vec(Tuple(Unk0621, String))) Unk0622 := …

  # Lexer.lex_char/1
  pub def lex_char(p0 String) Tuple(Unk0623, Unk0615) := …

  # Lexer.lex_parts/3
  pub def lex_parts(p0 String, _lit Vec(String), _parts Vec(Tuple(Unk0624, Unk0611))) Tuple(Vec(Tuple(Unk0624, Unk0611)), Unk0625) := …

  # Lexer.lex_string_token/1
  pub def lex_string_token(str String) Tuple(Tuple(Unk0627, Vec(Unk0628)), Unk0626) := …

  # Lexer.parse_hex!/1
  pub def parse_hex!(hex Unk0614) Int53 := …

  # Lexer.punct/1
  pub def punct(str String) Option(Unk0629) := …

  # Lexer.string_token/1
  pub def string_token(parts Vec(Unk0628)) Tuple(Unk0627, Vec(Unk0628)) := …

  # Lexer.strip_trivia/1
  pub def strip_trivia(tokens Unk0630) Unk0631 := …

  # Lexer.take_comment/1
  pub def take_comment(str String) Tuple(Unk0632, String) := …

  # Lexer.take_hex/2
  pub def take_hex(str Unk0633, max Int53) Tuple(String, Unk0633) := …

  # Lexer.take_hex/3
  pub def take_hex(p0 Unk0633, max Int53, acc String) Tuple(String, Unk0633) := …

  # Lexer.tok_str/2
  pub def tok_str(p0 Unk0634, nl_as String) String := …

  # Lexer.tokenize/1
  pub def tokenize(src String) Unk0635 := …

  # Lexer.tokenize_trivia/1
  pub def tokenize_trivia(src String) Unk0622 := …

  # Lexer.word/1
  pub def word(w String) Tuple(Unk0621, String) := …

  # Livebook.eval/1
  pub def eval(source String) Unk0636 := …

  # Livebook.output/1
  pub def output(p0 Vec(String)) Unk0636 := …

  # Livebook.run/2
  pub def run(session Unk0637, source String) Tuple(Unk0638, Unk0637) := …

  # Livebook.session_pid/0
  pub def session_pid() Unk0639 := …

  # Lower.add_list_elem_vars/2
  pub def add_list_elem_vars(acc Unk0640, p1 Unk0641) Unk0640 := …

  # Lower.add_var/2
  pub def add_var(acc Unk0640, p1 Unk0642) Unk0640 := …

  # Lower.all_pat_vars/1
  pub def all_pat_vars(p0 Sum2) Vec(Unk0643) := …

  # Lower.arm_rebinds/3
  pub def arm_rebinds(pats Unk0644, iso Unk0645, used Unk0646) Vec(Unk0647) := …

  # Lower.assoc/1
  pub def assoc(op String) Unk0648 := …

  # Lower.body_ast/2
  pub def body_ast(src Unk0649, ctx Unk0650) Unk0651 := …

  # Lower.borrow_arg/5
  pub def borrow_arg(a Tuple(Unk0194, String), pt String, funs Map(Unk0652, Unk0653), borrowed Option(Unk0654), ec Unk0655) Unk0656 := …

  # Lower.borrow_value/2
  pub def borrow_value(p0 Tuple(Unk0194, String), _borrowed Option(Unk0654)) Tuple(Unk0194, String) := …

  # Lower.borrowed_in_pat/2
  pub def borrowed_in_pat(p0 Sum2, p1 Bool) Vec(Unk0657) := …

  # Lower.borrowed_vars/2
  pub def borrowed_vars(params Unk0658, pats Unk0659) Option(Unk0660) := …

  # Lower.build_env/3
  pub def build_env(types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Unk0661), ranges Vec(Unk0662)) Unk0663 := …

  # Lower.build_meta/1
  pub def build_meta(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0664 := …

  # Lower.build_struct_meta/1
  pub def build_struct_meta(structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0665 := …

  # Lower.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Lower.case_guard/3
  pub def case_guard(p0 Option(Unk0017), _ Unk0666, _ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.catchall_pat?/1
  pub def catchall_pat?(p0 Sum2) Bool := …

  # Lower.char_vars/2
  pub def char_vars(params Unk0669, pats Unk0670) Unk0671 := …

  # Lower.check!/2
  pub def check!(p0 Map(Unk0672, Vec(Unk0010)), _env Unk0663) Unk0673 := …

  # Lower.coerce_string_ast/2
  pub def coerce_string_ast(p0 Sum1, ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.coerce_string_branch/2
  pub def coerce_string_branch(p0 Sum1, ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.collect_ids/2
  pub def collect_ids(p0 Vec(Unk0674), acc Unk0646) Unk0646 := …

  # Lower.collect_owned_field_vars/3
  pub def collect_owned_field_vars(p0 Unk0675, ctx Map(Unk0677, Unk0676), acc Unk0678) Unk0678 := …

  # Lower.compile/5
  pub def compile(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0672, Vec(Unk0010)), p2 Unk0679, p3 Unk0680, p4 Unk0316) Unk0242 := …

  # Lower.compile_beam/4
  pub def compile_beam(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0672, Vec(Unk0010)), p2 Unk0681, p3 Unk0682) Unk0242 := …

  # Lower.compile_elixir/4
  pub def compile_elixir(types Vec(Map(Unk0009, Vec(Unk0010))), func Map(Unk0672, Vec(Unk0010)), p2 Unk0683, p3 Unk0684) Unk0242 := …

  # Lower.compile_module/1
  pub def compile_module(p0 Unk0685) Unk0242 := …

  # Lower.compile_module_beam/1
  pub def compile_module_beam(p0 Unk0686) Unk0242 := …

  # Lower.cons_tail_names/1
  pub def cons_tail_names(p0 Sum2) Vec(Unk0687) := …

  # Lower.cons_tail_rebinds/1
  pub def cons_tail_rebinds(p0 Sum2) Vec(String) := …

  # Lower.const_set/1
  pub def const_set(consts Vec(Unk0688)) Unk0689 := …

  # Lower.core_pat_ex/1
  pub def core_pat_ex(surface Sum2) String := …

  # Lower.core_pat_rs/2
  pub def core_pat_rs(surface Sum2, meta Unk0690) String := …

  # Lower.core_pat_vars/1
  pub def core_pat_vars(p0 Sum2) Vec(Unk0691) := …

  # Lower.ctx/4
  pub def ctx(meta Unk0664, smeta Unk0665, cset Unk0689, p3 Unk0692) Map(Unk0677, Unk0676) := …

  # Lower.deref_ids/2
  pub def deref_ids(ast Tuple(Unk0693, String), p1 Vec(Unk0694)) Tuple(Unk0693, String) := …

  # Lower.disp/2
  pub def disp(p0 String, p1 Unk0666) String := …

  # Lower.elixir_clauses/3
  pub def elixir_clauses(func Map(Unk0672, Vec(Unk0010)), ctx Unk0695, def_kw String) String := …

  # Lower.emit/3
  pub def emit(p0 Option(Unk0017), _t Unk0666, _ec Tuple(Unk0668, Unk0667)) Tuple(String, Int53) := …

  # Lower.emit_ast/2
  pub def emit_ast(ast Option(Unk0017), target Unk0666) Unk0696 := …

  # Lower.emit_block/3
  pub def emit_block(p0 Sum1, p1 Unk0666, _ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.emit_ctx/1
  pub def emit_ctx(p0 Unk0697) Tuple(Unk0699, Unk0698) := …

  # Lower.emit_expr/2
  pub def emit_expr(src String, target Unk0666) Unk0700 := …

  # Lower.enum_generics/2
  pub def enum_generics(name Unk0701, parametric Map(Unk0701, Vec(Unk0702))) String := …

  # Lower.ex_const/2
  pub def ex_const(c Unk0688, ctx Unk0695) String := …

  # Lower.ex_doc/2
  pub def ex_doc(p0 Vec(Unk0010), _attr String) String := …

  # Lower.ex_struct/1
  pub def ex_struct(s Unk0703) String := …

  # Lower.ex_typespec/1
  pub def ex_typespec(t Map(Unk0704, Vec(Unk0010))) String := …

  # Lower.ex_use/1
  pub def ex_use(p0 Unk0705) String := …

  # Lower.flatten_concat/1
  pub def flatten_concat(p0 Sum1) Vec(Sum1) := …

  # Lower.fn_all_tvars/3
  pub def fn_all_tvars(func Map(Unk0672, Vec(Unk0010)), pinst Unk0706, ec Tuple(Unk0707, Unk0708)) Vec(Unk0010) := …

  # Lower.guard_kw/1
  pub def guard_kw(p0 Unk0666) String := …

  # Lower.guard_str/4
  pub def guard_str(c Map(Unk0709, String), target Unk0666, ec Tuple(Unk0668, Unk0667), p3 Unk0710) String := …

  # Lower.impl_param/2
  pub def impl_param(p0 Unk0711, rust_type String) String := …

  # Lower.infer_concrete_params/3
  pub def infer_concrete_params(func Map(Unk0672, Vec(Unk0010)), params Vec(Unk0712), ec Tuple(Unk0707, Unk0708)) Vec(String) := …

  # Lower.infer_tvar_binding/2
  pub def infer_tvar_binding(p0 Unk0713, ec Unk0714) Unk0715 := …

  # Lower.insert_borrows/4
  pub def insert_borrows(p0 Option(Unk0017), funs Map(Unk0652, Unk0653), ec Unk0655, borrowed Option(Unk0654)) Tuple(Unk0194, String) := …

  # Lower.iso_cons_positions/1
  pub def iso_cons_positions(func Map(Unk0672, Vec(Unk0010))) Unk0645 := …

  # Lower.list_rpat?/1
  pub def list_rpat?(p0 Unk0716) Bool := …

  # Lower.member_scan/3
  pub def member_scan(p0 Vec(Unk0717), _name Vec(Unk0718), _prev Bool) Bool := …

  # Lower.module_elixir/1
  pub def module_elixir(p0 Unk0719) String := …

  # Lower.module_rust/1
  pub def module_rust(p0 Unk0720) String := …

  # Lower.ofb/3
  pub def ofb(p0 Vec(Unk0721), ctx Map(Unk0677, Unk0676), acc Unk0678) Unk0678 := …

  # Lower.owned_arg?/2
  pub def owned_arg?(p0 Tuple(Unk0194, String), _funs Map(Unk0652, Unk0653)) Bool := …

  # Lower.owned_field_binders/2
  pub def owned_field_binders(ast Vec(Unk0721), ctx Map(Unk0677, Unk0676)) Unk0678 := …

  # Lower.owned_field_var?/2
  pub def owned_field_var?(p0 Tuple(Unk0194, String), ec Unk0655) Bool := …

  # Lower.owned_scrut?/2
  pub def owned_scrut?(p0 Unk0722, _ctx Map(Unk0677, Unk0676)) Bool := …

  # Lower.owned_str_arg/1
  pub def owned_str_arg(s Unk0723) Unk0724 := …

  # Lower.p/4
  pub def p(node Option(Unk0017), ctx Int53, t Unk0666, ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.pair_inst/2
  pub def pair_inst(func Map(Unk0672, Vec(Unk0010)), ec Tuple(Unk0707, Unk0708)) Unk0706 := …

  # Lower.param_rtypes/2
  pub def param_rtypes(name Unk0652, funs Map(Unk0652, Unk0653)) Vec(String) := …

  # Lower.parametric_param_map/1
  pub def parametric_param_map(types Vec(Map(Unk0009, Vec(Unk0010)))) Unk0725 := …

  # Lower.parametric_used?/2
  pub def parametric_used?(func Map(Unk0672, Vec(Unk0010)), name Unk0726) Bool := …

  # Lower.pascal?/1
  pub def pascal?(s Unk0727) Bool := …

  # Lower.pat_ex/1
  pub def pat_ex(p0 Sum2) String := …

  # Lower.pat_rs/2
  pub def pat_rs(p0 Sum2, _ Unk0690) String := …

  # Lower.pipe_to_call/2
  pub def pipe_to_call(l Unk0728, p1 Sum1) Option(Unk0017) := …

  # Lower.proto_method_traits/1
  pub def proto_method_traits(protocols Vec(Map(Unk0009, Vec(Unk0010)))) Unk0729 := …

  # Lower.pub_sig_type_names/1
  pub def pub_sig_type_names(funcs Unk0730) Unk0731 := …

  # Lower.ref_type/2
  pub def ref_type(p0 String, self_repr Unk0732) String := …

  # Lower.resolve_consts/2
  pub def resolve_consts(p0 Option(Unk0017), cset Unk0733) Tuple(Unk0194, String) := …

  # Lower.resolve_rust_pats/2
  pub def resolve_rust_pats(p0 Option(Unk0017), meta Unk0690) Tuple(Unk0194, String) := …

  # Lower.resolve_structs/2
  pub def resolve_structs(p0 Option(Unk0017), smeta Unk0734) Tuple(Unk0194, String) := …

  # Lower.resolve_variants/2
  pub def resolve_variants(p0 Option(Unk0017), meta Map(Unk0736, Option(Unk0735))) Tuple(Unk0194, String) := …

  # Lower.rest_pat_rs/1
  pub def rest_pat_rs(p0 Sum2) String := …

  # Lower.result_parts/1
  pub def result_parts(ret String) Tuple(Unk0737, String) := …

  # Lower.result_payload/3
  pub def result_payload(val Option(Unk0017), string? Bool, ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.rewrite_proto_calls/2
  pub def rewrite_proto_calls(p0 Vec(Unk0738), methods Unk0739) Vec(Unk0738) := …

  # Lower.rpat/1
  pub def rpat(p0 Sum2) String := …

  # Lower.rs_doc/2
  pub def rs_doc(p0 Vec(Unk0010), _prefix String) String := …

  # Lower.rust_arm_body/2
  pub def rust_arm_body(p0 Sum1, s String) String := …

  # Lower.rust_case/4
  pub def rust_case(scrut Option(Unk0017), arms Vec(Unk0740), body_fn Fn(Option(Unk0017), String), ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.rust_const/2
  pub def rust_const(c Unk0688, ctx Map(Unk0677, Unk0676)) String := …

  # Lower.rust_enum/3
  pub def rust_enum(t Map(Unk0009, Vec(Unk0010)), p1 String, p2 Unk0725) String := …

  # Lower.rust_fn/4
  pub def rust_fn(p0 Map(Unk0672, Vec(Unk0010)), _ctx Map(Unk0677, Unk0676), vis String, _base_ec Tuple(Unk0699, Unk0698)) String := …

  # Lower.rust_generics/1
  pub def rust_generics(p0 Unk0741) String := …

  # Lower.rust_impl/4
  pub def rust_impl(p0 Map(Unk0009, Vec(Unk0010)), protocols Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0677, Unk0676), base_ec Tuple(Unk0699, Unk0698)) String := …

  # Lower.rust_impl_method/6
  pub def rust_impl_method(method Unk0742, sig Unk0743, rust_type String, c Map(Unk0677, Unk0676), copy_recv? Bool, base_ec Tuple(Unk0699, Unk0698)) String := …

  # Lower.rust_lit_type/1
  pub def rust_lit_type(p0 Unk0744) String := …

  # Lower.rust_owned_elem/2
  pub def rust_owned_elem(p0 Option(Unk0017), ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.rust_program/1
  pub def rust_program(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) String := …

  # Lower.rust_proto_body/3
  pub def rust_proto_body(src Unk0745, c Map(Unk0747, Unk0746), ec Unk0748) Unk0749 := …

  # Lower.rust_protocols/4
  pub def rust_protocols(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), types Vec(Map(Unk0009, Vec(Unk0010))), structs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0750 := …

  # Lower.rust_scrut/2
  pub def rust_scrut(params Unk0751, iso Unk0645) String := …

  # Lower.rust_struct/2
  pub def rust_struct(s Unk0752, p1 Unk0753) String := …

  # Lower.rust_total_shim?/1
  pub def rust_total_shim?(func Map(Unk0672, Vec(Unk0010))) Bool := …

  # Lower.rust_trait/1
  pub def rust_trait(p0 Unk0754) String := …

  # Lower.rust_use/1
  pub def rust_use(p0 Unk0755) String := …

  # Lower.rustify_parametric/2
  pub def rustify_parametric(rust_type String, pinst Vec(Unk0756)) String := …

  # Lower.scalar_literal?/1
  pub def scalar_literal?(p0 Tuple(Unk0194, String)) Bool := …

  # Lower.sig_param/2
  pub def sig_param(p String, self_repr Unk0757) String := …

  # Lower.slice_binders/2
  pub def slice_binders(params Unk0758, pats Vec(Sum2)) Unk0678 := …

  # Lower.slice_elem_vars/1
  pub def slice_elem_vars(p0 Sum2) Vec(Unk0759) := …

  # Lower.slice_var?/2
  pub def slice_var?(p0 Sum1, ec Tuple(Unk0668, Unk0667)) Bool := …

  # Lower.str_lit/1
  pub def str_lit(s Unk0760) String := …

  # Lower.strip_prefix/2
  pub def strip_prefix(rest Vec(Unk0761), p1 Vec(Unk0718)) Tuple(Unk0762, Vec(Unk0761)) := …

  # Lower.struct_pairs/4
  pub def struct_pairs(name Unk0763, labels Vec(Unk0764), args Vec(Option(Unk0017)), smeta Unk0734) Unk0765 := …

  # Lower.subst_assoc/2
  pub def subst_assoc(t String, assoc_rust Vec(Unk0766)) String := …

  # Lower.tail_expr/1
  pub def tail_expr(p0 Unk0767) Unk0767 := …

  # Lower.tail_slice_id?/2
  pub def tail_slice_id?(p0 Sum1, ec Tuple(Unk0668, Unk0667)) Bool := …

  # Lower.to_elixir/4
  pub def to_elixir(func Map(Unk0672, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), p2 Unk0768, p3 Unk0665) Unk0769 := …

  # Lower.to_rust/6
  pub def to_rust(func Map(Unk0672, Vec(Unk0010)), types Vec(Map(Unk0009, Vec(Unk0010))), meta Unk0664, p3 Unk0770, p4 Unk0665, p5 Unk0771) Unk0772 := …

  # Lower.trait_impl_block/4
  pub def trait_impl_block(protocols Vec(Map(Unk0009, Vec(Unk0010))), impl_decls Vec(Map(Unk0009, Vec(Unk0010))), c Map(Unk0677, Unk0676), base_ec Tuple(Unk0699, Unk0698)) String := …

  # Lower.trait_params/2
  pub def trait_params(param_str String, self_repr Unk0757) String := …

  # Lower.tuple_or_one/2
  pub def tuple_or_one(p0 Vec(Sum2), f Fn(Sum2, String)) String := …

  # Lower.tvar_name?/1
  pub def tvar_name?(t Unk0773) Bool := …

  # Lower.type_idents/1
  pub def type_idents(p0 Unk0774) Vec(Unk0775) := …

  # Lower.type_param_tvars/1
  pub def type_param_tvars(t Unk0776) Unk0777 := …

  # Lower.used_ids/1
  pub def used_ids(ast Vec(Unk0674)) Unk0646 := …

  # Lower.user_type?/2
  pub def user_type?(t Unk0778, ctx Map(Unk0677, Unk0676)) Bool := …

  # Lower.variant_info/2
  pub def variant_info(meta Map(Unk0736, Option(Unk0735)), name Unk0727) Option(Unk0735) := …

  # Lower.variant_lit/2
  pub def variant_lit(info Option(Unk0735), pairs Vec(Unk0779)) Tuple(Unk0194, String) := …

  # Lower.variant_pairs/3
  pub def variant_pairs(info Option(Unk0735), args Vec(Option(Unk0017)), meta Map(Unk0736, Option(Unk0735))) Vec(Unk0779) := …

  # Lower.widen_char_arith/2
  pub def widen_char_arith(p0 Option(Unk0017), cvars Unk0780) Tuple(Unk0194, String) := …

  # Lower.with_chain_rs/4
  pub def with_chain_rs(p0 Vec(Unk0781), body String, _else_rs String, _ec Tuple(Unk0668, Unk0667)) String := …

  # Lower.word_member?/2
  pub def word_member?(str Unk0782, name Unk0726) Bool := …

  # Lower.word_scan/4
  pub def word_scan(p0 Vec(Unk0783), _name Vec(Unk0718), _repl String, _prev Bool) String := …

  # Lower.wrap_char/2
  pub def wrap_char(p0 Tuple(Unk0194, String), _cvars Unk0780) Tuple(Unk0194, String) := …

  # Macro.binders_here/1
  pub def binders_here(p0 Vec(Unk0784)) Vec(Unk0785) := …

  # Macro.build_env/1
  pub def build_env(defs Unk0786) Map(Unk0240, Unk0241) := …

  # Macro.check_portable!/2
  pub def check_portable!(name Unk0787, tmpl Option(Unk0017)) Unk0788 := …

  # Macro.collect_binders/1
  pub def collect_binders(node Vec(Unk0784)) Vec(Unk0785) := …

  # Macro.do_expand/4
  pub def do_expand(_env Map(Unk0240, Unk0241), _ast Option(Unk0017), d Int53, _p Bool) Tuple(Unk0194, String) := …

  # Macro.expand/3
  pub def expand(env Map(Unk0240, Unk0241), ast Option(Unk0017), p2 Vec(Tuple(Unk0789, Bool))) Option(Unk0017) := …

  # Macro.freshen/2
  pub def freshen(tmpl Vec(Unk0784), params Unk0790) Tuple(Unk0194, Vec(Unk0791)) := …

  # Macro.introduces_failable_bind?/1
  pub def introduces_failable_bind?(node Option(Unk0017)) Bool := …

  # Macro.map_node/2
  pub def map_node(p0 Option(Unk0017), f Fn(Option(Unk0017), Tuple(Unk0194, String))) Tuple(Unk0194, String) := …

  # Macro.rename/2
  pub def rename(p0 Vec(Unk0784), ren Map(Unk0792, Vec(Unk0791))) Tuple(Unk0194, Vec(Unk0791)) := …

  # Macro.substitute/2
  pub def substitute(p0 Tuple(Unk0194, Vec(Unk0791)), subst Map(Unk0793, Option(Unk0017))) Option(Unk0017) := …

  # Macro.walk_for_with/1
  pub def walk_for_with(p0 Option(Unk0017)) Tuple(Unk0194, String) := …

  # Opaque.do_erase/2
  pub def do_erase(prog Unk0794, ctx Tuple(Unk0795, Unk0796)) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase/1
  pub def erase(p0 Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Map(Unk0033, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Opaque.erase_clause/3
  pub def erase_clause(p0 Unk0797, _ctx Unk0798, _env Unk0799) Clause := …

  # Opaque.erase_const/2
  pub def erase_const(p0 Unk0800, p1 Unk0801) Const := …

  # Opaque.erase_ctx/1
  pub def erase_ctx(all Vec(Unk0802)) Tuple(Unk0795, Unk0796) := …

  # Opaque.erase_func/2
  pub def erase_func(p0 Unk0803, p1 Tuple(Unk0795, Unk0796)) Func := …

  # Opaque.erase_mod/2
  pub def erase_mod(p0 Unk0804, ctx Tuple(Unk0795, Unk0796)) Mod := …

  # Opaque.erase_struct/2
  pub def erase_struct(p0 Unk0805, p1 Tuple(Unk0795, Unk0796)) Struct := …

  # Opaque.erase_type/2
  pub def erase_type(p0 Unk0806, p1 Tuple(Unk0795, Unk0796)) Type := …

  # Opaque.erase_variant/2
  pub def erase_variant(p0 Unk0807, names Unk0808) Variant := …

  # Opaque.opaques/1
  pub def opaques(prog Map(Unk0809, Vec(Unk0802))) Vec(Unk0802) := …

  # Opaque.strip/3
  pub def strip(p0 Vec(Unk0810), p1 Unk0811, env Map(Unk0085, Vec(Unk0079))) Vec(Unk0810) := …

  # Opaque.strip_into/3
  pub def strip_into(ast Vec(Unk0810), ctx Unk0811, env Map(Unk0085, Vec(Unk0079))) Vec(Unk0810) := …

  # Opaque.subst/2
  pub def subst(p0 Option(Unk0812), _names Unk0813) Option(Unk0812) := …

  # Opaque.subst_fix/4
  pub def subst_fix(type Option(Unk0812), _names Unk0813, _re Unk0814, p3 Int53) Option(Unk0812) := …

  # PatternLower.add_struct/3
  pub def add_struct(env Tuple(Unk0367, Map(String, String)), name String, fields Vec(String)) Tuple(Unk0367, Map(String, String)) := …

  # PatternLower.lower/2
  pub def lower(pat Sum2, env Map(Unk0373, Unk0372)) Tuple(Unk0815, Bool) := …

  # PatternLower.lower_clause/2
  pub def lower_clause(p0 Unk0816, env Map(Unk0373, Unk0372)) Unk0371 := …

  # PatternLower.lower_list/3
  pub def lower_list(p0 Vec(Sum2), p1 Sum2, _env Map(Unk0373, Unk0372)) Tuple(Unk0815, Bool) := …

  # PatternLower.lower_many/2
  pub def lower_many(ps Vec(Sum2), env Map(Unk0373, Unk0372)) Unk0817 := …

  # PortAnalysis.analyze/1
  pub def analyze(sources Unk0818) Unk0819 := …

  # PortAnalysis.case_arm_sets/1
  pub def case_arm_sets(ast Unk0820) Vec(Unk0821) := …

  # PortAnalysis.clause_head_sets/1
  pub def clause_head_sets(ast Unk0820) Vec(Unk0821) := …

  # PortAnalysis.cluster_sums/1
  pub def cluster_sums(sets Vec(Unk0822)) Unk0537 := …

  # PortAnalysis.collect_errors/2
  pub def collect_errors(ast Unk0823, acc Unk0824) Unk0824 := …

  # PortAnalysis.collect_groups/1
  pub def collect_groups(p0 Unk0825) Vec(Unk0535) := …

  # PortAnalysis.collect_structs/2
  pub def collect_structs(ast Unk0826, acc Unk0827) Unk0827 := …

  # PortAnalysis.dispatch_sets/1
  pub def dispatch_sets(ast Unk0820) Vec(Unk0822) := …

  # PortAnalysis.error_proposal/1
  pub def error_proposal(p0 Unk0828) Unk0829 := …

  # PortAnalysis.error_shape/1
  pub def error_shape(p0 Unk0830) Tuple(Unk0831, Option(Unk0832)) := …

  # PortAnalysis.errors_section/1
  pub def errors_section(data Unk0833) String := …

  # PortAnalysis.head_name_pats/1
  pub def head_name_pats(p0 Unk0834) Tuple(Unk0836, Vec(Unk0835)) := …

  # PortAnalysis.holes_section/1
  pub def holes_section(data Unk0833) String := …

  # PortAnalysis.module_name/1
  pub def module_name(p0 Unk0837) String := …

  # PortAnalysis.module_report/3
  pub def module_report(file Unk0838, ast Unk0837, src Unk0839) Unk0840 := …

  # PortAnalysis.module_stmts/1
  pub def module_stmts(p0 Unk0841) Vec(String) := …

  # PortAnalysis.needs_review?/1
  pub def needs_review?(p0 Unk0842) Bool := …

  # PortAnalysis.param_name_index/1
  pub def param_name_index(mods_groups Vec(Tuple(String, Vec(Unk0535)))) Unk0843 := …

  # PortAnalysis.parse/1
  pub def parse(src Unk0844) Option(Unk0845) := …

  # PortAnalysis.pascal/1
  pub def pascal(atom_str Unk0846) Unk0847 := …

  # PortAnalysis.pattern_structs/1
  pub def pattern_structs(p0 Unk0848) Vec(Unk0849) := …

  # PortAnalysis.reach_note/1
  pub def reach_note(type String) Unk0850 := …

  # PortAnalysis.short/1
  pub def short(p0 Unk0851) String := …

  # PortAnalysis.sigs_section/1
  pub def sigs_section(data Unk0833) String := …

  # PortAnalysis.src_of/2
  pub def src_of(sources Unk0818, file Unk0852) Unk0839 := …

  # PortAnalysis.summary_section/1
  pub def summary_section(data Unk0833) String := …

  # PortAnalysis.sums_section/1
  pub def sums_section(data Unk0833) String := …

  # PortAnalysis.to_markdown/1
  pub def to_markdown(data Unk0833) Unk0853 := …

  # Pratt.after_paren/2
  pub def after_paren(tokens Vec(Unk0854), p1 Int53) Vec(Unk0854) := …

  # Pratt.assoc/1
  pub def assoc(op Option(Unk0855)) Unk0856 := …

  # Pratt.bp/1
  pub def bp(op Option(Unk0855)) Tuple(Int53, Int53) := …

  # Pratt.climb/3
  pub def climb(lhs Option(Unk0857), tokens Vec(Vec(Vec(Unk0620))), min_bp Int53) Tuple(Option(Unk0857), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.collect_dots/2
  pub def collect_dots(node Tuple(Unk0858, Unk0859), p1 Vec(Vec(Unk0620))) Tuple(Tuple(Unk0858, Unk0859), Vec(Vec(Unk0620))) := …

  # Pratt.desugar_prop/2
  pub def desugar_prop(stmts Vec(Tuple(Unk0861, Unk0860)), depth Int53) Tuple(Unk0862, Vec(Tuple(Unk0861, Unk0860))) := …

  # Pratt.desugar_propagation/1
  pub def desugar_propagation(stmts Vec(Tuple(Unk0861, Unk0860))) Tuple(Unk0862, Vec(Tuple(Unk0861, Unk0860))) := …

  # Pratt.expect_kw/2
  pub def expect_kw(p0 Vec(Vec(Vec(Unk0620))), k String) Vec(Vec(Vec(Unk0620))) := …

  # Pratt.expect_op/2
  pub def expect_op(p0 Vec(Vec(Vec(Unk0620))), o String) Vec(Vec(Vec(Unk0620))) := …

  # Pratt.expect_rbracket/1
  pub def expect_rbracket(p0 Vec(Vec(Vec(Unk0620)))) Vec(Vec(Vec(Unk0620))) := …

  # Pratt.expect_rparen/1
  pub def expect_rparen(p0 Vec(Vec(Vec(Unk0620)))) Vec(Vec(Vec(Unk0620))) := …

  # Pratt.finish_arg/2
  pub def finish_arg(a Unk0863, p1 Vec(Vec(Vec(Unk0620)))) Tuple(Vec(Unk0863), Vec(Vec(Vec(Vec(Unk0620))))) := …

  # Pratt.here/1
  pub def here(p0 Vec(Unk0864)) String := …

  # Pratt.int_of/1
  pub def int_of(n Unk0865) Vec(Tuple(Unk0867, Unk0866)) := …

  # Pratt.lambda_ahead?/1
  pub def lambda_ahead?(p0 Vec(Unk0854)) Bool := …

  # Pratt.level/1
  pub def level(op Option(Unk0855)) Unk0868 := …

  # Pratt.opinfo/1
  pub def opinfo(op String) Unk0869 := …

  # Pratt.parse/1
  pub def parse(ast String) Option(Unk0017) := …

  # Pratt.parse_args/1
  pub def parse_args(p0 Vec(Vec(Vec(Vec(Unk0620))))) Tuple(Vec(Unk0863), Vec(Vec(Vec(Vec(Unk0620))))) := …

  # Pratt.parse_arms/2
  pub def parse_arms(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Unk0870)) Tuple(Vec(Unk0870), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_block/1
  pub def parse_block(tokens Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0862, Vec(Tuple(Unk0861, Unk0860))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_body/1
  pub def parse_body(ast Option(Unk0017)) Option(Unk0017) := …

  # Pratt.parse_capture/1
  pub def parse_capture(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_case/1
  pub def parse_case(tokens Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_expr/2
  pub def parse_expr(tokens Vec(Vec(Vec(Unk0620))), min_bp Int53) Tuple(Option(Unk0857), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_if/1
  pub def parse_if(tokens Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_lambda/1
  pub def parse_lambda(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_list/2
  pub def parse_list(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Unk0872)) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_map/2
  pub def parse_map(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0867, Unk0866))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_param/1
  pub def parse_param(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0873, Option(Unk0874)), Vec(Vec(Unk0620))) := …

  # Pratt.parse_params/1
  pub def parse_params(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Vec(Unk0875), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat/1
  pub def parse_pat(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0876, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat_args/2
  pub def parse_pat_args(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Unk0877)) Tuple(Vec(Unk0877), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat_fields/2
  pub def parse_pat_fields(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0879, Unk0878))) Tuple(Vec(Tuple(Unk0879, Unk0878)), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat_list/2
  pub def parse_pat_list(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Unk0880)) Tuple(Tuple(Unk0876, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat_map/2
  pub def parse_pat_map(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0867, Unk0866))) Tuple(Tuple(Unk0876, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_pat_tuple/2
  pub def parse_pat_tuple(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0867, Unk0866))) Tuple(Tuple(Unk0876, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_path/1
  pub def parse_path(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0858, Unk0859), Vec(Vec(Unk0620))) := …

  # Pratt.parse_pats/1
  pub def parse_pats(str String) Vec(Unk0881) := …

  # Pratt.parse_pats/2
  pub def parse_pats(tokens Vec(Vec(Vec(Unk0620))), acc Vec(Unk0881)) Vec(Unk0881) := …

  # Pratt.parse_postfix/2
  pub def parse_postfix(node Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), p1 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_prefix/1
  pub def parse_prefix(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_primary/1
  pub def parse_primary(p0 Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_stmt/1
  pub def parse_stmt(p0 Vec(Vec(Vec(Vec(Unk0620))))) Tuple(Tuple(Unk0883, Unk0882), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_stmts/2
  pub def parse_stmts(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Unk0884)) Tuple(Vec(Unk0884), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_tuple/2
  pub def parse_tuple(p0 Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0867, Unk0866))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_type/1
  pub def parse_type(p0 Vec(Vec(Vec(Unk0620)))) Tuple(String, Vec(Vec(Unk0620))) := …

  # Pratt.parse_type_args/2
  pub def parse_type_args(tokens Vec(Vec(Vec(Unk0620))), acc Vec(Unk0885)) Tuple(Vec(Unk0885), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_with/1
  pub def parse_with(tokens Vec(Vec(Vec(Unk0620)))) Tuple(Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.parse_with_clauses/2
  pub def parse_with_clauses(tokens Vec(Vec(Vec(Unk0620))), acc Vec(Tuple(Unk0886, Unk0887))) Tuple(Vec(Tuple(Unk0886, Unk0887)), Vec(Vec(Vec(Unk0620)))) := …

  # Pratt.pascal?/1
  pub def pascal?(s Unk0888) Bool := …

  # Pratt.peek_infix/1
  pub def peek_infix(p0 Vec(Vec(Vec(Unk0620)))) Option(Unk0855) := …

  # Pratt.same_level_root?/2
  pub def same_level_root?(p0 Option(Unk0857), op Option(Unk0855)) Bool := …

  # Pratt.sexpr/1
  pub def sexpr(p0 Option(Unk0017)) String := …

  # Pratt.sexpr_pat/1
  pub def sexpr_pat(p0 Unk0889) String := …

  # Pratt.sexpr_stmt/1
  pub def sexpr_stmt(p0 Unk0890) String := …

  # Pratt.str_interp/1
  pub def str_interp(parts Vec(Unk0891)) Tuple(Unk0871, Vec(Tuple(Unk0867, Unk0866))) := …

  # Pratt.tok_desc/1
  pub def tok_desc(p0 Unk0864) String := …

  # Prelude.with_prelude/1
  pub def with_prelude(types Vec(Map(Unk0009, Vec(Unk0010)))) Vec(Type) := …

  # Prim.normalize/1
  pub def normalize(p0 String) Option(Unk0017) := …

  # Protocol.check_assoc!/2
  pub def check_assoc!(protocols Vec(Unk0217), impl_decls Vec(Unk0217)) Unk0892 := …

  # Protocol.check_impl/3
  pub def check_impl(p0 Unk0893, protocols Unk0894, reg Unk0895) Unk0896 := …

  # Protocol.check_no_overlap/3
  pub def check_no_overlap(impls Vec(Unk0897), reg Unk0895, targets Unk0898) Unk0899 := …

  # Protocol.dispatcher/4
  pub def dispatcher(proto Unk0900, sig Unk0901, impls Vec(Unk0897), reg Unk0895) Vec(Unk0902) := …

  # Protocol.dispatcher_params/2
  pub def dispatcher_params(sig_params Unk0903, vars Vec(String)) Unk0904 := …

  # Protocol.expand/5
  pub def expand(protocols Unk0894, impls Vec(Unk0897), p2 Unk0317, p3 Unk0318, p4 Unk0319) Vec(Unk0320) := …

  # Protocol.guard_for!/3
  pub def guard_for!(type String, proto Unk0900, reg Unk0895) Unk0905 := …

  # Protocol.impl_methods/2
  pub def impl_methods(p0 Unk0897, protocols Unk0894) Vec(Unk0320) := …

  # Protocol.mangle/3
  pub def mangle(proto Unk0906, type Unk0907, method Unk0908) String := …

  # Protocol.param_type/1
  pub def param_type(p Unk0909) Unk0910 := …

  # Protocol.registry/2
  pub def registry(types Unk0911, structs Vec(Unk0912)) Unk0895 := …

  # Protocol.runtime_dispatch_target?/1
  pub def runtime_dispatch_target?(p0 Unk0898) Bool := …

  # Protocol.subst_self/2
  pub def subst_self(p0 Unk0913, _type Unk0914) Option(Unk0915) := …

  # Protocol.sum_guard/1
  pub def sum_guard(variants Unk0916) String := …

  # Protocol.tag_disjunction/2
  pub def tag_disjunction(variants Vec(Unk0917), lhs Unk0918) String := …

  # Range.check/3
  pub def check(lo Unk0919, hi Unk0920, a Sum1) Sum1 := …

  # Range.expand_of/2
  pub def expand_of(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Range.lit/1
  pub def lit(n Unk0921) Sum1 := …

  # Range.table/1
  pub def table(ranges Vec(Map(Unk0009, Vec(Unk0010)))) Map(Unk0018, Unk0019) := …

  # Range.walk/2
  pub def walk(node Option(Unk0017), table Map(Unk0018, Unk0019)) Sum1 := …

  # Reach.all_emittable?/2
  pub def all_emittable?(f Map(Unk0922, Vec(Unk0923)), pctx Unk0924) Bool := …

  # Reach.all_funcs/1
  pub def all_funcs(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Vec(Map(Unk0009, Vec(Unk0010))) := …

  # Reach.analyze/1
  pub def analyze(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk0925 := …

  # Reach.atom_prim_blocker/0
  pub def atom_prim_blocker() Unk0926 := …

  # Reach.bare_atom_blocker/0
  pub def bare_atom_blocker() Unk0926 := …

  # Reach.build_default/0
  pub def build_default() Option(Unk0927) := …

  # Reach.builder_tail_ok?/2
  pub def builder_tail_ok?(f Map(Unk0922, Vec(Unk0923)), generics Unk0928) Bool := …

  # Reach.check_contracts/2
  pub def check_contracts(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), p1 Option(Unk0927)) Tuple(Unk0929, String) := …

  # Reach.classify/3
  pub def classify(p0 Sum1, _modnames Unk0930, p2 Tuple(Vec(Unk0926), Unk0931)) Tuple(Vec(Unk0926), Unk0931) := …

  # Reach.collect_ctors/2
  pub def collect_ctors(p0 Sum1, ctors Map(Unk0932, Unk0933)) Vec(Tuple(Unk0934, Unk0935)) := …

  # Reach.conc_erl?/2
  pub def conc_erl?(m String, fun Unk0936) Bool := …

  # Reach.contract_message/1
  pub def contract_message(violations Vec(Unk0937)) String := …

  # Reach.core/2
  pub def core(src Unk0938, parser Fn(Unk0940, Unk0939)) Sum1 := …

  # Reach.ctor_aligned?/2
  pub def ctor_aligned?(p0 Tuple(Unk0934, Unk0935), f Map(Unk0922, Vec(Unk0923))) Bool := …

  # Reach.deep/1
  pub def deep(t Option(Unk0017)) Vec(Unk0941) := …

  # Reach.emittable_parametric?/1
  pub def emittable_parametric?(t Unk0942) Unk0943 := …

  # Reach.ffi/2
  pub def ffi(construct String, conc? Bool) Unk0926 := …

  # Reach.find_atom_ordering/1
  pub def find_atom_ordering(p0 Option(Unk0017)) Vec(Unk0941) := …

  # Reach.fixpoint/2
  pub def fixpoint(facts Unk0944, table Map(Unk0946, Unk0945)) Map(Unk0946, Unk0945) := …

  # Reach.fn_type_blocker/0
  pub def fn_type_blocker() Unk0926 := …

  # Reach.func_symbol_violations/1
  pub def func_symbol_violations(f Unk0947) Vec(Unk0941) := …

  # Reach.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.gate!/2
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), default Option(Unk0927)) Symbol := …

  # Reach.int_blocker/0
  pub def int_blocker() Unk0926 := …

  # Reach.js_wide_int?/1
  pub def js_wide_int?(t Unk0948) Bool := …

  # Reach.mix_default/0
  pub def mix_default() Unk0949 := …

  # Reach.parametric_blocker/0
  pub def parametric_blocker() Unk0926 := …

  # Reach.parametric_constructions/2
  pub def parametric_constructions(f Map(Unk0922, Vec(Unk0923)), ctors Map(Unk0932, Unk0933)) Vec(Tuple(Unk0934, Unk0935)) := …

  # Reach.parametric_ctx/2
  pub def parametric_ctx(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))), funs Vec(Map(Unk0009, Vec(Unk0010)))) Unk0924 := …

  # Reach.parametric_rs_ok?/2
  pub def parametric_rs_ok?(f Map(Unk0922, Vec(Unk0923)), pctx Unk0924) Bool := …

  # Reach.parametric_type?/1
  pub def parametric_type?(t Unk0950) Bool := …

  # Reach.pascal?/1
  pub def pascal?(s Unk0951) Bool := …

  # Reach.ref_blocker/0
  pub def ref_blocker() Unk0926 := …

  # Reach.result_value_blocker/0
  pub def result_value_blocker() Unk0926 := …

  # Reach.scan/3
  pub def scan(p0 Sum1, modnames Unk0930, p2 Tuple(Vec(Unk0926), Unk0931)) Tuple(Vec(Unk0926), Unk0931) := …

  # Reach.scan_func/3
  pub def scan_func(f Map(Unk0922, Vec(Unk0923)), modnames Unk0930, pctx Unk0924) Tuple(Vec(Unk0926), Unk0931) := …

  # Reach.sig_idents/1
  pub def sig_idents(f Map(Unk0952, Vec(Unk0953))) Unk0954 := …

  # Reach.sig_uses_fn_type?/1
  pub def sig_uses_fn_type?(f Map(Unk0922, Vec(Unk0923))) Bool := …

  # Reach.symbol_lint!/1
  pub def symbol_lint!(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Symbol := …

  # Reach.tail_calls_generic?/2
  pub def tail_calls_generic?(p0 Unk0955, generics Unk0928) Bool := …

  # Reach.tvar?/1
  pub def tvar?(t Unk0956) Unk0957 := …

  # Reach.type_has_tvar?/1
  pub def type_has_tvar?(t Unk0958) Bool := …

  # Reach.type_idents/1
  pub def type_idents(t Unk0958) Vec(Unk0959) := …

  # Reach.uses_parametric?/2
  pub def uses_parametric?(f Map(Unk0922, Vec(Unk0923)), names Unk0960) Bool := …

  # Reach.validate_default/1
  pub def validate_default(p0 Option(Unk0927)) Option(Unk0927) := …

  # Reach.wide_prim_blocker/0
  pub def wide_prim_blocker() Unk0926 := …

  # Reach.width_blocker/0
  pub def width_blocker() Unk0926 := …

  # Repl.accumulate_line/2
  pub def accumulate_line(line String, p1 Unk0961) Tuple(Vec(String), String) := …

  # Repl.bind_env/2
  pub def bind_env(binds Vec(Unk0962), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Map(Unk0085, Vec(Unk0079)) := …

  # Repl.bind_with_type/4
  pub def bind_with_type(s Session, input String, name String, type Vec(Unk0079)) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.candidate_pool/2
  pub def candidate_pool(p0 Unk0964, _s Session) Vec(Unk0965) := …

  # Repl.common_prefix/2
  pub def common_prefix(a Unk0966, b Unk0967) String := …

  # Repl.common_prefix/3
  pub def common_prefix(p0 Unk0966, p1 Unk0967, acc String) String := …

  # Repl.complete/2
  pub def complete(before_cursor String, p1 Session) Tuple(Vec(Unk0968), String) := …

  # Repl.continuation/2
  pub def continuation(_word String, p1 Vec(Unk0968)) String := …

  # Repl.decl_names/1
  pub def decl_names(input String) Unk0969 := …

  # Repl.describe/1
  pub def describe(p0 Session) Unk0970 := …

  # Repl.eval/2
  pub def eval(p0 Session, input String) Unk0971 := …

  # Repl.eval_bind/4
  pub def eval_bind(s Session, input String, name String, rhs Option(Unk0017)) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.eval_decl/2
  pub def eval_decl(s Tuple(Unk0972, Vec(Tuple(Unk0969, Unk0973))), input String) Tuple(Tuple(Unk0974, Unk0969), Unk0975) := …

  # Repl.eval_expr/2
  pub def eval_expr(s Session, input String) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.eval_stmt/2
  pub def eval_stmt(s Session, input String) Tuple(Tuple(Unk0963, String), Session) := …

  # Repl.flush_entries/1
  pub def flush_entries(p0 Unk0976) Vec(Unk0977) := …

  # Repl.infer_or_unknown/3
  pub def infer_or_unknown(ast Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Repl.info/1
  pub def info(p0 Session) Unk0978 := …

  # Repl.longest_common_prefix/1
  pub def longest_common_prefix(p0 Vec(Unk0979)) Unk0979 := …

  # Repl.program/3
  pub def program(units Vec(Tuple(Unk0969, Unk0973)), binds Vec(Tuple(String, Unk0980)), expr_src String) String := …

  # Repl.reload/2
  pub def reload(s Tuple(Unk0972, Vec(Tuple(Unk0969, Unk0973))), src String) Symbol := …

  # Repl.render/1
  pub def render(p0 Unk0981) String := …

  # Repl.run/4
  pub def run(s Tuple(Unk0972, Vec(Tuple(Unk0969, Unk0973))), binds Vec(Tuple(String, Unk0980)), units Vec(Tuple(Unk0969, Unk0973)), expr_src String) Tuple(Unk0982, Unk0983) := …

  # Repl.safe_decl/1
  pub def safe_decl(units Vec(Tuple(Unk0969, Unk0973))) Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010)))) := …

  # Repl.safe_infer/3
  pub def safe_infer(ast Option(Unk0017), env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Repl.safe_infer_input/3
  pub def safe_infer_input(input String, env Map(Unk0085, Vec(Unk0079)), ic Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079)))) Vec(Unk0079) := …

  # Repl.safe_parse_body/1
  pub def safe_parse_body(input String) Tuple(Unk0984, Option(Unk0017)) := …

  # Repl.scan_count/2
  pub def scan_count(input String, regex Unk0985) Unk0986 := …

  # Repl.session_ic/1
  pub def session_ic(p0 Session) Map(Unk0081, Map(Vec(Unk0079), Vec(Unk0079))) := …

  # Repl.type_of/2
  pub def type_of(p0 Session, input String) Vec(Unk0079) := …

  # Repl.units_src/1
  pub def units_src(units Vec(Tuple(Unk0969, Unk0973))) String := …

  # SelfHost.badge/1
  pub def badge(p0 Unk0987) String := …

  # SelfHost.composition/0
  pub def composition() Unk0988 := …

  # SelfHost.evidence/1
  pub def evidence(p0 Unk0989) String := …

  # SelfHost.external_host_calls/1
  pub def external_host_calls(prog Map(Unk0990, Vec(Map(Unk0991, Vec(Unk0992))))) Vec(Unk0993) := …

  # SelfHost.ffi_ledger/0
  pub def ffi_ledger() Unk0994 := …

  # SelfHost.passes/0
  pub def passes() Unk0995 := …

  # SelfHost.sibling_compose_call?/2
  pub def sibling_compose_call?(construct Unk0996, siblings Unk0997) Bool := …

  # SelfHost.stages/0
  pub def stages() Unk0998 := …

  # SelfHost.status_markdown/1
  pub def status_markdown(stages Vec(Unk0999)) String := …

  # Shadow.ded_bind/5
  pub def ded_bind(n Unk1000, t Bool, e Vec(Unk1001), p3 Unk1002, fresh Fn(Unk1005, Unk1003, Unk1004)) Unk1006 := …

  # Shadow.ded_block/4
  pub def ded_block(stmts Vec(Unk1007), r Map(Unk1009, Unk1008), ver Unk1010, fresh Fn(Unk1005, Unk1003, Unk1004)) Vec(Unk0549) := …

  # Shadow.ded_expr/3
  pub def ded_expr(p0 Vec(Unk1001), r Map(Unk1009, Unk1008), _fresh Fn(Unk1005, Unk1003, Unk1004)) Vec(Unk1001) := …

  # Shadow.dedup/3
  pub def dedup(stmts Vec(Unk1007), params Vec(Unk0552), fresh Fn(Unk1005, Unk1003, Unk1004)) Vec(Unk0549) := …

  # Shadow.pat_var_names/1
  pub def pat_var_names(p0 Sum2) Vec(Unk1011) := …

  # ShowStdlib.module/0
  pub def module() Unk0261 := …

  # Test.run/2
  pub def run(src String, p1 Unk1012) Unk1013 := …

  # Tour.build_cell/1
  pub def build_cell(p0 Unk1014) Unk1015 := …

  # Tour.build_reach_example/1
  pub def build_reach_example(p0 Unk1016) Unk1017 := …

  # Tour.elixir_module/1
  pub def elixir_module(src String) Unk1018 := …

  # Tour.encode/2
  pub def encode(map Vec(Unk1019), indent Int53) String := …

  # Tour.encode_string/1
  pub def encode_string(s Vec(Unk1019)) String := …

  # Tour.generate/0
  pub def generate() Unk1020 := …

  # Tour.reach_map/1
  pub def reach_map(prog Map(Unk0022, Vec(Map(Unk0009, Vec(Unk0010))))) Unk1021 := …

  # Transpile.add_clause/2
  pub def add_clause(open Tuple(Unk1022, Vec(Unk1023)), clause Unk1023) Option(Unk1024) := …

  # Transpile.build_clause/2
  pub def build_clause(head Unk1025, kw Unk1026) Unk1023 := …

  # Transpile.case_arm/1
  pub def case_arm(p0 Unk1027) String := …

  # Transpile.classify/1
  pub def classify(p0 String) Tuple(Unk1028, String) := …

  # Transpile.close_group/2
  pub def close_group(acc Vec(Unk1029), p1 Unk1029) Vec(Unk1029) := …

  # Transpile.def_groups/1
  pub def def_groups(stmts Vec(String)) Vec(Unk1029) := …

  # Transpile.escape/1
  pub def escape(s Unk1030) Unk1031 := …

  # Transpile.escape_lit/1
  pub def escape_lit(s Unk1032) String := …

  # Transpile.flush/2
  pub def flush(p0 Unk1033, _sigmap Map(Tuple(Unk1035, Unk1034), Bool)) Vec(String) := …

  # Transpile.hole_sig?/1
  pub def hole_sig?(p0 Unk1036) Bool := …

  # Transpile.infer_program/1
  pub def infer_program(p0 Unk1037) Tuple(Unk1038, Vec(String)) := …

  # Transpile.infer_report/1
  pub def infer_report(source Unk1039) Unk1040 := …

  # Transpile.infer_sigs/2
  pub def infer_sigs(p0 Unk1041, type_env Map(Unk0473, Tuple(Unk0451, String))) Unk1038 := …

  # Transpile.inferred/1
  pub def inferred(source Unk0839) Tuple(Unk1038, Vec(String)) := …

  # Transpile.max_placeholder/1
  pub def max_placeholder(p0 Vec(Unk1042)) Int53 := …

  # Transpile.mod_str/1
  pub def mod_str(p0 Unk1043) String := …

  # Transpile.module_groups/1
  pub def module_groups(src Unk1044) Tuple(String, Unk1045) := …

  # Transpile.moduledoc_lines/1
  pub def moduledoc_lines(text Unk1046) Vec(String) := …

  # Transpile.name_str/1
  pub def name_str(n Unk1047) Unk1048 := …

  # Transpile.new_group/3
  pub def new_group(vis Unk1049, clause Unk1023, doc Option(Unk1050)) Option(Unk1024) := …

  # Transpile.one_line/1
  pub def one_line(s Unk1051) Unk1052 := …

  # Transpile.prime_xmod/1
  pub def prime_xmod(sources Unk1053) Unk1054 := …

  # Transpile.rank/1
  pub def rank(entries Unk1055) Unk1056 := …

  # Transpile.render_body/1
  pub def render_body(p0 Bool) Option(Unk1057) := …

  # Transpile.render_clause/2
  pub def render_clause(kw String, c Unk1058) String := …

  # Transpile.render_items/3
  pub def render_items(stmts Vec(String), sigmap Map(Tuple(Unk1035, Unk1034), Bool), mod_name Unk1059) Vec(String) := …

  # Transpile.render_submodule/3
  pub def render_submodule(name Unk1059, body String, sigmap Map(Tuple(Unk1035, Unk1034), Bool)) Vec(String) := …

  # Transpile.same_group?/3
  pub def same_group?(open Unk1060, vis Unk1061, clause Unk1023) Bool := …

  # Transpile.short_name/1
  pub def short_name(p0 Unk1043) String := …

  # Transpile.sibling_module?/2
  pub def sibling_module?(p0 Unk1062, m String) Bool := …

  # Transpile.simple?/1
  pub def simple?(p0 Vec(Unk1063)) Bool := …

  # Transpile.snippet/1
  pub def snippet(node Unk1043) String := …

  # Transpile.stdlib_map/0
  pub def stdlib_map() Unk0536 := …

  # Transpile.string_part/1
  pub def string_part(s Unk1032) Tuple(Unk1064, String) := …

  # Transpile.string_parts/1
  pub def string_parts(segments Unk1065) Unk1066 := …

  # Transpile.struct_decl/2
  pub def struct_decl(mod_name Unk1059, fields Vec(Unk1067)) String := …

  # Transpile.struct_field?/1
  pub def struct_field?(a Unk1068) Bool := …

  # Transpile.struct_mod_noise?/1
  pub def struct_mod_noise?(p0 Unk1069) Bool := …

  # Transpile.subst_ph/2
  pub def subst_ph(p0 Vec(Unk1070), ps Unk1071) Vec(Unk1070) := …

  # Transpile.toplevel/3
  pub def toplevel(p0 Unk1072, sigmap Unk1073, types Vec(String)) Vec(String) := …

  # Transpile.transpile/2
  pub def transpile(source Unk1074, p1 Unk1075) Unk1076 := …

  # Transpile.transpile_with_stats/2
  pub def transpile_with_stats(source Unk1074, p1 Unk1077) Tuple(Unk1076, Unk1078) := …

  # Transpile.underscore_var/1
  pub def underscore_var(name Unk1079) String := …

  # Transpile.var?/1
  pub def var?(p0 Unk1080) Bool := …

  # Transpile.var_name/1
  pub def var_name(p0 Unk1043) String := …
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
| `Unk0017` | 84 | `Beam.body_forms/3:p0`, `Beam.body_seq/2:p0`, `Beam.cons/3:p2`, `Beam.expr_form/2:p0`, `Beam.guard_core/1:ret`, `Beam.guard_form/2:p0`, `Beam.i64_overflow/4:p1`, `Beam.i64_overflow/4:p2`, `Beam.remote_call/4:p2`, `Beam.with_form/5:p1`, `Check.ann_each/3:p0`, `Check.annotate/3:p0`, `Check.bind_mismatch/5:p2`, `Check.body_literal_adopts?/2:p0`, `Check.call_bound_error/5:p1`, `Check.called_ret_with/4:p2`, `Check.const_int/1:p0`, `Check.infer/3:p0`, `Check.infer_tail/3:p0`, `Check.label_error/1:p0`, `Check.label_error_children/1:p0`, `Check.list_elems/1:p0`, `Check.lit_expr_adopts?/2:p0`, `Check.lit_range_error/3:p0`, `Check.num_mix_error/5:p1`, `Check.num_mix_error/5:p2`, `Check.oor_scan/5:p0`, `Check.scan_bound_calls/4:p0`, `Check.scan_num_mix/3:p0`, `Check.scan_num_mix_children/3:p0`, `Check.walk_children/4:p0`, `Comptime.fold/1:p0`, `Core.from_expr/1:p0`, `Core.from_expr/1:ret`, `Core.from_pairs/1:ret`, `Core.from_stmt/1:ret`, `Core.from_tail/1:ret`, `Exhaustiveness.body_core/1:p0`, `Exhaustiveness.body_core/1:ret`, `Interp.resolve/4:ret`, `Interp.stringify/3:p0`, `JS.clause_return/3:p0`, `JS.guarded_return/4:p0`, `JVM.clause_value/2:p0`, `Lower.case_guard/3:p0`, `Lower.emit/3:p0`, `Lower.emit_ast/2:p0`, `Lower.insert_borrows/4:p0`, `Lower.p/4:p0`, `Lower.pipe_to_call/2:ret`, `Lower.resolve_consts/2:p0`, `Lower.resolve_rust_pats/2:p0`, `Lower.resolve_structs/2:p0`, `Lower.resolve_variants/2:p0`, `Lower.result_payload/3:p0`, `Lower.rust_case/4:p0`, `Lower.rust_case/4:p2`, `Lower.rust_owned_elem/2:p0`, `Lower.struct_pairs/4:p2`, `Lower.variant_pairs/3:p1`, `Lower.widen_char_arith/2:p0`, `Macro.check_portable!/2:p1`, `Macro.do_expand/4:p1`, `Macro.expand/3:p1`, `Macro.expand/3:ret`, `Macro.introduces_failable_bind?/1:p0`, `Macro.map_node/2:p0`, `Macro.map_node/2:p1`, `Macro.substitute/2:p1`, `Macro.substitute/2:ret`, `Macro.walk_for_with/1:p0`, `Pratt.parse/1:ret`, `Pratt.parse_body/1:p0`, `Pratt.parse_body/1:ret`, `Pratt.sexpr/1:p0`, `Prim.normalize/1:ret`, `Range.expand_of/2:p0`, `Range.walk/2:p0`, `Reach.deep/1:p0`, `Reach.find_atom_ordering/1:p0`, `Repl.eval_bind/4:p3`, `Repl.infer_or_unknown/3:p0`, `Repl.safe_infer/3:p0`, `Repl.safe_parse_body/1:ret` |
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
| `Unk0079` | 128 | `Check.abstract_cast_ret/3:p0`, `Check.abstract_cast_ret/3:p2`, `Check.abstract_cast_ret/3:ret`, `Check.abstract_op_type/4:p1`, `Check.abstract_op_type/4:p2`, `Check.abstract_op_type/4:p3`, `Check.adoptable_int?/1:p0`, `Check.ann_each/3:p1`, `Check.ann_each/3:p2`, `Check.ann_each/3:ret`, `Check.ann_stmts/3:p1`, `Check.ann_stmts/3:p2`, `Check.ann_stmts/3:ret`, `Check.annotate/3:p1`, `Check.annotate/3:p2`, `Check.annotate/3:ret`, `Check.arith_type/4:p2`, `Check.arith_type/4:p3`, `Check.assignable?/2:p0`, `Check.assignable?/2:p1`, `Check.bind_mismatch/5:p1`, `Check.bind_mismatch/5:p3`, `Check.bind_mismatch/5:p4`, `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.body_literal_adopts?/2:p1`, `Check.branch_join/1:p0`, `Check.branch_join/1:ret`, `Check.build_fn/2:p1`, `Check.call_bound_error/5:p0`, `Check.call_bound_error/5:p2`, `Check.call_bound_error/5:p3`, `Check.call_bound_error/5:p4`, `Check.called_ret/2:p0`, `Check.called_ret/2:p1`, `Check.called_ret/2:ret`, `Check.called_ret_with/4:p0`, `Check.called_ret_with/4:p1`, `Check.called_ret_with/4:p3`, `Check.called_ret_with/4:ret`, `Check.check_bind_stmts/3:p1`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.clause_env/3:ret`, `Check.concrete_type?/1:p0`, `Check.ctor_type/2:p0`, `Check.ctor_type/2:p1`, `Check.ctor_type/2:ret`, `Check.first_bound_violation/4:p0`, `Check.first_bound_violation/4:p2`, `Check.first_bound_violation/4:p3`, `Check.float_type?/1:p0`, `Check.fn_ret/1:p0`, `Check.fn_ret/1:ret`, `Check.has_tvar?/1:p0`, `Check.infer/3:p1`, `Check.infer/3:p2`, `Check.infer/3:ret`, `Check.infer_block/4:p1`, `Check.infer_block/4:p2`, `Check.infer_block/4:p3`, `Check.infer_block/4:ret`, `Check.infer_tail/3:p1`, `Check.infer_tail/3:p2`, `Check.infer_tail/3:ret`, `Check.instantiate_ret/2:p1`, `Check.instantiate_ret/2:ret`, `Check.int_type?/1:p0`, `Check.join_all/1:ret`, `Check.list_elem/1:p0`, `Check.lit_expr_adopts?/2:p1`, `Check.literal_adopts?/2:p1`, `Check.missing_impl/5:p0`, `Check.missing_impl/5:p2`, `Check.missing_impl/5:p4`, `Check.narrow/4:p1`, `Check.narrow/4:p2`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_base/2:p1`, `Check.range_bind/6:p1`, `Check.range_bind/6:p4`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p0`, `Check.resolve_range/2:p1`, `Check.resolve_range/2:ret`, `Check.scan_bound_calls/4:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_bound_calls/4:p3`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p1`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p1`, `Check.walk_children/4:p2`, `Check.walk_children/4:p3`, `Decl.clause_env/2:ret`, `Interp.int_type?/1:p0`, `Interp.resolve/4:p1`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p1`, `Interp.resolve_part/4:p2`, `Interp.stringify/3:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:p1`, `Repl.bind_env/2:ret`, `Repl.bind_with_type/4:p3`, `Repl.infer_or_unknown/3:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.infer_or_unknown/3:ret`, `Repl.safe_infer/3:p1`, `Repl.safe_infer/3:p2`, `Repl.safe_infer/3:ret`, `Repl.safe_infer_input/3:p1`, `Repl.safe_infer_input/3:p2`, `Repl.safe_infer_input/3:ret`, `Repl.session_ic/1:ret`, `Repl.type_of/2:ret` |
| `Unk0080` | 1 | `Check.abstract_cast_ret/3:p1` |
| `Unk0081` | 38 | `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p3`, `Check.ann_each/3:p2`, `Check.ann_stmts/3:p2`, `Check.annotate/3:p2`, `Check.bind_mismatch/5:p4`, `Check.call_bound_error/5:p3`, `Check.called_ret/2:p0`, `Check.called_ret_with/4:p0`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.ctor_type/2:p0`, `Check.first_bound_violation/4:p3`, `Check.infer/3:p2`, `Check.infer_block/4:p2`, `Check.infer_tail/3:p2`, `Check.narrow/4:p2`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p2`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0082` | 1 | `Check.abstract_op_type/4:p0` |
| `Unk0083` | 1 | `Check.abstract_op_type/4:ret` |
| `Unk0084` | 1 | `Check.all_types/1:p0` |
| `Unk0085` | 28 | `Check.ann_each/3:p1`, `Check.ann_stmts/3:p1`, `Check.annotate/3:p1`, `Check.bind_mismatch/5:p3`, `Check.call_bound_error/5:p2`, `Check.called_ret_with/4:p3`, `Check.check_bind_stmts/3:p1`, `Check.clause_env/3:ret`, `Check.infer/3:p1`, `Check.infer_block/4:p1`, `Check.infer_tail/3:p1`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.range_bind/6:p4`, `Check.scan_bound_calls/4:p1`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix_children/3:p1`, `Check.walk_children/4:p1`, `Decl.clause_env/2:ret`, `Interp.resolve/4:p1`, `Interp.resolve_part/4:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.safe_infer/3:p1`, `Repl.safe_infer_input/3:p1` |
| `Unk0086` | 1 | `Check.ann_stmts/3:p0` |
| `Unk0087` | 1 | `Check.arith_type/4:ret` |
| `Unk0088` | 4 | `Check.bind_mismatch/5:p0`, `Check.lit_range_error/3:p2`, `Check.oor_scan/5:p4`, `Check.range_bind/6:p0` |
| `Unk0089` | 2 | `Check.bind_mismatch/5:ret`, `Check.check_bind_stmts/3:ret` |
| `Unk0090` | 4 | `Check.bind_tvar/4:p0`, `Check.bind_tvar/4:p1`, `Check.inner_of/1:p0`, `Check.inner_of/1:ret` |
| `Unk0091` | 1 | `Check.bind_tvar/4:p2` |
| `Unk0092` | 3 | `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.first_bound_violation/4:p2` |
| `Unk0093` | 1 | `Check.branch_join/1:p0` |
| `Unk0094` | 1 | `Check.build_fn/2:p0` |
| `Unk0095` | 2 | `Check.call_bound_error/5:ret`, `Check.first_bound_violation/4:ret` |
| `Unk0096` | 1 | `Check.call_name/1:p0` |
| `Unk0097` | 2 | `Check.call_name/1:ret`, `Check.with_callees/1:ret` |
| `Unk0098` | 1 | `Check.check/1:ret` |
| `Unk0099` | 1 | `Check.check_bind_stmts/3:p0` |
| `Unk0100` | 1 | `Check.check_binds/2:ret` |
| `Unk0101` | 1 | `Check.check_bounds/2:ret` |
| `Unk0102` | 1 | `Check.check_error_set/2:p0` |
| `Unk0103` | 2 | `Check.check_error_set/2:p1`, `Check.check_func/3:p2` |
| `Unk0104` | 1 | `Check.check_error_set/2:ret` |
| `Unk0105` | 1 | `Check.check_external_caps/1:ret` |
| `Unk0106` | 1 | `Check.check_func/3:p0` |
| `Unk0107` | 1 | `Check.check_func/3:ret` |
| `Unk0108` | 1 | `Check.check_labels/1:ret` |
| `Unk0109` | 1 | `Check.check_numeric_mix/2:ret` |
| `Unk0110` | 1 | `Check.check_program/1:ret` |
| `Unk0111` | 1 | `Check.check_return/2:ret` |
| `Unk0112` | 1 | `Check.clause_env/3:p0` |
| `Unk0113` | 1 | `Check.clause_env/3:p1` |
| `Unk0114` | 1 | `Check.comp_str/1:p0` |
| `Unk0115` | 1 | `Check.const_int/1:ret` |
| `Unk0116` | 1 | `Check.const_int/1:ret` |
| `Unk0117` | 1 | `Check.ctor_types/2:p1` |
| `Unk0118` | 1 | `Check.ctor_types/2:p1` |
| `Unk0119` | 1 | `Check.ctor_types/2:ret` |
| `Unk0120` | 1 | `Check.ctor_types/2:ret` |
| `Unk0121` | 2 | `Check.debottom/1:p0`, `Check.debottom/1:ret` |
| `Unk0122` | 1 | `Check.declared_set/2:p0` |
| `Unk0123` | 4 | `Check.declared_set/2:p1`, `Check.declared_set/2:ret`, `Check.error_sets/1:ret`, `Check.solve_error_sets/2:p1` |
| `Unk0124` | 1 | `Check.declared_set/2:ret` |
| `Unk0125` | 3 | `Check.direct_tags/1:p0`, `Check.produced_set/2:p0`, `Check.propagated_callees/1:p0` |
| `Unk0126` | 1 | `Check.direct_tags/1:ret` |
| `Unk0127` | 1 | `Check.error_tags/1:p0` |
| `Unk0128` | 2 | `Check.error_tags/1:ret`, `Check.tag_name/1:ret` |
| `Unk0129` | 1 | `Check.fbound_table/1:p0` |
| `Unk0130` | 1 | `Check.fbound_table/1:ret` |
| `Unk0131` | 1 | `Check.first_bound_violation/4:p1` |
| `Unk0132` | 1 | `Check.fixpoint/2:p0` |
| `Unk0133` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0134` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0135` | 1 | `Check.fn_parts/1:ret` |
| `Unk0136` | 1 | `Check.fsig/1:p0` |
| `Unk0137` | 1 | `Check.fsig/1:ret` |
| `Unk0138` | 1 | `Check.generic_ret?/2:p0` |
| `Unk0139` | 1 | `Check.generic_ret?/2:p1` |
| `Unk0140` | 1 | `Check.impl_table/1:p0` |
| `Unk0141` | 1 | `Check.impl_table/1:p0` |
| `Unk0142` | 1 | `Check.impl_table/1:ret` |
| `Unk0143` | 1 | `Check.infer_block/4:p0` |
| `Unk0144` | 1 | `Check.instantiate_ret/2:p0` |
| `Unk0145` | 1 | `Check.int_literal?/1:p0` |
| `Unk0146` | 1 | `Check.join/2:ret` |
| `Unk0147` | 1 | `Check.join_all/1:p0` |
| `Unk0148` | 1 | `Check.kind_prefix/1:p0` |
| `Unk0149` | 2 | `Check.label_error/1:ret`, `Check.label_error_children/1:ret` |
| `Unk0150` | 1 | `Check.list_elem/1:ret` |
| `Unk0151` | 1 | `Check.list_elems/1:ret` |
| `Unk0152` | 2 | `Check.lit_range_error/3:ret`, `Check.oor_scan/5:ret` |
| `Unk0153` | 1 | `Check.literal_ordinal/2:ret` |
| `Unk0154` | 1 | `Check.missing_impl/5:p1` |
| `Unk0155` | 1 | `Check.missing_impl/5:p3` |
| `Unk0156` | 1 | `Check.missing_impl/5:ret` |
| `Unk0157` | 1 | `Check.num_bits/2:p0` |
| `Unk0158` | 1 | `Check.num_bits/2:p1` |
| `Unk0159` | 2 | `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0160` | 1 | `Check.num_join/2:p0` |
| `Unk0161` | 1 | `Check.num_join/2:p1` |
| `Unk0162` | 1 | `Check.num_lub/2:ret` |
| `Unk0163` | 1 | `Check.num_mix?/2:p0` |
| `Unk0164` | 1 | `Check.num_mix?/2:p1` |
| `Unk0165` | 1 | `Check.num_mix_error/5:p0` |
| `Unk0166` | 1 | `Check.num_mix_error/5:ret` |
| `Unk0167` | 1 | `Check.num_widens?/2:p0` |
| `Unk0168` | 1 | `Check.num_widens?/2:p1` |
| `Unk0169` | 1 | `Check.oor_scan/5:p2` |
| `Unk0170` | 1 | `Check.oor_scan/5:p3` |
| `Unk0171` | 1 | `Check.opaque_table/1:p0` |
| `Unk0172` | 1 | `Check.opaque_table/1:p0` |
| `Unk0173` | 1 | `Check.opaque_table/1:ret` |
| `Unk0174` | 1 | `Check.pascal?/1:p0` |
| `Unk0175` | 1 | `Check.produced_set/2:p1` |
| `Unk0176` | 1 | `Check.produced_set/2:p1` |
| `Unk0177` | 1 | `Check.produced_set/2:ret` |
| `Unk0178` | 1 | `Check.propagated_callees/1:ret` |
| `Unk0179` | 1 | `Check.range_base/2:ret` |
| `Unk0180` | 1 | `Check.range_bind/6:p2` |
| `Unk0181` | 1 | `Check.range_bind/6:ret` |
| `Unk0182` | 1 | `Check.range_table/1:p0` |
| `Unk0183` | 1 | `Check.range_table/1:p0` |
| `Unk0184` | 1 | `Check.range_table/1:ret` |
| `Unk0185` | 2 | `Check.scan_bound_calls/4:ret`, `Check.walk_children/4:ret` |
| `Unk0186` | 2 | `Check.scan_num_mix/3:ret`, `Check.scan_num_mix_children/3:ret` |
| `Unk0187` | 1 | `Check.solve_error_sets/2:p0` |
| `Unk0188` | 1 | `Check.tag_name/1:p0` |
| `Unk0189` | 1 | `Check.type_table/1:ret` |
| `Unk0190` | 2 | `Check.uint_signed_join/2:p0`, `Check.uint_signed_join/2:p1` |
| `Unk0191` | 1 | `Check.with_callees/1:p0` |
| `Unk0192` | 1 | `Comptime.eval/1:p0` |
| `Unk0193` | 1 | `Comptime.eval/1:ret` |
| `Unk0194` | 24 | `Comptime.fold/1:ret`, `Interp.resolve/4:p0`, `Lower.borrow_arg/5:p0`, `Lower.borrow_value/2:p0`, `Lower.borrow_value/2:ret`, `Lower.insert_borrows/4:ret`, `Lower.owned_arg?/2:p0`, `Lower.owned_field_var?/2:p0`, `Lower.resolve_consts/2:ret`, `Lower.resolve_rust_pats/2:ret`, `Lower.resolve_structs/2:ret`, `Lower.resolve_variants/2:ret`, `Lower.scalar_literal?/1:p0`, `Lower.variant_lit/2:ret`, `Lower.widen_char_arith/2:ret`, `Lower.wrap_char/2:p0`, `Lower.wrap_char/2:ret`, `Macro.do_expand/4:ret`, `Macro.freshen/2:ret`, `Macro.map_node/2:p1`, `Macro.map_node/2:ret`, `Macro.rename/2:ret`, `Macro.substitute/2:p0`, `Macro.walk_for_with/1:ret` |
| `Unk0195` | 1 | `Comptime.int_div/3:p0` |
| `Unk0196` | 1 | `Comptime.int_div/3:p2` |
| `Unk0197` | 1 | `Comptime.int_div/3:p2` |
| `Unk0198` | 1 | `Comptime.int_div/3:p2` |
| `Unk0199` | 1 | `Comptime.int_div/3:ret` |
| `Unk0200` | 1 | `Core.first_unsupported/2:p0` |
| `Unk0201` | 3 | `Core.first_unsupported/2:p1`, `Core.first_unsupported/2:ret`, `Core.reject_unsupported!/4:p1` |
| `Unk0202` | 2 | `Core.first_unsupported/2:p1`, `Core.reject_unsupported!/4:p1` |
| `Unk0203` | 1 | `Core.from_arm/1:p0` |
| `Unk0204` | 1 | `Core.from_arm/1:ret` |
| `Unk0205` | 1 | `Core.from_pairs/1:p0` |
| `Unk0206` | 1 | `Core.from_pairs/1:ret` |
| `Unk0207` | 1 | `Core.from_stmt/1:p0` |
| `Unk0208` | 1 | `Core.from_stmt/1:ret` |
| `Unk0209` | 1 | `Core.from_tail/1:p0` |
| `Unk0210` | 2 | `Core.reject_unsupported!/4:p0`, `JS.function_js/2:p0` |
| `Unk0211` | 8 | `Cst.build/1:p0`, `Cst.open/4:p0`, `Cst.open/4:p2`, `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p0`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0212` | 1 | `Cst.build/1:ret` |
| `Unk0213` | 1 | `Cst.open/4:p1` |
| `Unk0214` | 4 | `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0215` | 2 | `Cst.open/4:ret`, `Cst.seq/2:ret` |
| `Unk0216` | 7 | `Decl.all_impl_decls/1:p0`, `Decl.all_impls/1:p0`, `Decl.all_protocols/1:p0`, `Decl.collect_aliases/1:p0`, `Decl.collect_macros/1:p0`, `Decl.in_scope/2:p0`, `Decl.lower_meta/3:p1` |
| `Unk0217` | 5 | `Decl.all_impl_decls/1:ret`, `Decl.all_protocols/1:ret`, `Decl.in_scope/2:ret`, `Protocol.check_assoc!/2:p0`, `Protocol.check_assoc!/2:p1` |
| `Unk0218` | 1 | `Decl.all_impls/1:ret` |
| `Unk0219` | 2 | `Decl.assemble/3:p0`, `Decl.protocol_defs/4:p0` |
| `Unk0220` | 5 | `Decl.assemble/3:p1`, `Decl.subst_const/2:p1`, `Decl.subst_func/2:p1`, `Decl.subst_struct/2:p1`, `Decl.subst_type/2:p1` |
| `Unk0221` | 1 | `Decl.assemble/3:p2` |
| `Unk0222` | 1 | `Decl.assemble/3:ret` |
| `Unk0223` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0224` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0225` | 1 | `Decl.attach_external/3:p0` |
| `Unk0226` | 1 | `Decl.attach_external/3:p1` |
| `Unk0227` | 1 | `Decl.attach_external/3:p2` |
| `Unk0228` | 1 | `Decl.attach_targets/2:p0` |
| `Unk0229` | 2 | `Decl.attach_targets/2:p1`, `Decl.parse_targets/1:ret` |
| `Unk0230` | 37 | `Decl.balanced_parens/1:p0`, `Decl.balanced_parens/1:ret`, `Decl.decl_boundary?/1:p0`, `Decl.decl_kw?/1:p0`, `Decl.def_raw/4:p2`, `Decl.line_continues?/2:p0`, `Decl.line_continues?/2:p1`, `Decl.skip_nl/1:p0`, `Decl.skip_nl/1:ret`, `Decl.split_decls/1:p0`, `Decl.take_block/3:p0`, `Decl.take_block/3:p2`, `Decl.take_block/3:ret`, `Decl.take_decl/1:p0`, `Decl.take_decl/1:ret`, `Decl.take_def/1:p0`, `Decl.take_def/1:ret`, `Decl.take_head/4:p2`, `Decl.take_head/4:p3`, `Decl.take_head/4:ret`, `Decl.take_line/2:p0`, `Decl.take_line/2:p1`, `Decl.take_line/2:ret`, `Decl.take_line/3:p0`, `Decl.take_line/3:p1`, `Decl.take_line/3:ret`, `Decl.take_mod_body/2:p0`, `Decl.take_mod_body/2:ret`, `Decl.take_parens/3:p0`, `Decl.take_parens/3:p2`, `Decl.take_parens/3:ret`, `Decl.take_type/2:p0`, `Decl.take_type/2:p1`, `Decl.take_type/2:ret`, `Decl.take_until_do/2:p0`, `Decl.take_until_do/2:p1`, `Decl.take_until_do/2:ret` |
| `Unk0231` | 3 | `Decl.block_seps/5:p0`, `Decl.block_seps/5:p4`, `Decl.block_seps/5:ret` |
| `Unk0232` | 1 | `Decl.build_func/1:p0` |
| `Unk0233` | 1 | `Decl.calls_show_float?/1:p0` |
| `Unk0234` | 1 | `Decl.clause/2:p0` |
| `Unk0235` | 1 | `Decl.clause/2:p1` |
| `Unk0236` | 2 | `Decl.clause_env/2:p1`, `Decl.meta_clause/5:p3` |
| `Unk0237` | 1 | `Decl.collapse_parens/1:p0` |
| `Unk0238` | 1 | `Decl.collapse_parens/1:ret` |
| `Unk0239` | 1 | `Decl.collect_aliases/1:ret` |
| `Unk0240` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0241` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0242` | 8 | `Decl.compile/1:ret`, `Decl.compile_beam/1:ret`, `Decl.protocol_unit/3:ret`, `Lower.compile/5:ret`, `Lower.compile_beam/4:ret`, `Lower.compile_elixir/4:ret`, `Lower.compile_module/1:ret`, `Lower.compile_module_beam/1:ret` |
| `Unk0243` | 1 | `Decl.compile_beam/1:ret` |
| `Unk0244` | 2 | `Decl.def_raw/4:p0`, `Decl.take_head/4:p0` |
| `Unk0245` | 2 | `Decl.def_raw/4:p1`, `Decl.take_head/4:p1` |
| `Unk0246` | 2 | `Decl.def_raw/4:p3`, `Decl.detok_block/1:ret` |
| `Unk0247` | 3 | `Decl.def_raw/4:ret`, `Decl.take_def/1:ret`, `Decl.take_head/4:ret` |
| `Unk0248` | 1 | `Decl.detok_block/1:p0` |
| `Unk0249` | 3 | `Decl.extract_parens/1:p0`, `Decl.parse_struct/3:p0`, `Decl.variant/1:p0` |
| `Unk0250` | 1 | `Decl.extract_parens/1:ret` |
| `Unk0251` | 1 | `Decl.field/1:p0` |
| `Unk0252` | 1 | `Decl.fields/1:p0` |
| `Unk0253` | 1 | `Decl.fields/1:ret` |
| `Unk0254` | 1 | `Decl.impl_struct/3:p0` |
| `Unk0255` | 1 | `Decl.impl_struct/3:p1` |
| `Unk0256` | 1 | `Decl.impl_struct/3:p2` |
| `Unk0257` | 1 | `Decl.impl_struct/3:ret` |
| `Unk0258` | 1 | `Decl.in_scope/2:p1` |
| `Unk0259` | 1 | `Decl.in_scope/2:p1` |
| `Unk0260` | 3 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0` |
| `Unk0261` | 4 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0`, `ShowStdlib.module/0:ret` |
| `Unk0262` | 1 | `Decl.lower_meta/3:p0` |
| `Unk0263` | 1 | `Decl.lower_meta/3:p2` |
| `Unk0264` | 1 | `Decl.lower_meta/3:ret` |
| `Unk0265` | 1 | `Decl.macro_param_names/1:p0` |
| `Unk0266` | 1 | `Decl.macro_param_names/1:ret` |
| `Unk0267` | 1 | `Decl.mark_pub/1:p0` |
| `Unk0268` | 1 | `Decl.mark_test/1:p0` |
| `Unk0269` | 1 | `Decl.meta_clause/5:p0` |
| `Unk0270` | 4 | `Decl.meta_clause/5:p4`, `Interp.resolve/4:p3`, `Interp.resolve_part/4:p3`, `Interp.stringify/3:p2` |
| `Unk0271` | 1 | `Decl.meta_clause/5:ret` |
| `Unk0272` | 1 | `Decl.nz/1:ret` |
| `Unk0273` | 1 | `Decl.param/1:p0` |
| `Unk0274` | 1 | `Decl.param/1:ret` |
| `Unk0275` | 7 | `Decl.parse_abstract/4:p0`, `Decl.parse_alias/1:p0`, `Decl.parse_const/3:p0`, `Decl.parse_opaque/3:p0`, `Decl.parse_range/3:p0`, `Decl.parse_type/3:p0`, `Decl.split_once/2:p0` |
| `Unk0276` | 2 | `Decl.parse_abstract/4:p1`, `Decl.parse_abstract_members/1:p0` |
| `Unk0277` | 1 | `Decl.parse_abstract/4:p2` |
| `Unk0278` | 1 | `Decl.parse_abstract/4:p3` |
| `Unk0279` | 1 | `Decl.parse_abstract_members/1:ret` |
| `Unk0280` | 2 | `Decl.parse_alias/1:ret`, `Decl.strip_type_params/1:ret` |
| `Unk0281` | 1 | `Decl.parse_alias/1:ret` |
| `Unk0282` | 1 | `Decl.parse_assoc_binding/1:p0` |
| `Unk0283` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0284` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0285` | 1 | `Decl.parse_binder/1:p0` |
| `Unk0286` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0287` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0288` | 1 | `Decl.parse_binders/1:p0` |
| `Unk0289` | 1 | `Decl.parse_binders/1:ret` |
| `Unk0290` | 1 | `Decl.parse_bounds/1:p0` |
| `Unk0291` | 1 | `Decl.parse_bounds/1:ret` |
| `Unk0292` | 2 | `Decl.parse_cast_rule/1:p0`, `Decl.parse_op_rule/1:p0` |
| `Unk0293` | 1 | `Decl.parse_cast_rule/1:ret` |
| `Unk0294` | 1 | `Decl.parse_const/3:p1` |
| `Unk0295` | 1 | `Decl.parse_const/3:p2` |
| `Unk0296` | 1 | `Decl.parse_external/1:p0` |
| `Unk0297` | 1 | `Decl.parse_external/1:ret` |
| `Unk0298` | 1 | `Decl.parse_external/1:ret` |
| `Unk0299` | 1 | `Decl.parse_head/1:ret` |
| `Unk0300` | 1 | `Decl.parse_op_rule/1:ret` |
| `Unk0301` | 1 | `Decl.parse_opaque/3:p1` |
| `Unk0302` | 1 | `Decl.parse_opaque/3:p2` |
| `Unk0303` | 1 | `Decl.parse_ordinal/1:p0` |
| `Unk0304` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0305` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0306` | 1 | `Decl.parse_params/1:p0` |
| `Unk0307` | 1 | `Decl.parse_params/1:ret` |
| `Unk0308` | 1 | `Decl.parse_range/3:p1` |
| `Unk0309` | 1 | `Decl.parse_range/3:p2` |
| `Unk0310` | 1 | `Decl.parse_struct/3:p1` |
| `Unk0311` | 1 | `Decl.parse_struct/3:p2` |
| `Unk0312` | 1 | `Decl.parse_targets/1:p0` |
| `Unk0313` | 1 | `Decl.parse_type/3:p1` |
| `Unk0314` | 1 | `Decl.parse_type/3:p2` |
| `Unk0315` | 1 | `Decl.parse_use/1:p0` |
| `Unk0316` | 2 | `Decl.proto_method_traits/1:ret`, `Lower.compile/5:p4` |
| `Unk0317` | 2 | `Decl.protocol_defs/4:p1`, `Protocol.expand/5:p2` |
| `Unk0318` | 2 | `Decl.protocol_defs/4:p2`, `Protocol.expand/5:p3` |
| `Unk0319` | 2 | `Decl.protocol_defs/4:p3`, `Protocol.expand/5:p4` |
| `Unk0320` | 3 | `Decl.protocol_defs/4:ret`, `Protocol.expand/5:ret`, `Protocol.impl_methods/2:ret` |
| `Unk0321` | 1 | `Decl.protocol_struct/2:p0` |
| `Unk0322` | 1 | `Decl.protocol_struct/2:p1` |
| `Unk0323` | 1 | `Decl.protocol_struct/2:ret` |
| `Unk0324` | 1 | `Decl.req_ret/1:p0` |
| `Unk0325` | 1 | `Decl.req_ret/1:ret` |
| `Unk0326` | 1 | `Decl.split2/2:p0` |
| `Unk0327` | 1 | `Decl.split2/2:p1` |
| `Unk0328` | 1 | `Decl.split2/2:ret` |
| `Unk0329` | 1 | `Decl.split2/2:ret` |
| `Unk0330` | 1 | `Decl.split_decls/1:ret` |
| `Unk0331` | 1 | `Decl.split_forall/1:p0` |
| `Unk0332` | 1 | `Decl.split_forall/1:ret` |
| `Unk0333` | 1 | `Decl.split_once/2:ret` |
| `Unk0334` | 1 | `Decl.split_once/2:ret` |
| `Unk0335` | 1 | `Decl.split_top/2:p0` |
| `Unk0336` | 1 | `Decl.split_top/2:ret` |
| `Unk0337` | 1 | `Decl.strip_type_params/1:p0` |
| `Unk0338` | 1 | `Decl.subst_const/2:p0` |
| `Unk0339` | 1 | `Decl.subst_fields/2:p0` |
| `Unk0340` | 1 | `Decl.subst_fields/2:p1` |
| `Unk0341` | 1 | `Decl.subst_func/2:p0` |
| `Unk0342` | 1 | `Decl.subst_struct/2:p0` |
| `Unk0343` | 1 | `Decl.subst_type/2:p0` |
| `Unk0344` | 2 | `Decl.subst_type_str/2:p0`, `Decl.subst_type_str/2:ret` |
| `Unk0345` | 1 | `Decl.subst_type_str/2:p1` |
| `Unk0346` | 1 | `Decl.subst_variant/2:p0` |
| `Unk0347` | 1 | `Decl.subst_variant/2:p1` |
| `Unk0348` | 2 | `Decl.take_mod_body/2:p1`, `Decl.take_mod_body/2:ret` |
| `Unk0349` | 1 | `Decl.take_until_do/2:ret` |
| `Unk0350` | 30 | `Doc.concat/1:p0`, `Doc.concat/1:ret`, `Doc.concat/2:p0`, `Doc.concat/2:p1`, `Doc.concat/2:ret`, `Doc.empty/0:ret`, `Doc.group/2:p0`, `Doc.hardline/0:ret`, `Doc.if_break/2:p0`, `Doc.if_break/2:p1`, `Doc.if_break/2:ret`, `Doc.join/2:p0`, `Doc.join/2:p1`, `Doc.join/2:ret`, `Doc.line/0:ret`, `Doc.line_suffix/1:p0`, `Doc.line_suffix/1:ret`, `Doc.must_break?/1:p0`, `Doc.nest/2:p1`, `Doc.nest/2:ret`, `Doc.render/2:p0`, `Doc.softline/0:ret`, `Doc.text/1:ret`, `Format.bd/3:ret`, `Format.chain_body/2:ret`, `Format.chain_doc/1:ret`, `Format.chain_tail/2:ret`, `Format.group_doc/4:ret`, `Format.line_doc/1:ret`, `Format.node_doc/2:ret` |
| `Unk0351` | 2 | `Doc.do_render/5:p2`, `Doc.fits?/2:p1` |
| `Unk0352` | 3 | `Doc.do_render/5:p3`, `Doc.flat_string/1:p0`, `Doc.flush_suffix/2:p0` |
| `Unk0353` | 1 | `Doc.group/2:ret` |
| `Unk0354` | 14 | `Doc.nest/2:p0`, `Format.apply_node/3:p1`, `Format.apply_node/3:p2`, `Format.apply_node/3:ret`, `Format.indent_and_render/4:p1`, `Format.pop/1:p0`, `Format.pop/1:ret`, `Format.push/2:p0`, `Format.push/2:p1`, `Format.push/2:ret`, `Format.render_line/2:p1`, `Format.update_stack/4:p2`, `Format.update_stack/4:p3`, `Format.update_stack/4:ret` |
| `Unk0355` | 2 | `Doctest.augment/2:p1`, `Doctest.extract/1:ret` |
| `Unk0356` | 1 | `Doctest.exunit_cases/2:p1` |
| `Unk0357` | 1 | `Doctest.exunit_cases/2:ret` |
| `Unk0358` | 1 | `Doctest.fences/1:p0` |
| `Unk0359` | 1 | `Doctest.fences/1:ret` |
| `Unk0360` | 1 | `Doctest.module_doc_strings/1:ret` |
| `Unk0361` | 1 | `Doctest.pairs/1:p0` |
| `Unk0362` | 1 | `Doctest.pairs/1:ret` |
| `Unk0363` | 1 | `Doctest.run/2:p1` |
| `Unk0364` | 1 | `Doctest.run/2:ret` |
| `Unk0365` | 1 | `Doctest.run_markdown/1:p0` |
| `Unk0366` | 1 | `Doctest.run_markdown/1:ret` |
| `Unk0367` | 8 | `Exhaustiveness.add_range/4:p0`, `Exhaustiveness.add_range/4:ret`, `Exhaustiveness.add_type/3:p0`, `Exhaustiveness.add_type/3:ret`, `Exhaustiveness.base_env/0:ret`, `Exhaustiveness.program_env/3:ret`, `PatternLower.add_struct/3:p0`, `PatternLower.add_struct/3:ret` |
| `Unk0368` | 1 | `Exhaustiveness.add_range/4:p2` |
| `Unk0369` | 1 | `Exhaustiveness.add_range/4:p3` |
| `Unk0370` | 1 | `Exhaustiveness.add_type/3:p2` |
| `Unk0371` | 2 | `Exhaustiveness.analyze/3:p0`, `PatternLower.lower_clause/2:ret` |
| `Unk0372` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0373` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0374` | 1 | `Exhaustiveness.analyze/3:ret` |
| `Unk0375` | 2 | `Exhaustiveness.arity/2:p1`, `Exhaustiveness.specialize/3:p1` |
| `Unk0376` | 1 | `Exhaustiveness.check_case_bodies!/2:p0` |
| `Unk0377` | 1 | `Exhaustiveness.check_case_bodies!/2:p1` |
| `Unk0378` | 1 | `Exhaustiveness.check_case_bodies!/2:ret` |
| `Unk0379` | 1 | `Exhaustiveness.check_match!/3:p0` |
| `Unk0380` | 2 | `Exhaustiveness.check_match!/3:p2`, `Exhaustiveness.check_one_case!/3:p2` |
| `Unk0381` | 1 | `Exhaustiveness.check_match!/3:ret` |
| `Unk0382` | 1 | `Exhaustiveness.check_one_case!/3:ret` |
| `Unk0383` | 2 | `Exhaustiveness.collect_cases/2:p0`, `Exhaustiveness.collect_children/2:p0` |
| `Unk0384` | 4 | `Exhaustiveness.collect_cases/2:p1`, `Exhaustiveness.collect_cases/2:ret`, `Exhaustiveness.collect_children/2:p1`, `Exhaustiveness.collect_children/2:ret` |
| `Unk0385` | 7 | `Exhaustiveness.default/1:p0`, `Exhaustiveness.default/1:ret`, `Exhaustiveness.head_ctors/1:p0`, `Exhaustiveness.specialize/3:p0`, `Exhaustiveness.specialize/3:ret`, `Exhaustiveness.useful?/3:p0`, `Exhaustiveness.witness/3:p0` |
| `Unk0386` | 3 | `Exhaustiveness.head_ctors/1:ret`, `Exhaustiveness.missing_head/2:p1`, `Exhaustiveness.signature/2:p1` |
| `Unk0387` | 2 | `Exhaustiveness.missing_head/2:ret`, `Exhaustiveness.witness/3:ret` |
| `Unk0388` | 1 | `Exhaustiveness.pascal/1:p0` |
| `Unk0389` | 1 | `Exhaustiveness.program_env/3:p1` |
| `Unk0390` | 1 | `Exhaustiveness.program_env/3:p2` |
| `Unk0391` | 1 | `Exhaustiveness.render/1:p0` |
| `Unk0392` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0393` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0394` | 1 | `Exhaustiveness.useful?/3:p1` |
| `Unk0395` | 1 | `Exhaustiveness.witness/3:ret` |
| `Unk0396` | 1 | `Fixpoint.check/4:p2` |
| `Unk0397` | 1 | `Fixpoint.check/4:p3` |
| `Unk0398` | 1 | `Fixpoint.check/4:ret` |
| `Unk0399` | 46 | `Format.apply_node/3:p0`, `Format.bd/3:p0`, `Format.bd/3:p1`, `Format.blank?/1:p0`, `Format.block_head?/2:p0`, `Format.block_head?/2:p1`, `Format.boundary?/1:p0`, `Format.chain?/1:p0`, `Format.chain_body/2:p0`, `Format.chain_body/2:p1`, `Format.chain_doc/1:p0`, `Format.chain_link?/2:p0`, `Format.chain_link?/2:p1`, `Format.chain_tail/2:p0`, `Format.comment_only?/1:p0`, `Format.declaration_line?/1:p0`, `Format.ends_with_comment?/1:p0`, `Format.head_tok/1:p0`, `Format.indent_and_render/4:p0`, `Format.lead_adjust/1:p0`, `Format.leading_wrap_op?/1:p0`, `Format.line_doc/1:p0`, `Format.mark/1:p0`, `Format.mark/1:ret`, `Format.mark/3:p0`, `Format.mark/3:p1`, `Format.mark/3:p2`, `Format.mark/3:ret`, `Format.merge_chains/1:p0`, `Format.merge_chains/1:ret`, `Format.next_code_line/1:p0`, `Format.next_code_line/1:ret`, `Format.node_doc/2:p0`, `Format.render_line/2:p0`, `Format.split_items/1:ret`, `Format.split_level/1:p0`, `Format.split_node?/2:p0`, `Format.tail_tok/1:p0`, `Format.take_until_level/3:p0`, `Format.take_until_level/3:p2`, `Format.take_until_level/3:ret`, `Format.trailing_op?/1:p0`, `Format.trailing_wrap_op?/1:p0`, `Format.update_stack/4:p0`, `Format.update_stack/4:p1`, `Format.value_end?/1:p0` |
| `Unk0400` | 10 | `Format.boundary_tok?/1:p0`, `Format.closer_lead?/1:p0`, `Format.cont_lead?/1:p0`, `Format.decl_kw?/1:p0`, `Format.head_tok/1:ret`, `Format.space?/2:p0`, `Format.space?/2:p1`, `Format.tail_tok/1:ret`, `Format.value_end_tok?/1:p0`, `Format.wrap_op_tok?/1:p0` |
| `Unk0401` | 4 | `Format.chain_tail/2:p1`, `Format.split_level/1:ret`, `Format.split_node?/2:p1`, `Format.take_until_level/3:p1` |
| `Unk0402` | 7 | `Format.chunk_on_comma/3:p0`, `Format.chunk_on_comma/3:p1`, `Format.chunk_on_comma/3:p2`, `Format.chunk_on_comma/3:ret`, `Format.finish_items/2:p0`, `Format.finish_items/2:p1`, `Format.finish_items/2:ret` |
| `Unk0403` | 6 | `Format.cons_group?/1:p0`, `Format.group_doc/4:p1`, `Format.has_comment?/1:p0`, `Format.magic_comma?/1:p0`, `Format.split_items/1:p0`, `Format.trailing_comma?/1:p0` |
| `Unk0404` | 1 | `Format.format_result/1:ret` |
| `Unk0405` | 1 | `Format.format_result/1:ret` |
| `Unk0406` | 3 | `Format.group_doc/4:p0`, `Format.group_doc/4:p2`, `Format.leaf/1:p0` |
| `Unk0407` | 1 | `Format.has_tok?/2:p0` |
| `Unk0408` | 2 | `Format.has_tok?/2:p0`, `Format.has_tok?/2:p1` |
| `Unk0409` | 6 | `Format.ll/3:p0`, `Format.ll/3:p1`, `Format.ll/3:p2`, `Format.ll/3:ret`, `Format.logical_lines/1:p0`, `Format.logical_lines/1:ret` |
| `Unk0410` | 1 | `Format.squeeze_blanks/1:p0` |
| `Unk0411` | 1 | `Format.squeeze_blanks/1:ret` |
| `Unk0412` | 1 | `Format.wrap_op_node?/1:p0` |
| `Unk0413` | 1 | `Formatting.apply_edits/2:p1` |
| `Unk0414` | 1 | `Formatting.bump_del/3:p0` |
| `Unk0415` | 3 | `Formatting.bump_del/3:p1`, `Formatting.bump_ins/3:p1`, `Formatting.start_hunk/1:p0` |
| `Unk0416` | 1 | `Formatting.bump_del/3:ret` |
| `Unk0417` | 1 | `Formatting.bump_ins/3:p0` |
| `Unk0418` | 1 | `Formatting.bump_ins/3:p2` |
| `Unk0419` | 1 | `Formatting.bump_ins/3:ret` |
| `Unk0420` | 1 | `Formatting.clamp/3:p2` |
| `Unk0421` | 1 | `Formatting.edit/1:p0` |
| `Unk0422` | 1 | `Formatting.edit/1:ret` |
| `Unk0423` | 4 | `Formatting.flush/2:p0`, `Formatting.flush/2:p1`, `Formatting.flush/2:ret`, `Formatting.to_hunks/1:ret` |
| `Unk0424` | 2 | `Formatting.formatting/1:ret`, `Formatting.hunks/2:ret` |
| `Unk0425` | 1 | `Formatting.range_formatting/3:ret` |
| `Unk0426` | 1 | `Formatting.start_hunk/1:ret` |
| `Unk0427` | 1 | `Formatting.to_hunks/1:p0` |
| `Unk0428` | 1 | `FormsEquiv.abstract_code/1:p0` |
| `Unk0429` | 1 | `FormsEquiv.abstract_code/1:ret` |
| `Unk0430` | 3 | `FormsEquiv.alpha_rename/1:p0`, `FormsEquiv.walk_rename/2:p0`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0431` | 1 | `FormsEquiv.alpha_rename/1:ret` |
| `Unk0432` | 3 | `FormsEquiv.bool_clause/1:p0`, `FormsEquiv.bool_clause_pair/1:p0`, `FormsEquiv.bool_clause_pair/1:ret` |
| `Unk0433` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0434` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0435` | 2 | `FormsEquiv.canon_bool_case/1:p0`, `FormsEquiv.canon_bool_case/1:ret` |
| `Unk0436` | 9 | `FormsEquiv.diff/2:p0`, `FormsEquiv.diff/2:p1`, `FormsEquiv.equivalent?/2:p0`, `FormsEquiv.equivalent?/2:p1`, `FormsEquiv.normalize/1:p0`, `FormsEquiv.verified?/2:p0`, `FormsEquiv.verified?/2:p1`, `FormsEquiv.verify/2:p0`, `FormsEquiv.verify/2:p1` |
| `Unk0437` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0438` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0439` | 2 | `FormsEquiv.fold_neg_literal/1:p0`, `FormsEquiv.fold_neg_literal/1:ret` |
| `Unk0440` | 1 | `FormsEquiv.key/1:p0` |
| `Unk0441` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0442` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0443` | 1 | `FormsEquiv.normalize/1:ret` |
| `Unk0444` | 1 | `FormsEquiv.user_function?/1:p0` |
| `Unk0445` | 1 | `FormsEquiv.verify/2:ret` |
| `Unk0446` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0447` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0448` | 2 | `FormsEquiv.zero_anno/1:p0`, `FormsEquiv.zero_anno/1:ret` |
| `Unk0449` | 2 | `History.dedup_consecutive/1:p0`, `History.dedup_consecutive/1:ret` |
| `Unk0450` | 1 | `History.load/0:ret` |
| `Unk0451` | 101 | `Infer.app/2:p1`, `Infer.app/2:ret`, `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p2`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p2`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p2`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p3`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.collect_specs/2:p1`, `Infer.con/1:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.free_vars/2:p1`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p1`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p1`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p1`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p2`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p1`, `Infer.gen_pat/4:p2`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p2`, `Infer.gen_pat_cons/5:p3`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p1`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:p1`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p1`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p2`, `Infer.parse_type/2:ret`, `Infer.render/3:p0`, `Infer.render/3:p2`, `Infer.render_wp/3:p0`, `Infer.render_wp/3:p2`, `Infer.resolve/2:p0`, `Infer.resolve/2:p1`, `Infer.resolve/2:ret`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p4`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p3`, `Infer.sigvar_call/5:p4`, `Infer.spec_pair/2:p1`, `Infer.store_new/0:ret`, `Infer.translate_spec/2:p1`, `Infer.translate_spec/2:ret`, `Infer.translate_type/2:ret`, `Infer.type_pair/2:ret`, `Infer.unify/3:p0`, `Infer.unify/3:p1`, `Infer.unify/3:p2`, `Infer.unify/3:ret`, `Infer.union_spec/3:p2`, `Infer.union_spec/3:ret`, `Infer.unk_vars/2:p0`, `Infer.unk_vars/2:p1`, `Infer.vec_spec/2:p1`, `Infer.vec_spec/2:ret`, `Transpile.infer_sigs/2:p1` |
| `Unk0452` | 55 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.occurs?/3:p0`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0453` | 59 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.apply_spec_terms/4:p3`, `Infer.apply_spec_terms/4:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p1`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p1`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p1`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p1`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.seed_spec/6:p5`, `Infer.seed_spec/6:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0454` | 17 | `Infer.apply_spec_terms/4:p0`, `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/2:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0455` | 2 | `Infer.apply_spec_terms/4:p1`, `Infer.seed_spec/6:p3` |
| `Unk0456` | 1 | `Infer.bind/3:ret` |
| `Unk0457` | 3 | `Infer.bind_checked/3:ret`, `Infer.do_unify/3:ret`, `Infer.unify/3:ret` |
| `Unk0458` | 1 | `Infer.bind_params/3:p0` |
| `Unk0459` | 1 | `Infer.bind_params/3:p1` |
| `Unk0460` | 1 | `Infer.bind_params/3:ret` |
| `Unk0461` | 1 | `Infer.build_ctx/2:p0` |
| `Unk0462` | 1 | `Infer.build_ctx/2:p1` |
| `Unk0463` | 1 | `Infer.build_ctx/2:ret` |
| `Unk0464` | 1 | `Infer.build_ledger/2:p0` |
| `Unk0465` | 1 | `Infer.build_ledger/2:ret` |
| `Unk0466` | 14 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.sigvar_call/5:p0` |
| `Unk0467` | 17 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.collect_specs/2:ret`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.seed_spec/6:p0`, `Infer.seed_spec/6:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0468` | 1 | `Infer.call_sig/6:p1` |
| `Unk0469` | 1 | `Infer.case_arm/1:p0` |
| `Unk0470` | 1 | `Infer.case_arm/1:ret` |
| `Unk0471` | 1 | `Infer.case_arm/1:ret` |
| `Unk0472` | 1 | `Infer.clear_xmod/0:ret` |
| `Unk0473` | 6 | `Infer.collect_specs/2:p1`, `Infer.spec_pair/2:p1`, `Infer.translate_spec/2:p1`, `Infer.union_spec/3:p2`, `Infer.vec_spec/2:p1`, `Transpile.infer_sigs/2:p1` |
| `Unk0474` | 1 | `Infer.collect_types/2:ret` |
| `Unk0475` | 1 | `Infer.collect_types/2:ret` |
| `Unk0476` | 1 | `Infer.free_vars/2:ret` |
| `Unk0477` | 1 | `Infer.fresh_n/2:ret` |
| `Unk0478` | 2 | `Infer.freshen_tvars/2:p0`, `Infer.freshen_tvars/2:ret` |
| `Unk0479` | 1 | `Infer.freshen_tvars/2:ret` |
| `Unk0480` | 3 | `Infer.gen_pat/4:p0`, `Infer.gen_pat_cons/5:p0`, `Infer.gen_pat_cons/5:p1` |
| `Unk0481` | 1 | `Infer.generalize_map/3:p0` |
| `Unk0482` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0483` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0484` | 3 | `Infer.hole_or/2:p0`, `Infer.hole_or/2:p1`, `Infer.hole_or/2:ret` |
| `Unk0485` | 2 | `Infer.hole_sig?/1:p0`, `Infer.infer_group/2:ret` |
| `Unk0486` | 1 | `Infer.infer_group/2:p0` |
| `Unk0487` | 1 | `Infer.instantiate/5:p0` |
| `Unk0488` | 2 | `Infer.load_prelude_sigs/0:ret`, `Infer.prelude_sigs/0:ret` |
| `Unk0489` | 1 | `Infer.mark_num/2:ret` |
| `Unk0490` | 1 | `Infer.max_ph/1:p0` |
| `Unk0491` | 1 | `Infer.maybe_tuple/4:p0` |
| `Unk0492` | 1 | `Infer.mod_name/1:p0` |
| `Unk0493` | 1 | `Infer.ok_payload/3:p0` |
| `Unk0494` | 2 | `Infer.ok_payload/3:p2`, `Infer.result_analysis/3:p2` |
| `Unk0495` | 1 | `Infer.ok_payload/3:ret` |
| `Unk0496` | 1 | `Infer.parse_type/2:p0` |
| `Unk0497` | 1 | `Infer.parse_type/2:p1` |
| `Unk0498` | 2 | `Infer.parse_type/2:p1`, `Infer.tvar?/1:p0` |
| `Unk0499` | 1 | `Infer.pascal/1:p0` |
| `Unk0500` | 1 | `Infer.prime_xmod/2:p0` |
| `Unk0501` | 1 | `Infer.prime_xmod/2:p1` |
| `Unk0502` | 1 | `Infer.prime_xmod/2:ret` |
| `Unk0503` | 1 | `Infer.put_slot/3:p0` |
| `Unk0504` | 1 | `Infer.put_slot/3:ret` |
| `Unk0505` | 1 | `Infer.render_wp/3:p1` |
| `Unk0506` | 1 | `Infer.resolve_program/2:p0` |
| `Unk0507` | 2 | `Infer.resolve_program/2:ret`, `Infer.whole_program/4:ret` |
| `Unk0508` | 1 | `Infer.resolve_struct_params/4:p0` |
| `Unk0509` | 1 | `Infer.resolve_struct_params/4:p1` |
| `Unk0510` | 1 | `Infer.result_analysis/3:p0` |
| `Unk0511` | 1 | `Infer.result_analysis/3:ret` |
| `Unk0512` | 1 | `Infer.result_tag/1:p0` |
| `Unk0513` | 1 | `Infer.result_tag/1:ret` |
| `Unk0514` | 1 | `Infer.result_tag/1:ret` |
| `Unk0515` | 1 | `Infer.sig_of/1:p0` |
| `Unk0516` | 1 | `Infer.sig_of/1:ret` |
| `Unk0517` | 1 | `Infer.sigvar_call/5:p1` |
| `Unk0518` | 1 | `Infer.sigvar_call/5:p2` |
| `Unk0519` | 1 | `Infer.sigvar_call/5:ret` |
| `Unk0520` | 1 | `Infer.slot_sig/3:p2` |
| `Unk0521` | 1 | `Infer.slot_sig/3:ret` |
| `Unk0522` | 1 | `Infer.spec_pair/2:p0` |
| `Unk0523` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0524` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0525` | 1 | `Infer.spec_pair/2:ret` |
| `Unk0526` | 1 | `Infer.spec_str/1:p0` |
| `Unk0527` | 4 | `Infer.translate_spec/2:p0`, `Infer.union_spec/3:p0`, `Infer.union_spec/3:p1`, `Infer.vec_spec/2:p0` |
| `Unk0528` | 1 | `Infer.translate_type/2:p0` |
| `Unk0529` | 1 | `Infer.tvar?/1:ret` |
| `Unk0530` | 1 | `Infer.tvar_name/1:p0` |
| `Unk0531` | 1 | `Infer.tvar_name/1:ret` |
| `Unk0532` | 1 | `Infer.type_pair/2:p0` |
| `Unk0533` | 1 | `Infer.type_pair/2:ret` |
| `Unk0534` | 1 | `Infer.unk_vars/2:ret` |
| `Unk0535` | 3 | `Infer.whole_program/4:p0`, `PortAnalysis.collect_groups/1:ret`, `PortAnalysis.param_name_index/1:p0` |
| `Unk0536` | 2 | `Infer.whole_program/4:p1`, `Transpile.stdlib_map/0:ret` |
| `Unk0537` | 2 | `Infer.whole_program/4:p2`, `PortAnalysis.cluster_sums/1:ret` |
| `Unk0538` | 1 | `Infer.whole_program/4:p3` |
| `Unk0539` | 1 | `Infer.xmod_cache/0:ret` |
| `Unk0540` | 2 | `Interp.concat_chain/1:p0`, `Interp.concat_chain/1:ret` |
| `Unk0541` | 1 | `Interp.resolve_part/4:p0` |
| `Unk0542` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0543` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0544` | 2 | `JS.all_funcs/1:p0`, `JS.all_funcs/1:ret` |
| `Unk0545` | 1 | `JS.all_funcs/1:p0` |
| `Unk0546` | 1 | `JS.arm_return/3:p0` |
| `Unk0547` | 1 | `JS.arm_return/3:p1` |
| `Unk0548` | 1 | `JS.bind_lines/1:p0` |
| `Unk0549` | 4 | `JS.block_return/2:p0`, `JVM.block_value/1:p0`, `Shadow.ded_block/4:ret`, `Shadow.dedup/3:ret` |
| `Unk0550` | 1 | `JS.case_arm_js/2:p0` |
| `Unk0551` | 1 | `JS.clause_js/2:p0` |
| `Unk0552` | 4 | `JS.clause_return/3:p1`, `JS.guarded_return/4:p2`, `JVM.clause_value/2:p1`, `Shadow.dedup/3:p1` |
| `Unk0553` | 1 | `JS.cp_lit/2:p0` |
| `Unk0554` | 1 | `JS.dispatcher_js/5:p0` |
| `Unk0555` | 1 | `JS.dispatcher_js/5:p1` |
| `Unk0556` | 1 | `JS.dispatcher_js/5:p2` |
| `Unk0557` | 1 | `JS.dispatcher_js/5:p3` |
| `Unk0558` | 2 | `JS.float?/1:p0`, `JS.num_js/2:p0` |
| `Unk0559` | 1 | `JS.guarded_return/4:p1` |
| `Unk0560` | 3 | `JS.js_atom/1:p0`, `JS.js_str/1:p0`, `JS.lit_js/2:p0` |
| `Unk0561` | 1 | `JS.js_guard!/4:p1` |
| `Unk0562` | 1 | `JS.js_guard!/4:p2` |
| `Unk0563` | 1 | `JS.js_guard!/4:p3` |
| `Unk0564` | 1 | `JS.js_guard!/4:ret` |
| `Unk0565` | 1 | `JS.js_number_int?/1:p0` |
| `Unk0566` | 1 | `JS.mangle/3:p0` |
| `Unk0567` | 1 | `JS.mangle/3:p1` |
| `Unk0568` | 1 | `JS.mangle/3:p2` |
| `Unk0569` | 1 | `JS.match_elems/3:p0` |
| `Unk0570` | 1 | `JS.match_elems/3:ret` |
| `Unk0571` | 1 | `JS.paren/2:p0` |
| `Unk0572` | 1 | `JS.paren/2:p1` |
| `Unk0573` | 1 | `JS.pascal?/1:p0` |
| `Unk0574` | 1 | `JS.pat_match/3:ret` |
| `Unk0575` | 1 | `JS.reject_mixed_int_mode!/1:ret` |
| `Unk0576` | 1 | `JS.reject_wide_int!/2:p0` |
| `Unk0577` | 1 | `JS.reject_wide_int!/2:p1` |
| `Unk0578` | 1 | `JS.reject_wide_int!/2:ret` |
| `Unk0579` | 1 | `JS.stmt_js/2:p0` |
| `Unk0580` | 1 | `JS.stmt_return/2:p0` |
| `Unk0581` | 1 | `JS.stmt_return/2:p1` |
| `Unk0582` | 1 | `JS.struct_name_set/1:ret` |
| `Unk0583` | 1 | `JS.sum_ctor_map/1:ret` |
| `Unk0584` | 1 | `JS.sum_guard_js/1:p0` |
| `Unk0585` | 2 | `JVM.all_funcs/1:p0`, `JVM.all_funcs/1:ret` |
| `Unk0586` | 1 | `JVM.all_funcs/1:p0` |
| `Unk0587` | 1 | `JVM.bind_str/1:p0` |
| `Unk0588` | 1 | `JVM.case_arms/2:p0` |
| `Unk0589` | 1 | `JVM.case_arms/2:ret` |
| `Unk0590` | 1 | `JVM.case_arms/2:ret` |
| `Unk0591` | 4 | `JVM.clause_lines/1:p0`, `JVM.closed_or_cond/3:p2`, `JVM.prepend_if/3:p2`, `JVM.run_or_cond/3:p2` |
| `Unk0592` | 1 | `JVM.clause_match/1:p0` |
| `Unk0593` | 1 | `JVM.clause_match/1:ret` |
| `Unk0594` | 3 | `JVM.closed_or_cond/3:p0`, `JVM.prepend_if/3:p0`, `JVM.run_or_cond/3:p0` |
| `Unk0595` | 1 | `JVM.function_kt/1:p0` |
| `Unk0596` | 1 | `JVM.guarded_arm/2:p1` |
| `Unk0597` | 1 | `JVM.guarded_return/3:p0` |
| `Unk0598` | 1 | `JVM.guarded_return/3:p1` |
| `Unk0599` | 1 | `JVM.guarded_return/3:p2` |
| `Unk0600` | 1 | `JVM.kotlin_module/2:p1` |
| `Unk0601` | 2 | `JVM.kt_str/1:p0`, `JVM.lit_kt/1:p0` |
| `Unk0602` | 1 | `JVM.kt_type/1:ret` |
| `Unk0603` | 1 | `JVM.pat_match/2:ret` |
| `Unk0604` | 1 | `JVM.stmt_kt/1:p0` |
| `Unk0605` | 1 | `JVM.stmt_value/1:p0` |
| `Unk0606` | 1 | `JVM.sum_decl/1:p0` |
| `Unk0607` | 1 | `JVM.to_jar/3:p2` |
| `Unk0608` | 1 | `JVM.to_jar/3:ret` |
| `Unk0609` | 1 | `JVM.variant_decl/2:p0` |
| `Unk0610` | 1 | `JVM.variant_decl/2:p1` |
| `Unk0611` | 4 | `Lexer.binify/1:ret`, `Lexer.capture_hole/3:ret`, `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0612` | 1 | `Lexer.capture_hole/3:ret` |
| `Unk0613` | 1 | `Lexer.char_escape/1:p0` |
| `Unk0614` | 2 | `Lexer.char_escape/1:ret`, `Lexer.parse_hex!/1:p0` |
| `Unk0615` | 2 | `Lexer.close_char/1:ret`, `Lexer.lex_char/1:ret` |
| `Unk0616` | 1 | `Lexer.collapse_nl/1:p0` |
| `Unk0617` | 1 | `Lexer.collapse_nl/1:ret` |
| `Unk0618` | 1 | `Lexer.detokenize/2:p0` |
| `Unk0619` | 1 | `Lexer.escape_str/1:p0` |
| `Unk0620` | 75 | `Lexer.expr_tokens/1:ret`, `Pratt.climb/3:p1`, `Pratt.climb/3:ret`, `Pratt.collect_dots/2:p1`, `Pratt.collect_dots/2:ret`, `Pratt.expect_kw/2:p0`, `Pratt.expect_kw/2:ret`, `Pratt.expect_op/2:p0`, `Pratt.expect_op/2:ret`, `Pratt.expect_rbracket/1:p0`, `Pratt.expect_rbracket/1:ret`, `Pratt.expect_rparen/1:p0`, `Pratt.expect_rparen/1:ret`, `Pratt.finish_arg/2:p1`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:p0`, `Pratt.parse_args/1:ret`, `Pratt.parse_arms/2:p0`, `Pratt.parse_arms/2:ret`, `Pratt.parse_block/1:p0`, `Pratt.parse_block/1:ret`, `Pratt.parse_capture/1:p0`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:p0`, `Pratt.parse_case/1:ret`, `Pratt.parse_expr/2:p0`, `Pratt.parse_expr/2:ret`, `Pratt.parse_if/1:p0`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:p0`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:p0`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p0`, `Pratt.parse_map/2:ret`, `Pratt.parse_param/1:p0`, `Pratt.parse_param/1:ret`, `Pratt.parse_params/1:p0`, `Pratt.parse_params/1:ret`, `Pratt.parse_pat/1:p0`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_args/2:p0`, `Pratt.parse_pat_args/2:ret`, `Pratt.parse_pat_fields/2:p0`, `Pratt.parse_pat_fields/2:ret`, `Pratt.parse_pat_list/2:p0`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p0`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p0`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_path/1:p0`, `Pratt.parse_path/1:ret`, `Pratt.parse_pats/2:p0`, `Pratt.parse_postfix/2:p1`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:p0`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:p0`, `Pratt.parse_primary/1:ret`, `Pratt.parse_stmt/1:p0`, `Pratt.parse_stmt/1:ret`, `Pratt.parse_stmts/2:p0`, `Pratt.parse_stmts/2:ret`, `Pratt.parse_tuple/2:p0`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_type/1:p0`, `Pratt.parse_type/1:ret`, `Pratt.parse_type_args/2:p0`, `Pratt.parse_type_args/2:ret`, `Pratt.parse_with/1:p0`, `Pratt.parse_with/1:ret`, `Pratt.parse_with_clauses/2:p0`, `Pratt.parse_with_clauses/2:ret`, `Pratt.peek_infix/1:p0` |
| `Unk0621` | 2 | `Lexer.lex/2:p1`, `Lexer.word/1:ret` |
| `Unk0622` | 2 | `Lexer.lex/2:ret`, `Lexer.tokenize_trivia/1:ret` |
| `Unk0623` | 1 | `Lexer.lex_char/1:ret` |
| `Unk0624` | 2 | `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0625` | 1 | `Lexer.lex_parts/3:ret` |
| `Unk0626` | 1 | `Lexer.lex_string_token/1:ret` |
| `Unk0627` | 2 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:ret` |
| `Unk0628` | 3 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:p0`, `Lexer.string_token/1:ret` |
| `Unk0629` | 1 | `Lexer.punct/1:ret` |
| `Unk0630` | 1 | `Lexer.strip_trivia/1:p0` |
| `Unk0631` | 1 | `Lexer.strip_trivia/1:ret` |
| `Unk0632` | 1 | `Lexer.take_comment/1:ret` |
| `Unk0633` | 4 | `Lexer.take_hex/2:p0`, `Lexer.take_hex/2:ret`, `Lexer.take_hex/3:p0`, `Lexer.take_hex/3:ret` |
| `Unk0634` | 1 | `Lexer.tok_str/2:p0` |
| `Unk0635` | 1 | `Lexer.tokenize/1:ret` |
| `Unk0636` | 2 | `Livebook.eval/1:ret`, `Livebook.output/1:ret` |
| `Unk0637` | 2 | `Livebook.run/2:p0`, `Livebook.run/2:ret` |
| `Unk0638` | 1 | `Livebook.run/2:ret` |
| `Unk0639` | 1 | `Livebook.session_pid/0:ret` |
| `Unk0640` | 4 | `Lower.add_list_elem_vars/2:p0`, `Lower.add_list_elem_vars/2:ret`, `Lower.add_var/2:p0`, `Lower.add_var/2:ret` |
| `Unk0641` | 1 | `Lower.add_list_elem_vars/2:p1` |
| `Unk0642` | 1 | `Lower.add_var/2:p1` |
| `Unk0643` | 1 | `Lower.all_pat_vars/1:ret` |
| `Unk0644` | 1 | `Lower.arm_rebinds/3:p0` |
| `Unk0645` | 3 | `Lower.arm_rebinds/3:p1`, `Lower.iso_cons_positions/1:ret`, `Lower.rust_scrut/2:p1` |
| `Unk0646` | 4 | `Lower.arm_rebinds/3:p2`, `Lower.collect_ids/2:p1`, `Lower.collect_ids/2:ret`, `Lower.used_ids/1:ret` |
| `Unk0647` | 1 | `Lower.arm_rebinds/3:ret` |
| `Unk0648` | 1 | `Lower.assoc/1:ret` |
| `Unk0649` | 1 | `Lower.body_ast/2:p0` |
| `Unk0650` | 1 | `Lower.body_ast/2:p1` |
| `Unk0651` | 1 | `Lower.body_ast/2:ret` |
| `Unk0652` | 5 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p0`, `Lower.param_rtypes/2:p1` |
| `Unk0653` | 4 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p1` |
| `Unk0654` | 3 | `Lower.borrow_arg/5:p3`, `Lower.borrow_value/2:p1`, `Lower.insert_borrows/4:p3` |
| `Unk0655` | 3 | `Lower.borrow_arg/5:p4`, `Lower.insert_borrows/4:p2`, `Lower.owned_field_var?/2:p1` |
| `Unk0656` | 1 | `Lower.borrow_arg/5:ret` |
| `Unk0657` | 1 | `Lower.borrowed_in_pat/2:ret` |
| `Unk0658` | 1 | `Lower.borrowed_vars/2:p0` |
| `Unk0659` | 1 | `Lower.borrowed_vars/2:p1` |
| `Unk0660` | 1 | `Lower.borrowed_vars/2:ret` |
| `Unk0661` | 1 | `Lower.build_env/3:p1` |
| `Unk0662` | 1 | `Lower.build_env/3:p2` |
| `Unk0663` | 2 | `Lower.build_env/3:ret`, `Lower.check!/2:p1` |
| `Unk0664` | 3 | `Lower.build_meta/1:ret`, `Lower.ctx/4:p0`, `Lower.to_rust/6:p2` |
| `Unk0665` | 4 | `Lower.build_struct_meta/1:ret`, `Lower.ctx/4:p1`, `Lower.to_elixir/4:p3`, `Lower.to_rust/6:p4` |
| `Unk0666` | 9 | `Lower.case_guard/3:p1`, `Lower.disp/2:p1`, `Lower.emit/3:p1`, `Lower.emit_ast/2:p1`, `Lower.emit_block/3:p1`, `Lower.emit_expr/2:p1`, `Lower.guard_kw/1:p0`, `Lower.guard_str/4:p1`, `Lower.p/4:p2` |
| `Unk0667` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0668` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0669` | 1 | `Lower.char_vars/2:p0` |
| `Unk0670` | 1 | `Lower.char_vars/2:p1` |
| `Unk0671` | 1 | `Lower.char_vars/2:ret` |
| `Unk0672` | 14 | `Lower.check!/2:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_used?/2:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_rust/6:p0` |
| `Unk0673` | 1 | `Lower.check!/2:ret` |
| `Unk0674` | 2 | `Lower.collect_ids/2:p0`, `Lower.used_ids/1:p0` |
| `Unk0675` | 1 | `Lower.collect_owned_field_vars/3:p0` |
| `Unk0676` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0677` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0678` | 6 | `Lower.collect_owned_field_vars/3:p2`, `Lower.collect_owned_field_vars/3:ret`, `Lower.ofb/3:p2`, `Lower.ofb/3:ret`, `Lower.owned_field_binders/2:ret`, `Lower.slice_binders/2:ret` |
| `Unk0679` | 1 | `Lower.compile/5:p2` |
| `Unk0680` | 1 | `Lower.compile/5:p3` |
| `Unk0681` | 1 | `Lower.compile_beam/4:p2` |
| `Unk0682` | 1 | `Lower.compile_beam/4:p3` |
| `Unk0683` | 1 | `Lower.compile_elixir/4:p2` |
| `Unk0684` | 1 | `Lower.compile_elixir/4:p3` |
| `Unk0685` | 1 | `Lower.compile_module/1:p0` |
| `Unk0686` | 1 | `Lower.compile_module_beam/1:p0` |
| `Unk0687` | 1 | `Lower.cons_tail_names/1:ret` |
| `Unk0688` | 3 | `Lower.const_set/1:p0`, `Lower.ex_const/2:p0`, `Lower.rust_const/2:p0` |
| `Unk0689` | 2 | `Lower.const_set/1:ret`, `Lower.ctx/4:p2` |
| `Unk0690` | 3 | `Lower.core_pat_rs/2:p1`, `Lower.pat_rs/2:p1`, `Lower.resolve_rust_pats/2:p1` |
| `Unk0691` | 1 | `Lower.core_pat_vars/1:ret` |
| `Unk0692` | 1 | `Lower.ctx/4:p3` |
| `Unk0693` | 2 | `Lower.deref_ids/2:p0`, `Lower.deref_ids/2:ret` |
| `Unk0694` | 1 | `Lower.deref_ids/2:p1` |
| `Unk0695` | 2 | `Lower.elixir_clauses/3:p1`, `Lower.ex_const/2:p1` |
| `Unk0696` | 1 | `Lower.emit_ast/2:ret` |
| `Unk0697` | 1 | `Lower.emit_ctx/1:p0` |
| `Unk0698` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0699` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0700` | 1 | `Lower.emit_expr/2:ret` |
| `Unk0701` | 2 | `Lower.enum_generics/2:p0`, `Lower.enum_generics/2:p1` |
| `Unk0702` | 1 | `Lower.enum_generics/2:p1` |
| `Unk0703` | 1 | `Lower.ex_struct/1:p0` |
| `Unk0704` | 1 | `Lower.ex_typespec/1:p0` |
| `Unk0705` | 1 | `Lower.ex_use/1:p0` |
| `Unk0706` | 2 | `Lower.fn_all_tvars/3:p1`, `Lower.pair_inst/2:ret` |
| `Unk0707` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0708` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0709` | 1 | `Lower.guard_str/4:p0` |
| `Unk0710` | 1 | `Lower.guard_str/4:p3` |
| `Unk0711` | 1 | `Lower.impl_param/2:p0` |
| `Unk0712` | 1 | `Lower.infer_concrete_params/3:p1` |
| `Unk0713` | 1 | `Lower.infer_tvar_binding/2:p0` |
| `Unk0714` | 1 | `Lower.infer_tvar_binding/2:p1` |
| `Unk0715` | 1 | `Lower.infer_tvar_binding/2:ret` |
| `Unk0716` | 1 | `Lower.list_rpat?/1:p0` |
| `Unk0717` | 1 | `Lower.member_scan/3:p0` |
| `Unk0718` | 3 | `Lower.member_scan/3:p1`, `Lower.strip_prefix/2:p1`, `Lower.word_scan/4:p1` |
| `Unk0719` | 1 | `Lower.module_elixir/1:p0` |
| `Unk0720` | 1 | `Lower.module_rust/1:p0` |
| `Unk0721` | 2 | `Lower.ofb/3:p0`, `Lower.owned_field_binders/2:p0` |
| `Unk0722` | 1 | `Lower.owned_scrut?/2:p0` |
| `Unk0723` | 1 | `Lower.owned_str_arg/1:p0` |
| `Unk0724` | 1 | `Lower.owned_str_arg/1:ret` |
| `Unk0725` | 2 | `Lower.parametric_param_map/1:ret`, `Lower.rust_enum/3:p2` |
| `Unk0726` | 2 | `Lower.parametric_used?/2:p1`, `Lower.word_member?/2:p1` |
| `Unk0727` | 2 | `Lower.pascal?/1:p0`, `Lower.variant_info/2:p1` |
| `Unk0728` | 1 | `Lower.pipe_to_call/2:p0` |
| `Unk0729` | 1 | `Lower.proto_method_traits/1:ret` |
| `Unk0730` | 1 | `Lower.pub_sig_type_names/1:p0` |
| `Unk0731` | 1 | `Lower.pub_sig_type_names/1:ret` |
| `Unk0732` | 1 | `Lower.ref_type/2:p1` |
| `Unk0733` | 1 | `Lower.resolve_consts/2:p1` |
| `Unk0734` | 2 | `Lower.resolve_structs/2:p1`, `Lower.struct_pairs/4:p3` |
| `Unk0735` | 6 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_info/2:ret`, `Lower.variant_lit/2:p0`, `Lower.variant_pairs/3:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0736` | 3 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0737` | 1 | `Lower.result_parts/1:ret` |
| `Unk0738` | 2 | `Lower.rewrite_proto_calls/2:p0`, `Lower.rewrite_proto_calls/2:ret` |
| `Unk0739` | 1 | `Lower.rewrite_proto_calls/2:p1` |
| `Unk0740` | 1 | `Lower.rust_case/4:p1` |
| `Unk0741` | 1 | `Lower.rust_generics/1:p0` |
| `Unk0742` | 1 | `Lower.rust_impl_method/6:p0` |
| `Unk0743` | 1 | `Lower.rust_impl_method/6:p1` |
| `Unk0744` | 1 | `Lower.rust_lit_type/1:p0` |
| `Unk0745` | 1 | `Lower.rust_proto_body/3:p0` |
| `Unk0746` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0747` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0748` | 1 | `Lower.rust_proto_body/3:p2` |
| `Unk0749` | 1 | `Lower.rust_proto_body/3:ret` |
| `Unk0750` | 1 | `Lower.rust_protocols/4:ret` |
| `Unk0751` | 1 | `Lower.rust_scrut/2:p0` |
| `Unk0752` | 1 | `Lower.rust_struct/2:p0` |
| `Unk0753` | 1 | `Lower.rust_struct/2:p1` |
| `Unk0754` | 1 | `Lower.rust_trait/1:p0` |
| `Unk0755` | 1 | `Lower.rust_use/1:p0` |
| `Unk0756` | 1 | `Lower.rustify_parametric/2:p1` |
| `Unk0757` | 2 | `Lower.sig_param/2:p1`, `Lower.trait_params/2:p1` |
| `Unk0758` | 1 | `Lower.slice_binders/2:p0` |
| `Unk0759` | 1 | `Lower.slice_elem_vars/1:ret` |
| `Unk0760` | 1 | `Lower.str_lit/1:p0` |
| `Unk0761` | 2 | `Lower.strip_prefix/2:p0`, `Lower.strip_prefix/2:ret` |
| `Unk0762` | 1 | `Lower.strip_prefix/2:ret` |
| `Unk0763` | 1 | `Lower.struct_pairs/4:p0` |
| `Unk0764` | 1 | `Lower.struct_pairs/4:p1` |
| `Unk0765` | 1 | `Lower.struct_pairs/4:ret` |
| `Unk0766` | 1 | `Lower.subst_assoc/2:p1` |
| `Unk0767` | 2 | `Lower.tail_expr/1:p0`, `Lower.tail_expr/1:ret` |
| `Unk0768` | 1 | `Lower.to_elixir/4:p2` |
| `Unk0769` | 1 | `Lower.to_elixir/4:ret` |
| `Unk0770` | 1 | `Lower.to_rust/6:p3` |
| `Unk0771` | 1 | `Lower.to_rust/6:p5` |
| `Unk0772` | 1 | `Lower.to_rust/6:ret` |
| `Unk0773` | 1 | `Lower.tvar_name?/1:p0` |
| `Unk0774` | 1 | `Lower.type_idents/1:p0` |
| `Unk0775` | 1 | `Lower.type_idents/1:ret` |
| `Unk0776` | 1 | `Lower.type_param_tvars/1:p0` |
| `Unk0777` | 1 | `Lower.type_param_tvars/1:ret` |
| `Unk0778` | 1 | `Lower.user_type?/2:p0` |
| `Unk0779` | 2 | `Lower.variant_lit/2:p1`, `Lower.variant_pairs/3:ret` |
| `Unk0780` | 2 | `Lower.widen_char_arith/2:p1`, `Lower.wrap_char/2:p1` |
| `Unk0781` | 1 | `Lower.with_chain_rs/4:p0` |
| `Unk0782` | 1 | `Lower.word_member?/2:p0` |
| `Unk0783` | 1 | `Lower.word_scan/4:p0` |
| `Unk0784` | 4 | `Macro.binders_here/1:p0`, `Macro.collect_binders/1:p0`, `Macro.freshen/2:p0`, `Macro.rename/2:p0` |
| `Unk0785` | 2 | `Macro.binders_here/1:ret`, `Macro.collect_binders/1:ret` |
| `Unk0786` | 1 | `Macro.build_env/1:p0` |
| `Unk0787` | 1 | `Macro.check_portable!/2:p0` |
| `Unk0788` | 1 | `Macro.check_portable!/2:ret` |
| `Unk0789` | 1 | `Macro.expand/3:p2` |
| `Unk0790` | 1 | `Macro.freshen/2:p1` |
| `Unk0791` | 4 | `Macro.freshen/2:ret`, `Macro.rename/2:p1`, `Macro.rename/2:ret`, `Macro.substitute/2:p0` |
| `Unk0792` | 1 | `Macro.rename/2:p1` |
| `Unk0793` | 1 | `Macro.substitute/2:p1` |
| `Unk0794` | 1 | `Opaque.do_erase/2:p0` |
| `Unk0795` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0796` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0797` | 1 | `Opaque.erase_clause/3:p0` |
| `Unk0798` | 1 | `Opaque.erase_clause/3:p1` |
| `Unk0799` | 1 | `Opaque.erase_clause/3:p2` |
| `Unk0800` | 1 | `Opaque.erase_const/2:p0` |
| `Unk0801` | 1 | `Opaque.erase_const/2:p1` |
| `Unk0802` | 3 | `Opaque.erase_ctx/1:p0`, `Opaque.opaques/1:p0`, `Opaque.opaques/1:ret` |
| `Unk0803` | 1 | `Opaque.erase_func/2:p0` |
| `Unk0804` | 1 | `Opaque.erase_mod/2:p0` |
| `Unk0805` | 1 | `Opaque.erase_struct/2:p0` |
| `Unk0806` | 1 | `Opaque.erase_type/2:p0` |
| `Unk0807` | 1 | `Opaque.erase_variant/2:p0` |
| `Unk0808` | 1 | `Opaque.erase_variant/2:p1` |
| `Unk0809` | 1 | `Opaque.opaques/1:p0` |
| `Unk0810` | 4 | `Opaque.strip/3:p0`, `Opaque.strip/3:ret`, `Opaque.strip_into/3:p0`, `Opaque.strip_into/3:ret` |
| `Unk0811` | 2 | `Opaque.strip/3:p1`, `Opaque.strip_into/3:p1` |
| `Unk0812` | 4 | `Opaque.subst/2:p0`, `Opaque.subst/2:ret`, `Opaque.subst_fix/4:p0`, `Opaque.subst_fix/4:ret` |
| `Unk0813` | 2 | `Opaque.subst/2:p1`, `Opaque.subst_fix/4:p1` |
| `Unk0814` | 1 | `Opaque.subst_fix/4:p2` |
| `Unk0815` | 2 | `PatternLower.lower/2:ret`, `PatternLower.lower_list/3:ret` |
| `Unk0816` | 1 | `PatternLower.lower_clause/2:p0` |
| `Unk0817` | 1 | `PatternLower.lower_many/2:ret` |
| `Unk0818` | 2 | `PortAnalysis.analyze/1:p0`, `PortAnalysis.src_of/2:p0` |
| `Unk0819` | 1 | `PortAnalysis.analyze/1:ret` |
| `Unk0820` | 3 | `PortAnalysis.case_arm_sets/1:p0`, `PortAnalysis.clause_head_sets/1:p0`, `PortAnalysis.dispatch_sets/1:p0` |
| `Unk0821` | 2 | `PortAnalysis.case_arm_sets/1:ret`, `PortAnalysis.clause_head_sets/1:ret` |
| `Unk0822` | 2 | `PortAnalysis.cluster_sums/1:p0`, `PortAnalysis.dispatch_sets/1:ret` |
| `Unk0823` | 1 | `PortAnalysis.collect_errors/2:p0` |
| `Unk0824` | 2 | `PortAnalysis.collect_errors/2:p1`, `PortAnalysis.collect_errors/2:ret` |
| `Unk0825` | 1 | `PortAnalysis.collect_groups/1:p0` |
| `Unk0826` | 1 | `PortAnalysis.collect_structs/2:p0` |
| `Unk0827` | 2 | `PortAnalysis.collect_structs/2:p1`, `PortAnalysis.collect_structs/2:ret` |
| `Unk0828` | 1 | `PortAnalysis.error_proposal/1:p0` |
| `Unk0829` | 1 | `PortAnalysis.error_proposal/1:ret` |
| `Unk0830` | 1 | `PortAnalysis.error_shape/1:p0` |
| `Unk0831` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0832` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0833` | 6 | `PortAnalysis.errors_section/1:p0`, `PortAnalysis.holes_section/1:p0`, `PortAnalysis.sigs_section/1:p0`, `PortAnalysis.summary_section/1:p0`, `PortAnalysis.sums_section/1:p0`, `PortAnalysis.to_markdown/1:p0` |
| `Unk0834` | 1 | `PortAnalysis.head_name_pats/1:p0` |
| `Unk0835` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0836` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0837` | 2 | `PortAnalysis.module_name/1:p0`, `PortAnalysis.module_report/3:p1` |
| `Unk0838` | 1 | `PortAnalysis.module_report/3:p0` |
| `Unk0839` | 3 | `PortAnalysis.module_report/3:p2`, `PortAnalysis.src_of/2:ret`, `Transpile.inferred/1:p0` |
| `Unk0840` | 1 | `PortAnalysis.module_report/3:ret` |
| `Unk0841` | 1 | `PortAnalysis.module_stmts/1:p0` |
| `Unk0842` | 1 | `PortAnalysis.needs_review?/1:p0` |
| `Unk0843` | 1 | `PortAnalysis.param_name_index/1:ret` |
| `Unk0844` | 1 | `PortAnalysis.parse/1:p0` |
| `Unk0845` | 1 | `PortAnalysis.parse/1:ret` |
| `Unk0846` | 1 | `PortAnalysis.pascal/1:p0` |
| `Unk0847` | 1 | `PortAnalysis.pascal/1:ret` |
| `Unk0848` | 1 | `PortAnalysis.pattern_structs/1:p0` |
| `Unk0849` | 1 | `PortAnalysis.pattern_structs/1:ret` |
| `Unk0850` | 1 | `PortAnalysis.reach_note/1:ret` |
| `Unk0851` | 1 | `PortAnalysis.short/1:p0` |
| `Unk0852` | 1 | `PortAnalysis.src_of/2:p1` |
| `Unk0853` | 1 | `PortAnalysis.to_markdown/1:ret` |
| `Unk0854` | 3 | `Pratt.after_paren/2:p0`, `Pratt.after_paren/2:ret`, `Pratt.lambda_ahead?/1:p0` |
| `Unk0855` | 5 | `Pratt.assoc/1:p0`, `Pratt.bp/1:p0`, `Pratt.level/1:p0`, `Pratt.peek_infix/1:ret`, `Pratt.same_level_root?/2:p1` |
| `Unk0856` | 1 | `Pratt.assoc/1:ret` |
| `Unk0857` | 4 | `Pratt.climb/3:p0`, `Pratt.climb/3:ret`, `Pratt.parse_expr/2:ret`, `Pratt.same_level_root?/2:p0` |
| `Unk0858` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0859` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0860` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0861` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0862` | 3 | `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0863` | 3 | `Pratt.finish_arg/2:p0`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:ret` |
| `Unk0864` | 2 | `Pratt.here/1:p0`, `Pratt.tok_desc/1:p0` |
| `Unk0865` | 1 | `Pratt.int_of/1:p0` |
| `Unk0866` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0867` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0868` | 1 | `Pratt.level/1:ret` |
| `Unk0869` | 1 | `Pratt.opinfo/1:ret` |
| `Unk0870` | 2 | `Pratt.parse_arms/2:p1`, `Pratt.parse_arms/2:ret` |
| `Unk0871` | 13 | `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0872` | 1 | `Pratt.parse_list/2:p1` |
| `Unk0873` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0874` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0875` | 1 | `Pratt.parse_params/1:ret` |
| `Unk0876` | 4 | `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:ret` |
| `Unk0877` | 2 | `Pratt.parse_pat_args/2:p1`, `Pratt.parse_pat_args/2:ret` |
| `Unk0878` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0879` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0880` | 1 | `Pratt.parse_pat_list/2:p1` |
| `Unk0881` | 3 | `Pratt.parse_pats/1:ret`, `Pratt.parse_pats/2:p1`, `Pratt.parse_pats/2:ret` |
| `Unk0882` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0883` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0884` | 2 | `Pratt.parse_stmts/2:p1`, `Pratt.parse_stmts/2:ret` |
| `Unk0885` | 2 | `Pratt.parse_type_args/2:p1`, `Pratt.parse_type_args/2:ret` |
| `Unk0886` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0887` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0888` | 1 | `Pratt.pascal?/1:p0` |
| `Unk0889` | 1 | `Pratt.sexpr_pat/1:p0` |
| `Unk0890` | 1 | `Pratt.sexpr_stmt/1:p0` |
| `Unk0891` | 1 | `Pratt.str_interp/1:p0` |
| `Unk0892` | 1 | `Protocol.check_assoc!/2:ret` |
| `Unk0893` | 1 | `Protocol.check_impl/3:p0` |
| `Unk0894` | 3 | `Protocol.check_impl/3:p1`, `Protocol.expand/5:p0`, `Protocol.impl_methods/2:p1` |
| `Unk0895` | 5 | `Protocol.check_impl/3:p2`, `Protocol.check_no_overlap/3:p1`, `Protocol.dispatcher/4:p3`, `Protocol.guard_for!/3:p2`, `Protocol.registry/2:ret` |
| `Unk0896` | 1 | `Protocol.check_impl/3:ret` |
| `Unk0897` | 4 | `Protocol.check_no_overlap/3:p0`, `Protocol.dispatcher/4:p2`, `Protocol.expand/5:p1`, `Protocol.impl_methods/2:p0` |
| `Unk0898` | 2 | `Protocol.check_no_overlap/3:p2`, `Protocol.runtime_dispatch_target?/1:p0` |
| `Unk0899` | 1 | `Protocol.check_no_overlap/3:ret` |
| `Unk0900` | 2 | `Protocol.dispatcher/4:p0`, `Protocol.guard_for!/3:p1` |
| `Unk0901` | 1 | `Protocol.dispatcher/4:p1` |
| `Unk0902` | 1 | `Protocol.dispatcher/4:ret` |
| `Unk0903` | 1 | `Protocol.dispatcher_params/2:p0` |
| `Unk0904` | 1 | `Protocol.dispatcher_params/2:ret` |
| `Unk0905` | 1 | `Protocol.guard_for!/3:ret` |
| `Unk0906` | 1 | `Protocol.mangle/3:p0` |
| `Unk0907` | 1 | `Protocol.mangle/3:p1` |
| `Unk0908` | 1 | `Protocol.mangle/3:p2` |
| `Unk0909` | 1 | `Protocol.param_type/1:p0` |
| `Unk0910` | 1 | `Protocol.param_type/1:ret` |
| `Unk0911` | 1 | `Protocol.registry/2:p0` |
| `Unk0912` | 1 | `Protocol.registry/2:p1` |
| `Unk0913` | 1 | `Protocol.subst_self/2:p0` |
| `Unk0914` | 1 | `Protocol.subst_self/2:p1` |
| `Unk0915` | 1 | `Protocol.subst_self/2:ret` |
| `Unk0916` | 1 | `Protocol.sum_guard/1:p0` |
| `Unk0917` | 1 | `Protocol.tag_disjunction/2:p0` |
| `Unk0918` | 1 | `Protocol.tag_disjunction/2:p1` |
| `Unk0919` | 1 | `Range.check/3:p0` |
| `Unk0920` | 1 | `Range.check/3:p1` |
| `Unk0921` | 1 | `Range.lit/1:p0` |
| `Unk0922` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0923` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0924` | 4 | `Reach.all_emittable?/2:p1`, `Reach.parametric_ctx/2:ret`, `Reach.parametric_rs_ok?/2:p1`, `Reach.scan_func/3:p2` |
| `Unk0925` | 1 | `Reach.analyze/1:ret` |
| `Unk0926` | 15 | `Reach.atom_prim_blocker/0:ret`, `Reach.bare_atom_blocker/0:ret`, `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.ffi/2:ret`, `Reach.fn_type_blocker/0:ret`, `Reach.int_blocker/0:ret`, `Reach.parametric_blocker/0:ret`, `Reach.ref_blocker/0:ret`, `Reach.result_value_blocker/0:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret`, `Reach.wide_prim_blocker/0:ret`, `Reach.width_blocker/0:ret` |
| `Unk0927` | 5 | `Reach.build_default/0:ret`, `Reach.check_contracts/2:p1`, `Reach.gate!/2:p1`, `Reach.validate_default/1:p0`, `Reach.validate_default/1:ret` |
| `Unk0928` | 2 | `Reach.builder_tail_ok?/2:p1`, `Reach.tail_calls_generic?/2:p1` |
| `Unk0929` | 1 | `Reach.check_contracts/2:ret` |
| `Unk0930` | 3 | `Reach.classify/3:p1`, `Reach.scan/3:p1`, `Reach.scan_func/3:p1` |
| `Unk0931` | 5 | `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret` |
| `Unk0932` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0933` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0934` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0935` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0936` | 1 | `Reach.conc_erl?/2:p1` |
| `Unk0937` | 1 | `Reach.contract_message/1:p0` |
| `Unk0938` | 1 | `Reach.core/2:p0` |
| `Unk0939` | 1 | `Reach.core/2:p1` |
| `Unk0940` | 1 | `Reach.core/2:p1` |
| `Unk0941` | 3 | `Reach.deep/1:ret`, `Reach.find_atom_ordering/1:ret`, `Reach.func_symbol_violations/1:ret` |
| `Unk0942` | 1 | `Reach.emittable_parametric?/1:p0` |
| `Unk0943` | 1 | `Reach.emittable_parametric?/1:ret` |
| `Unk0944` | 1 | `Reach.fixpoint/2:p0` |
| `Unk0945` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0946` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0947` | 1 | `Reach.func_symbol_violations/1:p0` |
| `Unk0948` | 1 | `Reach.js_wide_int?/1:p0` |
| `Unk0949` | 1 | `Reach.mix_default/0:ret` |
| `Unk0950` | 1 | `Reach.parametric_type?/1:p0` |
| `Unk0951` | 1 | `Reach.pascal?/1:p0` |
| `Unk0952` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0953` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0954` | 1 | `Reach.sig_idents/1:ret` |
| `Unk0955` | 1 | `Reach.tail_calls_generic?/2:p0` |
| `Unk0956` | 1 | `Reach.tvar?/1:p0` |
| `Unk0957` | 1 | `Reach.tvar?/1:ret` |
| `Unk0958` | 2 | `Reach.type_has_tvar?/1:p0`, `Reach.type_idents/1:p0` |
| `Unk0959` | 1 | `Reach.type_idents/1:ret` |
| `Unk0960` | 1 | `Reach.uses_parametric?/2:p1` |
| `Unk0961` | 1 | `Repl.accumulate_line/2:p1` |
| `Unk0962` | 1 | `Repl.bind_env/2:p0` |
| `Unk0963` | 4 | `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:ret`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:ret` |
| `Unk0964` | 1 | `Repl.candidate_pool/2:p0` |
| `Unk0965` | 1 | `Repl.candidate_pool/2:ret` |
| `Unk0966` | 2 | `Repl.common_prefix/2:p0`, `Repl.common_prefix/3:p0` |
| `Unk0967` | 2 | `Repl.common_prefix/2:p1`, `Repl.common_prefix/3:p1` |
| `Unk0968` | 2 | `Repl.complete/2:ret`, `Repl.continuation/2:p1` |
| `Unk0969` | 9 | `Repl.decl_names/1:ret`, `Repl.eval_decl/2:p0`, `Repl.eval_decl/2:ret`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0970` | 1 | `Repl.describe/1:ret` |
| `Unk0971` | 1 | `Repl.eval/2:ret` |
| `Unk0972` | 3 | `Repl.eval_decl/2:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0` |
| `Unk0973` | 7 | `Repl.eval_decl/2:p0`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0974` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0975` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0976` | 1 | `Repl.flush_entries/1:p0` |
| `Unk0977` | 1 | `Repl.flush_entries/1:ret` |
| `Unk0978` | 1 | `Repl.info/1:ret` |
| `Unk0979` | 2 | `Repl.longest_common_prefix/1:p0`, `Repl.longest_common_prefix/1:ret` |
| `Unk0980` | 2 | `Repl.program/3:p1`, `Repl.run/4:p1` |
| `Unk0981` | 1 | `Repl.render/1:p0` |
| `Unk0982` | 1 | `Repl.run/4:ret` |
| `Unk0983` | 1 | `Repl.run/4:ret` |
| `Unk0984` | 1 | `Repl.safe_parse_body/1:ret` |
| `Unk0985` | 1 | `Repl.scan_count/2:p1` |
| `Unk0986` | 1 | `Repl.scan_count/2:ret` |
| `Unk0987` | 1 | `SelfHost.badge/1:p0` |
| `Unk0988` | 1 | `SelfHost.composition/0:ret` |
| `Unk0989` | 1 | `SelfHost.evidence/1:p0` |
| `Unk0990` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0991` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0992` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0993` | 1 | `SelfHost.external_host_calls/1:ret` |
| `Unk0994` | 1 | `SelfHost.ffi_ledger/0:ret` |
| `Unk0995` | 1 | `SelfHost.passes/0:ret` |
| `Unk0996` | 1 | `SelfHost.sibling_compose_call?/2:p0` |
| `Unk0997` | 1 | `SelfHost.sibling_compose_call?/2:p1` |
| `Unk0998` | 1 | `SelfHost.stages/0:ret` |
| `Unk0999` | 1 | `SelfHost.status_markdown/1:p0` |
| `Unk1000` | 1 | `Shadow.ded_bind/5:p0` |
| `Unk1001` | 3 | `Shadow.ded_bind/5:p2`, `Shadow.ded_expr/3:p0`, `Shadow.ded_expr/3:ret` |
| `Unk1002` | 1 | `Shadow.ded_bind/5:p3` |
| `Unk1003` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1004` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1005` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1006` | 1 | `Shadow.ded_bind/5:ret` |
| `Unk1007` | 2 | `Shadow.ded_block/4:p0`, `Shadow.dedup/3:p0` |
| `Unk1008` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk1009` | 2 | `Shadow.ded_block/4:p1`, `Shadow.ded_expr/3:p1` |
| `Unk1010` | 1 | `Shadow.ded_block/4:p2` |
| `Unk1011` | 1 | `Shadow.pat_var_names/1:ret` |
| `Unk1012` | 1 | `Test.run/2:p1` |
| `Unk1013` | 1 | `Test.run/2:ret` |
| `Unk1014` | 1 | `Tour.build_cell/1:p0` |
| `Unk1015` | 1 | `Tour.build_cell/1:ret` |
| `Unk1016` | 1 | `Tour.build_reach_example/1:p0` |
| `Unk1017` | 1 | `Tour.build_reach_example/1:ret` |
| `Unk1018` | 1 | `Tour.elixir_module/1:ret` |
| `Unk1019` | 2 | `Tour.encode/2:p0`, `Tour.encode_string/1:p0` |
| `Unk1020` | 1 | `Tour.generate/0:ret` |
| `Unk1021` | 1 | `Tour.reach_map/1:ret` |
| `Unk1022` | 1 | `Transpile.add_clause/2:p0` |
| `Unk1023` | 5 | `Transpile.add_clause/2:p0`, `Transpile.add_clause/2:p1`, `Transpile.build_clause/2:ret`, `Transpile.new_group/3:p1`, `Transpile.same_group?/3:p2` |
| `Unk1024` | 2 | `Transpile.add_clause/2:ret`, `Transpile.new_group/3:ret` |
| `Unk1025` | 1 | `Transpile.build_clause/2:p0` |
| `Unk1026` | 1 | `Transpile.build_clause/2:p1` |
| `Unk1027` | 1 | `Transpile.case_arm/1:p0` |
| `Unk1028` | 1 | `Transpile.classify/1:ret` |
| `Unk1029` | 4 | `Transpile.close_group/2:p0`, `Transpile.close_group/2:p1`, `Transpile.close_group/2:ret`, `Transpile.def_groups/1:ret` |
| `Unk1030` | 1 | `Transpile.escape/1:p0` |
| `Unk1031` | 1 | `Transpile.escape/1:ret` |
| `Unk1032` | 2 | `Transpile.escape_lit/1:p0`, `Transpile.string_part/1:p0` |
| `Unk1033` | 1 | `Transpile.flush/2:p0` |
| `Unk1034` | 3 | `Transpile.flush/2:p1`, `Transpile.render_items/3:p1`, `Transpile.render_submodule/3:p2` |
| `Unk1035` | 3 | `Transpile.flush/2:p1`, `Transpile.render_items/3:p1`, `Transpile.render_submodule/3:p2` |
| `Unk1036` | 1 | `Transpile.hole_sig?/1:p0` |
| `Unk1037` | 1 | `Transpile.infer_program/1:p0` |
| `Unk1038` | 3 | `Transpile.infer_program/1:ret`, `Transpile.infer_sigs/2:ret`, `Transpile.inferred/1:ret` |
| `Unk1039` | 1 | `Transpile.infer_report/1:p0` |
| `Unk1040` | 1 | `Transpile.infer_report/1:ret` |
| `Unk1041` | 1 | `Transpile.infer_sigs/2:p0` |
| `Unk1042` | 1 | `Transpile.max_placeholder/1:p0` |
| `Unk1043` | 4 | `Transpile.mod_str/1:p0`, `Transpile.short_name/1:p0`, `Transpile.snippet/1:p0`, `Transpile.var_name/1:p0` |
| `Unk1044` | 1 | `Transpile.module_groups/1:p0` |
| `Unk1045` | 1 | `Transpile.module_groups/1:ret` |
| `Unk1046` | 1 | `Transpile.moduledoc_lines/1:p0` |
| `Unk1047` | 1 | `Transpile.name_str/1:p0` |
| `Unk1048` | 1 | `Transpile.name_str/1:ret` |
| `Unk1049` | 1 | `Transpile.new_group/3:p0` |
| `Unk1050` | 1 | `Transpile.new_group/3:p2` |
| `Unk1051` | 1 | `Transpile.one_line/1:p0` |
| `Unk1052` | 1 | `Transpile.one_line/1:ret` |
| `Unk1053` | 1 | `Transpile.prime_xmod/1:p0` |
| `Unk1054` | 1 | `Transpile.prime_xmod/1:ret` |
| `Unk1055` | 1 | `Transpile.rank/1:p0` |
| `Unk1056` | 1 | `Transpile.rank/1:ret` |
| `Unk1057` | 1 | `Transpile.render_body/1:ret` |
| `Unk1058` | 1 | `Transpile.render_clause/2:p1` |
| `Unk1059` | 3 | `Transpile.render_items/3:p2`, `Transpile.render_submodule/3:p0`, `Transpile.struct_decl/2:p0` |
| `Unk1060` | 1 | `Transpile.same_group?/3:p0` |
| `Unk1061` | 1 | `Transpile.same_group?/3:p1` |
| `Unk1062` | 1 | `Transpile.sibling_module?/2:p0` |
| `Unk1063` | 1 | `Transpile.simple?/1:p0` |
| `Unk1064` | 1 | `Transpile.string_part/1:ret` |
| `Unk1065` | 1 | `Transpile.string_parts/1:p0` |
| `Unk1066` | 1 | `Transpile.string_parts/1:ret` |
| `Unk1067` | 1 | `Transpile.struct_decl/2:p1` |
| `Unk1068` | 1 | `Transpile.struct_field?/1:p0` |
| `Unk1069` | 1 | `Transpile.struct_mod_noise?/1:p0` |
| `Unk1070` | 2 | `Transpile.subst_ph/2:p0`, `Transpile.subst_ph/2:ret` |
| `Unk1071` | 1 | `Transpile.subst_ph/2:p1` |
| `Unk1072` | 1 | `Transpile.toplevel/3:p0` |
| `Unk1073` | 1 | `Transpile.toplevel/3:p1` |
| `Unk1074` | 2 | `Transpile.transpile/2:p0`, `Transpile.transpile_with_stats/2:p0` |
| `Unk1075` | 1 | `Transpile.transpile/2:p1` |
| `Unk1076` | 2 | `Transpile.transpile/2:ret`, `Transpile.transpile_with_stats/2:ret` |
| `Unk1077` | 1 | `Transpile.transpile_with_stats/2:p1` |
| `Unk1078` | 1 | `Transpile.transpile_with_stats/2:ret` |
| `Unk1079` | 1 | `Transpile.underscore_var/1:p0` |
| `Unk1080` | 1 | `Transpile.var?/1:p0` |

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
| `String.t()` (expr) | 3 | **NEEDS DECISION** | — |
| `_` (var/propagation) | 3 | propagated `E` (no fixed tag) | — |
| `_reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `list()` (expr) | 2 | **NEEDS DECISION** | — |
| `reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `"`#{name}`: range `#{ann}` is ` (expr) | 1 | **NEEDS DECISION** | — |
| `x` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"cannot read: #{:file.format_e` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{x}` is not a compile-time ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: body has type `#{b` (expr) | 1 | **NEEDS DECISION** | — |
| `"unsupported in comptime: #{in` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{f.name}`: returns error(s)` (expr) | 1 | **NEEDS DECISION** | — |
| `contract_message(vs)` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an integer literal` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{g}` requires `#{tvar}: #{p` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{op}`: no implicit Int↔Floa` (expr) | 1 | **NEEDS DECISION** | — |
| `parts |> List.last() |> to_str` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: binding declared `` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an `@external` par` (expr) | 1 | **NEEDS DECISION** | — |
| `"`<~` is in-place mutation of ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: value of type `#{t` (expr) | 1 | **NEEDS DECISION** | — |
| `{:__aliases__, _, parts}` (expr) | 1 | **NEEDS DECISION** | — |
| `tag` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `{:already_started, pid}` (expr) | 1 | **NEEDS DECISION** | — |
| `bad` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `"`#{f}(…)`: labeled arguments ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{n}`: literal #{v} is out o` (expr) | 1 | **NEEDS DECISION** | — |
| `"operator `#{op}` not allowed ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: literal #{v} is ou` (expr) | 1 | **NEEDS DECISION** | — |

