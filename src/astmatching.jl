using Tokenize: Tokens

global _EXPR = 0
function is_template_expr(expr)
    isexpr(expr, CSTParser.UnarySyntaxOpCall) || return (false, nothing, false)
    global _EXPR = expr
    if isexpr(children(expr)[2], OPERATOR, Tokens.DDDOT)
        isexpr(children(expr)[1], CSTParser.UnarySyntaxOpCall) || return (false, nothing, false)
        isexpr(children(children(expr)[1])[1], OPERATOR, Tokens.EX_OR) || return (false, nothing, false)
        return (true, Symbol( children(children(expr)[1])[2].val), true)
    end
    isexpr(children(expr)[1], OPERATOR, Tokens.EX_OR) || return (false, nothing, false)
    return (true, Symbol(children(expr)[2].val), false)
end

function matches_template(x, y)
    if typeof(x) != typeof(y)
     #  println("Returning false because $(typeof(x)) != $(typeof(y))")
        return false
    end
    if typeof(x) == CSTParser.IDENTIFIER
        return strip(x.val) == strip(y.val)
    end
    if typeof(x) in (CSTParser.KEYWORD, CSTParser.PUNCTUATION, CSTParser.OPERATOR)
        if x.kind != y.kind
          # println("Returning false because $(x) != $(y)")
        end
        return x.kind == y.kind
    end
    #println("MAAATCHED")
    #println(x)
    #println(y)
    true
end

matches_template(x::OverlayNode, y::OverlayNode) = matches_template(x.expr, y.expr)

function matches_template2(x, y)
    if (typeof(x) == BinarySyntaxOpCall && typeof(y) == CSTParser.WhereOpCall) ||
            (typeof(x) == CSTParser.WhereOpCall && typeof(y) == BinarySyntaxOpCall)
        return true
    end
    if typeof(x) != typeof(y)
        return false
    end
    if typeof(x) in (CSTParser.KEYWORD, CSTParser.PUNCTUATION, CSTParser.OPERATOR)
        if x.kind != y.kind
            return false
        end
    end
    true
end
matches_template2(x::OverlayNode, y::OverlayNode) = matches_template2(x.expr, y.expr)

struct EmptyMatch
    parent
end


global A, B
function match_parameters(template, match, result)
    if typeof(template.expr) == CSTParser.PUNCTUATION
  #      @show template.expr.kind, match.expr.kind
    end
    !matches_template2(template, match) && error("Shouldn't have gotten here $template, $match")
    j = 1
    for (i,x) in enumerate(children(template))
        if j > length(children(match)) && i == length(children(template))
            ret, sym, slurp = is_template_expr(x)
            if ret
                result[sym] = (false, (EmptyMatch(match),))
                break
            end
        end
        y = children(match)[j]
        ret, sym, slurp = is_template_expr(x)
        if typeof(x.expr) == CSTParser.PUNCTUATION
            x.expr.kind, y.expr.kind, j
        else
            typeof(x.expr), typeof(y.expr), j
        end
         if !ret && matches_template(x, y)
            ok = match_parameters(x, y, result)
            ok || return ok
            j += 1
        else
            without_trailing_ws = is_last_leaf(x)
            if ret
                if !slurp
                    result[sym] =  (without_trailing_ws, (y,))
                    j += 1
                else
                    matched_exprs = Any[]
                    if i == length(children(template))
                        result[sym] = (without_trailing_ws, children(match)[j:end])
                        j = length(children(match))
                    else
                        nextx = children(template)[i + 1]
                        startj = j
                        while j <= length(children(match)) && !matches_template2(nextx, children(match)[j])
              #              println("Pushing...", typeof(nextx), typeof(children(match)[j]))
                            push!(matched_exprs, children(match)[j])
                            j += 1
                        end
             #           println("Ending...", typeof(nextx), typeof(children(match)[j]))
                        global A= nextx
                        global B = children(match)[j]
                        result[sym] = (without_trailing_ws, isempty(matched_exprs) ? (EmptyMatch(children(match)[j]),) : matched_exprs)
                    end
                end
            else
                return false
            end
        end
    end
    if j < length(children(match))
        return false
    end
    # Compare to other version
    
    #@show template, match
    return true
end

