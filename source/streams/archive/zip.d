/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to access Zip files
 */
module streams.archive.zip;
private
{
    import std.algorithm : min;
    import std.array : uninitializedArray;
    import std.bitmanip : bitfields;

    import io.stream;

    import streams.data;
    import streams.memory;
    import streams.slice;
    import streams.util.wrappers;
}

private align(1) struct GeneralFlags
{
    mixin(bitfields!(
        bool, "encrypted", 1,
        bool, "bit1", 1,
        bool, "bit2", 1,
        bool, "dataDescriptor", 1,
        bool, "enhancedDeflation", 1,
        bool, "compressedPatchedData", 1,
        bool, "strongEncryption", 1,
        int, "", 4,
        bool, "efs", 1,
        bool, "", 1,
        bool, "maskHeaderValues", 1,
        int, "", 2));
}

private struct LocalFileHeader
{
    enum uint signature = 0x04034b50;

    RawData data;
    alias data this;
    static assert(RawData.sizeof == 26);

    ubyte[] extraField;
    ubyte[] fileName;

    void read(Source)(auto ref Source s) if (isSource!Source)
    {
        data = s.rawRead!RawData;
        fileName = uninitializedArray!(ubyte[])(fileNameLength);
        s.readExactly(fileName);
        extraField = uninitializedArray!(ubyte[])(extraFieldLength);
        s.readExactly(extraField);
    }

    void write(Sink)(auto ref Sink s) if (isSink!Sink)
    {
        s.rawWrite(data);
        s.writeExactly(fileName);
        s.writeExactly(extraField);
    }

    private align(1) struct RawData
    {
    align(1):
        ushort versionRequired;
        GeneralFlags flags;
        ushort compressionMethod;
        ushort modificationTime;
        ushort modificationDate;
        uint crc32;
        uint compressedSize;
        uint uncompressedSize;
        ushort fileNameLength;
        ushort extraFieldLength;

    }
}

private struct FileHeader
{
    enum uint signature = 0x02014b50;

    RawData data;
    alias data this;
    static assert(RawData.sizeof == 42);

    ubyte[] fileName;
    ubyte[] extraField;
    ubyte[] comment;

    void read(Source)(auto ref Source s) if (isSource!Source)
    {
        data = s.rawRead!RawData;
        fileName = uninitializedArray!(ubyte[])(fileNameLength);
        s.readExactly(fileName);
        extraField = uninitializedArray!(ubyte[])(extraFieldLength);
        s.readExactly(extraField);
        comment = uninitializedArray!(ubyte[])(commentLength);
        s.readExactly(comment);
    }

    void write(Sink)(auto ref Sink s) if (isSink!Sink)
    {
        s.rawWrite(data);
        s.writeExactly(fileName);
        s.writeExactly(extraField);
        s.writeExactly(comment);
    }

    private align(1) struct RawData
    {
    align(1):
        ubyte zipVersion;
        ubyte fileAttribute;
        ushort extractVersion;
        GeneralFlags flags;
        ushort compressionMethod;
        ushort modificationTime;
        ushort modificationDate;
        uint crc32;
        uint compressedSize;
        uint uncompressedSize;
        ushort fileNameLength;
        ushort extraFieldLength;
        ushort commentLength;
        ushort diskNumberStart;
        ushort internalAttributes;
        uint externalAttributes;
        uint relativeOffsetOfLocalHeader;
    }
}

private struct EndOfCentralDirRecord
{
    enum uint signature = 0x06054b50;

    RawData data;
    alias data this;

    char[] comment;

    void read(Source)(auto ref Source source) if (isSource!Source)
    {
        data = source.rawRead!RawData;
        comment = uninitializedArray!(char[])(commentLength);
        source.readExactly(comment);
    }

    void write(Sink)(auto ref Sink s) if (isSink!Sink)
    {
        s.rawWrite(data);
        s.writeExactly(comment);
    }

    private align(1) struct RawData
    {
    align(1):
        ushort diskNumber;
        ushort diskWithCentralDir;
        ushort entriesInCentralDirOnThisDisk;
        ushort entriesInCentralDir;
        uint sizeOfCentralDir;
        uint offsetOfCentralDirFromStartingDisk;
        ushort commentLength;
    }
}

/**
 * Opens an existing zip archive from a stream.
 *
 * Params:
 * 	stream = Stream to read the archive from.
 */
