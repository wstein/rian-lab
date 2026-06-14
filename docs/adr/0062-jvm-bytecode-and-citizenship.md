# ADR-0062 — JVM citizenship: from a Kotlin transpiler to direct bytecode

**Status:** Proposed
**Implemented:** partial — rung B shipped (`Rian.JVM.to_jar`, `mix rian.jar` — `lib/rian/jvm.ex`, `lib/mix/tasks/rian.jar.ex`); rung C (direct JVM bytecode, no Kotlin source) not
**Refs:** ADR-0031 (the BEAM precedent — reuse the runtime, emit forms, not source text), ADR-0049 §3a (the JVM emitter is Kotlin), ADR-0041 (target model / per-target representation), ADR-0057 (concurrency & FFI are native-per-target), ADR-0050 (typed core IR — one IR, many emitters), ADR-0026 (don't fork the host)
**Owners:** Maya Lin (emitters) · Arthur Pendelton (compilers/bytecode) · Elena Rostova (interop seam) · Samir Patel (conformance) · Kira Neri (honesty/determinism) · Rachel Okafor (PM)

## Context

`Rian.JVM` (ADR-0049 §3a) emits **Kotlin source text**. To run, that text is handed to `kotlinc`.
That is exactly where the **BEAM** backend *started* — transpiling to Elixir source — before ADR-0031
concluded it "wasn't good enough to be a true Erlang citizen" and pivoted to emitting **Erlang
abstract forms → `:compile.forms` → a loadable `.beam` in memory**, with no source text and no second
language in the middle. Being a *citizen* of the BEAM (Dialyzer specs, line-tracked stack traces,
ecosystem tooling "for free") followed from emitting the platform's own loadable artifact directly.

The question this ADR settles: **what does the same move look like for the JVM**, so Rian becomes a
JVM citizen on the footing of Clojure/Scala/Kotlin (their own compilers emit bytecode directly; none
route through Java source)?

Two facts shape the answer, and one of them is the crux:

1. **The Rian compiler is BEAM-hosted (Elixir).** `:compile.forms` works in-process *because the
   compiler runs on the BEAM*. There is **no in-process JVM equivalent** available to an Elixir
   process. So "direct bytecode" cannot simply mirror the BEAM mechanism — the platform's compiler
   isn't in the same VM. (Contrast Clojure, whose compiler runs *on* the JVM and calls ASM in-process.)
2. **JDK 24 finalized `java.lang.classfile`** (JEP 484) — a *standard* class-file builder API, no ASM
   dependency. The dev/CI image here is JDK 25, so it is available.

## Decision

Adopt a **three-rung ladder**, and explicitly do **not** jump straight to bytecode. Each rung is a
distinct, shippable increment; later rungs are gated on Rian's own self-hosting progress.

### Rung B — a runnable JAR via the host compiler *(shipped 2026-06-13)*

`Rian.JVM.to_jar/3` + `mix rian.jar` emit Kotlin and invoke `kotlinc -include-runtime`, producing a
`java -jar`-runnable artifact (optionally with a generated `main`). This is the **transpiler rung** —
honest about depending on a second language and its compiler, exactly as the BEAM's interim
Elixir-source emitter was. It delivers a real artifact today and unblocks "does it run on a real JVM"
verification. It is **not** citizenship.

### Rung C — direct JVM bytecode (the ADR-0031 analog)

Emit `.class`/`.jar` with **no source step**. Because the compiler is BEAM-hosted (fact 1), there are
three candidate mechanisms; the choice is the substance of this rung:

- **C1 — `classfile` helper (recommended first form).** A small JVM-side helper takes a Rian Core-IR
  description (the typed core, ADR-0050, serialized e.g. as JSON) and uses `java.lang.classfile`
  (fact 2) to build bytecode. Out-of-process, but it is the platform's *own* standard "IR → bytecode"
  API — the nearest moral equivalent of `:compile.forms`. No ASM, no Kotlin runtime bundled.
- **C2 — classfile bytes from Elixir.** Write the constant pool / methods / **stack-map frames**
  directly from the Elixir compiler (the format is fully documented). Maximal control, no JVM helper,
  but it re-implements a large surface the JDK already gives us — likely not worth it before C1.
- **C3 — in-process, post-self-hosting.** Once Rian self-hosts *on the JVM*, a JVM-hosted Rian
  compiler calls `java.lang.classfile` in-process — the genuine Clojure-shaped end state. This is the
  natural terminus, and it ties rung C to the self-hosting roadmap (SELFHOST.md) rather than being a
  parallel effort.

**Direction:** pursue **C1** when rung C is scheduled (standard API, no bundled runtime, no
duplicated format work); treat **C3** as the long-term terminus that falls out of self-hosting; keep
**C2** only as a fallback if out-of-process proves unacceptable.

### Citizenship is more than bytecode

Bytecode is necessary, not sufficient. A JVM *citizen* (the rung-C contract, beyond emitting bytes):

1. **Java interop, both directions.** Calling Java *from* Rian needs a **JVM-native FFI lane** — host
   FFI is `:ex`-pinned today (ADR-0057), so the JVM gets its own native-per-target FFI, the same way
   each target owns its concurrency. Being called *from* Java needs **Java-callable signatures**
   (named classes, methods with JVM descriptors, ideally implementing declared Java interfaces).
2. **Packaging** — `.jar` + `Main-Class` manifest (rung B already), then Maven/Gradle coordinates.
3. **Debuggability** — `LineNumberTable` + `SourceFile` attributes so stack traces and the JVM
   debugger map to Rian source (the line-tracked property `Rian.Beam` already gives the BEAM).
4. **Runtime/representation** — either a tiny Rian runtime for sums/lists/maps, or a continued mapping
   onto JVM-native types (rung-B already does `Int64→Long`, sums→`sealed`/`data class`); settle the
   value-type story (boxing vs. Valhalla value classes) per ADR-0049's open item.

## Rationale

- **Replays a decision the project already made well.** ADR-0031's "emit the platform's loadable
  artifact, not source" is the proven path to citizenship; this ADR is that decision re-applied to a
  platform whose compiler happens not to share our VM.
- **Sequencing beats a leap.** Rung B is a day; rung C is a quarter and only *truly* citizen-grade
  alongside interop + self-hosting. Shipping B now, recording C as a gated decision, avoids a
  half-built bytecode emitter that misses the interop half of "citizen."
- **No fork, one IR.** Every rung consumes the typed core IR (ADR-0050); rung C adds a new *backend
  form*, not a new front-end — consistent with how BEAM/Rust/JS/JVM-Kotlin already share the core.

## Consequences

- **Now:** rung B is shipped (`Rian.JVM.to_jar/3`, `mix rian.jar`); `:jvm` is a first-class Reach
  target (ADR-0058). The Kotlin source emitter remains the inspection/debug view, exactly as the
  Elixir-text emitter remains one for the BEAM.
- **Later (gated on scheduling + self-hosting):** rung C via C1, then the interop/signature/debug-info
  contract above. Each is its own ADR-amending increment with `kotlinc`/`java`-or-`classfile`
  verification, kept **non-blocking in CI** until JVM is promoted from Tier 2 (ADR-0049).

## Open items

- **C1 wire format** — how the Core IR crosses to the `classfile` helper (JSON schema vs. a compact
  form); error/line propagation back.
- **Interop surface** — the Rian syntax for calling Java and for declaring Java-visible exports
  (a JVM FFI lane per ADR-0057); which Java types map to which Rian types at the boundary.
- **Value types** — boxing vs. Project Valhalla value classes for `Int*`/opaque/range types
  (ADR-0049/0043/0036), once they exist on the JVM.
- **Promotion criteria** — what advances JVM from Tier 2 to Tier 1 (ADR-0049 open item), e.g. rung C +
  interop + all tour examples compiling and running.