function leaf_is_template_expr(x)
    isempty(children(x)) && return (false, nothing, false)
    ret, sym, slurp = is_template_expr(x)
    ret || return leaf_is_template_expr(children(x)[1])
    ret, sym, slurp
end
is_template_expr(x::OverlayNode) = is_template_expr(x.expr)
leaf_is_template_expr(x::OverlayNode) = leaf_is_template_expr(x.expr)

function text(o::OverlayNode, leading_trivia = true, trailing_trivia = true)
    o.buffer[1 + ((leading_trivia ? first(o.fullspan) : first(o.span)):(trailing_trivia ? last(o.fullspan) : last(o.span)))]
end

function trailing_ws(o::OverlayNode)
    o.buffer[1 + (1+last(o.span):last(o.fullspan))]
end

function leading_ws(o::OverlayNode)
    o.buffer[1 + (first(o.fullspan):first(o.fullspan)-1)]
end

span_text(o::OverlayNode) = text(o, false, false)
fullspan_text(o::OverlayNode) = text(o, true, true)

using AbstractTrees: prevsibling, nextsibling

function prev_node_ws(node)
    while true
        sib = prevsibling(node)
        sib != nothing && return trailing_ws(sib)
        node.parent == nothing && return ""
        node = node.parent
    end
end

function next_is_template(node)
    while true
        sib = nextsibling(node)
        sib != nothing && return leaf_is_template_expr(sib)
        node.parent == nothing && return (false, nothing, false)
        node = node.parent
    end
end

function is_last_leaf(node)
    while true
        sib = nextsibling(node)
        sib != nothing && return false
        node.parent == nothing && return true
        node = node.parent
    end
end

function reassemble(out::IO, replacement, matches)
    if isempty(children(replacement))
        ret, sym, _ = next_is_template(replacement)
        skip_trailing_ws = ret && endswith(String(sym), "!")
        rt = text(replacement, true, !skip_trailing_ws)
        write(out, rt)
    end
    i = 1
    while i <= length(children(replacement))
        x = children(replacement)[i]
        ret, sym, slurp = is_template_expr(x)
        if !ret
            reassemble(out, x, matches)
        else
            endswith(String(sym), "!") && (sym = Symbol(String(sym)[1:end-1]))
            exprs = matches[sym]
            write(out, prev_node_ws(first(exprs)))
            for expr in exprs
                write(out, fullspan_text(expr))
            end
        end
        i += 1
    end
    replacement
end

function skip_next_ws(c)
    ret, sym, _ = next_is_template(c)
    ret && endswith(String(sym), "!")
end

function reassemble_tree(replacement, matches, parent = nothing)
    if isempty(children(replacement))
        return skip_next_ws(replacement) ?
            TriviaReplacementNode(parent, replacement, leading_ws(replacement), "") :
            replacement
    end
    ret = ChildReplacementNode(parent, Any[], replacement)
    for (i, x) in enumerate(children(replacement))
        istemp, sym, slurp = is_template_expr(x)
        if !istemp
            push!(ret.children, reassemble_tree(x, matches, ret))
        else
            use_template_trailing_ws = true
            if endswith(String(sym), "!")
                use_template_trailing_ws = false
                sym = Symbol(String(sym)[1:end-1])
            end
            no_trailing_ws, exprs = matches[sym]
            expr = first(exprs)
            if typeof(expr) == EmptyMatch
                push!(ret.children, TriviaInsertionNode(prev_node_ws(expr.parent)))
                continue
            end
            push!(ret.children, TriviaReplacementNode(ret, expr,
                string(prev_node_ws(expr), leading_ws(expr)),
                    skip_next_ws(x) ? "" :
                    string(no_trailing_ws ? "" : trailing_ws(expr),
                          use_template_trailing_ws ? trailing_ws(x) : "")))
            append!(ret.children, exprs[2:end])
        end
    end
    ret
end

function inspect_matches(result, text)
    for (sym, ((pre_ws, offset), expr)) in result
        print(STDOUT, sym, ": ")
        span = isa(expr, Array) ? (first(first(expr).fullspan):last(last(expr).fullspan)) : expr.fullspan
        show(STDOUT, text[1 + span])
        println(STDOUT)
    end
end
