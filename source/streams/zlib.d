/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to read and write Zlib streams
 */
module streams.zlib;
private {
	import etc.c.zlib;

	import io.stream;

	import streams: unbufferedFileStream;
	import streams.util.traits: isDirectSource;
}

private enum WINDOW_BITS_DEFAULT = 15;

enum ZLIB_BUFFER_SIZE = 256 * 1024;

/**
 * Creates a Zlib stream.
 * 
 * Params:
 * 	stream = Base stream.
 * 	encoding = Encoding to use.
 * 	windowBits = Window bits.
 */
static auto zlibStream(Stream)(
	auto ref Stream stream,
	Encoding encoding = Encoding.Guess,
	int windowBits = WINDOW_BITS_DEFAULT) if (isStream!Stream) {
	auto s = ZlibStream!Stream(stream, encoding, windowBits);
	s.bufferSize = ZLIB_BUFFER_SIZE;
	return s;
}

/**
 * Open a file as a Zlib stream.
 * 
 * Params:
 * 	path = File path.
 * 	encoding = Encoding to use.
 * 	windowBits = Window bits.
 */
static auto zlibStream(
	in string path,
	Encoding encoding = Encoding.Guess,
	int windowBits = WINDOW_BITS_DEFAULT) {
	return zlibStream(unbufferedFileStream(path));
}

/**
 * Zlib stream structure
 */
struct ZlibStreamBase(Stream) if (isStream!Stream) {
	Stream base;

	static if(!isDirectSource!Stream)
		private ubyte[] buffer;
	private z_stream zStream;
	private bool init = false;

	@disable this(this);

	@disable long seekTo(long, From);

	void cleanup() {
		if(init) {
			inflateEnd(&zStream);
			init = false;
		}
	}
	/**
	 * Creates a Zlib stream.
	 * 
	 * Params:
	 * 	stream = Base stream.
	 * 	encoding = Encoding to use.
	 * 	windowBits = Window bits.
	 */
	this()(auto ref Stream stream, Encoding encoding, int windowBits) {
		base = stream;
		switch(encoding) {
			case Encoding.Zlib:
				break;
			case Encoding.Gzip:
				windowBits += 16;
				break;
			case Encoding.Guess:
				windowBits += 32;
				break;
			case Encoding.None:
				windowBits *= -1;
				break;
			default:
				throw new ZlibException("Invalid encoding");
		}
		with(zStream) {
			zalloc = null;
			zfree = null;
			opaque = null;
			avail_in = 0;
			next_in = null;
		}
		auto res = inflateInit2(&zStream, windowBits);
		if(res != Z_OK)
			throw new ZlibException(res);
		static if(!isDirectSource!Stream)
			buffer = new ubyte[ZLIB_BUFFER_SIZE];
		init = true;
	}

	~this() {
		cleanup();
	}

	static if(isSource!Stream) {
		/**
		 * Reads and decodes bytes from a base stream.
		 * 
		 * Params:
		 * 	chunk = Byte buffer to read into.
		 */
		size_t read(ubyte[] chunk) {
			import std.conv: to;

			if(!init)
				return 0;
			if(zStream.avail_in == 0) {
				static if(isDirectSource!Stream) {
					auto slice = base.read(ZLIB_BUFFER_SIZE);
					if(slice.length == 0)
						return 0;
					zStream.avail_in = to!uint(slice.length);
					zStream.next_in = slice.ptr;
				} else {
					auto len = base.read(buffer);
					if(len == 0)
						return 0;
					zStream.avail_in = to!uint(len);
					zStream.next_in = buffer.ptr;
				}
			}
			zStream.avail_out = to!uint(chunk.length);
			zStream.next_out = cast(ubyte*)chunk.ptr;
			auto ret = inflate(&zStream, Z_NO_FLUSH);
			switch(ret) {
				case Z_NEED_DICT:
				case Z_DATA_ERROR:
				case Z_MEM_ERROR:
					cleanup();
					throw new ZlibException(ret);
				case Z_STREAM_END:
					cleanup();
					break;
				default:
			}
			return chunk.length - zStream.avail_out;
		}
	}
}

enum Encoding {
	Guess,
	Zlib,
	Gzip,
	None
}

class ZlibException: Exception {
	@nogc @safe this(int err) pure nothrow {
		string msg;
		switch (err) {
			case Z_STREAM_END: msg = "End of the stream"; break;
			case Z_NEED_DICT: msg = "Need a preset dictionary"; break;
			case Z_ERRNO: msg = "File operation error (errno)"; break;
			case Z_STREAM_ERROR: msg = "Stream state is inconsistent"; break;
			case Z_DATA_ERROR: msg = "Input data is corrupted"; break;
			case Z_MEM_ERROR: msg = "Not enough memory"; break;
			case Z_BUF_ERROR: msg = "Buf error"; break;
			case Z_VERSION_ERROR: msg = "Incompatible zlib version"; break;
			default: msg = "Undefined error";  break;
		}
		super(msg);
	}

	@nogc @safe this(in string msg) pure nothrow {
		super(msg);
	}
}

import std.typecons;
import io.buffer: FixedBuffer;
alias ZlibStream(Stream) = RefCounted!(FixedBuffer!(ZlibStreamBase!Stream), RefCountedAutoInitialize.no);

unittest {
	import streams.memory;

	// this is zlib encoded string "drocks"
	immutable(ubyte)[] raw = [0x78,0x9C,0x4B,0x29,0xCA,0x4F,0xCE,0x2E,0x06,0x00,0x08,0xC6,0x02,0x87];
	auto mem = memoryStream(raw);
	auto zlib = zlibStream(mem);
	assert("drocks" == zlib.copyToMemory.data);
}