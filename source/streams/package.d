/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 *
 * Description:
 * 
 */
module streams;
private {
	import io.file;
	import io.stream;
}

/**
 * Convenience function. Opens a file with buffering with specified flags.
 * 
 * Params:
 * 	path = Path to the file.
 * 	flags = File flags.
 */
static auto fileStream(string path, FileFlags flags = FileFlags.readExisting) {
	return File(path, flags);
}

/**
 * Convenience function. Opens a file without buffering with specified flags.
 * 
 * Params:
 * 	path = Path to the file.
 * 	flags = File flags.
 */
static auto unbufferedFileStream(string path, FileFlags flags = FileFlags.readExisting) {
	return UnbufferedFile(path, flags);
}

/**
 * Reads a certain amount of bytes from a source
 * and writes them into a sink.
 * 
 * Params:
 * 	source = Stream to read bytes from.
 * 	sink = Stream to write into.
 * 	upTo = Maximum number of bytes to copy (all if -1).
 * 	bufferSize = The size of memory buffer to use.
 */
static void copyTo(Source, Sink)(
	auto ref Source source,
	auto ref Sink sink,
	size_t upTo = -1,
	size_t bufferSize = 64 * 1024) if (isSource!Source && isSink!Sink) {
	import std.array: uninitializedArray;

	auto buffer = uninitializedArray!(ubyte[])(bufferSize);
	if(upTo != -1) {
		size_t count = 0;
		while(count < upTo) {
			size_t read = source.read(buffer);
			if(read == 0) break;
			count += read;
			sink.write(buffer[0..read]);
		}
	} else {
		while(true) {
			size_t read = source.read(buffer);
			if(read == 0) break;
			sink.write(buffer[0..read]);
		}
	}
}