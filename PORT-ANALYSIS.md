# Port Analysis — Elixir → Rian

**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the
`REVIEW` sections and record decisions in a `port.spec` (feedback loop not yet
wired). Regenerate to diff against source — do not hand-edit this file.

## Summary

- modules: 42 · type slots: 2908 · auto-filled: 590 (20%) · holes: 2318
- structs seen: 49 · proposed sums: 2 · distinct error idioms: 31

## 1. Inferred signatures — AUTO (high confidence, type-check-validated)

| function | signature | return reach |
|---|---|---|
| `beam_func/1` | `(T) Vec(T) forall T` | ✓ all 4 |
| `core_list_tail/1` | `(T) T forall T` | ✓ all 4 |
| `union_t/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `borrowed/1` | `(String) String` | ✓ all 4 |
| `owned/1` | `(String) String` | ✓ all 4 |
| `rust_name/1` | `(String) String` | ✓ all 4 |
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
| `truthy!/1` | `(T) T forall T` | ✓ all 4 |
| `block_seps/5` | `(Vec(T), Int53, Int53, Int53, Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `inject_stdlib/1` | `(T) T forall T` | ✓ all 4 |
| `skip_nl/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `chunk_on_comma/3` | `(Vec(T), Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `collapse_runs/2` | `(Vec(String), Vec(String)) Vec(String)` | ✓ all 4 |
| `finish_items/2` | `(Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `format/1` | `(T) T forall T` | ✓ all 4 |
| `ll/3` | `(Vec(T), Vec(T), Vec(Vec(T))) Vec(Vec(T)) forall T` | ✓ all 4 |
| `logical_lines/1` | `(Vec(T)) Vec(Vec(T)) forall T` | ✓ all 4 |
| `next_code_line/1` | `(Vec(Option(T))) Option(T) forall T` | ✓ all 4 |
| `pop/1` | `(Vec(Vec(T))) Vec(T) forall T` | ✓ all 4 |
| `push/2` | `(Int53, Vec(Int53)) Vec(Int53)` | ✓ all 4 |
| `concat/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `concat/2` | `(T, T) T forall T` | ✓ all 4 |
| `canon_bool_case/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `fold_neg_literal/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `zero_anno/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `concat_chain/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `cp_expr/2` | `(String, Bool) String` | ✓ all 4 |
| `int_typeof/1` | `(Bool) String` | ✓ all 4 |
| `js_fresh/2` | `(String, Int53) String` | ✓ all 4 |
| `js_op/1` | `(String) String` | ✓ all 4 |
| `js_str_cp/1` | `(Int53) String` | ✓ all 4 |
| `float_repr_helper/0` | `() String` | ✓ all 4 |
| `kt_fresh/2` | `(String, Int53) String` | ✓ all 4 |
| `kt_op/1` | `(String) String` | ✓ all 4 |
| `kt_str_cp/1` | `(Int53) String` | ✓ all 4 |
| `num_kt/1` | `(String) String` | ✓ all 4 |
| `char_source/1` | `(Int53) String` | ✓ all 4 |
| `cp!/1` | `(T) T forall T` | ✓ all 4 |
| `norm_num/1` | `(T) T forall T` | ✓ all 4 |
| `str_cp_source/1` | `(Int53) String` | ✓ all 4 |
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
| `to_snake/1` | `(T) T forall T` | ✓ all 4 |
| `after_paren/2` | `(Vec(T), Int53) Vec(T) forall T` | ✓ all 4 |
| `expect_rbracket/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `expect_rparen/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `parse_body/1` | `(T) T forall T` | ✓ all 4 |
| `with_prelude/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `normalize/1` | `(Vec(T)) Vec(T) forall T` | ✓ all 4 |
| `validate_default/1` | `(Option(T)) Option(T) forall T` | ✓ all 4 |
| `longest_common_prefix/1` | `(Vec(T)) T forall T` | ✓ all 4 |
| `dedup_consecutive/1` | `(Vec(Vec(Vec(T)))) Vec(Vec(T)) forall T` | ✓ all 4 |
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
  pub def beam_for(module Unk0008, funcs Vec(Unk0009), ranges Vec(Map(Unk0010, Vec(Unk0011))), types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Map(Unk0010, Vec(Unk0011)))) Unk0012 := …

  # Beam.beam_func/1
  pub def beam_func(p0 Unk0013) Vec(Unk0013) := …

  # Beam.bin_seg/1
  pub def bin_seg(form Tuple(Option(Unk0014), Unk0015)) Unk0016 := …

  # Beam.bind_var/2
  pub def bind_var(n String, s Map(String, Unk0017)) Tuple(Unk0017, Map(String, Unk0017)) := …

  # Beam.block_forms/2
  pub def block_forms(p0 Sum1, _s Map(String, Unk0017)) Vec(Tuple(Option(Unk0014), Unk0015)) := …

  # Beam.body_forms/3
  pub def body_forms(src Sum1, scope Map(String, Unk0017), rtable Map(Unk0019, Unk0018)) Vec(Tuple(Option(Unk0014), Unk0015)) := …

  # Beam.body_seq/2
  pub def body_seq(p0 Sum1, s Map(String, Unk0017)) Vec(Tuple(Option(Unk0014), Unk0015)) := …

  # Beam.bump_var/1
  pub def bump_var(cur Unk0017) Unk0017 := …

  # Beam.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Beam.cap_arity_list/1
  pub def cap_arity_list(es Vec(Sum1)) Int53 := …

  # Beam.clause_form/2
  pub def clause_form(p0 Unk0020, rtable Map(Unk0019, Unk0018)) Unk0021 := …

  # Beam.compile/2
  pub def compile(src String, module Unk0008) Unk0012 := …

  # Beam.compile_ir/2
  pub def compile_ir(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), module Unk0008) Unk0012 := …

  # Beam.compile_program/1
  pub def compile_program(src String) Unk0023 := …

  # Beam.compile_program_ir/1
  pub def compile_program_ir(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0024 := …

  # Beam.cons/3
  pub def cons(p0 Vec(Unk0025), tail Tuple(Option(Unk0014), Unk0015), _f Fn(Sum1, Tuple(Option(Unk0014), Unk0015))) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.core_list_tail/1
  pub def core_list_tail(p0 Tuple(Option(Unk0014), Unk0015)) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.else_dispatch/3
  pub def else_dispatch(p0 Vec(Unk0026), catch_var String, _s Map(String, Unk0017)) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.erl_op/1
  pub def erl_op(p0 String) Unk0027 := …

  # Beam.expr_form/2
  pub def expr_form(p0 Sum1, _s Map(String, Unk0017)) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.fn_form/2
  pub def fn_form(t String, tctx Unk0028) Unk0029 := …

  # Beam.fun_ref/3
  pub def fun_ref(mod Unk0030, fun Unk0031, arity Unk0032) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.funcs_of/1
  pub def funcs_of(p0 Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Unk0009) := …

  # Beam.function_form/2
  pub def function_form(p0 Unk0006, rtable Map(Unk0019, Unk0018)) Unk0034 := …

  # Beam.guard_core/1
  pub def guard_core(p0 Sum1) Sum1 := …

  # Beam.guard_form/2
  pub def guard_form(p0 Sum1, _scope Map(String, Unk0017)) Vec(Vec(Tuple(Option(Unk0014), Unk0015))) := …

  # Beam.i64_overflow/4
  pub def i64_overflow(kind Unk0035, a Sum1, b Sum1, s Map(String, Unk0017)) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.i64_project/2
  pub def i64_project(p0 Unk0035, sv Unk0036) Unk0037 := …

  # Beam.int_t/0
  pub def int_t() Unk0038 := …

  # Beam.load/2
  pub def load(src String, module Unk0008) Tuple(Unk0039, Unk0008) := …

  # Beam.load_aux_mods/1
  pub def load_aux_mods(p0 Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0040 := …

  # Beam.load_ir/2
  pub def load_ir(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), module Unk0008) Tuple(Unk0041, Unk0008) := …

  # Beam.load_program/1
  pub def load_program(src Unk0042) Unk0043 := …

  # Beam.load_program_ir/1
  pub def load_program_ir(prog Unk0044) Unk0045 := …

  # Beam.map_field_pat/1
  pub def map_field_pat(p0 Unk0046) Unk0047 := …

  # Beam.num_form/1
  pub def num_form(n Unk0048) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.pascal?/1
  pub def pascal?(s Unk0049) Bool := …

  # Beam.pat_form/1
  pub def pat_form(p0 Sum2) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.pat_vars/2
  pub def pat_vars(p0 Sum2, acc Map(String, Unk0017)) Map(String, Unk0017) := …

  # Beam.ranges_of/1
  pub def ranges_of(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Map(Unk0010, Vec(Unk0011))) := …

  # Beam.remote_call/4
  pub def remote_call(mod Unk0050, fun String, args Vec(Sum1), scope Map(String, Unk0017)) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.spec_form/2
  pub def spec_form(p0 Unk0006, tctx Unk0028) Unk0034 := …

  # Beam.stmt_form/2
  pub def stmt_form(p0 Unk0051, s Map(String, Unk0017)) Tuple(Tuple(Option(Unk0014), Unk0015), Map(String, Unk0017)) := …

  # Beam.str_form/1
  pub def str_form(s Unk0052) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.struct_form/2
  pub def struct_form(p0 Map(Unk0010, Vec(Unk0011)), tctx Unk0028) Unk0005 := …

  # Beam.structs_of/1
  pub def structs_of(p0 Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Map(Unk0010, Vec(Unk0011))) := …

  # Beam.sum_form/2
  pub def sum_form(variants Unk0053, tctx Unk0028) Unk0054 := …

  # Beam.type_attrs/3
  pub def type_attrs(types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Map(Unk0010, Vec(Unk0011))), tctx Unk0028) Vec(Unk0034) := …

  # Beam.type_ctx/3
  pub def type_ctx(types Vec(Map(Unk0010, Vec(Unk0011))), ranges Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Map(Unk0010, Vec(Unk0011)))) Unk0028 := …

  # Beam.type_form/2
  pub def type_form(p0 String, _tctx Unk0028) Unk0005 := …

  # Beam.types_of/1
  pub def types_of(p0 Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Map(Unk0010, Vec(Unk0011))) := …

  # Beam.union_t/1
  pub def union_t(p0 Vec(Unk0005)) Unk0005 := …

  # Beam.var_atom/1
  pub def var_atom(p0 String) Unk0017 := …

  # Beam.var_form/1
  pub def var_form(x String) Tuple(Option(Unk0014), Unk0015) := …

  # Beam.with_form/5
  pub def with_form(p0 Vec(Unk0055), body Sum1, _els Vec(Unk0026), s Map(String, Unk0017), _d Int53) Tuple(Option(Unk0014), Unk0015) := …

  # Capability.beam_legal!/1
  pub def beam_legal!(p0 Unk0056) Unk0057 := …

  # Capability.count_block/3
  pub def count_block(p0 Vec(Unk0058), _bound Unk0059, acc Unk0060) Unk0060 := …

  # Capability.count_uses/1
  pub def count_uses(ast Unk0061) Unk0060 := …

  # Capability.count_uses/2
  pub def count_uses(p0 Unk0061, bound Unk0059) Unk0060 := …

  # Capability.lin_check/2
  pub def lin_check(env Map(Unk0062, Unk0063), ast Unk0061) Tuple(Unk0064, Vec(Unk0065)) := …

  # Capability.lin_check_block/3
  pub def lin_check_block(env Map(Unk0067, Unk0066), bindings Vec(Unk0068), final Unk0061) Tuple(Unk0064, Vec(Unk0065)) := …

  # Capability.max_merge/2
  pub def max_merge(a Unk0060, b Unk0060) Unk0060 := …

  # Capability.merge/2
  pub def merge(a Unk0060, b Unk0060) Unk0060 := …

  # Capability.parametric/1
  pub def parametric(t String) Tuple(String, Vec(Unk0069)) := …

  # Capability.pat_vars/1
  pub def pat_vars(p0 Unk0070) Unk0071 := …

  # Capability.rust_param/2
  pub def rust_param(p0 Unk0072, t String) String := …

  # Capability.split_top_level/1
  pub def split_top_level(s String) Vec(Unk0069) := …

  # Capability.verdict/2
  pub def verdict(env Map(Unk0062, Unk0063), uses Unk0060) Tuple(Unk0064, Vec(Unk0065)) := …

  # Check.abstract_cast_ret/3
  pub def abstract_cast_ret(ht Vec(Unk0073), cn Unk0074, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0076) := …

  # Check.abstract_op_type/4
  pub def abstract_op_type(op Unk0077, lt Vec(Unk0073), rt Vec(Unk0073), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0078 := …

  # Check.adoptable_int?/1
  pub def adoptable_int?(t Vec(Unk0073)) Bool := …

  # Check.all_types/1
  pub def all_types(prog Map(Unk0079, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Type) := …

  # Check.ann_each/3
  pub def ann_each(nodes Vec(Sum1), env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.ann_stmts/3
  pub def ann_stmts(p0 Vec(Unk0081), _env Map(Unk0080, Vec(Unk0073)), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.annotate/3
  pub def annotate(ast Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.arith_type/4
  pub def arith_type(l Sum1, r Sum1, lt Vec(Unk0073), rt Vec(Unk0073)) Unk0082 := …

  # Check.assignable?/2
  pub def assignable?(t Vec(Unk0073), t Vec(Unk0073)) Bool := …

  # Check.bind_mismatch/5
  pub def bind_mismatch(name Unk0083, ann Vec(Unk0073), e Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0084) := …

  # Check.bind_tvar/4
  pub def bind_tvar(_p Unk0085, p1 Unk0085, _tvars Unk0086, acc Map(Unk0087, Vec(Unk0073))) Map(Unk0087, Vec(Unk0073)) := …

  # Check.body_literal_adopts?/2
  pub def body_literal_adopts?(p0 Sum1, ret Vec(Unk0073)) Bool := …

  # Check.branch_join/1
  pub def branch_join(typed Vec(Tuple(Unk0088, Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.build_fn/2
  pub def build_fn(args Vec(Unk0089), ret Vec(Unk0073)) String := …

  # Check.call_bound_error/5
  pub def call_bound_error(g Vec(Unk0073), args Vec(Sum1), env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), fbounds Map(Vec(Unk0073), Vec(Unk0073))) Option(Unk0090) := …

  # Check.call_name/1
  pub def call_name(p0 Unk0091) Vec(Unk0092) := …

  # Check.called_ret/2
  pub def called_ret(ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), f Vec(Unk0073)) Vec(Unk0073) := …

  # Check.called_ret_with/4
  pub def called_ret_with(ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), f Vec(Unk0073), args_ast Vec(Sum1), env Map(Unk0080, Vec(Unk0073))) Vec(Unk0073) := …

  # Check.check/1
  pub def check(src Unk0093) Unk0094 := …

  # Check.check_bind_stmts/3
  pub def check_bind_stmts(p0 Vec(Unk0095), _env Map(Unk0080, Vec(Unk0073)), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0084) := …

  # Check.check_binds/2
  pub def check_binds(p0 Func, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0096 := …

  # Check.check_bounds/2
  pub def check_bounds(p0 Func, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0097 := …

  # Check.check_error_set/2
  pub def check_error_set(p0 Unk0098, p1 Unk0099) Tuple(Unk0100, String) := …

  # Check.check_external_caps/1
  pub def check_external_caps(p0 Func) Tuple(Unk0101, String) := …

  # Check.check_func/3
  pub def check_func(p0 Unk0102, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), eset Unk0099) Unk0103 := …

  # Check.check_labels/1
  pub def check_labels(p0 Func) Unk0104 := …

  # Check.check_numeric_mix/2
  pub def check_numeric_mix(p0 Func, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0105 := …

  # Check.check_program/1
  pub def check_program(p0 Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0106 := …

  # Check.check_return/2
  pub def check_return(p0 Func, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0107 := …

  # Check.clause_env/3
  pub def clause_env(pats Unk0108, params Unk0109, ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Map(Unk0080, Vec(Unk0073)) := …

  # Check.comp_str/1
  pub def comp_str(p0 Unk0110) String := …

  # Check.concrete_type?/1
  pub def concrete_type?(p0 Vec(Unk0073)) Bool := …

  # Check.conservative/1
  pub def conservative(p0 Vec(Unk0073)) Vec(Unk0073) := …

  # Check.const_int/1
  pub def const_int(p0 Sum1) Tuple(Unk0112, Unk0111) := …

  # Check.ctor_type/2
  pub def ctor_type(ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), name Vec(Unk0073)) Vec(Unk0073) := …

  # Check.ctor_types/2
  pub def ctor_types(types Vec(Type), prog Map(Unk0113, Vec(Unk0114))) Map(Unk0115, Unk0116) := …

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
  pub def first_bound_violation(g Vec(Unk0073), bounds Unk0127, subs Map(Unk0087, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0090) := …

  # Check.fixpoint/2
  pub def fixpoint(facts Unk0128, table Map(Unk0130, Unk0129)) Map(Unk0130, Unk0129) := …

  # Check.float_type?/1
  pub def float_type?(t Vec(Unk0073)) Bool := …

  # Check.fn_parts/1
  pub def fn_parts(p0 String) Unk0131 := …

  # Check.fn_ret/1
  pub def fn_ret(ft Vec(Unk0073)) Option(Unk0076) := …

  # Check.fsig/1
  pub def fsig(f Unk0132) Unk0133 := …

  # Check.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0134 := …

  # Check.generic_ret?/2
  pub def generic_ret?(_ret Unk0135, p1 Vec(Unk0136)) Bool := …

  # Check.has_tvar?/1
  pub def has_tvar?(s Vec(Unk0073)) Bool := …

  # Check.impl_table/1
  pub def impl_table(prog Map(Unk0138, Vec(Unk0137))) Unk0139 := …

  # Check.infer/3
  pub def infer(ast Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.infer_block/4
  pub def infer_block(p0 Vec(Unk0140), _env Map(Unk0080, Vec(Unk0073)), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), value Vec(Unk0073)) Vec(Unk0073) := …

  # Check.infer_tail/3
  pub def infer_tail(p0 Sum1, _env Map(Unk0080, Vec(Unk0073)), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.inner_of/1
  pub def inner_of(p0 Unk0085) Unk0085 := …

  # Check.instantiate_ret/2
  pub def instantiate_ret(p0 Unk0141, arg_types Vec(Vec(Unk0073))) Vec(Unk0073) := …

  # Check.int_lit_expr?/1
  pub def int_lit_expr?(p0 Sum1) Bool := …

  # Check.int_literal?/1
  pub def int_literal?(n Unk0142) Bool := …

  # Check.int_type?/1
  pub def int_type?(t Vec(Unk0073)) Bool := …

  # Check.join/2
  pub def join(t String, t String) Option(Unk0143) := …

  # Check.join_all/1
  pub def join_all(types Vec(Unk0144)) Vec(Unk0073) := …

  # Check.kind_prefix/1
  pub def kind_prefix(p0 Unk0145) String := …

  # Check.label_error/1
  pub def label_error(p0 Sum1) Tuple(Unk0146, String) := …

  # Check.label_error_children/1
  pub def label_error_children(node Sum1) Tuple(Unk0146, String) := …

  # Check.list_elem/1
  pub def list_elem(p0 Vec(Unk0073)) Unk0147 := …

  # Check.list_elems/1
  pub def list_elems(p0 Sum1) Vec(Unk0148) := …

  # Check.list_of/1
  pub def list_of(p0 Vec(Unk0073)) String := …

  # Check.lit_expr_adopts?/2
  pub def lit_expr_adopts?(p0 Sum1, ret Vec(Unk0073)) Bool := …

  # Check.lit_range_error/3
  pub def lit_range_error(expr Sum1, p1 String, name Unk0083) Option(Unk0149) := …

  # Check.literal_adopts?/2
  pub def literal_adopts?(p0 Sum1, ann Vec(Unk0073)) Bool := …

  # Check.literal_ordinal/2
  pub def literal_ordinal(p0 Sum1, p1 String) Tuple(Unk0150, Int53) := …

  # Check.missing_impl/5
  pub def missing_impl(g Vec(Unk0073), tvar Unk0151, ty Vec(Unk0073), protos Unk0152, impls Map(Vec(Unk0073), Vec(Unk0073))) Option(Unk0153) := …

  # Check.mixed_num?/2
  pub def mixed_num?(lt Vec(Unk0073), rt Vec(Unk0073)) Bool := …

  # Check.narrow/4
  pub def narrow(p0 Sum2, type Vec(Unk0073), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), env Map(Unk0080, Vec(Unk0073))) Map(Unk0080, Vec(Unk0073)) := …

  # Check.num_bits/2
  pub def num_bits(kind Unk0154, w Unk0155) Option(Unk0156) := …

  # Check.num_join/2
  pub def num_join(p0 Unk0157, p1 Unk0158) Option(Unk0143) := …

  # Check.num_kind/1
  pub def num_kind(p0 Vec(Unk0073)) Option(Unk0156) := …

  # Check.num_lub/2
  pub def num_lub(x String, y String) Unk0159 := …

  # Check.num_mix?/2
  pub def num_mix?(p0 Unk0160, k Unk0161) Bool := …

  # Check.num_mix_error/5
  pub def num_mix_error(op Unk0162, l Sum1, r Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Unk0163 := …

  # Check.num_widens?/2
  pub def num_widens?(p0 Unk0164, p1 Unk0165) Bool := …

  # Check.oor_scan/5
  pub def oor_scan(p0 Sum1, ty String, lo Unk0166, hi Unk0167, n Unk0083) Tuple(Unk0168, String) := …

  # Check.opaque_table/1
  pub def opaque_table(prog Map(Unk0169, Vec(Unk0170))) Unk0171 := …

  # Check.parametric_join/2
  pub def parametric_join(p0 String, _ String) Option(Unk0143) := …

  # Check.parse_parametric/1
  pub def parse_parametric(s String) Tuple(String, Vec(Unk0069)) := …

  # Check.pascal?/1
  pub def pascal?(s Unk0172) Bool := …

  # Check.produced_set/2
  pub def produced_set(f Unk0121, table Map(Unk0174, Unk0173)) Unk0175 := …

  # Check.program_ic/1
  pub def program_ic(p0 Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))) := …

  # Check.propagated_callees/1
  pub def propagated_callees(f Unk0121) Unk0176 := …

  # Check.range_base/2
  pub def range_base(ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), n Vec(Unk0073)) Option(Unk0177) := …

  # Check.range_bind/6
  pub def range_bind(name Unk0083, ann Vec(Unk0073), p2 Unk0178, ce Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0179) := …

  # Check.range_table/1
  pub def range_table(prog Map(Unk0180, Vec(Unk0181))) Unk0182 := …

  # Check.resolve_range/2
  pub def resolve_range(t Vec(Unk0073), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Check.scan_bound_calls/4
  pub def scan_bound_calls(p0 Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), fbounds Map(Vec(Unk0073), Vec(Unk0073))) Option(Unk0183) := …

  # Check.scan_num_mix/3
  pub def scan_num_mix(p0 Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0184) := …

  # Check.scan_num_mix_children/3
  pub def scan_num_mix_children(node Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0184) := …

  # Check.solve_error_sets/2
  pub def solve_error_sets(funcs Vec(Unk0185), tsets Map(Unk0119, Vec(Unk0119))) Map(Unk0130, Unk0129) := …

  # Check.split_top_commas/1
  pub def split_top_commas(s String) Vec(Unk0069) := …

  # Check.tag_name/1
  pub def tag_name(p0 Unk0186) Option(Unk0124) := …

  # Check.type_table/1
  pub def type_table(types Vec(Type)) Unk0187 := …

  # Check.uint_signed_join/2
  pub def uint_signed_join(u Unk0188, i Unk0188) Option(Unk0143) := …

  # Check.unify/2
  pub def unify(t Vec(Unk0073), t Vec(Unk0073)) Vec(Unk0073) := …

  # Check.walk_children/4
  pub def walk_children(node Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), fbounds Map(Vec(Unk0073), Vec(Unk0073))) Option(Unk0183) := …

  # Check.with_callees/1
  pub def with_callees(p0 Vec(Unk0189)) Vec(Unk0092) := …

  # Comptime.eval/1
  pub def eval(p0 Unk0190) Tuple(Unk0191, String) := …

  # Comptime.fold/1
  pub def fold(p0 Sum1) Tuple(Unk0192, String) := …

  # Comptime.int_div/3
  pub def int_div(_a Unk0193, p1 Int53, _op Fn(Unk0195, Unk0196, Unk0194)) Tuple(Unk0197, Int53) := …

  # Core.first_unsupported/2
  pub def first_unsupported(node Unk0198, unsup Map(Unk0199, Option(Unk0200))) Option(Unk0200) := …

  # Core.from_arm/1
  pub def from_arm(p0 Unk0201) Unk0202 := …

  # Core.from_expr/1
  pub def from_expr(p0 Sum1) Sum1 := …

  # Core.from_pairs/1
  pub def from_pairs(pairs Vec(Unk0203)) Vec(Tuple(Unk0204, Sum1)) := …

  # Core.from_pat/1
  pub def from_pat(p0 Sum2) Sum2 := …

  # Core.from_stmt/1
  pub def from_stmt(p0 Unk0205) Tuple(Unk0206, Sum1) := …

  # Core.from_tail/1
  pub def from_tail(p0 Unk0207) Sum1 := …

  # Core.reject_unsupported!/4
  pub def reject_unsupported!(funcs Vec(Unk0208), unsup Map(Unk0199, Option(Unk0200)), target Unk0209, exception Unk0210) Unk0211 := …

  # Cst.build/1
  pub def build(tokens Vec(Unk0212)) Unk0213 := …

  # Cst.open/4
  pub def open(open_tok Unk0212, close Unk0214, rest Vec(Unk0212), acc Vec(Tuple(Unk0215, Unk0212))) Tuple(Vec(Tuple(Unk0215, Unk0212)), Vec(Unk0216)) := …

  # Cst.seq/2
  pub def seq(p0 Vec(Unk0212), acc Vec(Tuple(Unk0215, Unk0212))) Tuple(Vec(Tuple(Unk0215, Unk0212)), Vec(Unk0216)) := …

  # Decl.all_impl_decls/1
  pub def all_impl_decls(decls Vec(Unk0217)) Vec(Unk0218) := …

  # Decl.all_impls/1
  pub def all_impls(decls Vec(Unk0217)) Vec(Unk0219) := …

  # Decl.all_protocols/1
  pub def all_protocols(decls Vec(Unk0217)) Vec(Unk0218) := …

  # Decl.assemble/3
  pub def assemble(decls Vec(Unk0220), aliases Unk0221, p2 Unk0222) Unk0223 := …

  # Decl.attach_doc/2
  pub def attach_doc(p0 Tuple(Unk0224, Map(Unk0225, Bool)), doc Bool) Tuple(Unk0224, Map(Unk0225, Bool)) := …

  # Decl.attach_external/3
  pub def attach_external(p0 Unk0226, target Unk0227, spec Unk0228) Tuple(Unk0224, Map(Unk0225, Bool)) := …

  # Decl.attach_targets/2
  pub def attach_targets(p0 Unk0229, targets Unk0230) Tuple(Unk0224, Map(Unk0225, Bool)) := …

  # Decl.balanced_parens/1
  pub def balanced_parens(p0 Vec(Unk0231)) Tuple(Vec(Unk0231), Vec(Unk0231)) := …

  # Decl.block_seps/5
  pub def block_seps(p0 Vec(Unk0232), _d Int53, _w Int53, _p Int53, acc Vec(Unk0232)) Vec(Unk0232) := …

  # Decl.build_func/1
  pub def build_func(p0 Vec(Unk0233)) Func := …

  # Decl.calls_show_float?/1
  pub def calls_show_float?(p0 Vec(Unk0234)) Bool := …

  # Decl.clause/2
  pub def clause(p0 Unk0235, _arity Unk0236) Clause := …

  # Decl.clause_env/2
  pub def clause_env(p0 Clause, params Unk0237) Map(Unk0080, Vec(Unk0073)) := …

  # Decl.collapse_parens/1
  pub def collapse_parens(s Unk0238) Unk0239 := …

  # Decl.collect_aliases/1
  pub def collect_aliases(decls Vec(Unk0217)) Unk0240 := …

  # Decl.collect_macros/1
  pub def collect_macros(decls Vec(Unk0217)) Map(Unk0241, Unk0242) := …

  # Decl.compile/1
  pub def compile(src String) Vec(Tuple(String, Unk0243)) := …

  # Decl.compile_beam/1
  pub def compile_beam(src String) Vec(Tuple(Unk0244, Unk0243)) := …

  # Decl.decl_boundary?/1
  pub def decl_boundary?(p0 Vec(Vec(Unk0231))) Bool := …

  # Decl.decl_kw?/1
  pub def decl_kw?(p0 Vec(Vec(Unk0231))) Bool := …

  # Decl.def_raw/4
  pub def def_raw(name Unk0245, params Unk0246, head_rev Vec(Vec(Unk0231)), body Option(Unk0247)) Unk0248 := …

  # Decl.detok_block/1
  pub def detok_block(tokens Unk0249) Option(Unk0247) := …

  # Decl.extract_parens/1
  pub def extract_parens(str Unk0250) Unk0251 := …

  # Decl.field/1
  pub def field(f Unk0252) Field := …

  # Decl.fields/1
  pub def fields(inside Unk0253) Vec(Unk0254) := …

  # Decl.impl_struct/3
  pub def impl_struct(proto Unk0255, type Unk0256, inner Unk0257) Unk0258 := …

  # Decl.in_scope/2
  pub def in_scope(decls Vec(Unk0217), f Fn(Unk0259, Unk0260)) Vec(Unk0218) := …

  # Decl.inject_stdlib/1
  pub def inject_stdlib(prog Tuple(Unk0261, Vec(Unk0262))) Tuple(Unk0261, Vec(Unk0262)) := …

  # Decl.line_continues?/2
  pub def line_continues?(p0 Vec(Vec(Unk0231)), _rest Vec(Vec(Unk0231))) Bool := …

  # Decl.lower_meta/3
  pub def lower_meta(funcs Vec(Unk0263), decls Vec(Unk0217), targets Option(Unk0264)) Vec(Unk0265) := …

  # Decl.macro_param_names/1
  pub def macro_param_names(pstr Unk0266) Unk0267 := …

  # Decl.mark_pub/1
  pub def mark_pub(p0 Unk0268) Tuple(Unk0224, Map(Unk0225, Bool)) := …

  # Decl.mark_test/1
  pub def mark_test(p0 Unk0269) Tuple(Unk0224, Map(Unk0225, Bool)) := …

  # Decl.meta_clause/5
  pub def meta_clause(p0 Unk0270, _env Map(Unk0241, Unk0242), _p Bool, _params Unk0237, _show Unk0271) Unk0272 := …

  # Decl.needs_show_float?/1
  pub def needs_show_float?(prog Tuple(Unk0261, Vec(Unk0262))) Bool := …

  # Decl.nz/1
  pub def nz(s String) Option(Unk0273) := …

  # Decl.param/1
  pub def param(p Unk0274) Unk0275 := …

  # Decl.parse/1
  pub def parse(src String) Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))) := …

  # Decl.parse_abstract/4
  pub def parse_abstract(head Unk0276, body_toks Unk0277, pub? Unk0278, doc Unk0279) Opaque := …

  # Decl.parse_abstract_members/1
  pub def parse_abstract_members(toks Unk0277) Unk0280 := …

  # Decl.parse_alias/1
  pub def parse_alias(text Unk0276) Tuple(Unk0281, Unk0282) := …

  # Decl.parse_assoc_binding/1
  pub def parse_assoc_binding(t Unk0283) Tuple(Unk0285, Option(Unk0284)) := …

  # Decl.parse_binder/1
  pub def parse_binder(b Unk0286) Tuple(Unk0288, Vec(Unk0287)) := …

  # Decl.parse_binders/1
  pub def parse_binders(binders Unk0289) Vec(Unk0290) := …

  # Decl.parse_bounds/1
  pub def parse_bounds(text Unk0291) Unk0292 := …

  # Decl.parse_cast_rule/1
  pub def parse_cast_rule(p0 Unk0293) Unk0294 := …

  # Decl.parse_const/3
  pub def parse_const(text Unk0276, pub? Unk0295, doc Unk0296) Const := …

  # Decl.parse_external/1
  pub def parse_external(p0 Vec(Unk0297)) Tuple(Unk0298, Unk0299) := …

  # Decl.parse_head/1
  pub def parse_head(head String) Unk0300 := …

  # Decl.parse_op_rule/1
  pub def parse_op_rule(p0 Unk0293) Unk0301 := …

  # Decl.parse_opaque/3
  pub def parse_opaque(text Unk0276, pub? Unk0302, doc Unk0303) Opaque := …

  # Decl.parse_ordinal/1
  pub def parse_ordinal(p0 Unk0304) Tuple(Unk0306, Unk0305) := …

  # Decl.parse_params/1
  pub def parse_params(str Unk0307) Vec(Unk0308) := …

  # Decl.parse_range/3
  pub def parse_range(text Unk0276, pub? Unk0309, doc Unk0310) Range := …

  # Decl.parse_struct/3
  pub def parse_struct(text Unk0250, pub? Unk0311, doc Unk0312) Struct := …

  # Decl.parse_targets/1
  pub def parse_targets(toks Unk0313) Unk0230 := …

  # Decl.parse_type/3
  pub def parse_type(rest Unk0276, pub? Unk0314, doc Unk0315) Type := …

  # Decl.parse_use/1
  pub def parse_use(text Unk0316) Use := …

  # Decl.proto_method_traits/1
  pub def proto_method_traits(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0317 := …

  # Decl.protocol_defs/4
  pub def protocol_defs(decls Vec(Unk0220), types Unk0318, structs Unk0319, targets Unk0320) Vec(Unk0321) := …

  # Decl.protocol_struct/2
  pub def protocol_struct(name Unk0322, inner Unk0323) Unk0324 := …

  # Decl.protocol_unit/3
  pub def protocol_unit(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Map(Unk0010, Vec(Unk0011)))) Vec(Tuple(String, Unk0243)) := …

  # Decl.req_ret/1
  pub def req_ret(p0 Unk0325) Unk0326 := …

  # Decl.skip_nl/1
  pub def skip_nl(p0 Vec(Unk0231)) Vec(Unk0231) := …

  # Decl.split2/2
  pub def split2(str Unk0327, sep Unk0328) Tuple(Unk0330, Unk0329) := …

  # Decl.split_decls/1
  pub def split_decls(p0 Vec(Vec(Unk0231))) Vec(Unk0331) := …

  # Decl.split_forall/1
  pub def split_forall(head Unk0332) Unk0333 := …

  # Decl.split_once/2
  pub def split_once(str Unk0276, sep String) Tuple(Unk0334, Unk0335) := …

  # Decl.split_top/2
  pub def split_top(str Unk0336, sep String) Unk0337 := …

  # Decl.strip_type_params/1
  pub def strip_type_params(name Unk0338) Unk0281 := …

  # Decl.subst_const/2
  pub def subst_const(p0 Unk0339, aliases Unk0221) Const := …

  # Decl.subst_fields/2
  pub def subst_fields(fs Vec(Unk0340), aliases Unk0341) Vec(Field) := …

  # Decl.subst_func/2
  pub def subst_func(p0 Unk0342, aliases Unk0221) Func := …

  # Decl.subst_struct/2
  pub def subst_struct(p0 Unk0343, aliases Unk0221) Struct := …

  # Decl.subst_type/2
  pub def subst_type(p0 Unk0344, aliases Unk0221) Type := …

  # Decl.subst_type_str/2
  pub def subst_type_str(type Unk0345, aliases Vec(Unk0346)) Unk0345 := …

  # Decl.subst_variant/2
  pub def subst_variant(p0 Unk0347, aliases Unk0348) Variant := …

  # Decl.take_block/3
  pub def take_block(p0 Vec(Vec(Unk0231)), depth Int53, acc Vec(Vec(Unk0231))) Tuple(Vec(Vec(Unk0231)), Vec(Vec(Unk0231))) := …

  # Decl.take_decl/1
  pub def take_decl(p0 Vec(Vec(Unk0231))) Tuple(Tuple(Unk0224, Map(Unk0225, Bool)), Vec(Unk0231)) := …

  # Decl.take_def/1
  pub def take_def(p0 Vec(Vec(Unk0231))) Tuple(Unk0248, Vec(Vec(Unk0231))) := …

  # Decl.take_head/4
  pub def take_head(name Unk0245, params Unk0246, p2 Vec(Vec(Unk0231)), head Vec(Vec(Unk0231))) Tuple(Unk0248, Vec(Vec(Unk0231))) := …

  # Decl.take_line/2
  pub def take_line(tokens Vec(Vec(Unk0231)), acc Vec(Vec(Unk0231))) Tuple(Vec(Vec(Unk0231)), Vec(Vec(Unk0231))) := …

  # Decl.take_line/3
  pub def take_line(p0 Vec(Vec(Unk0231)), acc Vec(Vec(Unk0231)), _depth Int53) Tuple(Vec(Vec(Unk0231)), Vec(Vec(Unk0231))) := …

  # Decl.take_mod_body/2
  pub def take_mod_body(p0 Vec(Vec(Unk0231)), acc Vec(Unk0349)) Tuple(Vec(Unk0349), Vec(Vec(Unk0231))) := …

  # Decl.take_parens/3
  pub def take_parens(p0 Vec(Unk0231), p1 Int53, acc Vec(Unk0231)) Tuple(Vec(Unk0231), Vec(Unk0231)) := …

  # Decl.take_type/2
  pub def take_type(p0 Vec(Vec(Unk0231)), acc Vec(Vec(Unk0231))) Tuple(Vec(Vec(Unk0231)), Vec(Vec(Unk0231))) := …

  # Decl.take_until_do/2
  pub def take_until_do(p0 Vec(Vec(Unk0231)), acc Vec(Vec(Unk0231))) Tuple(Vec(Vec(Unk0231)), Unk0350) := …

  # Decl.variant/1
  pub def variant(v Unk0250) Variant := …

  # Doc.concat/1
  pub def concat(docs Vec(Tuple(Unk0351, String))) Tuple(Unk0351, String) := …

  # Doc.concat/2
  pub def concat(a Tuple(Unk0351, String), b Tuple(Unk0351, String)) Tuple(Unk0351, String) := …

  # Doc.do_render/5
  pub def do_render(_w Int53, _k Int53, p2 Vec(Unk0352), p3 Vec(Unk0353), out Vec(String)) Vec(String) := …

  # Doc.empty/0
  pub def empty() Tuple(Unk0351, String) := …

  # Doc.fits?/2
  pub def fits?(w Int53, _work Vec(Unk0352)) Bool := …

  # Doc.flat_string/1
  pub def flat_string(p0 Unk0353) String := …

  # Doc.flush_suffix/2
  pub def flush_suffix(p0 Vec(Unk0353), out Vec(String)) Vec(String) := …

  # Doc.group/1
  pub def group(doc Tuple(Unk0351, String)) Unk0354 := …

  # Doc.hardline/0
  pub def hardline() Tuple(Unk0351, String) := …

  # Doc.if_break/2
  pub def if_break(broken Tuple(Unk0351, String), flat Tuple(Unk0351, String)) Tuple(Unk0351, String) := …

  # Doc.join/2
  pub def join(_sep Tuple(Unk0351, String), p1 Vec(Tuple(Unk0351, String))) Tuple(Unk0351, String) := …

  # Doc.line/0
  pub def line() Tuple(Unk0351, String) := …

  # Doc.line_suffix/1
  pub def line_suffix(doc Tuple(Unk0351, String)) Tuple(Unk0351, String) := …

  # Doc.must_break?/1
  pub def must_break?(p0 Tuple(Unk0351, String)) Bool := …

  # Doc.nest/2
  pub def nest(n Vec(Unk0355), doc Tuple(Unk0351, String)) Tuple(Unk0351, String) := …

  # Doc.render/2
  pub def render(doc Tuple(Unk0351, String), width Int53) String := …

  # Doc.softline/0
  pub def softline() Tuple(Unk0351, String) := …

  # Doc.text/1
  pub def text(s String) Tuple(Unk0351, String) := …

  # Doctest.augment/2
  pub def augment(src String, examples Vec(Unk0356)) String := …

  # Doctest.extract/1
  pub def extract(src String) Vec(Unk0356) := …

  # Doctest.exunit_cases/2
  pub def exunit_cases(src String, mod Unk0357) Unk0358 := …

  # Doctest.fences/1
  pub def fences(md Unk0359) Unk0360 := …

  # Doctest.module_doc_strings/1
  pub def module_doc_strings(p0 Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Unk0361) := …

  # Doctest.pairs/1
  pub def pairs(p0 Unk0362) Vec(Unk0363) := …

  # Doctest.run/2
  pub def run(src String, p1 Unk0364) Vec(Unk0365) := …

  # Doctest.run_markdown/1
  pub def run_markdown(md Unk0366) Unk0367 := …

  # Exhaustiveness.add_range/4
  pub def add_range(env Tuple(Unk0368, Map(String, String)), type_name String, lo Unk0369, hi Unk0370) Tuple(Unk0368, Map(String, String)) := …

  # Exhaustiveness.add_type/3
  pub def add_type(env Tuple(Unk0368, Map(String, String)), type_name String, variants Vec(Tuple(String, Unk0371))) Tuple(Unk0368, Map(String, String)) := …

  # Exhaustiveness.analyze/3
  pub def analyze(arms Vec(Unk0372), n Int53, env Map(Unk0374, Unk0373)) Unk0375 := …

  # Exhaustiveness.arity/2
  pub def arity(_env Map(Unk0374, Unk0373), p1 Unk0376) Int53 := …

  # Exhaustiveness.base_env/0
  pub def base_env() Tuple(Unk0368, Map(String, String)) := …

  # Exhaustiveness.body_core/1
  pub def body_core(body Sum1) Sum1 := …

  # Exhaustiveness.check_case_bodies!/2
  pub def check_case_bodies!(funcs Unk0377, env Unk0378) Unk0379 := …

  # Exhaustiveness.check_match!/3
  pub def check_match!(core Unk0380, env Map(Unk0374, Unk0373), where Unk0381) Unk0382 := …

  # Exhaustiveness.check_one_case!/3
  pub def check_one_case!(p0 Sum1, env Map(Unk0374, Unk0373), where Unk0381) Unk0383 := …

  # Exhaustiveness.collect_cases/2
  pub def collect_cases(p0 Vec(Unk0384), acc Vec(Unk0385)) Vec(Unk0385) := …

  # Exhaustiveness.collect_children/2
  pub def collect_children(struct Vec(Unk0384), acc Vec(Unk0385)) Vec(Unk0385) := …

  # Exhaustiveness.default/1
  pub def default(rows Vec(Unk0386)) Vec(Unk0386) := …

  # Exhaustiveness.head_ctors/1
  pub def head_ctors(rows Vec(Unk0386)) Vec(Unk0387) := …

  # Exhaustiveness.missing_head/2
  pub def missing_head(_env Map(Unk0374, Unk0373), p1 Vec(Unk0387)) Unk0388 := …

  # Exhaustiveness.pascal/1
  pub def pascal(c Unk0389) String := …

  # Exhaustiveness.program_env/3
  pub def program_env(types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Unk0390), ranges Vec(Unk0391)) Tuple(Unk0368, Map(String, String)) := …

  # Exhaustiveness.render/1
  pub def render(p0 Vec(Unk0392)) String := …

  # Exhaustiveness.signature/2
  pub def signature(_env Map(Unk0374, Unk0373), p1 Vec(Unk0387)) Tuple(Unk0394, Vec(Unk0393)) := …

  # Exhaustiveness.specialize/3
  pub def specialize(rows Vec(Unk0386), c Unk0376, env Map(Unk0374, Unk0373)) Vec(Unk0386) := …

  # Exhaustiveness.useful?/3
  pub def useful?(rows Vec(Unk0386), p1 Vec(Unk0395), _env Map(Unk0374, Unk0373)) Bool := …

  # Exhaustiveness.witness/3
  pub def witness(rows Vec(Unk0386), p1 Int53, _env Map(Unk0374, Unk0373)) Tuple(Unk0396, Vec(Unk0388)) := …

  # Fixpoint.check/4
  pub def check(mod Unk0397, corpus Unk0398, project Unk0399, p3 Unk0400) Unk0401 := …

  # Fixpoint.load_lexer/2
  pub def load_lexer(source String, mod Unk0008) Unk0008 := …

  # Format.apply_node/3
  pub def apply_node(p0 Option(Unk0402), base Vec(Unk0355), st Vec(Vec(Unk0355))) Vec(Vec(Unk0355)) := …

  # Format.bd/3
  pub def bd(p0 Vec(Option(Unk0402)), _prev Option(Unk0402), _rf Bool) Tuple(Unk0351, String) := …

  # Format.blank?/1
  pub def blank?(p0 Vec(Option(Unk0402))) Bool := …

  # Format.block_head?/2
  pub def block_head?(p0 Vec(Option(Unk0402)), next Vec(Vec(Option(Unk0402)))) Bool := …

  # Format.boundary?/1
  pub def boundary?(p0 Option(Unk0403)) Bool := …

  # Format.boundary_tok?/1
  pub def boundary_tok?(p0 Tuple(Unk0404, String)) Bool := …

  # Format.chunk_on_comma/3
  pub def chunk_on_comma(p0 Vec(Unk0405), cur Vec(Unk0405), acc Vec(Vec(Unk0405))) Vec(Vec(Unk0405)) := …

  # Format.closer_lead?/1
  pub def closer_lead?(p0 Tuple(Unk0404, String)) Bool := …

  # Format.comment_only?/1
  pub def comment_only?(line Vec(Option(Unk0402))) Bool := …

  # Format.cons_group?/1
  pub def cons_group?(inner Vec(Unk0406)) Bool := …

  # Format.cont_lead?/1
  pub def cont_lead?(p0 Tuple(Unk0404, String)) Bool := …

  # Format.decl_kw?/1
  pub def decl_kw?(p0 Tuple(Unk0404, String)) Bool := …

  # Format.declaration_line?/1
  pub def declaration_line?(p0 Vec(Option(Unk0402))) Bool := …

  # Format.finish_items/2
  pub def finish_items(cur Vec(Unk0405), acc Vec(Vec(Unk0405))) Vec(Vec(Unk0405)) := …

  # Format.format/1
  pub def format(src Unk0407) Unk0407 := …

  # Format.format_result/1
  pub def format_result(src Unk0407) Tuple(Unk0409, Unk0408) := …

  # Format.group_doc/4
  pub def group_doc(open Unk0410, inner Vec(Unk0406), close Unk0410, reflow? Bool) Tuple(Unk0351, String) := …

  # Format.has_comment?/1
  pub def has_comment?(nodes Vec(Unk0406)) Bool := …

  # Format.has_tok?/2
  pub def has_tok?(line Vec(Tuple(Unk0412, Tuple(Unk0411, String))), t Tuple(Unk0411, String)) Bool := …

  # Format.head_tok/1
  pub def head_tok(p0 Option(Unk0402)) Tuple(Unk0404, String) := …

  # Format.indent_and_render/4
  pub def indent_and_render(p0 Vec(Vec(Option(Unk0402))), _stack Vec(Vec(Unk0355)), _cont Int53, acc Vec(String)) Vec(String) := …

  # Format.lead_adjust/1
  pub def lead_adjust(p0 Vec(Option(Unk0402))) Int53 := …

  # Format.leaf/1
  pub def leaf(p0 Unk0410) String := …

  # Format.line_doc/1
  pub def line_doc(nodes Vec(Option(Unk0402))) Tuple(Unk0351, String) := …

  # Format.ll/3
  pub def ll(p0 Vec(Unk0413), cur Vec(Unk0413), acc Vec(Vec(Unk0413))) Vec(Vec(Unk0413)) := …

  # Format.logical_lines/1
  pub def logical_lines(nodes Vec(Unk0413)) Vec(Vec(Unk0413)) := …

  # Format.mark/1
  pub def mark(nodes Vec(Option(Unk0402))) Vec(Option(Unk0402)) := …

  # Format.mark/3
  pub def mark(p0 Vec(Option(Unk0402)), _prev Option(Unk0402), acc Vec(Option(Unk0402))) Vec(Option(Unk0402)) := …

  # Format.next_code_line/1
  pub def next_code_line(p0 Vec(Vec(Option(Unk0402)))) Option(Unk0403) := …

  # Format.node_doc/2
  pub def node_doc(p0 Option(Unk0402), _rf Bool) Tuple(Unk0351, String) := …

  # Format.pop/1
  pub def pop(p0 Vec(Vec(Unk0355))) Vec(Vec(Unk0355)) := …

  # Format.push/2
  pub def push(base Vec(Unk0355), st Vec(Vec(Unk0355))) Vec(Vec(Unk0355)) := …

  # Format.render_line/2
  pub def render_line(nodes Vec(Option(Unk0402)), base Vec(Unk0355)) String := …

  # Format.space?/2
  pub def space?(_prev Unk0414, p1 Tuple(Unk0404, String)) Bool := …

  # Format.split_items/1
  pub def split_items(nodes Vec(Unk0406)) Vec(Vec(Option(Unk0402))) := …

  # Format.squeeze_blanks/1
  pub def squeeze_blanks(lines Unk0415) Unk0416 := …

  # Format.tail_tok/1
  pub def tail_tok(p0 Option(Unk0402)) Unk0414 := …

  # Format.trailing_comma?/1
  pub def trailing_comma?(inner Vec(Unk0406)) Bool := …

  # Format.trailing_op?/1
  pub def trailing_op?(line Vec(Option(Unk0402))) Bool := …

  # Format.update_stack/4
  pub def update_stack(line Vec(Option(Unk0402)), rest Vec(Vec(Option(Unk0402))), base Vec(Unk0355), stack Vec(Vec(Unk0355))) Vec(Vec(Unk0355)) := …

  # Format.value_end?/1
  pub def value_end?(p0 Option(Unk0402)) Bool := …

  # Format.value_end_tok?/1
  pub def value_end_tok?(p0 Unk0414) Bool := …

  # FormsEquiv.abstract_code/1
  pub def abstract_code(beam Unk0417) Unk0418 := …

  # FormsEquiv.alpha_rename/1
  pub def alpha_rename(form Unk0419) Unk0420 := …

  # FormsEquiv.bool_clause/1
  pub def bool_clause(p0 Unk0421) Tuple(Unk0423, Unk0422) := …

  # FormsEquiv.bool_clause_pair/1
  pub def bool_clause_pair(p0 Vec(Unk0421)) Tuple(Unk0421, Unk0421) := …

  # FormsEquiv.canon_bool_case/1
  pub def canon_bool_case(p0 Vec(Unk0424)) Vec(Unk0424) := …

  # FormsEquiv.diff/2
  pub def diff(a Unk0425, b Unk0425) Tuple(Unk0427, Vec(Unk0426)) := …

  # FormsEquiv.equivalent?/2
  pub def equivalent?(a Unk0425, b Unk0425) Bool := …

  # FormsEquiv.fold_neg_literal/1
  pub def fold_neg_literal(p0 Vec(Unk0428)) Vec(Unk0428) := …

  # FormsEquiv.key/1
  pub def key(p0 Unk0429) Tuple(Unk0431, Unk0430) := …

  # FormsEquiv.normalize/1
  pub def normalize(beam Unk0425) Unk0432 := …

  # FormsEquiv.user_function?/1
  pub def user_function?(p0 Unk0433) Bool := …

  # FormsEquiv.verified?/2
  pub def verified?(oracle Unk0425, port Unk0425) Bool := …

  # FormsEquiv.verify/2
  pub def verify(oracle Unk0425, port Unk0425) Vec(Unk0434) := …

  # FormsEquiv.walk_rename/2
  pub def walk_rename(p0 Unk0419, map Map(Unk0436, Unk0435)) Tuple(Unk0419, Map(Unk0436, Unk0435)) := …

  # FormsEquiv.zero_anno/1
  pub def zero_anno(tuple Vec(Unk0437)) Vec(Unk0437) := …

  # History.add/1
  pub def add(line Unk0438) Unk0439 := …

  # History.dedup_consecutive/1
  pub def dedup_consecutive(p0 Vec(Vec(Unk0440))) Vec(Vec(Unk0440)) := …

  # History.load/0
  pub def load() Vec(Unk0441) := …

  # History.path/0
  pub def path() Unk0442 := …

  # Infer.app/2
  pub def app(head String, args Vec(Unk0443)) Tuple(Unk0444, String) := …

  # Infer.app1/2
  pub def app1(head String, s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.bind/3
  pub def bind(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), id Unk0445, t Tuple(Unk0444, String)) Unk0447 := …

  # Infer.bind_checked/3
  pub def bind_checked(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), i Unk0445, t Tuple(Unk0444, String)) Tuple(Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), Unk0448) := …

  # Infer.bind_params/3
  pub def bind_params(args Unk0449, pvars Unk0450, store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Unk0451 := …

  # Infer.build_ctx/2
  pub def build_ctx(stdlib_map Unk0452, p1 Unk0453) Unk0454 := …

  # Infer.build_ledger/2
  pub def build_ledger(params Unk0455, ret String) Vec(Tuple(String, Unk0456)) := …

  # Infer.call_sig/6
  pub def call_sig(ctx Map(Unk0458, Unk0457), key Unk0459, args Vec(Bool), env Map(String, Tuple(Unk0444, String)), _outer Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.case_arm/1
  pub def case_arm(p0 Unk0460) Tuple(Unk0462, Option(Unk0461)) := …

  # Infer.clear_xmod/0
  pub def clear_xmod() Unk0463 := …

  # Infer.cluster_name/2
  pub def cluster_name(clusters Unk0457, struct String) String := …

  # Infer.con/1
  pub def con(name String) Tuple(Unk0444, String) := …

  # Infer.do_unify/3
  pub def do_unify(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), t Tuple(Unk0444, String), t Tuple(Unk0444, String)) Tuple(Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), Unk0448) := …

  # Infer.free_vars/2
  pub def free_vars(store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), t Tuple(Unk0444, String)) Vec(Unk0464) := …

  # Infer.fresh/1
  pub def fresh(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.fresh_n/2
  pub def fresh_n(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), k Int53) Tuple(Vec(Unk0465), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.fresh_num/1
  pub def fresh_num(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.freshen_tvars/2
  pub def freshen_tvars(tvars Vec(Unk0466), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Map(Unk0466, Unk0467), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen/4
  pub def gen(n Bool, _env Map(String, Tuple(Unk0444, String)), _ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen_args_then_fresh/4
  pub def gen_args_then_fresh(args Vec(Bool), env Map(String, Tuple(Unk0444, String)), ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen_block/4
  pub def gen_block(p0 Vec(Bool), _env Map(String, Tuple(Unk0444, String)), _ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen_cons/5
  pub def gen_cons(h Bool, t Bool, env Map(String, Tuple(Unk0444, String)), ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen_pat/4
  pub def gen_pat(p0 Vec(Unk0468), pv Tuple(Unk0444, String), env Map(String, Tuple(Unk0444, String)), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Map(String, Tuple(Unk0444, String)), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.gen_pat_cons/5
  pub def gen_pat_cons(h Vec(Unk0468), t Vec(Unk0468), pv Tuple(Unk0444, String), env Map(String, Tuple(Unk0444, String)), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Map(String, Tuple(Unk0444, String)), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.generalize_map/3
  pub def generalize_map(pvars Unk0469, rvar Tuple(Unk0444, String), store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Map(Unk0471, Unk0470) := …

  # Infer.hole_or/2
  pub def hole_or(p0 Unk0472, h Unk0472) Unk0472 := …

  # Infer.hole_sig?/1
  pub def hole_sig?(p0 Unk0473) Bool := …

  # Infer.infer_group/2
  pub def infer_group(p0 Unk0474, ctx Tuple(Unk0476, Unk0475)) Unk0473 := …

  # Infer.instantiate/5
  pub def instantiate(p0 Unk0477, args Vec(Bool), env Map(String, Tuple(Unk0444, String)), ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.load_prelude_sigs/0
  pub def load_prelude_sigs() Unk0478 := …

  # Infer.mark_num/2
  pub def mark_num(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), t Tuple(Unk0444, String)) Tuple(Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), Unk0479) := …

  # Infer.max_ph/1
  pub def max_ph(p0 Vec(Unk0480)) Int53 := …

  # Infer.maybe_tuple/4
  pub def maybe_tuple(elems Vec(Unk0481), env Map(String, Tuple(Unk0444, String)), ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Tuple(Unk0444, String), Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) := …

  # Infer.mod_name/1
  pub def mod_name(p0 Unk0482) String := …

  # Infer.num_conflict?/3
  pub def num_conflict?(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), i Unk0445, t Tuple(Unk0444, String)) Bool := …

  # Infer.numeric_con?/1
  pub def numeric_con?(p0 Tuple(Unk0444, String)) Bool := …

  # Infer.occurs?/3
  pub def occurs?(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), i Unk0445, t Tuple(Unk0444, String)) Bool := …

  # Infer.ok_payload/3
  pub def ok_payload(tail_pairs Vec(Unk0483), ctx Map(Unk0458, Unk0457), store Unk0484) Unk0485 := …

  # Infer.parse_type/2
  pub def parse_type(str Unk0486, fmap Map(Unk0488, Unk0487)) Tuple(Unk0444, String) := …

  # Infer.prelude_sigs/0
  pub def prelude_sigs() Unk0478 := …

  # Infer.prime_xmod/2
  pub def prime_xmod(modules Unk0489, stdlib_map Unk0490) Unk0491 := …

  # Infer.put_slot/3
  pub def put_slot(sig Tuple(Unk0492, String), p1 String, ts String) Unk0493 := …

  # Infer.render/3
  pub def render(store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), gmap Map(Unk0471, Unk0470), t Tuple(Unk0444, String)) String := …

  # Infer.render_wp/3
  pub def render_wp(store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), unk_names Map(Unk0494, String), t Tuple(Unk0444, String)) String := …

  # Infer.resolve/2
  pub def resolve(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), p1 Tuple(Unk0444, String)) Tuple(Unk0444, String) := …

  # Infer.resolve_program/2
  pub def resolve_program(sigvars Vec(Unk0495), store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Unk0496 := …

  # Infer.resolve_struct_params/4
  pub def resolve_struct_params(args Unk0497, pvars Unk0498, ctx Map(Unk0458, Unk0457), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))) := …

  # Infer.result_analysis/3
  pub def result_analysis(clause_envs Vec(Unk0499), ctx Map(Unk0458, Unk0457), store Unk0484) Unk0500 := …

  # Infer.result_tag/1
  pub def result_tag(p0 Unk0501) Tuple(Unk0502, Unk0503) := …

  # Infer.sig_of/1
  pub def sig_of(f Unk0504) Unk0505 := …

  # Infer.sigvar_call/5
  pub def sigvar_call(ctx Map(Unk0458, Unk0457), key Unk0506, args Unk0507, env Map(String, Tuple(Unk0444, String)), s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String)))) Unk0508 := …

  # Infer.slot_sig/3
  pub def slot_sig(p0 String, ts String, _ Vec(Unk0509)) Unk0510 := …

  # Infer.store_new/0
  pub def store_new() Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))) := …

  # Infer.tvar?/1
  pub def tvar?(s Unk0488) Unk0511 := …

  # Infer.tvar_name/1
  pub def tvar_name(i Unk0512) Unk0513 := …

  # Infer.unify/3
  pub def unify(s Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), a Tuple(Unk0444, String), b Tuple(Unk0444, String)) Tuple(Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), Unk0448) := …

  # Infer.unk_vars/2
  pub def unk_vars(store Tuple(Unk0446, Map(Unk0445, Tuple(Unk0444, String))), v Tuple(Unk0444, String)) Vec(Unk0514) := …

  # Infer.whole_program/3
  pub def whole_program(modules Vec(Tuple(String, Vec(Unk0515))), stdlib Unk0516, p2 Unk0517) Unk0496 := …

  # Infer.xmod_cache/0
  pub def xmod_cache() Unk0518 := …

  # Interp.concat_chain/1
  pub def concat_chain(parts Vec(Tuple(Unk0519, String))) Tuple(Unk0519, String) := …

  # Interp.int_type?/1
  pub def int_type?(t Vec(Unk0073)) Bool := …

  # Interp.resolve/4
  pub def resolve(p0 Tuple(Unk0192, String), env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), show Unk0271) Sum1 := …

  # Interp.resolve_part/4
  pub def resolve_part(p0 Unk0520, _env Map(Unk0080, Vec(Unk0073)), _ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))), _show Unk0271) Tuple(Unk0521, Unk0522) := …

  # Interp.stringify/3
  pub def stringify(expr Sum1, p1 Vec(Unk0073), _show Unk0271) Tuple(Unk0521, Unk0522) := …

  # JS.all_funcs/1
  pub def all_funcs(prog Map(Unk0523, Vec(Unk0524))) Vec(Unk0524) := …

  # JS.arm_return/3
  pub def arm_return(body Unk0525, p1 Unk0526, i53 Bool) String := …

  # JS.bind_lines/1
  pub def bind_lines(binds Vec(Unk0527)) Vec(String) := …

  # JS.block_return/2
  pub def block_return(p0 Vec(Unk0528), i53 Bool) String := …

  # JS.branch_js/2
  pub def branch_js(p0 Sum1, i53 Bool) String := …

  # JS.case_arm_js/2
  pub def case_arm_js(p0 Unk0529, i53 Bool) String := …

  # JS.clause_js/2
  pub def clause_js(p0 Unk0530, i53 Bool) String := …

  # JS.clause_return/3
  pub def clause_return(src Sum1, params Vec(Unk0531), i53 Bool) String := …

  # JS.cp_lit/2
  pub def cp_lit(cp Unk0532, i53 Bool) String := …

  # JS.dispatcher_js/5
  pub def dispatcher_js(proto Unk0533, method Unk0534, impl_types Vec(Unk0535), reg Unk0536, i53 Bool) String := …

  # JS.expr_js/2
  pub def expr_js(p0 Sum1, i53 Bool) String := …

  # JS.float?/1
  pub def float?(n Unk0537) Bool := …

  # JS.function_js/2
  pub def function_js(p0 Unk0208, _i53 Bool) String := …

  # JS.guarded_return/4
  pub def guarded_return(body Sum1, p1 Unk0538, params Vec(Unk0531), i53 Bool) String := …

  # JS.js_atom/1
  pub def js_atom(name Unk0539) String := …

  # JS.js_guard!/4
  pub def js_guard!(type String, proto Unk0540, reg Unk0541, i53 Unk0542) Unk0543 := …

  # JS.js_number_int?/1
  pub def js_number_int?(t Unk0544) Bool := …

  # JS.js_str/1
  pub def js_str(s Unk0539) String := …

  # JS.lit_js/2
  pub def lit_js(v Unk0539, i53 Bool) String := …

  # JS.mangle/3
  pub def mangle(proto Unk0545, type Unk0546, method Unk0547) String := …

  # JS.match_elems/3
  pub def match_elems(es Unk0548, acc String, i53 Bool) Unk0549 := …

  # JS.num_js/2
  pub def num_js(n Unk0537, i53 Bool) String := …

  # JS.paren/2
  pub def paren(e Unk0550, i53 Unk0551) String := …

  # JS.pascal?/1
  pub def pascal?(s Unk0552) Bool := …

  # JS.pat_match/3
  pub def pat_match(p0 Sum2, _acc String, _i53 Bool) Tuple(Vec(String), Vec(Tuple(Unk0553, String))) := …

  # JS.program_number_mode?/1
  pub def program_number_mode?(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Bool := …

  # JS.protocol_dispatchers_js/2
  pub def protocol_dispatchers_js(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011)))), i53 Bool) String := …

  # JS.reject_mixed_int_mode!/1
  pub def reject_mixed_int_mode!(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0554 := …

  # JS.reject_wide_int!/2
  pub def reject_wide_int!(name Unk0555, p1 Unk0556) Unk0557 := …

  # JS.split_top_commas/1
  pub def split_top_commas(s String) Vec(Unk0069) := …

  # JS.stmt_js/2
  pub def stmt_js(p0 Unk0558, i53 Bool) String := …

  # JS.stmt_return/2
  pub def stmt_return(p0 Unk0559, i53 Unk0560) String := …

  # JS.struct_name_set/1
  pub def struct_name_set(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0561 := …

  # JS.sum_ctor_map/1
  pub def sum_ctor_map(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0562 := …

  # JS.sum_guard_js/1
  pub def sum_guard_js(ctors Vec(Unk0563)) String := …

  # JVM.all_funcs/1
  pub def all_funcs(prog Map(Unk0565, Vec(Unk0564))) Vec(Unk0564) := …

  # JVM.all_types/1
  pub def all_types(prog Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Map(Unk0010, Vec(Unk0011))) := …

  # JVM.bind_str/1
  pub def bind_str(p0 Vec(Unk0566)) String := …

  # JVM.block_value/1
  pub def block_value(p0 Vec(Unk0528)) String := …

  # JVM.branch_kt/1
  pub def branch_kt(p0 Sum1) String := …

  # JVM.case_arms/2
  pub def case_arms(arms Unk0567, acc String) Tuple(Vec(Unk0569), Unk0568) := …

  # JVM.clause_lines/1
  pub def clause_lines(p0 Vec(Unk0570)) Tuple(String, Bool) := …

  # JVM.clause_match/1
  pub def clause_match(pats Unk0571) Unk0572 := …

  # JVM.clause_value/2
  pub def clause_value(src Sum1, params Vec(Unk0531)) String := …

  # JVM.closed_or_cond/3
  pub def closed_or_cond(p0 Vec(Unk0573), line String, _rest Vec(Unk0570)) Tuple(String, Bool) := …

  # JVM.expr_kt/1
  pub def expr_kt(p0 Sum1) String := …

  # JVM.function_kt/1
  pub def function_kt(p0 Unk0574) String := …

  # JVM.guarded_arm/2
  pub def guarded_arm(body_kt String, p1 Unk0575) String := …

  # JVM.guarded_return/3
  pub def guarded_return(body Unk0576, p1 Unk0577, params Vec(Unk0578)) String := …

  # JVM.kotlin_module/2
  pub def kotlin_module(src String, p1 Unk0579) String := …

  # JVM.kt_str/1
  pub def kt_str(s Unk0580) String := …

  # JVM.kt_type/1
  pub def kt_type(p0 String) Unk0581 := …

  # JVM.lit_kt/1
  pub def lit_kt(v Unk0580) String := …

  # JVM.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Tuple(Vec(String), Vec(Tuple(Unk0582, String))) := …

  # JVM.prepend_if/3
  pub def prepend_if(tests Vec(Unk0573), line String, rest Vec(Unk0570)) Tuple(String, Bool) := …

  # JVM.run_or_cond/3
  pub def run_or_cond(p0 Vec(Unk0573), line String, rest Vec(Unk0570)) Tuple(String, Bool) := …

  # JVM.stmt_kt/1
  pub def stmt_kt(p0 Unk0583) String := …

  # JVM.stmt_value/1
  pub def stmt_value(p0 Unk0584) String := …

  # JVM.sum_decl/1
  pub def sum_decl(t Unk0585) String := …

  # JVM.to_jar/3
  pub def to_jar(src String, jar_path String, p2 Unk0586) Unk0587 := …

  # JVM.variant_decl/2
  pub def variant_decl(p0 Unk0588, tname Unk0589) String := …

  # Lexer.binify/1
  pub def binify(acc Vec(String)) Unk0590 := …

  # Lexer.capture_hole/3
  pub def capture_hole(p0 String, _d Int53, _acc Vec(String)) Tuple(Unk0590, Unk0591) := …

  # Lexer.char_escape/1
  pub def char_escape(p0 Unk0592) Tuple(Int53, Unk0593) := …

  # Lexer.close_char/1
  pub def close_char(p0 String) Unk0594 := …

  # Lexer.collapse_nl/1
  pub def collapse_nl(tokens Unk0595) Unk0596 := …

  # Lexer.detokenize/2
  pub def detokenize(tokens Unk0597, p1 Unk0598) Unk0599 := …

  # Lexer.escape_str/1
  pub def escape_str(s Unk0600) String := …

  # Lexer.expr_tokens/1
  pub def expr_tokens(src Sum1) Vec(Vec(Vec(Unk0601))) := …

  # Lexer.lex/2
  pub def lex(str String, acc Vec(Tuple(Unk0602, String))) Unk0603 := …

  # Lexer.lex_char/1
  pub def lex_char(p0 String) Tuple(Unk0604, Unk0594) := …

  # Lexer.lex_parts/3
  pub def lex_parts(p0 String, _lit Vec(String), _parts Vec(Tuple(Unk0605, Unk0590))) Tuple(Vec(Tuple(Unk0605, Unk0590)), Unk0606) := …

  # Lexer.lex_string_token/1
  pub def lex_string_token(str String) Tuple(Tuple(Unk0607, Vec(Unk0609)), Unk0608) := …

  # Lexer.parse_hex!/1
  pub def parse_hex!(hex Unk0593) Int53 := …

  # Lexer.punct/1
  pub def punct(str String) Option(Unk0610) := …

  # Lexer.string_token/1
  pub def string_token(parts Vec(Unk0609)) Tuple(Unk0607, Vec(Unk0609)) := …

  # Lexer.strip_trivia/1
  pub def strip_trivia(tokens Unk0611) Unk0612 := …

  # Lexer.take_comment/1
  pub def take_comment(str String) Tuple(Unk0613, String) := …

  # Lexer.take_hex/2
  pub def take_hex(str Unk0614, max Int53) Tuple(String, Unk0614) := …

  # Lexer.take_hex/3
  pub def take_hex(p0 Unk0614, max Int53, acc String) Tuple(String, Unk0614) := …

  # Lexer.tok_str/2
  pub def tok_str(p0 Unk0615, nl_as String) String := …

  # Lexer.tokenize/1
  pub def tokenize(src Unk0616) Unk0617 := …

  # Lexer.tokenize_trivia/1
  pub def tokenize_trivia(src String) Unk0603 := …

  # Lexer.word/1
  pub def word(w String) Tuple(Unk0602, String) := …

  # Livebook.eval/1
  pub def eval(source Unk0618) Unk0619 := …

  # Livebook.output/1
  pub def output(p0 Vec(String)) Unk0619 := …

  # Livebook.reset/0
  pub def reset() Unk0620 := …

  # Livebook.run/2
  pub def run(session Unk0621, source Unk0618) Tuple(Unk0622, Unk0621) := …

  # Livebook.session_pid/0
  pub def session_pid() Unk0623 := …

  # Lower.add_list_elem_vars/2
  pub def add_list_elem_vars(acc Unk0624, p1 Unk0625) Unk0624 := …

  # Lower.add_var/2
  pub def add_var(acc Unk0624, p1 Unk0626) Unk0624 := …

  # Lower.all_pat_vars/1
  pub def all_pat_vars(p0 Sum2) Vec(Unk0627) := …

  # Lower.arm_rebinds/3
  pub def arm_rebinds(pats Unk0628, iso Unk0629, used Unk0630) Vec(Unk0631) := …

  # Lower.assoc/1
  pub def assoc(op String) Unk0632 := …

  # Lower.body_ast/2
  pub def body_ast(src Unk0633, ctx Unk0634) Unk0635 := …

  # Lower.borrow_arg/5
  pub def borrow_arg(a Tuple(Unk0192, String), pt String, funs Map(Unk0636, Unk0637), borrowed Option(Unk0638), ec Unk0639) Unk0640 := …

  # Lower.borrow_value/2
  pub def borrow_value(p0 Tuple(Unk0192, String), _borrowed Option(Unk0638)) Tuple(Unk0192, String) := …

  # Lower.borrowed_in_pat/2
  pub def borrowed_in_pat(p0 Sum2, p1 Bool) Vec(Unk0641) := …

  # Lower.borrowed_vars/2
  pub def borrowed_vars(params Unk0642, pats Unk0643) Option(Unk0644) := …

  # Lower.build_env/3
  pub def build_env(types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Unk0645), ranges Vec(Unk0646)) Unk0647 := …

  # Lower.build_meta/1
  pub def build_meta(types Vec(Map(Unk0010, Vec(Unk0011)))) Unk0648 := …

  # Lower.build_struct_meta/1
  pub def build_struct_meta(structs Vec(Map(Unk0010, Vec(Unk0011)))) Unk0649 := …

  # Lower.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Lower.case_guard/3
  pub def case_guard(p0 Sum1, _ Unk0650, _ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.catchall_pat?/1
  pub def catchall_pat?(p0 Sum2) Bool := …

  # Lower.char_vars/2
  pub def char_vars(params Unk0653, pats Unk0654) Unk0655 := …

  # Lower.check!/2
  pub def check!(p0 Map(Unk0656, Vec(Unk0011)), _env Unk0647) Unk0657 := …

  # Lower.coerce_string_ast/2
  pub def coerce_string_ast(p0 Sum1, ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.coerce_string_branch/2
  pub def coerce_string_branch(p0 Sum1, ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.collect_ids/2
  pub def collect_ids(p0 Vec(Unk0658), acc Unk0630) Unk0630 := …

  # Lower.collect_owned_field_vars/3
  pub def collect_owned_field_vars(p0 Unk0659, ctx Map(Unk0660, Unk0661), acc Unk0662) Unk0662 := …

  # Lower.compile/5
  pub def compile(types Vec(Map(Unk0010, Vec(Unk0011))), func Map(Unk0656, Vec(Unk0011)), p2 Unk0663, p3 Unk0664, p4 Unk0317) Unk0243 := …

  # Lower.compile_beam/4
  pub def compile_beam(types Vec(Map(Unk0010, Vec(Unk0011))), func Map(Unk0656, Vec(Unk0011)), p2 Unk0665, p3 Unk0666) Unk0243 := …

  # Lower.compile_elixir/4
  pub def compile_elixir(types Vec(Map(Unk0010, Vec(Unk0011))), func Map(Unk0656, Vec(Unk0011)), p2 Unk0667, p3 Unk0668) Unk0243 := …

  # Lower.compile_module/1
  pub def compile_module(p0 Unk0669) Unk0243 := …

  # Lower.compile_module_beam/1
  pub def compile_module_beam(p0 Unk0670) Unk0243 := …

  # Lower.cons_tail_names/1
  pub def cons_tail_names(p0 Sum2) Vec(Unk0671) := …

  # Lower.cons_tail_rebinds/1
  pub def cons_tail_rebinds(p0 Sum2) Vec(String) := …

  # Lower.const_set/1
  pub def const_set(consts Vec(Unk0672)) Unk0673 := …

  # Lower.core_pat_ex/1
  pub def core_pat_ex(surface Sum2) String := …

  # Lower.core_pat_rs/2
  pub def core_pat_rs(surface Sum2, meta Unk0674) String := …

  # Lower.core_pat_vars/1
  pub def core_pat_vars(p0 Sum2) Vec(Unk0675) := …

  # Lower.ctx/4
  pub def ctx(meta Unk0648, smeta Unk0649, cset Unk0673, p3 Unk0676) Map(Unk0660, Unk0661) := …

  # Lower.deref_ids/2
  pub def deref_ids(ast Tuple(Unk0677, String), p1 Vec(Unk0678)) Tuple(Unk0677, String) := …

  # Lower.disp/2
  pub def disp(p0 String, p1 Unk0650) String := …

  # Lower.elixir_clauses/3
  pub def elixir_clauses(func Map(Unk0656, Vec(Unk0011)), ctx Unk0679, def_kw String) String := …

  # Lower.emit/3
  pub def emit(p0 Sum1, _t Unk0650, _ec Tuple(Unk0651, Unk0652)) Tuple(String, Int53) := …

  # Lower.emit_ast/2
  pub def emit_ast(ast Sum1, target Unk0650) Unk0680 := …

  # Lower.emit_block/3
  pub def emit_block(p0 Sum1, p1 Unk0650, _ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.emit_ctx/1
  pub def emit_ctx(p0 Unk0681) Tuple(Unk0683, Unk0682) := …

  # Lower.emit_expr/2
  pub def emit_expr(src Sum1, target Unk0650) Unk0684 := …

  # Lower.enum_generics/2
  pub def enum_generics(name Unk0685, parametric Map(Unk0685, Vec(Unk0686))) String := …

  # Lower.ex_const/2
  pub def ex_const(c Unk0672, ctx Unk0679) String := …

  # Lower.ex_doc/2
  pub def ex_doc(p0 Vec(Unk0011), _attr String) String := …

  # Lower.ex_struct/1
  pub def ex_struct(s Unk0687) String := …

  # Lower.ex_typespec/1
  pub def ex_typespec(t Map(Unk0688, Vec(Unk0011))) String := …

  # Lower.ex_use/1
  pub def ex_use(p0 Unk0689) String := …

  # Lower.flatten_concat/1
  pub def flatten_concat(p0 Sum1) Vec(Sum1) := …

  # Lower.fn_all_tvars/3
  pub def fn_all_tvars(func Map(Unk0656, Vec(Unk0011)), pinst Unk0690, ec Tuple(Unk0692, Unk0691)) Vec(Unk0011) := …

  # Lower.guard_kw/1
  pub def guard_kw(p0 Unk0650) String := …

  # Lower.guard_str/4
  pub def guard_str(c Map(Unk0693, Sum1), target Unk0650, ec Tuple(Unk0651, Unk0652), p3 Unk0694) String := …

  # Lower.impl_param/2
  pub def impl_param(p0 Unk0695, rust_type String) String := …

  # Lower.infer_concrete_params/3
  pub def infer_concrete_params(func Map(Unk0656, Vec(Unk0011)), params Vec(Unk0696), ec Tuple(Unk0692, Unk0691)) Vec(String) := …

  # Lower.infer_tvar_binding/2
  pub def infer_tvar_binding(p0 Unk0697, ec Unk0698) Unk0699 := …

  # Lower.insert_borrows/4
  pub def insert_borrows(p0 Sum1, funs Map(Unk0636, Unk0637), ec Unk0639, borrowed Option(Unk0638)) Tuple(Unk0192, String) := …

  # Lower.iso_cons_positions/1
  pub def iso_cons_positions(func Map(Unk0656, Vec(Unk0011))) Unk0629 := …

  # Lower.list_rpat?/1
  pub def list_rpat?(p0 Unk0700) Bool := …

  # Lower.member_scan/3
  pub def member_scan(p0 Vec(Unk0701), _name Vec(Unk0702), _prev Bool) Bool := …

  # Lower.module_elixir/1
  pub def module_elixir(p0 Unk0703) String := …

  # Lower.module_rust/1
  pub def module_rust(p0 Unk0704) String := …

  # Lower.name_type/1
  pub def name_type(p Unk0069) Tuple(String, String) := …

  # Lower.ofb/3
  pub def ofb(p0 Vec(Unk0705), ctx Map(Unk0660, Unk0661), acc Unk0662) Unk0662 := …

  # Lower.owned_arg?/2
  pub def owned_arg?(p0 Tuple(Unk0192, String), _funs Map(Unk0636, Unk0637)) Bool := …

  # Lower.owned_field_binders/2
  pub def owned_field_binders(ast Vec(Unk0705), ctx Map(Unk0660, Unk0661)) Unk0662 := …

  # Lower.owned_field_var?/2
  pub def owned_field_var?(p0 Tuple(Unk0192, String), ec Unk0639) Bool := …

  # Lower.owned_scrut?/2
  pub def owned_scrut?(p0 Unk0706, _ctx Map(Unk0660, Unk0661)) Bool := …

  # Lower.owned_str_arg/1
  pub def owned_str_arg(s Unk0707) Unk0708 := …

  # Lower.p/4
  pub def p(node Sum1, ctx Int53, t Unk0650, ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.pair_inst/2
  pub def pair_inst(func Map(Unk0656, Vec(Unk0011)), ec Tuple(Unk0692, Unk0691)) Unk0690 := …

  # Lower.param_rtypes/2
  pub def param_rtypes(name Unk0636, funs Map(Unk0636, Unk0637)) Vec(String) := …

  # Lower.parametric_param_map/1
  pub def parametric_param_map(types Vec(Map(Unk0010, Vec(Unk0011)))) Unk0709 := …

  # Lower.parametric_used?/2
  pub def parametric_used?(func Map(Unk0656, Vec(Unk0011)), name Unk0710) Bool := …

  # Lower.pascal?/1
  pub def pascal?(s Unk0711) Bool := …

  # Lower.pat_ex/1
  pub def pat_ex(p0 Sum2) String := …

  # Lower.pat_rs/2
  pub def pat_rs(p0 Sum2, _ Unk0674) String := …

  # Lower.pcommas/1
  pub def pcommas(s String) Vec(Unk0069) := …

  # Lower.pipe_to_call/2
  pub def pipe_to_call(l Unk0712, p1 Sum1) Sum1 := …

  # Lower.proto_method_traits/1
  pub def proto_method_traits(protocols Vec(Map(Unk0010, Vec(Unk0011)))) Unk0713 := …

  # Lower.pub_sig_type_names/1
  pub def pub_sig_type_names(funcs Unk0714) Unk0715 := …

  # Lower.ref_type/2
  pub def ref_type(p0 String, self_repr Unk0716) String := …

  # Lower.resolve_consts/2
  pub def resolve_consts(p0 Sum1, cset Unk0717) Tuple(Unk0192, String) := …

  # Lower.resolve_rust_pats/2
  pub def resolve_rust_pats(p0 Sum1, meta Unk0674) Tuple(Unk0192, String) := …

  # Lower.resolve_structs/2
  pub def resolve_structs(p0 Sum1, smeta Unk0718) Tuple(Unk0192, String) := …

  # Lower.resolve_variants/2
  pub def resolve_variants(p0 Sum1, meta Map(Unk0720, Option(Unk0719))) Tuple(Unk0192, String) := …

  # Lower.rest_pat_rs/1
  pub def rest_pat_rs(p0 Sum2) String := …

  # Lower.result_parts/1
  pub def result_parts(ret String) Tuple(Unk0721, String) := …

  # Lower.result_payload/3
  pub def result_payload(val Sum1, string? Bool, ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.rewrite_proto_calls/2
  pub def rewrite_proto_calls(p0 Vec(Unk0722), methods Unk0723) Vec(Unk0722) := …

  # Lower.rpat/1
  pub def rpat(p0 Sum2) String := …

  # Lower.rs_doc/2
  pub def rs_doc(p0 Vec(Unk0011), _prefix String) String := …

  # Lower.rust_arm_body/2
  pub def rust_arm_body(p0 Sum1, s String) String := …

  # Lower.rust_case/4
  pub def rust_case(scrut Sum1, arms Vec(Unk0724), body_fn Fn(Sum1, String), ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.rust_const/2
  pub def rust_const(c Unk0672, ctx Map(Unk0660, Unk0661)) String := …

  # Lower.rust_enum/3
  pub def rust_enum(t Map(Unk0010, Vec(Unk0011)), p1 String, p2 Unk0709) String := …

  # Lower.rust_fn/4
  pub def rust_fn(p0 Map(Unk0656, Vec(Unk0011)), _ctx Map(Unk0660, Unk0661), vis String, _base_ec Tuple(Unk0683, Unk0682)) String := …

  # Lower.rust_generics/1
  pub def rust_generics(p0 Unk0725) String := …

  # Lower.rust_impl/4
  pub def rust_impl(p0 Map(Unk0010, Vec(Unk0011)), protocols Vec(Map(Unk0010, Vec(Unk0011))), c Map(Unk0660, Unk0661), base_ec Tuple(Unk0683, Unk0682)) String := …

  # Lower.rust_impl_method/6
  pub def rust_impl_method(method Unk0726, sig Unk0727, rust_type String, c Map(Unk0660, Unk0661), copy_recv? Bool, base_ec Tuple(Unk0683, Unk0682)) String := …

  # Lower.rust_lit_type/1
  pub def rust_lit_type(p0 Unk0728) String := …

  # Lower.rust_owned_elem/2
  pub def rust_owned_elem(p0 Sum1, ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.rust_program/1
  pub def rust_program(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) String := …

  # Lower.rust_proto_body/3
  pub def rust_proto_body(src Unk0729, c Map(Unk0730, Unk0731), ec Unk0732) Unk0733 := …

  # Lower.rust_protocols/4
  pub def rust_protocols(protocols Vec(Map(Unk0010, Vec(Unk0011))), impl_decls Vec(Map(Unk0010, Vec(Unk0011))), types Vec(Map(Unk0010, Vec(Unk0011))), structs Vec(Map(Unk0010, Vec(Unk0011)))) Unk0734 := …

  # Lower.rust_scrut/2
  pub def rust_scrut(params Unk0735, iso Unk0629) String := …

  # Lower.rust_struct/2
  pub def rust_struct(s Unk0736, p1 Unk0737) String := …

  # Lower.rust_total_shim?/1
  pub def rust_total_shim?(func Map(Unk0656, Vec(Unk0011))) Bool := …

  # Lower.rust_trait/1
  pub def rust_trait(p0 Unk0738) String := …

  # Lower.rust_use/1
  pub def rust_use(p0 Unk0739) String := …

  # Lower.rustify_parametric/2
  pub def rustify_parametric(rust_type String, pinst Vec(Unk0740)) String := …

  # Lower.scalar_literal?/1
  pub def scalar_literal?(p0 Tuple(Unk0192, String)) Bool := …

  # Lower.sig_param/2
  pub def sig_param(p Unk0069, self_repr Unk0741) String := …

  # Lower.slice_binders/2
  pub def slice_binders(params Unk0742, pats Vec(Sum2)) Unk0662 := …

  # Lower.slice_elem_vars/1
  pub def slice_elem_vars(p0 Sum2) Vec(Unk0743) := …

  # Lower.slice_var?/2
  pub def slice_var?(p0 Sum1, ec Tuple(Unk0651, Unk0652)) Bool := …

  # Lower.str_lit/1
  pub def str_lit(s Unk0744) String := …

  # Lower.strip_prefix/2
  pub def strip_prefix(rest Vec(Unk0745), p1 Vec(Unk0702)) Tuple(Unk0746, Vec(Unk0745)) := …

  # Lower.struct_pairs/4
  pub def struct_pairs(name Unk0747, labels Vec(Unk0748), args Vec(Sum1), smeta Unk0718) Unk0749 := …

  # Lower.subst_assoc/2
  pub def subst_assoc(t String, assoc_rust Vec(Unk0750)) String := …

  # Lower.tail_expr/1
  pub def tail_expr(p0 Unk0751) Unk0751 := …

  # Lower.tail_slice_id?/2
  pub def tail_slice_id?(p0 Sum1, ec Tuple(Unk0651, Unk0652)) Bool := …

  # Lower.to_elixir/4
  pub def to_elixir(func Map(Unk0656, Vec(Unk0011)), types Vec(Map(Unk0010, Vec(Unk0011))), p2 Unk0752, p3 Unk0649) Unk0753 := …

  # Lower.to_rust/6
  pub def to_rust(func Map(Unk0656, Vec(Unk0011)), types Vec(Map(Unk0010, Vec(Unk0011))), meta Unk0648, p3 Unk0754, p4 Unk0649, p5 Unk0755) Unk0756 := …

  # Lower.trait_impl_block/4
  pub def trait_impl_block(protocols Vec(Map(Unk0010, Vec(Unk0011))), impl_decls Vec(Map(Unk0010, Vec(Unk0011))), c Map(Unk0660, Unk0661), base_ec Tuple(Unk0683, Unk0682)) String := …

  # Lower.trait_params/2
  pub def trait_params(param_str String, self_repr Unk0741) String := …

  # Lower.tuple_or_one/2
  pub def tuple_or_one(p0 Vec(Sum2), f Fn(Sum2, String)) String := …

  # Lower.tvar_name?/1
  pub def tvar_name?(t Unk0757) Bool := …

  # Lower.type_idents/1
  pub def type_idents(p0 Unk0758) Vec(Unk0759) := …

  # Lower.type_param_tvars/1
  pub def type_param_tvars(t Unk0760) Unk0761 := …

  # Lower.used_ids/1
  pub def used_ids(ast Vec(Unk0658)) Unk0630 := …

  # Lower.user_type?/2
  pub def user_type?(t Unk0762, ctx Map(Unk0660, Unk0661)) Bool := …

  # Lower.variant_info/2
  pub def variant_info(meta Map(Unk0720, Option(Unk0719)), name Unk0711) Option(Unk0719) := …

  # Lower.variant_lit/2
  pub def variant_lit(info Option(Unk0719), pairs Vec(Unk0763)) Tuple(Unk0192, String) := …

  # Lower.variant_pairs/3
  pub def variant_pairs(info Option(Unk0719), args Vec(Sum1), meta Map(Unk0720, Option(Unk0719))) Vec(Unk0763) := …

  # Lower.widen_char_arith/2
  pub def widen_char_arith(p0 Sum1, cvars Unk0764) Tuple(Unk0192, String) := …

  # Lower.with_chain_rs/4
  pub def with_chain_rs(p0 Vec(Unk0765), body String, _else_rs String, _ec Tuple(Unk0651, Unk0652)) String := …

  # Lower.word_member?/2
  pub def word_member?(str Unk0766, name Unk0710) Bool := …

  # Lower.word_scan/4
  pub def word_scan(p0 Vec(Unk0767), _name Vec(Unk0702), _repl String, _prev Bool) String := …

  # Lower.wrap_char/2
  pub def wrap_char(p0 Tuple(Unk0192, String), _cvars Unk0764) Tuple(Unk0192, String) := …

  # Macro.binders_here/1
  pub def binders_here(p0 Vec(Unk0768)) Vec(Unk0769) := …

  # Macro.build_env/1
  pub def build_env(defs Unk0770) Map(Unk0241, Unk0242) := …

  # Macro.check_portable!/2
  pub def check_portable!(name Unk0771, tmpl Sum1) Unk0772 := …

  # Macro.collect_binders/1
  pub def collect_binders(node Vec(Unk0768)) Vec(Unk0769) := …

  # Macro.do_expand/4
  pub def do_expand(_env Map(Unk0241, Unk0242), _ast Sum1, d Int53, _p Bool) Tuple(Unk0192, String) := …

  # Macro.expand/3
  pub def expand(env Map(Unk0241, Unk0242), ast Sum1, p2 Vec(Tuple(Unk0773, Bool))) Sum1 := …

  # Macro.freshen/2
  pub def freshen(tmpl Vec(Unk0768), params Unk0774) Tuple(Unk0192, Vec(Unk0775)) := …

  # Macro.introduces_failable_bind?/1
  pub def introduces_failable_bind?(node Sum1) Bool := …

  # Macro.map_node/2
  pub def map_node(p0 Sum1, f Fn(Sum1, Tuple(Unk0192, String))) Tuple(Unk0192, String) := …

  # Macro.rename/2
  pub def rename(p0 Vec(Unk0768), ren Map(Unk0776, Vec(Unk0775))) Tuple(Unk0192, Vec(Unk0775)) := …

  # Macro.substitute/2
  pub def substitute(p0 Tuple(Unk0192, Vec(Unk0775)), subst Map(Unk0777, Sum1)) Sum1 := …

  # Macro.walk_for_with/1
  pub def walk_for_with(p0 Sum1) Tuple(Unk0192, String) := …

  # Opaque.do_erase/2
  pub def do_erase(prog Unk0778, ctx Tuple(Unk0779, Unk0780)) Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011)))) := …

  # Opaque.erase/1
  pub def erase(p0 Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Map(Unk0033, Vec(Map(Unk0010, Vec(Unk0011)))) := …

  # Opaque.erase_clause/3
  pub def erase_clause(p0 Unk0781, _ctx Unk0782, _env Unk0783) Clause := …

  # Opaque.erase_const/2
  pub def erase_const(p0 Unk0784, p1 Unk0785) Const := …

  # Opaque.erase_ctx/1
  pub def erase_ctx(all Vec(Unk0786)) Tuple(Unk0779, Unk0780) := …

  # Opaque.erase_func/2
  pub def erase_func(p0 Unk0787, p1 Tuple(Unk0779, Unk0780)) Func := …

  # Opaque.erase_mod/2
  pub def erase_mod(p0 Unk0788, ctx Tuple(Unk0779, Unk0780)) Mod := …

  # Opaque.erase_struct/2
  pub def erase_struct(p0 Unk0789, p1 Tuple(Unk0779, Unk0780)) Struct := …

  # Opaque.erase_type/2
  pub def erase_type(p0 Unk0790, p1 Tuple(Unk0779, Unk0780)) Type := …

  # Opaque.erase_variant/2
  pub def erase_variant(p0 Unk0791, names Unk0792) Variant := …

  # Opaque.opaques/1
  pub def opaques(prog Map(Unk0793, Vec(Unk0786))) Vec(Unk0786) := …

  # Opaque.strip/3
  pub def strip(p0 Vec(Unk0794), p1 Unk0795, env Map(Unk0080, Vec(Unk0073))) Vec(Unk0794) := …

  # Opaque.strip_into/3
  pub def strip_into(ast Vec(Unk0794), ctx Unk0795, env Map(Unk0080, Vec(Unk0073))) Vec(Unk0794) := …

  # Opaque.subst/2
  pub def subst(p0 Option(Unk0796), _names Unk0797) Option(Unk0796) := …

  # Opaque.subst_fix/4
  pub def subst_fix(type Option(Unk0796), _names Unk0797, _re Unk0798, p3 Int53) Option(Unk0796) := …

  # PatternLower.add_struct/3
  pub def add_struct(env Tuple(Unk0368, Map(String, String)), name String, fields Vec(String)) Tuple(Unk0368, Map(String, String)) := …

  # PatternLower.lower/2
  pub def lower(pat Sum2, env Map(Unk0374, Unk0373)) Tuple(Unk0799, Bool) := …

  # PatternLower.lower_clause/2
  pub def lower_clause(p0 Unk0800, env Map(Unk0374, Unk0373)) Unk0372 := …

  # PatternLower.lower_list/3
  pub def lower_list(p0 Vec(Sum2), p1 Sum2, _env Map(Unk0374, Unk0373)) Tuple(Unk0799, Bool) := …

  # PatternLower.lower_many/2
  pub def lower_many(ps Vec(Sum2), env Map(Unk0374, Unk0373)) Unk0801 := …

  # PortAnalysis.analyze/1
  pub def analyze(sources Unk0802) Unk0803 := …

  # PortAnalysis.case_arm_sets/1
  pub def case_arm_sets(ast Unk0804) Vec(Unk0805) := …

  # PortAnalysis.clause_head_sets/1
  pub def clause_head_sets(ast Unk0804) Vec(Unk0805) := …

  # PortAnalysis.cluster_sums/1
  pub def cluster_sums(sets Vec(Unk0806)) Unk0517 := …

  # PortAnalysis.collect_errors/2
  pub def collect_errors(ast Unk0807, acc Unk0808) Unk0808 := …

  # PortAnalysis.collect_groups/1
  pub def collect_groups(p0 Unk0809) Vec(Unk0515) := …

  # PortAnalysis.collect_structs/2
  pub def collect_structs(ast Unk0810, acc Unk0811) Unk0811 := …

  # PortAnalysis.dispatch_sets/1
  pub def dispatch_sets(ast Unk0804) Vec(Unk0806) := …

  # PortAnalysis.error_proposal/1
  pub def error_proposal(p0 Unk0812) Unk0813 := …

  # PortAnalysis.error_shape/1
  pub def error_shape(p0 Unk0814) Tuple(Unk0815, Option(Unk0816)) := …

  # PortAnalysis.errors_section/1
  pub def errors_section(data Unk0817) String := …

  # PortAnalysis.head_name_pats/1
  pub def head_name_pats(p0 Unk0818) Tuple(Unk0820, Vec(Unk0819)) := …

  # PortAnalysis.holes_section/1
  pub def holes_section(data Unk0817) String := …

  # PortAnalysis.module_name/1
  pub def module_name(p0 Unk0821) String := …

  # PortAnalysis.module_report/3
  pub def module_report(file Unk0822, ast Unk0821, src Unk0823) Unk0824 := …

  # PortAnalysis.needs_review?/1
  pub def needs_review?(p0 Unk0825) Bool := …

  # PortAnalysis.param_name_index/1
  pub def param_name_index(mods_groups Vec(Tuple(String, Vec(Unk0515)))) Unk0826 := …

  # PortAnalysis.parse/1
  pub def parse(src Unk0827) Option(Unk0828) := …

  # PortAnalysis.pascal/1
  pub def pascal(atom_str Unk0829) Unk0830 := …

  # PortAnalysis.pattern_structs/1
  pub def pattern_structs(p0 Unk0831) Vec(Unk0832) := …

  # PortAnalysis.reach_note/1
  pub def reach_note(type Unk0833) Unk0834 := …

  # PortAnalysis.short/1
  pub def short(p0 Unk0835) String := …

  # PortAnalysis.sigs_section/1
  pub def sigs_section(data Unk0817) String := …

  # PortAnalysis.src_of/2
  pub def src_of(sources Unk0802, file Unk0836) Unk0823 := …

  # PortAnalysis.summary_section/1
  pub def summary_section(data Unk0817) String := …

  # PortAnalysis.sums_section/1
  pub def sums_section(data Unk0817) String := …

  # PortAnalysis.to_markdown/1
  pub def to_markdown(data Unk0817) Unk0837 := …

  # Pratt.after_paren/2
  pub def after_paren(tokens Vec(Unk0838), p1 Int53) Vec(Unk0838) := …

  # Pratt.assoc/1
  pub def assoc(op String) Unk0839 := …

  # Pratt.climb/3
  pub def climb(lhs Option(Unk0840), tokens Vec(Vec(Vec(Unk0601))), min_bp Int53) Tuple(Option(Unk0840), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.collect_dots/2
  pub def collect_dots(node Tuple(Unk0841, Unk0842), p1 Vec(Vec(Unk0601))) Tuple(Tuple(Unk0841, Unk0842), Vec(Vec(Unk0601))) := …

  # Pratt.desugar_prop/2
  pub def desugar_prop(stmts Vec(Tuple(Unk0843, Unk0844)), depth Int53) Tuple(Unk0845, Vec(Tuple(Unk0843, Unk0844))) := …

  # Pratt.desugar_propagation/1
  pub def desugar_propagation(stmts Vec(Tuple(Unk0843, Unk0844))) Tuple(Unk0845, Vec(Tuple(Unk0843, Unk0844))) := …

  # Pratt.expect_kw/2
  pub def expect_kw(p0 Vec(Vec(Vec(Unk0601))), k String) Vec(Vec(Vec(Unk0601))) := …

  # Pratt.expect_op/2
  pub def expect_op(p0 Vec(Vec(Vec(Unk0601))), o String) Vec(Vec(Vec(Unk0601))) := …

  # Pratt.expect_rbracket/1
  pub def expect_rbracket(p0 Vec(Vec(Vec(Unk0601)))) Vec(Vec(Vec(Unk0601))) := …

  # Pratt.expect_rparen/1
  pub def expect_rparen(p0 Vec(Vec(Vec(Unk0601)))) Vec(Vec(Vec(Unk0601))) := …

  # Pratt.finish_arg/2
  pub def finish_arg(a Unk0846, p1 Vec(Vec(Vec(Unk0601)))) Tuple(Vec(Unk0846), Vec(Vec(Vec(Vec(Unk0601))))) := …

  # Pratt.here/1
  pub def here(p0 Vec(Unk0847)) String := …

  # Pratt.int_of/1
  pub def int_of(n Unk0848) Vec(Tuple(Unk0849, Unk0850)) := …

  # Pratt.lambda_ahead?/1
  pub def lambda_ahead?(p0 Vec(Unk0838)) Bool := …

  # Pratt.level/1
  pub def level(op String) Unk0851 := …

  # Pratt.opinfo/1
  pub def opinfo(op String) Unk0852 := …

  # Pratt.parse/1
  pub def parse(ast Sum1) Sum1 := …

  # Pratt.parse_args/1
  pub def parse_args(p0 Vec(Vec(Vec(Vec(Unk0601))))) Tuple(Vec(Unk0846), Vec(Vec(Vec(Vec(Unk0601))))) := …

  # Pratt.parse_arms/2
  pub def parse_arms(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Unk0853)) Tuple(Vec(Unk0853), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_block/1
  pub def parse_block(tokens Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0845, Vec(Tuple(Unk0843, Unk0844))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_body/1
  pub def parse_body(ast Sum1) Sum1 := …

  # Pratt.parse_capture/1
  pub def parse_capture(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_case/1
  pub def parse_case(tokens Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_expr/2
  pub def parse_expr(tokens Vec(Vec(Vec(Unk0601))), min_bp Int53) Tuple(Option(Unk0840), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_if/1
  pub def parse_if(tokens Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_lambda/1
  pub def parse_lambda(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_list/2
  pub def parse_list(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Unk0855)) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_map/2
  pub def parse_map(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0849, Unk0850))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_param/1
  pub def parse_param(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0857, Option(Unk0856)), Vec(Vec(Unk0601))) := …

  # Pratt.parse_params/1
  pub def parse_params(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Vec(Unk0858), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat/1
  pub def parse_pat(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0859, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat_args/2
  pub def parse_pat_args(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Unk0860)) Tuple(Vec(Unk0860), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat_fields/2
  pub def parse_pat_fields(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0862, Unk0861))) Tuple(Vec(Tuple(Unk0862, Unk0861)), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat_list/2
  pub def parse_pat_list(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Unk0863)) Tuple(Tuple(Unk0859, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat_map/2
  pub def parse_pat_map(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0849, Unk0850))) Tuple(Tuple(Unk0859, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_pat_tuple/2
  pub def parse_pat_tuple(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0849, Unk0850))) Tuple(Tuple(Unk0859, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_path/1
  pub def parse_path(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0841, Unk0842), Vec(Vec(Unk0601))) := …

  # Pratt.parse_pats/1
  pub def parse_pats(str Sum1) Vec(Unk0864) := …

  # Pratt.parse_pats/2
  pub def parse_pats(tokens Vec(Vec(Vec(Unk0601))), acc Vec(Unk0864)) Vec(Unk0864) := …

  # Pratt.parse_postfix/2
  pub def parse_postfix(node Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), p1 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_prefix/1
  pub def parse_prefix(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_primary/1
  pub def parse_primary(p0 Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_sexpr/1
  pub def parse_sexpr(str Sum1) String := …

  # Pratt.parse_stmt/1
  pub def parse_stmt(p0 Vec(Vec(Vec(Vec(Unk0601))))) Tuple(Tuple(Unk0866, Unk0865), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_stmts/2
  pub def parse_stmts(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Unk0867)) Tuple(Vec(Unk0867), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_tuple/2
  pub def parse_tuple(p0 Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0849, Unk0850))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_type/1
  pub def parse_type(p0 Vec(Vec(Vec(Unk0601)))) Tuple(String, Vec(Vec(Unk0601))) := …

  # Pratt.parse_type_args/2
  pub def parse_type_args(tokens Vec(Vec(Unk0601)), acc Vec(Unk0868)) Tuple(Vec(Unk0868), Vec(Vec(Unk0601))) := …

  # Pratt.parse_with/1
  pub def parse_with(tokens Vec(Vec(Vec(Unk0601)))) Tuple(Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.parse_with_clauses/2
  pub def parse_with_clauses(tokens Vec(Vec(Vec(Unk0601))), acc Vec(Tuple(Unk0870, Unk0869))) Tuple(Vec(Tuple(Unk0870, Unk0869)), Vec(Vec(Vec(Unk0601)))) := …

  # Pratt.pascal?/1
  pub def pascal?(s Unk0871) Bool := …

  # Pratt.peek_infix/1
  pub def peek_infix(p0 Vec(Vec(Vec(Unk0601)))) String := …

  # Pratt.same_level_root?/2
  pub def same_level_root?(p0 Option(Unk0840), op String) Bool := …

  # Pratt.sexpr/1
  pub def sexpr(p0 Sum1) String := …

  # Pratt.sexpr_pat/1
  pub def sexpr_pat(p0 Unk0872) String := …

  # Pratt.sexpr_stmt/1
  pub def sexpr_stmt(p0 Unk0873) String := …

  # Pratt.str_interp/1
  pub def str_interp(parts Vec(Unk0874)) Tuple(Unk0854, Vec(Tuple(Unk0849, Unk0850))) := …

  # Pratt.tok_desc/1
  pub def tok_desc(p0 Unk0847) String := …

  # Prelude.with_prelude/1
  pub def with_prelude(types Vec(Map(Unk0010, Vec(Unk0011)))) Vec(Type) := …

  # Prim.names/0
  pub def names() Unk0875 := …

  # Prim.normalize/1
  pub def normalize(p0 Sum1) Sum1 := …

  # Prim.overflow_ops/0
  pub def overflow_ops() Unk0876 := …

  # Protocol.check_assoc!/2
  pub def check_assoc!(protocols Vec(Unk0218), impl_decls Vec(Unk0218)) Unk0877 := …

  # Protocol.check_impl/3
  pub def check_impl(p0 Unk0878, protocols Unk0879, reg Unk0880) Unk0881 := …

  # Protocol.check_no_overlap/3
  pub def check_no_overlap(impls Vec(Unk0882), reg Unk0880, targets Unk0883) Unk0884 := …

  # Protocol.dispatcher/4
  pub def dispatcher(proto Unk0885, sig Unk0886, impls Vec(Unk0882), reg Unk0880) Vec(Unk0887) := …

  # Protocol.dispatcher_params/2
  pub def dispatcher_params(sig_params Unk0888, vars Vec(String)) Unk0889 := …

  # Protocol.expand/5
  pub def expand(protocols Unk0879, impls Vec(Unk0882), p2 Unk0318, p3 Unk0319, p4 Unk0320) Vec(Unk0321) := …

  # Protocol.guard_for!/3
  pub def guard_for!(type String, proto Unk0885, reg Unk0880) Unk0890 := …

  # Protocol.impl_methods/2
  pub def impl_methods(p0 Unk0882, protocols Unk0879) Vec(Unk0321) := …

  # Protocol.mangle/3
  pub def mangle(proto Unk0891, type Unk0892, method Unk0893) String := …

  # Protocol.param_type/1
  pub def param_type(p Unk0894) Unk0895 := …

  # Protocol.registry/2
  pub def registry(types Unk0896, structs Vec(Unk0897)) Unk0880 := …

  # Protocol.runtime_dispatch_target?/1
  pub def runtime_dispatch_target?(p0 Unk0883) Bool := …

  # Protocol.split_commas/1
  pub def split_commas(s String) Vec(Unk0069) := …

  # Protocol.subst_self/2
  pub def subst_self(p0 Unk0898, _type Unk0899) Option(Unk0900) := …

  # Protocol.sum_guard/1
  pub def sum_guard(variants Unk0901) String := …

  # Protocol.tag_disjunction/2
  pub def tag_disjunction(variants Vec(Unk0902), lhs Unk0903) String := …

  # Range.check/3
  pub def check(lo Unk0904, hi Unk0905, a Sum1) Sum1 := …

  # Range.expand_of/2
  pub def expand_of(node Sum1, table Map(Unk0019, Unk0018)) Sum1 := …

  # Range.lit/1
  pub def lit(n Unk0906) Sum1 := …

  # Range.table/1
  pub def table(ranges Vec(Map(Unk0010, Vec(Unk0011)))) Map(Unk0019, Unk0018) := …

  # Range.walk/2
  pub def walk(node Sum1, table Map(Unk0019, Unk0018)) Sum1 := …

  # Reach.all_emittable?/2
  pub def all_emittable?(f Map(Unk0908, Vec(Unk0907)), pctx Unk0909) Bool := …

  # Reach.all_funcs/1
  pub def all_funcs(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Vec(Map(Unk0010, Vec(Unk0011))) := …

  # Reach.analyze/1
  pub def analyze(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0910 := …

  # Reach.atom_prim_blocker/0
  pub def atom_prim_blocker() Unk0911 := …

  # Reach.bare_atom_blocker/0
  pub def bare_atom_blocker() Unk0911 := …

  # Reach.build_default/0
  pub def build_default() Option(Unk0912) := …

  # Reach.builder_tail_ok?/2
  pub def builder_tail_ok?(f Map(Unk0908, Vec(Unk0907)), generics Unk0913) Bool := …

  # Reach.check_contracts/2
  pub def check_contracts(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), p1 Option(Unk0912)) Tuple(Unk0914, String) := …

  # Reach.classify/3
  pub def classify(p0 Sum1, _modnames Unk0915, p2 Tuple(Vec(Unk0911), Unk0916)) Tuple(Vec(Unk0911), Unk0916) := …

  # Reach.collect_ctors/2
  pub def collect_ctors(p0 Sum1, ctors Map(Unk0917, Unk0918)) Vec(Tuple(Unk0920, Unk0919)) := …

  # Reach.conc_erl?/2
  pub def conc_erl?(m String, fun Unk0921) Bool := …

  # Reach.contract_message/1
  pub def contract_message(violations Vec(Unk0922)) String := …

  # Reach.core/2
  pub def core(src Unk0923, parser Fn(Unk0924, Unk0925)) Sum1 := …

  # Reach.ctor_aligned?/2
  pub def ctor_aligned?(p0 Tuple(Unk0920, Unk0919), f Map(Unk0908, Vec(Unk0907))) Bool := …

  # Reach.deep/1
  pub def deep(t Vec(Unk0926)) Vec(Unk0927) := …

  # Reach.emittable_parametric?/1
  pub def emittable_parametric?(t Unk0928) Unk0929 := …

  # Reach.ffi/2
  pub def ffi(construct String, conc? Bool) Unk0911 := …

  # Reach.find_atom_ordering/1
  pub def find_atom_ordering(p0 Vec(Unk0926)) Vec(Unk0927) := …

  # Reach.fixpoint/2
  pub def fixpoint(facts Unk0930, table Map(Unk0931, Unk0932)) Map(Unk0931, Unk0932) := …

  # Reach.fn_type_blocker/0
  pub def fn_type_blocker() Unk0911 := …

  # Reach.func_symbol_violations/1
  pub def func_symbol_violations(f Unk0933) Vec(Unk0927) := …

  # Reach.gate!/1
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0934 := …

  # Reach.gate!/2
  pub def gate!(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), default Option(Unk0912)) Unk0934 := …

  # Reach.int_blocker/0
  pub def int_blocker() Unk0911 := …

  # Reach.js_wide_int?/1
  pub def js_wide_int?(t Unk0935) Bool := …

  # Reach.mix_default/0
  pub def mix_default() Unk0936 := …

  # Reach.parametric_blocker/0
  pub def parametric_blocker() Unk0911 := …

  # Reach.parametric_constructions/2
  pub def parametric_constructions(f Map(Unk0908, Vec(Unk0907)), ctors Map(Unk0917, Unk0918)) Vec(Tuple(Unk0920, Unk0919)) := …

  # Reach.parametric_ctx/2
  pub def parametric_ctx(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))), funs Vec(Map(Unk0010, Vec(Unk0011)))) Unk0909 := …

  # Reach.parametric_rs_ok?/2
  pub def parametric_rs_ok?(f Map(Unk0908, Vec(Unk0907)), pctx Unk0909) Bool := …

  # Reach.parametric_type?/1
  pub def parametric_type?(t Unk0937) Bool := …

  # Reach.pascal?/1
  pub def pascal?(s Unk0938) Bool := …

  # Reach.ref_blocker/0
  pub def ref_blocker() Unk0911 := …

  # Reach.result_value_blocker/0
  pub def result_value_blocker() Unk0911 := …

  # Reach.scan/3
  pub def scan(p0 Sum1, modnames Unk0915, p2 Tuple(Vec(Unk0911), Unk0916)) Tuple(Vec(Unk0911), Unk0916) := …

  # Reach.scan_func/3
  pub def scan_func(f Map(Unk0908, Vec(Unk0907)), modnames Unk0915, pctx Unk0909) Tuple(Vec(Unk0911), Unk0916) := …

  # Reach.sig_idents/1
  pub def sig_idents(f Map(Unk0940, Vec(Unk0939))) Unk0941 := …

  # Reach.sig_uses_fn_type?/1
  pub def sig_uses_fn_type?(f Map(Unk0908, Vec(Unk0907))) Bool := …

  # Reach.symbol_lint!/1
  pub def symbol_lint!(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk0942 := …

  # Reach.tail_calls_generic?/2
  pub def tail_calls_generic?(p0 Unk0943, generics Unk0913) Bool := …

  # Reach.targets/0
  pub def targets() Unk0944 := …

  # Reach.tvar?/1
  pub def tvar?(t Unk0945) Unk0946 := …

  # Reach.type_has_tvar?/1
  pub def type_has_tvar?(t Unk0947) Bool := …

  # Reach.type_idents/1
  pub def type_idents(t Unk0947) Vec(Unk0948) := …

  # Reach.uses_parametric?/2
  pub def uses_parametric?(f Map(Unk0908, Vec(Unk0907)), names Unk0949) Bool := …

  # Reach.validate_default/1
  pub def validate_default(p0 Option(Unk0912)) Option(Unk0912) := …

  # Reach.wide_prim_blocker/0
  pub def wide_prim_blocker() Unk0911 := …

  # Reach.width_blocker/0
  pub def width_blocker() Unk0911 := …

  # Repl.accumulate_line/2
  pub def accumulate_line(line String, p1 Unk0950) Tuple(Vec(String), String) := …

  # Repl.bind_env/2
  pub def bind_env(binds Vec(Unk0951), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Map(Unk0080, Vec(Unk0073)) := …

  # Repl.bind_with_type/4
  pub def bind_with_type(s Session, input Sum1, name Sum1, type Option(Unk0952)) Tuple(Tuple(Unk0953, String), Session) := …

  # Repl.candidate_pool/2
  pub def candidate_pool(p0 Unk0954, _s Session) Vec(Unk0955) := …

  # Repl.common_prefix/2
  pub def common_prefix(a Unk0956, b Unk0957) String := …

  # Repl.common_prefix/3
  pub def common_prefix(p0 Unk0956, p1 Unk0957, acc String) String := …

  # Repl.complete/2
  pub def complete(before_cursor Unk0958, p1 Unk0959) Tuple(Vec(Unk0960), String) := …

  # Repl.continuation/2
  pub def continuation(_word String, p1 Vec(Unk0960)) String := …

  # Repl.decl_names/1
  pub def decl_names(input String) Unk0961 := …

  # Repl.describe/1
  pub def describe(p0 Unk0962) Unk0963 := …

  # Repl.eval/2
  pub def eval(p0 Unk0964, input String) Unk0965 := …

  # Repl.eval_bind/4
  pub def eval_bind(s Session, input Sum1, name Sum1, rhs Sum1) Tuple(Tuple(Unk0953, String), Session) := …

  # Repl.eval_decl/2
  pub def eval_decl(s Tuple(Unk0967, Vec(Tuple(Unk0961, Unk0966))), input String) Tuple(Tuple(Unk0969, Unk0961), Unk0968) := …

  # Repl.eval_expr/2
  pub def eval_expr(s Session, input Sum1) Tuple(Tuple(Unk0953, String), Session) := …

  # Repl.eval_stmt/2
  pub def eval_stmt(s Session, input Sum1) Tuple(Tuple(Unk0953, String), Session) := …

  # Repl.flush_entries/1
  pub def flush_entries(p0 Unk0970) Vec(Unk0971) := …

  # Repl.infer_or_unknown/3
  pub def infer_or_unknown(ast Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Vec(Unk0073) := …

  # Repl.info/1
  pub def info(p0 Session) Unk0972 := …

  # Repl.longest_common_prefix/1
  pub def longest_common_prefix(p0 Vec(Unk0973)) Unk0973 := …

  # Repl.module_name/1
  pub def module_name(p0 Session) Unk0008 := …

  # Repl.program/3
  pub def program(units Vec(Tuple(Unk0961, Unk0966)), binds Vec(Tuple(Sum1, Unk0974)), expr_src Sum1) String := …

  # Repl.reload/2
  pub def reload(s Tuple(Unk0967, Vec(Tuple(Unk0961, Unk0966))), src String) Unk0008 := …

  # Repl.render/1
  pub def render(p0 Unk0975) String := …

  # Repl.run/4
  pub def run(s Tuple(Unk0967, Vec(Tuple(Unk0961, Unk0966))), binds Vec(Tuple(Sum1, Unk0974)), units Vec(Tuple(Unk0961, Unk0966)), expr_src Sum1) Tuple(Unk0977, Unk0976) := …

  # Repl.safe_decl/1
  pub def safe_decl(units Vec(Tuple(Unk0961, Unk0966))) Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011)))) := …

  # Repl.safe_infer/3
  pub def safe_infer(ast Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0952) := …

  # Repl.safe_infer_input/3
  pub def safe_infer_input(input Sum1, env Map(Unk0080, Vec(Unk0073)), ic Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073)))) Option(Unk0952) := …

  # Repl.safe_parse_body/1
  pub def safe_parse_body(input Sum1) Tuple(Unk0978, Sum1) := …

  # Repl.scan_count/2
  pub def scan_count(input String, regex Unk0979) Unk0980 := …

  # Repl.session_ic/1
  pub def session_ic(p0 Session) Map(Unk0075, Map(Vec(Unk0073), Vec(Unk0073))) := …

  # Repl.split_entries/1
  pub def split_entries(source Unk0981) Unk0982 := …

  # Repl.trailing_token/1
  pub def trailing_token(text Unk0958) String := …

  # Repl.type_of/2
  pub def type_of(p0 Unk0983, input Sum1) Option(Unk0952) := …

  # Repl.units_src/1
  pub def units_src(units Vec(Tuple(Unk0961, Unk0966))) String := …

  # Repl.vocabulary/0
  pub def vocabulary() Vec(Unk0984) := …

  # SelfHost.badge/1
  pub def badge(p0 Unk0985) String := …

  # SelfHost.composition/0
  pub def composition() Unk0986 := …

  # SelfHost.count/1
  pub def count(status Unk0987) Int53 := …

  # SelfHost.evidence/1
  pub def evidence(p0 Unk0988) String := …

  # SelfHost.evidence_files/0
  pub def evidence_files() Unk0989 := …

  # SelfHost.external_host_calls/1
  pub def external_host_calls(prog Map(Unk0991, Vec(Map(Unk0992, Vec(Unk0990))))) Vec(Unk0993) := …

  # SelfHost.ffi_in_file/1
  pub def ffi_in_file(path Unk0994) Unk0995 := …

  # SelfHost.ffi_ledger/0
  pub def ffi_ledger() Unk0996 := …

  # SelfHost.passes/0
  pub def passes() Unk0997 := …

  # SelfHost.percent/0
  pub def percent() Unk0998 := …

  # SelfHost.selfhost_files/0
  pub def selfhost_files() Unk0999 := …

  # SelfHost.selfhost_module_names/0
  pub def selfhost_module_names() Unk1000 := …

  # SelfHost.sibling_compose_call?/2
  pub def sibling_compose_call?(construct Unk1001, siblings Unk1002) Bool := …

  # SelfHost.stages/0
  pub def stages() Unk1003 := …

  # SelfHost.status_markdown/1
  pub def status_markdown(stages Vec(Unk1004)) String := …

  # Shadow.ded_bind/5
  pub def ded_bind(n Unk1005, t Bool, e Vec(Unk1006), p3 Unk1007, fresh Fn(Unk1009, Unk1010, Unk1008)) Unk1011 := …

  # Shadow.ded_block/4
  pub def ded_block(stmts Vec(Unk1012), r Map(Unk1014, Unk1013), ver Unk1015, fresh Fn(Unk1009, Unk1010, Unk1008)) Vec(Unk0528) := …

  # Shadow.ded_expr/3
  pub def ded_expr(p0 Vec(Unk1006), r Map(Unk1014, Unk1013), _fresh Fn(Unk1009, Unk1010, Unk1008)) Vec(Unk1006) := …

  # Shadow.dedup/3
  pub def dedup(stmts Vec(Unk1012), params Vec(Unk0531), fresh Fn(Unk1009, Unk1010, Unk1008)) Vec(Unk0528) := …

  # Shadow.pat_var_names/1
  pub def pat_var_names(p0 Sum2) Vec(Unk1016) := …

  # ShowStdlib.module/0
  pub def module() Unk0262 := …

  # Test.compile!/2
  pub def compile!(src String, mod Unk0008) Unk0008 := …

  # Test.default_mod/1
  pub def default_mod(src String) Unk1017 := …

  # Test.run/2
  pub def run(src String, p1 Unk1018) Unk1019 := …

  # Test.run_one/2
  pub def run_one(mod Unk0008, name Unk1020) Bool := …

  # Test.rust/1
  pub def rust(src String) Unk1021 := …

  # Test.tests/1
  pub def tests(src String) Vec(Unk1022) := …

  # Tour.build_cell/1
  pub def build_cell(p0 Unk1023) Unk1024 := …

  # Tour.build_reach_example/1
  pub def build_reach_example(p0 Unk1025) Unk1026 := …

  # Tour.elixir_module/1
  pub def elixir_module(src String) Unk1027 := …

  # Tour.encode/2
  pub def encode(map Vec(Unk1028), indent Int53) String := …

  # Tour.encode_string/1
  pub def encode_string(s Vec(Unk1028)) String := …

  # Tour.generate/0
  pub def generate() Unk1029 := …

  # Tour.reach_map/1
  pub def reach_map(prog Map(Unk0022, Vec(Map(Unk0010, Vec(Unk0011))))) Unk1030 := …

  # Tour.to_json/0
  pub def to_json() Unk1031 := …

  # Transpile.add_clause/2
  pub def add_clause(open Tuple(Unk1032, Vec(Unk1033)), clause Unk1033) Option(Unk1034) := …

  # Transpile.block_stmts/1
  pub def block_stmts(p0 Unk1035) Vec(Unk1035) := …

  # Transpile.build_clause/2
  pub def build_clause(head Unk1036, kw Unk1037) Unk1033 := …

  # Transpile.case_arm/1
  pub def case_arm(p0 Unk1038) String := …

  # Transpile.classify/1
  pub def classify(p0 String) Tuple(Unk1039, String) := …

  # Transpile.close_group/2
  pub def close_group(acc Vec(Unk1040), p1 Unk1040) Vec(Unk1040) := …

  # Transpile.def_groups/1
  pub def def_groups(stmts Vec(String)) Vec(Unk1040) := …

  # Transpile.escape/1
  pub def escape(s Unk1041) Unk1042 := …

  # Transpile.escape_lit/1
  pub def escape_lit(s Unk1043) String := …

  # Transpile.flush/2
  pub def flush(p0 Unk1044, _sigmap Map(Tuple(Unk1045, Unk1046), Bool)) Vec(String) := …

  # Transpile.hole_sig?/1
  pub def hole_sig?(p0 Unk1047) Bool := …

  # Transpile.infer_program/1
  pub def infer_program(ast Unk1048) Tuple(Unk1049, Vec(String)) := …

  # Transpile.infer_report/1
  pub def infer_report(source Unk1050) Unk1051 := …

  # Transpile.infer_sigs/1
  pub def infer_sigs(p0 Unk1048) Unk1049 := …

  # Transpile.inferred/1
  pub def inferred(source Unk0823) Tuple(Unk1049, Vec(String)) := …

  # Transpile.max_placeholder/1
  pub def max_placeholder(p0 Vec(Unk1052)) Int53 := …

  # Transpile.mod_str/1
  pub def mod_str(p0 Unk1053) String := …

  # Transpile.module_groups/1
  pub def module_groups(src Unk1054) Tuple(String, Unk1055) := …

  # Transpile.moduledoc_lines/1
  pub def moduledoc_lines(text Unk1056) Vec(String) := …

  # Transpile.name_str/1
  pub def name_str(n Unk1057) Unk1058 := …

  # Transpile.new_group/3
  pub def new_group(vis Unk1059, clause Unk1033, doc Option(Unk1060)) Option(Unk1034) := …

  # Transpile.one_line/1
  pub def one_line(s Unk1061) Unk1062 := …

  # Transpile.prime_xmod/1
  pub def prime_xmod(sources Unk1063) Unk1064 := …

  # Transpile.rank/1
  pub def rank(entries Unk1065) Unk1066 := …

  # Transpile.render_clause/2
  pub def render_clause(kw String, c Unk1067) String := …

  # Transpile.render_items/2
  pub def render_items(stmts Vec(String), sigmap Map(Tuple(Unk1045, Unk1046), Bool)) Vec(String) := …

  # Transpile.same_group?/3
  pub def same_group?(open Unk1068, vis Unk1069, clause Unk1033) Bool := …

  # Transpile.short_name/1
  pub def short_name(p0 Unk1053) String := …

  # Transpile.sibling_module?/2
  pub def sibling_module?(p0 Unk1070, m String) Bool := …

  # Transpile.simple?/1
  pub def simple?(p0 Vec(Unk1071)) Bool := …

  # Transpile.snippet/1
  pub def snippet(node Unk1053) String := …

  # Transpile.stdlib_map/0
  pub def stdlib_map() Unk0516 := …

  # Transpile.string_part/1
  pub def string_part(s Unk1043) Tuple(Unk1072, String) := …

  # Transpile.string_parts/1
  pub def string_parts(segments Unk1073) Unk1074 := …

  # Transpile.subst_ph/2
  pub def subst_ph(p0 Vec(Unk1075), ps Unk1076) Vec(Unk1075) := …

  # Transpile.toplevel/3
  pub def toplevel(p0 Unk1077, sigmap Unk1078, types Vec(String)) Vec(String) := …

  # Transpile.transpile/2
  pub def transpile(source Unk1079, p1 Unk1080) Unk1081 := …

  # Transpile.transpile_with_stats/2
  pub def transpile_with_stats(source Unk1079, p1 Unk1082) Tuple(Unk1081, Unk1083) := …

  # Transpile.underscore_var/1
  pub def underscore_var(name Unk1084) String := …

  # Transpile.var?/1
  pub def var?(p0 Unk1085) Bool := …

  # Transpile.var_name/1
  pub def var_name(p0 Unk1053) String := …

  # TypeStr.split_top_commas/1
  pub def split_top_commas(p0 String) Vec(Unk0069) := …
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
| `Unk0008` | 14 | `Beam.beam_for/5:p0`, `Beam.compile/2:p1`, `Beam.compile_ir/2:p1`, `Beam.load/2:p1`, `Beam.load/2:ret`, `Beam.load_ir/2:p1`, `Beam.load_ir/2:ret`, `Fixpoint.load_lexer/2:p1`, `Fixpoint.load_lexer/2:ret`, `Repl.module_name/1:ret`, `Repl.reload/2:ret`, `Test.compile!/2:p1`, `Test.compile!/2:ret`, `Test.run_one/2:p0` |
| `Unk0009` | 2 | `Beam.beam_for/5:p1`, `Beam.funcs_of/1:ret` |
| `Unk0010` | 74 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.compile/5:p0`, `Lower.compile_beam/4:p0`, `Lower.compile_elixir/4:p0`, `Lower.parametric_param_map/1:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0011` | 92 | `Beam.beam_for/5:p2`, `Beam.beam_for/5:p3`, `Beam.beam_for/5:p4`, `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.load_ir/2:p0`, `Beam.ranges_of/1:p0`, `Beam.ranges_of/1:ret`, `Beam.struct_form/2:p0`, `Beam.structs_of/1:p0`, `Beam.structs_of/1:ret`, `Beam.type_attrs/3:p0`, `Beam.type_attrs/3:p1`, `Beam.type_ctx/3:p0`, `Beam.type_ctx/3:p1`, `Beam.type_ctx/3:p2`, `Beam.types_of/1:p0`, `Beam.types_of/1:ret`, `Check.all_types/1:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Decl.protocol_unit/3:p1`, `Decl.protocol_unit/3:p2`, `Doctest.module_doc_strings/1:p0`, `Exhaustiveness.program_env/3:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/2:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JS.struct_name_set/1:p0`, `JS.sum_ctor_map/1:p0`, `JVM.all_types/1:p0`, `JVM.all_types/1:ret`, `Lower.build_env/3:p0`, `Lower.build_meta/1:p0`, `Lower.build_struct_meta/1:p0`, `Lower.check!/2:p0`, `Lower.compile/5:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p0`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p0`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.ex_doc/2:p0`, `Lower.ex_typespec/1:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.fn_all_tvars/3:ret`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_param_map/1:p0`, `Lower.parametric_used?/2:p0`, `Lower.proto_method_traits/1:p0`, `Lower.rs_doc/2:p0`, `Lower.rust_enum/3:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_impl/4:p0`, `Lower.rust_impl/4:p1`, `Lower.rust_program/1:p0`, `Lower.rust_protocols/4:p0`, `Lower.rust_protocols/4:p1`, `Lower.rust_protocols/4:p2`, `Lower.rust_protocols/4:p3`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_elixir/4:p1`, `Lower.to_rust/6:p0`, `Lower.to_rust/6:p1`, `Lower.trait_impl_block/4:p0`, `Lower.trait_impl_block/4:p1`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:p0`, `Opaque.erase/1:ret`, `Prelude.with_prelude/1:p0`, `Range.table/1:p0`, `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0012` | 3 | `Beam.beam_for/5:ret`, `Beam.compile/2:ret`, `Beam.compile_ir/2:ret` |
| `Unk0013` | 2 | `Beam.beam_func/1:p0`, `Beam.beam_func/1:ret` |
| `Unk0014` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0015` | 21 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.stmt_form/2:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0016` | 1 | `Beam.bin_seg/1:ret` |
| `Unk0017` | 18 | `Beam.bind_var/2:p1`, `Beam.bind_var/2:ret`, `Beam.block_forms/2:p1`, `Beam.body_forms/3:p1`, `Beam.body_seq/2:p1`, `Beam.bump_var/1:p0`, `Beam.bump_var/1:ret`, `Beam.else_dispatch/3:p2`, `Beam.expr_form/2:p1`, `Beam.guard_form/2:p1`, `Beam.i64_overflow/4:p3`, `Beam.pat_vars/2:p1`, `Beam.pat_vars/2:ret`, `Beam.remote_call/4:p3`, `Beam.stmt_form/2:p1`, `Beam.stmt_form/2:ret`, `Beam.var_atom/1:ret`, `Beam.with_form/5:p3` |
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
| `Unk0042` | 1 | `Beam.load_program/1:p0` |
| `Unk0043` | 1 | `Beam.load_program/1:ret` |
| `Unk0044` | 1 | `Beam.load_program_ir/1:p0` |
| `Unk0045` | 1 | `Beam.load_program_ir/1:ret` |
| `Unk0046` | 1 | `Beam.map_field_pat/1:p0` |
| `Unk0047` | 1 | `Beam.map_field_pat/1:ret` |
| `Unk0048` | 1 | `Beam.num_form/1:p0` |
| `Unk0049` | 1 | `Beam.pascal?/1:p0` |
| `Unk0050` | 1 | `Beam.remote_call/4:p0` |
| `Unk0051` | 1 | `Beam.stmt_form/2:p0` |
| `Unk0052` | 1 | `Beam.str_form/1:p0` |
| `Unk0053` | 1 | `Beam.sum_form/2:p0` |
| `Unk0054` | 1 | `Beam.sum_form/2:ret` |
| `Unk0055` | 1 | `Beam.with_form/5:p0` |
| `Unk0056` | 1 | `Capability.beam_legal!/1:p0` |
| `Unk0057` | 1 | `Capability.beam_legal!/1:ret` |
| `Unk0058` | 1 | `Capability.count_block/3:p0` |
| `Unk0059` | 2 | `Capability.count_block/3:p1`, `Capability.count_uses/2:p1` |
| `Unk0060` | 11 | `Capability.count_block/3:p2`, `Capability.count_block/3:ret`, `Capability.count_uses/1:ret`, `Capability.count_uses/2:ret`, `Capability.max_merge/2:p0`, `Capability.max_merge/2:p1`, `Capability.max_merge/2:ret`, `Capability.merge/2:p0`, `Capability.merge/2:p1`, `Capability.merge/2:ret`, `Capability.verdict/2:p1` |
| `Unk0061` | 4 | `Capability.count_uses/1:p0`, `Capability.count_uses/2:p0`, `Capability.lin_check/2:p1`, `Capability.lin_check_block/3:p2` |
| `Unk0062` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0063` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0064` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0065` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0066` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0067` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0068` | 1 | `Capability.lin_check_block/3:p1` |
| `Unk0069` | 10 | `Capability.parametric/1:ret`, `Capability.split_top_level/1:ret`, `Check.parse_parametric/1:ret`, `Check.split_top_commas/1:ret`, `JS.split_top_commas/1:ret`, `Lower.name_type/1:p0`, `Lower.pcommas/1:ret`, `Lower.sig_param/2:p0`, `Protocol.split_commas/1:ret`, `TypeStr.split_top_commas/1:ret` |
| `Unk0070` | 1 | `Capability.pat_vars/1:p0` |
| `Unk0071` | 1 | `Capability.pat_vars/1:ret` |
| `Unk0072` | 1 | `Capability.rust_param/2:p0` |
| `Unk0073` | 131 | `Check.abstract_cast_ret/3:p0`, `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p1`, `Check.abstract_op_type/4:p2`, `Check.abstract_op_type/4:p3`, `Check.adoptable_int?/1:p0`, `Check.ann_each/3:p1`, `Check.ann_each/3:p2`, `Check.ann_each/3:ret`, `Check.ann_stmts/3:p1`, `Check.ann_stmts/3:p2`, `Check.ann_stmts/3:ret`, `Check.annotate/3:p1`, `Check.annotate/3:p2`, `Check.annotate/3:ret`, `Check.arith_type/4:p2`, `Check.arith_type/4:p3`, `Check.assignable?/2:p0`, `Check.assignable?/2:p1`, `Check.bind_mismatch/5:p1`, `Check.bind_mismatch/5:p3`, `Check.bind_mismatch/5:p4`, `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.body_literal_adopts?/2:p1`, `Check.branch_join/1:p0`, `Check.branch_join/1:ret`, `Check.build_fn/2:p1`, `Check.call_bound_error/5:p0`, `Check.call_bound_error/5:p2`, `Check.call_bound_error/5:p3`, `Check.call_bound_error/5:p4`, `Check.called_ret/2:p0`, `Check.called_ret/2:p1`, `Check.called_ret/2:ret`, `Check.called_ret_with/4:p0`, `Check.called_ret_with/4:p1`, `Check.called_ret_with/4:p3`, `Check.called_ret_with/4:ret`, `Check.check_bind_stmts/3:p1`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.clause_env/3:ret`, `Check.concrete_type?/1:p0`, `Check.conservative/1:p0`, `Check.conservative/1:ret`, `Check.ctor_type/2:p0`, `Check.ctor_type/2:p1`, `Check.ctor_type/2:ret`, `Check.first_bound_violation/4:p0`, `Check.first_bound_violation/4:p2`, `Check.first_bound_violation/4:p3`, `Check.float_type?/1:p0`, `Check.fn_ret/1:p0`, `Check.has_tvar?/1:p0`, `Check.infer/3:p1`, `Check.infer/3:p2`, `Check.infer/3:ret`, `Check.infer_block/4:p1`, `Check.infer_block/4:p2`, `Check.infer_block/4:p3`, `Check.infer_block/4:ret`, `Check.infer_tail/3:p1`, `Check.infer_tail/3:p2`, `Check.infer_tail/3:ret`, `Check.instantiate_ret/2:p1`, `Check.instantiate_ret/2:ret`, `Check.int_type?/1:p0`, `Check.join_all/1:ret`, `Check.list_elem/1:p0`, `Check.list_of/1:p0`, `Check.lit_expr_adopts?/2:p1`, `Check.literal_adopts?/2:p1`, `Check.missing_impl/5:p0`, `Check.missing_impl/5:p2`, `Check.missing_impl/5:p4`, `Check.mixed_num?/2:p0`, `Check.mixed_num?/2:p1`, `Check.narrow/4:p1`, `Check.narrow/4:p2`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_kind/1:p0`, `Check.num_mix_error/5:p3`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_base/2:p1`, `Check.range_bind/6:p1`, `Check.range_bind/6:p4`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p0`, `Check.resolve_range/2:p1`, `Check.resolve_range/2:ret`, `Check.scan_bound_calls/4:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_bound_calls/4:p3`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p1`, `Check.scan_num_mix_children/3:p2`, `Check.unify/2:p0`, `Check.unify/2:p1`, `Check.unify/2:ret`, `Check.walk_children/4:p1`, `Check.walk_children/4:p2`, `Check.walk_children/4:p3`, `Decl.clause_env/2:ret`, `Interp.int_type?/1:p0`, `Interp.resolve/4:p1`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p1`, `Interp.resolve_part/4:p2`, `Interp.stringify/3:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:p1`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.infer_or_unknown/3:ret`, `Repl.safe_infer/3:p1`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p1`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0074` | 1 | `Check.abstract_cast_ret/3:p1` |
| `Unk0075` | 38 | `Check.abstract_cast_ret/3:p2`, `Check.abstract_op_type/4:p3`, `Check.ann_each/3:p2`, `Check.ann_stmts/3:p2`, `Check.annotate/3:p2`, `Check.bind_mismatch/5:p4`, `Check.call_bound_error/5:p3`, `Check.called_ret/2:p0`, `Check.called_ret_with/4:p0`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.ctor_type/2:p0`, `Check.first_bound_violation/4:p3`, `Check.infer/3:p2`, `Check.infer_block/4:p2`, `Check.infer_tail/3:p2`, `Check.narrow/4:p2`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_base/2:p0`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p2`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0076` | 2 | `Check.abstract_cast_ret/3:ret`, `Check.fn_ret/1:ret` |
| `Unk0077` | 1 | `Check.abstract_op_type/4:p0` |
| `Unk0078` | 1 | `Check.abstract_op_type/4:ret` |
| `Unk0079` | 1 | `Check.all_types/1:p0` |
| `Unk0080` | 28 | `Check.ann_each/3:p1`, `Check.ann_stmts/3:p1`, `Check.annotate/3:p1`, `Check.bind_mismatch/5:p3`, `Check.call_bound_error/5:p2`, `Check.called_ret_with/4:p3`, `Check.check_bind_stmts/3:p1`, `Check.clause_env/3:ret`, `Check.infer/3:p1`, `Check.infer_block/4:p1`, `Check.infer_tail/3:p1`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.range_bind/6:p4`, `Check.scan_bound_calls/4:p1`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix_children/3:p1`, `Check.walk_children/4:p1`, `Decl.clause_env/2:ret`, `Interp.resolve/4:p1`, `Interp.resolve_part/4:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.safe_infer/3:p1`, `Repl.safe_infer_input/3:p1` |
| `Unk0081` | 1 | `Check.ann_stmts/3:p0` |
| `Unk0082` | 1 | `Check.arith_type/4:ret` |
| `Unk0083` | 4 | `Check.bind_mismatch/5:p0`, `Check.lit_range_error/3:p2`, `Check.oor_scan/5:p4`, `Check.range_bind/6:p0` |
| `Unk0084` | 2 | `Check.bind_mismatch/5:ret`, `Check.check_bind_stmts/3:ret` |
| `Unk0085` | 4 | `Check.bind_tvar/4:p0`, `Check.bind_tvar/4:p1`, `Check.inner_of/1:p0`, `Check.inner_of/1:ret` |
| `Unk0086` | 1 | `Check.bind_tvar/4:p2` |
| `Unk0087` | 3 | `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.first_bound_violation/4:p2` |
| `Unk0088` | 1 | `Check.branch_join/1:p0` |
| `Unk0089` | 1 | `Check.build_fn/2:p0` |
| `Unk0090` | 2 | `Check.call_bound_error/5:ret`, `Check.first_bound_violation/4:ret` |
| `Unk0091` | 1 | `Check.call_name/1:p0` |
| `Unk0092` | 2 | `Check.call_name/1:ret`, `Check.with_callees/1:ret` |
| `Unk0093` | 1 | `Check.check/1:p0` |
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
| `Unk0134` | 1 | `Check.gate!/1:ret` |
| `Unk0135` | 1 | `Check.generic_ret?/2:p0` |
| `Unk0136` | 1 | `Check.generic_ret?/2:p1` |
| `Unk0137` | 1 | `Check.impl_table/1:p0` |
| `Unk0138` | 1 | `Check.impl_table/1:p0` |
| `Unk0139` | 1 | `Check.impl_table/1:ret` |
| `Unk0140` | 1 | `Check.infer_block/4:p0` |
| `Unk0141` | 1 | `Check.instantiate_ret/2:p0` |
| `Unk0142` | 1 | `Check.int_literal?/1:p0` |
| `Unk0143` | 4 | `Check.join/2:ret`, `Check.num_join/2:ret`, `Check.parametric_join/2:ret`, `Check.uint_signed_join/2:ret` |
| `Unk0144` | 1 | `Check.join_all/1:p0` |
| `Unk0145` | 1 | `Check.kind_prefix/1:p0` |
| `Unk0146` | 2 | `Check.label_error/1:ret`, `Check.label_error_children/1:ret` |
| `Unk0147` | 1 | `Check.list_elem/1:ret` |
| `Unk0148` | 1 | `Check.list_elems/1:ret` |
| `Unk0149` | 1 | `Check.lit_range_error/3:ret` |
| `Unk0150` | 1 | `Check.literal_ordinal/2:ret` |
| `Unk0151` | 1 | `Check.missing_impl/5:p1` |
| `Unk0152` | 1 | `Check.missing_impl/5:p3` |
| `Unk0153` | 1 | `Check.missing_impl/5:ret` |
| `Unk0154` | 1 | `Check.num_bits/2:p0` |
| `Unk0155` | 1 | `Check.num_bits/2:p1` |
| `Unk0156` | 2 | `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0157` | 1 | `Check.num_join/2:p0` |
| `Unk0158` | 1 | `Check.num_join/2:p1` |
| `Unk0159` | 1 | `Check.num_lub/2:ret` |
| `Unk0160` | 1 | `Check.num_mix?/2:p0` |
| `Unk0161` | 1 | `Check.num_mix?/2:p1` |
| `Unk0162` | 1 | `Check.num_mix_error/5:p0` |
| `Unk0163` | 1 | `Check.num_mix_error/5:ret` |
| `Unk0164` | 1 | `Check.num_widens?/2:p0` |
| `Unk0165` | 1 | `Check.num_widens?/2:p1` |
| `Unk0166` | 1 | `Check.oor_scan/5:p2` |
| `Unk0167` | 1 | `Check.oor_scan/5:p3` |
| `Unk0168` | 1 | `Check.oor_scan/5:ret` |
| `Unk0169` | 1 | `Check.opaque_table/1:p0` |
| `Unk0170` | 1 | `Check.opaque_table/1:p0` |
| `Unk0171` | 1 | `Check.opaque_table/1:ret` |
| `Unk0172` | 1 | `Check.pascal?/1:p0` |
| `Unk0173` | 1 | `Check.produced_set/2:p1` |
| `Unk0174` | 1 | `Check.produced_set/2:p1` |
| `Unk0175` | 1 | `Check.produced_set/2:ret` |
| `Unk0176` | 1 | `Check.propagated_callees/1:ret` |
| `Unk0177` | 1 | `Check.range_base/2:ret` |
| `Unk0178` | 1 | `Check.range_bind/6:p2` |
| `Unk0179` | 1 | `Check.range_bind/6:ret` |
| `Unk0180` | 1 | `Check.range_table/1:p0` |
| `Unk0181` | 1 | `Check.range_table/1:p0` |
| `Unk0182` | 1 | `Check.range_table/1:ret` |
| `Unk0183` | 2 | `Check.scan_bound_calls/4:ret`, `Check.walk_children/4:ret` |
| `Unk0184` | 2 | `Check.scan_num_mix/3:ret`, `Check.scan_num_mix_children/3:ret` |
| `Unk0185` | 1 | `Check.solve_error_sets/2:p0` |
| `Unk0186` | 1 | `Check.tag_name/1:p0` |
| `Unk0187` | 1 | `Check.type_table/1:ret` |
| `Unk0188` | 2 | `Check.uint_signed_join/2:p0`, `Check.uint_signed_join/2:p1` |
| `Unk0189` | 1 | `Check.with_callees/1:p0` |
| `Unk0190` | 1 | `Comptime.eval/1:p0` |
| `Unk0191` | 1 | `Comptime.eval/1:ret` |
| `Unk0192` | 24 | `Comptime.fold/1:ret`, `Interp.resolve/4:p0`, `Lower.borrow_arg/5:p0`, `Lower.borrow_value/2:p0`, `Lower.borrow_value/2:ret`, `Lower.insert_borrows/4:ret`, `Lower.owned_arg?/2:p0`, `Lower.owned_field_var?/2:p0`, `Lower.resolve_consts/2:ret`, `Lower.resolve_rust_pats/2:ret`, `Lower.resolve_structs/2:ret`, `Lower.resolve_variants/2:ret`, `Lower.scalar_literal?/1:p0`, `Lower.variant_lit/2:ret`, `Lower.widen_char_arith/2:ret`, `Lower.wrap_char/2:p0`, `Lower.wrap_char/2:ret`, `Macro.do_expand/4:ret`, `Macro.freshen/2:ret`, `Macro.map_node/2:p1`, `Macro.map_node/2:ret`, `Macro.rename/2:ret`, `Macro.substitute/2:p0`, `Macro.walk_for_with/1:ret` |
| `Unk0193` | 1 | `Comptime.int_div/3:p0` |
| `Unk0194` | 1 | `Comptime.int_div/3:p2` |
| `Unk0195` | 1 | `Comptime.int_div/3:p2` |
| `Unk0196` | 1 | `Comptime.int_div/3:p2` |
| `Unk0197` | 1 | `Comptime.int_div/3:ret` |
| `Unk0198` | 1 | `Core.first_unsupported/2:p0` |
| `Unk0199` | 2 | `Core.first_unsupported/2:p1`, `Core.reject_unsupported!/4:p1` |
| `Unk0200` | 3 | `Core.first_unsupported/2:p1`, `Core.first_unsupported/2:ret`, `Core.reject_unsupported!/4:p1` |
| `Unk0201` | 1 | `Core.from_arm/1:p0` |
| `Unk0202` | 1 | `Core.from_arm/1:ret` |
| `Unk0203` | 1 | `Core.from_pairs/1:p0` |
| `Unk0204` | 1 | `Core.from_pairs/1:ret` |
| `Unk0205` | 1 | `Core.from_stmt/1:p0` |
| `Unk0206` | 1 | `Core.from_stmt/1:ret` |
| `Unk0207` | 1 | `Core.from_tail/1:p0` |
| `Unk0208` | 2 | `Core.reject_unsupported!/4:p0`, `JS.function_js/2:p0` |
| `Unk0209` | 1 | `Core.reject_unsupported!/4:p2` |
| `Unk0210` | 1 | `Core.reject_unsupported!/4:p3` |
| `Unk0211` | 1 | `Core.reject_unsupported!/4:ret` |
| `Unk0212` | 8 | `Cst.build/1:p0`, `Cst.open/4:p0`, `Cst.open/4:p2`, `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p0`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0213` | 1 | `Cst.build/1:ret` |
| `Unk0214` | 1 | `Cst.open/4:p1` |
| `Unk0215` | 4 | `Cst.open/4:p3`, `Cst.open/4:ret`, `Cst.seq/2:p1`, `Cst.seq/2:ret` |
| `Unk0216` | 2 | `Cst.open/4:ret`, `Cst.seq/2:ret` |
| `Unk0217` | 7 | `Decl.all_impl_decls/1:p0`, `Decl.all_impls/1:p0`, `Decl.all_protocols/1:p0`, `Decl.collect_aliases/1:p0`, `Decl.collect_macros/1:p0`, `Decl.in_scope/2:p0`, `Decl.lower_meta/3:p1` |
| `Unk0218` | 5 | `Decl.all_impl_decls/1:ret`, `Decl.all_protocols/1:ret`, `Decl.in_scope/2:ret`, `Protocol.check_assoc!/2:p0`, `Protocol.check_assoc!/2:p1` |
| `Unk0219` | 1 | `Decl.all_impls/1:ret` |
| `Unk0220` | 2 | `Decl.assemble/3:p0`, `Decl.protocol_defs/4:p0` |
| `Unk0221` | 5 | `Decl.assemble/3:p1`, `Decl.subst_const/2:p1`, `Decl.subst_func/2:p1`, `Decl.subst_struct/2:p1`, `Decl.subst_type/2:p1` |
| `Unk0222` | 1 | `Decl.assemble/3:p2` |
| `Unk0223` | 1 | `Decl.assemble/3:ret` |
| `Unk0224` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0225` | 7 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret`, `Decl.attach_external/3:ret`, `Decl.attach_targets/2:ret`, `Decl.mark_pub/1:ret`, `Decl.mark_test/1:ret`, `Decl.take_decl/1:ret` |
| `Unk0226` | 1 | `Decl.attach_external/3:p0` |
| `Unk0227` | 1 | `Decl.attach_external/3:p1` |
| `Unk0228` | 1 | `Decl.attach_external/3:p2` |
| `Unk0229` | 1 | `Decl.attach_targets/2:p0` |
| `Unk0230` | 2 | `Decl.attach_targets/2:p1`, `Decl.parse_targets/1:ret` |
| `Unk0231` | 37 | `Decl.balanced_parens/1:p0`, `Decl.balanced_parens/1:ret`, `Decl.decl_boundary?/1:p0`, `Decl.decl_kw?/1:p0`, `Decl.def_raw/4:p2`, `Decl.line_continues?/2:p0`, `Decl.line_continues?/2:p1`, `Decl.skip_nl/1:p0`, `Decl.skip_nl/1:ret`, `Decl.split_decls/1:p0`, `Decl.take_block/3:p0`, `Decl.take_block/3:p2`, `Decl.take_block/3:ret`, `Decl.take_decl/1:p0`, `Decl.take_decl/1:ret`, `Decl.take_def/1:p0`, `Decl.take_def/1:ret`, `Decl.take_head/4:p2`, `Decl.take_head/4:p3`, `Decl.take_head/4:ret`, `Decl.take_line/2:p0`, `Decl.take_line/2:p1`, `Decl.take_line/2:ret`, `Decl.take_line/3:p0`, `Decl.take_line/3:p1`, `Decl.take_line/3:ret`, `Decl.take_mod_body/2:p0`, `Decl.take_mod_body/2:ret`, `Decl.take_parens/3:p0`, `Decl.take_parens/3:p2`, `Decl.take_parens/3:ret`, `Decl.take_type/2:p0`, `Decl.take_type/2:p1`, `Decl.take_type/2:ret`, `Decl.take_until_do/2:p0`, `Decl.take_until_do/2:p1`, `Decl.take_until_do/2:ret` |
| `Unk0232` | 3 | `Decl.block_seps/5:p0`, `Decl.block_seps/5:p4`, `Decl.block_seps/5:ret` |
| `Unk0233` | 1 | `Decl.build_func/1:p0` |
| `Unk0234` | 1 | `Decl.calls_show_float?/1:p0` |
| `Unk0235` | 1 | `Decl.clause/2:p0` |
| `Unk0236` | 1 | `Decl.clause/2:p1` |
| `Unk0237` | 2 | `Decl.clause_env/2:p1`, `Decl.meta_clause/5:p3` |
| `Unk0238` | 1 | `Decl.collapse_parens/1:p0` |
| `Unk0239` | 1 | `Decl.collapse_parens/1:ret` |
| `Unk0240` | 1 | `Decl.collect_aliases/1:ret` |
| `Unk0241` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0242` | 5 | `Decl.collect_macros/1:ret`, `Decl.meta_clause/5:p1`, `Macro.build_env/1:ret`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0243` | 8 | `Decl.compile/1:ret`, `Decl.compile_beam/1:ret`, `Decl.protocol_unit/3:ret`, `Lower.compile/5:ret`, `Lower.compile_beam/4:ret`, `Lower.compile_elixir/4:ret`, `Lower.compile_module/1:ret`, `Lower.compile_module_beam/1:ret` |
| `Unk0244` | 1 | `Decl.compile_beam/1:ret` |
| `Unk0245` | 2 | `Decl.def_raw/4:p0`, `Decl.take_head/4:p0` |
| `Unk0246` | 2 | `Decl.def_raw/4:p1`, `Decl.take_head/4:p1` |
| `Unk0247` | 2 | `Decl.def_raw/4:p3`, `Decl.detok_block/1:ret` |
| `Unk0248` | 3 | `Decl.def_raw/4:ret`, `Decl.take_def/1:ret`, `Decl.take_head/4:ret` |
| `Unk0249` | 1 | `Decl.detok_block/1:p0` |
| `Unk0250` | 3 | `Decl.extract_parens/1:p0`, `Decl.parse_struct/3:p0`, `Decl.variant/1:p0` |
| `Unk0251` | 1 | `Decl.extract_parens/1:ret` |
| `Unk0252` | 1 | `Decl.field/1:p0` |
| `Unk0253` | 1 | `Decl.fields/1:p0` |
| `Unk0254` | 1 | `Decl.fields/1:ret` |
| `Unk0255` | 1 | `Decl.impl_struct/3:p0` |
| `Unk0256` | 1 | `Decl.impl_struct/3:p1` |
| `Unk0257` | 1 | `Decl.impl_struct/3:p2` |
| `Unk0258` | 1 | `Decl.impl_struct/3:ret` |
| `Unk0259` | 1 | `Decl.in_scope/2:p1` |
| `Unk0260` | 1 | `Decl.in_scope/2:p1` |
| `Unk0261` | 3 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0` |
| `Unk0262` | 4 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret`, `Decl.needs_show_float?/1:p0`, `ShowStdlib.module/0:ret` |
| `Unk0263` | 1 | `Decl.lower_meta/3:p0` |
| `Unk0264` | 1 | `Decl.lower_meta/3:p2` |
| `Unk0265` | 1 | `Decl.lower_meta/3:ret` |
| `Unk0266` | 1 | `Decl.macro_param_names/1:p0` |
| `Unk0267` | 1 | `Decl.macro_param_names/1:ret` |
| `Unk0268` | 1 | `Decl.mark_pub/1:p0` |
| `Unk0269` | 1 | `Decl.mark_test/1:p0` |
| `Unk0270` | 1 | `Decl.meta_clause/5:p0` |
| `Unk0271` | 4 | `Decl.meta_clause/5:p4`, `Interp.resolve/4:p3`, `Interp.resolve_part/4:p3`, `Interp.stringify/3:p2` |
| `Unk0272` | 1 | `Decl.meta_clause/5:ret` |
| `Unk0273` | 1 | `Decl.nz/1:ret` |
| `Unk0274` | 1 | `Decl.param/1:p0` |
| `Unk0275` | 1 | `Decl.param/1:ret` |
| `Unk0276` | 7 | `Decl.parse_abstract/4:p0`, `Decl.parse_alias/1:p0`, `Decl.parse_const/3:p0`, `Decl.parse_opaque/3:p0`, `Decl.parse_range/3:p0`, `Decl.parse_type/3:p0`, `Decl.split_once/2:p0` |
| `Unk0277` | 2 | `Decl.parse_abstract/4:p1`, `Decl.parse_abstract_members/1:p0` |
| `Unk0278` | 1 | `Decl.parse_abstract/4:p2` |
| `Unk0279` | 1 | `Decl.parse_abstract/4:p3` |
| `Unk0280` | 1 | `Decl.parse_abstract_members/1:ret` |
| `Unk0281` | 2 | `Decl.parse_alias/1:ret`, `Decl.strip_type_params/1:ret` |
| `Unk0282` | 1 | `Decl.parse_alias/1:ret` |
| `Unk0283` | 1 | `Decl.parse_assoc_binding/1:p0` |
| `Unk0284` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0285` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0286` | 1 | `Decl.parse_binder/1:p0` |
| `Unk0287` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0288` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0289` | 1 | `Decl.parse_binders/1:p0` |
| `Unk0290` | 1 | `Decl.parse_binders/1:ret` |
| `Unk0291` | 1 | `Decl.parse_bounds/1:p0` |
| `Unk0292` | 1 | `Decl.parse_bounds/1:ret` |
| `Unk0293` | 2 | `Decl.parse_cast_rule/1:p0`, `Decl.parse_op_rule/1:p0` |
| `Unk0294` | 1 | `Decl.parse_cast_rule/1:ret` |
| `Unk0295` | 1 | `Decl.parse_const/3:p1` |
| `Unk0296` | 1 | `Decl.parse_const/3:p2` |
| `Unk0297` | 1 | `Decl.parse_external/1:p0` |
| `Unk0298` | 1 | `Decl.parse_external/1:ret` |
| `Unk0299` | 1 | `Decl.parse_external/1:ret` |
| `Unk0300` | 1 | `Decl.parse_head/1:ret` |
| `Unk0301` | 1 | `Decl.parse_op_rule/1:ret` |
| `Unk0302` | 1 | `Decl.parse_opaque/3:p1` |
| `Unk0303` | 1 | `Decl.parse_opaque/3:p2` |
| `Unk0304` | 1 | `Decl.parse_ordinal/1:p0` |
| `Unk0305` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0306` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0307` | 1 | `Decl.parse_params/1:p0` |
| `Unk0308` | 1 | `Decl.parse_params/1:ret` |
| `Unk0309` | 1 | `Decl.parse_range/3:p1` |
| `Unk0310` | 1 | `Decl.parse_range/3:p2` |
| `Unk0311` | 1 | `Decl.parse_struct/3:p1` |
| `Unk0312` | 1 | `Decl.parse_struct/3:p2` |
| `Unk0313` | 1 | `Decl.parse_targets/1:p0` |
| `Unk0314` | 1 | `Decl.parse_type/3:p1` |
| `Unk0315` | 1 | `Decl.parse_type/3:p2` |
| `Unk0316` | 1 | `Decl.parse_use/1:p0` |
| `Unk0317` | 2 | `Decl.proto_method_traits/1:ret`, `Lower.compile/5:p4` |
| `Unk0318` | 2 | `Decl.protocol_defs/4:p1`, `Protocol.expand/5:p2` |
| `Unk0319` | 2 | `Decl.protocol_defs/4:p2`, `Protocol.expand/5:p3` |
| `Unk0320` | 2 | `Decl.protocol_defs/4:p3`, `Protocol.expand/5:p4` |
| `Unk0321` | 3 | `Decl.protocol_defs/4:ret`, `Protocol.expand/5:ret`, `Protocol.impl_methods/2:ret` |
| `Unk0322` | 1 | `Decl.protocol_struct/2:p0` |
| `Unk0323` | 1 | `Decl.protocol_struct/2:p1` |
| `Unk0324` | 1 | `Decl.protocol_struct/2:ret` |
| `Unk0325` | 1 | `Decl.req_ret/1:p0` |
| `Unk0326` | 1 | `Decl.req_ret/1:ret` |
| `Unk0327` | 1 | `Decl.split2/2:p0` |
| `Unk0328` | 1 | `Decl.split2/2:p1` |
| `Unk0329` | 1 | `Decl.split2/2:ret` |
| `Unk0330` | 1 | `Decl.split2/2:ret` |
| `Unk0331` | 1 | `Decl.split_decls/1:ret` |
| `Unk0332` | 1 | `Decl.split_forall/1:p0` |
| `Unk0333` | 1 | `Decl.split_forall/1:ret` |
| `Unk0334` | 1 | `Decl.split_once/2:ret` |
| `Unk0335` | 1 | `Decl.split_once/2:ret` |
| `Unk0336` | 1 | `Decl.split_top/2:p0` |
| `Unk0337` | 1 | `Decl.split_top/2:ret` |
| `Unk0338` | 1 | `Decl.strip_type_params/1:p0` |
| `Unk0339` | 1 | `Decl.subst_const/2:p0` |
| `Unk0340` | 1 | `Decl.subst_fields/2:p0` |
| `Unk0341` | 1 | `Decl.subst_fields/2:p1` |
| `Unk0342` | 1 | `Decl.subst_func/2:p0` |
| `Unk0343` | 1 | `Decl.subst_struct/2:p0` |
| `Unk0344` | 1 | `Decl.subst_type/2:p0` |
| `Unk0345` | 2 | `Decl.subst_type_str/2:p0`, `Decl.subst_type_str/2:ret` |
| `Unk0346` | 1 | `Decl.subst_type_str/2:p1` |
| `Unk0347` | 1 | `Decl.subst_variant/2:p0` |
| `Unk0348` | 1 | `Decl.subst_variant/2:p1` |
| `Unk0349` | 2 | `Decl.take_mod_body/2:p1`, `Decl.take_mod_body/2:ret` |
| `Unk0350` | 1 | `Decl.take_until_do/2:ret` |
| `Unk0351` | 27 | `Doc.concat/1:p0`, `Doc.concat/1:ret`, `Doc.concat/2:p0`, `Doc.concat/2:p1`, `Doc.concat/2:ret`, `Doc.empty/0:ret`, `Doc.group/1:p0`, `Doc.hardline/0:ret`, `Doc.if_break/2:p0`, `Doc.if_break/2:p1`, `Doc.if_break/2:ret`, `Doc.join/2:p0`, `Doc.join/2:p1`, `Doc.join/2:ret`, `Doc.line/0:ret`, `Doc.line_suffix/1:p0`, `Doc.line_suffix/1:ret`, `Doc.must_break?/1:p0`, `Doc.nest/2:p1`, `Doc.nest/2:ret`, `Doc.render/2:p0`, `Doc.softline/0:ret`, `Doc.text/1:ret`, `Format.bd/3:ret`, `Format.group_doc/4:ret`, `Format.line_doc/1:ret`, `Format.node_doc/2:ret` |
| `Unk0352` | 2 | `Doc.do_render/5:p2`, `Doc.fits?/2:p1` |
| `Unk0353` | 3 | `Doc.do_render/5:p3`, `Doc.flat_string/1:p0`, `Doc.flush_suffix/2:p0` |
| `Unk0354` | 1 | `Doc.group/1:ret` |
| `Unk0355` | 14 | `Doc.nest/2:p0`, `Format.apply_node/3:p1`, `Format.apply_node/3:p2`, `Format.apply_node/3:ret`, `Format.indent_and_render/4:p1`, `Format.pop/1:p0`, `Format.pop/1:ret`, `Format.push/2:p0`, `Format.push/2:p1`, `Format.push/2:ret`, `Format.render_line/2:p1`, `Format.update_stack/4:p2`, `Format.update_stack/4:p3`, `Format.update_stack/4:ret` |
| `Unk0356` | 2 | `Doctest.augment/2:p1`, `Doctest.extract/1:ret` |
| `Unk0357` | 1 | `Doctest.exunit_cases/2:p1` |
| `Unk0358` | 1 | `Doctest.exunit_cases/2:ret` |
| `Unk0359` | 1 | `Doctest.fences/1:p0` |
| `Unk0360` | 1 | `Doctest.fences/1:ret` |
| `Unk0361` | 1 | `Doctest.module_doc_strings/1:ret` |
| `Unk0362` | 1 | `Doctest.pairs/1:p0` |
| `Unk0363` | 1 | `Doctest.pairs/1:ret` |
| `Unk0364` | 1 | `Doctest.run/2:p1` |
| `Unk0365` | 1 | `Doctest.run/2:ret` |
| `Unk0366` | 1 | `Doctest.run_markdown/1:p0` |
| `Unk0367` | 1 | `Doctest.run_markdown/1:ret` |
| `Unk0368` | 8 | `Exhaustiveness.add_range/4:p0`, `Exhaustiveness.add_range/4:ret`, `Exhaustiveness.add_type/3:p0`, `Exhaustiveness.add_type/3:ret`, `Exhaustiveness.base_env/0:ret`, `Exhaustiveness.program_env/3:ret`, `PatternLower.add_struct/3:p0`, `PatternLower.add_struct/3:ret` |
| `Unk0369` | 1 | `Exhaustiveness.add_range/4:p2` |
| `Unk0370` | 1 | `Exhaustiveness.add_range/4:p3` |
| `Unk0371` | 1 | `Exhaustiveness.add_type/3:p2` |
| `Unk0372` | 2 | `Exhaustiveness.analyze/3:p0`, `PatternLower.lower_clause/2:ret` |
| `Unk0373` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0374` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0375` | 1 | `Exhaustiveness.analyze/3:ret` |
| `Unk0376` | 2 | `Exhaustiveness.arity/2:p1`, `Exhaustiveness.specialize/3:p1` |
| `Unk0377` | 1 | `Exhaustiveness.check_case_bodies!/2:p0` |
| `Unk0378` | 1 | `Exhaustiveness.check_case_bodies!/2:p1` |
| `Unk0379` | 1 | `Exhaustiveness.check_case_bodies!/2:ret` |
| `Unk0380` | 1 | `Exhaustiveness.check_match!/3:p0` |
| `Unk0381` | 2 | `Exhaustiveness.check_match!/3:p2`, `Exhaustiveness.check_one_case!/3:p2` |
| `Unk0382` | 1 | `Exhaustiveness.check_match!/3:ret` |
| `Unk0383` | 1 | `Exhaustiveness.check_one_case!/3:ret` |
| `Unk0384` | 2 | `Exhaustiveness.collect_cases/2:p0`, `Exhaustiveness.collect_children/2:p0` |
| `Unk0385` | 4 | `Exhaustiveness.collect_cases/2:p1`, `Exhaustiveness.collect_cases/2:ret`, `Exhaustiveness.collect_children/2:p1`, `Exhaustiveness.collect_children/2:ret` |
| `Unk0386` | 7 | `Exhaustiveness.default/1:p0`, `Exhaustiveness.default/1:ret`, `Exhaustiveness.head_ctors/1:p0`, `Exhaustiveness.specialize/3:p0`, `Exhaustiveness.specialize/3:ret`, `Exhaustiveness.useful?/3:p0`, `Exhaustiveness.witness/3:p0` |
| `Unk0387` | 3 | `Exhaustiveness.head_ctors/1:ret`, `Exhaustiveness.missing_head/2:p1`, `Exhaustiveness.signature/2:p1` |
| `Unk0388` | 2 | `Exhaustiveness.missing_head/2:ret`, `Exhaustiveness.witness/3:ret` |
| `Unk0389` | 1 | `Exhaustiveness.pascal/1:p0` |
| `Unk0390` | 1 | `Exhaustiveness.program_env/3:p1` |
| `Unk0391` | 1 | `Exhaustiveness.program_env/3:p2` |
| `Unk0392` | 1 | `Exhaustiveness.render/1:p0` |
| `Unk0393` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0394` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0395` | 1 | `Exhaustiveness.useful?/3:p1` |
| `Unk0396` | 1 | `Exhaustiveness.witness/3:ret` |
| `Unk0397` | 1 | `Fixpoint.check/4:p0` |
| `Unk0398` | 1 | `Fixpoint.check/4:p1` |
| `Unk0399` | 1 | `Fixpoint.check/4:p2` |
| `Unk0400` | 1 | `Fixpoint.check/4:p3` |
| `Unk0401` | 1 | `Fixpoint.check/4:ret` |
| `Unk0402` | 27 | `Format.apply_node/3:p0`, `Format.bd/3:p0`, `Format.bd/3:p1`, `Format.blank?/1:p0`, `Format.block_head?/2:p0`, `Format.block_head?/2:p1`, `Format.comment_only?/1:p0`, `Format.declaration_line?/1:p0`, `Format.head_tok/1:p0`, `Format.indent_and_render/4:p0`, `Format.lead_adjust/1:p0`, `Format.line_doc/1:p0`, `Format.mark/1:p0`, `Format.mark/1:ret`, `Format.mark/3:p0`, `Format.mark/3:p1`, `Format.mark/3:p2`, `Format.mark/3:ret`, `Format.next_code_line/1:p0`, `Format.node_doc/2:p0`, `Format.render_line/2:p0`, `Format.split_items/1:ret`, `Format.tail_tok/1:p0`, `Format.trailing_op?/1:p0`, `Format.update_stack/4:p0`, `Format.update_stack/4:p1`, `Format.value_end?/1:p0` |
| `Unk0403` | 2 | `Format.boundary?/1:p0`, `Format.next_code_line/1:ret` |
| `Unk0404` | 6 | `Format.boundary_tok?/1:p0`, `Format.closer_lead?/1:p0`, `Format.cont_lead?/1:p0`, `Format.decl_kw?/1:p0`, `Format.head_tok/1:ret`, `Format.space?/2:p1` |
| `Unk0405` | 7 | `Format.chunk_on_comma/3:p0`, `Format.chunk_on_comma/3:p1`, `Format.chunk_on_comma/3:p2`, `Format.chunk_on_comma/3:ret`, `Format.finish_items/2:p0`, `Format.finish_items/2:p1`, `Format.finish_items/2:ret` |
| `Unk0406` | 5 | `Format.cons_group?/1:p0`, `Format.group_doc/4:p1`, `Format.has_comment?/1:p0`, `Format.split_items/1:p0`, `Format.trailing_comma?/1:p0` |
| `Unk0407` | 3 | `Format.format/1:p0`, `Format.format/1:ret`, `Format.format_result/1:p0` |
| `Unk0408` | 1 | `Format.format_result/1:ret` |
| `Unk0409` | 1 | `Format.format_result/1:ret` |
| `Unk0410` | 3 | `Format.group_doc/4:p0`, `Format.group_doc/4:p2`, `Format.leaf/1:p0` |
| `Unk0411` | 2 | `Format.has_tok?/2:p0`, `Format.has_tok?/2:p1` |
| `Unk0412` | 1 | `Format.has_tok?/2:p0` |
| `Unk0413` | 6 | `Format.ll/3:p0`, `Format.ll/3:p1`, `Format.ll/3:p2`, `Format.ll/3:ret`, `Format.logical_lines/1:p0`, `Format.logical_lines/1:ret` |
| `Unk0414` | 3 | `Format.space?/2:p0`, `Format.tail_tok/1:ret`, `Format.value_end_tok?/1:p0` |
| `Unk0415` | 1 | `Format.squeeze_blanks/1:p0` |
| `Unk0416` | 1 | `Format.squeeze_blanks/1:ret` |
| `Unk0417` | 1 | `FormsEquiv.abstract_code/1:p0` |
| `Unk0418` | 1 | `FormsEquiv.abstract_code/1:ret` |
| `Unk0419` | 3 | `FormsEquiv.alpha_rename/1:p0`, `FormsEquiv.walk_rename/2:p0`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0420` | 1 | `FormsEquiv.alpha_rename/1:ret` |
| `Unk0421` | 3 | `FormsEquiv.bool_clause/1:p0`, `FormsEquiv.bool_clause_pair/1:p0`, `FormsEquiv.bool_clause_pair/1:ret` |
| `Unk0422` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0423` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0424` | 2 | `FormsEquiv.canon_bool_case/1:p0`, `FormsEquiv.canon_bool_case/1:ret` |
| `Unk0425` | 9 | `FormsEquiv.diff/2:p0`, `FormsEquiv.diff/2:p1`, `FormsEquiv.equivalent?/2:p0`, `FormsEquiv.equivalent?/2:p1`, `FormsEquiv.normalize/1:p0`, `FormsEquiv.verified?/2:p0`, `FormsEquiv.verified?/2:p1`, `FormsEquiv.verify/2:p0`, `FormsEquiv.verify/2:p1` |
| `Unk0426` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0427` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0428` | 2 | `FormsEquiv.fold_neg_literal/1:p0`, `FormsEquiv.fold_neg_literal/1:ret` |
| `Unk0429` | 1 | `FormsEquiv.key/1:p0` |
| `Unk0430` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0431` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0432` | 1 | `FormsEquiv.normalize/1:ret` |
| `Unk0433` | 1 | `FormsEquiv.user_function?/1:p0` |
| `Unk0434` | 1 | `FormsEquiv.verify/2:ret` |
| `Unk0435` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0436` | 2 | `FormsEquiv.walk_rename/2:p1`, `FormsEquiv.walk_rename/2:ret` |
| `Unk0437` | 2 | `FormsEquiv.zero_anno/1:p0`, `FormsEquiv.zero_anno/1:ret` |
| `Unk0438` | 1 | `History.add/1:p0` |
| `Unk0439` | 1 | `History.add/1:ret` |
| `Unk0440` | 2 | `History.dedup_consecutive/1:p0`, `History.dedup_consecutive/1:ret` |
| `Unk0441` | 1 | `History.load/0:ret` |
| `Unk0442` | 1 | `History.path/0:ret` |
| `Unk0443` | 1 | `Infer.app/2:p1` |
| `Unk0444` | 83 | `Infer.app/2:ret`, `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p2`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p2`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p3`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.con/1:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.free_vars/2:p1`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p1`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p1`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p1`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p2`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p1`, `Infer.gen_pat/4:p2`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p2`, `Infer.gen_pat_cons/5:p3`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p1`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:p1`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p1`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p2`, `Infer.parse_type/2:ret`, `Infer.render/3:p0`, `Infer.render/3:p2`, `Infer.render_wp/3:p0`, `Infer.render_wp/3:p2`, `Infer.resolve/2:p0`, `Infer.resolve/2:p1`, `Infer.resolve/2:ret`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.sigvar_call/5:p3`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:p1`, `Infer.unify/3:p2`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0`, `Infer.unk_vars/2:p1` |
| `Unk0445` | 55 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.bind/3:p0`, `Infer.bind/3:p1`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:p1`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.num_conflict?/3:p1`, `Infer.occurs?/3:p0`, `Infer.occurs?/3:p1`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0446` | 51 | `Infer.app1/2:p1`, `Infer.app1/2:ret`, `Infer.bind/3:p0`, `Infer.bind_checked/3:p0`, `Infer.bind_checked/3:ret`, `Infer.bind_params/3:p2`, `Infer.call_sig/6:p5`, `Infer.call_sig/6:ret`, `Infer.do_unify/3:p0`, `Infer.do_unify/3:ret`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh/1:ret`, `Infer.fresh_n/2:p0`, `Infer.fresh_n/2:ret`, `Infer.fresh_num/1:p0`, `Infer.fresh_num/1:ret`, `Infer.freshen_tvars/2:p1`, `Infer.freshen_tvars/2:ret`, `Infer.gen/4:p3`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:p3`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:p4`, `Infer.gen_cons/5:ret`, `Infer.gen_pat/4:p3`, `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:p4`, `Infer.gen_pat_cons/5:ret`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.instantiate/5:ret`, `Infer.mark_num/2:p0`, `Infer.mark_num/2:ret`, `Infer.maybe_tuple/4:p3`, `Infer.maybe_tuple/4:ret`, `Infer.num_conflict?/3:p0`, `Infer.occurs?/3:p0`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.resolve_struct_params/4:p3`, `Infer.resolve_struct_params/4:ret`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unify/3:ret`, `Infer.unk_vars/2:p0` |
| `Unk0447` | 1 | `Infer.bind/3:ret` |
| `Unk0448` | 3 | `Infer.bind_checked/3:ret`, `Infer.do_unify/3:ret`, `Infer.unify/3:ret` |
| `Unk0449` | 1 | `Infer.bind_params/3:p0` |
| `Unk0450` | 1 | `Infer.bind_params/3:p1` |
| `Unk0451` | 1 | `Infer.bind_params/3:ret` |
| `Unk0452` | 1 | `Infer.build_ctx/2:p0` |
| `Unk0453` | 1 | `Infer.build_ctx/2:p1` |
| `Unk0454` | 1 | `Infer.build_ctx/2:ret` |
| `Unk0455` | 1 | `Infer.build_ledger/2:p0` |
| `Unk0456` | 1 | `Infer.build_ledger/2:ret` |
| `Unk0457` | 13 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.cluster_name/2:p0`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0458` | 12 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.instantiate/5:p3`, `Infer.maybe_tuple/4:p2`, `Infer.ok_payload/3:p1`, `Infer.resolve_struct_params/4:p2`, `Infer.result_analysis/3:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0459` | 1 | `Infer.call_sig/6:p1` |
| `Unk0460` | 1 | `Infer.case_arm/1:p0` |
| `Unk0461` | 1 | `Infer.case_arm/1:ret` |
| `Unk0462` | 1 | `Infer.case_arm/1:ret` |
| `Unk0463` | 1 | `Infer.clear_xmod/0:ret` |
| `Unk0464` | 1 | `Infer.free_vars/2:ret` |
| `Unk0465` | 1 | `Infer.fresh_n/2:ret` |
| `Unk0466` | 2 | `Infer.freshen_tvars/2:p0`, `Infer.freshen_tvars/2:ret` |
| `Unk0467` | 1 | `Infer.freshen_tvars/2:ret` |
| `Unk0468` | 3 | `Infer.gen_pat/4:p0`, `Infer.gen_pat_cons/5:p0`, `Infer.gen_pat_cons/5:p1` |
| `Unk0469` | 1 | `Infer.generalize_map/3:p0` |
| `Unk0470` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0471` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0472` | 3 | `Infer.hole_or/2:p0`, `Infer.hole_or/2:p1`, `Infer.hole_or/2:ret` |
| `Unk0473` | 2 | `Infer.hole_sig?/1:p0`, `Infer.infer_group/2:ret` |
| `Unk0474` | 1 | `Infer.infer_group/2:p0` |
| `Unk0475` | 1 | `Infer.infer_group/2:p1` |
| `Unk0476` | 1 | `Infer.infer_group/2:p1` |
| `Unk0477` | 1 | `Infer.instantiate/5:p0` |
| `Unk0478` | 2 | `Infer.load_prelude_sigs/0:ret`, `Infer.prelude_sigs/0:ret` |
| `Unk0479` | 1 | `Infer.mark_num/2:ret` |
| `Unk0480` | 1 | `Infer.max_ph/1:p0` |
| `Unk0481` | 1 | `Infer.maybe_tuple/4:p0` |
| `Unk0482` | 1 | `Infer.mod_name/1:p0` |
| `Unk0483` | 1 | `Infer.ok_payload/3:p0` |
| `Unk0484` | 2 | `Infer.ok_payload/3:p2`, `Infer.result_analysis/3:p2` |
| `Unk0485` | 1 | `Infer.ok_payload/3:ret` |
| `Unk0486` | 1 | `Infer.parse_type/2:p0` |
| `Unk0487` | 1 | `Infer.parse_type/2:p1` |
| `Unk0488` | 2 | `Infer.parse_type/2:p1`, `Infer.tvar?/1:p0` |
| `Unk0489` | 1 | `Infer.prime_xmod/2:p0` |
| `Unk0490` | 1 | `Infer.prime_xmod/2:p1` |
| `Unk0491` | 1 | `Infer.prime_xmod/2:ret` |
| `Unk0492` | 1 | `Infer.put_slot/3:p0` |
| `Unk0493` | 1 | `Infer.put_slot/3:ret` |
| `Unk0494` | 1 | `Infer.render_wp/3:p1` |
| `Unk0495` | 1 | `Infer.resolve_program/2:p0` |
| `Unk0496` | 2 | `Infer.resolve_program/2:ret`, `Infer.whole_program/3:ret` |
| `Unk0497` | 1 | `Infer.resolve_struct_params/4:p0` |
| `Unk0498` | 1 | `Infer.resolve_struct_params/4:p1` |
| `Unk0499` | 1 | `Infer.result_analysis/3:p0` |
| `Unk0500` | 1 | `Infer.result_analysis/3:ret` |
| `Unk0501` | 1 | `Infer.result_tag/1:p0` |
| `Unk0502` | 1 | `Infer.result_tag/1:ret` |
| `Unk0503` | 1 | `Infer.result_tag/1:ret` |
| `Unk0504` | 1 | `Infer.sig_of/1:p0` |
| `Unk0505` | 1 | `Infer.sig_of/1:ret` |
| `Unk0506` | 1 | `Infer.sigvar_call/5:p1` |
| `Unk0507` | 1 | `Infer.sigvar_call/5:p2` |
| `Unk0508` | 1 | `Infer.sigvar_call/5:ret` |
| `Unk0509` | 1 | `Infer.slot_sig/3:p2` |
| `Unk0510` | 1 | `Infer.slot_sig/3:ret` |
| `Unk0511` | 1 | `Infer.tvar?/1:ret` |
| `Unk0512` | 1 | `Infer.tvar_name/1:p0` |
| `Unk0513` | 1 | `Infer.tvar_name/1:ret` |
| `Unk0514` | 1 | `Infer.unk_vars/2:ret` |
| `Unk0515` | 3 | `Infer.whole_program/3:p0`, `PortAnalysis.collect_groups/1:ret`, `PortAnalysis.param_name_index/1:p0` |
| `Unk0516` | 2 | `Infer.whole_program/3:p1`, `Transpile.stdlib_map/0:ret` |
| `Unk0517` | 2 | `Infer.whole_program/3:p2`, `PortAnalysis.cluster_sums/1:ret` |
| `Unk0518` | 1 | `Infer.xmod_cache/0:ret` |
| `Unk0519` | 2 | `Interp.concat_chain/1:p0`, `Interp.concat_chain/1:ret` |
| `Unk0520` | 1 | `Interp.resolve_part/4:p0` |
| `Unk0521` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0522` | 2 | `Interp.resolve_part/4:ret`, `Interp.stringify/3:ret` |
| `Unk0523` | 1 | `JS.all_funcs/1:p0` |
| `Unk0524` | 2 | `JS.all_funcs/1:p0`, `JS.all_funcs/1:ret` |
| `Unk0525` | 1 | `JS.arm_return/3:p0` |
| `Unk0526` | 1 | `JS.arm_return/3:p1` |
| `Unk0527` | 1 | `JS.bind_lines/1:p0` |
| `Unk0528` | 4 | `JS.block_return/2:p0`, `JVM.block_value/1:p0`, `Shadow.ded_block/4:ret`, `Shadow.dedup/3:ret` |
| `Unk0529` | 1 | `JS.case_arm_js/2:p0` |
| `Unk0530` | 1 | `JS.clause_js/2:p0` |
| `Unk0531` | 4 | `JS.clause_return/3:p1`, `JS.guarded_return/4:p2`, `JVM.clause_value/2:p1`, `Shadow.dedup/3:p1` |
| `Unk0532` | 1 | `JS.cp_lit/2:p0` |
| `Unk0533` | 1 | `JS.dispatcher_js/5:p0` |
| `Unk0534` | 1 | `JS.dispatcher_js/5:p1` |
| `Unk0535` | 1 | `JS.dispatcher_js/5:p2` |
| `Unk0536` | 1 | `JS.dispatcher_js/5:p3` |
| `Unk0537` | 2 | `JS.float?/1:p0`, `JS.num_js/2:p0` |
| `Unk0538` | 1 | `JS.guarded_return/4:p1` |
| `Unk0539` | 3 | `JS.js_atom/1:p0`, `JS.js_str/1:p0`, `JS.lit_js/2:p0` |
| `Unk0540` | 1 | `JS.js_guard!/4:p1` |
| `Unk0541` | 1 | `JS.js_guard!/4:p2` |
| `Unk0542` | 1 | `JS.js_guard!/4:p3` |
| `Unk0543` | 1 | `JS.js_guard!/4:ret` |
| `Unk0544` | 1 | `JS.js_number_int?/1:p0` |
| `Unk0545` | 1 | `JS.mangle/3:p0` |
| `Unk0546` | 1 | `JS.mangle/3:p1` |
| `Unk0547` | 1 | `JS.mangle/3:p2` |
| `Unk0548` | 1 | `JS.match_elems/3:p0` |
| `Unk0549` | 1 | `JS.match_elems/3:ret` |
| `Unk0550` | 1 | `JS.paren/2:p0` |
| `Unk0551` | 1 | `JS.paren/2:p1` |
| `Unk0552` | 1 | `JS.pascal?/1:p0` |
| `Unk0553` | 1 | `JS.pat_match/3:ret` |
| `Unk0554` | 1 | `JS.reject_mixed_int_mode!/1:ret` |
| `Unk0555` | 1 | `JS.reject_wide_int!/2:p0` |
| `Unk0556` | 1 | `JS.reject_wide_int!/2:p1` |
| `Unk0557` | 1 | `JS.reject_wide_int!/2:ret` |
| `Unk0558` | 1 | `JS.stmt_js/2:p0` |
| `Unk0559` | 1 | `JS.stmt_return/2:p0` |
| `Unk0560` | 1 | `JS.stmt_return/2:p1` |
| `Unk0561` | 1 | `JS.struct_name_set/1:ret` |
| `Unk0562` | 1 | `JS.sum_ctor_map/1:ret` |
| `Unk0563` | 1 | `JS.sum_guard_js/1:p0` |
| `Unk0564` | 2 | `JVM.all_funcs/1:p0`, `JVM.all_funcs/1:ret` |
| `Unk0565` | 1 | `JVM.all_funcs/1:p0` |
| `Unk0566` | 1 | `JVM.bind_str/1:p0` |
| `Unk0567` | 1 | `JVM.case_arms/2:p0` |
| `Unk0568` | 1 | `JVM.case_arms/2:ret` |
| `Unk0569` | 1 | `JVM.case_arms/2:ret` |
| `Unk0570` | 4 | `JVM.clause_lines/1:p0`, `JVM.closed_or_cond/3:p2`, `JVM.prepend_if/3:p2`, `JVM.run_or_cond/3:p2` |
| `Unk0571` | 1 | `JVM.clause_match/1:p0` |
| `Unk0572` | 1 | `JVM.clause_match/1:ret` |
| `Unk0573` | 3 | `JVM.closed_or_cond/3:p0`, `JVM.prepend_if/3:p0`, `JVM.run_or_cond/3:p0` |
| `Unk0574` | 1 | `JVM.function_kt/1:p0` |
| `Unk0575` | 1 | `JVM.guarded_arm/2:p1` |
| `Unk0576` | 1 | `JVM.guarded_return/3:p0` |
| `Unk0577` | 1 | `JVM.guarded_return/3:p1` |
| `Unk0578` | 1 | `JVM.guarded_return/3:p2` |
| `Unk0579` | 1 | `JVM.kotlin_module/2:p1` |
| `Unk0580` | 2 | `JVM.kt_str/1:p0`, `JVM.lit_kt/1:p0` |
| `Unk0581` | 1 | `JVM.kt_type/1:ret` |
| `Unk0582` | 1 | `JVM.pat_match/2:ret` |
| `Unk0583` | 1 | `JVM.stmt_kt/1:p0` |
| `Unk0584` | 1 | `JVM.stmt_value/1:p0` |
| `Unk0585` | 1 | `JVM.sum_decl/1:p0` |
| `Unk0586` | 1 | `JVM.to_jar/3:p2` |
| `Unk0587` | 1 | `JVM.to_jar/3:ret` |
| `Unk0588` | 1 | `JVM.variant_decl/2:p0` |
| `Unk0589` | 1 | `JVM.variant_decl/2:p1` |
| `Unk0590` | 4 | `Lexer.binify/1:ret`, `Lexer.capture_hole/3:ret`, `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0591` | 1 | `Lexer.capture_hole/3:ret` |
| `Unk0592` | 1 | `Lexer.char_escape/1:p0` |
| `Unk0593` | 2 | `Lexer.char_escape/1:ret`, `Lexer.parse_hex!/1:p0` |
| `Unk0594` | 2 | `Lexer.close_char/1:ret`, `Lexer.lex_char/1:ret` |
| `Unk0595` | 1 | `Lexer.collapse_nl/1:p0` |
| `Unk0596` | 1 | `Lexer.collapse_nl/1:ret` |
| `Unk0597` | 1 | `Lexer.detokenize/2:p0` |
| `Unk0598` | 1 | `Lexer.detokenize/2:p1` |
| `Unk0599` | 1 | `Lexer.detokenize/2:ret` |
| `Unk0600` | 1 | `Lexer.escape_str/1:p0` |
| `Unk0601` | 75 | `Lexer.expr_tokens/1:ret`, `Pratt.climb/3:p1`, `Pratt.climb/3:ret`, `Pratt.collect_dots/2:p1`, `Pratt.collect_dots/2:ret`, `Pratt.expect_kw/2:p0`, `Pratt.expect_kw/2:ret`, `Pratt.expect_op/2:p0`, `Pratt.expect_op/2:ret`, `Pratt.expect_rbracket/1:p0`, `Pratt.expect_rbracket/1:ret`, `Pratt.expect_rparen/1:p0`, `Pratt.expect_rparen/1:ret`, `Pratt.finish_arg/2:p1`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:p0`, `Pratt.parse_args/1:ret`, `Pratt.parse_arms/2:p0`, `Pratt.parse_arms/2:ret`, `Pratt.parse_block/1:p0`, `Pratt.parse_block/1:ret`, `Pratt.parse_capture/1:p0`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:p0`, `Pratt.parse_case/1:ret`, `Pratt.parse_expr/2:p0`, `Pratt.parse_expr/2:ret`, `Pratt.parse_if/1:p0`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:p0`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:p0`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p0`, `Pratt.parse_map/2:ret`, `Pratt.parse_param/1:p0`, `Pratt.parse_param/1:ret`, `Pratt.parse_params/1:p0`, `Pratt.parse_params/1:ret`, `Pratt.parse_pat/1:p0`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_args/2:p0`, `Pratt.parse_pat_args/2:ret`, `Pratt.parse_pat_fields/2:p0`, `Pratt.parse_pat_fields/2:ret`, `Pratt.parse_pat_list/2:p0`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p0`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p0`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_path/1:p0`, `Pratt.parse_path/1:ret`, `Pratt.parse_pats/2:p0`, `Pratt.parse_postfix/2:p1`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:p0`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:p0`, `Pratt.parse_primary/1:ret`, `Pratt.parse_stmt/1:p0`, `Pratt.parse_stmt/1:ret`, `Pratt.parse_stmts/2:p0`, `Pratt.parse_stmts/2:ret`, `Pratt.parse_tuple/2:p0`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_type/1:p0`, `Pratt.parse_type/1:ret`, `Pratt.parse_type_args/2:p0`, `Pratt.parse_type_args/2:ret`, `Pratt.parse_with/1:p0`, `Pratt.parse_with/1:ret`, `Pratt.parse_with_clauses/2:p0`, `Pratt.parse_with_clauses/2:ret`, `Pratt.peek_infix/1:p0` |
| `Unk0602` | 2 | `Lexer.lex/2:p1`, `Lexer.word/1:ret` |
| `Unk0603` | 2 | `Lexer.lex/2:ret`, `Lexer.tokenize_trivia/1:ret` |
| `Unk0604` | 1 | `Lexer.lex_char/1:ret` |
| `Unk0605` | 2 | `Lexer.lex_parts/3:p2`, `Lexer.lex_parts/3:ret` |
| `Unk0606` | 1 | `Lexer.lex_parts/3:ret` |
| `Unk0607` | 2 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:ret` |
| `Unk0608` | 1 | `Lexer.lex_string_token/1:ret` |
| `Unk0609` | 3 | `Lexer.lex_string_token/1:ret`, `Lexer.string_token/1:p0`, `Lexer.string_token/1:ret` |
| `Unk0610` | 1 | `Lexer.punct/1:ret` |
| `Unk0611` | 1 | `Lexer.strip_trivia/1:p0` |
| `Unk0612` | 1 | `Lexer.strip_trivia/1:ret` |
| `Unk0613` | 1 | `Lexer.take_comment/1:ret` |
| `Unk0614` | 4 | `Lexer.take_hex/2:p0`, `Lexer.take_hex/2:ret`, `Lexer.take_hex/3:p0`, `Lexer.take_hex/3:ret` |
| `Unk0615` | 1 | `Lexer.tok_str/2:p0` |
| `Unk0616` | 1 | `Lexer.tokenize/1:p0` |
| `Unk0617` | 1 | `Lexer.tokenize/1:ret` |
| `Unk0618` | 2 | `Livebook.eval/1:p0`, `Livebook.run/2:p1` |
| `Unk0619` | 2 | `Livebook.eval/1:ret`, `Livebook.output/1:ret` |
| `Unk0620` | 1 | `Livebook.reset/0:ret` |
| `Unk0621` | 2 | `Livebook.run/2:p0`, `Livebook.run/2:ret` |
| `Unk0622` | 1 | `Livebook.run/2:ret` |
| `Unk0623` | 1 | `Livebook.session_pid/0:ret` |
| `Unk0624` | 4 | `Lower.add_list_elem_vars/2:p0`, `Lower.add_list_elem_vars/2:ret`, `Lower.add_var/2:p0`, `Lower.add_var/2:ret` |
| `Unk0625` | 1 | `Lower.add_list_elem_vars/2:p1` |
| `Unk0626` | 1 | `Lower.add_var/2:p1` |
| `Unk0627` | 1 | `Lower.all_pat_vars/1:ret` |
| `Unk0628` | 1 | `Lower.arm_rebinds/3:p0` |
| `Unk0629` | 3 | `Lower.arm_rebinds/3:p1`, `Lower.iso_cons_positions/1:ret`, `Lower.rust_scrut/2:p1` |
| `Unk0630` | 4 | `Lower.arm_rebinds/3:p2`, `Lower.collect_ids/2:p1`, `Lower.collect_ids/2:ret`, `Lower.used_ids/1:ret` |
| `Unk0631` | 1 | `Lower.arm_rebinds/3:ret` |
| `Unk0632` | 1 | `Lower.assoc/1:ret` |
| `Unk0633` | 1 | `Lower.body_ast/2:p0` |
| `Unk0634` | 1 | `Lower.body_ast/2:p1` |
| `Unk0635` | 1 | `Lower.body_ast/2:ret` |
| `Unk0636` | 5 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p0`, `Lower.param_rtypes/2:p1` |
| `Unk0637` | 4 | `Lower.borrow_arg/5:p2`, `Lower.insert_borrows/4:p1`, `Lower.owned_arg?/2:p1`, `Lower.param_rtypes/2:p1` |
| `Unk0638` | 3 | `Lower.borrow_arg/5:p3`, `Lower.borrow_value/2:p1`, `Lower.insert_borrows/4:p3` |
| `Unk0639` | 3 | `Lower.borrow_arg/5:p4`, `Lower.insert_borrows/4:p2`, `Lower.owned_field_var?/2:p1` |
| `Unk0640` | 1 | `Lower.borrow_arg/5:ret` |
| `Unk0641` | 1 | `Lower.borrowed_in_pat/2:ret` |
| `Unk0642` | 1 | `Lower.borrowed_vars/2:p0` |
| `Unk0643` | 1 | `Lower.borrowed_vars/2:p1` |
| `Unk0644` | 1 | `Lower.borrowed_vars/2:ret` |
| `Unk0645` | 1 | `Lower.build_env/3:p1` |
| `Unk0646` | 1 | `Lower.build_env/3:p2` |
| `Unk0647` | 2 | `Lower.build_env/3:ret`, `Lower.check!/2:p1` |
| `Unk0648` | 3 | `Lower.build_meta/1:ret`, `Lower.ctx/4:p0`, `Lower.to_rust/6:p2` |
| `Unk0649` | 4 | `Lower.build_struct_meta/1:ret`, `Lower.ctx/4:p1`, `Lower.to_elixir/4:p3`, `Lower.to_rust/6:p4` |
| `Unk0650` | 9 | `Lower.case_guard/3:p1`, `Lower.disp/2:p1`, `Lower.emit/3:p1`, `Lower.emit_ast/2:p1`, `Lower.emit_block/3:p1`, `Lower.emit_expr/2:p1`, `Lower.guard_kw/1:p0`, `Lower.guard_str/4:p1`, `Lower.p/4:p2` |
| `Unk0651` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0652` | 13 | `Lower.case_guard/3:p2`, `Lower.coerce_string_ast/2:p1`, `Lower.coerce_string_branch/2:p1`, `Lower.emit/3:p2`, `Lower.emit_block/3:p2`, `Lower.guard_str/4:p2`, `Lower.p/4:p3`, `Lower.result_payload/3:p2`, `Lower.rust_case/4:p3`, `Lower.rust_owned_elem/2:p1`, `Lower.slice_var?/2:p1`, `Lower.tail_slice_id?/2:p1`, `Lower.with_chain_rs/4:p3` |
| `Unk0653` | 1 | `Lower.char_vars/2:p0` |
| `Unk0654` | 1 | `Lower.char_vars/2:p1` |
| `Unk0655` | 1 | `Lower.char_vars/2:ret` |
| `Unk0656` | 14 | `Lower.check!/2:p0`, `Lower.compile/5:p1`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p1`, `Lower.elixir_clauses/3:p0`, `Lower.fn_all_tvars/3:p0`, `Lower.infer_concrete_params/3:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/2:p0`, `Lower.parametric_used?/2:p0`, `Lower.rust_fn/4:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_elixir/4:p0`, `Lower.to_rust/6:p0` |
| `Unk0657` | 1 | `Lower.check!/2:ret` |
| `Unk0658` | 2 | `Lower.collect_ids/2:p0`, `Lower.used_ids/1:p0` |
| `Unk0659` | 1 | `Lower.collect_owned_field_vars/3:p0` |
| `Unk0660` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0661` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/4:p1`, `Lower.rust_impl/4:p2`, `Lower.rust_impl_method/6:p3`, `Lower.trait_impl_block/4:p2`, `Lower.user_type?/2:p1` |
| `Unk0662` | 6 | `Lower.collect_owned_field_vars/3:p2`, `Lower.collect_owned_field_vars/3:ret`, `Lower.ofb/3:p2`, `Lower.ofb/3:ret`, `Lower.owned_field_binders/2:ret`, `Lower.slice_binders/2:ret` |
| `Unk0663` | 1 | `Lower.compile/5:p2` |
| `Unk0664` | 1 | `Lower.compile/5:p3` |
| `Unk0665` | 1 | `Lower.compile_beam/4:p2` |
| `Unk0666` | 1 | `Lower.compile_beam/4:p3` |
| `Unk0667` | 1 | `Lower.compile_elixir/4:p2` |
| `Unk0668` | 1 | `Lower.compile_elixir/4:p3` |
| `Unk0669` | 1 | `Lower.compile_module/1:p0` |
| `Unk0670` | 1 | `Lower.compile_module_beam/1:p0` |
| `Unk0671` | 1 | `Lower.cons_tail_names/1:ret` |
| `Unk0672` | 3 | `Lower.const_set/1:p0`, `Lower.ex_const/2:p0`, `Lower.rust_const/2:p0` |
| `Unk0673` | 2 | `Lower.const_set/1:ret`, `Lower.ctx/4:p2` |
| `Unk0674` | 3 | `Lower.core_pat_rs/2:p1`, `Lower.pat_rs/2:p1`, `Lower.resolve_rust_pats/2:p1` |
| `Unk0675` | 1 | `Lower.core_pat_vars/1:ret` |
| `Unk0676` | 1 | `Lower.ctx/4:p3` |
| `Unk0677` | 2 | `Lower.deref_ids/2:p0`, `Lower.deref_ids/2:ret` |
| `Unk0678` | 1 | `Lower.deref_ids/2:p1` |
| `Unk0679` | 2 | `Lower.elixir_clauses/3:p1`, `Lower.ex_const/2:p1` |
| `Unk0680` | 1 | `Lower.emit_ast/2:ret` |
| `Unk0681` | 1 | `Lower.emit_ctx/1:p0` |
| `Unk0682` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0683` | 5 | `Lower.emit_ctx/1:ret`, `Lower.rust_fn/4:p3`, `Lower.rust_impl/4:p3`, `Lower.rust_impl_method/6:p5`, `Lower.trait_impl_block/4:p3` |
| `Unk0684` | 1 | `Lower.emit_expr/2:ret` |
| `Unk0685` | 2 | `Lower.enum_generics/2:p0`, `Lower.enum_generics/2:p1` |
| `Unk0686` | 1 | `Lower.enum_generics/2:p1` |
| `Unk0687` | 1 | `Lower.ex_struct/1:p0` |
| `Unk0688` | 1 | `Lower.ex_typespec/1:p0` |
| `Unk0689` | 1 | `Lower.ex_use/1:p0` |
| `Unk0690` | 2 | `Lower.fn_all_tvars/3:p1`, `Lower.pair_inst/2:ret` |
| `Unk0691` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0692` | 3 | `Lower.fn_all_tvars/3:p2`, `Lower.infer_concrete_params/3:p2`, `Lower.pair_inst/2:p1` |
| `Unk0693` | 1 | `Lower.guard_str/4:p0` |
| `Unk0694` | 1 | `Lower.guard_str/4:p3` |
| `Unk0695` | 1 | `Lower.impl_param/2:p0` |
| `Unk0696` | 1 | `Lower.infer_concrete_params/3:p1` |
| `Unk0697` | 1 | `Lower.infer_tvar_binding/2:p0` |
| `Unk0698` | 1 | `Lower.infer_tvar_binding/2:p1` |
| `Unk0699` | 1 | `Lower.infer_tvar_binding/2:ret` |
| `Unk0700` | 1 | `Lower.list_rpat?/1:p0` |
| `Unk0701` | 1 | `Lower.member_scan/3:p0` |
| `Unk0702` | 3 | `Lower.member_scan/3:p1`, `Lower.strip_prefix/2:p1`, `Lower.word_scan/4:p1` |
| `Unk0703` | 1 | `Lower.module_elixir/1:p0` |
| `Unk0704` | 1 | `Lower.module_rust/1:p0` |
| `Unk0705` | 2 | `Lower.ofb/3:p0`, `Lower.owned_field_binders/2:p0` |
| `Unk0706` | 1 | `Lower.owned_scrut?/2:p0` |
| `Unk0707` | 1 | `Lower.owned_str_arg/1:p0` |
| `Unk0708` | 1 | `Lower.owned_str_arg/1:ret` |
| `Unk0709` | 2 | `Lower.parametric_param_map/1:ret`, `Lower.rust_enum/3:p2` |
| `Unk0710` | 2 | `Lower.parametric_used?/2:p1`, `Lower.word_member?/2:p1` |
| `Unk0711` | 2 | `Lower.pascal?/1:p0`, `Lower.variant_info/2:p1` |
| `Unk0712` | 1 | `Lower.pipe_to_call/2:p0` |
| `Unk0713` | 1 | `Lower.proto_method_traits/1:ret` |
| `Unk0714` | 1 | `Lower.pub_sig_type_names/1:p0` |
| `Unk0715` | 1 | `Lower.pub_sig_type_names/1:ret` |
| `Unk0716` | 1 | `Lower.ref_type/2:p1` |
| `Unk0717` | 1 | `Lower.resolve_consts/2:p1` |
| `Unk0718` | 2 | `Lower.resolve_structs/2:p1`, `Lower.struct_pairs/4:p3` |
| `Unk0719` | 6 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_info/2:ret`, `Lower.variant_lit/2:p0`, `Lower.variant_pairs/3:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0720` | 3 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0721` | 1 | `Lower.result_parts/1:ret` |
| `Unk0722` | 2 | `Lower.rewrite_proto_calls/2:p0`, `Lower.rewrite_proto_calls/2:ret` |
| `Unk0723` | 1 | `Lower.rewrite_proto_calls/2:p1` |
| `Unk0724` | 1 | `Lower.rust_case/4:p1` |
| `Unk0725` | 1 | `Lower.rust_generics/1:p0` |
| `Unk0726` | 1 | `Lower.rust_impl_method/6:p0` |
| `Unk0727` | 1 | `Lower.rust_impl_method/6:p1` |
| `Unk0728` | 1 | `Lower.rust_lit_type/1:p0` |
| `Unk0729` | 1 | `Lower.rust_proto_body/3:p0` |
| `Unk0730` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0731` | 1 | `Lower.rust_proto_body/3:p1` |
| `Unk0732` | 1 | `Lower.rust_proto_body/3:p2` |
| `Unk0733` | 1 | `Lower.rust_proto_body/3:ret` |
| `Unk0734` | 1 | `Lower.rust_protocols/4:ret` |
| `Unk0735` | 1 | `Lower.rust_scrut/2:p0` |
| `Unk0736` | 1 | `Lower.rust_struct/2:p0` |
| `Unk0737` | 1 | `Lower.rust_struct/2:p1` |
| `Unk0738` | 1 | `Lower.rust_trait/1:p0` |
| `Unk0739` | 1 | `Lower.rust_use/1:p0` |
| `Unk0740` | 1 | `Lower.rustify_parametric/2:p1` |
| `Unk0741` | 2 | `Lower.sig_param/2:p1`, `Lower.trait_params/2:p1` |
| `Unk0742` | 1 | `Lower.slice_binders/2:p0` |
| `Unk0743` | 1 | `Lower.slice_elem_vars/1:ret` |
| `Unk0744` | 1 | `Lower.str_lit/1:p0` |
| `Unk0745` | 2 | `Lower.strip_prefix/2:p0`, `Lower.strip_prefix/2:ret` |
| `Unk0746` | 1 | `Lower.strip_prefix/2:ret` |
| `Unk0747` | 1 | `Lower.struct_pairs/4:p0` |
| `Unk0748` | 1 | `Lower.struct_pairs/4:p1` |
| `Unk0749` | 1 | `Lower.struct_pairs/4:ret` |
| `Unk0750` | 1 | `Lower.subst_assoc/2:p1` |
| `Unk0751` | 2 | `Lower.tail_expr/1:p0`, `Lower.tail_expr/1:ret` |
| `Unk0752` | 1 | `Lower.to_elixir/4:p2` |
| `Unk0753` | 1 | `Lower.to_elixir/4:ret` |
| `Unk0754` | 1 | `Lower.to_rust/6:p3` |
| `Unk0755` | 1 | `Lower.to_rust/6:p5` |
| `Unk0756` | 1 | `Lower.to_rust/6:ret` |
| `Unk0757` | 1 | `Lower.tvar_name?/1:p0` |
| `Unk0758` | 1 | `Lower.type_idents/1:p0` |
| `Unk0759` | 1 | `Lower.type_idents/1:ret` |
| `Unk0760` | 1 | `Lower.type_param_tvars/1:p0` |
| `Unk0761` | 1 | `Lower.type_param_tvars/1:ret` |
| `Unk0762` | 1 | `Lower.user_type?/2:p0` |
| `Unk0763` | 2 | `Lower.variant_lit/2:p1`, `Lower.variant_pairs/3:ret` |
| `Unk0764` | 2 | `Lower.widen_char_arith/2:p1`, `Lower.wrap_char/2:p1` |
| `Unk0765` | 1 | `Lower.with_chain_rs/4:p0` |
| `Unk0766` | 1 | `Lower.word_member?/2:p0` |
| `Unk0767` | 1 | `Lower.word_scan/4:p0` |
| `Unk0768` | 4 | `Macro.binders_here/1:p0`, `Macro.collect_binders/1:p0`, `Macro.freshen/2:p0`, `Macro.rename/2:p0` |
| `Unk0769` | 2 | `Macro.binders_here/1:ret`, `Macro.collect_binders/1:ret` |
| `Unk0770` | 1 | `Macro.build_env/1:p0` |
| `Unk0771` | 1 | `Macro.check_portable!/2:p0` |
| `Unk0772` | 1 | `Macro.check_portable!/2:ret` |
| `Unk0773` | 1 | `Macro.expand/3:p2` |
| `Unk0774` | 1 | `Macro.freshen/2:p1` |
| `Unk0775` | 4 | `Macro.freshen/2:ret`, `Macro.rename/2:p1`, `Macro.rename/2:ret`, `Macro.substitute/2:p0` |
| `Unk0776` | 1 | `Macro.rename/2:p1` |
| `Unk0777` | 1 | `Macro.substitute/2:p1` |
| `Unk0778` | 1 | `Opaque.do_erase/2:p0` |
| `Unk0779` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0780` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0781` | 1 | `Opaque.erase_clause/3:p0` |
| `Unk0782` | 1 | `Opaque.erase_clause/3:p1` |
| `Unk0783` | 1 | `Opaque.erase_clause/3:p2` |
| `Unk0784` | 1 | `Opaque.erase_const/2:p0` |
| `Unk0785` | 1 | `Opaque.erase_const/2:p1` |
| `Unk0786` | 3 | `Opaque.erase_ctx/1:p0`, `Opaque.opaques/1:p0`, `Opaque.opaques/1:ret` |
| `Unk0787` | 1 | `Opaque.erase_func/2:p0` |
| `Unk0788` | 1 | `Opaque.erase_mod/2:p0` |
| `Unk0789` | 1 | `Opaque.erase_struct/2:p0` |
| `Unk0790` | 1 | `Opaque.erase_type/2:p0` |
| `Unk0791` | 1 | `Opaque.erase_variant/2:p0` |
| `Unk0792` | 1 | `Opaque.erase_variant/2:p1` |
| `Unk0793` | 1 | `Opaque.opaques/1:p0` |
| `Unk0794` | 4 | `Opaque.strip/3:p0`, `Opaque.strip/3:ret`, `Opaque.strip_into/3:p0`, `Opaque.strip_into/3:ret` |
| `Unk0795` | 2 | `Opaque.strip/3:p1`, `Opaque.strip_into/3:p1` |
| `Unk0796` | 4 | `Opaque.subst/2:p0`, `Opaque.subst/2:ret`, `Opaque.subst_fix/4:p0`, `Opaque.subst_fix/4:ret` |
| `Unk0797` | 2 | `Opaque.subst/2:p1`, `Opaque.subst_fix/4:p1` |
| `Unk0798` | 1 | `Opaque.subst_fix/4:p2` |
| `Unk0799` | 2 | `PatternLower.lower/2:ret`, `PatternLower.lower_list/3:ret` |
| `Unk0800` | 1 | `PatternLower.lower_clause/2:p0` |
| `Unk0801` | 1 | `PatternLower.lower_many/2:ret` |
| `Unk0802` | 2 | `PortAnalysis.analyze/1:p0`, `PortAnalysis.src_of/2:p0` |
| `Unk0803` | 1 | `PortAnalysis.analyze/1:ret` |
| `Unk0804` | 3 | `PortAnalysis.case_arm_sets/1:p0`, `PortAnalysis.clause_head_sets/1:p0`, `PortAnalysis.dispatch_sets/1:p0` |
| `Unk0805` | 2 | `PortAnalysis.case_arm_sets/1:ret`, `PortAnalysis.clause_head_sets/1:ret` |
| `Unk0806` | 2 | `PortAnalysis.cluster_sums/1:p0`, `PortAnalysis.dispatch_sets/1:ret` |
| `Unk0807` | 1 | `PortAnalysis.collect_errors/2:p0` |
| `Unk0808` | 2 | `PortAnalysis.collect_errors/2:p1`, `PortAnalysis.collect_errors/2:ret` |
| `Unk0809` | 1 | `PortAnalysis.collect_groups/1:p0` |
| `Unk0810` | 1 | `PortAnalysis.collect_structs/2:p0` |
| `Unk0811` | 2 | `PortAnalysis.collect_structs/2:p1`, `PortAnalysis.collect_structs/2:ret` |
| `Unk0812` | 1 | `PortAnalysis.error_proposal/1:p0` |
| `Unk0813` | 1 | `PortAnalysis.error_proposal/1:ret` |
| `Unk0814` | 1 | `PortAnalysis.error_shape/1:p0` |
| `Unk0815` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0816` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0817` | 6 | `PortAnalysis.errors_section/1:p0`, `PortAnalysis.holes_section/1:p0`, `PortAnalysis.sigs_section/1:p0`, `PortAnalysis.summary_section/1:p0`, `PortAnalysis.sums_section/1:p0`, `PortAnalysis.to_markdown/1:p0` |
| `Unk0818` | 1 | `PortAnalysis.head_name_pats/1:p0` |
| `Unk0819` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0820` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0821` | 2 | `PortAnalysis.module_name/1:p0`, `PortAnalysis.module_report/3:p1` |
| `Unk0822` | 1 | `PortAnalysis.module_report/3:p0` |
| `Unk0823` | 3 | `PortAnalysis.module_report/3:p2`, `PortAnalysis.src_of/2:ret`, `Transpile.inferred/1:p0` |
| `Unk0824` | 1 | `PortAnalysis.module_report/3:ret` |
| `Unk0825` | 1 | `PortAnalysis.needs_review?/1:p0` |
| `Unk0826` | 1 | `PortAnalysis.param_name_index/1:ret` |
| `Unk0827` | 1 | `PortAnalysis.parse/1:p0` |
| `Unk0828` | 1 | `PortAnalysis.parse/1:ret` |
| `Unk0829` | 1 | `PortAnalysis.pascal/1:p0` |
| `Unk0830` | 1 | `PortAnalysis.pascal/1:ret` |
| `Unk0831` | 1 | `PortAnalysis.pattern_structs/1:p0` |
| `Unk0832` | 1 | `PortAnalysis.pattern_structs/1:ret` |
| `Unk0833` | 1 | `PortAnalysis.reach_note/1:p0` |
| `Unk0834` | 1 | `PortAnalysis.reach_note/1:ret` |
| `Unk0835` | 1 | `PortAnalysis.short/1:p0` |
| `Unk0836` | 1 | `PortAnalysis.src_of/2:p1` |
| `Unk0837` | 1 | `PortAnalysis.to_markdown/1:ret` |
| `Unk0838` | 3 | `Pratt.after_paren/2:p0`, `Pratt.after_paren/2:ret`, `Pratt.lambda_ahead?/1:p0` |
| `Unk0839` | 1 | `Pratt.assoc/1:ret` |
| `Unk0840` | 4 | `Pratt.climb/3:p0`, `Pratt.climb/3:ret`, `Pratt.parse_expr/2:ret`, `Pratt.same_level_root?/2:p0` |
| `Unk0841` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0842` | 3 | `Pratt.collect_dots/2:p0`, `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0843` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0844` | 5 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:p0`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0845` | 3 | `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:ret`, `Pratt.parse_block/1:ret` |
| `Unk0846` | 3 | `Pratt.finish_arg/2:p0`, `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:ret` |
| `Unk0847` | 2 | `Pratt.here/1:p0`, `Pratt.tok_desc/1:p0` |
| `Unk0848` | 1 | `Pratt.int_of/1:p0` |
| `Unk0849` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0850` | 22 | `Pratt.int_of/1:ret`, `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:p1`, `Pratt.parse_map/2:ret`, `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:p1`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:p1`, `Pratt.parse_pat_tuple/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:p1`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0851` | 1 | `Pratt.level/1:ret` |
| `Unk0852` | 1 | `Pratt.opinfo/1:ret` |
| `Unk0853` | 2 | `Pratt.parse_arms/2:p1`, `Pratt.parse_arms/2:ret` |
| `Unk0854` | 13 | `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:ret`, `Pratt.parse_postfix/2:p0`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret`, `Pratt.str_interp/1:ret` |
| `Unk0855` | 1 | `Pratt.parse_list/2:p1` |
| `Unk0856` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0857` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0858` | 1 | `Pratt.parse_params/1:ret` |
| `Unk0859` | 4 | `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:ret` |
| `Unk0860` | 2 | `Pratt.parse_pat_args/2:p1`, `Pratt.parse_pat_args/2:ret` |
| `Unk0861` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0862` | 2 | `Pratt.parse_pat_fields/2:p1`, `Pratt.parse_pat_fields/2:ret` |
| `Unk0863` | 1 | `Pratt.parse_pat_list/2:p1` |
| `Unk0864` | 3 | `Pratt.parse_pats/1:ret`, `Pratt.parse_pats/2:p1`, `Pratt.parse_pats/2:ret` |
| `Unk0865` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0866` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk0867` | 2 | `Pratt.parse_stmts/2:p1`, `Pratt.parse_stmts/2:ret` |
| `Unk0868` | 2 | `Pratt.parse_type_args/2:p1`, `Pratt.parse_type_args/2:ret` |
| `Unk0869` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0870` | 2 | `Pratt.parse_with_clauses/2:p1`, `Pratt.parse_with_clauses/2:ret` |
| `Unk0871` | 1 | `Pratt.pascal?/1:p0` |
| `Unk0872` | 1 | `Pratt.sexpr_pat/1:p0` |
| `Unk0873` | 1 | `Pratt.sexpr_stmt/1:p0` |
| `Unk0874` | 1 | `Pratt.str_interp/1:p0` |
| `Unk0875` | 1 | `Prim.names/0:ret` |
| `Unk0876` | 1 | `Prim.overflow_ops/0:ret` |
| `Unk0877` | 1 | `Protocol.check_assoc!/2:ret` |
| `Unk0878` | 1 | `Protocol.check_impl/3:p0` |
| `Unk0879` | 3 | `Protocol.check_impl/3:p1`, `Protocol.expand/5:p0`, `Protocol.impl_methods/2:p1` |
| `Unk0880` | 5 | `Protocol.check_impl/3:p2`, `Protocol.check_no_overlap/3:p1`, `Protocol.dispatcher/4:p3`, `Protocol.guard_for!/3:p2`, `Protocol.registry/2:ret` |
| `Unk0881` | 1 | `Protocol.check_impl/3:ret` |
| `Unk0882` | 4 | `Protocol.check_no_overlap/3:p0`, `Protocol.dispatcher/4:p2`, `Protocol.expand/5:p1`, `Protocol.impl_methods/2:p0` |
| `Unk0883` | 2 | `Protocol.check_no_overlap/3:p2`, `Protocol.runtime_dispatch_target?/1:p0` |
| `Unk0884` | 1 | `Protocol.check_no_overlap/3:ret` |
| `Unk0885` | 2 | `Protocol.dispatcher/4:p0`, `Protocol.guard_for!/3:p1` |
| `Unk0886` | 1 | `Protocol.dispatcher/4:p1` |
| `Unk0887` | 1 | `Protocol.dispatcher/4:ret` |
| `Unk0888` | 1 | `Protocol.dispatcher_params/2:p0` |
| `Unk0889` | 1 | `Protocol.dispatcher_params/2:ret` |
| `Unk0890` | 1 | `Protocol.guard_for!/3:ret` |
| `Unk0891` | 1 | `Protocol.mangle/3:p0` |
| `Unk0892` | 1 | `Protocol.mangle/3:p1` |
| `Unk0893` | 1 | `Protocol.mangle/3:p2` |
| `Unk0894` | 1 | `Protocol.param_type/1:p0` |
| `Unk0895` | 1 | `Protocol.param_type/1:ret` |
| `Unk0896` | 1 | `Protocol.registry/2:p0` |
| `Unk0897` | 1 | `Protocol.registry/2:p1` |
| `Unk0898` | 1 | `Protocol.subst_self/2:p0` |
| `Unk0899` | 1 | `Protocol.subst_self/2:p1` |
| `Unk0900` | 1 | `Protocol.subst_self/2:ret` |
| `Unk0901` | 1 | `Protocol.sum_guard/1:p0` |
| `Unk0902` | 1 | `Protocol.tag_disjunction/2:p0` |
| `Unk0903` | 1 | `Protocol.tag_disjunction/2:p1` |
| `Unk0904` | 1 | `Range.check/3:p0` |
| `Unk0905` | 1 | `Range.check/3:p1` |
| `Unk0906` | 1 | `Range.lit/1:p0` |
| `Unk0907` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0908` | 8 | `Reach.all_emittable?/2:p0`, `Reach.builder_tail_ok?/2:p0`, `Reach.ctor_aligned?/2:p1`, `Reach.parametric_constructions/2:p0`, `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0`, `Reach.uses_parametric?/2:p0` |
| `Unk0909` | 4 | `Reach.all_emittable?/2:p1`, `Reach.parametric_ctx/2:ret`, `Reach.parametric_rs_ok?/2:p1`, `Reach.scan_func/3:p2` |
| `Unk0910` | 1 | `Reach.analyze/1:ret` |
| `Unk0911` | 15 | `Reach.atom_prim_blocker/0:ret`, `Reach.bare_atom_blocker/0:ret`, `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.ffi/2:ret`, `Reach.fn_type_blocker/0:ret`, `Reach.int_blocker/0:ret`, `Reach.parametric_blocker/0:ret`, `Reach.ref_blocker/0:ret`, `Reach.result_value_blocker/0:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret`, `Reach.wide_prim_blocker/0:ret`, `Reach.width_blocker/0:ret` |
| `Unk0912` | 5 | `Reach.build_default/0:ret`, `Reach.check_contracts/2:p1`, `Reach.gate!/2:p1`, `Reach.validate_default/1:p0`, `Reach.validate_default/1:ret` |
| `Unk0913` | 2 | `Reach.builder_tail_ok?/2:p1`, `Reach.tail_calls_generic?/2:p1` |
| `Unk0914` | 1 | `Reach.check_contracts/2:ret` |
| `Unk0915` | 3 | `Reach.classify/3:p1`, `Reach.scan/3:p1`, `Reach.scan_func/3:p1` |
| `Unk0916` | 5 | `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret` |
| `Unk0917` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0918` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk0919` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0920` | 3 | `Reach.collect_ctors/2:ret`, `Reach.ctor_aligned?/2:p0`, `Reach.parametric_constructions/2:ret` |
| `Unk0921` | 1 | `Reach.conc_erl?/2:p1` |
| `Unk0922` | 1 | `Reach.contract_message/1:p0` |
| `Unk0923` | 1 | `Reach.core/2:p0` |
| `Unk0924` | 1 | `Reach.core/2:p1` |
| `Unk0925` | 1 | `Reach.core/2:p1` |
| `Unk0926` | 2 | `Reach.deep/1:p0`, `Reach.find_atom_ordering/1:p0` |
| `Unk0927` | 3 | `Reach.deep/1:ret`, `Reach.find_atom_ordering/1:ret`, `Reach.func_symbol_violations/1:ret` |
| `Unk0928` | 1 | `Reach.emittable_parametric?/1:p0` |
| `Unk0929` | 1 | `Reach.emittable_parametric?/1:ret` |
| `Unk0930` | 1 | `Reach.fixpoint/2:p0` |
| `Unk0931` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0932` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk0933` | 1 | `Reach.func_symbol_violations/1:p0` |
| `Unk0934` | 2 | `Reach.gate!/1:ret`, `Reach.gate!/2:ret` |
| `Unk0935` | 1 | `Reach.js_wide_int?/1:p0` |
| `Unk0936` | 1 | `Reach.mix_default/0:ret` |
| `Unk0937` | 1 | `Reach.parametric_type?/1:p0` |
| `Unk0938` | 1 | `Reach.pascal?/1:p0` |
| `Unk0939` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0940` | 1 | `Reach.sig_idents/1:p0` |
| `Unk0941` | 1 | `Reach.sig_idents/1:ret` |
| `Unk0942` | 1 | `Reach.symbol_lint!/1:ret` |
| `Unk0943` | 1 | `Reach.tail_calls_generic?/2:p0` |
| `Unk0944` | 1 | `Reach.targets/0:ret` |
| `Unk0945` | 1 | `Reach.tvar?/1:p0` |
| `Unk0946` | 1 | `Reach.tvar?/1:ret` |
| `Unk0947` | 2 | `Reach.type_has_tvar?/1:p0`, `Reach.type_idents/1:p0` |
| `Unk0948` | 1 | `Reach.type_idents/1:ret` |
| `Unk0949` | 1 | `Reach.uses_parametric?/2:p1` |
| `Unk0950` | 1 | `Repl.accumulate_line/2:p1` |
| `Unk0951` | 1 | `Repl.bind_env/2:p0` |
| `Unk0952` | 4 | `Repl.bind_with_type/4:p3`, `Repl.safe_infer/3:ret`, `Repl.safe_infer_input/3:ret`, `Repl.type_of/2:ret` |
| `Unk0953` | 4 | `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:ret`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:ret` |
| `Unk0954` | 1 | `Repl.candidate_pool/2:p0` |
| `Unk0955` | 1 | `Repl.candidate_pool/2:ret` |
| `Unk0956` | 2 | `Repl.common_prefix/2:p0`, `Repl.common_prefix/3:p0` |
| `Unk0957` | 2 | `Repl.common_prefix/2:p1`, `Repl.common_prefix/3:p1` |
| `Unk0958` | 2 | `Repl.complete/2:p0`, `Repl.trailing_token/1:p0` |
| `Unk0959` | 1 | `Repl.complete/2:p1` |
| `Unk0960` | 2 | `Repl.complete/2:ret`, `Repl.continuation/2:p1` |
| `Unk0961` | 9 | `Repl.decl_names/1:ret`, `Repl.eval_decl/2:p0`, `Repl.eval_decl/2:ret`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0962` | 1 | `Repl.describe/1:p0` |
| `Unk0963` | 1 | `Repl.describe/1:ret` |
| `Unk0964` | 1 | `Repl.eval/2:p0` |
| `Unk0965` | 1 | `Repl.eval/2:ret` |
| `Unk0966` | 7 | `Repl.eval_decl/2:p0`, `Repl.program/3:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk0967` | 3 | `Repl.eval_decl/2:p0`, `Repl.reload/2:p0`, `Repl.run/4:p0` |
| `Unk0968` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0969` | 1 | `Repl.eval_decl/2:ret` |
| `Unk0970` | 1 | `Repl.flush_entries/1:p0` |
| `Unk0971` | 1 | `Repl.flush_entries/1:ret` |
| `Unk0972` | 1 | `Repl.info/1:ret` |
| `Unk0973` | 2 | `Repl.longest_common_prefix/1:p0`, `Repl.longest_common_prefix/1:ret` |
| `Unk0974` | 2 | `Repl.program/3:p1`, `Repl.run/4:p1` |
| `Unk0975` | 1 | `Repl.render/1:p0` |
| `Unk0976` | 1 | `Repl.run/4:ret` |
| `Unk0977` | 1 | `Repl.run/4:ret` |
| `Unk0978` | 1 | `Repl.safe_parse_body/1:ret` |
| `Unk0979` | 1 | `Repl.scan_count/2:p1` |
| `Unk0980` | 1 | `Repl.scan_count/2:ret` |
| `Unk0981` | 1 | `Repl.split_entries/1:p0` |
| `Unk0982` | 1 | `Repl.split_entries/1:ret` |
| `Unk0983` | 1 | `Repl.type_of/2:p0` |
| `Unk0984` | 1 | `Repl.vocabulary/0:ret` |
| `Unk0985` | 1 | `SelfHost.badge/1:p0` |
| `Unk0986` | 1 | `SelfHost.composition/0:ret` |
| `Unk0987` | 1 | `SelfHost.count/1:p0` |
| `Unk0988` | 1 | `SelfHost.evidence/1:p0` |
| `Unk0989` | 1 | `SelfHost.evidence_files/0:ret` |
| `Unk0990` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0991` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0992` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk0993` | 1 | `SelfHost.external_host_calls/1:ret` |
| `Unk0994` | 1 | `SelfHost.ffi_in_file/1:p0` |
| `Unk0995` | 1 | `SelfHost.ffi_in_file/1:ret` |
| `Unk0996` | 1 | `SelfHost.ffi_ledger/0:ret` |
| `Unk0997` | 1 | `SelfHost.passes/0:ret` |
| `Unk0998` | 1 | `SelfHost.percent/0:ret` |
| `Unk0999` | 1 | `SelfHost.selfhost_files/0:ret` |
| `Unk1000` | 1 | `SelfHost.selfhost_module_names/0:ret` |
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
| `Unk1017` | 1 | `Test.default_mod/1:ret` |
| `Unk1018` | 1 | `Test.run/2:p1` |
| `Unk1019` | 1 | `Test.run/2:ret` |
| `Unk1020` | 1 | `Test.run_one/2:p1` |
| `Unk1021` | 1 | `Test.rust/1:ret` |
| `Unk1022` | 1 | `Test.tests/1:ret` |
| `Unk1023` | 1 | `Tour.build_cell/1:p0` |
| `Unk1024` | 1 | `Tour.build_cell/1:ret` |
| `Unk1025` | 1 | `Tour.build_reach_example/1:p0` |
| `Unk1026` | 1 | `Tour.build_reach_example/1:ret` |
| `Unk1027` | 1 | `Tour.elixir_module/1:ret` |
| `Unk1028` | 2 | `Tour.encode/2:p0`, `Tour.encode_string/1:p0` |
| `Unk1029` | 1 | `Tour.generate/0:ret` |
| `Unk1030` | 1 | `Tour.reach_map/1:ret` |
| `Unk1031` | 1 | `Tour.to_json/0:ret` |
| `Unk1032` | 1 | `Transpile.add_clause/2:p0` |
| `Unk1033` | 5 | `Transpile.add_clause/2:p0`, `Transpile.add_clause/2:p1`, `Transpile.build_clause/2:ret`, `Transpile.new_group/3:p1`, `Transpile.same_group?/3:p2` |
| `Unk1034` | 2 | `Transpile.add_clause/2:ret`, `Transpile.new_group/3:ret` |
| `Unk1035` | 2 | `Transpile.block_stmts/1:p0`, `Transpile.block_stmts/1:ret` |
| `Unk1036` | 1 | `Transpile.build_clause/2:p0` |
| `Unk1037` | 1 | `Transpile.build_clause/2:p1` |
| `Unk1038` | 1 | `Transpile.case_arm/1:p0` |
| `Unk1039` | 1 | `Transpile.classify/1:ret` |
| `Unk1040` | 4 | `Transpile.close_group/2:p0`, `Transpile.close_group/2:p1`, `Transpile.close_group/2:ret`, `Transpile.def_groups/1:ret` |
| `Unk1041` | 1 | `Transpile.escape/1:p0` |
| `Unk1042` | 1 | `Transpile.escape/1:ret` |
| `Unk1043` | 2 | `Transpile.escape_lit/1:p0`, `Transpile.string_part/1:p0` |
| `Unk1044` | 1 | `Transpile.flush/2:p0` |
| `Unk1045` | 2 | `Transpile.flush/2:p1`, `Transpile.render_items/2:p1` |
| `Unk1046` | 2 | `Transpile.flush/2:p1`, `Transpile.render_items/2:p1` |
| `Unk1047` | 1 | `Transpile.hole_sig?/1:p0` |
| `Unk1048` | 2 | `Transpile.infer_program/1:p0`, `Transpile.infer_sigs/1:p0` |
| `Unk1049` | 3 | `Transpile.infer_program/1:ret`, `Transpile.infer_sigs/1:ret`, `Transpile.inferred/1:ret` |
| `Unk1050` | 1 | `Transpile.infer_report/1:p0` |
| `Unk1051` | 1 | `Transpile.infer_report/1:ret` |
| `Unk1052` | 1 | `Transpile.max_placeholder/1:p0` |
| `Unk1053` | 4 | `Transpile.mod_str/1:p0`, `Transpile.short_name/1:p0`, `Transpile.snippet/1:p0`, `Transpile.var_name/1:p0` |
| `Unk1054` | 1 | `Transpile.module_groups/1:p0` |
| `Unk1055` | 1 | `Transpile.module_groups/1:ret` |
| `Unk1056` | 1 | `Transpile.moduledoc_lines/1:p0` |
| `Unk1057` | 1 | `Transpile.name_str/1:p0` |
| `Unk1058` | 1 | `Transpile.name_str/1:ret` |
| `Unk1059` | 1 | `Transpile.new_group/3:p0` |
| `Unk1060` | 1 | `Transpile.new_group/3:p2` |
| `Unk1061` | 1 | `Transpile.one_line/1:p0` |
| `Unk1062` | 1 | `Transpile.one_line/1:ret` |
| `Unk1063` | 1 | `Transpile.prime_xmod/1:p0` |
| `Unk1064` | 1 | `Transpile.prime_xmod/1:ret` |
| `Unk1065` | 1 | `Transpile.rank/1:p0` |
| `Unk1066` | 1 | `Transpile.rank/1:ret` |
| `Unk1067` | 1 | `Transpile.render_clause/2:p1` |
| `Unk1068` | 1 | `Transpile.same_group?/3:p0` |
| `Unk1069` | 1 | `Transpile.same_group?/3:p1` |
| `Unk1070` | 1 | `Transpile.sibling_module?/2:p0` |
| `Unk1071` | 1 | `Transpile.simple?/1:p0` |
| `Unk1072` | 1 | `Transpile.string_part/1:ret` |
| `Unk1073` | 1 | `Transpile.string_parts/1:p0` |
| `Unk1074` | 1 | `Transpile.string_parts/1:ret` |
| `Unk1075` | 2 | `Transpile.subst_ph/2:p0`, `Transpile.subst_ph/2:ret` |
| `Unk1076` | 1 | `Transpile.subst_ph/2:p1` |
| `Unk1077` | 1 | `Transpile.toplevel/3:p0` |
| `Unk1078` | 1 | `Transpile.toplevel/3:p1` |
| `Unk1079` | 2 | `Transpile.transpile/2:p0`, `Transpile.transpile_with_stats/2:p0` |
| `Unk1080` | 1 | `Transpile.transpile/2:p1` |
| `Unk1081` | 2 | `Transpile.transpile/2:ret`, `Transpile.transpile_with_stats/2:ret` |
| `Unk1082` | 1 | `Transpile.transpile_with_stats/2:p1` |
| `Unk1083` | 1 | `Transpile.transpile_with_stats/2:ret` |
| `Unk1084` | 1 | `Transpile.underscore_var/1:p0` |
| `Unk1085` | 1 | `Transpile.var?/1:p0` |

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
| `"…"` (string) | 5 | **NEEDS DECISION** — name a variant | — |
| `Exception.message(e)` (expr) | 4 | **NEEDS DECISION** | — |
| `_` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `_reason` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `msg` (var/propagation) | 2 | propagated `E` (no fixed tag) | — |
| `"`#{f.name}`: returns error(s)` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{f}(…)`: labeled arguments ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{g}` requires `#{tvar}: #{p` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an `@external` par` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: an integer literal` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: binding declared `` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: body has type `#{b` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: literal #{v} is ou` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: range `#{ann}` is ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{name}`: value of type `#{t` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{n}`: literal #{v} is out o` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{op}`: no implicit Int↔Floa` (expr) | 1 | **NEEDS DECISION** | — |
| `"`#{x}` is not a compile-time ` (expr) | 1 | **NEEDS DECISION** | — |
| `"`<~` is in-place mutation of ` (expr) | 1 | **NEEDS DECISION** | — |
| `"operator `#{op}` not allowed ` (expr) | 1 | **NEEDS DECISION** | — |
| `"unsupported in comptime: #{in` (expr) | 1 | **NEEDS DECISION** | — |
| `String.t()` (expr) | 1 | **NEEDS DECISION** | — |
| `contract_message(vs)` (expr) | 1 | **NEEDS DECISION** | — |
| `parts |> List.last() |> to_str` (expr) | 1 | **NEEDS DECISION** | — |
| `{:__aliases__, _, parts}` (expr) | 1 | **NEEDS DECISION** | — |
| `{:already_started, pid}` (expr) | 1 | **NEEDS DECISION** | — |
| `bad` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `reason` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `tag` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |
| `x` (var/propagation) | 1 | propagated `E` (no fixed tag) | — |

