/**
 * Copyright: Copyright Jacek Malec, 2016
 * License:   MIT
 * Authors:   Jacek Malec
 */
module streams.util.wrappers;
private
{
    import io.stream;
}

/**
 * Wraps any source into a generic polymorphic source.
 * 
 * Params:
 * 	stream = Stream to wrap.
 */
static GenericSource wrapSource(Stream)(auto ref Stream stream) if (isSource!Stream)
{
    return new SourceWrapper!Stream(stream);
}

/**
 * Interface for the most typical source use cases
 */
interface GenericSource
{
    /**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
    size_t read(ubyte[] buf);
    /**
	 * Reads bytes into the specified buffer.
	 * The number of bytes read is returned.
	 */
    size_t read(char[] buf);
}

class SourceWrapper(Stream) : GenericSource
{
    Stream base;

    this()(auto ref Stream s)
    {
        base = s;
    }

pragma(inline):
    final size_t read(ubyte[] buf)
    {
        return base.read(buf);
    }

pragma(inline):
    final size_t read(char[] buf)
    {
        return base.read(cast(ubyte[]) buf);
    }
}
