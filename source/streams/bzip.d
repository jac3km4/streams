/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to read and write bzip2 streams
 */
module streams.bzip;
private {
	import io.stream;
	import bzlib;

	import streams.util.direct;
}

enum BZIP_BUFFER_SIZE = 8 * 1024;

/**
 * Creates an input zlib2 stream.
 * 
 * Params:
 * 	stream = Base stream.
 *  small = Whether the library will use an alternative decompression algorithm
 * 			which uses less memory but at the cost of decompressing more slowly.
 */
static auto bzipInputStream(Stream)(
	auto ref Stream stream,
	bool small = false) if (isSource!Stream) {
	auto s = BzipInputStream!Stream(stream, small);
	static if(!isDirectSource!Stream)
		s.bufferSize = BZIP_BUFFER_SIZE;
	return s;
}

/**
 * Creates an output zlib2 stream.
 * 
 * Params:
 * 	stream = Base stream.
 * 	blockSize = Block size to be used for compression. It should be a value between 1 and 9 inclusive,
 * 				and the actual block size used is 100000 x this figure.
 * 				9 gives the best compression but takes most memory.
 */
static auto bzipOutputStream(Stream)(
	auto ref Stream stream,
	BlockSize blockSize = BlockSize.Normal) if (isSink!Stream) {
	return BzipOutputStream!Stream(stream, blockSize);
}

/**
 * bzip2 input stream structure
 */
struct BzipInputStreamBase(Source) if (isSource!Source) {
	Source base;
	private bz_stream _bzStream;
	private bool _init = false;
	private ubyte[] _buffer;

	@disable this(this);

	private void cleanup() {
		if(!_init)
			throw new BzipException("Stream is closed");
		BZ2_bzDecompressEnd(&_bzStream);
		_init = false;
	}

	/**
	 * Creates an input zlib2 stream.
	 * 
	 * Params:
	 * 	stream = Base stream.
	 *  small = Whether the library will use an alternative decompression algorithm
	 * 			which uses less memory but at the cost of decompressing more slowly.
	 */
	this()(auto ref Source source, bool small) {
		auto res = BZ2_bzDecompressInit(&_bzStream, 0, small);
		if(res != BZ_OK)
			throw new BzipException(res);
		base = source;
		_buffer = new ubyte[BZIP_BUFFER_SIZE];
		_init = true;
	}

	~this() {
		if(_init)
			cleanup();
	}

	/**
	 * Reads and decompresses bytes from a base stream.
	 * 
	 * Params:
	 * 	buf = Byte buffer to read into.
	 */
	size_t read(ubyte[] buf) {
		import std.conv: to;

		if(!_init)
			throw new BzipException("Cannot read from a closed stream");
		bool finish = false;
		_bzStream.avail_out = to!uint(buf.length);
		_bzStream.next_out = buf.ptr;
		do {
			if(_bzStream.avail_in == 0) {
				auto len = base.read(_buffer);
				if(len == 0)
					return 0;
				_bzStream.avail_in = to!uint(len);
				_bzStream.next_in = _buffer.ptr;
			}
			auto res = BZ2_bzDecompress(&_bzStream);
			switch(res) {
				case BZ_OK:
					break;
				case BZ_STREAM_END:
					cleanup();
					finish = true;
					break;
				default:
					throw new BzipException(res);
			}
		} while(!finish && _bzStream.avail_out > 0);
		return buf.length - _bzStream.avail_out;
	}
}


struct BzipOutputStreamBase(Sink) if (isSink!Sink) {
	Sink base;
	private bool _init = false;
	private bz_stream _bzStream;
	private ubyte[] _buffer;

	@disable this(this);
	
	private void cleanup() {
		if(!_init)
			throw new BzipException("Stream is closed");
		BZ2_bzCompressEnd(&_bzStream);
		_init = false;
	}

	/**
	 * Creates an output zlib2 stream.
	 * 
	 * Params:
	 * 	stream = Base stream.
	 * 	blockSize = Block size to be used for compression. It should be a value between 1 and 9 inclusive,
	 * 				and the actual block size used is 100000 x this figure.
	 * 				9 gives the best compression but takes most memory.
	 */
	this()(auto ref Sink sink, BlockSize blockSize) {
		if(blockSize < 1 || blockSize > 9)
			throw new BzipException("bzip2 block size has to be between 1 and 9");
		auto res = BZ2_bzCompressInit(&_bzStream, blockSize, 0, 0);
		if(res != BZ_OK)
			throw new BzipException(res);
		base = sink;
		_buffer = new ubyte[BZIP_BUFFER_SIZE];
		_init = true;
	}

