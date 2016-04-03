/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module handles swapping byte order.
 */
module streams.util.endian;
private
{
    import std.system : Endian, endian;
    import std.traits;
}

/**
 * Swaps the order of bytes of a scalar value.
 * 
 * Params:
 * 	t = Scalar value.
 * 
 * Returns: Scalar value with reversed bytes.
 */
static @nogc T swapEndianScalar(T)(T t) pure nothrow if (isScalarType!T)
{
    auto dst = cast(ubyte*)&t;
    for (int i = 0, j = T.sizeof - 1; i < T.sizeof / 2; ++i, --j)
    {
        immutable tmp = dst[i];
        dst[i] = dst[j];
        dst[j] = tmp;
    }
    return t;
}

/**
 * Swaps the order of bytes of structure's members in place.
 * 
 * Params:
 * 	s = Structure reference.
 */
static @nogc void swapEndianStruct(Struct)(ref Struct s) pure nothrow if (is(Struct == struct))
{
    foreach (i, type; Fields!Struct)
    {
        static if (isScalarType!type && type.sizeof > 1)
        {
            s.tupleof[i] = swapEndianScalar(s.tupleof[i]);
        }
        else static if (is(type == struct))
        {
            swapEndianStruct(s.tupleof[i]);
        }
        else static if (type.sizeof != 1)
        {
            static assert(0, "Invalid type for an endian swap");
        }
    }
}

unittest
{
    import std.stdio : writeln;

    struct Foo
    {
        int a;
        short b;
        long c;
        byte d;
    }

    auto f = Foo(1, 2, 3, 4);
    swapEndianStruct(f);
    assert(f == Foo(16777216, 512, 216172782113783808, 4));
}
