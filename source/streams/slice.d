/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides stream-based read access to a
 * slice of some source.
 */
module streams.slice;
private
{
    import io.stream;
    import streams.util.direct;
}

/**
 * Creates a new slice stream based on the given source.
 *
 * Params:
 * 	source = Source stream.
 * 	start = Offset of the slice stream in the original stream.
 * 	length = Length of the slice stream.
 */
static auto sliceStream(Source)(auto ref Source source, size_t start, size_t length) if (
        isSource!Source)
{
    return SliceStream!Source(source, start, length);
}

/**
 * Slice stream structure.
 */
struct SliceStreamBase(Source) if (isSource!Source)
{
    Source base;
    private size_t _start, _length, _position = 0;

    @disable this(this);

    /**
	 * Creates a new slice stream based on the given source.
	 *
	 * Params:
	 * 	source = Source stream.
	 * 	start = Offset of the slice stream in the original stream.
	 * 	length = Length of the slice stream.
	 */
    this()(auto ref Source source, size_t start, size_t length)
    {
        base = source;
        _start = start;
        _length = length;
    }

    /**
	 * Reads bytes into the specified buffer
	 * from the underlying stream.
	 * The number of bytes read is returned.
	 */
    size_t read(ubyte[] buf)
    {
        if (_position >= _length)
            return 0;
        size_t len = buf.length;
        if (_position + buf.length > _length)
            len = _length - _position;
        if (base.position != _start + _position)
            base.seekTo(_start + _position);
        auto read = base.read(buf[0 .. len]);
        _position += read;
        return read;
    }

    static if (isDirectSource!Source)
    {
        /**
		 * Returns a slice of the underyling
		 * stream's buffer (if it allows such operation)..
		 */
        @nogc @safe @property const(ubyte[]) opSlice(size_t i, size_t j) pure nothrow
        {
            return base[_start + i .. _start + j];
        }

        /**
		 * Returns length of the underlying buffer.
		 */
        @nogc @safe @property size_t opDollar(size_t dim : 0)() pure nothrow
        {
            return length;
        }
    }

    /**
	 * Returns length of the slice.
	 */
    @nogc @safe @property size_t length() pure nothrow
    {
        return _length;
    }

    /**
	 * Returns current position in the slice.
	 */
    @nogc @safe @property size_t position() pure nothrow
    {
        return _position;
    }

    /**
	 * Sets position in the slice..
	 */
    @nogc @safe @property void position(size_t pos) pure nothrow
    {
        _position = pos;
    }
}

import std.typecons;

alias SliceStream(Stream) = RefCounted!(SliceStreamBase!Stream, RefCountedAutoInitialize.no);

unittest
{
    import streams.memory;

    immutable(ubyte[]) raw = [1, 2, 3, 4, 5, 6];
    auto mem = memoryStream(raw);
    auto slice = sliceStream(mem, 2, 3);
    assert(slice.directRead(2) == [3, 4]);
    auto buf = new ubyte[2];
    slice.read(buf);
    assert(buf[] == [5, 0]);
}
