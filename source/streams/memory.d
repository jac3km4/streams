/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module enables you to treat
 * chunks of memory as a stream.
 */
module streams.memory;
private {
	import std.array: appender, Appender;

	import io.stream;

	import streams: copyTo;
}

/**
 * Creates a read-only memory stream from a byte array.
 * 
 * Params:
 * 	data = Immutable byte array.
 */
static @nogc auto memoryStream(immutable(ubyte)[] data) nothrow {
	return ReadOnlyMemoryStream(data);
}

/**
 * Creates a memory stream based on a byte array.
 * 
 * Params:
 * 	data = Byte array.
 */
static auto memoryStream(ubyte[] data) nothrow {
	return MemoryStream(data);
}

/**
 * Creates a memory stream reserving specified amount of memory.
 * 
 * Params:
 * 	size = Amount of bytes to preallocate.
 */
static auto memoryStream(size_t size) {
	return MemoryStream(size);
}

/**
 * Creates a memory stream.
 */
static auto memoryStream() {
	import std.typecons: refCounted;

	return refCounted(MemoryStreamBase());
}

/**
 * Copies a certain amount of bytes from a stream
 * and returns them as a read-only memory stream.
 *
 * Params:
 * 	source = Stream to copy bytes from.
 * 	upTo = Maximum number of bytes to copy (all if -1).
 * 	bufferSize = The size of memory buffer to use (if it's required).
 */
static auto copyToMemory(Source)(
	auto ref Source source,
	size_t upTo = -1,
	size_t bufferSize = 64 * 1024) if (isSource!Source) {
	import streams.util.direct;

	static if(isDirectSource!Source) {
		auto buf = source.directReadAll(upTo).idup;
		alias bytes = buf;
	}
	else static if(isSeekable!Source) {
		ubyte[] buf;
		if(upTo == -1)
			buf = cast(immutable(ubyte)[])source.readAll();
		else buf = cast(immutable(ubyte)[])source.readAll(upTo);
		alias bytes = buf;
	} else {
		auto mem = memoryStream();
		source.copyTo(mem, upTo, bufferSize);
		auto buf = cast(immutable(ubyte)[])mem.data;
		alias bytes = buf;
	}
	return memoryStream(bytes);
}

/**
 * A read-only memory stream.
 */
struct ReadOnlyMemoryStreamBase {
	private size_t _position = 0;
	private immutable (ubyte)[] _buffer;

	@disable this(this);

	/**
	 * Creates a read-only memory stream from a byte array.
	 * 
	 * Params:
	 * 	data = Immutable byte array.
	 */
	@nogc @safe this(immutable(ubyte)[] data) pure nothrow {
		_buffer = data;
	}

	/**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
	@nogc @safe size_t read(ubyte[] buf) pure nothrow {
		auto remaining = _buffer.length - _position;
		if(remaining == 0)
			return 0;
		size_t len;
		if(remaining < buf.length)
			len = remaining;
		else len = buf.length;
		auto end = _position + len;
		buf[0..len] = _buffer[_position..end];
		_position = end;
		return len;
	}

	/**
	 * Seeks relative to a position.
	 *
	 * Params:
	 *   offset = Offset relative to a reference point.
	 *   from   = Optional reference point.
	 */
	long seekTo(long offset, From from = From.start) {
		switch(from) {
			case From.start:
				_position = offset;
				break;
			case From.here:
				_position += offset;
				break;
			case From.end:
				_position = _buffer.length + offset;
				break;
			default:
		}
		if(_position >= _buffer.length)
			throw new SeekException("Can't seek past the buffer");
		else if (_position < 0)
			throw new SeekException("Position can't be negative");
		return _position;
	}

	/**
	 * Returns a slice of the underlying buffer.
	 */
	@nogc @safe @property const(ubyte[]) opSlice(size_t i, size_t j) pure nothrow {
		return _buffer[i..j];
	}
	/**
	 * Returns length of the underlying buffer.
	 */
	@nogc @safe @property size_t opDollar(size_t dim: 0)() pure nothrow {
		return length;
	}

