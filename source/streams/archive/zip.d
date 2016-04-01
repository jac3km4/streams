/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * This module provides an interface to access Zip files
 */
module streams.archive.zip;
private {
	import std.algorithm: min;
	import std.array: uninitializedArray;
	import std.bitmanip: bitfields;

	import io.stream;

	import streams.data;
	import streams.memory;
	import streams.zlib;
	import streams.slice;
	import streams.util.wrappers;
}

struct LocalFileHeader {
	private enum uint signature = 0x04034b50;

	RawData data;
	alias data this;
	static assert(RawData.sizeof == 26);

	ubyte[] extraField;
	ubyte[] fileName;

	void read(Source)(auto ref Source s) if (isSource!Source) {
		data = s.rawRead!RawData;
		fileName = uninitializedArray!(ubyte[])(fileNameLength);
		s.readExactly(fileName);
		extraField = uninitializedArray!(ubyte[])(extraFieldLength);
		s.readExactly(extraField);
	}

	void write(Sink)(auto ref Sink s) if (isSink!Sink) {
		s.rawWrite(data);
		s.writeExactly(fileName);
		s.writeExactly(extraField);
	}

	private align(1) struct RawData {
	align(1):
		ushort versionRequired;
		Flags flags;
		ushort compressionMethod;
		ushort modificationTime;
		ushort modificationDate;
		uint crc32;
		uint compressedSize;
		uint uncompressedSize;
		ushort fileNameLength;
		ushort extraFieldLength;

		private align(1) struct Flags {
			mixin(bitfields!(
					bool,	"encrypted",	1,
					bool,	"bit1",	1,
					bool,	"bit2", 1,
					bool,	"unsetSize",	1,
					bool,	"enhancedDeflating",	1,
					bool,	"compressedPatchedData",	1,
					bool,	"strongEncryption",	1,
					int,	"",	4,
					bool,	"efs",	1,
					bool,	"enhancedCompression",	1,
					bool,	"encryptedCentralDir",	1,
					int,	"",	2));
		}
	}
}

struct FileHeader {
	private enum uint signature = 0x02014b50;

	RawData data;
	alias data this;
	static assert(RawData.sizeof == 42);

	const (char)[] fileName;
	ubyte[] extraField;
	const(char)[] comment;

	void read(Source)(auto ref Source s) if (isSource!Source) {
		data = s.rawRead!RawData;
		fileName = uninitializedArray!(char[])(fileNameLength);
		s.readExactly(fileName);
		extraField = uninitializedArray!(ubyte[])(extraFieldLength);
		s.readExactly(extraField);
		comment = uninitializedArray!(char[])(commentLength);
		s.readExactly(comment);
	}

	void write(Sink)(auto ref Sink s) if (isSink!Sink) {
		s.rawWrite(data);
		s.writeExactly(fileName);
		s.writeExactly(extraField);
		s.writeExactly(comment);
	}

	private align(1) struct RawData {
	align(1):
		ubyte zipVersion;
		ubyte fileAttribute;
		ushort extractVersion;
		ushort flags;
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

struct EndOfCentralDirRecord {
	private enum uint signature = 0x06054b50;
	RawData data;
	alias data this;

	char[] comment;

	void read(Source)(auto ref Source source) if (isSource!Source) {
		data = source.rawRead!RawData;
		comment = uninitializedArray!(char[])(commentLength);
		source.readExactly(comment);
	}

	void write(Sink)(auto ref Sink s) if (isSink!Sink) {
		s.rawWrite(data);
		s.writeExactly(comment);
	}

	private align(1) struct RawData {
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

auto zipArchive(Stream)(auto ref Stream s) if (isStream!Stream && isSeekable!Stream) {
	return ZipArchive!Stream(s);
}

/**
 * This structure is used to read
 * and manipulate Zip archives
 */
struct ZipArchive(Stream) if (isStream!Stream && isSeekable!Stream) {
	private Stream stream;
	FileHeader[] headers;

	/**
	 * Opens an existing zip archive from a stream
	 * 
	 * Params:
	 * 	stream = Stream to read archive from
	 */
	this()(auto ref Stream stream) {
		this.stream = stream;
		readCentralDirectory();
	}

	private void readCentralDirectory() {
		auto eocd = readEocdRecord();
		headers = new FileHeader[eocd.entriesInCentralDir];
		stream.seekTo(eocd.offsetOfCentralDirFromStartingDisk);
		auto mem = stream.copyToMemory(eocd.sizeOfCentralDir);
		foreach(i, ref header; headers) {
			if(mem.decode!uint != FileHeader.signature)
				throw new ZipException("Invalid file header signature");
			header.read(mem);
		}
	}

	private EndOfCentralDirRecord readEocdRecord() {
		enum maxOffset = uint.sizeof + EndOfCentralDirRecord.RawData.sizeof + ushort.max;
		size_t blockSize = min(maxOffset, stream.length);
		stream.seekTo(-blockSize, From.end);
		auto block = uninitializedArray!(ubyte[])(blockSize);
		stream.readExactly(block);
		auto mem = memoryStream(block);
		if(blockSize >= EndOfCentralDirRecord.RawData.sizeof) {
			for(size_t i = blockSize - EndOfCentralDirRecord.RawData.sizeof; i >= 0; --i) {
				if(*(cast(uint*)(block.ptr + i)) == EndOfCentralDirRecord.signature) {
					EndOfCentralDirRecord eocd;
					mem.seekTo(i + 4);
					eocd.read(mem);
					return eocd;
				}
			}
		}
		throw new ZipException("End of Central Directory record not found");
	}

	GenericSource openFile(ref FileHeader header) {
		stream.seekTo(header.relativeOffsetOfLocalHeader);
		if(stream.decode!uint != LocalFileHeader.signature)
			throw new ZipException("Invalid local file header signature");
		LocalFileHeader local;
		local.read(stream);
		auto slice = sliceStream(stream, stream.position, header.compressedSize);
		switch(header.compressionMethod) {
			case 0:
				return wrapSource(slice);
			case 8:
				return wrapSource(zlibStream(slice, Encoding.None));
			default:
				throw new ZipException("Unexpected compression method");
		}
	}
}