auto zipArchiveReader(Stream)(auto ref Stream s) if (isStream!Stream && isSeekable!Stream)
{
    return ZipArchiveReader!Stream(s);
}

/**
 * This structure is used to read Zip archives.
 */
struct ZipArchiveReader(Stream) if (isStream!Stream && isSeekable!Stream)
{
    private Stream _stream;
    private FileHeader[] _headers;

    /**
	 * Opens an existing zip archive from a stream.
	 *
	 * Params:
	 * 	stream = Stream to the read archive from.
	 */
    this()(auto ref Stream stream)
    {
        _stream = stream;
        readCentralDirectory();
    }

    private void readCentralDirectory()
    {
        auto eocd = readEocdRecord();
        _headers = new FileHeader[eocd.entriesInCentralDir];
        _stream.seekTo(eocd.offsetOfCentralDirFromStartingDisk);
        auto mem = _stream.copyToMemory(eocd.sizeOfCentralDir);
        foreach (i, ref header; _headers)
        {
            if (mem.decode!uint != FileHeader.signature)
                throw new ZipException("Invalid file header signature");
            header.read(mem);
        }
    }

    private EndOfCentralDirRecord readEocdRecord()
    {
        enum maxOffset = uint.sizeof + EndOfCentralDirRecord.RawData.sizeof + ushort.max;
        size_t blockSize = min(maxOffset, _stream.length);
        _stream.seekTo(-blockSize, From.end);
        auto block = uninitializedArray!(ubyte[])(blockSize);
        _stream.readExactly(block);
        if (blockSize >= EndOfCentralDirRecord.RawData.sizeof)
        {
            for (size_t i = blockSize - EndOfCentralDirRecord.RawData.sizeof; i >= 0;
                    --i)
            {
                if (*(cast(uint*)(block.ptr + i)) == EndOfCentralDirRecord.signature)
                {
                    auto mem = memoryStream(block[i + 4 .. $]);
                    EndOfCentralDirRecord eocd;
                    eocd.read(mem);
                    return eocd;
                }
            }
        }
        throw new ZipException("End of Central Directory record not found");
    }

    /**
	 * Returns an input range containing all archive members.
	 */
    @nogc @safe @property auto entries() pure nothrow
    {
        import std.algorithm : map;

        return _headers.map!(header => ZipEntry(_stream, header));
    }

    /**
     * Zip entry structure.
     */
    struct ZipEntry
    {
        private Stream _stream;
        private FileHeader _header;

        /**
	    * Returns the name of an entry.
	    */
        @property const(char[]) fileName()
        {
            if (_header.flags.efs)
            {
                return cast(char[]) _header.fileName;
            }
            else
            {
                return cp437toUtf8(_header.fileName);
            }
        }

        /**
	     * Returns the comment associated to an entry.
	     */
        @property const(char[]) comment()
        {
            if (_header.flags.efs)
            {
                return cast(char[]) _header.comment;
            }
            else
            {
                return cp437toUtf8(_header.comment);
            }
        }

        /**
	     * Returns the size of an of an entry in bytes.
	     */
        @property @safe @nogc size() pure nothrow
        {
            return _header.uncompressedSize;
        }

        /**
	     * Returns an input stream with the contents of an entry.
	     */
        auto openReader()
        {
            import streams.zlib;
            import streams.bzip;

            _stream.seekTo(_header.relativeOffsetOfLocalHeader);
            if (_stream.decode!uint != LocalFileHeader.signature)
                throw new ZipException("Invalid local file header signature");
            LocalFileHeader local;
            local.read(_stream);
            auto slice = sliceStream(_stream, _stream.position, _header.compressedSize);
            switch (_header.compressionMethod)
            {
            case 0:
                return wrapSource(slice);
            case 8:
                return wrapSource(zlibInputStream(slice, Encoding.None));
            case 12:
                return wrapSource(bzipInputStream(slice));
            default:
                throw new ZipException("Unsupported compression method");
            }

        }
    }
}

class ZipException : Exception
{
    @nogc @safe this(in string message, in string file = __FILE__,
        size_t line = __LINE__, Throwable next = null) pure nothrow
    {
        super(message, file, line, next);
    }
}

/**
 * Converts CP437 encoded bytes to UTF-8.
 * 
 * Note: It returns the original array if no conversion is required.
 */
