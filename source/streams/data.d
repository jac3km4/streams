/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module contains methods which
 * allow manipulating binary data in streams.
 */
module streams.data;
private
{
    import std.conv : to;
    import std.system : Endian, endian;
    import std.traits;

    import io.stream;

    import streams.util.endian;
    import streams.util.direct;
}

private enum doesNeedSwap(T, Endian E) = T.sizeof > 1 && endian != E;

/**
 * Decodes a primitive value from a source
 * taking care of endianess.
 * 
 * Params:
 * 	source = Stream to read from.
 */
static T decode(T, Endian E = Endian.littleEndian, Source)(auto ref Source source) if (
        isSource!Source && isScalarType!T)
{
    static if (isDirectSource!Source)
    {
        auto slice = source.directRead(T.sizeof);
        if (slice.length != T.sizeof)
            throw new ReadException("Failed to read enough bytes");
        auto deref = *cast(T*) slice;
        alias t = deref;
    }
    else
    {
        T t;
        auto ptr = (cast(ubyte*)&t)[0 .. T.sizeof];
        if (source.read(ptr) != T.sizeof)
            throw new ReadException("Failed to read enough bytes");
    }
    static if (doesNeedSwap!(T, E))
        return swapEndianScalar(t);
    else
        return t;
}

/**
 * Encodes a primitive value into a sink
 * taking care of endianess.
 * 
 * Params:
 * 	sink = Stream to write into.
 * 	t = Value to encode.
 */
static void encode(T, Endian E = Endian.littleEndian, Sink)(auto ref Sink sink, T t) if (
        isSink!Sink && isScalarType!T)
{
    static if (doesNeedSwap!(T, E))
    {
        T x = swapEndianScalar(t);
        alias src = x;
    }
    else
        alias src = t;
    auto ptr = (cast(ubyte*)&src)[0 .. T.sizeof];
    if (sink.write(ptr) != T.sizeof)
        throw new WriteException("Failed to write enough bytes");
}

/**
 * Interprets bytes from source as a structure
 * taking care of endianess of it's members.
 * 
 * Params:
 * 	source = Stream to read from.
 */
static Struct rawRead(Struct, Endian E = Endian.littleEndian, Source)(auto ref Source source) if (
        isSource!Source && is(Struct == struct))
{
    static if (isDirectSource!Source)
    {
        auto slice = source.directRead(Struct.sizeof);
        if (slice.length != Struct.sizeof)
            throw new ReadException("Failed to read enough bytes");
        auto s = *cast(Struct*) slice;
        alias res = s;
    }
    else
    {
        Struct s;
        auto ptr = (cast(ubyte*)&s)[0 .. Struct.sizeof];
        if (source.read(ptr) != Struct.sizeof)
            throw new ReadException("Failed to read enough bytes");
        alias res = s;
    }
    static if (endian != E)
        swapEndianStruct(res);
    return res;
}

/**
 * Encodes a structure as a sequence of bytes
 * taking care of endianess of it's members.
 * 
 * Params:
 * 	sink = Stream to write into.
 * 	s = Structure to encode.
 */
static void rawWrite(Struct, Endian E = Endian.littleEndian, Sink)(auto ref Sink sink,
    in Struct s) if (isSink!Sink && is(Struct == struct))
{
    static if (endian != E)
    {
        scope auto copy = s;
        swapEndianStruct(copy);
        alias src = copy;
    }
    else
    {
        alias src = s;
    }
    auto ptr = (cast(ubyte*)&src)[0 .. Struct.sizeof];
    if (sink.write(ptr) != Struct.sizeof)
        throw new WriteException("Failed to write enough bytes");
}

unittest
{
    import streams.memory : memoryStream;

    struct Foo
    {
        ubyte a;
        short b;
    }

    immutable(ubyte[]) data = [11, 0, 99, 0];
    auto s = memoryStream(data);
    assert(s.rawRead!Foo == Foo(11, 99));
    s.seekTo(0, From.start);
    assert(s.decode!ubyte == 11);
}
