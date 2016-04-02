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

	import streams.util.direct;
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
	static if(!isDirectSource!Stream)
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
	import streams: unbufferedFileStream;

	return zlibStream(unbufferedFileStream(path));
}

/**
 * Zlib stream structure
 */
struct ZlibStreamBase(Stream) if (isStream!Stream) {
	private enum _isDirect = isDirectSource!Stream;
	Stream base;

	static if(!_isDirect)
		private ubyte[] _buffer;
	private z_stream _zStream;
	private bool _init = false;

	@disable this(this);

	void cleanup() {
		if(_init) {
			inflateEnd(&_zStream);
			_init = false;
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
		with(_zStream) {
			zalloc = null;
			zfree = null;
			opaque = null;
			avail_in = 0;
			next_in = null;
		}
		auto res = inflateInit2(&_zStream, windowBits);
		if(res != Z_OK)
			throw new ZlibException(res);
		static if(!_isDirect)
			_buffer = new ubyte[ZLIB_BUFFER_SIZE];
		_init = true;
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

			if(!_init)
				return 0;
			if(_zStream.avail_in == 0) {
				static if(_isDirect) {
					auto slice = base.directRead(ZLIB_BUFFER_SIZE);
					if(slice.length == 0)
						return 0;
					_zStream.avail_in = to!uint(slice.length);
					_zStream.next_in = slice.ptr;
				} else {
					auto len = base.read(_buffer);
					if(len == 0)
						return 0;
					_zStream.avail_in = to!uint(len);
					_zStream.next_in = _buffer.ptr;
				}
			}
			_zStream.avail_out = to!uint(chunk.length);
			_zStream.next_out = chunk.ptr;
			auto ret = inflate(&_zStream, Z_NO_FLUSH);
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
			return chunk.length - _zStream.avail_out;
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

template StreamType(Stream) {
	static if(isDirectSource!Stream)
		alias type = RefCounted!(ZlibStreamBase!Stream, RefCountedAutoInitialize.no);
	else
		alias type = RefCounted!(FixedBuffer!(ZlibStreamBase!Stream), RefCountedAutoInitialize.no);
}

alias ZlibStream(Stream) = StreamType!(Stream).type;

unittest {
	import streams.memory;

	// this is zlib encoded string "drocks"
	immutable(ubyte)[] raw = [0x78,0x9C,0x4B,0x29,0xCA,0x4F,0xCE,0x2E,0x06,0x00,0x08,0xC6,0x02,0x87];
	auto mem = memoryStream(raw);
	auto zlib = zlibStream(mem);
	assert("drocks" == zlib.copyToMemory.data);
}