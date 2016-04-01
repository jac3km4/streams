/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 */
module streams.util.traits;

/**
 * Checks if a type is a direct source.
 * Direct source allows safely slicing it's original buffer.
 * It mut define the member function $(D read).
 */ 
enum isDirectSource(Stream) =
	is(typeof({
				Stream s = void;
				const(ubyte)[] n = s.read(1);
			}));