static char[] cp437toUtf8(ubyte[] bytes)
{
    /*
	 * we check if the buffer contains special
	 * cp437 codes which map to 2-byte utf8 codepoints
	 */
    int highCodes = 0;
    for (int i = 0; i < bytes.length; i++)
        if (bytes[i] > 127)
            highCodes++;
    if (highCodes == 0)
        return cast(char[]) bytes;
    /*
	 * copy bytes one by one, or two in case
	 * of a special codepoint
	 */
    auto buffer = uninitializedArray!(char[])(bytes.length + highCodes);
    for (int i = 0, j = 0; i < bytes.length; i++)
    {
        if (bytes[i] > 127)
        {
            auto next = j + 2;
            buffer[j .. next] = cp437toUtf8(bytes[i])[];
            j = next;
        }
        else
        {
            buffer[j] = bytes[i];
            j++;
        }
    }
    return buffer;
}

/**
 * Converts CP437 encoded byte to UTF-8 codepoint(s);
 */
static string cp437toUtf8(ubyte code)
{
    switch (code)
    {
    case 0x80:
        return [0xc3, 0x87];
    case 0x81:
        return [0xc3, 0xbc];
    case 0x82:
        return [0xc3, 0xa9];
    case 0x83:
        return [0xc3, 0xa2];
    case 0x84:
        return [0xc3, 0xa4];
    case 0x85:
        return [0xc3, 0xa0];
    case 0x86:
        return [0xc3, 0xa5];
    case 0x87:
        return [0xc3, 0xa7];
    case 0x88:
        return [0xc3, 0xaa];
    case 0x89:
        return [0xc3, 0xab];
    case 0x8a:
        return [0xc3, 0xa8];
    case 0x8b:
        return [0xc3, 0xaf];
    case 0x8c:
        return [0xc3, 0xae];
    case 0x8d:
        return [0xc3, 0xac];
    case 0x8e:
        return [0xc3, 0x84];
    case 0x8f:
        return [0xc3, 0x85];
    case 0x90:
        return [0xc3, 0x89];
    case 0x91:
        return [0xc3, 0xa6];
    case 0x92:
        return [0xc3, 0x86];
    case 0x93:
        return [0xc3, 0xb4];
    case 0x94:
        return [0xc3, 0xb6];
    case 0x95:
        return [0xc3, 0xb2];
    case 0x96:
        return [0xc3, 0xbb];
    case 0x97:
        return [0xc3, 0xb9];
    case 0x98:
        return [0xc3, 0xbf];
    case 0x99:
        return [0xc3, 0x96];
    case 0x9a:
        return [0xc3, 0x9c];
    case 0x9b:
        return [0xc2, 0xa2];
    case 0x9c:
        return [0xc2, 0xa3];
    case 0x9d:
        return [0xc2, 0xa5];
    case 0xa0:
        return [0xc3, 0xa1];
    case 0xa1:
        return [0xc3, 0xad];
    case 0xa2:
        return [0xc3, 0xb3];
    case 0xa3:
        return [0xc3, 0xba];
    case 0xa4:
        return [0xc3, 0xb1];
    case 0xa5:
        return [0xc3, 0x91];
    case 0xa6:
        return [0xc2, 0xaa];
    case 0xa7:
        return [0xc2, 0xba];
    case 0xa8:
        return [0xc2, 0xbf];
    case 0xaa:
        return [0xc2, 0xac];
    case 0xab:
        return [0xc2, 0xbd];
    case 0xac:
        return [0xc2, 0xbc];
    case 0xad:
        return [0xc2, 0xa1];
    case 0xae:
        return [0xc2, 0xab];
    case 0xaf:
        return [0xc2, 0xbb];
    case 0xe1:
        return [0xc3, 0x9f];
    case 0xe6:
        return [0xc2, 0xb5];
    case 0xf1:
        return [0xc2, 0xb1];
    case 0xf6:
        return [0xc3, 0xb7];
    case 0xf8:
        return [0xc2, 0xb0];
    case 0xfa:
        return [0xc2, 0xb7];
    case 0xfd:
        return [0xc2, 0xb2];
    case 0xff:
        return [0xc2, 0xa0];
    default:
        return [cast(char) code];
    }
}

unittest
{
    ubyte[] cps = [0xf6, 'a', 0xe6, 'b', 0xad, 'c'];
    // this is CP437 encoded - DIVISION SIGN, 'a', MICRO SIGN, 'b', INVERTED EXCLAMATION MARK, 'c'
    const str = cp437toUtf8(cps);
    assert(str == "÷aµb¡c");
}
