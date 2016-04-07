/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to read and write Zlib streams
 */
module streams.zlib;
private
{
    import etc.c.zlib;

    import io.stream;

    import streams.util.direct;
}

private enum WINDOW_BITS_DEFAULT = 15;

enum ZLIB_BUFFER_SIZE = 256 * 1024;

/**
 * Creates an input Zlib stream.
 * 
 * Params:
 * 	stream = Base stream.
 * 	encoding = Encoding to use.
 * 	windowBits = Window bits.
 */
auto zlibInputStream(Stream)(auto ref Stream stream,
    Encoding encoding = Encoding.Guess, int windowBits = WINDOW_BITS_DEFAULT) if (isSource!Stream)
{
    auto s = ZlibInputStream!Stream(stream, encoding, windowBits);
    static if (!isDirectSource!Stream)
        s.bufferSize = ZLIB_BUFFER_SIZE;
    return s;
}

/**
 * Creates an output Zlib stream.
 * 
 * Params:
 * 	stream = Base stream.
 * 	level = Compression level.
 */
auto zlibOutputStream(Stream)(auto ref Stream stream,
    CompressionLevel level = CompressionLevel.Normal) if (isSink!Stream)
{
    return zlibOutputStream(stream, level, Encoding.Zlib);
}

/**
 * Creates an output Zlib stream.
 * 
 * Params:
 * 	stream = Base stream.
 * 	level = Compression level.
 * 	encoding = Encoding to use.
 * 	windowBits = Window bits.
 */
auto zlibOutputStream(Stream)(auto ref Stream stream, CompressionLevel level,
    Encoding encoding, int windowBits = WINDOW_BITS_DEFAULT) if (isSink!Stream)
{
    return ZlibOutputStream!Stream(stream, level, encoding, windowBits);
}

/**
 * Zlib input stream structure
 */
struct ZlibInputStreamBase(Source) if (isSource!Source)
{
    Source base;
    private z_stream _zStream;
    private bool _init = false;

    static if (!_isDirect)
        private ubyte[] _buffer;

    private enum _isDirect = isDirectSource!Source;

    @disable this(this);

    private void cleanup()
    {
        if (!_init)
            throw new ZlibException("Stream is closed");
        inflateEnd(&_zStream);
        _init = false;
    }

