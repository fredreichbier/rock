use utf8proc

import lang/[Codepoint, IO]

utf8proc_iterate: extern func (Octet*, SSizeT, Int32*) -> SSizeT

/** given a sequence of bytes, count all codepoints. That's probably slow,
 * don't do it all day long. */
countCodepoints: func (bytes: Octet[]) -> SizeT {
    remaining := bytes length
    ptr := bytes data as Octet*
    codepoints := 0
    while(remaining > 0) {
        current: Int32
        bytesRead := utf8proc_iterate(ptr, remaining, current&)
        if(bytesRead < 0) {
            UnicodeError new(bytesRead) throw()
        } else {
            ptr += bytesRead
            remaining -= bytesRead
            codepoints += 1
        }
    }
    codepoints
}

Utf8String: class extends Iterable<Codepoint> {
    bytes: Octet[]
    codepoints: SizeT

    /** Construct a UTF-8 string from a normal ooc String, which is interpreted
     * as UTF-8. So, just the bytes are copied. */
    init: func ~fromString (input: String) {
        bytes length = input size
        bytes data = gc_malloc(bytes length * Octet size)
        memcpy(bytes data, input _buffer data, bytes length)
        init(bytes)
    }

    /** Read data from an array, does not copy. */
    init: func ~fromArray (=bytes) {
        codepoints = countCodepoints(bytes)
    }

    /** Read data from memory, does not copy. */
    init: func ~fromMemory (memory: Octet*, size: SizeT) {
        bytes length = size
        bytes data = memory
        init(bytes)    
    }

    iterator: func -> Iterator<Codepoint> {
        Utf8StringIterator<Codepoint> new(this)
    }

    print: func {
        fwrite(bytes data, 1, bytes length, stdout)
    }

    println: func {
        print()
        "\n" print()
    }
}

Utf8StringIterator: class <T> extends Iterator<Codepoint> {
    bytesRead := 0
    str: Utf8String

    init: func ~withStr (=str) {
    }

    hasNext?: func -> Bool {
        bytesRead < str bytes length
    }

    next: func -> T {
        // calculate the pointer to the current utf-8 code unit
        ptr := str bytes data as Octet* + bytesRead
        current: Codepoint
        bytesJustRead := utf8proc_iterate(ptr, str bytes length - bytesRead, current&)
        if(bytesJustRead < 0) {
            UnicodeError new(bytesJustRead) throw()
        } else {
            bytesRead += bytesJustRead
            current
        }
    }

    remove: func -> Bool {
        false // TODO
    }
}
