/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to access tar archives
 */
module streams.archive.tar;
private
{
    import io.stream;

    import streams.slice;
}

/**
 * 
 */
struct TARFileHeader
{
    ubyte[100] filename;
    ubyte[8] mode;
    ubyte[8] uid;
    ubyte[8] gid;
    ubyte[12] fileSize;
    ubyte[12] lastModification;
    ubyte[8] checksum;
    ubyte typeFlag;
    ubyte[100] linkedFileName;
    //USTar-specific fields -- NUL-filled in non-USTAR version
    ubyte[6] ustarIndicator;
    ubyte[2] ustarVersion;
    ubyte[32] ownerUserName;
    ubyte[32] ownerGroupName;
    ubyte[8] deviceMajorNumber;
    ubyte[8] deviceMinorNumber;
    ubyte[155] filenamePrefix;
    ubyte[12] padding; //Nothing of interest, but relevant for checksum
}

static auto tarArchive(Stream)(auto ref Stream stream) if (isStream!Stream)
{
    return TarArchive!Stream(stream);
}

struct TarArchiveBase(Stream) if (isStream!Stream && isSeekable!Stream)
{
    private Stream _stream;

    this()(auto ref Stream stream)
    {
        _stream = stream;
    }

    ByEntry byEntry()
    {
        return ByEntry(_stream);
    }

    struct ByEntry
    {
        private Stream _stream;
        Entry _current;
        private bool _eof = false;
        private size_t _nextEntry = 0;

        this()(auto ref Stream stream)
        {
            _stream = stream;
            popFront();
        }

        @property Entry front() nothrow
        {
            return _current;
        }

        void popFront()
        {
            import std.algorithm : all;
            import std.string : fromStringz;
            import std.stdio : writeln;

            ubyte[512] buffer;
            _stream.readExactly(buffer);
            auto header = *(cast(TARFileHeader*) buffer.ptr);
            if (buffer[0 .. $].all!"a == 0")
            {
                _eof = true;
            }
            else
            {
                auto pos = _stream.position;
                _current = Entry(_stream, pos, header);
                _nextEntry = pos + _current.length;
            }
        }

        @property @safe @nogc bool empty() pure nothrow
        {
            return _eof;
        }

        struct Entry
        {
            private Stream _stream;
            private size_t _position;
            private TARFileHeader _header;

            this()(auto ref Stream stream, size_t position, TARFileHeader header)
            {
                _stream = stream;
                _position = position;
                _header = header;
            }

            @property @safe @nogc size_t length() pure nothrow const
            {
                auto str = _header.fileSize;
                size_t size = 0;
                int count = 1;
                for (int j = 11; j > 0; j--, count *= 8)
                    size += (str[j - 1] - '0') * count;
                return size;
            }

            @property const(char)[] fileName() pure nothrow const
            {
                import std.string : fromStringz;

                return fromStringz(cast(char*) _header.filename);
            }

            auto openReader()
            {
                return sliceStream(_stream, _position, length);
            }
        }
    }
}

import std.typecons;
alias TarArchive(Stream) = RefCounted!(TarArchiveBase!Stream, RefCountedAutoInitialize.no);