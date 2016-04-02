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
private {
	import io.stream;

	import streams.util.traits: isDirectSource;
}

/**
 * Creates a new slice stream based on the given source.
 * 
 * Params:
 * 	source = Source stream.
 * 	start = Offset of the slice stream in the original stream.
 * 	length = Length of the slice stream.
 */
static auto sliceStream(Source)(auto ref Source source, size_t start, size_t length) if (isSource!Source) {
	return new SliceStream!Stream(source, start, length);
}

/**
 * Slice stream structure.
 */
struct SliceStreamBase(Source) if (isSource!Source) {
	Source base;
	alias base this;
	private size_t start, length, position = 0;

	@disable long seekTo(long, From);

	@disable this(this);

	/**
	 * Creates a new slice stream based on the given source.
	 * 
	 * Params:
	 * 	source = Source stream.
	 * 	start = Offset of the slice stream in the original stream.
	 * 	length = Length of the slice stream.
	 */
	this(auto ref Source source, size_t start, size_t length) {
		base = source;
		this.start = start;
		this.length = length;
	}

	/**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
	size_t read(ubyte[] buf) {
		if(position >= length)
			return 0;
		size_t len = buf.length;
		if(position + buf.length > length)
			len = length - position;
		if(base.position != start + position)
			base.seekTo(position);
		auto read = base.read(buf[0..len]);
		position += read;
		return read;
	}

	static if (isDirectSource!Source) {
		/**
		 * Provides a direct access to a number of bytes.
		 * If remaining bytes is less than size, then a
		 * smaller slice is returned.
		 */
		const(ubyte[]) read(size_t size) {
			if(position >= length)
				return 0;
			size_t len = size;
			if(position + size > length)
				len = length - position;
			if(base.position != start + position)
				base.seekTo(position);
			auto slice = base.read(len);
			position += slice.length;
			return slice;
		}
	}
}

import std.typecons;
alias SliceStream(Stream) = RefCounted!(SliceStreamBase!Stream, RefCountedAutoInitialize.no);