    /**
	 * Creates an input Zlib stream.
	 * 
	 * Params:
	 * 	stream = Base stream.
	 * 	encoding = Encoding to use.
	 * 	windowBits = Window bits.
	 */
    this()(auto ref Source stream, Encoding encoding, int windowBits)
    {
        switch (encoding)
        {
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
        with (_zStream)
        {
            zalloc = null;
            zfree = null;
            opaque = null;
            avail_in = 0;
            next_in = null;
        }
        auto res = inflateInit2(&_zStream, windowBits);
        if (res != Z_OK)
            throw new ZlibException(res);
        base = stream;
        static if (!_isDirect)
            _buffer = new ubyte[ZLIB_BUFFER_SIZE];
        _init = true;
    }

    ~this()
    {
        if (_init)
            cleanup();
    }

    /**
	 * Reads and decompresses bytes from a base stream.
	 * 
	 * Params:
	 * 	buf = Byte buffer to read into.
	 */
    size_t read(ubyte[] buf)
    {
        import std.conv : to;

        if (!_init)
            return 0;
        if (_zStream.avail_in == 0)
        {
            static if (_isDirect)
            {
                auto slice = base.directRead(ZLIB_BUFFER_SIZE);
                if (slice.length == 0)
                    return 0;
                _zStream.avail_in = to!uint(slice.length);
                _zStream.next_in = slice.ptr;
            }
            else
            {
                auto len = base.read(_buffer);
                if (len == 0)
                    return 0;
                _zStream.avail_in = to!uint(len);
                _zStream.next_in = _buffer.ptr;
            }
        }
        _zStream.avail_out = to!uint(buf.length);
        _zStream.next_out = buf.ptr;
        auto ret = inflate(&_zStream, Z_NO_FLUSH);
        switch (ret)
        {
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
        return buf.length - _zStream.avail_out;
    }
}

/**
 * Zlib output stream structure
 */
struct ZlibOutputStreamBase(Sink) if (isSink!Sink)
{
    Sink base;
    private bool _init = false;
    private z_stream _zStream;
    private ubyte[] _buffer;

    private void cleanup()
    {
        if (!_init)
            throw new ZlibException("Stream is closed");
        deflateEnd(&_zStream);
        _init = false;
    }

    @disable this(this);

    /**
	 * Creates an output Zlib stream.
	 * 
	 * Params:
	 * 	stream = Base stream.
	 * 	level = Compression level.
	 * 	encoding = Encoding to use.
	 * 	windowBits = Window bits.
	 */
    this()(auto ref Sink stream, CompressionLevel level, Encoding encoding,
        int windowBits = WINDOW_BITS_DEFAULT)
    {

        switch (encoding)
        {
        case Encoding.Zlib:
            break;
        case Encoding.Gzip:
            windowBits += 16;
            break;
        case Encoding.None:
            windowBits *= -1;
            break;
        default:
            throw new ZlibException("Invalid encoding");
        }
        with (_zStream)
        {
            zalloc = null;
            zfree = null;
        }
        auto res = deflateInit2(&_zStream, level, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY);
        if (res != Z_OK)
            throw new ZlibException(res);
        base = stream;
        _init = true;
        _buffer = new ubyte[ZLIB_BUFFER_SIZE];
    }

    ~this()
    {
        if (_init)
            cleanup();
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
    size_t write(in ubyte[] src)
    {
        import std.conv : to;

        if (!_init)
            throw new ZlibException("Cannot write to a closed stream");
        _zStream.avail_in = to!uint(src.length);
        _zStream.next_in = src.ptr;
        do
        {
            _zStream.avail_out = to!uint(_buffer.length);
            _zStream.next_out = _buffer.ptr;
            auto res = deflate(&_zStream, Z_NO_FLUSH);
            if (res != Z_OK)
                throw new ZlibException(res);
            auto length = _buffer.length - _zStream.avail_out;
            if (length > 0)
                base.writeExactly(_buffer[0 .. length]);
        }
        while (_zStream.avail_out == 0);
        return src.length;
    }

    /**
	 * Finishes writing, pushing all the data into
	 * the underlying stream. Closes the stream.
	 */
    void flush()
    {
        import std.conv : to;

        if (!_init)
            throw new ZlibException("Cannot flush a closed stream");

        with (_zStream)
        {
            avail_in = 0;
            next_in = null;
        }
        bool finish = false;
        do
        {
            _zStream.avail_out = to!uint(_buffer.length);
            _zStream.next_out = _buffer.ptr;
            auto res = deflate(&_zStream, Z_FINISH);
            switch (res)
            {
            case Z_OK:
                break;
            case Z_STREAM_END:
                cleanup();
                finish = true;
                break;
            default:
                throw new ZlibException(res);
            }
            auto length = _buffer.length - _zStream.avail_out;
            if (length > 0)
                base.writeExactly(_buffer[0 .. length]);
        }
        while (!finish);
    }
}

/**
 * Zlib encoding types
 */
enum Encoding
{
    Guess,
    Zlib,
    Gzip,
    None
}

/**
 * Zlib compression levels
 */
enum CompressionLevel : int
{
    Normal = -1,
    None = 0,
    Fast = 1,
    Best = 9
}

class ZlibException : Exception
{
    @safe this(int err, in string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow
    {
        string msg;
        switch (err)
        {
        case Z_STREAM_END:
            msg = "End of the stream";
            break;
        case Z_NEED_DICT:
            msg = "Need a preset dictionary";
            break;
        case Z_ERRNO:
            msg = "File operation error (errno)";
            break;
        case Z_STREAM_ERROR:
            msg = "Stream state is inconsistent";
            break;
        case Z_DATA_ERROR:
            msg = "Input data is corrupted";
            break;
        case Z_MEM_ERROR:
            msg = "Not enough memory";
            break;
        case Z_BUF_ERROR:
            msg = "Buf error";
            break;
        case Z_VERSION_ERROR:
            msg = "Incompatible zlib version";
            break;
        default:
            msg = "Undefined error";
            break;
        }
        super(msg, file, line, next);
    }

    @nogc @safe this(in string message, in string file = __FILE__,
        size_t line = __LINE__, Throwable next = null) pure nothrow
    {
        super(message, file, line, next);
    }
}

import std.typecons;
import io.buffer : FixedBuffer;

private template InputStreamType(Stream)
{
    static if (isDirectSource!Stream)
        alias InputStreamType = RefCounted!(ZlibInputStreamBase!Stream,
            RefCountedAutoInitialize.no);
    else
        alias InputStreamType = RefCounted!(
            FixedBuffer!(ZlibInputStreamBase!Stream), RefCountedAutoInitialize.no);
}

alias ZlibInputStream(Stream) = InputStreamType!(Stream);

alias ZlibOutputStream(Stream) = RefCounted!(ZlibOutputStreamBase!Stream,
    RefCountedAutoInitialize.no);

unittest
{
    import streams.memory;
    {
        // this is zlib encoded string "drocks"
        immutable(ubyte)[] raw = [
            0x78, 0x9C, 0x4B, 0x29, 0xCA, 0x4F, 0xCE, 0x2E, 0x06, 0x00, 0x08, 0xC6,
            0x02, 0x87
        ];
        auto mem = memoryStream(raw);
        auto zlib = zlibInputStream(mem);
        assert("drocks" == zlib.copyToMemory.data);
    }
    {
        auto str = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.";
        auto mem = memoryStream();
        auto zlibOut = zlibOutputStream(mem);
        zlibOut.writeExactly(str);
        zlibOut.flush();
        // and read it...
        mem.seekTo(0);
        auto zlibIn = zlibInputStream(mem);
        auto buf = new char[str.length];
        zlibIn.readExactly(buf);
        assert(buf[] == str[]);
        // we should be on the end of the stream
        assert(mem.position == mem.length);
    }
}