	/**
	 * Returns the underlying buffer.
	 */
	@nogc @safe @property immutable(ubyte[]) data() pure nothrow {
		return _buffer;
	}

	/**
	 * Returns length of the underlying buffer.
	 */
	@nogc @safe @property size_t length() pure nothrow {
		return _buffer.length;
	}

	/**
	 * Returns current position in the stream.
	 */
	@nogc @safe @property size_t position() pure nothrow {
		return _position;
	}

	/**
	 * Sets position in the stream.
	 */
	@nogc @safe @property void position(size_t pos) pure nothrow {
		_position = pos;
	}
}

/**
 * A mutable memory stream.
 */
struct MemoryStreamBase {
	private size_t _position = 0;
	private Appender!(ubyte[]) _buffer;

	@disable this(this);

	/**
	 * Creates a memory stream based on a byte array.
	 * 
	 * Params:
	 * 	data = Byte array.
	 */
	@safe this(ubyte[] data) pure nothrow {
		_buffer = appender(data);
	}

	/**
	 * Creates a memory stream reserving specified amount of memory.
	 * 
	 * Params:
	 * 	size = Amount of bytes to preallocate.
	 */
	@safe this(size_t size) pure nothrow {
		_buffer.reserve(size);
	}

	/**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
	@nogc @safe size_t read(ubyte[] buf) pure nothrow {
		auto data = _buffer.data;
		auto remaining = data.length - _position;
		if(remaining == 0)
			return 0;
		size_t len;
		if(remaining < buf.length)
			len = remaining;
		else len = buf.length;
		auto end = _position + len;
		buf[0..len] = data[_position..end];
		_position = end;
		return len;
	}

	/**
	 * Inserts data in the buffer.
	 *
	 * Params:
	 *   data = Byte array to be inserted.
	 *
	 * Returns: The number of bytes that were inserted.
	 */
	@safe size_t write(in ubyte[] data) pure {
		auto length = _buffer.data.length;
		if(_position == length) {
			_buffer ~= data;
		} else if(_position + data.length > length) {
			_buffer.shrinkTo(_position);
			_buffer ~= data;
		} else if(_position + data.length < length) {
			_buffer.data[_position.._position + data.length] = data[];
		}
		_position += data.length;
		return data.length;
	}

	/**
	 * Seeks relative to a position.
	 *
	 * Params:
	 *   offset = Offset relative to a reference point.
	 *   from   = Optional reference point.
	 */
	long seekTo(long offset, From from = From.start) {
		auto data = _buffer.data;
		switch(from) {
			case From.start:
				_position = offset;
				break;
			case From.here:
				_position += offset;
				break;
			case From.end:
				_position = data.length + offset;
				break;
			default:
		}
		if(_position >= data.length)
			throw new SeekException("Can't seek past the buffer");
		else if (_position < 0)
			throw new SeekException("Position can't be negative");
		return _position;
	}

	/**
	 * Returns a slice of the underlying buffer.
	 */
	@nogc @safe @property const(ubyte[]) opSlice(size_t i, size_t j) pure nothrow {
		return _buffer.data[i..j];
	}
	/**
	 * Returns length of the underlying buffer.
	 */
	@nogc @safe @property size_t opDollar(size_t dim: 0)() pure nothrow {
		return length;
	}

	/**
	 * Returns the underlying buffer.
	 */
	@nogc @safe @property const(ubyte)[] data() pure nothrow {
		return _buffer.data;
	}

	/**
	 * Returns length of the underlying buffer.
	 */
	@nogc @safe @property size_t length() pure nothrow {
		return _buffer.data.length;
	}

	/**
	 * Returns current position in the stream.
	 */
	@nogc @safe @property size_t position() pure nothrow {
		return _position;
	}

	/**
	 * Sets position in the stream.
	 */
	@nogc @safe @property void position(size_t pos) pure nothrow {
		_position = pos;
	}
}

import std.typecons;
alias ReadOnlyMemoryStream = RefCounted!(ReadOnlyMemoryStreamBase, RefCountedAutoInitialize.no);
alias MemoryStream = RefCounted!(MemoryStreamBase, RefCountedAutoInitialize.no);