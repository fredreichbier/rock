import structs/ArrayList
import ../frontend/Token
import Expression, Visitor, Type, Node, FunctionCall, OperatorDecl,
       Import, Module, FunctionCall, ClassDecl, CoverDecl, AddressOf,
       ArrayAccess, VariableAccess, Cast, NullLiteral, PropertyDecl,
       Tuple
import tinker/[Trail, Resolver, Response, Errors]

OpType: enum {
    add        /*  +  */
    sub        /*  -  */
    mul        /*  *  */
    div        /*  /  */
    mod        /*  %  */
    rshift     /*  >> */
    lshift     /*  << */
    bOr        /*  |  */
    bXor       /*  ^  */
    bAnd       /*  &  */

    ass        /*  =  */
    addAss     /*  += */
    subAss     /*  -= */
    mulAss     /*  *= */
    divAss     /*  /= */
    rshiftAss  /* >>= */
    lshiftAss  /* <<= */
    bOrAss     /*  |= */
    bXorAss    /*  ^= */
    bAndAss    /*  &= */

    or         /*  || */
    and        /*  && */
}

opTypeRepr := static ["no-op",
        "+",
        "-",
        "*",
        "/",
        "%",
        ">>",
        "<<",
        "|",
        "^",
        "&",

        "=",
        "+=",
        "-=",
        "*=",
        "/=",
        ">>=",
        "<<=",
        "|=",
        "^=",
        "&=",

        "||",
        "&&"]

