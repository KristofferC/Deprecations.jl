using Tokenize.Tokens: STRING, GREATER, LESS, GREATER_EQ, GREATER_THAN_OR_EQUAL_TO, LESS_EQ, LESS_THAN_OR_EQUAL_TO
using CSTParser: MacroName
begin
    struct ObsoleteVersionCheck; vers; end
    register(ObsoleteVersionCheck, Deprecation(
        "This version check is for a version of julia that is no longer supported by this package",
        "julia",
        typemin(VersionNumber), typemin(VersionNumber), typemax(VersionNumber)
    ))
    ObsoleteVersionCheck() = ObsoleteVersionCheck(Pkg.Reqs.parse(IOBuffer("julia 0.6"))["julia"])

    const comparisons = Dict(
         GREATER                  => >,
         LESS                     => <,
         GREATER_EQ               => >=,
         GREATER_THAN_OR_EQUAL_TO => ≥,
         LESS_EQ                  => <=,
         LESS_THAN_OR_EQUAL_TO    => ≤,
         #= TODO:
         EQEQ                     => ==,
         EQEQEQ                   => ===,
         IDENTICAL_TO             => ≡,
         NOT_EQ                   => !=,
         NOT_EQUAL_TO             => ≠,
         NOT_IS                   => !==
         =#)


    function detect_ver_arguments(VERSION_arg, v_arg)
        isa(VERSION_arg, CSTParser.IDENTIFIER) || return nothing
        VERSION_arg.val == "VERSION" || return nothing
        isa(v_arg, EXPR{CSTParser.x_Str}) || return nothing
        isa(v_arg.args[1], CSTParser.IDENTIFIER) || return nothing
        (isa(v_arg.args[2], CSTParser.LITERAL) && v_arg.args[1].kind == STRING) || return nothing
        v_arg.args[1].val == "v" || return nothing
        VersionNumber(v_arg.args[2].val)
    end

    function dep_for_vers(::Type{ObsoleteVersionCheck}, vers)
        ObsoleteVersionCheck(vers["julia"])
    end

    is_identifier(x) = false
    is_identifier(x::CSTParser.IDENTIFIER, id) = x.val == id
    is_identifier(x::OverlayNode, id) = is_identifier(x.expr, id)

    function is_macroname(x::OverlayNode{MacroCall}, name)
        c = children(x)[1]
        isexpr(c, MacroName) || return false
        return is_identifier(children(c)[2], name)
    end

    match(ObsoleteVersionCheck, CSTParser.If) do x
        dep, expr, resolutions, context = x
        replace_expr = expr
        comparison = children(expr)[2]
        isexpr(comparison, CSTParser.BinaryOpCall) || return
        # TODO:
        #isexpr(children(comparison)[2], CSTParser.OPERATOR{6,op,false} where op) || return
        comparison = comparison.expr
        opc = comparison.args[2].kind
        haskey(comparisons, opc) || return
        # Also applies in @static context, but not necessarily in other macro contexts
        if context.in_macrocall
            context.top_macrocall == parent(expr) || return
            is_macroname(context.top_macrocall, "static") || return
            replace_expr = context.top_macrocall
        end
        r1 = detect_ver_arguments(comparison.args[1], comparison.args[3])
        if r1 !== nothing
            f = comparisons[opc]
            alwaystrue = all(interval->(f(interval.lower, r1) && f(interval.upper, r1)), dep.vers.intervals)
            alwaysfalse = all(interval->(!f(interval.lower, r1) && !f(interval.upper, r1)), dep.vers.intervals)
            @assert !(alwaystrue && alwaysfalse)
            alwaystrue && resolve_inline_body(resolutions, expr, replace_expr)
            alwaysfalse && resolve_delete_expr(resolutions, expr, replace_expr)
            return
        end
        r2 = detect_ver_arguments(comparison.args[3], comparison.args[1])
        if r2 !== nothing
            f = comparisons[opc]
            alwaystrue = all(interval->(f(interval.lower, r2) && f(interval.upper, r2)), dep.vers.intervals)
            alwaysfalse = all(interval->(!f(interval.lower, r2) && !f(interval.upper, r2)), dep.vers.intervals)
            @assert !(alwaystrue && alwaysfalse)
            alwaystrue && resolve_inline_body(resolutions, expr, replace_expr)
            alwaysfalse && resolve_delete_expr(resolutions, expr, replace_expr)
        end
    end
end
