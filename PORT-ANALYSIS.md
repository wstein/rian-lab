# Port Analysis — Elixir → Rian

**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the
`REVIEW` sections and record decisions in a `port.spec` (feedback loop not yet
wired). Regenerate to diff against source — do not hand-edit this file.

## Summary

- modules: 41 · type slots: 2819 · auto-filled: 578 (21%) · holes: 2241
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
| `cp_expr/1` | `(String) String` | ✓ all 4 |
| `int_typeof/0` | `() String` | ✓ all 4 |
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
| `join_doc/2` | `(String, String) String` | ✓ all 4 |
| `owned_rtype?/1` | `(String) Bool` | ✓ all 4 |
| `owned_value_type?/1` | `(String) Bool` | ✓ all 4 |
| `prim_ex/1` | `(String) String` | ✓ all 4 |
| `rust_char_lit/1` | `(Int53) String` | ✓ all 4 |
| `str_lit_cp/1` | `(Int53) String` | ✓ all 4 |
| `tail_expr/1` | `(T) T forall T` | ✓ all 4 |
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
  pub def beam_for(module Unk0008, funcs Vec(Unk0009), ranges Vec(Type), types Vec(Type), structs Vec(Type)) Unk0010 := …

  # Beam.beam_func/1
  pub def beam_func(p0 Unk0011) Vec(Unk0011) := …

  # Beam.bin_seg/1
  pub def bin_seg(form Unk0012) Unk0013 := …

  # Beam.bind_var/2
  pub def bind_var(n String, s Map(String, Unk0014)) Unk0015 := …

  # Beam.block_forms/2
  pub def block_forms(p0 Sum1, _s Map(String, Unk0014)) Vec(Unk0012) := …

  # Beam.body_forms/3
  pub def body_forms(src Sum1, scope Map(String, Unk0014), rtable Map(Unk0017, Unk0016)) Vec(Unk0012) := …

  # Beam.body_seq/2
  pub def body_seq(p0 Sum1, s Map(String, Unk0014)) Vec(Unk0012) := …

  # Beam.bump_var/1
  pub def bump_var(cur Unk0014) Unk0018 := …

  # Beam.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Beam.cap_arity_list/1
  pub def cap_arity_list(es Vec(Sum1)) Int53 := …

  # Beam.clause_form/2
  pub def clause_form(p0 Unk0019, rtable Map(Unk0017, Unk0016)) Unk0020 := …

  # Beam.compile/2
  pub def compile(src String, module Unk0008) Unk0010 := …

  # Beam.compile_ir/2
  pub def compile_ir(prog Map(Unk0021, Vec(Type)), module Unk0008) Unk0010 := …

  # Beam.compile_program/1
  pub def compile_program(src String) Unk0022 := …

  # Beam.compile_program_ir/1
  pub def compile_program_ir(prog Map(Unk0021, Vec(Type))) Unk0023 := …

  # Beam.cons/3
  pub def cons(p0 Vec(Unk0024), tail Unk0012, _f Fn(Sum1, Unk0012)) Unk0012 := …

  # Beam.core_list_tail/1
  pub def core_list_tail(p0 Unk0012) Unk0012 := …

  # Beam.else_dispatch/3
  pub def else_dispatch(p0 Vec(Unk0025), catch_var String, _s Map(String, Unk0014)) Unk0012 := …

  # Beam.erl_op/1
  pub def erl_op(p0 String) Unk0026 := …

  # Beam.expr_form/2
  pub def expr_form(p0 Sum1, _s Map(String, Unk0014)) Unk0012 := …

  # Beam.fn_form/2
  pub def fn_form(t Unk0027, tctx Unk0028) Unk0029 := …

  # Beam.fun_ref/3
  pub def fun_ref(mod Unk0030, fun Unk0031, arity Unk0032) Unk0012 := …

  # Beam.funcs_of/1
  pub def funcs_of(p0 Map(Unk0033, Vec(Type))) Vec(Unk0009) := …

  # Beam.function_form/2
  pub def function_form(p0 Unk0034, rtable Map(Unk0017, Unk0016)) Unk0035 := …

  # Beam.guard_core/1
  pub def guard_core(p0 Sum1) Sum1 := …

  # Beam.guard_form/2
  pub def guard_form(p0 Sum1, _scope Map(String, Unk0014)) Vec(Vec(Unk0012)) := …

  # Beam.i64_overflow/4
  pub def i64_overflow(kind Unk0036, a Sum1, b Sum1, s Map(String, Unk0014)) Unk0012 := …

  # Beam.i64_project/2
  pub def i64_project(p0 Unk0037, sv Unk0038) Unk0039 := …

  # Beam.inner_of/1
  pub def inner_of(p0 Unk0040) Unk0041 := …

  # Beam.int_t/0
  pub def int_t() Unk0042 := …

  # Beam.load/2
  pub def load(src String, module Unk0008) Unk0043 := …

  # Beam.load_aux_mods/1
  pub def load_aux_mods(p0 Map(Unk0033, Vec(Type))) Unk0044 := …

  # Beam.load_ir/2
  pub def load_ir(prog Map(Unk0021, Vec(Type)), module Unk0008) Unk0045 := …

  # Beam.load_program/1
  pub def load_program(src Unk0046) Unk0047 := …

  # Beam.load_program_ir/1
  pub def load_program_ir(prog Unk0048) Unk0049 := …

  # Beam.map_field_pat/1
  pub def map_field_pat(p0 Unk0050) Unk0051 := …

  # Beam.num_form/1
  pub def num_form(n Unk0052) Unk0012 := …

  # Beam.pascal?/1
  pub def pascal?(s Unk0053) Bool := …

  # Beam.pat_form/1
  pub def pat_form(p0 Sum2) Unk0012 := …

  # Beam.pat_vars/2
  pub def pat_vars(p0 Sum2, acc Map(String, Unk0014)) Map(String, Unk0014) := …

  # Beam.ranges_of/1
  pub def ranges_of(prog Map(Unk0033, Vec(Type))) Vec(Type) := …

  # Beam.remote_call/4
  pub def remote_call(mod Unk0054, fun String, args Vec(Sum1), scope Map(String, Unk0014)) Unk0012 := …

  # Beam.spec_form/2
  pub def spec_form(p0 Unk0034, tctx Unk0028) Unk0035 := …

  # Beam.split_top/2
  pub def split_top(s Unk0055, sep String) Unk0056 := …

  # Beam.stmt_form/2
  pub def stmt_form(p0 Unk0057, s Map(String, Unk0014)) Unk0058 := …

  # Beam.str_form/1
  pub def str_form(s Unk0059) Unk0012 := …

  # Beam.struct_form/2
  pub def struct_form(p0 Type, tctx Unk0028) Unk0060 := …

  # Beam.structs_of/1
  pub def structs_of(p0 Map(Unk0033, Vec(Type))) Vec(Type) := …

  # Beam.sum_form/2
  pub def sum_form(variants Unk0061, tctx Unk0028) Unk0062 := …

  # Beam.tag/1
  pub def tag(ctor Unk0063) Unk0063 := …

  # Beam.top_level_union?/1
  pub def top_level_union?(t Unk0055) Bool := …

  # Beam.type_attrs/3
  pub def type_attrs(types Vec(Type), structs Vec(Type), tctx Unk0028) Vec(Unk0035) := …

  # Beam.type_ctx/3
  pub def type_ctx(types Vec(Type), ranges Vec(Type), structs Vec(Type)) Unk0028 := …

  # Beam.type_form/2
  pub def type_form(p0 Unk0064, _tctx Unk0028) Unk0005 := …

  # Beam.types_of/1
  pub def types_of(p0 Map(Unk0033, Vec(Type))) Vec(Type) := …

  # Beam.union_t/1
  pub def union_t(p0 Vec(Unk0060)) Unk0060 := …

  # Beam.var_atom/1
  pub def var_atom(p0 String) Unk0014 := …

  # Beam.var_form/1
  pub def var_form(x String) Unk0012 := …

  # Beam.with_form/5
  pub def with_form(p0 Vec(Unk0065), body Sum1, _els Vec(Unk0025), s Map(String, Unk0014), _d Int53) Unk0012 := …

  # Capability.beam_legal!/1
  pub def beam_legal!(p0 Unk0066) Unk0067 := …

  # Capability.count_block/3
  pub def count_block(p0 Vec(Unk0068), _bound Unk0069, acc Unk0070) Unk0070 := …

  # Capability.count_uses/1
  pub def count_uses(ast Unk0071) Unk0070 := …

  # Capability.count_uses/2
  pub def count_uses(p0 Unk0071, bound Unk0069) Unk0070 := …

  # Capability.lin_check/2
  pub def lin_check(env Map(Unk0072, Unk0073), ast Unk0071) Unk0074 := …

  # Capability.lin_check_block/3
  pub def lin_check_block(env Unk0075, bindings Vec(Unk0076), final Unk0071) Unk0074 := …

  # Capability.max_merge/2
  pub def max_merge(a Unk0070, b Unk0070) Unk0070 := …

  # Capability.merge/2
  pub def merge(a Unk0070, b Unk0070) Unk0070 := …

  # Capability.parametric/1
  pub def parametric(t String) Option(Unk0077) := …

  # Capability.pat_vars/1
  pub def pat_vars(p0 Unk0078) Unk0079 := …

  # Capability.rust_param/2
  pub def rust_param(p0 Unk0080, t String) String := …

  # Capability.split_top_level/1
  pub def split_top_level(s String) Vec(Unk0081) := …

  # Capability.verdict/2
  pub def verdict(env Map(Unk0072, Unk0073), uses Unk0070) Unk0074 := …

  # Check.abstract_cast_ret/3
  pub def abstract_cast_ret(ht String, cn Unk0082, ic Map(Unk0083, Map(String, String))) Option(Unk0084) := …

  # Check.abstract_op_type/4
  pub def abstract_op_type(op Unk0085, lt String, rt String, ic Unk0086) Unk0087 := …

  # Check.adoptable_int?/1
  pub def adoptable_int?(t Unk0088) Bool := …

  # Check.all_types/1
  pub def all_types(prog Map(Unk0089, Vec(Type))) Vec(Type) := …

  # Check.ann_each/3
  pub def ann_each(nodes Vec(Sum1), env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Vec(Sum1) := …

  # Check.ann_stmts/3
  pub def ann_stmts(p0 Vec(Unk0091), _env Map(Unk0090, String), _ic Map(Unk0083, Map(String, String))) Vec(Unk0092) := …

  # Check.annotate/3
  pub def annotate(ast Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Sum1 := …

  # Check.arith_type/4
  pub def arith_type(l Unk0093, r Unk0094, lt Unk0095, rt Unk0096) Unk0097 := …

  # Check.bind_mismatch/5
  pub def bind_mismatch(name Unk0098, ann Unk0099, e Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk0100) := …

  # Check.bind_tvar/4
  pub def bind_tvar(_p Unk0101, p1 Unk0102, _tvars Unk0103, acc Map(Unk0104, String)) Map(Unk0104, String) := …

  # Check.body_literal_adopts?/2
  pub def body_literal_adopts?(p0 Unk0105, ret Unk0088) Bool := …

  # Check.branch_join/1
  pub def branch_join(typed Vec(Unk0106)) String := …

  # Check.build_fn/2
  pub def build_fn(args Vec(Unk0107), ret String) String := …

  # Check.call_bound_error/5
  pub def call_bound_error(g String, args Vec(Sum1), env Map(Unk0090, String), ic Map(Unk0083, Map(String, String)), fbounds Map(String, String)) Option(Unk0108) := …

  # Check.call_name/1
  pub def call_name(p0 Unk0109) Vec(Unk0110) := …

  # Check.called_ret/2
  pub def called_ret(ic Map(Unk0083, Map(String, String)), f String) String := …

  # Check.called_ret_with/4
  pub def called_ret_with(ic Map(Unk0083, Map(String, String)), f String, args_ast Vec(Sum1), env Map(Unk0090, String)) String := …

  # Check.check/1
  pub def check(src Unk0111) Unk0112 := …

  # Check.check_bind_stmts/3
  pub def check_bind_stmts(p0 Vec(Unk0113), _env Map(Unk0090, String), _ic Map(Unk0083, Map(String, String))) Option(Unk0100) := …

  # Check.check_binds/2
  pub def check_binds(p0 Func, ic Map(Unk0083, Map(String, String))) Unk0114 := …

  # Check.check_bounds/2
  pub def check_bounds(p0 Func, ic Map(Unk0083, Map(String, String))) Unk0115 := …

  # Check.check_error_set/2
  pub def check_error_set(p0 Unk0116, p1 Unk0117) Unk0118 := …

  # Check.check_external_caps/1
  pub def check_external_caps(p0 Func) Unk0119 := …

  # Check.check_func/3
  pub def check_func(p0 Unk0120, ic Map(Unk0083, Map(String, String)), eset Unk0121) Unk0122 := …

  # Check.check_labels/1
  pub def check_labels(p0 Func) Unk0123 := …

  # Check.check_numeric_mix/2
  pub def check_numeric_mix(p0 Func, ic Map(Unk0083, Map(String, String))) Unk0124 := …

  # Check.check_program/1
  pub def check_program(p0 Map(Unk0021, Vec(Type))) Unk0125 := …

  # Check.check_return/2
  pub def check_return(p0 Func, ic Map(Unk0083, Map(String, String))) Unk0126 := …

  # Check.clause_env/3
  pub def clause_env(pats Unk0127, params Unk0128, ic Map(Unk0083, Map(String, String))) Map(Unk0090, String) := …

  # Check.comp_str/1
  pub def comp_str(p0 Unk0129) String := …

  # Check.comp_unify/2
  pub def comp_unify(x Unk0130, x Unk0131) Unk0131 := …

  # Check.conservative/1
  pub def conservative(p0 Unk0132) Unk0132 := …

  # Check.const_int/1
  pub def const_int(p0 Unk0133) Unk0134 := …

  # Check.ctor_type/2
  pub def ctor_type(ic Map(Unk0083, Map(String, String)), name String) String := …

  # Check.ctor_types/2
  pub def ctor_types(types Unk0135, prog Map(Unk0136, Vec(Unk0137))) Map(Unk0139, Unk0138) := …

  # Check.debottom/1
  pub def debottom(p0 Unk0140) Unk0140 := …

  # Check.declared_set/2
  pub def declared_set(ret Unk0141, tsets Unk0142) Option(Unk0143) := …

  # Check.direct_tags/1
  pub def direct_tags(f Unk0144) Unk0145 := …

  # Check.error_sets/1
  pub def error_sets(types Vec(Type)) Unk0146 := …

  # Check.error_tags/1
  pub def error_tags(p0 Vec(Unk0147)) Vec(Option(Unk0148)) := …

  # Check.fbound_table/1
  pub def fbound_table(funcs Unk0149) Unk0150 := …

  # Check.first_bound_violation/4
  pub def first_bound_violation(g String, bounds Unk0151, subs Map(Unk0104, String), ic Map(Unk0083, Map(String, String))) Option(Unk0108) := …

  # Check.fixpoint/2
  pub def fixpoint(facts Unk0152, table Unk0153) Unk0153 := …

  # Check.float_type?/1
  pub def float_type?(t Unk0088) Bool := …

  # Check.fn_parts/1
  pub def fn_parts(p0 Unk0154) Unk0155 := …

  # Check.fn_ret/1
  pub def fn_ret(ft String) Option(Unk0084) := …

  # Check.fsig/1
  pub def fsig(f Unk0156) Unk0157 := …

  # Check.gate!/1
  pub def gate!(prog Map(Unk0021, Vec(Type))) Unk0158 := …

  # Check.generic_ret?/2
  pub def generic_ret?(_ret Unk0159, p1 Vec(Unk0160)) Bool := …

  # Check.impl_table/1
  pub def impl_table(prog Map(Unk0162, Vec(Unk0161))) Unk0163 := …

  # Check.infer/3
  pub def infer(ast Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) String := …

  # Check.infer_block/4
  pub def infer_block(p0 Vec(Unk0164), _env Map(Unk0090, String), _ic Map(Unk0083, Map(String, String)), value String) String := …

  # Check.infer_tail/3
  pub def infer_tail(p0 Sum1, _env Map(Unk0090, String), _ic Map(Unk0083, Map(String, String))) String := …

  # Check.inner_of/1
  pub def inner_of(p0 Unk0165) Unk0166 := …

  # Check.instantiate_ret/2
  pub def instantiate_ret(p0 Unk0167, arg_types Vec(String)) String := …

  # Check.int_lit_expr?/1
  pub def int_lit_expr?(p0 Sum1) Bool := …

  # Check.int_literal?/1
  pub def int_literal?(n Unk0168) Bool := …

  # Check.int_type?/1
  pub def int_type?(t Unk0088) Bool := …

  # Check.join_all/1
  pub def join_all(types Unk0169) Unk0170 := …

  # Check.kind_prefix/1
  pub def kind_prefix(p0 Unk0171) String := …

  # Check.label_error/1
  pub def label_error(p0 Sum1) Option(Unk0172) := …

  # Check.label_error_children/1
  pub def label_error_children(node Sum1) Option(Unk0172) := …

  # Check.list_elem/1
  pub def list_elem(p0 Unk0173) Unk0174 := …

  # Check.list_elems/1
  pub def list_elems(p0 Unk0133) Vec(Unk0175) := …

  # Check.list_of/1
  pub def list_of(p0 Unk0132) String := …

  # Check.lit_expr_adopts?/2
  pub def lit_expr_adopts?(p0 Sum1, ret Unk0088) Bool := …

  # Check.lit_range_error/3
  pub def lit_range_error(expr Unk0133, p1 String, name Unk0176) Option(Unk0177) := …

  # Check.literal_adopts?/2
  pub def literal_adopts?(p0 Sum1, ann Unk0088) Bool := …

  # Check.literal_ordinal/2
  pub def literal_ordinal(p0 Sum1, p1 String) Unk0178 := …

  # Check.missing_impl/5
  pub def missing_impl(g String, tvar Unk0179, ty String, protos Unk0180, impls Map(String, String)) Option(Unk0181) := …

  # Check.narrow/4
  pub def narrow(p0 Sum2, type String, _ic Map(Unk0083, Map(String, String)), env Map(Unk0090, String)) Map(Unk0090, String) := …

  # Check.num_bits/2
  pub def num_bits(kind Unk0182, w Unk0183) Option(Unk0184) := …

  # Check.num_join/2
  pub def num_join(p0 Unk0185, p1 Unk0186) String := …

  # Check.num_kind/1
  pub def num_kind(p0 String) Option(Unk0184) := …

  # Check.num_lub/2
  pub def num_lub(x String, y String) Unk0187 := …

  # Check.num_mix?/2
  pub def num_mix?(p0 Unk0188, k Unk0189) Bool := …

  # Check.num_mix_error/5
  pub def num_mix_error(op Unk0190, l Sum1, r Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Unk0191 := …

  # Check.num_widens?/2
  pub def num_widens?(p0 Unk0192, p1 Unk0193) Bool := …

  # Check.oor_scan/5
  pub def oor_scan(p0 Unk0133, ty String, lo Unk0194, hi Unk0195, n Unk0176) Option(Unk0177) := …

  # Check.opaque_table/1
  pub def opaque_table(prog Map(Unk0196, Vec(Unk0197))) Unk0198 := …

  # Check.parse_parametric/1
  pub def parse_parametric(s String) Unk0199 := …

  # Check.pascal?/1
  pub def pascal?(s Unk0200) Bool := …

  # Check.produced_set/2
  pub def produced_set(f Unk0144, table Map(Unk0202, Unk0201)) Unk0203 := …

  # Check.program_ic/1
  pub def program_ic(p0 Map(Unk0021, Vec(Type))) Map(Unk0083, Map(String, String)) := …

  # Check.propagated_callees/1
  pub def propagated_callees(f Unk0204) Unk0205 := …

  # Check.range_base/2
  pub def range_base(ic Map(Unk0206, Map(Unk0208, Unk0207)), n Unk0208) Option(Unk0209) := …

  # Check.range_bind/6
  pub def range_bind(name Unk0210, ann Unk0211, p2 Unk0212, ce Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk0213) := …

  # Check.range_table/1
  pub def range_table(prog Map(Unk0214, Vec(Unk0215))) Unk0216 := …

  # Check.resolve_range/2
  pub def resolve_range(t String, ic Map(Unk0083, Map(String, String))) String := …

  # Check.scan_bound_calls/4
  pub def scan_bound_calls(p0 Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String)), fbounds Map(String, String)) Option(Unk0217) := …

  # Check.scan_num_mix/3
  pub def scan_num_mix(p0 Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk0218) := …

  # Check.scan_num_mix_children/3
  pub def scan_num_mix_children(node Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk0218) := …

  # Check.solve_error_sets/2
  pub def solve_error_sets(funcs Unk0219, tsets Unk0142) Unk0153 := …

  # Check.split_top_commas/1
  pub def split_top_commas(s String) Vec(Unk0081) := …

  # Check.tag_name/1
  pub def tag_name(p0 Unk0220) Option(Unk0148) := …

  # Check.type_table/1
  pub def type_table(types Unk0221) Unk0222 := …

  # Check.uint_signed_join/2
  pub def uint_signed_join(u Unk0223, i Unk0223) String := …

  # Check.unify_fn/2
  pub def unify_fn(a Unk0154, b Unk0154) String := …

  # Check.walk_children/4
  pub def walk_children(node Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String)), fbounds Map(String, String)) Option(Unk0217) := …

  # Check.width_bounds/1
  pub def width_bounds(p0 String) Option(Unk0224) := …

  # Check.with_callees/1
  pub def with_callees(p0 Vec(Unk0225)) Vec(Unk0110) := …

  # Comptime.eval/1
  pub def eval(p0 Unk0226) Unk0227 := …

  # Comptime.fold/1
  pub def fold(p0 Sum1) Vec(Unk0228) := …

  # Comptime.int_div/3
  pub def int_div(_a Unk0229, p1 Int53, _op Unk0230) Unk0231 := …

  # Comptime.truthy!/1
  pub def truthy!(b Unk0232) Unk0232 := …

  # Core.from_arm/1
  pub def from_arm(p0 Unk0233) Unk0234 := …

  # Core.from_expr/1
  pub def from_expr(p0 Sum1) Sum1 := …

  # Core.from_pairs/1
  pub def from_pairs(pairs Vec(Unk0235)) Vec(Unk0236) := …

  # Core.from_pat/1
  pub def from_pat(p0 Sum2) Sum2 := …

  # Core.from_stmt/1
  pub def from_stmt(p0 Unk0237) Unk0238 := …

  # Core.from_tail/1
  pub def from_tail(p0 Unk0239) Sum1 := …

  # Cst.build/1
  pub def build(tokens Vec(Unk0240)) Unk0241 := …

  # Cst.open/4
  pub def open(open_tok Unk0242, close Unk0243, rest Vec(Unk0240), acc Vec(Unk0244)) Unk0245 := …

  # Cst.seq/2
  pub def seq(p0 Vec(Unk0240), acc Vec(Unk0244)) Unk0245 := …

  # Decl.all_impl_decls/1
  pub def all_impl_decls(decls Vec(Unk0246)) Vec(Unk0247) := …

  # Decl.all_impls/1
  pub def all_impls(decls Vec(Unk0246)) Vec(Unk0248) := …

  # Decl.all_protocols/1
  pub def all_protocols(decls Vec(Unk0246)) Vec(Unk0247) := …

  # Decl.assemble/3
  pub def assemble(decls Vec(Unk0249), aliases Unk0250, p2 Unk0251) Unk0252 := …

  # Decl.attach_doc/2
  pub def attach_doc(p0 Unk0253, doc Unk0254) Unk0253 := …

  # Decl.attach_external/3
  pub def attach_external(p0 Unk0255, target Unk0256, spec Unk0257) Unk0258 := …

  # Decl.attach_targets/2
  pub def attach_targets(p0 Unk0259, targets Unk0260) Unk0261 := …

  # Decl.balanced_parens/1
  pub def balanced_parens(p0 Vec(Unk0262)) Unk0263 := …

  # Decl.block_seps/5
  pub def block_seps(p0 Vec(Unk0264), _d Int53, _w Int53, _p Int53, acc Vec(Unk0264)) Vec(Unk0264) := …

  # Decl.build_func/1
  pub def build_func(p0 Vec(Unk0265)) Func := …

  # Decl.clause/2
  pub def clause(p0 Unk0266, _arity Unk0267) Clause := …

  # Decl.clause_env/2
  pub def clause_env(p0 Clause, params Unk0268) Map(Unk0090, String) := …

  # Decl.collapse_parens/1
  pub def collapse_parens(s Unk0269) Unk0270 := …

  # Decl.collect_aliases/1
  pub def collect_aliases(decls Vec(Unk0246)) Unk0271 := …

  # Decl.collect_macros/1
  pub def collect_macros(decls Vec(Unk0246)) Unk0272 := …

  # Decl.compile/1
  pub def compile(src String) Vec(Unk0273) := …

  # Decl.compile_beam/1
  pub def compile_beam(src String) Vec(Unk0274) := …

  # Decl.decl_boundary?/1
  pub def decl_boundary?(p0 Vec(Vec(Unk0262))) Bool := …

  # Decl.decl_kw?/1
  pub def decl_kw?(p0 Vec(Vec(Unk0262))) Bool := …

  # Decl.def_raw/4
  pub def def_raw(name Unk0275, params Unk0276, head_rev Vec(Unk0277), body Unk0278) Unk0279 := …

  # Decl.detok_block/1
  pub def detok_block(tokens Unk0280) Unk0281 := …

  # Decl.extract_parens/1
  pub def extract_parens(str Unk0282) Unk0283 := …

  # Decl.field/1
  pub def field(f Unk0284) Field := …

  # Decl.fields/1
  pub def fields(inside Unk0285) Vec(Unk0286) := …

  # Decl.impl_struct/3
  pub def impl_struct(proto Unk0287, type Unk0288, inner Unk0289) Unk0290 := …

  # Decl.in_scope/2
  pub def in_scope(decls Vec(Unk0246), f Fn(Unk0291, Unk0292)) Vec(Unk0247) := …

  # Decl.inject_stdlib/1
  pub def inject_stdlib(prog Unk0293) Unk0293 := …

  # Decl.line_continues?/2
  pub def line_continues?(p0 Vec(Vec(Unk0262)), _rest Vec(Vec(Unk0262))) Bool := …

  # Decl.lower_meta/3
  pub def lower_meta(funcs Vec(Unk0294), decls Vec(Unk0246), targets Option(Unk0295)) Vec(Unk0296) := …

  # Decl.macro_param_names/1
  pub def macro_param_names(pstr Unk0297) Unk0298 := …

  # Decl.mark_pub/1
  pub def mark_pub(p0 Unk0299) Unk0300 := …

  # Decl.mark_test/1
  pub def mark_test(p0 Unk0301) Unk0302 := …

  # Decl.match_paren/3
  pub def match_paren(p0 String, depth Int53, acc String) Unk0303 := …

  # Decl.meta_clause/5
  pub def meta_clause(p0 Unk0304, _env Map(Unk0306, Unk0305), _p Unk0307, _params Unk0268, _show Unk0308) Unk0309 := …

  # Decl.nz/1
  pub def nz(s Unk0310) Option(Unk0311) := …

  # Decl.param/1
  pub def param(p Unk0312) Unk0313 := …

  # Decl.parse/1
  pub def parse(src String) Map(Unk0021, Vec(Type)) := …

  # Decl.parse_abstract/4
  pub def parse_abstract(head Unk0314, body_toks Unk0315, pub? Unk0316, doc Unk0317) Opaque := …

  # Decl.parse_abstract_members/1
  pub def parse_abstract_members(toks Unk0315) Unk0318 := …

  # Decl.parse_alias/1
  pub def parse_alias(text Unk0314) Unk0319 := …

  # Decl.parse_assoc_binding/1
  pub def parse_assoc_binding(t Unk0320) Unk0321 := …

  # Decl.parse_binder/1
  pub def parse_binder(b Unk0322) Unk0323 := …

  # Decl.parse_binders/1
  pub def parse_binders(binders Unk0324) Vec(Unk0325) := …

  # Decl.parse_bounds/1
  pub def parse_bounds(text Unk0326) Unk0327 := …

  # Decl.parse_cast_rule/1
  pub def parse_cast_rule(p0 Unk0328) Unk0329 := …

  # Decl.parse_const/3
  pub def parse_const(text Unk0314, pub? Unk0330, doc Unk0331) Const := …

  # Decl.parse_external/1
  pub def parse_external(p0 Vec(Unk0332)) Unk0333 := …

  # Decl.parse_head/1
  pub def parse_head(head Unk0334) Unk0335 := …

  # Decl.parse_op_rule/1
  pub def parse_op_rule(p0 Unk0336) Unk0337 := …

  # Decl.parse_opaque/3
  pub def parse_opaque(text Unk0314, pub? Unk0338, doc Unk0339) Opaque := …

  # Decl.parse_ordinal/1
  pub def parse_ordinal(p0 Unk0340) Unk0341 := …

  # Decl.parse_params/1
  pub def parse_params(str Unk0342) Unk0343 := …

  # Decl.parse_range/3
  pub def parse_range(text Unk0314, pub? Unk0344, doc Unk0345) Range := …

  # Decl.parse_struct/3
  pub def parse_struct(text Unk0282, pub? Unk0346, doc Unk0347) Struct := …

  # Decl.parse_targets/1
  pub def parse_targets(toks Unk0348) Unk0349 := …

  # Decl.parse_type/3
  pub def parse_type(rest Unk0314, pub? Unk0350, doc Unk0351) Type := …

  # Decl.parse_use/1
  pub def parse_use(text Unk0352) Use := …

  # Decl.proto_method_traits/1
  pub def proto_method_traits(prog Map(Unk0021, Vec(Type))) Unk0353 := …

  # Decl.protocol_defs/4
  pub def protocol_defs(decls Vec(Unk0249), types Unk0354, structs Unk0355, targets Unk0356) Vec(Unk0357) := …

  # Decl.protocol_struct/2
  pub def protocol_struct(name Unk0358, inner Unk0359) Unk0360 := …

  # Decl.protocol_unit/3
  pub def protocol_unit(prog Map(Unk0021, Vec(Type)), types Vec(Type), structs Vec(Type)) Vec(Unk0273) := …

  # Decl.req_ret/1
  pub def req_ret(p0 Unk0361) Unk0362 := …

  # Decl.show_module/0
  pub def show_module() Unk0363 := …

  # Decl.skip_nl/1
  pub def skip_nl(p0 Vec(Unk0262)) Vec(Unk0262) := …

  # Decl.split2/2
  pub def split2(str Unk0364, sep Unk0365) Unk0366 := …

  # Decl.split_decls/1
  pub def split_decls(p0 Vec(Vec(Unk0262))) Vec(Unk0367) := …

  # Decl.split_forall/1
  pub def split_forall(head Unk0368) Unk0369 := …

  # Decl.split_once/2
  pub def split_once(str Unk0314, sep String) Unk0370 := …

  # Decl.split_top/2
  pub def split_top(str Unk0371, sep Unk0372) Unk0373 := …

  # Decl.strip_type_params/1
  pub def strip_type_params(name Unk0374) Unk0375 := …

  # Decl.subst_const/2
  pub def subst_const(p0 Unk0376, aliases Unk0250) Const := …

  # Decl.subst_fields/2
  pub def subst_fields(fs Vec(Unk0377), aliases Unk0378) Vec(Field) := …

  # Decl.subst_func/2
  pub def subst_func(p0 Unk0379, aliases Unk0250) Func := …

  # Decl.subst_struct/2
  pub def subst_struct(p0 Unk0380, aliases Unk0250) Struct := …

  # Decl.subst_type/2
  pub def subst_type(p0 Unk0381, aliases Unk0250) Type := …

  # Decl.subst_type_str/2
  pub def subst_type_str(type Unk0382, aliases Vec(Unk0383)) Unk0382 := …

  # Decl.subst_variant/2
  pub def subst_variant(p0 Unk0384, aliases Unk0385) Variant := …

  # Decl.take_block/3
  pub def take_block(p0 Vec(Vec(Unk0262)), depth Int53, acc Vec(Vec(Unk0262))) Unk0386 := …

  # Decl.take_decl/1
  pub def take_decl(p0 Vec(Vec(Unk0262))) Unk0387 := …

  # Decl.take_def/1
  pub def take_def(p0 Vec(Vec(Unk0262))) Unk0388 := …

  # Decl.take_head/4
  pub def take_head(name Unk0389, params Unk0390, p2 Vec(Vec(Unk0262)), head Vec(Vec(Unk0262))) Unk0388 := …

  # Decl.take_line/2
  pub def take_line(tokens Vec(Vec(Unk0262)), acc Vec(Vec(Unk0262))) Unk0391 := …

  # Decl.take_line/3
  pub def take_line(p0 Vec(Vec(Unk0262)), acc Vec(Vec(Unk0262)), _depth Int53) Unk0391 := …

  # Decl.take_mod_body/2
  pub def take_mod_body(p0 Vec(Unk0262), acc Vec(Unk0392)) Unk0393 := …

  # Decl.take_parens/3
  pub def take_parens(p0 Vec(Unk0262), p1 Int53, acc Vec(Unk0262)) Unk0263 := …

  # Decl.take_type/2
  pub def take_type(p0 Vec(Vec(Unk0262)), acc Vec(Vec(Unk0262))) Unk0394 := …

  # Decl.take_until_do/2
  pub def take_until_do(p0 Vec(Vec(Unk0262)), acc Vec(Vec(Unk0262))) Unk0395 := …

  # Decl.variant/1
  pub def variant(v Unk0282) Variant := …

  # Doc.concat/1
  pub def concat(docs Vec(Unk0396)) Unk0396 := …

  # Doc.concat/2
  pub def concat(a Unk0396, b Unk0396) Unk0396 := …

  # Doc.do_render/5
  pub def do_render(_w Int53, _k Int53, p2 Vec(Unk0397), p3 Vec(Unk0398), out Vec(String)) Vec(String) := …

  # Doc.empty/0
  pub def empty() Unk0396 := …

  # Doc.fits?/2
  pub def fits?(w Int53, _work Vec(Unk0397)) Bool := …

  # Doc.flat_string/1
  pub def flat_string(p0 Unk0398) String := …

  # Doc.flush_suffix/2
  pub def flush_suffix(p0 Vec(Unk0398), out Vec(String)) Vec(String) := …

  # Doc.group/1
  pub def group(doc Unk0399) Unk0400 := …

  # Doc.hardline/0
  pub def hardline() Unk0401 := …

  # Doc.if_break/2
  pub def if_break(broken Unk0402, flat Unk0403) Unk0404 := …

  # Doc.join/2
  pub def join(_sep Unk0405, p1 Vec(Unk0406)) Unk0396 := …

  # Doc.line/0
  pub def line() Unk0407 := …

  # Doc.line_suffix/1
  pub def line_suffix(doc Unk0396) Unk0396 := …

  # Doc.must_break?/1
  pub def must_break?(p0 Unk0399) Bool := …

  # Doc.nest/2
  pub def nest(n Vec(Unk0408), doc Unk0396) Unk0396 := …

  # Doc.render/2
  pub def render(doc Unk0396, width Int53) String := …

  # Doc.softline/0
  pub def softline() Unk0409 := …

  # Doc.text/1
  pub def text(s String) Unk0396 := …

  # Doctest.augment/2
  pub def augment(src String, examples Vec(Unk0410)) String := …

  # Doctest.extract/1
  pub def extract(src String) Vec(Unk0410) := …

  # Doctest.exunit_cases/2
  pub def exunit_cases(src String, mod Unk0411) Unk0412 := …

  # Doctest.fences/1
  pub def fences(md Unk0413) Unk0414 := …

  # Doctest.module_doc_strings/1
  pub def module_doc_strings(p0 Map(Unk0021, Vec(Type))) Vec(Unk0415) := …

  # Doctest.pairs/1
  pub def pairs(p0 Unk0416) Vec(Unk0417) := …

  # Doctest.run/2
  pub def run(src String, p1 Unk0418) Vec(Unk0419) := …

  # Doctest.run_markdown/1
  pub def run_markdown(md Unk0420) Unk0421 := …

  # Exhaustiveness.add_range/4
  pub def add_range(env Unk0422, type_name Unk0423, lo Unk0424, hi Unk0425) Unk0422 := …

  # Exhaustiveness.add_type/3
  pub def add_type(env Unk0422, type_name Unk0063, variants Vec(Unk0426)) Unk0422 := …

  # Exhaustiveness.analyze/3
  pub def analyze(arms Vec(Unk0427), n Int53, env Map(Unk0428, Unk0429)) Unk0430 := …

  # Exhaustiveness.arity/2
  pub def arity(_env Map(Unk0428, Unk0429), p1 Unk0431) Int53 := …

  # Exhaustiveness.base_env/0
  pub def base_env() Unk0422 := …

  # Exhaustiveness.body_core/1
  pub def body_core(body Sum1) Sum1 := …

  # Exhaustiveness.check_case_bodies!/2
  pub def check_case_bodies!(funcs Unk0432, env Unk0433) Unk0434 := …

  # Exhaustiveness.check_match!/3
  pub def check_match!(core Unk0435, env Map(Unk0428, Unk0429), where Unk0436) Unk0437 := …

  # Exhaustiveness.check_one_case!/3
  pub def check_one_case!(p0 Sum1, env Map(Unk0428, Unk0429), where Unk0436) Unk0438 := …

  # Exhaustiveness.collect_cases/2
  pub def collect_cases(p0 Vec(Unk0439), acc Vec(Unk0440)) Vec(Unk0440) := …

  # Exhaustiveness.collect_children/2
  pub def collect_children(struct Vec(Unk0439), acc Vec(Unk0440)) Vec(Unk0440) := …

  # Exhaustiveness.default/1
  pub def default(rows Vec(Unk0441)) Vec(Unk0441) := …

  # Exhaustiveness.head_ctors/1
  pub def head_ctors(rows Vec(Unk0441)) Vec(Unk0442) := …

  # Exhaustiveness.missing_head/2
  pub def missing_head(_env Map(Unk0428, Unk0429), p1 Vec(Unk0443)) Unk0444 := …

  # Exhaustiveness.pascal/1
  pub def pascal(c Unk0445) String := …

  # Exhaustiveness.program_env/3
  pub def program_env(types Vec(Type), structs Vec(Unk0446), ranges Vec(Unk0447)) Unk0422 := …

  # Exhaustiveness.render/1
  pub def render(p0 Vec(Unk0448)) String := …

  # Exhaustiveness.signature/2
  pub def signature(_env Map(Unk0428, Unk0429), p1 Vec(Unk0442)) Unk0449 := …

  # Exhaustiveness.specialize/3
  pub def specialize(rows Vec(Unk0441), c Unk0431, env Map(Unk0428, Unk0429)) Vec(Unk0441) := …

  # Exhaustiveness.useful?/3
  pub def useful?(rows Vec(Unk0441), p1 Vec(Unk0450), _env Map(Unk0428, Unk0429)) Bool := …

  # Exhaustiveness.witness/3
  pub def witness(rows Vec(Unk0441), p1 Int53, _env Map(Unk0428, Unk0429)) Unk0451 := …

  # Fixpoint.check/4
  pub def check(mod Unk0452, corpus Unk0453, project Unk0454, p3 Unk0455) Unk0456 := …

  # Fixpoint.load_lexer/2
  pub def load_lexer(source String, mod Unk0008) Unk0008 := …

  # Format.apply_node/3
  pub def apply_node(p0 Option(Unk0457), base Vec(Unk0408), st Vec(Vec(Unk0408))) Vec(Vec(Unk0408)) := …

  # Format.bd/3
  pub def bd(p0 Vec(Option(Unk0457)), _prev Option(Unk0457), _rf Bool) Unk0396 := …

  # Format.blank?/1
  pub def blank?(p0 Option(Unk0458)) Bool := …

  # Format.block_head?/2
  pub def block_head?(p0 Vec(Option(Unk0457)), next Vec(Option(Unk0458))) Bool := …

  # Format.boundary?/1
  pub def boundary?(p0 Option(Unk0458)) Bool := …

  # Format.boundary_tok?/1
  pub def boundary_tok?(p0 Unk0459) Bool := …

  # Format.chunk_on_comma/3
  pub def chunk_on_comma(p0 Vec(Unk0460), cur Vec(Unk0460), acc Vec(Vec(Unk0460))) Vec(Vec(Unk0460)) := …

  # Format.closer_lead?/1
  pub def closer_lead?(p0 Unk0461) Bool := …

  # Format.comment_only?/1
  pub def comment_only?(line Option(Unk0458)) Bool := …

  # Format.cons_group?/1
  pub def cons_group?(inner Vec(Unk0462)) Bool := …

  # Format.cont_lead?/1
  pub def cont_lead?(p0 Unk0463) Bool := …

  # Format.decl_kw?/1
  pub def decl_kw?(p0 Unk0459) Bool := …

  # Format.declaration_line?/1
  pub def declaration_line?(p0 Vec(Option(Unk0457))) Bool := …

  # Format.finish_items/2
  pub def finish_items(cur Vec(Unk0460), acc Vec(Vec(Unk0460))) Vec(Vec(Unk0460)) := …

  # Format.format/1
  pub def format(src Unk0464) Unk0464 := …

  # Format.format_result/1
  pub def format_result(src Unk0464) Unk0465 := …

  # Format.group_doc/4
  pub def group_doc(open Unk0466, inner Unk0467, close Unk0466, reflow? Bool) Unk0396 := …

  # Format.has_comment?/1
  pub def has_comment?(nodes Vec(Unk0468)) Bool := …

  # Format.has_tok?/2
  pub def has_tok?(line Vec(Unk0469), t Unk0470) Bool := …

  # Format.head_tok/1
  pub def head_tok(p0 Option(Unk0457)) Unk0459 := …

  # Format.indent_and_render/4
  pub def indent_and_render(p0 Vec(Option(Unk0458)), _stack Vec(Vec(Unk0408)), _cont Int53, acc Vec(String)) Vec(String) := …

  # Format.lead_adjust/1
  pub def lead_adjust(p0 Vec(Option(Unk0457))) Int53 := …

  # Format.leaf/1
  pub def leaf(p0 Unk0466) String := …

  # Format.line_doc/1
  pub def line_doc(nodes Vec(Option(Unk0457))) Unk0396 := …

  # Format.ll/3
  pub def ll(p0 Vec(Unk0471), cur Vec(Unk0471), acc Vec(Vec(Unk0471))) Vec(Vec(Unk0471)) := …

  # Format.logical_lines/1
  pub def logical_lines(nodes Vec(Unk0471)) Vec(Vec(Unk0471)) := …

  # Format.mark/1
  pub def mark(nodes Option(Unk0458)) Vec(Option(Unk0457)) := …

  # Format.mark/3
  pub def mark(p0 Option(Unk0458), _prev Option(Unk0457), acc Vec(Option(Unk0457))) Vec(Option(Unk0457)) := …

  # Format.next_code_line/1
  pub def next_code_line(p0 Vec(Option(Unk0458))) Option(Unk0458) := …

  # Format.node_doc/2
  pub def node_doc(p0 Option(Unk0457), _rf Bool) Unk0396 := …

  # Format.pop/1
  pub def pop(p0 Vec(Vec(Unk0408))) Vec(Vec(Unk0408)) := …

  # Format.push/2
  pub def push(base Vec(Unk0408), st Vec(Vec(Unk0408))) Vec(Vec(Unk0408)) := …

  # Format.render_line/2
  pub def render_line(nodes Vec(Option(Unk0457)), base Vec(Unk0408)) String := …

  # Format.space?/2
  pub def space?(_prev Unk0472, p1 Unk0459) Bool := …

  # Format.split_items/1
  pub def split_items(nodes Unk0467) Unk0473 := …

  # Format.squeeze_blanks/1
  pub def squeeze_blanks(lines Unk0474) Unk0475 := …

  # Format.tail_tok/1
  pub def tail_tok(p0 Option(Unk0457)) Unk0472 := …

  # Format.trailing_comma?/1
  pub def trailing_comma?(inner Vec(Unk0476)) Bool := …

  # Format.trailing_op?/1
  pub def trailing_op?(line Vec(Option(Unk0457))) Bool := …

  # Format.update_stack/4
  pub def update_stack(line Vec(Option(Unk0457)), rest Vec(Option(Unk0458)), base Vec(Unk0408), stack Vec(Vec(Unk0408))) Vec(Vec(Unk0408)) := …

  # Format.value_end?/1
  pub def value_end?(p0 Option(Unk0457)) Bool := …

  # Format.value_end_tok?/1
  pub def value_end_tok?(p0 Unk0472) Bool := …

  # FormsEquiv.abstract_code/1
  pub def abstract_code(beam Unk0477) Unk0478 := …

  # FormsEquiv.alpha_rename/1
  pub def alpha_rename(form Unk0479) Unk0480 := …

  # FormsEquiv.bool_clause/1
  pub def bool_clause(p0 Unk0481) Unk0482 := …

  # FormsEquiv.bool_clause_pair/1
  pub def bool_clause_pair(p0 Vec(Unk0483)) Unk0484 := …

  # FormsEquiv.canon_bool_case/1
  pub def canon_bool_case(p0 Vec(Unk0485)) Vec(Unk0485) := …

  # FormsEquiv.diff/2
  pub def diff(a Unk0486, b Unk0486) Unk0487 := …

  # FormsEquiv.equivalent?/2
  pub def equivalent?(a Unk0486, b Unk0486) Bool := …

  # FormsEquiv.fold_neg_literal/1
  pub def fold_neg_literal(p0 Vec(Unk0488)) Vec(Unk0488) := …

  # FormsEquiv.key/1
  pub def key(p0 Unk0489) Unk0490 := …

  # FormsEquiv.normalize/1
  pub def normalize(beam Unk0486) Unk0491 := …

  # FormsEquiv.user_function?/1
  pub def user_function?(p0 Unk0492) Bool := …

  # FormsEquiv.verified?/2
  pub def verified?(oracle Unk0486, port Unk0486) Bool := …

  # FormsEquiv.verify/2
  pub def verify(oracle Unk0486, port Unk0486) Vec(Unk0493) := …

  # FormsEquiv.walk_rename/2
  pub def walk_rename(p0 Unk0479, map Unk0494) Unk0495 := …

  # FormsEquiv.zero_anno/1
  pub def zero_anno(tuple Vec(Unk0496)) Vec(Unk0496) := …

  # History.add/1
  pub def add(line Unk0497) Unk0498 := …

  # History.dedup_consecutive/1
  pub def dedup_consecutive(p0 Vec(Vec(Unk0499))) Vec(Vec(Unk0499)) := …

  # History.load/0
  pub def load() Vec(Unk0500) := …

  # History.path/0
  pub def path() Unk0501 := …

  # Infer.app/2
  pub def app(head String, args Vec(Unk0502)) Unk0503 := …

  # Infer.app1/2
  pub def app1(head String, s Unk0504) Unk0505 := …

  # Infer.bind/3
  pub def bind(s Unk0506, id Unk0507, t Unk0508) Unk0509 := …

  # Infer.bind_checked/3
  pub def bind_checked(s Unk0504, i Unk0510, t Unk0503) Unk0511 := …

  # Infer.bind_params/3
  pub def bind_params(args Unk0512, pvars Unk0513, store Unk0514) Unk0515 := …

  # Infer.build_ctx/2
  pub def build_ctx(stdlib_map Unk0516, p1 Unk0517) Unk0518 := …

  # Infer.build_ledger/2
  pub def build_ledger(params Unk0519, ret String) Vec(Unk0520) := …

  # Infer.call_sig/6
  pub def call_sig(ctx Map(Unk0521, Unk0522), key Unk0523, args Vec(Bool), env Map(String, Unk0524), _outer Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.case_arm/1
  pub def case_arm(p0 Unk0525) Unk0526 := …

  # Infer.clear_xmod/0
  pub def clear_xmod() Unk0527 := …

  # Infer.cluster_name/2
  pub def cluster_name(clusters Unk0528, struct String) String := …

  # Infer.con/1
  pub def con(name String) Unk0503 := …

  # Infer.do_unify/3
  pub def do_unify(s Unk0504, t Unk0503, t Unk0503) Unk0511 := …

  # Infer.free_vars/2
  pub def free_vars(store Unk0504, t Unk0503) Vec(Unk0529) := …

  # Infer.fresh/1
  pub def fresh(s Unk0504) Unk0505 := …

  # Infer.fresh_n/2
  pub def fresh_n(s Unk0504, k Int53) Unk0530 := …

  # Infer.fresh_num/1
  pub def fresh_num(s Unk0504) Unk0505 := …

  # Infer.freshen_tvars/2
  pub def freshen_tvars(tvars Vec(Unk0531), s Unk0504) Unk0532 := …

  # Infer.gen/4
  pub def gen(n Bool, _env Map(String, Unk0524), _ctx Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.gen_args_then_fresh/4
  pub def gen_args_then_fresh(args Vec(Bool), env Map(String, Unk0524), ctx Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.gen_block/4
  pub def gen_block(p0 Vec(Bool), _env Map(String, Unk0524), _ctx Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.gen_cons/5
  pub def gen_cons(h Bool, t Bool, env Map(String, Unk0524), ctx Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.gen_pat/4
  pub def gen_pat(p0 Vec(Unk0533), pv Unk0503, env Map(String, Unk0524), s Unk0504) Unk0534 := …

  # Infer.gen_pat_cons/5
  pub def gen_pat_cons(h Vec(Unk0533), t Vec(Unk0533), pv Unk0503, env Map(String, Unk0524), s Unk0504) Unk0534 := …

  # Infer.generalize_map/3
  pub def generalize_map(pvars Unk0535, rvar Unk0503, store Unk0504) Unk0536 := …

  # Infer.hole_or/2
  pub def hole_or(p0 Unk0537, h Unk0537) Unk0537 := …

  # Infer.hole_sig?/1
  pub def hole_sig?(p0 Unk0538) Bool := …

  # Infer.infer_group/2
  pub def infer_group(p0 Unk0539, ctx Map(Unk0521, Unk0522)) Unk0540 := …

  # Infer.instantiate/5
  pub def instantiate(p0 Unk0541, args Vec(Bool), env Map(String, Unk0524), ctx Map(Unk0521, Unk0522), s Unk0504) Unk0505 := …

  # Infer.load_prelude_sigs/0
  pub def load_prelude_sigs() Unk0542 := …

  # Infer.mark_num/2
  pub def mark_num(s Unk0504, t Unk0503) Unk0543 := …

  # Infer.max_ph/1
  pub def max_ph(p0 Vec(Unk0544)) Int53 := …

  # Infer.mod_name/1
  pub def mod_name(p0 Unk0545) String := …

  # Infer.num_conflict?/3
  pub def num_conflict?(s Unk0546, i Unk0547, t Unk0548) Bool := …

  # Infer.numeric_con?/1
  pub def numeric_con?(p0 Unk0548) Bool := …

  # Infer.occurs?/3
  pub def occurs?(s Unk0504, i Unk0549, t Unk0503) Bool := …

  # Infer.ok_payload/3
  pub def ok_payload(tail_pairs Vec(Unk0550), ctx Map(Unk0521, Unk0522), store Unk0551) Unk0552 := …

  # Infer.parse_type/2
  pub def parse_type(str Unk0553, fmap Unk0554) Unk0555 := …

  # Infer.prelude_sigs/0
  pub def prelude_sigs() Unk0542 := …

  # Infer.prime_xmod/2
  pub def prime_xmod(modules Unk0556, stdlib_map Unk0557) Unk0558 := …

  # Infer.put_slot/3
  pub def put_slot(sig Unk0559, p1 String, ts String) Unk0560 := …

  # Infer.render/3
  pub def render(store Unk0504, gmap Unk0536, t Unk0503) String := …

  # Infer.render_wp/3
  pub def render_wp(store Unk0504, unk_names Unk0561, t Unk0503) String := …

  # Infer.resolve/2
  pub def resolve(s Unk0504, p1 Unk0503) Unk0503 := …

  # Infer.resolve_program/2
  pub def resolve_program(sigvars Vec(Unk0562), store Unk0504) Unk0563 := …

  # Infer.resolve_struct_params/4
  pub def resolve_struct_params(args Unk0564, pvars Unk0565, ctx Unk0566, s Unk0567) Unk0568 := …

  # Infer.result_analysis/3
  pub def result_analysis(clause_envs Vec(Unk0569), ctx Map(Unk0521, Unk0522), store Unk0570) Unk0571 := …

  # Infer.result_tag/1
  pub def result_tag(p0 Unk0572) Unk0573 := …

  # Infer.sig_of/1
  pub def sig_of(f Unk0574) Unk0575 := …

  # Infer.sigvar_call/5
  pub def sigvar_call(ctx Map(Unk0521, Unk0522), key Unk0576, args Unk0577, env Map(String, Unk0524), s Unk0504) Unk0578 := …

  # Infer.slot_sig/3
  pub def slot_sig(p0 String, ts String, _ Vec(Unk0579)) Unk0580 := …

  # Infer.store_new/0
  pub def store_new() Unk0504 := …

  # Infer.tvar?/1
  pub def tvar?(s Unk0581) Unk0582 := …

  # Infer.tvar_name/1
  pub def tvar_name(i Unk0583) Unk0584 := …

  # Infer.unify/3
  pub def unify(s Unk0504, a Unk0503, b Unk0503) Unk0511 := …

  # Infer.unk_vars/2
  pub def unk_vars(store Unk0504, v Unk0503) Vec(Unk0585) := …

  # Infer.whole_program/3
  pub def whole_program(modules Unk0586, stdlib Unk0587, p2 Unk0588) Unk0563 := …

  # Infer.xmod_cache/0
  pub def xmod_cache() Unk0589 := …

  # Interp.concat_chain/1
  pub def concat_chain(parts Vec(Unk0590)) Unk0590 := …

  # Interp.int_type?/1
  pub def int_type?(t Unk0591) Bool := …

  # Interp.resolve/4
  pub def resolve(p0 Vec(Unk0228), env Map(Unk0090, String), ic Map(Unk0083, Map(String, String)), show Unk0308) Sum1 := …

  # Interp.resolve_part/4
  pub def resolve_part(p0 Unk0592, _env Map(Unk0090, String), _ic Map(Unk0083, Map(String, String)), _show Unk0308) Sum1 := …

  # Interp.stringify/3
  pub def stringify(expr Sum1, p1 String, _show Unk0308) Sum1 := …

  # JS.all_funcs/1
  pub def all_funcs(prog Map(Unk0594, Vec(Unk0593))) Vec(Unk0593) := …

  # JS.arm_return/2
  pub def arm_return(body Unk0595, p1 Unk0596) String := …

  # JS.bind_lines/1
  pub def bind_lines(binds Vec(Unk0597)) Vec(String) := …

  # JS.block_return/1
  pub def block_return(p0 Vec(Unk0598)) String := …

  # JS.branch_js/1
  pub def branch_js(p0 Sum1) String := …

  # JS.case_arm_js/1
  pub def case_arm_js(p0 Unk0599) String := …

  # JS.clause_js/1
  pub def clause_js(p0 Unk0600) String := …

  # JS.clause_return/2
  pub def clause_return(src Sum1, params Vec(Unk0601)) String := …

  # JS.cp_lit/1
  pub def cp_lit(cp Unk0602) String := …

  # JS.dispatcher_js/4
  pub def dispatcher_js(proto Unk0603, method Unk0604, impl_types Vec(Unk0605), reg Unk0606) String := …

  # JS.expr_js/1
  pub def expr_js(p0 Sum1) String := …

  # JS.first_unsupported/2
  pub def first_unsupported(node Unk0607, unsup Map(Unk0608, Option(Unk0609))) Option(Unk0609) := …

  # JS.float?/1
  pub def float?(n Unk0610) Bool := …

  # JS.function_js/1
  pub def function_js(p0 Unk0611) String := …

  # JS.guarded_return/3
  pub def guarded_return(body Sum1, p1 Unk0612, params Vec(Unk0601)) String := …

  # JS.js_atom/1
  pub def js_atom(name Unk0613) String := …

  # JS.js_guard!/3
  pub def js_guard!(type Unk0614, proto Unk0615, reg Unk0616) Unk0617 := …

  # JS.js_number_int?/1
  pub def js_number_int?(t Unk0618) Bool := …

  # JS.js_str/1
  pub def js_str(s Unk0613) String := …

  # JS.lit_js/1
  pub def lit_js(v Unk0613) String := …

  # JS.mangle/3
  pub def mangle(proto Unk0619, type Unk0620, method Unk0621) String := …

  # JS.match_elems/2
  pub def match_elems(es Unk0622, acc String) Unk0623 := …

  # JS.num_js/1
  pub def num_js(n Unk0624) String := …

  # JS.paren/1
  pub def paren(e Unk0625) String := …

  # JS.pascal?/1
  pub def pascal?(s Unk0626) Bool := …

  # JS.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Unk0627 := …

  # JS.program_number_mode?/1
  pub def program_number_mode?(prog Map(Unk0033, Vec(Type))) Bool := …

  # JS.protocol_dispatchers_js/1
  pub def protocol_dispatchers_js(prog Map(Unk0033, Vec(Type))) String := …

  # JS.reject_mixed_int_mode!/1
  pub def reject_mixed_int_mode!(prog Map(Unk0033, Vec(Type))) Unk0628 := …

  # JS.reject_unsupported!/1
  pub def reject_unsupported!(funcs Vec(Unk0629)) Unk0630 := …

  # JS.reject_wide_int!/2
  pub def reject_wide_int!(name Unk0631, p1 Unk0632) Unk0633 := …

  # JS.split_top_commas/1
  pub def split_top_commas(s String) Vec(Unk0081) := …

  # JS.stmt_js/1
  pub def stmt_js(p0 Unk0634) String := …

  # JS.stmt_return/1
  pub def stmt_return(p0 Unk0635) String := …

  # JS.struct_name_set/1
  pub def struct_name_set(prog Map(Unk0637, Vec(Unk0636))) Unk0638 := …

  # JS.sum_ctor_map/1
  pub def sum_ctor_map(prog Map(Unk0640, Vec(Unk0639))) Unk0641 := …

  # JS.sum_guard_js/1
  pub def sum_guard_js(ctors Vec(Unk0642)) String := …

  # JVM.all_funcs/1
  pub def all_funcs(prog Map(Unk0644, Vec(Unk0643))) Vec(Unk0643) := …

  # JVM.all_types/1
  pub def all_types(prog Map(Unk0033, Vec(Type))) Vec(Type) := …

  # JVM.bind_str/1
  pub def bind_str(p0 Vec(Unk0645)) String := …

  # JVM.block_value/1
  pub def block_value(p0 Vec(Unk0598)) String := …

  # JVM.branch_kt/1
  pub def branch_kt(p0 Sum1) String := …

  # JVM.case_arms/2
  pub def case_arms(arms Unk0646, acc String) Unk0647 := …

  # JVM.clause_lines/1
  pub def clause_lines(clauses Unk0648) Unk0649 := …

  # JVM.clause_match/1
  pub def clause_match(pats Unk0650) Unk0651 := …

  # JVM.clause_value/2
  pub def clause_value(src Sum1, params Vec(Unk0601)) String := …

  # JVM.expr_kt/1
  pub def expr_kt(p0 Sum1) String := …

  # JVM.first_unsupported/2
  pub def first_unsupported(node Unk0652, unsup Map(Unk0653, Option(Unk0654))) Option(Unk0654) := …

  # JVM.function_kt/1
  pub def function_kt(p0 Unk0655) String := …

  # JVM.guarded_arm/2
  pub def guarded_arm(body_kt String, p1 Unk0656) String := …

  # JVM.guarded_return/3
  pub def guarded_return(body Unk0657, p1 Unk0658, params Vec(Unk0659)) String := …

  # JVM.kotlin_module/2
  pub def kotlin_module(src String, p1 Unk0660) String := …

  # JVM.kt_str/1
  pub def kt_str(s Unk0661) String := …

  # JVM.kt_type/1
  pub def kt_type(p0 Unk0662) Unk0663 := …

  # JVM.lit_kt/1
  pub def lit_kt(v Unk0661) String := …

  # JVM.pat_match/2
  pub def pat_match(p0 Sum2, _acc String) Unk0664 := …

  # JVM.reject_unsupported!/1
  pub def reject_unsupported!(funcs Vec(Unk0665)) Unk0666 := …

  # JVM.stmt_kt/1
  pub def stmt_kt(p0 Unk0667) String := …

  # JVM.stmt_value/1
  pub def stmt_value(p0 Unk0668) String := …

  # JVM.sum_decl/1
  pub def sum_decl(t Unk0669) String := …

  # JVM.to_jar/3
  pub def to_jar(src String, jar_path Unk0670, p2 Unk0671) Unk0672 := …

  # JVM.variant_decl/2
  pub def variant_decl(p0 Unk0673, tname Unk0674) String := …

  # Lexer.advance/2
  pub def advance(s Unk0675, n Unk0676) Unk0677 := …

  # Lexer.binify/1
  pub def binify(acc Unk0678) Unk0679 := …

  # Lexer.capture_hole/3
  pub def capture_hole(p0 String, _d Int53, _acc Vec(String)) Unk0680 := …

  # Lexer.char_escape/1
  pub def char_escape(p0 Unk0681) Unk0682 := …

  # Lexer.close_char/1
  pub def close_char(p0 String) Unk0683 := …

  # Lexer.collapse_nl/1
  pub def collapse_nl(tokens Unk0684) Unk0685 := …

  # Lexer.cp!/1
  pub def cp!(n Unk0686) Unk0686 := …

  # Lexer.detokenize/2
  pub def detokenize(tokens Unk0687, p1 Unk0688) Unk0689 := …

  # Lexer.escape_str/1
  pub def escape_str(s Unk0690) String := …

  # Lexer.expr_tokens/1
  pub def expr_tokens(src Sum1) Vec(Vec(Vec(Unk0691))) := …

  # Lexer.lex/2
  pub def lex(str Unk0692, acc Vec(Unk0693)) Unk0694 := …

  # Lexer.lex_char/1
  pub def lex_char(p0 String) Unk0695 := …

  # Lexer.lex_parts/3
  pub def lex_parts(p0 String, _lit Vec(String), _parts Vec(Unk0696)) Unk0697 := …

  # Lexer.lex_string_token/1
  pub def lex_string_token(str String) Unk0698 := …

  # Lexer.norm_num/1
  pub def norm_num(lexeme Unk0699) Unk0699 := …

  # Lexer.parse_hex!/1
  pub def parse_hex!(hex Unk0700) Unk0701 := …

  # Lexer.punct/1
  pub def punct(str Unk0702) Option(Unk0703) := …

  # Lexer.string_token/1
  pub def string_token(parts Vec(Unk0704)) Unk0705 := …

  # Lexer.strip_trivia/1
  pub def strip_trivia(tokens Unk0706) Unk0707 := …

  # Lexer.take_comment/1
  pub def take_comment(str Unk0708) Unk0709 := …

  # Lexer.take_hex/2
  pub def take_hex(str Unk0710, max Int53) Unk0711 := …

  # Lexer.take_hex/3
  pub def take_hex(p0 Unk0710, max Int53, acc String) Unk0711 := …

  # Lexer.tok_str/2
  pub def tok_str(p0 Unk0712, nl_as String) String := …

  # Lexer.tokenize/1
  pub def tokenize(src Unk0713) Unk0714 := …

  # Lexer.tokenize_trivia/1
  pub def tokenize_trivia(src Unk0692) Unk0694 := …

  # Lexer.word/1
  pub def word(w Unk0715) Unk0716 := …

  # Livebook.eval/1
  pub def eval(source Unk0717) Unk0718 := …

  # Livebook.output/1
  pub def output(p0 Vec(String)) Unk0718 := …

  # Livebook.reset/0
  pub def reset() Unk0719 := …

  # Livebook.run/2
  pub def run(session Unk0720, source Unk0717) Unk0721 := …

  # Livebook.session_pid/0
  pub def session_pid() Unk0722 := …

  # Lower.add_list_elem_vars/2
  pub def add_list_elem_vars(acc Unk0723, p1 Unk0724) Unk0723 := …

  # Lower.add_var/2
  pub def add_var(acc Unk0723, p1 Unk0725) Unk0723 := …

  # Lower.all_pat_vars/1
  pub def all_pat_vars(p0 Sum2) Vec(Unk0726) := …

  # Lower.arm_rebinds/3
  pub def arm_rebinds(pats Unk0727, iso Unk0728, used Unk0729) Vec(Unk0730) := …

  # Lower.assoc/1
  pub def assoc(op Unk0731) Unk0732 := …

  # Lower.assoc_proj/2
  pub def assoc_proj(s String, assoc Vec(Unk0733)) String := …

  # Lower.body_ast/2
  pub def body_ast(src Unk0734, ctx Unk0735) Unk0736 := …

  # Lower.borrow_arg/4
  pub def borrow_arg(a Unk0737, pt Unk0738, funs Map(Unk0739, Unk0740), borrowed Bool) Unk0741 := …

  # Lower.borrow_value/2
  pub def borrow_value(p0 Vec(Unk0228), _borrowed Bool) Vec(Unk0228) := …

  # Lower.borrowed_in_pat/2
  pub def borrowed_in_pat(p0 Sum2, p1 Bool) Vec(Unk0742) := …

  # Lower.borrowed_vars/2
  pub def borrowed_vars(params Unk0743, pats Unk0744) Option(Unk0745) := …

  # Lower.build_env/3
  pub def build_env(types Vec(Type), structs Vec(Unk0746), ranges Vec(Unk0747)) Unk0748 := …

  # Lower.build_meta/1
  pub def build_meta(types Vec(Type)) Unk0749 := …

  # Lower.build_struct_meta/1
  pub def build_struct_meta(structs Vec(Type)) Unk0750 := …

  # Lower.cap_arity/1
  pub def cap_arity(p0 Sum1) Int53 := …

  # Lower.case_guard/2
  pub def case_guard(p0 Sum1, _ Unk0751) String := …

  # Lower.catchall_pat?/1
  pub def catchall_pat?(p0 Sum2) Bool := …

  # Lower.char_vars/2
  pub def char_vars(params Unk0752, pats Unk0753) Unk0754 := …

  # Lower.check!/2
  pub def check!(p0 Unk0755, _env Unk0748) Unk0756 := …

  # Lower.coerce_string_ast/1
  pub def coerce_string_ast(p0 Sum1) String := …

  # Lower.coerce_string_branch/1
  pub def coerce_string_branch(p0 Sum1) String := …

  # Lower.collect_ids/2
  pub def collect_ids(p0 Vec(Unk0757), acc Unk0729) Unk0729 := …

  # Lower.collect_owned_field_vars/3
  pub def collect_owned_field_vars(p0 Unk0758, ctx Map(Unk0759, Unk0760), acc Unk0761) Unk0761 := …

  # Lower.compile/4
  pub def compile(types Vec(Type), func Unk0755, p2 Unk0762, p3 Unk0763) Unk0764 := …

  # Lower.compile_beam/4
  pub def compile_beam(types Vec(Type), func Unk0755, p2 Unk0765, p3 Unk0766) Unk0767 := …

  # Lower.compile_elixir/4
  pub def compile_elixir(types Vec(Type), func Unk0755, p2 Unk0768, p3 Unk0769) Unk0764 := …

  # Lower.compile_module/1
  pub def compile_module(p0 Unk0770) Unk0771 := …

  # Lower.compile_module_beam/1
  pub def compile_module_beam(p0 Unk0772) Unk0773 := …

  # Lower.cons_tail_names/1
  pub def cons_tail_names(p0 Sum2) Vec(Unk0774) := …

  # Lower.cons_tail_rebinds/1
  pub def cons_tail_rebinds(p0 Sum2) Vec(String) := …

  # Lower.const_set/1
  pub def const_set(consts Vec(Unk0775)) Unk0776 := …

  # Lower.core_pat_ex/1
  pub def core_pat_ex(surface Sum2) String := …

  # Lower.core_pat_rs/2
  pub def core_pat_rs(surface Sum2, meta Unk0777) String := …

  # Lower.core_pat_vars/1
  pub def core_pat_vars(p0 Sum2) Vec(Unk0778) := …

  # Lower.ctx/4
  pub def ctx(meta Unk0749, smeta Unk0750, cset Unk0776, p3 Unk0779) Map(Unk0759, Unk0760) := …

  # Lower.deref_ids/2
  pub def deref_ids(ast Vec(Unk0780), p1 Vec(Unk0781)) Vec(Unk0780) := …

  # Lower.disp/2
  pub def disp(p0 String, p1 Unk0782) String := …

  # Lower.elixir_clauses/3
  pub def elixir_clauses(func Map(Unk0784, Unk0783), ctx Unk0785, def_kw String) String := …

  # Lower.emit/2
  pub def emit(p0 Sum1, _t Unk0751) Unk0786 := …

  # Lower.emit_ast/2
  pub def emit_ast(ast Sum1, target Unk0751) Unk0787 := …

  # Lower.emit_block/2
  pub def emit_block(p0 Sum1, p1 Unk0788) String := …

  # Lower.emit_expr/2
  pub def emit_expr(src Sum1, target Unk0751) Unk0789 := …

  # Lower.enum_generics/1
  pub def enum_generics(name Unk0790) String := …

  # Lower.err_payload/1
  pub def err_payload(e Sum1) String := …

  # Lower.ex_const/2
  pub def ex_const(c Unk0775, ctx Unk0785) String := …

  # Lower.ex_doc/2
  pub def ex_doc(p0 Unk0783, _attr String) String := …

  # Lower.ex_scope/0
  pub def ex_scope() Unk0791 := …

  # Lower.ex_struct/1
  pub def ex_struct(s Unk0792) String := …

  # Lower.ex_typespec/1
  pub def ex_typespec(t Map(Unk0793, Unk0783)) String := …

  # Lower.ex_use/1
  pub def ex_use(p0 Unk0794) String := …

  # Lower.flatten_concat/1
  pub def flatten_concat(p0 Sum1) Vec(Sum1) := …

  # Lower.fn_all_tvars/2
  pub def fn_all_tvars(func Map(Unk0796, Vec(Unk0795)), pinst Unk0797) Vec(Unk0795) := …

  # Lower.generic_tvar_borrow?/1
  pub def generic_tvar_borrow?(p0 Unk0798) Bool := …

  # Lower.guard_kw/1
  pub def guard_kw(p0 Unk0751) String := …

  # Lower.guard_str/3
  pub def guard_str(c Map(Unk0799, Sum1), target Unk0751, p2 Unk0800) String := …

  # Lower.impl_param/2
  pub def impl_param(p0 Unk0801, rust_type String) String := …

  # Lower.infer_concrete_params/2
  pub def infer_concrete_params(func Unk0802, params Vec(Unk0803)) Vec(String) := …

  # Lower.infer_tvar_binding/1
  pub def infer_tvar_binding(p0 Unk0804) Unk0805 := …

  # Lower.insert_borrows/3
  pub def insert_borrows(p0 Sum1, funs Map(Unk0739, Unk0740), borrowed Bool) Vec(Unk0228) := …

  # Lower.iso_cons_positions/1
  pub def iso_cons_positions(func Map(Unk0796, Vec(Unk0795))) Unk0728 := …

  # Lower.list_rpat?/1
  pub def list_rpat?(p0 Unk0806) Bool := …

  # Lower.module_elixir/1
  pub def module_elixir(p0 Unk0807) String := …

  # Lower.module_rust/1
  pub def module_rust(p0 Unk0808) String := …

  # Lower.name_type/1
  pub def name_type(p Unk0081) Unk0809 := …

  # Lower.ofb/3
  pub def ofb(p0 Vec(Unk0810), ctx Map(Unk0759, Unk0760), acc Unk0761) Unk0761 := …

  # Lower.ok_payload/1
  pub def ok_payload(v Sum1) String := …

  # Lower.owned_arg?/2
  pub def owned_arg?(p0 Unk0811, _funs Map(Unk0812, Unk0813)) Bool := …

  # Lower.owned_field_binders/2
  pub def owned_field_binders(ast Vec(Unk0810), ctx Map(Unk0759, Unk0760)) Unk0761 := …

  # Lower.owned_field_var?/1
  pub def owned_field_var?(p0 Unk0814) Bool := …

  # Lower.owned_scrut?/2
  pub def owned_scrut?(p0 Unk0815, _ctx Map(Unk0759, Unk0760)) Bool := …

  # Lower.owned_str_arg/1
  pub def owned_str_arg(s Unk0816) Unk0817 := …

  # Lower.p/3
  pub def p(node Sum1, ctx Int53, t Unk0751) String := …

  # Lower.pair_inst/1
  pub def pair_inst(func Map(Unk0796, Vec(Unk0795))) Unk0797 := …

  # Lower.param_rtypes/2
  pub def param_rtypes(name Unk0739, funs Map(Unk0739, Unk0740)) Vec(String) := …

  # Lower.parametric_param_map/1
  pub def parametric_param_map(types Vec(Type)) Unk0818 := …

  # Lower.parametric_used?/2
  pub def parametric_used?(func Map(Unk0796, Vec(Unk0795)), name Unk0819) Bool := …

  # Lower.pascal?/1
  pub def pascal?(s Unk0820) Bool := …

  # Lower.pat_ex/1
  pub def pat_ex(p0 Sum2) String := …

  # Lower.pat_rs/2
  pub def pat_rs(p0 Sum2, _ Unk0777) String := …

  # Lower.pcommas/1
  pub def pcommas(s String) Vec(Unk0081) := …

  # Lower.pipe_to_call/2
  pub def pipe_to_call(l Unk0821, p1 Sum1) Sum1 := …

  # Lower.prec/1
  pub def prec(op Unk0822) Unk0823 := …

  # Lower.proto_method_traits/1
  pub def proto_method_traits(protocols Vec(Type)) Unk0824 := …

  # Lower.proto_methods/0
  pub def proto_methods() Unk0825 := …

  # Lower.pub_sig_type_names/1
  pub def pub_sig_type_names(funcs Unk0826) Unk0827 := …

  # Lower.put_ex_scope/1
  pub def put_ex_scope(s Unk0791) Unk0828 := …

  # Lower.put_result_str_flags/1
  pub def put_result_str_flags(ret Unk0829) Unk0830 := …

  # Lower.ref_type/2
  pub def ref_type(p0 String, self_repr Unk0831) String := …

  # Lower.resolve_consts/2
  pub def resolve_consts(p0 Sum1, cset Unk0832) Vec(Unk0228) := …

  # Lower.resolve_rust_pats/2
  pub def resolve_rust_pats(p0 Sum1, meta Unk0833) Vec(Unk0228) := …

  # Lower.resolve_structs/2
  pub def resolve_structs(p0 Sum1, smeta Unk0834) Vec(Unk0228) := …

  # Lower.resolve_variants/2
  pub def resolve_variants(p0 Sum1, meta Map(Unk0836, Option(Unk0835))) Vec(Unk0228) := …

  # Lower.rest_pat_rs/1
  pub def rest_pat_rs(p0 Sum2) String := …

  # Lower.result_parts/1
  pub def result_parts(ret Unk0829) Unk0837 := …

  # Lower.rewrite_proto_calls/2
  pub def rewrite_proto_calls(p0 Vec(Unk0838), methods Unk0839) Vec(Unk0838) := …

  # Lower.rpat/1
  pub def rpat(p0 Sum2) String := …

  # Lower.rs_doc/2
  pub def rs_doc(p0 Vec(Unk0795), _prefix String) String := …

  # Lower.rust_arm_body/2
  pub def rust_arm_body(p0 Sum1, s String) String := …

  # Lower.rust_case/3
  pub def rust_case(scrut Sum1, arms Vec(Unk0840), body_fn Fn(Unk0842, Unk0841)) String := …

  # Lower.rust_const/2
  pub def rust_const(c Unk0775, ctx Map(Unk0759, Unk0760)) String := …

  # Lower.rust_enum/2
  pub def rust_enum(t Map(Unk0843, Vec(Unk0795)), p1 Unk0844) String := …

  # Lower.rust_fn/3
  pub def rust_fn(p0 Map(Unk0796, Vec(Unk0795)), _ctx Map(Unk0759, Unk0760), vis String) String := …

  # Lower.rust_generics/1
  pub def rust_generics(p0 Unk0845) String := …

  # Lower.rust_impl/3
  pub def rust_impl(p0 Type, protocols Vec(Type), c Map(Unk0759, Unk0760)) String := …

  # Lower.rust_impl_method/5
  pub def rust_impl_method(method Unk0846, sig Unk0847, rust_type String, c Map(Unk0759, Unk0760), copy_recv? Bool) String := …

  # Lower.rust_lit_type/1
  pub def rust_lit_type(p0 Unk0848) String := …

  # Lower.rust_owned_elem/1
  pub def rust_owned_elem(p0 Sum1) String := …

  # Lower.rust_program/1
  pub def rust_program(prog Map(Unk0021, Vec(Type))) String := …

  # Lower.rust_proto_body/2
  pub def rust_proto_body(src Unk0849, c Map(Unk0850, Unk0851)) Unk0852 := …

  # Lower.rust_protocols/4
  pub def rust_protocols(protocols Vec(Type), impl_decls Vec(Type), types Vec(Type), structs Vec(Type)) Unk0853 := …

  # Lower.rust_ret/1
  pub def rust_ret(ret Unk0829) String := …

  # Lower.rust_scrut/2
  pub def rust_scrut(params Unk0854, iso Unk0728) String := …

  # Lower.rust_struct/2
  pub def rust_struct(s Unk0855, p1 Unk0856) String := …

  # Lower.rust_total_shim?/1
  pub def rust_total_shim?(func Map(Unk0796, Vec(Unk0795))) Bool := …

  # Lower.rust_trait/1
  pub def rust_trait(p0 Unk0857) String := …

  # Lower.rust_use/1
  pub def rust_use(p0 Unk0858) String := …

  # Lower.rustify_parametric/2
  pub def rustify_parametric(rust_type Unk0859, pinst Vec(Unk0860)) Unk0859 := …

  # Lower.scalar_literal?/1
  pub def scalar_literal?(p0 Unk0861) Bool := …

  # Lower.self_subst/2
  pub def self_subst(t Unk0862, repr String) Unk0829 := …

  # Lower.sig_param/2
  pub def sig_param(p Unk0081, self_repr Unk0863) String := …

  # Lower.slice_binders/2
  pub def slice_binders(params Unk0864, pats Vec(Sum2)) Unk0865 := …

  # Lower.slice_elem_vars/1
  pub def slice_elem_vars(p0 Sum2) Vec(Unk0866) := …

  # Lower.slice_var?/1
  pub def slice_var?(p0 Sum1) Bool := …

  # Lower.str_lit/1
  pub def str_lit(s Unk0867) String := …

  # Lower.struct_pairs/4
  pub def struct_pairs(name Unk0868, labels Unk0869, args Unk0870, smeta Unk0834) Unk0871 := …

  # Lower.subst_assoc/2
  pub def subst_assoc(t Unk0872, assoc_rust Vec(Unk0873)) Unk0872 := …

  # Lower.tail_expr/1
  pub def tail_expr(p0 Unk0874) Unk0874 := …

  # Lower.tail_slice_id?/1
  pub def tail_slice_id?(p0 Sum1) Bool := …

  # Lower.to_elixir/4
  pub def to_elixir(func Map(Unk0784, Unk0783), types Vec(Type), p2 Unk0875, p3 Unk0876) Unk0877 := …

  # Lower.to_rust/5
  pub def to_rust(func Map(Unk0796, Vec(Unk0795)), types Vec(Unk0878), meta Unk0879, p3 Unk0880, p4 Unk0881) Unk0882 := …

  # Lower.trait_impl_block/3
  pub def trait_impl_block(protocols Vec(Type), impl_decls Vec(Type), c Map(Unk0759, Unk0760)) String := …

  # Lower.trait_params/2
  pub def trait_params(param_str String, self_repr Unk0863) String := …

  # Lower.tuple_or_one/2
  pub def tuple_or_one(p0 Vec(Sum2), f Fn(Sum2, String)) String := …

  # Lower.tvar_name?/1
  pub def tvar_name?(t Unk0883) Bool := …

  # Lower.type_idents/1
  pub def type_idents(p0 Unk0884) Vec(Unk0885) := …

  # Lower.type_param_tvars/1
  pub def type_param_tvars(t Unk0886) Unk0887 := …

  # Lower.used_ids/1
  pub def used_ids(ast Sum1) Unk0729 := …

  # Lower.user_type?/2
  pub def user_type?(t Unk0888, ctx Map(Unk0759, Unk0760)) Bool := …

  # Lower.variant_info/2
  pub def variant_info(meta Map(Unk0836, Option(Unk0835)), name Unk0820) Option(Unk0835) := …

  # Lower.variant_lit/2
  pub def variant_lit(info Option(Unk0835), pairs Vec(Unk0889)) Vec(Unk0228) := …

  # Lower.variant_pairs/3
  pub def variant_pairs(info Option(Unk0835), args Unk0890, meta Map(Unk0836, Option(Unk0835))) Vec(Unk0889) := …

  # Lower.widen_char_arith/2
  pub def widen_char_arith(p0 Sum1, cvars Unk0891) Vec(Unk0228) := …

  # Lower.with_chain_rs/3
  pub def with_chain_rs(p0 Vec(Unk0892), body Unk0893, _else_rs String) String := …

  # Lower.with_ex_scope/2
  pub def with_ex_scope(names Vec(Unk0778), fun Fn(String)) String := …

  # Lower.wrap_char/2
  pub def wrap_char(p0 Vec(Unk0228), _cvars Unk0891) Vec(Unk0228) := …

  # Macro.binders_here/1
  pub def binders_here(p0 Vec(Unk0894)) Vec(Unk0895) := …

  # Macro.build_env/1
  pub def build_env(defs Unk0896) Unk0272 := …

  # Macro.check_portable!/2
  pub def check_portable!(name Unk0897, tmpl Sum1) Unk0898 := …

  # Macro.collect_binders/1
  pub def collect_binders(node Vec(Unk0894)) Vec(Unk0895) := …

  # Macro.do_expand/4
  pub def do_expand(_env Map(Unk0306, Unk0305), _ast Sum1, d Int53, _p Bool) Vec(Unk0228) := …

  # Macro.expand/3
  pub def expand(env Map(Unk0306, Unk0305), ast Sum1, p2 Vec(Unk0899)) Sum1 := …

  # Macro.freshen/2
  pub def freshen(tmpl Vec(Unk0894), params Unk0900) Vec(Unk0228) := …

  # Macro.introduces_failable_bind?/1
  pub def introduces_failable_bind?(node Sum1) Bool := …

  # Macro.map_node/2
  pub def map_node(p0 Sum1, f Fn(Sum1, Vec(Unk0228))) Vec(Unk0228) := …

  # Macro.rename/2
  pub def rename(p0 Vec(Unk0894), ren Unk0901) Vec(Unk0228) := …

  # Macro.substitute/2
  pub def substitute(p0 Vec(Unk0228), subst Map(Unk0902, Sum1)) Sum1 := …

  # Macro.walk_for_with/1
  pub def walk_for_with(p0 Sum1) Vec(Unk0228) := …

  # Opaque.do_erase/2
  pub def do_erase(prog Unk0903, ctx Unk0904) Map(Unk0033, Vec(Type)) := …

  # Opaque.erase/1
  pub def erase(p0 Map(Unk0021, Vec(Type))) Map(Unk0033, Vec(Type)) := …

  # Opaque.erase_clause/3
  pub def erase_clause(p0 Unk0905, _ctx Unk0906, _env Unk0907) Clause := …

  # Opaque.erase_const/2
  pub def erase_const(p0 Unk0908, p1 Unk0909) Const := …

  # Opaque.erase_ctx/1
  pub def erase_ctx(all Vec(Unk0910)) Unk0904 := …

  # Opaque.erase_func/2
  pub def erase_func(p0 Unk0911, p1 Unk0904) Func := …

  # Opaque.erase_mod/2
  pub def erase_mod(p0 Unk0912, ctx Unk0904) Mod := …

  # Opaque.erase_struct/2
  pub def erase_struct(p0 Unk0913, p1 Unk0904) Struct := …

  # Opaque.erase_type/2
  pub def erase_type(p0 Unk0914, p1 Unk0904) Type := …

  # Opaque.erase_variant/2
  pub def erase_variant(p0 Unk0915, names Unk0916) Variant := …

  # Opaque.opaques/1
  pub def opaques(prog Map(Unk0917, Vec(Unk0910))) Vec(Unk0910) := …

  # Opaque.strip/3
  pub def strip(p0 Vec(Unk0918), p1 Unk0919, env Map(Unk0090, String)) Vec(Unk0918) := …

  # Opaque.strip_into/3
  pub def strip_into(ast Vec(Unk0918), ctx Unk0919, env Map(Unk0090, String)) Vec(Unk0918) := …

  # Opaque.subst/2
  pub def subst(p0 Option(Unk0920), _names Unk0921) Option(Unk0920) := …

  # Opaque.subst_fix/4
  pub def subst_fix(type Option(Unk0920), _names Unk0921, _re Unk0922, p3 Int53) Option(Unk0920) := …

  # PatternLower.add_struct/3
  pub def add_struct(env Unk0422, name Unk0063, fields Vec(Unk0063)) Unk0422 := …

  # PatternLower.lower/2
  pub def lower(pat Sum2, env Map(Unk0428, Unk0429)) Unk0923 := …

  # PatternLower.lower_clause/2
  pub def lower_clause(p0 Unk0924, env Map(Unk0428, Unk0429)) Unk0427 := …

  # PatternLower.lower_list/3
  pub def lower_list(p0 Vec(Sum2), p1 Sum2, _env Map(Unk0428, Unk0429)) Unk0923 := …

  # PatternLower.lower_many/2
  pub def lower_many(ps Vec(Sum2), env Map(Unk0428, Unk0429)) Unk0925 := …

  # PatternLower.to_snake/1
  pub def to_snake(name Unk0063) Unk0063 := …

  # PortAnalysis.analyze/1
  pub def analyze(sources Unk0926) Unk0927 := …

  # PortAnalysis.case_arm_sets/1
  pub def case_arm_sets(ast Unk0928) Vec(Unk0929) := …

  # PortAnalysis.clause_head_sets/1
  pub def clause_head_sets(ast Unk0928) Vec(Unk0929) := …

  # PortAnalysis.cluster_sums/1
  pub def cluster_sums(sets Vec(Unk0930)) Unk0931 := …

  # PortAnalysis.collect_errors/2
  pub def collect_errors(ast Unk0932, acc Unk0933) Unk0933 := …

  # PortAnalysis.collect_groups/1
  pub def collect_groups(p0 Unk0934) Vec(Unk0935) := …

  # PortAnalysis.collect_structs/2
  pub def collect_structs(ast Unk0936, acc Unk0937) Unk0937 := …

  # PortAnalysis.dispatch_sets/1
  pub def dispatch_sets(ast Unk0928) Vec(Unk0930) := …

  # PortAnalysis.error_proposal/1
  pub def error_proposal(p0 Unk0938) Unk0939 := …

  # PortAnalysis.error_shape/1
  pub def error_shape(p0 Unk0940) Unk0941 := …

  # PortAnalysis.errors_section/1
  pub def errors_section(data Unk0942) String := …

  # PortAnalysis.head_name_pats/1
  pub def head_name_pats(p0 Unk0943) Unk0944 := …

  # PortAnalysis.holes_section/1
  pub def holes_section(data Unk0942) String := …

  # PortAnalysis.module_name/1
  pub def module_name(p0 Unk0945) String := …

  # PortAnalysis.module_report/3
  pub def module_report(file Unk0946, ast Unk0945, src Unk0947) Unk0948 := …

  # PortAnalysis.needs_review?/1
  pub def needs_review?(p0 Unk0949) Bool := …

  # PortAnalysis.param_name_index/1
  pub def param_name_index(mods_groups Unk0950) Unk0951 := …

  # PortAnalysis.parse/1
  pub def parse(src Unk0952) Option(Unk0953) := …

  # PortAnalysis.pascal/1
  pub def pascal(atom_str Unk0954) Unk0955 := …

  # PortAnalysis.pattern_structs/1
  pub def pattern_structs(p0 Unk0956) Vec(Unk0957) := …

  # PortAnalysis.reach_note/1
  pub def reach_note(type Unk0958) Unk0959 := …

  # PortAnalysis.short/1
  pub def short(p0 Unk0960) String := …

  # PortAnalysis.sigs_section/1
  pub def sigs_section(data Unk0942) String := …

  # PortAnalysis.src_of/2
  pub def src_of(sources Unk0961, file Unk0962) Unk0963 := …

  # PortAnalysis.summary_section/1
  pub def summary_section(data Unk0942) String := …

  # PortAnalysis.sums_section/1
  pub def sums_section(data Unk0942) String := …

  # PortAnalysis.to_markdown/1
  pub def to_markdown(data Unk0942) Unk0964 := …

  # Pratt.after_paren/2
  pub def after_paren(tokens Vec(Unk0965), p1 Int53) Vec(Unk0965) := …

  # Pratt.assoc/1
  pub def assoc(op Option(Unk0966)) Unk0967 := …

  # Pratt.bp/1
  pub def bp(op Option(Unk0966)) Unk0968 := …

  # Pratt.climb/3
  pub def climb(lhs Unk0969, tokens Vec(Vec(Vec(Unk0691))), min_bp Int53) Unk0970 := …

  # Pratt.collect_dots/2
  pub def collect_dots(node Unk0971, p1 Vec(Vec(Unk0691))) Unk0972 := …

  # Pratt.desugar_prop/2
  pub def desugar_prop(stmts Vec(Unk0973), depth Int53) Unk0974 := …

  # Pratt.desugar_propagation/1
  pub def desugar_propagation(stmts Vec(Unk0973)) Unk0974 := …

  # Pratt.expect_kw/2
  pub def expect_kw(p0 Vec(Vec(Vec(Unk0691))), k String) Vec(Vec(Vec(Unk0691))) := …

  # Pratt.expect_op/2
  pub def expect_op(p0 Vec(Vec(Vec(Unk0691))), o String) Vec(Vec(Vec(Unk0691))) := …

  # Pratt.expect_rbracket/1
  pub def expect_rbracket(p0 Vec(Vec(Vec(Unk0691)))) Vec(Vec(Vec(Unk0691))) := …

  # Pratt.expect_rparen/1
  pub def expect_rparen(p0 Vec(Vec(Vec(Unk0691)))) Vec(Vec(Vec(Unk0691))) := …

  # Pratt.finish_arg/2
  pub def finish_arg(a Unk0975, p1 Vec(Vec(Vec(Unk0691)))) Unk0976 := …

  # Pratt.here/1
  pub def here(p0 Vec(Unk0977)) String := …

  # Pratt.int_of/1
  pub def int_of(n Unk0978) Unk0979 := …

  # Pratt.lambda_ahead?/1
  pub def lambda_ahead?(p0 Vec(Unk0965)) Bool := …

  # Pratt.level/1
  pub def level(op Option(Unk0966)) Unk0980 := …

  # Pratt.opinfo/1
  pub def opinfo(op Option(Unk0966)) Unk0981 := …

  # Pratt.parse/1
  pub def parse(ast Sum1) Sum1 := …

  # Pratt.parse_args/1
  pub def parse_args(p0 Vec(Vec(Vec(Vec(Unk0691))))) Unk0976 := …

  # Pratt.parse_arms/2
  pub def parse_arms(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0982)) Unk0983 := …

  # Pratt.parse_block/1
  pub def parse_block(tokens Vec(Vec(Vec(Unk0691)))) Unk0984 := …

  # Pratt.parse_body/1
  pub def parse_body(ast Sum1) Sum1 := …

  # Pratt.parse_capture/1
  pub def parse_capture(p0 Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_case/1
  pub def parse_case(tokens Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_expr/2
  pub def parse_expr(tokens Vec(Vec(Vec(Unk0691))), min_bp Int53) Unk0970 := …

  # Pratt.parse_if/1
  pub def parse_if(tokens Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_lambda/1
  pub def parse_lambda(p0 Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_list/2
  pub def parse_list(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0986)) Unk0985 := …

  # Pratt.parse_map/2
  pub def parse_map(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0987)) Unk0985 := …

  # Pratt.parse_param/1
  pub def parse_param(p0 Vec(Vec(Vec(Unk0691)))) Unk0988 := …

  # Pratt.parse_params/1
  pub def parse_params(p0 Vec(Vec(Vec(Unk0691)))) Unk0989 := …

  # Pratt.parse_pat/1
  pub def parse_pat(p0 Vec(Vec(Vec(Unk0691)))) Unk0990 := …

  # Pratt.parse_pat_args/2
  pub def parse_pat_args(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0991)) Unk0992 := …

  # Pratt.parse_pat_fields/2
  pub def parse_pat_fields(p0 Vec(Vec(Vec(Vec(Unk0691)))), acc Vec(Unk0993)) Unk0994 := …

  # Pratt.parse_pat_list/2
  pub def parse_pat_list(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0995)) Unk0990 := …

  # Pratt.parse_pat_map/2
  pub def parse_pat_map(p0 Vec(Vec(Vec(Vec(Unk0691)))), acc Vec(Unk0996)) Unk0990 := …

  # Pratt.parse_pat_tuple/2
  pub def parse_pat_tuple(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk0997)) Unk0990 := …

  # Pratt.parse_path/1
  pub def parse_path(p0 Vec(Vec(Vec(Unk0691)))) Unk0972 := …

  # Pratt.parse_pats/1
  pub def parse_pats(str Sum1) Vec(Unk0998) := …

  # Pratt.parse_pats/2
  pub def parse_pats(tokens Vec(Vec(Vec(Unk0691))), acc Vec(Unk0998)) Vec(Unk0998) := …

  # Pratt.parse_postfix/2
  pub def parse_postfix(node Unk0999, p1 Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_prefix/1
  pub def parse_prefix(p0 Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_primary/1
  pub def parse_primary(p0 Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_sexpr/1
  pub def parse_sexpr(str Sum1) String := …

  # Pratt.parse_stmt/1
  pub def parse_stmt(p0 Vec(Vec(Vec(Unk0691)))) Unk1000 := …

  # Pratt.parse_stmts/2
  pub def parse_stmts(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk1001)) Unk1002 := …

  # Pratt.parse_tuple/2
  pub def parse_tuple(p0 Vec(Vec(Vec(Unk0691))), acc Vec(Unk1003)) Unk0985 := …

  # Pratt.parse_type/1
  pub def parse_type(p0 Vec(Vec(Vec(Unk0691)))) Unk1004 := …

  # Pratt.parse_type_args/2
  pub def parse_type_args(tokens Vec(Vec(Unk0691)), acc Vec(Unk1005)) Unk1006 := …

  # Pratt.parse_with/1
  pub def parse_with(tokens Vec(Vec(Vec(Unk0691)))) Unk0985 := …

  # Pratt.parse_with_clauses/2
  pub def parse_with_clauses(tokens Vec(Vec(Vec(Unk0691))), acc Vec(Unk1007)) Unk1008 := …

  # Pratt.pascal?/1
  pub def pascal?(s Unk1009) Bool := …

  # Pratt.peek_infix/1
  pub def peek_infix(p0 Vec(Vec(Vec(Unk0691)))) Option(Unk0966) := …

  # Pratt.same_level_root?/2
  pub def same_level_root?(p0 Unk0969, op Option(Unk0966)) Bool := …

  # Pratt.sexpr/1
  pub def sexpr(p0 Sum1) String := …

  # Pratt.sexpr_pat/1
  pub def sexpr_pat(p0 Unk1010) String := …

  # Pratt.sexpr_stmt/1
  pub def sexpr_stmt(p0 Unk1011) String := …

  # Pratt.str_interp/1
  pub def str_interp(parts Vec(Unk1012)) Unk0999 := …

  # Pratt.tok_desc/1
  pub def tok_desc(p0 Unk0977) String := …

  # Prim.names/0
  pub def names() Unk1013 := …

  # Prim.normalize/1
  pub def normalize(p0 Sum1) Sum1 := …

  # Prim.overflow_ops/0
  pub def overflow_ops() Unk1014 := …

  # Protocol.check_assoc!/2
  pub def check_assoc!(protocols Vec(Unk0247), impl_decls Vec(Unk0247)) Unk1015 := …

  # Protocol.check_impl/3
  pub def check_impl(p0 Unk1016, protocols Unk1017, reg Unk1018) Unk1019 := …

  # Protocol.check_no_overlap/3
  pub def check_no_overlap(impls Vec(Unk1020), reg Unk1018, targets Unk1021) Unk1022 := …

  # Protocol.dispatcher/4
  pub def dispatcher(proto Unk1023, sig Unk1024, impls Unk1025, reg Unk1026) Vec(Unk1027) := …

  # Protocol.dispatcher_params/2
  pub def dispatcher_params(sig_params Unk1028, vars Unk1029) Unk1030 := …

  # Protocol.expand/5
  pub def expand(protocols Unk1017, impls Vec(Unk1020), p2 Unk0354, p3 Unk0355, p4 Unk0356) Vec(Unk0357) := …

  # Protocol.guard_for!/3
  pub def guard_for!(type Unk1031, proto Unk1032, reg Unk1018) Unk1033 := …

  # Protocol.impl_methods/2
  pub def impl_methods(p0 Unk1020, protocols Unk1017) Vec(Unk0357) := …

  # Protocol.mangle/3
  pub def mangle(proto Unk1034, type Unk1035, method Unk1036) String := …

  # Protocol.param_type/1
  pub def param_type(p Unk1037) Unk1038 := …

  # Protocol.registry/2
  pub def registry(types Unk1039, structs Unk1040) Unk1018 := …

  # Protocol.runtime_dispatch_target?/1
  pub def runtime_dispatch_target?(p0 Unk1021) Bool := …

  # Protocol.snake/1
  pub def snake(name Unk0063) Unk0063 := …

  # Protocol.split_commas/1
  pub def split_commas(s String) Vec(Unk0081) := …

  # Protocol.struct_guard/1
  pub def struct_guard(tag Unk1041) String := …

  # Protocol.subst_self/2
  pub def subst_self(p0 Unk1042, _type Unk1043) Option(Unk1044) := …

  # Protocol.sum_guard/1
  pub def sum_guard(variants Unk1045) String := …

  # Protocol.tag_disjunction/2
  pub def tag_disjunction(variants Vec(Unk1046), lhs Unk1047) String := …

  # Range.check/3
  pub def check(lo Unk1048, hi Unk1049, a Sum1) Sum1 := …

  # Range.expand_of/2
  pub def expand_of(node Sum1, table Map(Unk0017, Unk0016)) Sum1 := …

  # Range.lit/1
  pub def lit(n Unk1050) Sum1 := …

  # Range.table/1
  pub def table(ranges Vec(Type)) Map(Unk0017, Unk0016) := …

  # Range.walk/2
  pub def walk(node Sum1, table Map(Unk0017, Unk0016)) Sum1 := …

  # Reach.all_emittable?/2
  pub def all_emittable?(f Unk1051, pctx Unk1052) Unk1053 := …

  # Reach.all_funcs/1
  pub def all_funcs(prog Map(Unk0021, Vec(Map(Unk1055, Vec(Unk1054))))) Vec(Map(Unk1055, Vec(Unk1054))) := …

  # Reach.analyze/1
  pub def analyze(prog Map(Unk0021, Vec(Map(Unk1055, Vec(Unk1054))))) Unk1056 := …

  # Reach.atom_prim_blocker/0
  pub def atom_prim_blocker() Unk1057 := …

  # Reach.bare_atom_blocker/0
  pub def bare_atom_blocker() Unk1058 := …

  # Reach.build_default/0
  pub def build_default() Option(Unk1059) := …

  # Reach.builder_tail_ok?/2
  pub def builder_tail_ok?(f Unk1060, generics Unk1061) Bool := …

  # Reach.check_contracts/2
  pub def check_contracts(prog Map(Unk0021, Vec(Map(Unk1055, Vec(Unk1054)))), p1 Option(Unk1059)) Unk1062 := …

  # Reach.classify/3
  pub def classify(p0 Sum1, _modnames Unk1063, p2 Unk1064) Unk1064 := …

  # Reach.collect_ctors/2
  pub def collect_ctors(p0 Sum1, ctors Map(Unk1066, Unk1065)) Vec(Unk1067) := …

  # Reach.conc_erl?/2
  pub def conc_erl?(m String, fun Unk1068) Bool := …

  # Reach.contract_message/1
  pub def contract_message(violations Vec(Unk1069)) String := …

  # Reach.core/2
  pub def core(src Unk1070, parser Fn(Unk1072, Unk1071)) Sum1 := …

  # Reach.ctor_aligned?/2
  pub def ctor_aligned?(p0 Unk1073, f Map(Unk1074, Vec(Unk1075))) Bool := …

  # Reach.deep/1
  pub def deep(t Vec(Unk1076)) Vec(Unk1077) := …

  # Reach.emittable_parametric?/1
  pub def emittable_parametric?(t Unk1078) Unk1079 := …

  # Reach.ffi/2
  pub def ffi(construct Unk1080, conc? Unk1081) Unk1082 := …

  # Reach.find_atom_ordering/1
  pub def find_atom_ordering(p0 Vec(Unk1076)) Vec(Unk1077) := …

  # Reach.fixpoint/2
  pub def fixpoint(facts Unk1083, table Unk1084) Unk1084 := …

  # Reach.fn_type_blocker/0
  pub def fn_type_blocker() Unk1085 := …

  # Reach.func_symbol_violations/1
  pub def func_symbol_violations(f Unk1086) Vec(Unk1077) := …

  # Reach.gate!/1
  pub def gate!(prog Map(Unk0021, Vec(Type))) Unk1087 := …

  # Reach.gate!/2
  pub def gate!(prog Map(Unk0021, Vec(Type)), default Option(Unk1059)) Unk1087 := …

  # Reach.int_blocker/0
  pub def int_blocker() Unk1088 := …

  # Reach.js_wide_int?/1
  pub def js_wide_int?(t Unk1089) Bool := …

  # Reach.mix_default/0
  pub def mix_default() Unk1090 := …

  # Reach.parametric_blocker/0
  pub def parametric_blocker() Unk1091 := …

  # Reach.parametric_constructions/2
  pub def parametric_constructions(f Unk1092, ctors Map(Unk1066, Unk1065)) Vec(Unk1067) := …

  # Reach.parametric_ctx/2
  pub def parametric_ctx(prog Map(Unk0021, Vec(Map(Unk1055, Vec(Unk1054)))), funs Vec(Map(Unk1055, Vec(Unk1054)))) Unk1093 := …

  # Reach.parametric_rs_ok?/2
  pub def parametric_rs_ok?(f Map(Unk1095, Vec(Unk1094)), pctx Unk1093) Bool := …

  # Reach.parametric_type?/1
  pub def parametric_type?(t Unk1096) Bool := …

  # Reach.pascal?/1
  pub def pascal?(s Unk1097) Unk1098 := …

  # Reach.ref_blocker/0
  pub def ref_blocker() Unk1099 := …

  # Reach.result_value_blocker/0
  pub def result_value_blocker() Unk1100 := …

  # Reach.scan/3
  pub def scan(p0 Sum1, modnames Unk1063, p2 Unk1064) Unk1064 := …

  # Reach.scan_func/3
  pub def scan_func(f Map(Unk1095, Vec(Unk1094)), modnames Unk1063, pctx Unk1093) Unk1064 := …

  # Reach.sig_idents/1
  pub def sig_idents(f Map(Unk1101, Vec(Unk1102))) Unk1103 := …

  # Reach.sig_uses_fn_type?/1
  pub def sig_uses_fn_type?(f Map(Unk1095, Vec(Unk1094))) Bool := …

  # Reach.symbol_lint!/1
  pub def symbol_lint!(prog Map(Unk0021, Vec(Map(Unk1055, Vec(Unk1054))))) Unk1104 := …

  # Reach.tail_calls_generic?/2
  pub def tail_calls_generic?(p0 Unk1105, generics Unk1061) Bool := …

  # Reach.targets/0
  pub def targets() Unk1106 := …

  # Reach.tvar?/1
  pub def tvar?(t Unk1107) Unk1108 := …

  # Reach.type_has_tvar?/1
  pub def type_has_tvar?(t Unk1109) Bool := …

  # Reach.type_idents/1
  pub def type_idents(t Unk1109) Vec(Unk1110) := …

  # Reach.uses_parametric?/2
  pub def uses_parametric?(f Unk1111, names Unk1112) Unk1113 := …

  # Reach.validate_default/1
  pub def validate_default(p0 Option(Unk1059)) Option(Unk1059) := …

  # Reach.wide_prim_blocker/0
  pub def wide_prim_blocker() Unk1114 := …

  # Reach.width_blocker/0
  pub def width_blocker() Unk1115 := …

  # Repl.accumulate_line/2
  pub def accumulate_line(line String, p1 Unk1116) Unk1117 := …

  # Repl.balanced?/1
  pub def balanced?(input Unk1118) Bool := …

  # Repl.bind_env/2
  pub def bind_env(binds Vec(Unk1119), ic Map(Unk0083, Map(String, String))) Map(Unk0090, String) := …

  # Repl.bind_with_type/4
  pub def bind_with_type(s Session, input String, name String, type Option(Unk1120)) Unk1121 := …

  # Repl.candidate_pool/2
  pub def candidate_pool(p0 Unk1122, _s Session) Vec(Unk1123) := …

  # Repl.common_prefix/2
  pub def common_prefix(a Unk1124, b Unk1125) String := …

  # Repl.common_prefix/3
  pub def common_prefix(p0 Unk1124, p1 Unk1125, acc String) String := …

  # Repl.complete/2
  pub def complete(before_cursor Unk1126, p1 Unk1127) Unk1128 := …

  # Repl.continuation/2
  pub def continuation(_word Unk1129, p1 Vec(Unk1130)) String := …

  # Repl.decl_names/1
  pub def decl_names(input String) Unk1131 := …

  # Repl.declaration?/1
  pub def declaration?(input Unk1118) Bool := …

  # Repl.describe/1
  pub def describe(p0 Unk1132) Unk1133 := …

  # Repl.eval/2
  pub def eval(p0 Unk1134, input Unk1135) Unk1136 := …

  # Repl.eval_bind/4
  pub def eval_bind(s Session, input String, name String, rhs Sum1) Unk1121 := …

  # Repl.eval_decl/2
  pub def eval_decl(s Session, input String) Unk1137 := …

  # Repl.eval_expr/2
  pub def eval_expr(s Session, input String) Unk1121 := …

  # Repl.eval_stmt/2
  pub def eval_stmt(s Session, input String) Unk1121 := …

  # Repl.flush_entries/1
  pub def flush_entries(p0 Unk1138) Vec(Unk1139) := …

  # Repl.infer_or_unknown/3
  pub def infer_or_unknown(ast Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk1120) := …

  # Repl.info/1
  pub def info(p0 Session) Unk1140 := …

  # Repl.longest_common_prefix/1
  pub def longest_common_prefix(p0 Vec(Unk1141)) Unk1141 := …

  # Repl.module_name/1
  pub def module_name(p0 Session) Unk0008 := …

  # Repl.program/3
  pub def program(units Vec(Unk1142), binds Vec(Unk1143), expr_src String) String := …

  # Repl.reload/2
  pub def reload(s Session, src String) Unk0008 := …

  # Repl.render/1
  pub def render(p0 Unk1144) String := …

  # Repl.run/4
  pub def run(s Session, binds Vec(Unk1143), units Vec(Unk1142), expr_src String) Unk1145 := …

  # Repl.safe_decl/1
  pub def safe_decl(units Vec(Unk1142)) Map(Unk0021, Vec(Type)) := …

  # Repl.safe_infer/3
  pub def safe_infer(ast Sum1, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk1120) := …

  # Repl.safe_infer_input/3
  pub def safe_infer_input(input String, env Map(Unk0090, String), ic Map(Unk0083, Map(String, String))) Option(Unk1120) := …

  # Repl.safe_parse_body/1
  pub def safe_parse_body(input String) Unk1146 := …

  # Repl.scan_count/2
  pub def scan_count(input Unk1118, regex Unk1147) Unk1148 := …

  # Repl.session_ic/1
  pub def session_ic(p0 Session) Map(Unk0083, Map(String, String)) := …

  # Repl.split_entries/1
  pub def split_entries(source Unk1149) Unk1150 := …

  # Repl.submit_or_continue/2
  pub def submit_or_continue(entries Unk1151, buffer String) Unk1117 := …

  # Repl.trailing_token/1
  pub def trailing_token(text Unk1126) String := …

  # Repl.type_of/2
  pub def type_of(p0 Unk1152, input String) Option(Unk1120) := …

  # Repl.units_src/1
  pub def units_src(units Vec(Unk1142)) String := …

  # Repl.vocabulary/0
  pub def vocabulary() Vec(Unk1153) := …

  # SelfHost.badge/1
  pub def badge(p0 Unk1154) String := …

  # SelfHost.composition/0
  pub def composition() Unk1155 := …

  # SelfHost.count/1
  pub def count(status Unk1156) Int53 := …

  # SelfHost.evidence/1
  pub def evidence(p0 Unk1157) String := …

  # SelfHost.evidence_files/0
  pub def evidence_files() Unk1158 := …

  # SelfHost.external_host_calls/1
  pub def external_host_calls(prog Map(Unk1161, Vec(Map(Unk1160, Vec(Unk1159))))) Vec(Unk1162) := …

  # SelfHost.ffi_in_file/1
  pub def ffi_in_file(path Unk1163) Unk1164 := …

  # SelfHost.ffi_ledger/0
  pub def ffi_ledger() Unk1165 := …

  # SelfHost.passes/0
  pub def passes() Unk1166 := …

  # SelfHost.percent/0
  pub def percent() Unk1167 := …

  # SelfHost.selfhost_files/0
  pub def selfhost_files() Unk1168 := …

  # SelfHost.selfhost_module_names/0
  pub def selfhost_module_names() Unk1169 := …

  # SelfHost.sibling_compose_call?/2
  pub def sibling_compose_call?(construct Unk1170, siblings Unk1171) Bool := …

  # SelfHost.stages/0
  pub def stages() Unk1172 := …

  # SelfHost.status_markdown/1
  pub def status_markdown(stages Vec(Unk1173)) String := …

  # Shadow.ded_bind/5
  pub def ded_bind(n Unk1174, t Bool, e Vec(Unk1175), p3 Unk1176, fresh Fn(Unk1177, Unk1178, Unk1179)) Unk1180 := …

  # Shadow.ded_block/4
  pub def ded_block(stmts Vec(Unk1181), r Unk1182, ver Unk1183, fresh Fn(Unk1177, Unk1178, Unk1179)) Vec(Unk0598) := …

  # Shadow.ded_expr/3
  pub def ded_expr(p0 Vec(Unk1175), r Unk1184, _fresh Fn(Unk1177, Unk1178, Unk1179)) Vec(Unk1175) := …

  # Shadow.dedup/3
  pub def dedup(stmts Vec(Unk1181), params Vec(Unk0601), fresh Fn(Unk1177, Unk1178, Unk1179)) Vec(Unk0598) := …

  # Shadow.pat_var_names/1
  pub def pat_var_names(p0 Sum2) Vec(Unk1185) := …

  # Test.compile!/2
  pub def compile!(src String, mod Unk0008) Unk0008 := …

  # Test.default_mod/1
  pub def default_mod(src String) Unk1186 := …

  # Test.run/2
  pub def run(src String, p1 Unk1187) Unk1188 := …

  # Test.run_one/2
  pub def run_one(mod Unk1189, name Unk1190) Unk1191 := …

  # Test.rust/1
  pub def rust(src String) Unk1192 := …

  # Test.tests/1
  pub def tests(src String) Vec(Unk1193) := …

  # Tour.build_cell/1
  pub def build_cell(p0 Unk1194) Unk1195 := …

  # Tour.build_reach_example/1
  pub def build_reach_example(p0 Unk1196) Unk1197 := …

  # Tour.elixir_module/1
  pub def elixir_module(src String) Unk1198 := …

  # Tour.encode/2
  pub def encode(map Vec(Unk1199), indent Int53) String := …

  # Tour.encode_string/1
  pub def encode_string(s Vec(Unk1199)) String := …

  # Tour.generate/0
  pub def generate() Unk1200 := …

  # Tour.reach_map/1
  pub def reach_map(prog Map(Unk0021, Vec(Type))) Unk1201 := …

  # Tour.to_json/0
  pub def to_json() Unk1202 := …

  # Transpile.add_clause/2
  pub def add_clause(open Unk1203, clause Unk1204) Unk1205 := …

  # Transpile.block_stmts/1
  pub def block_stmts(p0 Unk1206) Vec(Unk1206) := …

  # Transpile.build_clause/2
  pub def build_clause(head Unk1207, kw Unk1208) Unk1209 := …

  # Transpile.case_arm/1
  pub def case_arm(p0 Unk1210) String := …

  # Transpile.classify/1
  pub def classify(p0 Unk1211) Unk1212 := …

  # Transpile.close_group/2
  pub def close_group(acc Vec(Unk1213), p1 Unk1213) Vec(Unk1213) := …

  # Transpile.def_groups/1
  pub def def_groups(stmts Vec(Unk1211)) Vec(Unk1213) := …

  # Transpile.escape/1
  pub def escape(s Unk1214) Unk1215 := …

  # Transpile.escape_lit/1
  pub def escape_lit(s Unk1216) Unk1217 := …

  # Transpile.flush/2
  pub def flush(p0 Unk1218, _sigmap Map(Unk1219, Bool)) Vec(String) := …

  # Transpile.hole_sig?/1
  pub def hole_sig?(p0 Unk1220) Bool := …

  # Transpile.infer_program/1
  pub def infer_program(ast Unk1221) Unk1222 := …

  # Transpile.infer_report/1
  pub def infer_report(source Unk1223) Unk1224 := …

  # Transpile.infer_sigs/1
  pub def infer_sigs(p0 Unk1221) Unk1225 := …

  # Transpile.inferred/1
  pub def inferred(source Unk0947) Unk1222 := …

  # Transpile.max_placeholder/1
  pub def max_placeholder(p0 Vec(Unk1226)) Int53 := …

  # Transpile.mod_str/1
  pub def mod_str(p0 Unk1227) String := …

  # Transpile.module_groups/1
  pub def module_groups(src Unk1228) Option(Unk1229) := …

  # Transpile.moduledoc_lines/1
  pub def moduledoc_lines(text Unk1230) Vec(String) := …

  # Transpile.name_str/1
  pub def name_str(n Unk1231) Unk1232 := …

  # Transpile.new_group/3
  pub def new_group(vis Unk1233, clause Unk1234, doc Unk1235) Unk1236 := …

  # Transpile.one_line/1
  pub def one_line(s Unk1237) Unk1238 := …

  # Transpile.prime_xmod/1
  pub def prime_xmod(sources Unk1239) Unk1240 := …

  # Transpile.rank/1
  pub def rank(entries Unk1241) Unk1242 := …

  # Transpile.render_clause/2
  pub def render_clause(kw String, c Unk1243) String := …

  # Transpile.render_items/2
  pub def render_items(stmts Vec(Unk1211), sigmap Map(Unk1219, Bool)) Vec(String) := …

  # Transpile.same_group?/3
  pub def same_group?(open Unk1244, vis Unk1245, clause Unk1209) Bool := …

  # Transpile.short_name/1
  pub def short_name(p0 Unk1227) String := …

  # Transpile.sibling_module?/2
  pub def sibling_module?(p0 Unk1246, m Unk1247) Bool := …

  # Transpile.simple?/1
  pub def simple?(p0 Vec(Unk1248)) Bool := …

  # Transpile.snippet/1
  pub def snippet(node Unk1227) String := …

  # Transpile.stdlib_map/0
  pub def stdlib_map() Unk1249 := …

  # Transpile.string_part/1
  pub def string_part(s Unk1250) Unk1251 := …

  # Transpile.string_parts/1
  pub def string_parts(segments Unk1252) Unk1253 := …

  # Transpile.subst_ph/2
  pub def subst_ph(p0 Vec(Unk1254), ps Unk1255) Vec(Unk1254) := …

  # Transpile.toplevel/3
  pub def toplevel(p0 Unk1256, sigmap Unk1257, types Vec(String)) Vec(String) := …

  # Transpile.transpile/2
  pub def transpile(source Unk1258, p1 Unk1259) Unk1260 := …

  # Transpile.transpile_with_stats/2
  pub def transpile_with_stats(source Unk1258, p1 Unk1261) Unk1262 := …

  # Transpile.underscore_var/1
  pub def underscore_var(name Unk1263) String := …

  # Transpile.var?/1
  pub def var?(p0 Unk1264) Bool := …

  # Transpile.var_name/1
  pub def var_name(p0 Unk1227) String := …

  # TypeStr.split_top_commas/1
  pub def split_top_commas(p0 String) Vec(Unk0081) := …
```

### Placeholder index (replace once → applies to all sites)

| placeholder | sites | references |
|---|---|---|
| `Unk0001` | 1 | `Application.maybe_register_smart_cell/0:ret` |
| `Unk0002` | 1 | `Application.start/2:p0` |
| `Unk0003` | 1 | `Application.start/2:p1` |
| `Unk0004` | 1 | `Application.start/2:ret` |
| `Unk0005` | 2 | `Beam.any_t/0:ret`, `Beam.type_form/2:ret` |
| `Unk0006` | 1 | `Beam.arity/1:p0` |
| `Unk0007` | 1 | `Beam.arity/1:ret` |
| `Unk0008` | 11 | `Beam.beam_for/5:p0`, `Beam.compile/2:p1`, `Beam.compile_ir/2:p1`, `Beam.load/2:p1`, `Beam.load_ir/2:p1`, `Fixpoint.load_lexer/2:p1`, `Fixpoint.load_lexer/2:ret`, `Repl.module_name/1:ret`, `Repl.reload/2:ret`, `Test.compile!/2:p1`, `Test.compile!/2:ret` |
| `Unk0009` | 2 | `Beam.beam_for/5:p1`, `Beam.funcs_of/1:ret` |
| `Unk0010` | 3 | `Beam.beam_for/5:ret`, `Beam.compile/2:ret`, `Beam.compile_ir/2:ret` |
| `Unk0011` | 2 | `Beam.beam_func/1:p0`, `Beam.beam_func/1:ret` |
| `Unk0012` | 20 | `Beam.bin_seg/1:p0`, `Beam.block_forms/2:ret`, `Beam.body_forms/3:ret`, `Beam.body_seq/2:ret`, `Beam.cons/3:p1`, `Beam.cons/3:p2`, `Beam.cons/3:ret`, `Beam.core_list_tail/1:p0`, `Beam.core_list_tail/1:ret`, `Beam.else_dispatch/3:ret`, `Beam.expr_form/2:ret`, `Beam.fun_ref/3:ret`, `Beam.guard_form/2:ret`, `Beam.i64_overflow/4:ret`, `Beam.num_form/1:ret`, `Beam.pat_form/1:ret`, `Beam.remote_call/4:ret`, `Beam.str_form/1:ret`, `Beam.var_form/1:ret`, `Beam.with_form/5:ret` |
| `Unk0013` | 1 | `Beam.bin_seg/1:ret` |
| `Unk0014` | 15 | `Beam.bind_var/2:p1`, `Beam.block_forms/2:p1`, `Beam.body_forms/3:p1`, `Beam.body_seq/2:p1`, `Beam.bump_var/1:p0`, `Beam.else_dispatch/3:p2`, `Beam.expr_form/2:p1`, `Beam.guard_form/2:p1`, `Beam.i64_overflow/4:p3`, `Beam.pat_vars/2:p1`, `Beam.pat_vars/2:ret`, `Beam.remote_call/4:p3`, `Beam.stmt_form/2:p1`, `Beam.var_atom/1:ret`, `Beam.with_form/5:p3` |
| `Unk0015` | 1 | `Beam.bind_var/2:ret` |
| `Unk0016` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0017` | 6 | `Beam.body_forms/3:p2`, `Beam.clause_form/2:p1`, `Beam.function_form/2:p1`, `Range.expand_of/2:p1`, `Range.table/1:ret`, `Range.walk/2:p1` |
| `Unk0018` | 1 | `Beam.bump_var/1:ret` |
| `Unk0019` | 1 | `Beam.clause_form/2:p0` |
| `Unk0020` | 1 | `Beam.clause_form/2:ret` |
| `Unk0021` | 21 | `Beam.compile_ir/2:p0`, `Beam.compile_program_ir/1:p0`, `Beam.load_ir/2:p0`, `Check.check_program/1:p0`, `Check.gate!/1:p0`, `Check.program_ic/1:p0`, `Decl.parse/1:ret`, `Decl.proto_method_traits/1:p0`, `Decl.protocol_unit/3:p0`, `Doctest.module_doc_strings/1:p0`, `Lower.rust_program/1:p0`, `Opaque.erase/1:p0`, `Reach.all_funcs/1:p0`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.gate!/1:p0`, `Reach.gate!/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.symbol_lint!/1:p0`, `Repl.safe_decl/1:ret`, `Tour.reach_map/1:p0` |
| `Unk0022` | 1 | `Beam.compile_program/1:ret` |
| `Unk0023` | 1 | `Beam.compile_program_ir/1:ret` |
| `Unk0024` | 1 | `Beam.cons/3:p0` |
| `Unk0025` | 2 | `Beam.else_dispatch/3:p0`, `Beam.with_form/5:p2` |
| `Unk0026` | 1 | `Beam.erl_op/1:ret` |
| `Unk0027` | 1 | `Beam.fn_form/2:p0` |
| `Unk0028` | 7 | `Beam.fn_form/2:p1`, `Beam.spec_form/2:p1`, `Beam.struct_form/2:p1`, `Beam.sum_form/2:p1`, `Beam.type_attrs/3:p2`, `Beam.type_ctx/3:ret`, `Beam.type_form/2:p1` |
| `Unk0029` | 1 | `Beam.fn_form/2:ret` |
| `Unk0030` | 1 | `Beam.fun_ref/3:p0` |
| `Unk0031` | 1 | `Beam.fun_ref/3:p1` |
| `Unk0032` | 1 | `Beam.fun_ref/3:p2` |
| `Unk0033` | 11 | `Beam.funcs_of/1:p0`, `Beam.load_aux_mods/1:p0`, `Beam.ranges_of/1:p0`, `Beam.structs_of/1:p0`, `Beam.types_of/1:p0`, `JS.program_number_mode?/1:p0`, `JS.protocol_dispatchers_js/1:p0`, `JS.reject_mixed_int_mode!/1:p0`, `JVM.all_types/1:p0`, `Opaque.do_erase/2:ret`, `Opaque.erase/1:ret` |
| `Unk0034` | 2 | `Beam.function_form/2:p0`, `Beam.spec_form/2:p0` |
| `Unk0035` | 3 | `Beam.function_form/2:ret`, `Beam.spec_form/2:ret`, `Beam.type_attrs/3:ret` |
| `Unk0036` | 1 | `Beam.i64_overflow/4:p0` |
| `Unk0037` | 1 | `Beam.i64_project/2:p0` |
| `Unk0038` | 1 | `Beam.i64_project/2:p1` |
| `Unk0039` | 1 | `Beam.i64_project/2:ret` |
| `Unk0040` | 1 | `Beam.inner_of/1:p0` |
| `Unk0041` | 1 | `Beam.inner_of/1:ret` |
| `Unk0042` | 1 | `Beam.int_t/0:ret` |
| `Unk0043` | 1 | `Beam.load/2:ret` |
| `Unk0044` | 1 | `Beam.load_aux_mods/1:ret` |
| `Unk0045` | 1 | `Beam.load_ir/2:ret` |
| `Unk0046` | 1 | `Beam.load_program/1:p0` |
| `Unk0047` | 1 | `Beam.load_program/1:ret` |
| `Unk0048` | 1 | `Beam.load_program_ir/1:p0` |
| `Unk0049` | 1 | `Beam.load_program_ir/1:ret` |
| `Unk0050` | 1 | `Beam.map_field_pat/1:p0` |
| `Unk0051` | 1 | `Beam.map_field_pat/1:ret` |
| `Unk0052` | 1 | `Beam.num_form/1:p0` |
| `Unk0053` | 1 | `Beam.pascal?/1:p0` |
| `Unk0054` | 1 | `Beam.remote_call/4:p0` |
| `Unk0055` | 2 | `Beam.split_top/2:p0`, `Beam.top_level_union?/1:p0` |
| `Unk0056` | 1 | `Beam.split_top/2:ret` |
| `Unk0057` | 1 | `Beam.stmt_form/2:p0` |
| `Unk0058` | 1 | `Beam.stmt_form/2:ret` |
| `Unk0059` | 1 | `Beam.str_form/1:p0` |
| `Unk0060` | 3 | `Beam.struct_form/2:ret`, `Beam.union_t/1:p0`, `Beam.union_t/1:ret` |
| `Unk0061` | 1 | `Beam.sum_form/2:p0` |
| `Unk0062` | 1 | `Beam.sum_form/2:ret` |
| `Unk0063` | 9 | `Beam.tag/1:p0`, `Beam.tag/1:ret`, `Exhaustiveness.add_type/3:p1`, `PatternLower.add_struct/3:p1`, `PatternLower.add_struct/3:p2`, `PatternLower.to_snake/1:p0`, `PatternLower.to_snake/1:ret`, `Protocol.snake/1:p0`, `Protocol.snake/1:ret` |
| `Unk0064` | 1 | `Beam.type_form/2:p0` |
| `Unk0065` | 1 | `Beam.with_form/5:p0` |
| `Unk0066` | 1 | `Capability.beam_legal!/1:p0` |
| `Unk0067` | 1 | `Capability.beam_legal!/1:ret` |
| `Unk0068` | 1 | `Capability.count_block/3:p0` |
| `Unk0069` | 2 | `Capability.count_block/3:p1`, `Capability.count_uses/2:p1` |
| `Unk0070` | 11 | `Capability.count_block/3:p2`, `Capability.count_block/3:ret`, `Capability.count_uses/1:ret`, `Capability.count_uses/2:ret`, `Capability.max_merge/2:p0`, `Capability.max_merge/2:p1`, `Capability.max_merge/2:ret`, `Capability.merge/2:p0`, `Capability.merge/2:p1`, `Capability.merge/2:ret`, `Capability.verdict/2:p1` |
| `Unk0071` | 4 | `Capability.count_uses/1:p0`, `Capability.count_uses/2:p0`, `Capability.lin_check/2:p1`, `Capability.lin_check_block/3:p2` |
| `Unk0072` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0073` | 2 | `Capability.lin_check/2:p0`, `Capability.verdict/2:p0` |
| `Unk0074` | 3 | `Capability.lin_check/2:ret`, `Capability.lin_check_block/3:ret`, `Capability.verdict/2:ret` |
| `Unk0075` | 1 | `Capability.lin_check_block/3:p0` |
| `Unk0076` | 1 | `Capability.lin_check_block/3:p1` |
| `Unk0077` | 1 | `Capability.parametric/1:ret` |
| `Unk0078` | 1 | `Capability.pat_vars/1:p0` |
| `Unk0079` | 1 | `Capability.pat_vars/1:ret` |
| `Unk0080` | 1 | `Capability.rust_param/2:p0` |
| `Unk0081` | 8 | `Capability.split_top_level/1:ret`, `Check.split_top_commas/1:ret`, `JS.split_top_commas/1:ret`, `Lower.name_type/1:p0`, `Lower.pcommas/1:ret`, `Lower.sig_param/2:p0`, `Protocol.split_commas/1:ret`, `TypeStr.split_top_commas/1:ret` |
| `Unk0082` | 1 | `Check.abstract_cast_ret/3:p1` |
| `Unk0083` | 36 | `Check.abstract_cast_ret/3:p2`, `Check.ann_each/3:p2`, `Check.ann_stmts/3:p2`, `Check.annotate/3:p2`, `Check.bind_mismatch/5:p4`, `Check.call_bound_error/5:p3`, `Check.called_ret/2:p0`, `Check.called_ret_with/4:p0`, `Check.check_bind_stmts/3:p2`, `Check.check_binds/2:p1`, `Check.check_bounds/2:p1`, `Check.check_func/3:p1`, `Check.check_numeric_mix/2:p1`, `Check.check_return/2:p1`, `Check.clause_env/3:p2`, `Check.ctor_type/2:p0`, `Check.first_bound_violation/4:p3`, `Check.infer/3:p2`, `Check.infer_block/4:p2`, `Check.infer_tail/3:p2`, `Check.narrow/4:p2`, `Check.num_mix_error/5:p4`, `Check.program_ic/1:ret`, `Check.range_bind/6:p5`, `Check.resolve_range/2:p1`, `Check.scan_bound_calls/4:p2`, `Check.scan_num_mix/3:p2`, `Check.scan_num_mix_children/3:p2`, `Check.walk_children/4:p2`, `Interp.resolve/4:p2`, `Interp.resolve_part/4:p2`, `Repl.bind_env/2:p1`, `Repl.infer_or_unknown/3:p2`, `Repl.safe_infer/3:p2`, `Repl.safe_infer_input/3:p2`, `Repl.session_ic/1:ret` |
| `Unk0084` | 2 | `Check.abstract_cast_ret/3:ret`, `Check.fn_ret/1:ret` |
| `Unk0085` | 1 | `Check.abstract_op_type/4:p0` |
| `Unk0086` | 1 | `Check.abstract_op_type/4:p3` |
| `Unk0087` | 1 | `Check.abstract_op_type/4:ret` |
| `Unk0088` | 6 | `Check.adoptable_int?/1:p0`, `Check.body_literal_adopts?/2:p1`, `Check.float_type?/1:p0`, `Check.int_type?/1:p0`, `Check.lit_expr_adopts?/2:p1`, `Check.literal_adopts?/2:p1` |
| `Unk0089` | 1 | `Check.all_types/1:p0` |
| `Unk0090` | 28 | `Check.ann_each/3:p1`, `Check.ann_stmts/3:p1`, `Check.annotate/3:p1`, `Check.bind_mismatch/5:p3`, `Check.call_bound_error/5:p2`, `Check.called_ret_with/4:p3`, `Check.check_bind_stmts/3:p1`, `Check.clause_env/3:ret`, `Check.infer/3:p1`, `Check.infer_block/4:p1`, `Check.infer_tail/3:p1`, `Check.narrow/4:p3`, `Check.narrow/4:ret`, `Check.num_mix_error/5:p3`, `Check.range_bind/6:p4`, `Check.scan_bound_calls/4:p1`, `Check.scan_num_mix/3:p1`, `Check.scan_num_mix_children/3:p1`, `Check.walk_children/4:p1`, `Decl.clause_env/2:ret`, `Interp.resolve/4:p1`, `Interp.resolve_part/4:p1`, `Opaque.strip/3:p2`, `Opaque.strip_into/3:p2`, `Repl.bind_env/2:ret`, `Repl.infer_or_unknown/3:p1`, `Repl.safe_infer/3:p1`, `Repl.safe_infer_input/3:p1` |
| `Unk0091` | 1 | `Check.ann_stmts/3:p0` |
| `Unk0092` | 1 | `Check.ann_stmts/3:ret` |
| `Unk0093` | 1 | `Check.arith_type/4:p0` |
| `Unk0094` | 1 | `Check.arith_type/4:p1` |
| `Unk0095` | 1 | `Check.arith_type/4:p2` |
| `Unk0096` | 1 | `Check.arith_type/4:p3` |
| `Unk0097` | 1 | `Check.arith_type/4:ret` |
| `Unk0098` | 1 | `Check.bind_mismatch/5:p0` |
| `Unk0099` | 1 | `Check.bind_mismatch/5:p1` |
| `Unk0100` | 2 | `Check.bind_mismatch/5:ret`, `Check.check_bind_stmts/3:ret` |
| `Unk0101` | 1 | `Check.bind_tvar/4:p0` |
| `Unk0102` | 1 | `Check.bind_tvar/4:p1` |
| `Unk0103` | 1 | `Check.bind_tvar/4:p2` |
| `Unk0104` | 3 | `Check.bind_tvar/4:p3`, `Check.bind_tvar/4:ret`, `Check.first_bound_violation/4:p2` |
| `Unk0105` | 1 | `Check.body_literal_adopts?/2:p0` |
| `Unk0106` | 1 | `Check.branch_join/1:p0` |
| `Unk0107` | 1 | `Check.build_fn/2:p0` |
| `Unk0108` | 2 | `Check.call_bound_error/5:ret`, `Check.first_bound_violation/4:ret` |
| `Unk0109` | 1 | `Check.call_name/1:p0` |
| `Unk0110` | 2 | `Check.call_name/1:ret`, `Check.with_callees/1:ret` |
| `Unk0111` | 1 | `Check.check/1:p0` |
| `Unk0112` | 1 | `Check.check/1:ret` |
| `Unk0113` | 1 | `Check.check_bind_stmts/3:p0` |
| `Unk0114` | 1 | `Check.check_binds/2:ret` |
| `Unk0115` | 1 | `Check.check_bounds/2:ret` |
| `Unk0116` | 1 | `Check.check_error_set/2:p0` |
| `Unk0117` | 1 | `Check.check_error_set/2:p1` |
| `Unk0118` | 1 | `Check.check_error_set/2:ret` |
| `Unk0119` | 1 | `Check.check_external_caps/1:ret` |
| `Unk0120` | 1 | `Check.check_func/3:p0` |
| `Unk0121` | 1 | `Check.check_func/3:p2` |
| `Unk0122` | 1 | `Check.check_func/3:ret` |
| `Unk0123` | 1 | `Check.check_labels/1:ret` |
| `Unk0124` | 1 | `Check.check_numeric_mix/2:ret` |
| `Unk0125` | 1 | `Check.check_program/1:ret` |
| `Unk0126` | 1 | `Check.check_return/2:ret` |
| `Unk0127` | 1 | `Check.clause_env/3:p0` |
| `Unk0128` | 1 | `Check.clause_env/3:p1` |
| `Unk0129` | 1 | `Check.comp_str/1:p0` |
| `Unk0130` | 1 | `Check.comp_unify/2:p0` |
| `Unk0131` | 2 | `Check.comp_unify/2:p1`, `Check.comp_unify/2:ret` |
| `Unk0132` | 3 | `Check.conservative/1:p0`, `Check.conservative/1:ret`, `Check.list_of/1:p0` |
| `Unk0133` | 4 | `Check.const_int/1:p0`, `Check.list_elems/1:p0`, `Check.lit_range_error/3:p0`, `Check.oor_scan/5:p0` |
| `Unk0134` | 1 | `Check.const_int/1:ret` |
| `Unk0135` | 1 | `Check.ctor_types/2:p0` |
| `Unk0136` | 1 | `Check.ctor_types/2:p1` |
| `Unk0137` | 1 | `Check.ctor_types/2:p1` |
| `Unk0138` | 1 | `Check.ctor_types/2:ret` |
| `Unk0139` | 1 | `Check.ctor_types/2:ret` |
| `Unk0140` | 2 | `Check.debottom/1:p0`, `Check.debottom/1:ret` |
| `Unk0141` | 1 | `Check.declared_set/2:p0` |
| `Unk0142` | 2 | `Check.declared_set/2:p1`, `Check.solve_error_sets/2:p1` |
| `Unk0143` | 1 | `Check.declared_set/2:ret` |
| `Unk0144` | 2 | `Check.direct_tags/1:p0`, `Check.produced_set/2:p0` |
| `Unk0145` | 1 | `Check.direct_tags/1:ret` |
| `Unk0146` | 1 | `Check.error_sets/1:ret` |
| `Unk0147` | 1 | `Check.error_tags/1:p0` |
| `Unk0148` | 2 | `Check.error_tags/1:ret`, `Check.tag_name/1:ret` |
| `Unk0149` | 1 | `Check.fbound_table/1:p0` |
| `Unk0150` | 1 | `Check.fbound_table/1:ret` |
| `Unk0151` | 1 | `Check.first_bound_violation/4:p1` |
| `Unk0152` | 1 | `Check.fixpoint/2:p0` |
| `Unk0153` | 3 | `Check.fixpoint/2:p1`, `Check.fixpoint/2:ret`, `Check.solve_error_sets/2:ret` |
| `Unk0154` | 3 | `Check.fn_parts/1:p0`, `Check.unify_fn/2:p0`, `Check.unify_fn/2:p1` |
| `Unk0155` | 1 | `Check.fn_parts/1:ret` |
| `Unk0156` | 1 | `Check.fsig/1:p0` |
| `Unk0157` | 1 | `Check.fsig/1:ret` |
| `Unk0158` | 1 | `Check.gate!/1:ret` |
| `Unk0159` | 1 | `Check.generic_ret?/2:p0` |
| `Unk0160` | 1 | `Check.generic_ret?/2:p1` |
| `Unk0161` | 1 | `Check.impl_table/1:p0` |
| `Unk0162` | 1 | `Check.impl_table/1:p0` |
| `Unk0163` | 1 | `Check.impl_table/1:ret` |
| `Unk0164` | 1 | `Check.infer_block/4:p0` |
| `Unk0165` | 1 | `Check.inner_of/1:p0` |
| `Unk0166` | 1 | `Check.inner_of/1:ret` |
| `Unk0167` | 1 | `Check.instantiate_ret/2:p0` |
| `Unk0168` | 1 | `Check.int_literal?/1:p0` |
| `Unk0169` | 1 | `Check.join_all/1:p0` |
| `Unk0170` | 1 | `Check.join_all/1:ret` |
| `Unk0171` | 1 | `Check.kind_prefix/1:p0` |
| `Unk0172` | 2 | `Check.label_error/1:ret`, `Check.label_error_children/1:ret` |
| `Unk0173` | 1 | `Check.list_elem/1:p0` |
| `Unk0174` | 1 | `Check.list_elem/1:ret` |
| `Unk0175` | 1 | `Check.list_elems/1:ret` |
| `Unk0176` | 2 | `Check.lit_range_error/3:p2`, `Check.oor_scan/5:p4` |
| `Unk0177` | 2 | `Check.lit_range_error/3:ret`, `Check.oor_scan/5:ret` |
| `Unk0178` | 1 | `Check.literal_ordinal/2:ret` |
| `Unk0179` | 1 | `Check.missing_impl/5:p1` |
| `Unk0180` | 1 | `Check.missing_impl/5:p3` |
| `Unk0181` | 1 | `Check.missing_impl/5:ret` |
| `Unk0182` | 1 | `Check.num_bits/2:p0` |
| `Unk0183` | 1 | `Check.num_bits/2:p1` |
| `Unk0184` | 2 | `Check.num_bits/2:ret`, `Check.num_kind/1:ret` |
| `Unk0185` | 1 | `Check.num_join/2:p0` |
| `Unk0186` | 1 | `Check.num_join/2:p1` |
| `Unk0187` | 1 | `Check.num_lub/2:ret` |
| `Unk0188` | 1 | `Check.num_mix?/2:p0` |
| `Unk0189` | 1 | `Check.num_mix?/2:p1` |
| `Unk0190` | 1 | `Check.num_mix_error/5:p0` |
| `Unk0191` | 1 | `Check.num_mix_error/5:ret` |
| `Unk0192` | 1 | `Check.num_widens?/2:p0` |
| `Unk0193` | 1 | `Check.num_widens?/2:p1` |
| `Unk0194` | 1 | `Check.oor_scan/5:p2` |
| `Unk0195` | 1 | `Check.oor_scan/5:p3` |
| `Unk0196` | 1 | `Check.opaque_table/1:p0` |
| `Unk0197` | 1 | `Check.opaque_table/1:p0` |
| `Unk0198` | 1 | `Check.opaque_table/1:ret` |
| `Unk0199` | 1 | `Check.parse_parametric/1:ret` |
| `Unk0200` | 1 | `Check.pascal?/1:p0` |
| `Unk0201` | 1 | `Check.produced_set/2:p1` |
| `Unk0202` | 1 | `Check.produced_set/2:p1` |
| `Unk0203` | 1 | `Check.produced_set/2:ret` |
| `Unk0204` | 1 | `Check.propagated_callees/1:p0` |
| `Unk0205` | 1 | `Check.propagated_callees/1:ret` |
| `Unk0206` | 1 | `Check.range_base/2:p0` |
| `Unk0207` | 1 | `Check.range_base/2:p0` |
| `Unk0208` | 2 | `Check.range_base/2:p0`, `Check.range_base/2:p1` |
| `Unk0209` | 1 | `Check.range_base/2:ret` |
| `Unk0210` | 1 | `Check.range_bind/6:p0` |
| `Unk0211` | 1 | `Check.range_bind/6:p1` |
| `Unk0212` | 1 | `Check.range_bind/6:p2` |
| `Unk0213` | 1 | `Check.range_bind/6:ret` |
| `Unk0214` | 1 | `Check.range_table/1:p0` |
| `Unk0215` | 1 | `Check.range_table/1:p0` |
| `Unk0216` | 1 | `Check.range_table/1:ret` |
| `Unk0217` | 2 | `Check.scan_bound_calls/4:ret`, `Check.walk_children/4:ret` |
| `Unk0218` | 2 | `Check.scan_num_mix/3:ret`, `Check.scan_num_mix_children/3:ret` |
| `Unk0219` | 1 | `Check.solve_error_sets/2:p0` |
| `Unk0220` | 1 | `Check.tag_name/1:p0` |
| `Unk0221` | 1 | `Check.type_table/1:p0` |
| `Unk0222` | 1 | `Check.type_table/1:ret` |
| `Unk0223` | 2 | `Check.uint_signed_join/2:p0`, `Check.uint_signed_join/2:p1` |
| `Unk0224` | 1 | `Check.width_bounds/1:ret` |
| `Unk0225` | 1 | `Check.with_callees/1:p0` |
| `Unk0226` | 1 | `Comptime.eval/1:p0` |
| `Unk0227` | 1 | `Comptime.eval/1:ret` |
| `Unk0228` | 20 | `Comptime.fold/1:ret`, `Interp.resolve/4:p0`, `Lower.borrow_value/2:p0`, `Lower.borrow_value/2:ret`, `Lower.insert_borrows/3:ret`, `Lower.resolve_consts/2:ret`, `Lower.resolve_rust_pats/2:ret`, `Lower.resolve_structs/2:ret`, `Lower.resolve_variants/2:ret`, `Lower.variant_lit/2:ret`, `Lower.widen_char_arith/2:ret`, `Lower.wrap_char/2:p0`, `Lower.wrap_char/2:ret`, `Macro.do_expand/4:ret`, `Macro.freshen/2:ret`, `Macro.map_node/2:p1`, `Macro.map_node/2:ret`, `Macro.rename/2:ret`, `Macro.substitute/2:p0`, `Macro.walk_for_with/1:ret` |
| `Unk0229` | 1 | `Comptime.int_div/3:p0` |
| `Unk0230` | 1 | `Comptime.int_div/3:p2` |
| `Unk0231` | 1 | `Comptime.int_div/3:ret` |
| `Unk0232` | 2 | `Comptime.truthy!/1:p0`, `Comptime.truthy!/1:ret` |
| `Unk0233` | 1 | `Core.from_arm/1:p0` |
| `Unk0234` | 1 | `Core.from_arm/1:ret` |
| `Unk0235` | 1 | `Core.from_pairs/1:p0` |
| `Unk0236` | 1 | `Core.from_pairs/1:ret` |
| `Unk0237` | 1 | `Core.from_stmt/1:p0` |
| `Unk0238` | 1 | `Core.from_stmt/1:ret` |
| `Unk0239` | 1 | `Core.from_tail/1:p0` |
| `Unk0240` | 3 | `Cst.build/1:p0`, `Cst.open/4:p2`, `Cst.seq/2:p0` |
| `Unk0241` | 1 | `Cst.build/1:ret` |
| `Unk0242` | 1 | `Cst.open/4:p0` |
| `Unk0243` | 1 | `Cst.open/4:p1` |
| `Unk0244` | 2 | `Cst.open/4:p3`, `Cst.seq/2:p1` |
| `Unk0245` | 2 | `Cst.open/4:ret`, `Cst.seq/2:ret` |
| `Unk0246` | 7 | `Decl.all_impl_decls/1:p0`, `Decl.all_impls/1:p0`, `Decl.all_protocols/1:p0`, `Decl.collect_aliases/1:p0`, `Decl.collect_macros/1:p0`, `Decl.in_scope/2:p0`, `Decl.lower_meta/3:p1` |
| `Unk0247` | 5 | `Decl.all_impl_decls/1:ret`, `Decl.all_protocols/1:ret`, `Decl.in_scope/2:ret`, `Protocol.check_assoc!/2:p0`, `Protocol.check_assoc!/2:p1` |
| `Unk0248` | 1 | `Decl.all_impls/1:ret` |
| `Unk0249` | 2 | `Decl.assemble/3:p0`, `Decl.protocol_defs/4:p0` |
| `Unk0250` | 5 | `Decl.assemble/3:p1`, `Decl.subst_const/2:p1`, `Decl.subst_func/2:p1`, `Decl.subst_struct/2:p1`, `Decl.subst_type/2:p1` |
| `Unk0251` | 1 | `Decl.assemble/3:p2` |
| `Unk0252` | 1 | `Decl.assemble/3:ret` |
| `Unk0253` | 2 | `Decl.attach_doc/2:p0`, `Decl.attach_doc/2:ret` |
| `Unk0254` | 1 | `Decl.attach_doc/2:p1` |
| `Unk0255` | 1 | `Decl.attach_external/3:p0` |
| `Unk0256` | 1 | `Decl.attach_external/3:p1` |
| `Unk0257` | 1 | `Decl.attach_external/3:p2` |
| `Unk0258` | 1 | `Decl.attach_external/3:ret` |
| `Unk0259` | 1 | `Decl.attach_targets/2:p0` |
| `Unk0260` | 1 | `Decl.attach_targets/2:p1` |
| `Unk0261` | 1 | `Decl.attach_targets/2:ret` |
| `Unk0262` | 25 | `Decl.balanced_parens/1:p0`, `Decl.decl_boundary?/1:p0`, `Decl.decl_kw?/1:p0`, `Decl.line_continues?/2:p0`, `Decl.line_continues?/2:p1`, `Decl.skip_nl/1:p0`, `Decl.skip_nl/1:ret`, `Decl.split_decls/1:p0`, `Decl.take_block/3:p0`, `Decl.take_block/3:p2`, `Decl.take_decl/1:p0`, `Decl.take_def/1:p0`, `Decl.take_head/4:p2`, `Decl.take_head/4:p3`, `Decl.take_line/2:p0`, `Decl.take_line/2:p1`, `Decl.take_line/3:p0`, `Decl.take_line/3:p1`, `Decl.take_mod_body/2:p0`, `Decl.take_parens/3:p0`, `Decl.take_parens/3:p2`, `Decl.take_type/2:p0`, `Decl.take_type/2:p1`, `Decl.take_until_do/2:p0`, `Decl.take_until_do/2:p1` |
| `Unk0263` | 2 | `Decl.balanced_parens/1:ret`, `Decl.take_parens/3:ret` |
| `Unk0264` | 3 | `Decl.block_seps/5:p0`, `Decl.block_seps/5:p4`, `Decl.block_seps/5:ret` |
| `Unk0265` | 1 | `Decl.build_func/1:p0` |
| `Unk0266` | 1 | `Decl.clause/2:p0` |
| `Unk0267` | 1 | `Decl.clause/2:p1` |
| `Unk0268` | 2 | `Decl.clause_env/2:p1`, `Decl.meta_clause/5:p3` |
| `Unk0269` | 1 | `Decl.collapse_parens/1:p0` |
| `Unk0270` | 1 | `Decl.collapse_parens/1:ret` |
| `Unk0271` | 1 | `Decl.collect_aliases/1:ret` |
| `Unk0272` | 2 | `Decl.collect_macros/1:ret`, `Macro.build_env/1:ret` |
| `Unk0273` | 2 | `Decl.compile/1:ret`, `Decl.protocol_unit/3:ret` |
| `Unk0274` | 1 | `Decl.compile_beam/1:ret` |
| `Unk0275` | 1 | `Decl.def_raw/4:p0` |
| `Unk0276` | 1 | `Decl.def_raw/4:p1` |
| `Unk0277` | 1 | `Decl.def_raw/4:p2` |
| `Unk0278` | 1 | `Decl.def_raw/4:p3` |
| `Unk0279` | 1 | `Decl.def_raw/4:ret` |
| `Unk0280` | 1 | `Decl.detok_block/1:p0` |
| `Unk0281` | 1 | `Decl.detok_block/1:ret` |
| `Unk0282` | 3 | `Decl.extract_parens/1:p0`, `Decl.parse_struct/3:p0`, `Decl.variant/1:p0` |
| `Unk0283` | 1 | `Decl.extract_parens/1:ret` |
| `Unk0284` | 1 | `Decl.field/1:p0` |
| `Unk0285` | 1 | `Decl.fields/1:p0` |
| `Unk0286` | 1 | `Decl.fields/1:ret` |
| `Unk0287` | 1 | `Decl.impl_struct/3:p0` |
| `Unk0288` | 1 | `Decl.impl_struct/3:p1` |
| `Unk0289` | 1 | `Decl.impl_struct/3:p2` |
| `Unk0290` | 1 | `Decl.impl_struct/3:ret` |
| `Unk0291` | 1 | `Decl.in_scope/2:p1` |
| `Unk0292` | 1 | `Decl.in_scope/2:p1` |
| `Unk0293` | 2 | `Decl.inject_stdlib/1:p0`, `Decl.inject_stdlib/1:ret` |
| `Unk0294` | 1 | `Decl.lower_meta/3:p0` |
| `Unk0295` | 1 | `Decl.lower_meta/3:p2` |
| `Unk0296` | 1 | `Decl.lower_meta/3:ret` |
| `Unk0297` | 1 | `Decl.macro_param_names/1:p0` |
| `Unk0298` | 1 | `Decl.macro_param_names/1:ret` |
| `Unk0299` | 1 | `Decl.mark_pub/1:p0` |
| `Unk0300` | 1 | `Decl.mark_pub/1:ret` |
| `Unk0301` | 1 | `Decl.mark_test/1:p0` |
| `Unk0302` | 1 | `Decl.mark_test/1:ret` |
| `Unk0303` | 1 | `Decl.match_paren/3:ret` |
| `Unk0304` | 1 | `Decl.meta_clause/5:p0` |
| `Unk0305` | 3 | `Decl.meta_clause/5:p1`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0306` | 3 | `Decl.meta_clause/5:p1`, `Macro.do_expand/4:p0`, `Macro.expand/3:p0` |
| `Unk0307` | 1 | `Decl.meta_clause/5:p2` |
| `Unk0308` | 4 | `Decl.meta_clause/5:p4`, `Interp.resolve/4:p3`, `Interp.resolve_part/4:p3`, `Interp.stringify/3:p2` |
| `Unk0309` | 1 | `Decl.meta_clause/5:ret` |
| `Unk0310` | 1 | `Decl.nz/1:p0` |
| `Unk0311` | 1 | `Decl.nz/1:ret` |
| `Unk0312` | 1 | `Decl.param/1:p0` |
| `Unk0313` | 1 | `Decl.param/1:ret` |
| `Unk0314` | 7 | `Decl.parse_abstract/4:p0`, `Decl.parse_alias/1:p0`, `Decl.parse_const/3:p0`, `Decl.parse_opaque/3:p0`, `Decl.parse_range/3:p0`, `Decl.parse_type/3:p0`, `Decl.split_once/2:p0` |
| `Unk0315` | 2 | `Decl.parse_abstract/4:p1`, `Decl.parse_abstract_members/1:p0` |
| `Unk0316` | 1 | `Decl.parse_abstract/4:p2` |
| `Unk0317` | 1 | `Decl.parse_abstract/4:p3` |
| `Unk0318` | 1 | `Decl.parse_abstract_members/1:ret` |
| `Unk0319` | 1 | `Decl.parse_alias/1:ret` |
| `Unk0320` | 1 | `Decl.parse_assoc_binding/1:p0` |
| `Unk0321` | 1 | `Decl.parse_assoc_binding/1:ret` |
| `Unk0322` | 1 | `Decl.parse_binder/1:p0` |
| `Unk0323` | 1 | `Decl.parse_binder/1:ret` |
| `Unk0324` | 1 | `Decl.parse_binders/1:p0` |
| `Unk0325` | 1 | `Decl.parse_binders/1:ret` |
| `Unk0326` | 1 | `Decl.parse_bounds/1:p0` |
| `Unk0327` | 1 | `Decl.parse_bounds/1:ret` |
| `Unk0328` | 1 | `Decl.parse_cast_rule/1:p0` |
| `Unk0329` | 1 | `Decl.parse_cast_rule/1:ret` |
| `Unk0330` | 1 | `Decl.parse_const/3:p1` |
| `Unk0331` | 1 | `Decl.parse_const/3:p2` |
| `Unk0332` | 1 | `Decl.parse_external/1:p0` |
| `Unk0333` | 1 | `Decl.parse_external/1:ret` |
| `Unk0334` | 1 | `Decl.parse_head/1:p0` |
| `Unk0335` | 1 | `Decl.parse_head/1:ret` |
| `Unk0336` | 1 | `Decl.parse_op_rule/1:p0` |
| `Unk0337` | 1 | `Decl.parse_op_rule/1:ret` |
| `Unk0338` | 1 | `Decl.parse_opaque/3:p1` |
| `Unk0339` | 1 | `Decl.parse_opaque/3:p2` |
| `Unk0340` | 1 | `Decl.parse_ordinal/1:p0` |
| `Unk0341` | 1 | `Decl.parse_ordinal/1:ret` |
| `Unk0342` | 1 | `Decl.parse_params/1:p0` |
| `Unk0343` | 1 | `Decl.parse_params/1:ret` |
| `Unk0344` | 1 | `Decl.parse_range/3:p1` |
| `Unk0345` | 1 | `Decl.parse_range/3:p2` |
| `Unk0346` | 1 | `Decl.parse_struct/3:p1` |
| `Unk0347` | 1 | `Decl.parse_struct/3:p2` |
| `Unk0348` | 1 | `Decl.parse_targets/1:p0` |
| `Unk0349` | 1 | `Decl.parse_targets/1:ret` |
| `Unk0350` | 1 | `Decl.parse_type/3:p1` |
| `Unk0351` | 1 | `Decl.parse_type/3:p2` |
| `Unk0352` | 1 | `Decl.parse_use/1:p0` |
| `Unk0353` | 1 | `Decl.proto_method_traits/1:ret` |
| `Unk0354` | 2 | `Decl.protocol_defs/4:p1`, `Protocol.expand/5:p2` |
| `Unk0355` | 2 | `Decl.protocol_defs/4:p2`, `Protocol.expand/5:p3` |
| `Unk0356` | 2 | `Decl.protocol_defs/4:p3`, `Protocol.expand/5:p4` |
| `Unk0357` | 3 | `Decl.protocol_defs/4:ret`, `Protocol.expand/5:ret`, `Protocol.impl_methods/2:ret` |
| `Unk0358` | 1 | `Decl.protocol_struct/2:p0` |
| `Unk0359` | 1 | `Decl.protocol_struct/2:p1` |
| `Unk0360` | 1 | `Decl.protocol_struct/2:ret` |
| `Unk0361` | 1 | `Decl.req_ret/1:p0` |
| `Unk0362` | 1 | `Decl.req_ret/1:ret` |
| `Unk0363` | 1 | `Decl.show_module/0:ret` |
| `Unk0364` | 1 | `Decl.split2/2:p0` |
| `Unk0365` | 1 | `Decl.split2/2:p1` |
| `Unk0366` | 1 | `Decl.split2/2:ret` |
| `Unk0367` | 1 | `Decl.split_decls/1:ret` |
| `Unk0368` | 1 | `Decl.split_forall/1:p0` |
| `Unk0369` | 1 | `Decl.split_forall/1:ret` |
| `Unk0370` | 1 | `Decl.split_once/2:ret` |
| `Unk0371` | 1 | `Decl.split_top/2:p0` |
| `Unk0372` | 1 | `Decl.split_top/2:p1` |
| `Unk0373` | 1 | `Decl.split_top/2:ret` |
| `Unk0374` | 1 | `Decl.strip_type_params/1:p0` |
| `Unk0375` | 1 | `Decl.strip_type_params/1:ret` |
| `Unk0376` | 1 | `Decl.subst_const/2:p0` |
| `Unk0377` | 1 | `Decl.subst_fields/2:p0` |
| `Unk0378` | 1 | `Decl.subst_fields/2:p1` |
| `Unk0379` | 1 | `Decl.subst_func/2:p0` |
| `Unk0380` | 1 | `Decl.subst_struct/2:p0` |
| `Unk0381` | 1 | `Decl.subst_type/2:p0` |
| `Unk0382` | 2 | `Decl.subst_type_str/2:p0`, `Decl.subst_type_str/2:ret` |
| `Unk0383` | 1 | `Decl.subst_type_str/2:p1` |
| `Unk0384` | 1 | `Decl.subst_variant/2:p0` |
| `Unk0385` | 1 | `Decl.subst_variant/2:p1` |
| `Unk0386` | 1 | `Decl.take_block/3:ret` |
| `Unk0387` | 1 | `Decl.take_decl/1:ret` |
| `Unk0388` | 2 | `Decl.take_def/1:ret`, `Decl.take_head/4:ret` |
| `Unk0389` | 1 | `Decl.take_head/4:p0` |
| `Unk0390` | 1 | `Decl.take_head/4:p1` |
| `Unk0391` | 2 | `Decl.take_line/2:ret`, `Decl.take_line/3:ret` |
| `Unk0392` | 1 | `Decl.take_mod_body/2:p1` |
| `Unk0393` | 1 | `Decl.take_mod_body/2:ret` |
| `Unk0394` | 1 | `Decl.take_type/2:ret` |
| `Unk0395` | 1 | `Decl.take_until_do/2:ret` |
| `Unk0396` | 17 | `Doc.concat/1:p0`, `Doc.concat/1:ret`, `Doc.concat/2:p0`, `Doc.concat/2:p1`, `Doc.concat/2:ret`, `Doc.empty/0:ret`, `Doc.join/2:ret`, `Doc.line_suffix/1:p0`, `Doc.line_suffix/1:ret`, `Doc.nest/2:p1`, `Doc.nest/2:ret`, `Doc.render/2:p0`, `Doc.text/1:ret`, `Format.bd/3:ret`, `Format.group_doc/4:ret`, `Format.line_doc/1:ret`, `Format.node_doc/2:ret` |
| `Unk0397` | 2 | `Doc.do_render/5:p2`, `Doc.fits?/2:p1` |
| `Unk0398` | 3 | `Doc.do_render/5:p3`, `Doc.flat_string/1:p0`, `Doc.flush_suffix/2:p0` |
| `Unk0399` | 2 | `Doc.group/1:p0`, `Doc.must_break?/1:p0` |
| `Unk0400` | 1 | `Doc.group/1:ret` |
| `Unk0401` | 1 | `Doc.hardline/0:ret` |
| `Unk0402` | 1 | `Doc.if_break/2:p0` |
| `Unk0403` | 1 | `Doc.if_break/2:p1` |
| `Unk0404` | 1 | `Doc.if_break/2:ret` |
| `Unk0405` | 1 | `Doc.join/2:p0` |
| `Unk0406` | 1 | `Doc.join/2:p1` |
| `Unk0407` | 1 | `Doc.line/0:ret` |
| `Unk0408` | 14 | `Doc.nest/2:p0`, `Format.apply_node/3:p1`, `Format.apply_node/3:p2`, `Format.apply_node/3:ret`, `Format.indent_and_render/4:p1`, `Format.pop/1:p0`, `Format.pop/1:ret`, `Format.push/2:p0`, `Format.push/2:p1`, `Format.push/2:ret`, `Format.render_line/2:p1`, `Format.update_stack/4:p2`, `Format.update_stack/4:p3`, `Format.update_stack/4:ret` |
| `Unk0409` | 1 | `Doc.softline/0:ret` |
| `Unk0410` | 2 | `Doctest.augment/2:p1`, `Doctest.extract/1:ret` |
| `Unk0411` | 1 | `Doctest.exunit_cases/2:p1` |
| `Unk0412` | 1 | `Doctest.exunit_cases/2:ret` |
| `Unk0413` | 1 | `Doctest.fences/1:p0` |
| `Unk0414` | 1 | `Doctest.fences/1:ret` |
| `Unk0415` | 1 | `Doctest.module_doc_strings/1:ret` |
| `Unk0416` | 1 | `Doctest.pairs/1:p0` |
| `Unk0417` | 1 | `Doctest.pairs/1:ret` |
| `Unk0418` | 1 | `Doctest.run/2:p1` |
| `Unk0419` | 1 | `Doctest.run/2:ret` |
| `Unk0420` | 1 | `Doctest.run_markdown/1:p0` |
| `Unk0421` | 1 | `Doctest.run_markdown/1:ret` |
| `Unk0422` | 8 | `Exhaustiveness.add_range/4:p0`, `Exhaustiveness.add_range/4:ret`, `Exhaustiveness.add_type/3:p0`, `Exhaustiveness.add_type/3:ret`, `Exhaustiveness.base_env/0:ret`, `Exhaustiveness.program_env/3:ret`, `PatternLower.add_struct/3:p0`, `PatternLower.add_struct/3:ret` |
| `Unk0423` | 1 | `Exhaustiveness.add_range/4:p1` |
| `Unk0424` | 1 | `Exhaustiveness.add_range/4:p2` |
| `Unk0425` | 1 | `Exhaustiveness.add_range/4:p3` |
| `Unk0426` | 1 | `Exhaustiveness.add_type/3:p2` |
| `Unk0427` | 2 | `Exhaustiveness.analyze/3:p0`, `PatternLower.lower_clause/2:ret` |
| `Unk0428` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0429` | 13 | `Exhaustiveness.analyze/3:p2`, `Exhaustiveness.arity/2:p0`, `Exhaustiveness.check_match!/3:p1`, `Exhaustiveness.check_one_case!/3:p1`, `Exhaustiveness.missing_head/2:p0`, `Exhaustiveness.signature/2:p0`, `Exhaustiveness.specialize/3:p2`, `Exhaustiveness.useful?/3:p2`, `Exhaustiveness.witness/3:p2`, `PatternLower.lower/2:p1`, `PatternLower.lower_clause/2:p1`, `PatternLower.lower_list/3:p2`, `PatternLower.lower_many/2:p1` |
| `Unk0430` | 1 | `Exhaustiveness.analyze/3:ret` |
| `Unk0431` | 2 | `Exhaustiveness.arity/2:p1`, `Exhaustiveness.specialize/3:p1` |
| `Unk0432` | 1 | `Exhaustiveness.check_case_bodies!/2:p0` |
| `Unk0433` | 1 | `Exhaustiveness.check_case_bodies!/2:p1` |
| `Unk0434` | 1 | `Exhaustiveness.check_case_bodies!/2:ret` |
| `Unk0435` | 1 | `Exhaustiveness.check_match!/3:p0` |
| `Unk0436` | 2 | `Exhaustiveness.check_match!/3:p2`, `Exhaustiveness.check_one_case!/3:p2` |
| `Unk0437` | 1 | `Exhaustiveness.check_match!/3:ret` |
| `Unk0438` | 1 | `Exhaustiveness.check_one_case!/3:ret` |
| `Unk0439` | 2 | `Exhaustiveness.collect_cases/2:p0`, `Exhaustiveness.collect_children/2:p0` |
| `Unk0440` | 4 | `Exhaustiveness.collect_cases/2:p1`, `Exhaustiveness.collect_cases/2:ret`, `Exhaustiveness.collect_children/2:p1`, `Exhaustiveness.collect_children/2:ret` |
| `Unk0441` | 7 | `Exhaustiveness.default/1:p0`, `Exhaustiveness.default/1:ret`, `Exhaustiveness.head_ctors/1:p0`, `Exhaustiveness.specialize/3:p0`, `Exhaustiveness.specialize/3:ret`, `Exhaustiveness.useful?/3:p0`, `Exhaustiveness.witness/3:p0` |
| `Unk0442` | 2 | `Exhaustiveness.head_ctors/1:ret`, `Exhaustiveness.signature/2:p1` |
| `Unk0443` | 1 | `Exhaustiveness.missing_head/2:p1` |
| `Unk0444` | 1 | `Exhaustiveness.missing_head/2:ret` |
| `Unk0445` | 1 | `Exhaustiveness.pascal/1:p0` |
| `Unk0446` | 1 | `Exhaustiveness.program_env/3:p1` |
| `Unk0447` | 1 | `Exhaustiveness.program_env/3:p2` |
| `Unk0448` | 1 | `Exhaustiveness.render/1:p0` |
| `Unk0449` | 1 | `Exhaustiveness.signature/2:ret` |
| `Unk0450` | 1 | `Exhaustiveness.useful?/3:p1` |
| `Unk0451` | 1 | `Exhaustiveness.witness/3:ret` |
| `Unk0452` | 1 | `Fixpoint.check/4:p0` |
| `Unk0453` | 1 | `Fixpoint.check/4:p1` |
| `Unk0454` | 1 | `Fixpoint.check/4:p2` |
| `Unk0455` | 1 | `Fixpoint.check/4:p3` |
| `Unk0456` | 1 | `Fixpoint.check/4:ret` |
| `Unk0457` | 18 | `Format.apply_node/3:p0`, `Format.bd/3:p0`, `Format.bd/3:p1`, `Format.block_head?/2:p0`, `Format.declaration_line?/1:p0`, `Format.head_tok/1:p0`, `Format.lead_adjust/1:p0`, `Format.line_doc/1:p0`, `Format.mark/1:ret`, `Format.mark/3:p1`, `Format.mark/3:p2`, `Format.mark/3:ret`, `Format.node_doc/2:p0`, `Format.render_line/2:p0`, `Format.tail_tok/1:p0`, `Format.trailing_op?/1:p0`, `Format.update_stack/4:p0`, `Format.value_end?/1:p0` |
| `Unk0458` | 10 | `Format.blank?/1:p0`, `Format.block_head?/2:p1`, `Format.boundary?/1:p0`, `Format.comment_only?/1:p0`, `Format.indent_and_render/4:p0`, `Format.mark/1:p0`, `Format.mark/3:p0`, `Format.next_code_line/1:p0`, `Format.next_code_line/1:ret`, `Format.update_stack/4:p1` |
| `Unk0459` | 4 | `Format.boundary_tok?/1:p0`, `Format.decl_kw?/1:p0`, `Format.head_tok/1:ret`, `Format.space?/2:p1` |
| `Unk0460` | 7 | `Format.chunk_on_comma/3:p0`, `Format.chunk_on_comma/3:p1`, `Format.chunk_on_comma/3:p2`, `Format.chunk_on_comma/3:ret`, `Format.finish_items/2:p0`, `Format.finish_items/2:p1`, `Format.finish_items/2:ret` |
| `Unk0461` | 1 | `Format.closer_lead?/1:p0` |
| `Unk0462` | 1 | `Format.cons_group?/1:p0` |
| `Unk0463` | 1 | `Format.cont_lead?/1:p0` |
| `Unk0464` | 3 | `Format.format/1:p0`, `Format.format/1:ret`, `Format.format_result/1:p0` |
| `Unk0465` | 1 | `Format.format_result/1:ret` |
| `Unk0466` | 3 | `Format.group_doc/4:p0`, `Format.group_doc/4:p2`, `Format.leaf/1:p0` |
| `Unk0467` | 2 | `Format.group_doc/4:p1`, `Format.split_items/1:p0` |
| `Unk0468` | 1 | `Format.has_comment?/1:p0` |
| `Unk0469` | 1 | `Format.has_tok?/2:p0` |
| `Unk0470` | 1 | `Format.has_tok?/2:p1` |
| `Unk0471` | 6 | `Format.ll/3:p0`, `Format.ll/3:p1`, `Format.ll/3:p2`, `Format.ll/3:ret`, `Format.logical_lines/1:p0`, `Format.logical_lines/1:ret` |
| `Unk0472` | 3 | `Format.space?/2:p0`, `Format.tail_tok/1:ret`, `Format.value_end_tok?/1:p0` |
| `Unk0473` | 1 | `Format.split_items/1:ret` |
| `Unk0474` | 1 | `Format.squeeze_blanks/1:p0` |
| `Unk0475` | 1 | `Format.squeeze_blanks/1:ret` |
| `Unk0476` | 1 | `Format.trailing_comma?/1:p0` |
| `Unk0477` | 1 | `FormsEquiv.abstract_code/1:p0` |
| `Unk0478` | 1 | `FormsEquiv.abstract_code/1:ret` |
| `Unk0479` | 2 | `FormsEquiv.alpha_rename/1:p0`, `FormsEquiv.walk_rename/2:p0` |
| `Unk0480` | 1 | `FormsEquiv.alpha_rename/1:ret` |
| `Unk0481` | 1 | `FormsEquiv.bool_clause/1:p0` |
| `Unk0482` | 1 | `FormsEquiv.bool_clause/1:ret` |
| `Unk0483` | 1 | `FormsEquiv.bool_clause_pair/1:p0` |
| `Unk0484` | 1 | `FormsEquiv.bool_clause_pair/1:ret` |
| `Unk0485` | 2 | `FormsEquiv.canon_bool_case/1:p0`, `FormsEquiv.canon_bool_case/1:ret` |
| `Unk0486` | 9 | `FormsEquiv.diff/2:p0`, `FormsEquiv.diff/2:p1`, `FormsEquiv.equivalent?/2:p0`, `FormsEquiv.equivalent?/2:p1`, `FormsEquiv.normalize/1:p0`, `FormsEquiv.verified?/2:p0`, `FormsEquiv.verified?/2:p1`, `FormsEquiv.verify/2:p0`, `FormsEquiv.verify/2:p1` |
| `Unk0487` | 1 | `FormsEquiv.diff/2:ret` |
| `Unk0488` | 2 | `FormsEquiv.fold_neg_literal/1:p0`, `FormsEquiv.fold_neg_literal/1:ret` |
| `Unk0489` | 1 | `FormsEquiv.key/1:p0` |
| `Unk0490` | 1 | `FormsEquiv.key/1:ret` |
| `Unk0491` | 1 | `FormsEquiv.normalize/1:ret` |
| `Unk0492` | 1 | `FormsEquiv.user_function?/1:p0` |
| `Unk0493` | 1 | `FormsEquiv.verify/2:ret` |
| `Unk0494` | 1 | `FormsEquiv.walk_rename/2:p1` |
| `Unk0495` | 1 | `FormsEquiv.walk_rename/2:ret` |
| `Unk0496` | 2 | `FormsEquiv.zero_anno/1:p0`, `FormsEquiv.zero_anno/1:ret` |
| `Unk0497` | 1 | `History.add/1:p0` |
| `Unk0498` | 1 | `History.add/1:ret` |
| `Unk0499` | 2 | `History.dedup_consecutive/1:p0`, `History.dedup_consecutive/1:ret` |
| `Unk0500` | 1 | `History.load/0:ret` |
| `Unk0501` | 1 | `History.path/0:ret` |
| `Unk0502` | 1 | `Infer.app/2:p1` |
| `Unk0503` | 18 | `Infer.app/2:ret`, `Infer.bind_checked/3:p2`, `Infer.con/1:ret`, `Infer.do_unify/3:p1`, `Infer.do_unify/3:p2`, `Infer.free_vars/2:p1`, `Infer.gen_pat/4:p1`, `Infer.gen_pat_cons/5:p2`, `Infer.generalize_map/3:p1`, `Infer.mark_num/2:p1`, `Infer.occurs?/3:p2`, `Infer.render/3:p2`, `Infer.render_wp/3:p2`, `Infer.resolve/2:p1`, `Infer.resolve/2:ret`, `Infer.unify/3:p1`, `Infer.unify/3:p2`, `Infer.unk_vars/2:p1` |
| `Unk0504` | 27 | `Infer.app1/2:p1`, `Infer.bind_checked/3:p0`, `Infer.call_sig/6:p5`, `Infer.do_unify/3:p0`, `Infer.free_vars/2:p0`, `Infer.fresh/1:p0`, `Infer.fresh_n/2:p0`, `Infer.fresh_num/1:p0`, `Infer.freshen_tvars/2:p1`, `Infer.gen/4:p3`, `Infer.gen_args_then_fresh/4:p3`, `Infer.gen_block/4:p3`, `Infer.gen_cons/5:p4`, `Infer.gen_pat/4:p3`, `Infer.gen_pat_cons/5:p4`, `Infer.generalize_map/3:p2`, `Infer.instantiate/5:p4`, `Infer.mark_num/2:p0`, `Infer.occurs?/3:p0`, `Infer.render/3:p0`, `Infer.render_wp/3:p0`, `Infer.resolve/2:p0`, `Infer.resolve_program/2:p1`, `Infer.sigvar_call/5:p4`, `Infer.store_new/0:ret`, `Infer.unify/3:p0`, `Infer.unk_vars/2:p0` |
| `Unk0505` | 9 | `Infer.app1/2:ret`, `Infer.call_sig/6:ret`, `Infer.fresh/1:ret`, `Infer.fresh_num/1:ret`, `Infer.gen/4:ret`, `Infer.gen_args_then_fresh/4:ret`, `Infer.gen_block/4:ret`, `Infer.gen_cons/5:ret`, `Infer.instantiate/5:ret` |
| `Unk0506` | 1 | `Infer.bind/3:p0` |
| `Unk0507` | 1 | `Infer.bind/3:p1` |
| `Unk0508` | 1 | `Infer.bind/3:p2` |
| `Unk0509` | 1 | `Infer.bind/3:ret` |
| `Unk0510` | 1 | `Infer.bind_checked/3:p1` |
| `Unk0511` | 3 | `Infer.bind_checked/3:ret`, `Infer.do_unify/3:ret`, `Infer.unify/3:ret` |
| `Unk0512` | 1 | `Infer.bind_params/3:p0` |
| `Unk0513` | 1 | `Infer.bind_params/3:p1` |
| `Unk0514` | 1 | `Infer.bind_params/3:p2` |
| `Unk0515` | 1 | `Infer.bind_params/3:ret` |
| `Unk0516` | 1 | `Infer.build_ctx/2:p0` |
| `Unk0517` | 1 | `Infer.build_ctx/2:p1` |
| `Unk0518` | 1 | `Infer.build_ctx/2:ret` |
| `Unk0519` | 1 | `Infer.build_ledger/2:p0` |
| `Unk0520` | 1 | `Infer.build_ledger/2:ret` |
| `Unk0521` | 11 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.ok_payload/3:p1`, `Infer.result_analysis/3:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0522` | 11 | `Infer.call_sig/6:p0`, `Infer.call_sig/6:p4`, `Infer.gen/4:p2`, `Infer.gen_args_then_fresh/4:p2`, `Infer.gen_block/4:p2`, `Infer.gen_cons/5:p3`, `Infer.infer_group/2:p1`, `Infer.instantiate/5:p3`, `Infer.ok_payload/3:p1`, `Infer.result_analysis/3:p1`, `Infer.sigvar_call/5:p0` |
| `Unk0523` | 1 | `Infer.call_sig/6:p1` |
| `Unk0524` | 9 | `Infer.call_sig/6:p3`, `Infer.gen/4:p1`, `Infer.gen_args_then_fresh/4:p1`, `Infer.gen_block/4:p1`, `Infer.gen_cons/5:p2`, `Infer.gen_pat/4:p2`, `Infer.gen_pat_cons/5:p3`, `Infer.instantiate/5:p2`, `Infer.sigvar_call/5:p3` |
| `Unk0525` | 1 | `Infer.case_arm/1:p0` |
| `Unk0526` | 1 | `Infer.case_arm/1:ret` |
| `Unk0527` | 1 | `Infer.clear_xmod/0:ret` |
| `Unk0528` | 1 | `Infer.cluster_name/2:p0` |
| `Unk0529` | 1 | `Infer.free_vars/2:ret` |
| `Unk0530` | 1 | `Infer.fresh_n/2:ret` |
| `Unk0531` | 1 | `Infer.freshen_tvars/2:p0` |
| `Unk0532` | 1 | `Infer.freshen_tvars/2:ret` |
| `Unk0533` | 3 | `Infer.gen_pat/4:p0`, `Infer.gen_pat_cons/5:p0`, `Infer.gen_pat_cons/5:p1` |
| `Unk0534` | 2 | `Infer.gen_pat/4:ret`, `Infer.gen_pat_cons/5:ret` |
| `Unk0535` | 1 | `Infer.generalize_map/3:p0` |
| `Unk0536` | 2 | `Infer.generalize_map/3:ret`, `Infer.render/3:p1` |
| `Unk0537` | 3 | `Infer.hole_or/2:p0`, `Infer.hole_or/2:p1`, `Infer.hole_or/2:ret` |
| `Unk0538` | 1 | `Infer.hole_sig?/1:p0` |
| `Unk0539` | 1 | `Infer.infer_group/2:p0` |
| `Unk0540` | 1 | `Infer.infer_group/2:ret` |
| `Unk0541` | 1 | `Infer.instantiate/5:p0` |
| `Unk0542` | 2 | `Infer.load_prelude_sigs/0:ret`, `Infer.prelude_sigs/0:ret` |
| `Unk0543` | 1 | `Infer.mark_num/2:ret` |
| `Unk0544` | 1 | `Infer.max_ph/1:p0` |
| `Unk0545` | 1 | `Infer.mod_name/1:p0` |
| `Unk0546` | 1 | `Infer.num_conflict?/3:p0` |
| `Unk0547` | 1 | `Infer.num_conflict?/3:p1` |
| `Unk0548` | 2 | `Infer.num_conflict?/3:p2`, `Infer.numeric_con?/1:p0` |
| `Unk0549` | 1 | `Infer.occurs?/3:p1` |
| `Unk0550` | 1 | `Infer.ok_payload/3:p0` |
| `Unk0551` | 1 | `Infer.ok_payload/3:p2` |
| `Unk0552` | 1 | `Infer.ok_payload/3:ret` |
| `Unk0553` | 1 | `Infer.parse_type/2:p0` |
| `Unk0554` | 1 | `Infer.parse_type/2:p1` |
| `Unk0555` | 1 | `Infer.parse_type/2:ret` |
| `Unk0556` | 1 | `Infer.prime_xmod/2:p0` |
| `Unk0557` | 1 | `Infer.prime_xmod/2:p1` |
| `Unk0558` | 1 | `Infer.prime_xmod/2:ret` |
| `Unk0559` | 1 | `Infer.put_slot/3:p0` |
| `Unk0560` | 1 | `Infer.put_slot/3:ret` |
| `Unk0561` | 1 | `Infer.render_wp/3:p1` |
| `Unk0562` | 1 | `Infer.resolve_program/2:p0` |
| `Unk0563` | 2 | `Infer.resolve_program/2:ret`, `Infer.whole_program/3:ret` |
| `Unk0564` | 1 | `Infer.resolve_struct_params/4:p0` |
| `Unk0565` | 1 | `Infer.resolve_struct_params/4:p1` |
| `Unk0566` | 1 | `Infer.resolve_struct_params/4:p2` |
| `Unk0567` | 1 | `Infer.resolve_struct_params/4:p3` |
| `Unk0568` | 1 | `Infer.resolve_struct_params/4:ret` |
| `Unk0569` | 1 | `Infer.result_analysis/3:p0` |
| `Unk0570` | 1 | `Infer.result_analysis/3:p2` |
| `Unk0571` | 1 | `Infer.result_analysis/3:ret` |
| `Unk0572` | 1 | `Infer.result_tag/1:p0` |
| `Unk0573` | 1 | `Infer.result_tag/1:ret` |
| `Unk0574` | 1 | `Infer.sig_of/1:p0` |
| `Unk0575` | 1 | `Infer.sig_of/1:ret` |
| `Unk0576` | 1 | `Infer.sigvar_call/5:p1` |
| `Unk0577` | 1 | `Infer.sigvar_call/5:p2` |
| `Unk0578` | 1 | `Infer.sigvar_call/5:ret` |
| `Unk0579` | 1 | `Infer.slot_sig/3:p2` |
| `Unk0580` | 1 | `Infer.slot_sig/3:ret` |
| `Unk0581` | 1 | `Infer.tvar?/1:p0` |
| `Unk0582` | 1 | `Infer.tvar?/1:ret` |
| `Unk0583` | 1 | `Infer.tvar_name/1:p0` |
| `Unk0584` | 1 | `Infer.tvar_name/1:ret` |
| `Unk0585` | 1 | `Infer.unk_vars/2:ret` |
| `Unk0586` | 1 | `Infer.whole_program/3:p0` |
| `Unk0587` | 1 | `Infer.whole_program/3:p1` |
| `Unk0588` | 1 | `Infer.whole_program/3:p2` |
| `Unk0589` | 1 | `Infer.xmod_cache/0:ret` |
| `Unk0590` | 2 | `Interp.concat_chain/1:p0`, `Interp.concat_chain/1:ret` |
| `Unk0591` | 1 | `Interp.int_type?/1:p0` |
| `Unk0592` | 1 | `Interp.resolve_part/4:p0` |
| `Unk0593` | 2 | `JS.all_funcs/1:p0`, `JS.all_funcs/1:ret` |
| `Unk0594` | 1 | `JS.all_funcs/1:p0` |
| `Unk0595` | 1 | `JS.arm_return/2:p0` |
| `Unk0596` | 1 | `JS.arm_return/2:p1` |
| `Unk0597` | 1 | `JS.bind_lines/1:p0` |
| `Unk0598` | 4 | `JS.block_return/1:p0`, `JVM.block_value/1:p0`, `Shadow.ded_block/4:ret`, `Shadow.dedup/3:ret` |
| `Unk0599` | 1 | `JS.case_arm_js/1:p0` |
| `Unk0600` | 1 | `JS.clause_js/1:p0` |
| `Unk0601` | 4 | `JS.clause_return/2:p1`, `JS.guarded_return/3:p2`, `JVM.clause_value/2:p1`, `Shadow.dedup/3:p1` |
| `Unk0602` | 1 | `JS.cp_lit/1:p0` |
| `Unk0603` | 1 | `JS.dispatcher_js/4:p0` |
| `Unk0604` | 1 | `JS.dispatcher_js/4:p1` |
| `Unk0605` | 1 | `JS.dispatcher_js/4:p2` |
| `Unk0606` | 1 | `JS.dispatcher_js/4:p3` |
| `Unk0607` | 1 | `JS.first_unsupported/2:p0` |
| `Unk0608` | 1 | `JS.first_unsupported/2:p1` |
| `Unk0609` | 2 | `JS.first_unsupported/2:p1`, `JS.first_unsupported/2:ret` |
| `Unk0610` | 1 | `JS.float?/1:p0` |
| `Unk0611` | 1 | `JS.function_js/1:p0` |
| `Unk0612` | 1 | `JS.guarded_return/3:p1` |
| `Unk0613` | 3 | `JS.js_atom/1:p0`, `JS.js_str/1:p0`, `JS.lit_js/1:p0` |
| `Unk0614` | 1 | `JS.js_guard!/3:p0` |
| `Unk0615` | 1 | `JS.js_guard!/3:p1` |
| `Unk0616` | 1 | `JS.js_guard!/3:p2` |
| `Unk0617` | 1 | `JS.js_guard!/3:ret` |
| `Unk0618` | 1 | `JS.js_number_int?/1:p0` |
| `Unk0619` | 1 | `JS.mangle/3:p0` |
| `Unk0620` | 1 | `JS.mangle/3:p1` |
| `Unk0621` | 1 | `JS.mangle/3:p2` |
| `Unk0622` | 1 | `JS.match_elems/2:p0` |
| `Unk0623` | 1 | `JS.match_elems/2:ret` |
| `Unk0624` | 1 | `JS.num_js/1:p0` |
| `Unk0625` | 1 | `JS.paren/1:p0` |
| `Unk0626` | 1 | `JS.pascal?/1:p0` |
| `Unk0627` | 1 | `JS.pat_match/2:ret` |
| `Unk0628` | 1 | `JS.reject_mixed_int_mode!/1:ret` |
| `Unk0629` | 1 | `JS.reject_unsupported!/1:p0` |
| `Unk0630` | 1 | `JS.reject_unsupported!/1:ret` |
| `Unk0631` | 1 | `JS.reject_wide_int!/2:p0` |
| `Unk0632` | 1 | `JS.reject_wide_int!/2:p1` |
| `Unk0633` | 1 | `JS.reject_wide_int!/2:ret` |
| `Unk0634` | 1 | `JS.stmt_js/1:p0` |
| `Unk0635` | 1 | `JS.stmt_return/1:p0` |
| `Unk0636` | 1 | `JS.struct_name_set/1:p0` |
| `Unk0637` | 1 | `JS.struct_name_set/1:p0` |
| `Unk0638` | 1 | `JS.struct_name_set/1:ret` |
| `Unk0639` | 1 | `JS.sum_ctor_map/1:p0` |
| `Unk0640` | 1 | `JS.sum_ctor_map/1:p0` |
| `Unk0641` | 1 | `JS.sum_ctor_map/1:ret` |
| `Unk0642` | 1 | `JS.sum_guard_js/1:p0` |
| `Unk0643` | 2 | `JVM.all_funcs/1:p0`, `JVM.all_funcs/1:ret` |
| `Unk0644` | 1 | `JVM.all_funcs/1:p0` |
| `Unk0645` | 1 | `JVM.bind_str/1:p0` |
| `Unk0646` | 1 | `JVM.case_arms/2:p0` |
| `Unk0647` | 1 | `JVM.case_arms/2:ret` |
| `Unk0648` | 1 | `JVM.clause_lines/1:p0` |
| `Unk0649` | 1 | `JVM.clause_lines/1:ret` |
| `Unk0650` | 1 | `JVM.clause_match/1:p0` |
| `Unk0651` | 1 | `JVM.clause_match/1:ret` |
| `Unk0652` | 1 | `JVM.first_unsupported/2:p0` |
| `Unk0653` | 1 | `JVM.first_unsupported/2:p1` |
| `Unk0654` | 2 | `JVM.first_unsupported/2:p1`, `JVM.first_unsupported/2:ret` |
| `Unk0655` | 1 | `JVM.function_kt/1:p0` |
| `Unk0656` | 1 | `JVM.guarded_arm/2:p1` |
| `Unk0657` | 1 | `JVM.guarded_return/3:p0` |
| `Unk0658` | 1 | `JVM.guarded_return/3:p1` |
| `Unk0659` | 1 | `JVM.guarded_return/3:p2` |
| `Unk0660` | 1 | `JVM.kotlin_module/2:p1` |
| `Unk0661` | 2 | `JVM.kt_str/1:p0`, `JVM.lit_kt/1:p0` |
| `Unk0662` | 1 | `JVM.kt_type/1:p0` |
| `Unk0663` | 1 | `JVM.kt_type/1:ret` |
| `Unk0664` | 1 | `JVM.pat_match/2:ret` |
| `Unk0665` | 1 | `JVM.reject_unsupported!/1:p0` |
| `Unk0666` | 1 | `JVM.reject_unsupported!/1:ret` |
| `Unk0667` | 1 | `JVM.stmt_kt/1:p0` |
| `Unk0668` | 1 | `JVM.stmt_value/1:p0` |
| `Unk0669` | 1 | `JVM.sum_decl/1:p0` |
| `Unk0670` | 1 | `JVM.to_jar/3:p1` |
| `Unk0671` | 1 | `JVM.to_jar/3:p2` |
| `Unk0672` | 1 | `JVM.to_jar/3:ret` |
| `Unk0673` | 1 | `JVM.variant_decl/2:p0` |
| `Unk0674` | 1 | `JVM.variant_decl/2:p1` |
| `Unk0675` | 1 | `Lexer.advance/2:p0` |
| `Unk0676` | 1 | `Lexer.advance/2:p1` |
| `Unk0677` | 1 | `Lexer.advance/2:ret` |
| `Unk0678` | 1 | `Lexer.binify/1:p0` |
| `Unk0679` | 1 | `Lexer.binify/1:ret` |
| `Unk0680` | 1 | `Lexer.capture_hole/3:ret` |
| `Unk0681` | 1 | `Lexer.char_escape/1:p0` |
| `Unk0682` | 1 | `Lexer.char_escape/1:ret` |
| `Unk0683` | 1 | `Lexer.close_char/1:ret` |
| `Unk0684` | 1 | `Lexer.collapse_nl/1:p0` |
| `Unk0685` | 1 | `Lexer.collapse_nl/1:ret` |
| `Unk0686` | 2 | `Lexer.cp!/1:p0`, `Lexer.cp!/1:ret` |
| `Unk0687` | 1 | `Lexer.detokenize/2:p0` |
| `Unk0688` | 1 | `Lexer.detokenize/2:p1` |
| `Unk0689` | 1 | `Lexer.detokenize/2:ret` |
| `Unk0690` | 1 | `Lexer.escape_str/1:p0` |
| `Unk0691` | 43 | `Lexer.expr_tokens/1:ret`, `Pratt.climb/3:p1`, `Pratt.collect_dots/2:p1`, `Pratt.expect_kw/2:p0`, `Pratt.expect_kw/2:ret`, `Pratt.expect_op/2:p0`, `Pratt.expect_op/2:ret`, `Pratt.expect_rbracket/1:p0`, `Pratt.expect_rbracket/1:ret`, `Pratt.expect_rparen/1:p0`, `Pratt.expect_rparen/1:ret`, `Pratt.finish_arg/2:p1`, `Pratt.parse_args/1:p0`, `Pratt.parse_arms/2:p0`, `Pratt.parse_block/1:p0`, `Pratt.parse_capture/1:p0`, `Pratt.parse_case/1:p0`, `Pratt.parse_expr/2:p0`, `Pratt.parse_if/1:p0`, `Pratt.parse_lambda/1:p0`, `Pratt.parse_list/2:p0`, `Pratt.parse_map/2:p0`, `Pratt.parse_param/1:p0`, `Pratt.parse_params/1:p0`, `Pratt.parse_pat/1:p0`, `Pratt.parse_pat_args/2:p0`, `Pratt.parse_pat_fields/2:p0`, `Pratt.parse_pat_list/2:p0`, `Pratt.parse_pat_map/2:p0`, `Pratt.parse_pat_tuple/2:p0`, `Pratt.parse_path/1:p0`, `Pratt.parse_pats/2:p0`, `Pratt.parse_postfix/2:p1`, `Pratt.parse_prefix/1:p0`, `Pratt.parse_primary/1:p0`, `Pratt.parse_stmt/1:p0`, `Pratt.parse_stmts/2:p0`, `Pratt.parse_tuple/2:p0`, `Pratt.parse_type/1:p0`, `Pratt.parse_type_args/2:p0`, `Pratt.parse_with/1:p0`, `Pratt.parse_with_clauses/2:p0`, `Pratt.peek_infix/1:p0` |
| `Unk0692` | 2 | `Lexer.lex/2:p0`, `Lexer.tokenize_trivia/1:p0` |
| `Unk0693` | 1 | `Lexer.lex/2:p1` |
| `Unk0694` | 2 | `Lexer.lex/2:ret`, `Lexer.tokenize_trivia/1:ret` |
| `Unk0695` | 1 | `Lexer.lex_char/1:ret` |
| `Unk0696` | 1 | `Lexer.lex_parts/3:p2` |
| `Unk0697` | 1 | `Lexer.lex_parts/3:ret` |
| `Unk0698` | 1 | `Lexer.lex_string_token/1:ret` |
| `Unk0699` | 2 | `Lexer.norm_num/1:p0`, `Lexer.norm_num/1:ret` |
| `Unk0700` | 1 | `Lexer.parse_hex!/1:p0` |
| `Unk0701` | 1 | `Lexer.parse_hex!/1:ret` |
| `Unk0702` | 1 | `Lexer.punct/1:p0` |
| `Unk0703` | 1 | `Lexer.punct/1:ret` |
| `Unk0704` | 1 | `Lexer.string_token/1:p0` |
| `Unk0705` | 1 | `Lexer.string_token/1:ret` |
| `Unk0706` | 1 | `Lexer.strip_trivia/1:p0` |
| `Unk0707` | 1 | `Lexer.strip_trivia/1:ret` |
| `Unk0708` | 1 | `Lexer.take_comment/1:p0` |
| `Unk0709` | 1 | `Lexer.take_comment/1:ret` |
| `Unk0710` | 2 | `Lexer.take_hex/2:p0`, `Lexer.take_hex/3:p0` |
| `Unk0711` | 2 | `Lexer.take_hex/2:ret`, `Lexer.take_hex/3:ret` |
| `Unk0712` | 1 | `Lexer.tok_str/2:p0` |
| `Unk0713` | 1 | `Lexer.tokenize/1:p0` |
| `Unk0714` | 1 | `Lexer.tokenize/1:ret` |
| `Unk0715` | 1 | `Lexer.word/1:p0` |
| `Unk0716` | 1 | `Lexer.word/1:ret` |
| `Unk0717` | 2 | `Livebook.eval/1:p0`, `Livebook.run/2:p1` |
| `Unk0718` | 2 | `Livebook.eval/1:ret`, `Livebook.output/1:ret` |
| `Unk0719` | 1 | `Livebook.reset/0:ret` |
| `Unk0720` | 1 | `Livebook.run/2:p0` |
| `Unk0721` | 1 | `Livebook.run/2:ret` |
| `Unk0722` | 1 | `Livebook.session_pid/0:ret` |
| `Unk0723` | 4 | `Lower.add_list_elem_vars/2:p0`, `Lower.add_list_elem_vars/2:ret`, `Lower.add_var/2:p0`, `Lower.add_var/2:ret` |
| `Unk0724` | 1 | `Lower.add_list_elem_vars/2:p1` |
| `Unk0725` | 1 | `Lower.add_var/2:p1` |
| `Unk0726` | 1 | `Lower.all_pat_vars/1:ret` |
| `Unk0727` | 1 | `Lower.arm_rebinds/3:p0` |
| `Unk0728` | 3 | `Lower.arm_rebinds/3:p1`, `Lower.iso_cons_positions/1:ret`, `Lower.rust_scrut/2:p1` |
| `Unk0729` | 4 | `Lower.arm_rebinds/3:p2`, `Lower.collect_ids/2:p1`, `Lower.collect_ids/2:ret`, `Lower.used_ids/1:ret` |
| `Unk0730` | 1 | `Lower.arm_rebinds/3:ret` |
| `Unk0731` | 1 | `Lower.assoc/1:p0` |
| `Unk0732` | 1 | `Lower.assoc/1:ret` |
| `Unk0733` | 1 | `Lower.assoc_proj/2:p1` |
| `Unk0734` | 1 | `Lower.body_ast/2:p0` |
| `Unk0735` | 1 | `Lower.body_ast/2:p1` |
| `Unk0736` | 1 | `Lower.body_ast/2:ret` |
| `Unk0737` | 1 | `Lower.borrow_arg/4:p0` |
| `Unk0738` | 1 | `Lower.borrow_arg/4:p1` |
| `Unk0739` | 4 | `Lower.borrow_arg/4:p2`, `Lower.insert_borrows/3:p1`, `Lower.param_rtypes/2:p0`, `Lower.param_rtypes/2:p1` |
| `Unk0740` | 3 | `Lower.borrow_arg/4:p2`, `Lower.insert_borrows/3:p1`, `Lower.param_rtypes/2:p1` |
| `Unk0741` | 1 | `Lower.borrow_arg/4:ret` |
| `Unk0742` | 1 | `Lower.borrowed_in_pat/2:ret` |
| `Unk0743` | 1 | `Lower.borrowed_vars/2:p0` |
| `Unk0744` | 1 | `Lower.borrowed_vars/2:p1` |
| `Unk0745` | 1 | `Lower.borrowed_vars/2:ret` |
| `Unk0746` | 1 | `Lower.build_env/3:p1` |
| `Unk0747` | 1 | `Lower.build_env/3:p2` |
| `Unk0748` | 2 | `Lower.build_env/3:ret`, `Lower.check!/2:p1` |
| `Unk0749` | 2 | `Lower.build_meta/1:ret`, `Lower.ctx/4:p0` |
| `Unk0750` | 2 | `Lower.build_struct_meta/1:ret`, `Lower.ctx/4:p1` |
| `Unk0751` | 7 | `Lower.case_guard/2:p1`, `Lower.emit/2:p1`, `Lower.emit_ast/2:p1`, `Lower.emit_expr/2:p1`, `Lower.guard_kw/1:p0`, `Lower.guard_str/3:p1`, `Lower.p/3:p2` |
| `Unk0752` | 1 | `Lower.char_vars/2:p0` |
| `Unk0753` | 1 | `Lower.char_vars/2:p1` |
| `Unk0754` | 1 | `Lower.char_vars/2:ret` |
| `Unk0755` | 4 | `Lower.check!/2:p0`, `Lower.compile/4:p1`, `Lower.compile_beam/4:p1`, `Lower.compile_elixir/4:p1` |
| `Unk0756` | 1 | `Lower.check!/2:ret` |
| `Unk0757` | 1 | `Lower.collect_ids/2:p0` |
| `Unk0758` | 1 | `Lower.collect_owned_field_vars/3:p0` |
| `Unk0759` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/3:p1`, `Lower.rust_impl/3:p2`, `Lower.rust_impl_method/5:p3`, `Lower.trait_impl_block/3:p2`, `Lower.user_type?/2:p1` |
| `Unk0760` | 11 | `Lower.collect_owned_field_vars/3:p1`, `Lower.ctx/4:ret`, `Lower.ofb/3:p1`, `Lower.owned_field_binders/2:p1`, `Lower.owned_scrut?/2:p1`, `Lower.rust_const/2:p1`, `Lower.rust_fn/3:p1`, `Lower.rust_impl/3:p2`, `Lower.rust_impl_method/5:p3`, `Lower.trait_impl_block/3:p2`, `Lower.user_type?/2:p1` |
| `Unk0761` | 5 | `Lower.collect_owned_field_vars/3:p2`, `Lower.collect_owned_field_vars/3:ret`, `Lower.ofb/3:p2`, `Lower.ofb/3:ret`, `Lower.owned_field_binders/2:ret` |
| `Unk0762` | 1 | `Lower.compile/4:p2` |
| `Unk0763` | 1 | `Lower.compile/4:p3` |
| `Unk0764` | 2 | `Lower.compile/4:ret`, `Lower.compile_elixir/4:ret` |
| `Unk0765` | 1 | `Lower.compile_beam/4:p2` |
| `Unk0766` | 1 | `Lower.compile_beam/4:p3` |
| `Unk0767` | 1 | `Lower.compile_beam/4:ret` |
| `Unk0768` | 1 | `Lower.compile_elixir/4:p2` |
| `Unk0769` | 1 | `Lower.compile_elixir/4:p3` |
| `Unk0770` | 1 | `Lower.compile_module/1:p0` |
| `Unk0771` | 1 | `Lower.compile_module/1:ret` |
| `Unk0772` | 1 | `Lower.compile_module_beam/1:p0` |
| `Unk0773` | 1 | `Lower.compile_module_beam/1:ret` |
| `Unk0774` | 1 | `Lower.cons_tail_names/1:ret` |
| `Unk0775` | 3 | `Lower.const_set/1:p0`, `Lower.ex_const/2:p0`, `Lower.rust_const/2:p0` |
| `Unk0776` | 2 | `Lower.const_set/1:ret`, `Lower.ctx/4:p2` |
| `Unk0777` | 2 | `Lower.core_pat_rs/2:p1`, `Lower.pat_rs/2:p1` |
| `Unk0778` | 2 | `Lower.core_pat_vars/1:ret`, `Lower.with_ex_scope/2:p0` |
| `Unk0779` | 1 | `Lower.ctx/4:p3` |
| `Unk0780` | 2 | `Lower.deref_ids/2:p0`, `Lower.deref_ids/2:ret` |
| `Unk0781` | 1 | `Lower.deref_ids/2:p1` |
| `Unk0782` | 1 | `Lower.disp/2:p1` |
| `Unk0783` | 4 | `Lower.elixir_clauses/3:p0`, `Lower.ex_doc/2:p0`, `Lower.ex_typespec/1:p0`, `Lower.to_elixir/4:p0` |
| `Unk0784` | 2 | `Lower.elixir_clauses/3:p0`, `Lower.to_elixir/4:p0` |
| `Unk0785` | 2 | `Lower.elixir_clauses/3:p1`, `Lower.ex_const/2:p1` |
| `Unk0786` | 1 | `Lower.emit/2:ret` |
| `Unk0787` | 1 | `Lower.emit_ast/2:ret` |
| `Unk0788` | 1 | `Lower.emit_block/2:p1` |
| `Unk0789` | 1 | `Lower.emit_expr/2:ret` |
| `Unk0790` | 1 | `Lower.enum_generics/1:p0` |
| `Unk0791` | 2 | `Lower.ex_scope/0:ret`, `Lower.put_ex_scope/1:p0` |
| `Unk0792` | 1 | `Lower.ex_struct/1:p0` |
| `Unk0793` | 1 | `Lower.ex_typespec/1:p0` |
| `Unk0794` | 1 | `Lower.ex_use/1:p0` |
| `Unk0795` | 10 | `Lower.fn_all_tvars/2:p0`, `Lower.fn_all_tvars/2:ret`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/1:p0`, `Lower.parametric_used?/2:p0`, `Lower.rs_doc/2:p0`, `Lower.rust_enum/2:p0`, `Lower.rust_fn/3:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_rust/5:p0` |
| `Unk0796` | 7 | `Lower.fn_all_tvars/2:p0`, `Lower.iso_cons_positions/1:p0`, `Lower.pair_inst/1:p0`, `Lower.parametric_used?/2:p0`, `Lower.rust_fn/3:p0`, `Lower.rust_total_shim?/1:p0`, `Lower.to_rust/5:p0` |
| `Unk0797` | 2 | `Lower.fn_all_tvars/2:p1`, `Lower.pair_inst/1:ret` |
| `Unk0798` | 1 | `Lower.generic_tvar_borrow?/1:p0` |
| `Unk0799` | 1 | `Lower.guard_str/3:p0` |
| `Unk0800` | 1 | `Lower.guard_str/3:p2` |
| `Unk0801` | 1 | `Lower.impl_param/2:p0` |
| `Unk0802` | 1 | `Lower.infer_concrete_params/2:p0` |
| `Unk0803` | 1 | `Lower.infer_concrete_params/2:p1` |
| `Unk0804` | 1 | `Lower.infer_tvar_binding/1:p0` |
| `Unk0805` | 1 | `Lower.infer_tvar_binding/1:ret` |
| `Unk0806` | 1 | `Lower.list_rpat?/1:p0` |
| `Unk0807` | 1 | `Lower.module_elixir/1:p0` |
| `Unk0808` | 1 | `Lower.module_rust/1:p0` |
| `Unk0809` | 1 | `Lower.name_type/1:ret` |
| `Unk0810` | 2 | `Lower.ofb/3:p0`, `Lower.owned_field_binders/2:p0` |
| `Unk0811` | 1 | `Lower.owned_arg?/2:p0` |
| `Unk0812` | 1 | `Lower.owned_arg?/2:p1` |
| `Unk0813` | 1 | `Lower.owned_arg?/2:p1` |
| `Unk0814` | 1 | `Lower.owned_field_var?/1:p0` |
| `Unk0815` | 1 | `Lower.owned_scrut?/2:p0` |
| `Unk0816` | 1 | `Lower.owned_str_arg/1:p0` |
| `Unk0817` | 1 | `Lower.owned_str_arg/1:ret` |
| `Unk0818` | 1 | `Lower.parametric_param_map/1:ret` |
| `Unk0819` | 1 | `Lower.parametric_used?/2:p1` |
| `Unk0820` | 2 | `Lower.pascal?/1:p0`, `Lower.variant_info/2:p1` |
| `Unk0821` | 1 | `Lower.pipe_to_call/2:p0` |
| `Unk0822` | 1 | `Lower.prec/1:p0` |
| `Unk0823` | 1 | `Lower.prec/1:ret` |
| `Unk0824` | 1 | `Lower.proto_method_traits/1:ret` |
| `Unk0825` | 1 | `Lower.proto_methods/0:ret` |
| `Unk0826` | 1 | `Lower.pub_sig_type_names/1:p0` |
| `Unk0827` | 1 | `Lower.pub_sig_type_names/1:ret` |
| `Unk0828` | 1 | `Lower.put_ex_scope/1:ret` |
| `Unk0829` | 4 | `Lower.put_result_str_flags/1:p0`, `Lower.result_parts/1:p0`, `Lower.rust_ret/1:p0`, `Lower.self_subst/2:ret` |
| `Unk0830` | 1 | `Lower.put_result_str_flags/1:ret` |
| `Unk0831` | 1 | `Lower.ref_type/2:p1` |
| `Unk0832` | 1 | `Lower.resolve_consts/2:p1` |
| `Unk0833` | 1 | `Lower.resolve_rust_pats/2:p1` |
| `Unk0834` | 2 | `Lower.resolve_structs/2:p1`, `Lower.struct_pairs/4:p3` |
| `Unk0835` | 6 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_info/2:ret`, `Lower.variant_lit/2:p0`, `Lower.variant_pairs/3:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0836` | 3 | `Lower.resolve_variants/2:p1`, `Lower.variant_info/2:p0`, `Lower.variant_pairs/3:p2` |
| `Unk0837` | 1 | `Lower.result_parts/1:ret` |
| `Unk0838` | 2 | `Lower.rewrite_proto_calls/2:p0`, `Lower.rewrite_proto_calls/2:ret` |
| `Unk0839` | 1 | `Lower.rewrite_proto_calls/2:p1` |
| `Unk0840` | 1 | `Lower.rust_case/3:p1` |
| `Unk0841` | 1 | `Lower.rust_case/3:p2` |
| `Unk0842` | 1 | `Lower.rust_case/3:p2` |
| `Unk0843` | 1 | `Lower.rust_enum/2:p0` |
| `Unk0844` | 1 | `Lower.rust_enum/2:p1` |
| `Unk0845` | 1 | `Lower.rust_generics/1:p0` |
| `Unk0846` | 1 | `Lower.rust_impl_method/5:p0` |
| `Unk0847` | 1 | `Lower.rust_impl_method/5:p1` |
| `Unk0848` | 1 | `Lower.rust_lit_type/1:p0` |
| `Unk0849` | 1 | `Lower.rust_proto_body/2:p0` |
| `Unk0850` | 1 | `Lower.rust_proto_body/2:p1` |
| `Unk0851` | 1 | `Lower.rust_proto_body/2:p1` |
| `Unk0852` | 1 | `Lower.rust_proto_body/2:ret` |
| `Unk0853` | 1 | `Lower.rust_protocols/4:ret` |
| `Unk0854` | 1 | `Lower.rust_scrut/2:p0` |
| `Unk0855` | 1 | `Lower.rust_struct/2:p0` |
| `Unk0856` | 1 | `Lower.rust_struct/2:p1` |
| `Unk0857` | 1 | `Lower.rust_trait/1:p0` |
| `Unk0858` | 1 | `Lower.rust_use/1:p0` |
| `Unk0859` | 2 | `Lower.rustify_parametric/2:p0`, `Lower.rustify_parametric/2:ret` |
| `Unk0860` | 1 | `Lower.rustify_parametric/2:p1` |
| `Unk0861` | 1 | `Lower.scalar_literal?/1:p0` |
| `Unk0862` | 1 | `Lower.self_subst/2:p0` |
| `Unk0863` | 2 | `Lower.sig_param/2:p1`, `Lower.trait_params/2:p1` |
| `Unk0864` | 1 | `Lower.slice_binders/2:p0` |
| `Unk0865` | 1 | `Lower.slice_binders/2:ret` |
| `Unk0866` | 1 | `Lower.slice_elem_vars/1:ret` |
| `Unk0867` | 1 | `Lower.str_lit/1:p0` |
| `Unk0868` | 1 | `Lower.struct_pairs/4:p0` |
| `Unk0869` | 1 | `Lower.struct_pairs/4:p1` |
| `Unk0870` | 1 | `Lower.struct_pairs/4:p2` |
| `Unk0871` | 1 | `Lower.struct_pairs/4:ret` |
| `Unk0872` | 2 | `Lower.subst_assoc/2:p0`, `Lower.subst_assoc/2:ret` |
| `Unk0873` | 1 | `Lower.subst_assoc/2:p1` |
| `Unk0874` | 2 | `Lower.tail_expr/1:p0`, `Lower.tail_expr/1:ret` |
| `Unk0875` | 1 | `Lower.to_elixir/4:p2` |
| `Unk0876` | 1 | `Lower.to_elixir/4:p3` |
| `Unk0877` | 1 | `Lower.to_elixir/4:ret` |
| `Unk0878` | 1 | `Lower.to_rust/5:p1` |
| `Unk0879` | 1 | `Lower.to_rust/5:p2` |
| `Unk0880` | 1 | `Lower.to_rust/5:p3` |
| `Unk0881` | 1 | `Lower.to_rust/5:p4` |
| `Unk0882` | 1 | `Lower.to_rust/5:ret` |
| `Unk0883` | 1 | `Lower.tvar_name?/1:p0` |
| `Unk0884` | 1 | `Lower.type_idents/1:p0` |
| `Unk0885` | 1 | `Lower.type_idents/1:ret` |
| `Unk0886` | 1 | `Lower.type_param_tvars/1:p0` |
| `Unk0887` | 1 | `Lower.type_param_tvars/1:ret` |
| `Unk0888` | 1 | `Lower.user_type?/2:p0` |
| `Unk0889` | 2 | `Lower.variant_lit/2:p1`, `Lower.variant_pairs/3:ret` |
| `Unk0890` | 1 | `Lower.variant_pairs/3:p1` |
| `Unk0891` | 2 | `Lower.widen_char_arith/2:p1`, `Lower.wrap_char/2:p1` |
| `Unk0892` | 1 | `Lower.with_chain_rs/3:p0` |
| `Unk0893` | 1 | `Lower.with_chain_rs/3:p1` |
| `Unk0894` | 4 | `Macro.binders_here/1:p0`, `Macro.collect_binders/1:p0`, `Macro.freshen/2:p0`, `Macro.rename/2:p0` |
| `Unk0895` | 2 | `Macro.binders_here/1:ret`, `Macro.collect_binders/1:ret` |
| `Unk0896` | 1 | `Macro.build_env/1:p0` |
| `Unk0897` | 1 | `Macro.check_portable!/2:p0` |
| `Unk0898` | 1 | `Macro.check_portable!/2:ret` |
| `Unk0899` | 1 | `Macro.expand/3:p2` |
| `Unk0900` | 1 | `Macro.freshen/2:p1` |
| `Unk0901` | 1 | `Macro.rename/2:p1` |
| `Unk0902` | 1 | `Macro.substitute/2:p1` |
| `Unk0903` | 1 | `Opaque.do_erase/2:p0` |
| `Unk0904` | 6 | `Opaque.do_erase/2:p1`, `Opaque.erase_ctx/1:ret`, `Opaque.erase_func/2:p1`, `Opaque.erase_mod/2:p1`, `Opaque.erase_struct/2:p1`, `Opaque.erase_type/2:p1` |
| `Unk0905` | 1 | `Opaque.erase_clause/3:p0` |
| `Unk0906` | 1 | `Opaque.erase_clause/3:p1` |
| `Unk0907` | 1 | `Opaque.erase_clause/3:p2` |
| `Unk0908` | 1 | `Opaque.erase_const/2:p0` |
| `Unk0909` | 1 | `Opaque.erase_const/2:p1` |
| `Unk0910` | 3 | `Opaque.erase_ctx/1:p0`, `Opaque.opaques/1:p0`, `Opaque.opaques/1:ret` |
| `Unk0911` | 1 | `Opaque.erase_func/2:p0` |
| `Unk0912` | 1 | `Opaque.erase_mod/2:p0` |
| `Unk0913` | 1 | `Opaque.erase_struct/2:p0` |
| `Unk0914` | 1 | `Opaque.erase_type/2:p0` |
| `Unk0915` | 1 | `Opaque.erase_variant/2:p0` |
| `Unk0916` | 1 | `Opaque.erase_variant/2:p1` |
| `Unk0917` | 1 | `Opaque.opaques/1:p0` |
| `Unk0918` | 4 | `Opaque.strip/3:p0`, `Opaque.strip/3:ret`, `Opaque.strip_into/3:p0`, `Opaque.strip_into/3:ret` |
| `Unk0919` | 2 | `Opaque.strip/3:p1`, `Opaque.strip_into/3:p1` |
| `Unk0920` | 4 | `Opaque.subst/2:p0`, `Opaque.subst/2:ret`, `Opaque.subst_fix/4:p0`, `Opaque.subst_fix/4:ret` |
| `Unk0921` | 2 | `Opaque.subst/2:p1`, `Opaque.subst_fix/4:p1` |
| `Unk0922` | 1 | `Opaque.subst_fix/4:p2` |
| `Unk0923` | 2 | `PatternLower.lower/2:ret`, `PatternLower.lower_list/3:ret` |
| `Unk0924` | 1 | `PatternLower.lower_clause/2:p0` |
| `Unk0925` | 1 | `PatternLower.lower_many/2:ret` |
| `Unk0926` | 1 | `PortAnalysis.analyze/1:p0` |
| `Unk0927` | 1 | `PortAnalysis.analyze/1:ret` |
| `Unk0928` | 3 | `PortAnalysis.case_arm_sets/1:p0`, `PortAnalysis.clause_head_sets/1:p0`, `PortAnalysis.dispatch_sets/1:p0` |
| `Unk0929` | 2 | `PortAnalysis.case_arm_sets/1:ret`, `PortAnalysis.clause_head_sets/1:ret` |
| `Unk0930` | 2 | `PortAnalysis.cluster_sums/1:p0`, `PortAnalysis.dispatch_sets/1:ret` |
| `Unk0931` | 1 | `PortAnalysis.cluster_sums/1:ret` |
| `Unk0932` | 1 | `PortAnalysis.collect_errors/2:p0` |
| `Unk0933` | 2 | `PortAnalysis.collect_errors/2:p1`, `PortAnalysis.collect_errors/2:ret` |
| `Unk0934` | 1 | `PortAnalysis.collect_groups/1:p0` |
| `Unk0935` | 1 | `PortAnalysis.collect_groups/1:ret` |
| `Unk0936` | 1 | `PortAnalysis.collect_structs/2:p0` |
| `Unk0937` | 2 | `PortAnalysis.collect_structs/2:p1`, `PortAnalysis.collect_structs/2:ret` |
| `Unk0938` | 1 | `PortAnalysis.error_proposal/1:p0` |
| `Unk0939` | 1 | `PortAnalysis.error_proposal/1:ret` |
| `Unk0940` | 1 | `PortAnalysis.error_shape/1:p0` |
| `Unk0941` | 1 | `PortAnalysis.error_shape/1:ret` |
| `Unk0942` | 6 | `PortAnalysis.errors_section/1:p0`, `PortAnalysis.holes_section/1:p0`, `PortAnalysis.sigs_section/1:p0`, `PortAnalysis.summary_section/1:p0`, `PortAnalysis.sums_section/1:p0`, `PortAnalysis.to_markdown/1:p0` |
| `Unk0943` | 1 | `PortAnalysis.head_name_pats/1:p0` |
| `Unk0944` | 1 | `PortAnalysis.head_name_pats/1:ret` |
| `Unk0945` | 2 | `PortAnalysis.module_name/1:p0`, `PortAnalysis.module_report/3:p1` |
| `Unk0946` | 1 | `PortAnalysis.module_report/3:p0` |
| `Unk0947` | 2 | `PortAnalysis.module_report/3:p2`, `Transpile.inferred/1:p0` |
| `Unk0948` | 1 | `PortAnalysis.module_report/3:ret` |
| `Unk0949` | 1 | `PortAnalysis.needs_review?/1:p0` |
| `Unk0950` | 1 | `PortAnalysis.param_name_index/1:p0` |
| `Unk0951` | 1 | `PortAnalysis.param_name_index/1:ret` |
| `Unk0952` | 1 | `PortAnalysis.parse/1:p0` |
| `Unk0953` | 1 | `PortAnalysis.parse/1:ret` |
| `Unk0954` | 1 | `PortAnalysis.pascal/1:p0` |
| `Unk0955` | 1 | `PortAnalysis.pascal/1:ret` |
| `Unk0956` | 1 | `PortAnalysis.pattern_structs/1:p0` |
| `Unk0957` | 1 | `PortAnalysis.pattern_structs/1:ret` |
| `Unk0958` | 1 | `PortAnalysis.reach_note/1:p0` |
| `Unk0959` | 1 | `PortAnalysis.reach_note/1:ret` |
| `Unk0960` | 1 | `PortAnalysis.short/1:p0` |
| `Unk0961` | 1 | `PortAnalysis.src_of/2:p0` |
| `Unk0962` | 1 | `PortAnalysis.src_of/2:p1` |
| `Unk0963` | 1 | `PortAnalysis.src_of/2:ret` |
| `Unk0964` | 1 | `PortAnalysis.to_markdown/1:ret` |
| `Unk0965` | 3 | `Pratt.after_paren/2:p0`, `Pratt.after_paren/2:ret`, `Pratt.lambda_ahead?/1:p0` |
| `Unk0966` | 6 | `Pratt.assoc/1:p0`, `Pratt.bp/1:p0`, `Pratt.level/1:p0`, `Pratt.opinfo/1:p0`, `Pratt.peek_infix/1:ret`, `Pratt.same_level_root?/2:p1` |
| `Unk0967` | 1 | `Pratt.assoc/1:ret` |
| `Unk0968` | 1 | `Pratt.bp/1:ret` |
| `Unk0969` | 2 | `Pratt.climb/3:p0`, `Pratt.same_level_root?/2:p0` |
| `Unk0970` | 2 | `Pratt.climb/3:ret`, `Pratt.parse_expr/2:ret` |
| `Unk0971` | 1 | `Pratt.collect_dots/2:p0` |
| `Unk0972` | 2 | `Pratt.collect_dots/2:ret`, `Pratt.parse_path/1:ret` |
| `Unk0973` | 2 | `Pratt.desugar_prop/2:p0`, `Pratt.desugar_propagation/1:p0` |
| `Unk0974` | 2 | `Pratt.desugar_prop/2:ret`, `Pratt.desugar_propagation/1:ret` |
| `Unk0975` | 1 | `Pratt.finish_arg/2:p0` |
| `Unk0976` | 2 | `Pratt.finish_arg/2:ret`, `Pratt.parse_args/1:ret` |
| `Unk0977` | 2 | `Pratt.here/1:p0`, `Pratt.tok_desc/1:p0` |
| `Unk0978` | 1 | `Pratt.int_of/1:p0` |
| `Unk0979` | 1 | `Pratt.int_of/1:ret` |
| `Unk0980` | 1 | `Pratt.level/1:ret` |
| `Unk0981` | 1 | `Pratt.opinfo/1:ret` |
| `Unk0982` | 1 | `Pratt.parse_arms/2:p1` |
| `Unk0983` | 1 | `Pratt.parse_arms/2:ret` |
| `Unk0984` | 1 | `Pratt.parse_block/1:ret` |
| `Unk0985` | 11 | `Pratt.parse_capture/1:ret`, `Pratt.parse_case/1:ret`, `Pratt.parse_if/1:ret`, `Pratt.parse_lambda/1:ret`, `Pratt.parse_list/2:ret`, `Pratt.parse_map/2:ret`, `Pratt.parse_postfix/2:ret`, `Pratt.parse_prefix/1:ret`, `Pratt.parse_primary/1:ret`, `Pratt.parse_tuple/2:ret`, `Pratt.parse_with/1:ret` |
| `Unk0986` | 1 | `Pratt.parse_list/2:p1` |
| `Unk0987` | 1 | `Pratt.parse_map/2:p1` |
| `Unk0988` | 1 | `Pratt.parse_param/1:ret` |
| `Unk0989` | 1 | `Pratt.parse_params/1:ret` |
| `Unk0990` | 4 | `Pratt.parse_pat/1:ret`, `Pratt.parse_pat_list/2:ret`, `Pratt.parse_pat_map/2:ret`, `Pratt.parse_pat_tuple/2:ret` |
| `Unk0991` | 1 | `Pratt.parse_pat_args/2:p1` |
| `Unk0992` | 1 | `Pratt.parse_pat_args/2:ret` |
| `Unk0993` | 1 | `Pratt.parse_pat_fields/2:p1` |
| `Unk0994` | 1 | `Pratt.parse_pat_fields/2:ret` |
| `Unk0995` | 1 | `Pratt.parse_pat_list/2:p1` |
| `Unk0996` | 1 | `Pratt.parse_pat_map/2:p1` |
| `Unk0997` | 1 | `Pratt.parse_pat_tuple/2:p1` |
| `Unk0998` | 3 | `Pratt.parse_pats/1:ret`, `Pratt.parse_pats/2:p1`, `Pratt.parse_pats/2:ret` |
| `Unk0999` | 2 | `Pratt.parse_postfix/2:p0`, `Pratt.str_interp/1:ret` |
| `Unk1000` | 1 | `Pratt.parse_stmt/1:ret` |
| `Unk1001` | 1 | `Pratt.parse_stmts/2:p1` |
| `Unk1002` | 1 | `Pratt.parse_stmts/2:ret` |
| `Unk1003` | 1 | `Pratt.parse_tuple/2:p1` |
| `Unk1004` | 1 | `Pratt.parse_type/1:ret` |
| `Unk1005` | 1 | `Pratt.parse_type_args/2:p1` |
| `Unk1006` | 1 | `Pratt.parse_type_args/2:ret` |
| `Unk1007` | 1 | `Pratt.parse_with_clauses/2:p1` |
| `Unk1008` | 1 | `Pratt.parse_with_clauses/2:ret` |
| `Unk1009` | 1 | `Pratt.pascal?/1:p0` |
| `Unk1010` | 1 | `Pratt.sexpr_pat/1:p0` |
| `Unk1011` | 1 | `Pratt.sexpr_stmt/1:p0` |
| `Unk1012` | 1 | `Pratt.str_interp/1:p0` |
| `Unk1013` | 1 | `Prim.names/0:ret` |
| `Unk1014` | 1 | `Prim.overflow_ops/0:ret` |
| `Unk1015` | 1 | `Protocol.check_assoc!/2:ret` |
| `Unk1016` | 1 | `Protocol.check_impl/3:p0` |
| `Unk1017` | 3 | `Protocol.check_impl/3:p1`, `Protocol.expand/5:p0`, `Protocol.impl_methods/2:p1` |
| `Unk1018` | 4 | `Protocol.check_impl/3:p2`, `Protocol.check_no_overlap/3:p1`, `Protocol.guard_for!/3:p2`, `Protocol.registry/2:ret` |
| `Unk1019` | 1 | `Protocol.check_impl/3:ret` |
| `Unk1020` | 3 | `Protocol.check_no_overlap/3:p0`, `Protocol.expand/5:p1`, `Protocol.impl_methods/2:p0` |
| `Unk1021` | 2 | `Protocol.check_no_overlap/3:p2`, `Protocol.runtime_dispatch_target?/1:p0` |
| `Unk1022` | 1 | `Protocol.check_no_overlap/3:ret` |
| `Unk1023` | 1 | `Protocol.dispatcher/4:p0` |
| `Unk1024` | 1 | `Protocol.dispatcher/4:p1` |
| `Unk1025` | 1 | `Protocol.dispatcher/4:p2` |
| `Unk1026` | 1 | `Protocol.dispatcher/4:p3` |
| `Unk1027` | 1 | `Protocol.dispatcher/4:ret` |
| `Unk1028` | 1 | `Protocol.dispatcher_params/2:p0` |
| `Unk1029` | 1 | `Protocol.dispatcher_params/2:p1` |
| `Unk1030` | 1 | `Protocol.dispatcher_params/2:ret` |
| `Unk1031` | 1 | `Protocol.guard_for!/3:p0` |
| `Unk1032` | 1 | `Protocol.guard_for!/3:p1` |
| `Unk1033` | 1 | `Protocol.guard_for!/3:ret` |
| `Unk1034` | 1 | `Protocol.mangle/3:p0` |
| `Unk1035` | 1 | `Protocol.mangle/3:p1` |
| `Unk1036` | 1 | `Protocol.mangle/3:p2` |
| `Unk1037` | 1 | `Protocol.param_type/1:p0` |
| `Unk1038` | 1 | `Protocol.param_type/1:ret` |
| `Unk1039` | 1 | `Protocol.registry/2:p0` |
| `Unk1040` | 1 | `Protocol.registry/2:p1` |
| `Unk1041` | 1 | `Protocol.struct_guard/1:p0` |
| `Unk1042` | 1 | `Protocol.subst_self/2:p0` |
| `Unk1043` | 1 | `Protocol.subst_self/2:p1` |
| `Unk1044` | 1 | `Protocol.subst_self/2:ret` |
| `Unk1045` | 1 | `Protocol.sum_guard/1:p0` |
| `Unk1046` | 1 | `Protocol.tag_disjunction/2:p0` |
| `Unk1047` | 1 | `Protocol.tag_disjunction/2:p1` |
| `Unk1048` | 1 | `Range.check/3:p0` |
| `Unk1049` | 1 | `Range.check/3:p1` |
| `Unk1050` | 1 | `Range.lit/1:p0` |
| `Unk1051` | 1 | `Reach.all_emittable?/2:p0` |
| `Unk1052` | 1 | `Reach.all_emittable?/2:p1` |
| `Unk1053` | 1 | `Reach.all_emittable?/2:ret` |
| `Unk1054` | 7 | `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0` |
| `Unk1055` | 7 | `Reach.all_funcs/1:p0`, `Reach.all_funcs/1:ret`, `Reach.analyze/1:p0`, `Reach.check_contracts/2:p0`, `Reach.parametric_ctx/2:p0`, `Reach.parametric_ctx/2:p1`, `Reach.symbol_lint!/1:p0` |
| `Unk1056` | 1 | `Reach.analyze/1:ret` |
| `Unk1057` | 1 | `Reach.atom_prim_blocker/0:ret` |
| `Unk1058` | 1 | `Reach.bare_atom_blocker/0:ret` |
| `Unk1059` | 5 | `Reach.build_default/0:ret`, `Reach.check_contracts/2:p1`, `Reach.gate!/2:p1`, `Reach.validate_default/1:p0`, `Reach.validate_default/1:ret` |
| `Unk1060` | 1 | `Reach.builder_tail_ok?/2:p0` |
| `Unk1061` | 2 | `Reach.builder_tail_ok?/2:p1`, `Reach.tail_calls_generic?/2:p1` |
| `Unk1062` | 1 | `Reach.check_contracts/2:ret` |
| `Unk1063` | 3 | `Reach.classify/3:p1`, `Reach.scan/3:p1`, `Reach.scan_func/3:p1` |
| `Unk1064` | 5 | `Reach.classify/3:p2`, `Reach.classify/3:ret`, `Reach.scan/3:p2`, `Reach.scan/3:ret`, `Reach.scan_func/3:ret` |
| `Unk1065` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk1066` | 2 | `Reach.collect_ctors/2:p1`, `Reach.parametric_constructions/2:p1` |
| `Unk1067` | 2 | `Reach.collect_ctors/2:ret`, `Reach.parametric_constructions/2:ret` |
| `Unk1068` | 1 | `Reach.conc_erl?/2:p1` |
| `Unk1069` | 1 | `Reach.contract_message/1:p0` |
| `Unk1070` | 1 | `Reach.core/2:p0` |
| `Unk1071` | 1 | `Reach.core/2:p1` |
| `Unk1072` | 1 | `Reach.core/2:p1` |
| `Unk1073` | 1 | `Reach.ctor_aligned?/2:p0` |
| `Unk1074` | 1 | `Reach.ctor_aligned?/2:p1` |
| `Unk1075` | 1 | `Reach.ctor_aligned?/2:p1` |
| `Unk1076` | 2 | `Reach.deep/1:p0`, `Reach.find_atom_ordering/1:p0` |
| `Unk1077` | 3 | `Reach.deep/1:ret`, `Reach.find_atom_ordering/1:ret`, `Reach.func_symbol_violations/1:ret` |
| `Unk1078` | 1 | `Reach.emittable_parametric?/1:p0` |
| `Unk1079` | 1 | `Reach.emittable_parametric?/1:ret` |
| `Unk1080` | 1 | `Reach.ffi/2:p0` |
| `Unk1081` | 1 | `Reach.ffi/2:p1` |
| `Unk1082` | 1 | `Reach.ffi/2:ret` |
| `Unk1083` | 1 | `Reach.fixpoint/2:p0` |
| `Unk1084` | 2 | `Reach.fixpoint/2:p1`, `Reach.fixpoint/2:ret` |
| `Unk1085` | 1 | `Reach.fn_type_blocker/0:ret` |
| `Unk1086` | 1 | `Reach.func_symbol_violations/1:p0` |
| `Unk1087` | 2 | `Reach.gate!/1:ret`, `Reach.gate!/2:ret` |
| `Unk1088` | 1 | `Reach.int_blocker/0:ret` |
| `Unk1089` | 1 | `Reach.js_wide_int?/1:p0` |
| `Unk1090` | 1 | `Reach.mix_default/0:ret` |
| `Unk1091` | 1 | `Reach.parametric_blocker/0:ret` |
| `Unk1092` | 1 | `Reach.parametric_constructions/2:p0` |
| `Unk1093` | 3 | `Reach.parametric_ctx/2:ret`, `Reach.parametric_rs_ok?/2:p1`, `Reach.scan_func/3:p2` |
| `Unk1094` | 3 | `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0` |
| `Unk1095` | 3 | `Reach.parametric_rs_ok?/2:p0`, `Reach.scan_func/3:p0`, `Reach.sig_uses_fn_type?/1:p0` |
| `Unk1096` | 1 | `Reach.parametric_type?/1:p0` |
| `Unk1097` | 1 | `Reach.pascal?/1:p0` |
| `Unk1098` | 1 | `Reach.pascal?/1:ret` |
| `Unk1099` | 1 | `Reach.ref_blocker/0:ret` |
| `Unk1100` | 1 | `Reach.result_value_blocker/0:ret` |
| `Unk1101` | 1 | `Reach.sig_idents/1:p0` |
| `Unk1102` | 1 | `Reach.sig_idents/1:p0` |
| `Unk1103` | 1 | `Reach.sig_idents/1:ret` |
| `Unk1104` | 1 | `Reach.symbol_lint!/1:ret` |
| `Unk1105` | 1 | `Reach.tail_calls_generic?/2:p0` |
| `Unk1106` | 1 | `Reach.targets/0:ret` |
| `Unk1107` | 1 | `Reach.tvar?/1:p0` |
| `Unk1108` | 1 | `Reach.tvar?/1:ret` |
| `Unk1109` | 2 | `Reach.type_has_tvar?/1:p0`, `Reach.type_idents/1:p0` |
| `Unk1110` | 1 | `Reach.type_idents/1:ret` |
| `Unk1111` | 1 | `Reach.uses_parametric?/2:p0` |
| `Unk1112` | 1 | `Reach.uses_parametric?/2:p1` |
| `Unk1113` | 1 | `Reach.uses_parametric?/2:ret` |
| `Unk1114` | 1 | `Reach.wide_prim_blocker/0:ret` |
| `Unk1115` | 1 | `Reach.width_blocker/0:ret` |
| `Unk1116` | 1 | `Repl.accumulate_line/2:p1` |
| `Unk1117` | 2 | `Repl.accumulate_line/2:ret`, `Repl.submit_or_continue/2:ret` |
| `Unk1118` | 3 | `Repl.balanced?/1:p0`, `Repl.declaration?/1:p0`, `Repl.scan_count/2:p0` |
| `Unk1119` | 1 | `Repl.bind_env/2:p0` |
| `Unk1120` | 5 | `Repl.bind_with_type/4:p3`, `Repl.infer_or_unknown/3:ret`, `Repl.safe_infer/3:ret`, `Repl.safe_infer_input/3:ret`, `Repl.type_of/2:ret` |
| `Unk1121` | 4 | `Repl.bind_with_type/4:ret`, `Repl.eval_bind/4:ret`, `Repl.eval_expr/2:ret`, `Repl.eval_stmt/2:ret` |
| `Unk1122` | 1 | `Repl.candidate_pool/2:p0` |
| `Unk1123` | 1 | `Repl.candidate_pool/2:ret` |
| `Unk1124` | 2 | `Repl.common_prefix/2:p0`, `Repl.common_prefix/3:p0` |
| `Unk1125` | 2 | `Repl.common_prefix/2:p1`, `Repl.common_prefix/3:p1` |
| `Unk1126` | 2 | `Repl.complete/2:p0`, `Repl.trailing_token/1:p0` |
| `Unk1127` | 1 | `Repl.complete/2:p1` |
| `Unk1128` | 1 | `Repl.complete/2:ret` |
| `Unk1129` | 1 | `Repl.continuation/2:p0` |
| `Unk1130` | 1 | `Repl.continuation/2:p1` |
| `Unk1131` | 1 | `Repl.decl_names/1:ret` |
| `Unk1132` | 1 | `Repl.describe/1:p0` |
| `Unk1133` | 1 | `Repl.describe/1:ret` |
| `Unk1134` | 1 | `Repl.eval/2:p0` |
| `Unk1135` | 1 | `Repl.eval/2:p1` |
| `Unk1136` | 1 | `Repl.eval/2:ret` |
| `Unk1137` | 1 | `Repl.eval_decl/2:ret` |
| `Unk1138` | 1 | `Repl.flush_entries/1:p0` |
| `Unk1139` | 1 | `Repl.flush_entries/1:ret` |
| `Unk1140` | 1 | `Repl.info/1:ret` |
| `Unk1141` | 2 | `Repl.longest_common_prefix/1:p0`, `Repl.longest_common_prefix/1:ret` |
| `Unk1142` | 4 | `Repl.program/3:p0`, `Repl.run/4:p2`, `Repl.safe_decl/1:p0`, `Repl.units_src/1:p0` |
| `Unk1143` | 2 | `Repl.program/3:p1`, `Repl.run/4:p1` |
| `Unk1144` | 1 | `Repl.render/1:p0` |
| `Unk1145` | 1 | `Repl.run/4:ret` |
| `Unk1146` | 1 | `Repl.safe_parse_body/1:ret` |
| `Unk1147` | 1 | `Repl.scan_count/2:p1` |
| `Unk1148` | 1 | `Repl.scan_count/2:ret` |
| `Unk1149` | 1 | `Repl.split_entries/1:p0` |
| `Unk1150` | 1 | `Repl.split_entries/1:ret` |
| `Unk1151` | 1 | `Repl.submit_or_continue/2:p0` |
| `Unk1152` | 1 | `Repl.type_of/2:p0` |
| `Unk1153` | 1 | `Repl.vocabulary/0:ret` |
| `Unk1154` | 1 | `SelfHost.badge/1:p0` |
| `Unk1155` | 1 | `SelfHost.composition/0:ret` |
| `Unk1156` | 1 | `SelfHost.count/1:p0` |
| `Unk1157` | 1 | `SelfHost.evidence/1:p0` |
| `Unk1158` | 1 | `SelfHost.evidence_files/0:ret` |
| `Unk1159` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk1160` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk1161` | 1 | `SelfHost.external_host_calls/1:p0` |
| `Unk1162` | 1 | `SelfHost.external_host_calls/1:ret` |
| `Unk1163` | 1 | `SelfHost.ffi_in_file/1:p0` |
| `Unk1164` | 1 | `SelfHost.ffi_in_file/1:ret` |
| `Unk1165` | 1 | `SelfHost.ffi_ledger/0:ret` |
| `Unk1166` | 1 | `SelfHost.passes/0:ret` |
| `Unk1167` | 1 | `SelfHost.percent/0:ret` |
| `Unk1168` | 1 | `SelfHost.selfhost_files/0:ret` |
| `Unk1169` | 1 | `SelfHost.selfhost_module_names/0:ret` |
| `Unk1170` | 1 | `SelfHost.sibling_compose_call?/2:p0` |
| `Unk1171` | 1 | `SelfHost.sibling_compose_call?/2:p1` |
| `Unk1172` | 1 | `SelfHost.stages/0:ret` |
| `Unk1173` | 1 | `SelfHost.status_markdown/1:p0` |
| `Unk1174` | 1 | `Shadow.ded_bind/5:p0` |
| `Unk1175` | 3 | `Shadow.ded_bind/5:p2`, `Shadow.ded_expr/3:p0`, `Shadow.ded_expr/3:ret` |
| `Unk1176` | 1 | `Shadow.ded_bind/5:p3` |
| `Unk1177` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1178` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1179` | 4 | `Shadow.ded_bind/5:p4`, `Shadow.ded_block/4:p3`, `Shadow.ded_expr/3:p2`, `Shadow.dedup/3:p2` |
| `Unk1180` | 1 | `Shadow.ded_bind/5:ret` |
| `Unk1181` | 2 | `Shadow.ded_block/4:p0`, `Shadow.dedup/3:p0` |
| `Unk1182` | 1 | `Shadow.ded_block/4:p1` |
| `Unk1183` | 1 | `Shadow.ded_block/4:p2` |
| `Unk1184` | 1 | `Shadow.ded_expr/3:p1` |
| `Unk1185` | 1 | `Shadow.pat_var_names/1:ret` |
| `Unk1186` | 1 | `Test.default_mod/1:ret` |
| `Unk1187` | 1 | `Test.run/2:p1` |
| `Unk1188` | 1 | `Test.run/2:ret` |
| `Unk1189` | 1 | `Test.run_one/2:p0` |
| `Unk1190` | 1 | `Test.run_one/2:p1` |
| `Unk1191` | 1 | `Test.run_one/2:ret` |
| `Unk1192` | 1 | `Test.rust/1:ret` |
| `Unk1193` | 1 | `Test.tests/1:ret` |
| `Unk1194` | 1 | `Tour.build_cell/1:p0` |
| `Unk1195` | 1 | `Tour.build_cell/1:ret` |
| `Unk1196` | 1 | `Tour.build_reach_example/1:p0` |
| `Unk1197` | 1 | `Tour.build_reach_example/1:ret` |
| `Unk1198` | 1 | `Tour.elixir_module/1:ret` |
| `Unk1199` | 2 | `Tour.encode/2:p0`, `Tour.encode_string/1:p0` |
| `Unk1200` | 1 | `Tour.generate/0:ret` |
| `Unk1201` | 1 | `Tour.reach_map/1:ret` |
| `Unk1202` | 1 | `Tour.to_json/0:ret` |
| `Unk1203` | 1 | `Transpile.add_clause/2:p0` |
| `Unk1204` | 1 | `Transpile.add_clause/2:p1` |
| `Unk1205` | 1 | `Transpile.add_clause/2:ret` |
| `Unk1206` | 2 | `Transpile.block_stmts/1:p0`, `Transpile.block_stmts/1:ret` |
| `Unk1207` | 1 | `Transpile.build_clause/2:p0` |
| `Unk1208` | 1 | `Transpile.build_clause/2:p1` |
| `Unk1209` | 2 | `Transpile.build_clause/2:ret`, `Transpile.same_group?/3:p2` |
| `Unk1210` | 1 | `Transpile.case_arm/1:p0` |
| `Unk1211` | 3 | `Transpile.classify/1:p0`, `Transpile.def_groups/1:p0`, `Transpile.render_items/2:p0` |
| `Unk1212` | 1 | `Transpile.classify/1:ret` |
| `Unk1213` | 4 | `Transpile.close_group/2:p0`, `Transpile.close_group/2:p1`, `Transpile.close_group/2:ret`, `Transpile.def_groups/1:ret` |
| `Unk1214` | 1 | `Transpile.escape/1:p0` |
| `Unk1215` | 1 | `Transpile.escape/1:ret` |
| `Unk1216` | 1 | `Transpile.escape_lit/1:p0` |
| `Unk1217` | 1 | `Transpile.escape_lit/1:ret` |
| `Unk1218` | 1 | `Transpile.flush/2:p0` |
| `Unk1219` | 2 | `Transpile.flush/2:p1`, `Transpile.render_items/2:p1` |
| `Unk1220` | 1 | `Transpile.hole_sig?/1:p0` |
| `Unk1221` | 2 | `Transpile.infer_program/1:p0`, `Transpile.infer_sigs/1:p0` |
| `Unk1222` | 2 | `Transpile.infer_program/1:ret`, `Transpile.inferred/1:ret` |
| `Unk1223` | 1 | `Transpile.infer_report/1:p0` |
| `Unk1224` | 1 | `Transpile.infer_report/1:ret` |
| `Unk1225` | 1 | `Transpile.infer_sigs/1:ret` |
| `Unk1226` | 1 | `Transpile.max_placeholder/1:p0` |
| `Unk1227` | 4 | `Transpile.mod_str/1:p0`, `Transpile.short_name/1:p0`, `Transpile.snippet/1:p0`, `Transpile.var_name/1:p0` |
| `Unk1228` | 1 | `Transpile.module_groups/1:p0` |
| `Unk1229` | 1 | `Transpile.module_groups/1:ret` |
| `Unk1230` | 1 | `Transpile.moduledoc_lines/1:p0` |
| `Unk1231` | 1 | `Transpile.name_str/1:p0` |
| `Unk1232` | 1 | `Transpile.name_str/1:ret` |
| `Unk1233` | 1 | `Transpile.new_group/3:p0` |
| `Unk1234` | 1 | `Transpile.new_group/3:p1` |
| `Unk1235` | 1 | `Transpile.new_group/3:p2` |
| `Unk1236` | 1 | `Transpile.new_group/3:ret` |
| `Unk1237` | 1 | `Transpile.one_line/1:p0` |
| `Unk1238` | 1 | `Transpile.one_line/1:ret` |
| `Unk1239` | 1 | `Transpile.prime_xmod/1:p0` |
| `Unk1240` | 1 | `Transpile.prime_xmod/1:ret` |
| `Unk1241` | 1 | `Transpile.rank/1:p0` |
| `Unk1242` | 1 | `Transpile.rank/1:ret` |
| `Unk1243` | 1 | `Transpile.render_clause/2:p1` |
| `Unk1244` | 1 | `Transpile.same_group?/3:p0` |
| `Unk1245` | 1 | `Transpile.same_group?/3:p1` |
| `Unk1246` | 1 | `Transpile.sibling_module?/2:p0` |
| `Unk1247` | 1 | `Transpile.sibling_module?/2:p1` |
| `Unk1248` | 1 | `Transpile.simple?/1:p0` |
| `Unk1249` | 1 | `Transpile.stdlib_map/0:ret` |
| `Unk1250` | 1 | `Transpile.string_part/1:p0` |
| `Unk1251` | 1 | `Transpile.string_part/1:ret` |
| `Unk1252` | 1 | `Transpile.string_parts/1:p0` |
| `Unk1253` | 1 | `Transpile.string_parts/1:ret` |
| `Unk1254` | 2 | `Transpile.subst_ph/2:p0`, `Transpile.subst_ph/2:ret` |
| `Unk1255` | 1 | `Transpile.subst_ph/2:p1` |
| `Unk1256` | 1 | `Transpile.toplevel/3:p0` |
| `Unk1257` | 1 | `Transpile.toplevel/3:p1` |
| `Unk1258` | 2 | `Transpile.transpile/2:p0`, `Transpile.transpile_with_stats/2:p0` |
| `Unk1259` | 1 | `Transpile.transpile/2:p1` |
| `Unk1260` | 1 | `Transpile.transpile/2:ret` |
| `Unk1261` | 1 | `Transpile.transpile_with_stats/2:p1` |
| `Unk1262` | 1 | `Transpile.transpile_with_stats/2:ret` |
| `Unk1263` | 1 | `Transpile.underscore_var/1:p0` |
| `Unk1264` | 1 | `Transpile.var?/1:p0` |

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