BinaryOp: class extends Expression {

    left, right: Expression
    type: OpType

    init: func ~binaryOp (=left, =right, =type, .token) {
        super(token)
    }

    clone: func -> This {
        new(left clone(), right clone(), type, token)
    }

    isAssign: func -> Bool { (type >= OpType ass) && (type <= OpType bAndAss) }

    isBooleanOp: func -> Bool { type == OpType or || type == OpType and }

    accept: func (visitor: Visitor) {
        visitor visitBinaryOp(this)
    }

    // It's just an access, it has no side-effects whatsoever
    hasSideEffects : func -> Bool { !isAssign() }

    // that's probably not right (haha)
    getType: func -> Type { left getType() }
    getLeft:  func -> Expression { left  }
    getRight: func -> Expression { right }

    toString: func -> String {
        return left toString() + " " + opTypeRepr[type] + " " + right toString()
    }

    unwrapAssign: func (trail: Trail, res: Resolver) -> Bool {

        if(!isAssign()) return false

        innerType := type - (OpType addAss - OpType add)
        inner := BinaryOp new(left, right, innerType, token)
        right = inner
        type = OpType ass

        return true

    }

    resolve: func (trail: Trail, res: Resolver) -> Response {

        trail push(this)

        {
            response := left resolve(trail, res)
            if(!response ok()) {
                trail pop(this)
                return response
            }
        }

        {
            response := right resolve(trail, res)
            if(!response ok()) {
                trail pop(this)
                return response
            }
        }

        trail pop(this)

        {
            response := resolveOverload(trail, res)
            if(!response ok()) return response
        }

        if(type == OpType ass) {
            if(left getType() == null || !left isResolved()) {
                res wholeAgain(this, "left type is unresolved"); return Responses OK
            }
            if(right getType() == null || !right isResolved()) {
                res wholeAgain(this, "right type is unresolved"); return Responses OK
            }

            // Left side is a property access? Replace myself with a setter call.
            // Make sure we're not in the getter/setter.
            if(left instanceOf?(VariableAccess) && left as VariableAccess ref instanceOf?(PropertyDecl)) {
                leftProperty := left as VariableAccess ref as PropertyDecl
                if(leftProperty inOuterSpace(trail)) {
                    fCall := FunctionCall new(left as VariableAccess expr, leftProperty getSetterName(), token)
                    fCall getArguments() add(right)
                    trail peek() replace(this, fCall)
                    return Responses OK
                } else {
                    // We're in a setter/getter. This means the property is not virtual.
                    leftProperty setVirtual(false)
                }
            }

            cast : Cast = null
            realRight := right
            if(right instanceOf?(Cast)) {
                cast = right as Cast
                realRight = cast inner
            }

            // if we're an assignment from a generic return value
            // we need to set the returnArg to left and disappear! =)
            if(realRight instanceOf?(FunctionCall)) {
                fCall := realRight as FunctionCall
                fDecl := fCall getRef()
                if(!fDecl || !fDecl getReturnType() isResolved()) {
                    res wholeAgain(this, "Need more info on fDecl")
                    return Responses OK
                }

                if(!fDecl getReturnArgs() empty?()) {
                    fCall setReturnArg(fDecl getReturnType() isGeneric() ? left getGenericOperand() : left)
                    trail peek() replace(this, fCall)
                    res wholeAgain(this, "just replaced with fCall and set ourselves as returnArg")
                    return Responses OK
                }
            }

            if(isGeneric()) {
                sizeAcc: VariableAccess
                if(!right getType() isGeneric()) {
                    sizeAcc = VariableAccess new(VariableAccess new(right getType(), token), "size", token)
                } else {
                    sizeAcc = VariableAccess new(VariableAccess new(left getType(), token), "size", token)
                }


                fCall := FunctionCall new("memcpy", token)

                fCall args add(left  getGenericOperand())
                fCall args add(right getGenericOperand())
                fCall args add(sizeAcc)
                result := trail peek() replace(this, fCall)

                if(!result) {
                    if(res fatal) res throwError(CouldntReplace new(token, this, fCall, trail))
                }

                res wholeAgain(this, "Replaced ourselves, need to tidy up")
                return Responses OK
            }
        }

        // In case of a expression like `expr attribute += value` where `attribute`
        // is a property, we need to unwrap this to `expr attribute = expr attribute + value`.
        if(isAssign() && left instanceOf?(VariableAccess)) {
            if(left getType() == null || !left isResolved()) {
                res wholeAgain(this, "left type is unresolved"); return Responses OK
            }
            if(right getType() == null || !right isResolved()) {
                res wholeAgain(this, "right type is unresolved"); return Responses OK
            }
            // are we in a +=, *=, /=, ... operator? unwrap myself.
            if(left as VariableAccess ref instanceOf?(PropertyDecl)) {
                leftProperty := left as VariableAccess ref as PropertyDecl
                if(leftProperty inOuterSpace(trail)) {
                    // only outside of get/set.
                    unwrapAssign(trail, res)
                    trail push(this)
                    right resolve(trail, res)
                    trail pop(this)
                }
            }
        }

        if(type == OpType ass && left instanceOf?(Tuple) && right instanceOf?(Tuple)) {
            t1 := left as Tuple
            t2 := right as Tuple

            if(t1 elements size() != t2 elements size()) {
                res throwError(InvalidOperatorUse new(token, "Invalid assignment between operands of type %s and %s\n" format(
                    left getType() toString(), right getType() toString())))
                return Responses OK
            }

            for(i in 0..t1 elements size()) {
                ass := BinaryOp
                child := new(t1 elements[i], t2 elements[i], type, token)

                if(i == t1 elements size() - 1) {
                    // last? replace
                    if(!trail peek() replace(this, child)) {
                        res throwError(CouldntReplace new(token, this, child, trail))
                    }
                } else {
                    // otherwise, add before
                    if(!trail addBeforeInScope(this, child)) {
                        res throwError(CouldntAddBeforeInScope new(token, this, child, trail))
                    }
                }
            }
        }

        if(!isLegal(res)) {
            if(res fatal) {
                res throwError(InvalidOperatorUse new(token, "Invalid use of operator %s between operands of type %s and %s\n" format(
                    opTypeRepr[type], left getType() toString(), right getType() toString())))
                return Responses OK
            }
            res wholeAgain(this, "Illegal use, looping in hope.")
        }

        return Responses OK

    }

    isGeneric: func -> Bool {
        (left  getType() isGeneric() && left  getType() pointerLevel() == 0) ||
        (right getType() isGeneric() && right getType() pointerLevel() == 0)
    }

    isLegal: func (res: Resolver) -> Bool {
        if(left getType() == null || left getType() getRef() == null || right getType() == null || right getType() getRef() == null) {
            // must resolve first
            res wholeAgain(this, "Unresolved types, looping to determine legitness")
            return true
        }
        if(left getType() getName() == "Pointer" || right getType() getName() == "Pointer") {
            // pointer arithmetic: you can add, subtract, and assign pointers
            return (type == OpType add ||
                    type == OpType sub ||
                    type == OpType addAss ||
                    type == OpType subAss ||
                    type == OpType ass)
        }
        if(left getType() getRef() instanceOf?(ClassDecl) ||
           right getType() getRef() instanceOf?(ClassDecl)) {
            // you can only assign - all others must be overloaded
            return (type == OpType ass || isBooleanOp())
        }
        if((left  getType() getRef() instanceOf?(CoverDecl) &&
            left  getType() getRef() as CoverDecl getFromType() == null) ||
           (right getType() getRef() instanceOf?(CoverDecl) &&
            right getType() getRef() as CoverDecl getFromType() == null)) {
            // you can only assign structs, others must be overloaded
            return (type == OpType ass)
        }
        return true
    }

    resolveOverload: func (trail: Trail, res: Resolver) -> Response {

        // so here's the plan: we give each operator overload a score
        // depending on how well it fits our requirements (types)

        bestScore := 0
        candidate : OperatorDecl = null

        reqType := trail peek() getRequiredType()

        for(opDecl in trail module() getOperators()) {
            score := getScore(opDecl, reqType)
            //printf("Considering %s for %s, score = %d\n", opDecl toString(), toString(), score)
            if(score == -1) { res wholeAgain(this, "score of op == -1 !!"); return Responses OK }
            if(score > bestScore) {
                bestScore = score
                candidate = opDecl
            }
        }

        for(imp in trail module() getAllImports()) {
            module := imp getModule()
            for(opDecl in module getOperators()) {
                score := getScore(opDecl, reqType)
                //printf("Considering %s for %s, score = %d\n", opDecl toString(), toString(), score)
                if(score == -1) { res wholeAgain(this, "score of op == -1 !!"); return Responses OK }
                if(score > bestScore) {
                    bestScore = score
                    candidate = opDecl
                }
            }
        }

        if(candidate != null) {
            if(isAssign() && !candidate getSymbol() endsWith?("=")) {
                // we need to unwrap first!
                unwrapAssign(trail, res)
                trail push(this)
                right resolve(trail, res)
                trail pop(this)
                return Responses OK
            }

            fDecl := candidate getFunctionDecl()
            fCall := FunctionCall new(fDecl getName(), token)
            fCall getArguments() add(left)
            fCall getArguments() add(right)
            fCall setRef(fDecl)
            if(!trail peek() replace(this, fCall)) {
                if(res fatal) res throwError(CouldntReplace new(token, this, fCall, trail))
                res wholeAgain(this, "failed to replace oneself, gotta try again =)")
                return Responses OK
            }
            res wholeAgain(this, "Just replaced with an operator overload")
        }

        return Responses OK

    }

    getScore: func (op: OperatorDecl, reqType: Type) -> Int {

        symbol := opTypeRepr[type]

        half := false

        if(!(op getSymbol() equals?(symbol))) {
            if(isAssign() && symbol startsWith?(op getSymbol())) {
                // alright!
                half = true
            } else {
                return 0 // not the right overload type - skip
            }
        }

        fDecl := op getFunctionDecl()

        args := fDecl getArguments()
        if(args size() != 2) {
            token module params errorHandler onError(InvalidBinaryOverload new(op token,
                "Argl, you need 2 arguments to override the '%s' operator, not %d" format(symbol, args size())))
        }

        opLeft  := args get(0)
        opRight := args get(1)

        if(opLeft getType() == null || opRight getType() == null || left getType() == null || right getType() == null) {
            return -1
        }

        leftScore  := left  getType() getStrictScore(opLeft  getType())
        if(leftScore  == -1) return -1

        rightScore := right getType() getStrictScore(opRight getType())
        if(rightScore == -1) return -1

        reqScore   := reqType ? fDecl getReturnType() getScore(reqType) : 0
        if(reqScore   == -1) return -1

        //printf("leftScore = %d, rightScore = %d\n", leftScore, rightScore)

        score := leftScore + rightScore + reqScore

        if(half) score /= 2  // used to prioritize '+=', '-=', and blah, over '+ and =', etc.

        return score

    }

    replace: func (oldie, kiddo: Node) -> Bool {
        match oldie {
            case left  => left  = kiddo; true
            case right => right = kiddo; true
            case => false
        }
    }

}

InvalidBinaryOverload: class extends Error {
    init: super func ~tokenMessage
}

InvalidOperatorUse: class extends Error {
    init: super func ~tokenMessage
}