	/**
	 * Writes bytes into a stream.
	 * Note: this is not guaranteed to immediately
	 * write data into the underlying stream.
	 * Only calling flush guarantees that.
	 * 
	 * Params:
	 * 	src = Bytes to compress.
	 */
	size_t write(in ubyte[] src) {
		import std.conv: to;
		
		if(!_init)
			throw new BzipException("Cannot write to a closed stream");
		_bzStream.avail_in = to!uint(src.length); 
		_bzStream.next_in = cast(ubyte*)src.ptr;
		do {
			_bzStream.avail_out = to!uint(_buffer.length);
			_bzStream.next_out = _buffer.ptr;
			auto res = BZ2_bzCompress(&_bzStream, BZ_RUN);
			if(res != BZ_RUN_OK)
				throw new BzipException(res);
			auto length = _buffer.length - _bzStream.avail_out;
			if(length > 0)
				base.writeExactly(_buffer[0..length]);
		} while(_bzStream.avail_out == 0);
		return src.length;
	}

	/**
	 * Finishes writing, pushing all the data into
	 * the underlying stream. Closes the stream.
	 */ 
	void flush() {
		import std.conv: to;

		if(!_init)
			throw new BzipException("Cannot flush a closed stream");

		with(_bzStream) {
			avail_in = 0;
			next_in = null;
		}
		bool finish = false;
		do {
			_bzStream.avail_out = to!uint(_buffer.length);
			_bzStream.next_out = _buffer.ptr;
			auto res = BZ2_bzCompress(&_bzStream, BZ_FINISH);
			switch(res) {
				case BZ_FINISH_OK:
					break;
				case BZ_STREAM_END:
					cleanup();
					finish = true;
					break;
				default:
					throw new BzipException(res);
			}
			auto length = _buffer.length - _bzStream.avail_out;
			if(length > 0)
				base.writeExactly(_buffer[0..length]);
		} while(!finish);
	}
}

/**
 * zlib2 block size
 */
enum BlockSize : int {
	Normal = 9,
	Fast = 1,
	Best = 9
}

class BzipException: Exception {
	@safe this(int err) pure nothrow {
		import std.conv: to;
		string msg;
		switch (err) {
			case BZ_SEQUENCE_ERROR: msg = "Sequence error"; break;
			case BZ_PARAM_ERROR: msg = "Invalid parameter"; break;
			case BZ_MEM_ERROR: msg = "Not enough memory available"; break;
			case BZ_DATA_ERROR: msg = "Data integrity error detected in the compressed stream"; break;
			case BZ_DATA_ERROR_MAGIC: msg = "Compressed stream doesn't begin with the right magic bytes"; break;
			case BZ_CONFIG_ERROR: msg = "The library has been mis-compiled"; break;
			default: msg = "Undefined error: " ~ to!string(err); break;
		}
		super(msg);
	}

	@nogc @safe this(in string msg) pure nothrow {
		super(msg);
	}
}

import std.typecons;
import io.buffer: FixedBuffer;

private template InputStreamType(Stream) {
	static if(isDirectSource!Stream)
		alias type = BzipInputStreamBase!Stream;
	else
		alias type = FixedBuffer!(BzipInputStreamBase!Stream);
}

alias BzipInputStream(Stream) = RefCounted!(InputStreamType!(Stream).type, RefCountedAutoInitialize.no);

alias BzipOutputStream(Stream) = RefCounted!(BzipOutputStreamBase!Stream, RefCountedAutoInitialize.no);

unittest {
	{
		import streams.memory;

		auto str = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.";
		auto mem = memoryStream();
		auto zlibOut = bzipOutputStream(mem);
		zlibOut.writeExactly(str);
		zlibOut.flush();
		// and read it...
		mem.seekTo(0);
		auto zlibIn = bzipInputStream(mem);
		auto buf = new char[str.length];
		zlibIn.readExactly(buf);
		assert(buf[] == str[]);
		// we should be on the end of the stream
		assert(mem.position == mem.length);
	}
}