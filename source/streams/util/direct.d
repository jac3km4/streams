/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 */
module streams.util.direct;

/**
 * Checks if a type is a direct source.
 * Direct source allows safely slicing it's original buffer.
 * It mut define property length, getter and setter position
 * and overload dollar and slice operators.
 */ 
enum isDirectSource(Source) =
	is(typeof({
				Source s = void;
				size_t position = s.position;
				s.position = position;
				size_t length = s.length;
				const(ubyte)[] data = s[0..$];
			}));

/**
 * Provides a direct access to a number of bytes.
 * If remaining bytes is less than size, then a
 * smaller slice is returned.
 */
static const(ubyte[]) directRead(Source)(auto ref Source source, size_t size) if (isDirectSource!Source) {
	auto pos = source.position;
	auto remaining = source.length - pos;
	if(remaining == 0)
		return [];
	size_t len;
	if(remaining < size)
		len = remaining;
	else len = size;
	auto end = pos + len;
	auto slice = source[pos..end];
	source.position = end;
	return slice;
}

/**
 * Provides a direct access to bytes from current
 * position to the end of stream.
 */
static const(ubyte[]) directReadAll(Source)(auto ref Source source, size_t upTo = -1) if(isDirectSource!Source) {
	if(upTo == -1)
		return source[source.position..$];
	else return source.directRead(upTo);
}