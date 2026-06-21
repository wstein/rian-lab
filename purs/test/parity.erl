%% Cross-language parity harness for the PureScript port (ADR-0084). Generalized over
%% modules: reads purs/test/fixtures/parity.fixtures (generated from the Elixir reference
%% by gen_fixtures.exs), re-runs each input through the purerl build, and asserts the
%% canonical serialization matches the reference byte-for-byte. The canonical forms here
%% MUST mirror Canon in gen_fixtures.exs (lowercase hex of UTF-8 bytes).
-module(parity).
-export([run/1]).

run([Path]) ->
    {ok, Bin} = file:read_file(Path),
    Lines = [L || L <- binary:split(Bin, <<"\n">>, [global]), L =/= <<>>],
    Results = [check_line(L) || L <- Lines],
    Fails = [R || R = {fail, _, _, _, _} <- Results],
    Total = length(Results),
    case Fails of
        [] ->
            io:format("\x{2713} parity: ~p/~p records match~n", [Total, Total]),
            halt(0);
        _ ->
            lists:foreach(
                fun({fail, Stream, Src, Exp, Got}) ->
                    io:format(
                        "\x{2717} [~s] src=~s~n   expected ~s~n   got      ~s~n",
                        [Stream, Src, Exp, Got]
                    )
                end,
                Fails
            ),
            io:format("~p/~p records FAILED~n", [length(Fails), Total]),
            halt(1)
    end.

check_line(Line) ->
    [Stream, SrcHex, Exp] = binary:split(Line, <<"\t">>, [global]),
    try run_stream(Stream, unhex(SrcHex)) of
        Exp -> ok;
        Got -> {fail, Stream, SrcHex, Exp, Got}
    catch
        _:Reason -> {fail, Stream, SrcHex, Exp, iolist_to_binary(io_lib:format("CRASH ~p", [Reason]))}
    end.

%% Rian.Lexer (canon = the token stream; detok = hex of the rendered string)
run_stream(<<"tok">>, Src) -> canon('rian_lexer@ps':tokenize(Src));
run_stream(<<"expr">>, Src) -> canon('rian_lexer@ps':exprTokens(Src));
run_stream(<<"triv">>, Src) -> canon('rian_lexer@ps':tokenizeTrivia(Src));
run_stream(<<"detok">>, Src) ->
    hexbin('rian_lexer@ps':detokenize('rian_lexer@ps':tokenize(Src)));
run_stream(<<"detok;">>, Src) ->
    hexbin('rian_lexer@ps':detokenizeWith(<<";">>, 'rian_lexer@ps':tokenize(Src)));
