/**
  * Additional functions for working with UniNode library
  *
  * Copyright:
  *     Copyright (c) 2018, Maxim Tyapkin.
  * Authors:
  *     Maxim Tyapkin
  * License:
  *     This software is licensed under the terms of the BSD 3-clause license.
  *     The full terms of the license can be found in the LICENSE.md file.
  */

module djinja.uninode;

public
{
    import uninode.node;
    import uninode.serialization :
                serialize = serializeToUniNode,
                deserialize = deserializeUniNode;
}

private
{
    import std.array : array;
    import std.algorithm : among, map, sort;
    import std.conv : to;
    import std.format: fmt = format;
    import std.typecons : Tuple, tuple;

    import djinja.lexer;
    import djinja.exception : JinjaRenderException,
                              assertJinja = assertJinjaRender;
}


bool isNumericNode(ref UniNode n)
{
    return cast(bool)n.tag.among!(
            UniNode.Tag.integer,
            UniNode.Tag.uinteger,
            UniNode.Tag.floating
        );
}


bool isIntNode(ref UniNode n)
{
    return cast(bool)n.tag.among!(
            UniNode.Tag.integer,
            UniNode.Tag.uinteger
        );
}


bool isFloatNode(ref UniNode n)
{
    return n.tag == UniNode.Tag.floating;
}


bool isIterableNode(ref UniNode n)
{
    return cast(bool)n.tag.among!(
            UniNode.Tag.sequence,
            UniNode.Tag.mapping,
            UniNode.Tag.text
        );
}

void toIterableNode(ref UniNode n)
{
    switch (n.tag) with (UniNode.Tag)
    {
        case sequence:
            return;
        case text:
            n = UniNode(n.get!string.map!(a => UniNode(cast(string)[a])).array);
            return;
        case mapping:
            UniNode[] arr;
            foreach (key, val; n.getMapping)
                arr ~= UniNode([UniNode(key), val]);
            n = UniNode(arr);
            return;
        default:
            throw new JinjaRenderException("Can't implicity convert type %s to iterable".fmt(n.tag));
    }
}

void toCommonNumType(ref UniNode n1, ref UniNode n2)
{
    assertJinja(n1.isNumericNode, "Not a numeric type of %s".fmt(n1));
    assertJinja(n2.isNumericNode, "Not a numeric type of %s".fmt(n2));

    if (n1.isIntNode && n2.isFloatNode)
    {
        n1 = UniNode(n1.get!long.to!double);
        return;
    }

    if (n1.isFloatNode && n2.isIntNode)
    {
        n2 = UniNode(n2.get!long.to!double);
        return;
    }
}


void toCommonCmpType(ref UniNode n1, ref UniNode n2)
{
   if (n1.isNumericNode && n2.isNumericNode)
   {
       toCommonNumType(n1, n2);
       return;
   }
   if (n1.tag != n2.tag)
       throw new JinjaRenderException("Not comparable types %s and %s".fmt(n1.tag, n2.tag));
}


void toBoolType(ref UniNode n)
{
    switch (n.tag) with (UniNode.Tag)
    {
        case boolean:
            return;
        case integer:
        case uinteger:
            n = UniNode(n.get!long != 0);
            return;
        case floating:
            n = UniNode(n.get!double != 0);
            return;
        case text:
            n = UniNode(n.get!string.length > 0);
            return;
        case sequence:
        case mapping:
            n = UniNode(n.length > 0);
            return;
        case nil:
            n = UniNode(false);
            return;
        default:
            throw new JinjaRenderException("Can't cast type %s to bool".fmt(n.tag));
    }
}


void toStringType(ref UniNode n)
{
    import std.algorithm : map;
    import std.string : join;

    string getString(UniNode n)
    {
        bool quotes = n.tag == UniNode.Tag.text;
        n.toStringType;
        if (quotes)
            return "'" ~ n.get!string ~ "'";
        else
            return n.get!string;
    }

    string doSwitch()
    {
        final switch (n.tag) with (UniNode.Tag)
        {
            case nil:      return "";
            case boolean:  return n.get!bool.to!string;
            case integer:  return n.get!long.to!string;
            case uinteger: return n.get!ulong.to!string;
            case floating: return n.get!double.to!string;
            case text:     return n.get!string;
            case raw:      return n.get!(ubyte[]).to!string;
            case sequence:    return "["~n.getSequence.map!(a => getString(a)).join(", ").to!string~"]";
            case mapping:
                string[] results;
                Tuple!(string, UniNode)[] sorted = [];
                foreach (string key, ref UniNode value; n)
                    results ~= key ~ ": " ~ getString(value);
                return "{" ~ results.join(", ").to!string ~ "}";
        }
    }

    n = UniNode(doSwitch());
}


