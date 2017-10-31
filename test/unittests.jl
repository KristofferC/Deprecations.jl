using Base.Test
import Deprecations
import Tokenize.Tokens
import CSTParser: KEYWORD
##########
# isexpr #
##########


expr = CSTParser.parse("if true elseif false end")
elseif_arg = expr.args[4]

@test Deprecations.isexpr(elseif_arg, KEYWORD{Tokens.ELSEIF})

let
    x = CSTParser.parse("foo")
    y = CSTParser.parse(":foo")
    @test !Deprecations.matches_template(x, y)
end

let
    x = CSTParser.parse("foo")
    y = CSTParser.parse("foo")
    @test Deprecations.matches_template(x, y)
end

let
    x = CSTParser.parse("\$name")
    @test Deprecations.is_template_expr(x) == (true, :name, false)

    x = CSTParser.parse("using name...")
    @test Deprecations.is_template_expr(x) == (false, nothing, false)

    x = CSTParser.parse("\$BODY...")
    @test Deprecations.is_template_expr(x) == (true, :BODY, true)

    x = CSTParser.parse("::Type{\$NAME{\$T...}}")
    @test Deprecations.is_template_expr(x) == (false, nothing, false)
end


# What does is_template_expr do?
# Returns, ret_slo

# leaf_is_template_expr?