%% Rian.TypeStr (canon = a `,`-joined list of hex strings, or hex for normalize)
run_stream(<<"tsc">>, Src) -> strlist('rian_typeStr@ps':splitTopCommas(Src));
run_stream(<<"tsp">>, Src) -> strlist('rian_typeStr@ps':splitTopPipes(Src));
run_stream(<<"tsn">>, Src) -> hexbin('rian_typeStr@ps':normalize(Src));
%% Rian.Pratt (canon = hex of the parse_sexpr rendering — the reference's own oracle)
run_stream(<<"psx">>, Src) -> hexbin('rian_pratt@ps':parseSexpr(Src));
%% Rian.Core (canon = hex of coreSexpr over lexer→Pratt→from_expr)
run_stream(<<"cor">>, Src) -> hexbin('rian_core@ps':fromSource(Src));
%% Rian.Prim (canon = hex of sexpr(normalize(parse)) — matches the reference's parse_sexpr)
run_stream(<<"prm">>, Src) -> hexbin('rian_prim@ps':normalizeSexpr(Src));
%% Rian.Decl (canon = hex of the Prog serializer over tokenize→split_decls→assemble)
run_stream(<<"dcl">>, Src) -> hexbin('rian_decl@ps':declSexpr(Src));
%% Rian.Range (canon = hex of coreSexpr after the Name.of(n) rewrite over a fixed table)
run_stream(<<"rng">>, Src) -> hexbin('rian_range@ps':expandOfSexpr(Src));
%% Rian.PatternLower (canon = hex of the lowered checker patterns + guard, per scenario)
run_stream(<<"plw">>, Src) -> hexbin('rian_exhaustiveness@ps':plowSexpr(Src));
%% Rian.Exhaustiveness (canon = hex of the analyze result over a fixed scenario table)
run_stream(<<"exh">>, Src) -> hexbin('rian_exhaustiveness@ps':analyzeSexpr(Src));
%% Rian.Decl protocol/impl (canon = hex of the protocols + impl-decls IR only, synthesis-free)
run_stream(<<"prc">>, Src) -> hexbin('rian_decl@ps':protoImplSexpr(Src));
%% Rian.Prelude (canon = hex of `with_prelude(user_types)` — the built-in Option prepended)
run_stream(<<"prl">>, Src) -> hexbin('rian_prelude@ps':withPreludeSexpr(Src));
%% Rian.Exhaustiveness.program_env (canon = hex of the env's ctors table from a source)
run_stream(<<"pge">>, Src) -> hexbin('rian_exhaustiveness@ps':programEnvSexpr(Src));
%% Rian.External (canon = hex of each func's @external specs rendered against its params)
run_stream(<<"ext">>, Src) -> hexbin('rian_external@ps':externalRenderSexpr(Src));
%% Rian.Coherence (canon = hex of `rule:proto:type;…` for the protocol/impl coherence violations)
run_stream(<<"coh">>, Src) -> hexbin('rian_coherence@ps':violationsSexpr(Src));
%% Rian.Coherence under @targets(:rs) — the runtime-discriminator exemption (Rust-only scope)
run_stream(<<"cohrs">>, Src) -> hexbin('rian_coherence@ps':violationsRsSexpr(Src));
%% Rian.Check type algebra (canon = hex of the unify/join result over a `t;;u` pair)
run_stream(<<"uni">>, Src) -> hexbin('rian_check@ps':unifySexpr(Src));
run_stream(<<"joi">>, Src) -> hexbin('rian_check@ps':joinSexpr(Src));
%% Rian.Check.infer over the expression core (canon = the inferred type under a fixed env)
run_stream(<<"inf">>, Src) -> hexbin('rian_check@ps':inferSexpr(Src));
%% Rian.Check.infer over a function body (parseBody: ;-separated binds + value)
run_stream(<<"bdy">>, Src) -> hexbin('rian_check@ps':inferBodySexpr(Src));
%% Rian.Builtins host/stdlib signature table (canon = known?/ret/poly_sig for a mod;fun;arity)
run_stream(<<"bui">>, Src) -> hexbin('rian_builtins@ps':builtinSexpr(Src));
%% Rian.Shadow capture-avoiding := rename (canon = the deduped block's coreSexpr)
run_stream(<<"shd">>, Src) -> hexbin('rian_shadow@ps':dedupSexpr(Src));
%% Rian.Macro expand (canon = coreSexpr of a call expanded under the fixed macro env)
run_stream(<<"mac">>, Src) -> hexbin('rian_macro@ps':expandSexpr(Src));
%% Rian.Protocol expand (canon = serialized dispatcher / impl_* DefMaps)
run_stream(<<"pex">>, Src) -> hexbin('rian_protocol@ps':expandSexpr(Src)).

%% canonical serialization of the purerl token terms (must equal Canon in the generator).
%% A PureScript `Array` is a stdlib `array` under purerl, hence array:to_list.
canon(Toks) -> iolist_to_binary(lists:join("|", [tok(T) || T <- array:to_list(Toks)])).

tok({tNl}) -> "nl";
tok({tLparen}) -> "lparen";
tok({tRparen}) -> "rparen";
tok({tLbracket}) -> "lbracket";
tok({tRbracket}) -> "rbracket";
tok({tLbrace}) -> "lbrace";
tok({tRbrace}) -> "rbrace";
tok({tMapopen}) -> "mapopen";
tok({tBitopen}) -> "bitopen";
tok({tBitclose}) -> "bitclose";
tok({tComma}) -> "comma";
tok({tSemi}) -> "semi";
tok({tStr, B}) -> ["str:", hex(B)];
tok({tChar, N}) -> ["char:", integer_to_list(N)];
tok({tNum, B}) -> ["num:", hex(B)];
tok({tOp, B}) -> ["op:", hex(B)];
tok({tKw, B}) -> ["kw:", hex(B)];
tok({tId, B}) -> ["id:", hex(B)];
tok({tAnnot, B}) -> ["annot:", hex(B)];
tok({tComment, B}) -> ["comment:", hex(B)];
tok({tHeredoc, B}) -> ["heredoc:", hex(B)];
tok({tIstr, Parts}) -> ["istr:", lists:join(",", [part(P) || P <- array:to_list(Parts)])].

part({lit, B}) -> ["lit=", hex(B)];
part({hole, B}) -> ["hole=", hex(B)].

%% a Vec(String) result → a `,`-joined list of hex'd elements.
strlist(Arr) -> iolist_to_binary(lists:join(",", [hex(B) || B <- array:to_list(Arr)])).

hex(B) -> [io_lib:format("~2.16.0b", [X]) || X <- binary_to_list(B)].

hexbin(Str) -> iolist_to_binary(hex(Str)).

unhex(H) -> <<<<(list_to_integer([A, B], 16))>> || <<A, B>> <= H>>.