string getAsString(UniNode n)
{
    n.toStringType;
    return n.get!string;
}


void checkNodeType(ref UniNode n, UniNode.Tag kind, Position pos)
{
    if (n.tag != kind)
        assertJinja(0, "Unexpected expression type `%s`, expected `%s`".fmt(n.tag, kind), pos);
}



UniNode unary(string op)(UniNode lhs)
    if (op.among!(Operator.Plus,
                 Operator.Minus)
    )
{
    assertJinja(lhs.isNumericNode, "Expected int got %s".fmt(lhs.tag));

    if (lhs.isIntNode)
        return UniNode(mixin(op ~ "lhs.get!long"));
    else
        return UniNode(mixin(op ~ "lhs.get!double"));
}



UniNode unary(string op)(UniNode lhs)
    if (op == Operator.Not)
{
    lhs.toBoolType;
    return UniNode(!lhs.get!bool);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op.among!(Operator.Plus,
                 Operator.Minus,
                 Operator.Mul)
    )
{
    toCommonNumType(lhs, rhs);
    if (lhs.isIntNode)
        return UniNode(mixin("lhs.get!long" ~ op ~ "rhs.get!long"));
    else
        return UniNode(mixin("lhs.get!double" ~ op ~ "rhs.get!double"));
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.DivInt)
{
    assertJinja(lhs.isIntNode, "Expected int got %s".fmt(lhs.tag));
    assertJinja(rhs.isIntNode, "Expected int got %s".fmt(rhs.tag));
    return UniNode(lhs.get!long / rhs.get!long);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.DivFloat
        || op == Operator.Rem)
{
    toCommonNumType(lhs, rhs);

    if (lhs.isIntNode)
    {
        assertJinja(rhs.get!long != 0, "Division by zero!");
        return UniNode(mixin("lhs.get!long" ~ op ~ "rhs.get!long"));
    }
    else
    {
        assertJinja(rhs.get!double != 0, "Division by zero!");
        return UniNode(mixin("lhs.get!double" ~ op ~ "rhs.get!double"));
    }
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.Pow)
{
    toCommonNumType(lhs, rhs);
    if (lhs.isIntNode)
        return UniNode(lhs.get!long ^^ rhs.get!long);
    else
        return UniNode(lhs.get!double ^^ rhs.get!double);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op.among!(Operator.Eq, Operator.NotEq))
{
    toCommonCmpType(lhs, rhs);
    return UniNode(mixin("lhs" ~ op ~ "rhs"));
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op.among!(Operator.Less,
                  Operator.LessEq,
                  Operator.Greater,
                  Operator.GreaterEq)
       )
{
    toCommonCmpType(lhs, rhs);
    switch (lhs.tag) with (UniNode.Tag)
    {
        case integer:
        case uinteger:
            return UniNode(mixin("lhs.get!long" ~ op ~ "rhs.get!long"));
        case floating:
            return UniNode(mixin("lhs.get!double" ~ op ~ "rhs.get!double"));
        case text:
            return UniNode(mixin("lhs.get!string" ~ op ~ "rhs.get!string"));
        default:
            throw new JinjaRenderException("Not comparable type %s".fmt(lhs.tag));
    }
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.Or)
{
    lhs.toBoolType;
    rhs.toBoolType;
    return UniNode(lhs.get!bool || rhs.get!bool);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.And)
{
    lhs.toBoolType;
    rhs.toBoolType;
    return UniNode(lhs.get!bool && rhs.get!bool);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.Concat)
{
    lhs.toStringType;
    rhs.toStringType;
    return UniNode(lhs.get!string ~ rhs.get!string);
}



UniNode binary(string op)(UniNode lhs, UniNode rhs)
    if (op == Operator.In)
{
    import std.algorithm.searching : countUntil;

    switch (rhs.tag) with (UniNode.Tag)
    {
        case sequence:
            foreach(UniNode val; rhs)
            {
                if (val == lhs)
                    return UniNode(true);
            }
            return UniNode(false);
        case mapping:
            if (lhs.tag != UniNode.Tag.text)
                return UniNode(false);
            return UniNode(cast(bool)(lhs.get!string in rhs));
        case text:
            if (lhs.tag != UniNode.Tag.text)
                return UniNode(false);
            return UniNode(rhs.get!string.countUntil(lhs.get!string) >= 0);
        default:
            return UniNode(false);
    }
}
