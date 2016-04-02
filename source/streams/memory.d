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
static @nogc @safe auto memoryStream(immutable(ubyte)[] data) pure nothrow {
	return ReadOnlyMemoryStream(data);
}

/**
 * Creates a memory stream based on a byte array.
 * 
 * Params:
 * 	data = Byte array.
 */
static auto @safe memoryStream(ubyte[] data) pure nothrow {
	return MemoryStream(data);
}

/**
 * Creates a memory stream reserving specified amount of memory.
 * 
 * Params:
 * 	size = Amount of bytes to preallocate.
 */
static auto @safe memoryStream(size_t size) pure nothrow {
	return MemoryStream(size);
}

/**
 * Creates a memory stream.
 */
static @nogc @safe auto memoryStream() pure nothrow {
	return MemoryStream();
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
	import std.array: uninitializedArray;

	static if(isSeekable!Source) {
		auto buf = source.readAll(upTo);
		alias bytes = buf;
	} else {
		auto mem = memoryStream();
		source.copyTo(mem, upTo, bufferSize);
		auto buf = mem.data;
		alias bytes = buf;
	}
	return memoryStream(cast(immutable(ubyte)[])bytes);
}

/**
 * A read-only memory stream.
 */
struct ReadOnlyMemoryStream {
	private size_t position = 0;
	private immutable (ubyte)[] buffer;

	/**
	 * Creates a read-only memory stream from a byte array.
	 * 
	 * Params:
	 * 	data = Immutable byte array.
	 */
	@nogc @safe this(immutable(ubyte)[] data) pure nothrow {
		buffer = data;
	}

	/**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
	@nogc @safe size_t read(ubyte[] buf) pure nothrow {
		auto remaining = buffer.length - position;
		if(remaining == 0)
			return 0;
		size_t len;
		if(remaining < buf.length)
			len = remaining;
		else len = buf.length;
		auto end = position + len;
		buf[0..len] = buffer[position..end];
		position = end;
		return len;
	}

	/**
	 * Provides a direct access to a number of bytes.
	 * If remaining bytes is less than size, then a
	 * smaller slice is returned.
	 */
	@nogc @safe const(ubyte[]) read(size_t size) pure nothrow {
		auto remaining = buffer.length - position;
		if(remaining == 0)
			return [];
		size_t len;
		if(remaining < size)
			len = remaining;
		else len = size;
		auto end = position + len;
		auto slice = buffer[position..end];
		position = end;
		return slice;
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
				position = offset;
				break;
			case From.here:
				position += offset;
				break;
			case From.end:
				position = buffer.length + offset;
				break;
			default:
		}
		if(position >= buffer.length)
			throw new SeekException("Can't seek past the buffer");
		else if (position < 0)
			throw new SeekException("Position can't be negative");
		return position;
	}

	/**
	 * Returns the underlying buffer.
	 */
	@nogc @safe @property immutable(ubyte[]) data() pure nothrow {
		return buffer;
	}

	/**
	 * Returns a slice of the underlying buffer.
	 */
	@nogc @safe @property immutable(ubyte[]) opSlice(size_t i, size_t j) pure nothrow {
		return buffer[i..j];
	}
}

/**
 * A mutable memory stream.
 */
struct MemoryStream {
	private size_t position = 0;
	private Appender!(ubyte[]) buffer;

	/**
	 * Creates a memory stream based on a byte array.
	 * 
	 * Params:
	 * 	data = Byte array.
	 */
	@safe this(ubyte[] data) pure nothrow {
		buffer = appender(data);
	}

	/**
	 * Creates a memory stream reserving specified amount of memory.
	 * 
	 * Params:
	 * 	size = Amount of bytes to preallocate.
	 */
	@safe this(size_t size) pure nothrow {
		buffer.reserve(size);
	}

	/**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
	@nogc @safe size_t read(ubyte[] buf) pure nothrow {
		auto data = buffer.data;
		auto remaining = data.length - position;
		if(remaining == 0)
			return 0;
		size_t len;
		if(remaining < buf.length)
			len = remaining;
		else len = buf.length;
		auto end = position + len;
		buf[0..len] = data[position..end];
		position = end;
		return len;
	}

	/**
	 * Provides a direct access to a number of bytes.
	 * If remaining bytes is less than size, then a
	 * smaller slice is returned.
	 */
	@nogc @safe const(ubyte[]) read(size_t size) pure nothrow {
		auto data = buffer.data;
		auto remaining = data.length - position;
		if(remaining == 0)
			return [];
		size_t len;
		if(remaining < size)
			len = remaining;
		else len = size;
		auto end = position + len;
		auto slice = data[position..end];
		position = end;
		return slice;
	}

	/**
	 * Appends data to the buffer.
	 *
	 * Params:
	 *   data = Byte array to be appended.
	 *
	 * Returns: The number of bytes that were appended.
	 */
	@safe size_t write(in ubyte[] data) pure nothrow {
		buffer ~= data;
		position += data.length;
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
		auto data = buffer.data;
		switch(from) {
			case From.start:
				position = offset;
				break;
			case From.here:
				position += offset;
				break;
			case From.end:
				position = data.length + offset;
				break;
			default:
		}
		if(position >= data.length)
			throw new SeekException("Can't seek past the buffer");
		else if (position < 0)
			throw new SeekException("Position can't be negative");
		return position;
	}

	/**
	 * Returns the underlying buffer.
	 */
	@nogc @safe @property const(ubyte)[] data() pure nothrow {
		return buffer.data;
	}

	/**
	 * Returns a slice of the underlying buffer.
	 */
	@nogc @safe @property const(ubyte[]) opSlice(size_t i, size_t j) pure nothrow {
		return buffer.data[i..j];
	}
}