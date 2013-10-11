use utf8proc

import lang/[Codepoint, IO]

utf8proc_iterate: extern func (Octet*, SSizeT, Int32*) -> SSizeT
utf8proc_decompose: extern func (Octet*, SSizeT, Int32*, SSizeT, Int) -> SSizeT
utf8proc_reencode: extern func (Int32*, SSizeT, Int) -> SSizeT

Utf8ProcOptions: enum {
    NULLTERM =  (1<<0)
    STABLE =    (1<<1)
    COMPAT =    (1<<2)
    COMPOSE =   (1<<3)
    DECOMPOSE = (1<<4)
    IGNORE =    (1<<5)
    REJECTNA =  (1<<6)
    NLF2LS =    (1<<7)
    NLF2PS =    (1<<8)
    NLF2LF =    (NLF2LS | NLF2PS)
    STRIPCC =   (1<<9)
    CASEFOLD =  (1<<10)
    CHARBOUND = (1<<11)
    LUMP =      (1<<12)
    STRIPMARK = (1<<13)
}

/** Pretty much only a translated version of `utf8proc_map`, modified
 * to use the boehm gc. The original utf8proc_map uses malloc and free
 * and I don't see any options to customize them, so I figured this
 * would be the cleanest solution.
  */
utf8proc_map_gc: func (str: Octet*, strlen: SSizeT, dstptr: Octet**, options: Int) -> SSizeT {
    buffer: Int32*
    result: SSizeT
    dstptr@ = null
    result = utf8proc_decompose(str, strlen, null, 0, options)
    if(result < 0) return result
    buffer = gc_malloc(result * Int32 size + 1)
    if(!buffer) return -1 // UTF8PROC_ERROR_NOMEM
    result = utf8proc_decompose(str, strlen, buffer, result, options)
    if(result < 0) {
        // TODO: free?
        return result
    }
    result = utf8proc_reencode(buffer, result, options)
    if(result < 0) {
        // TODO: free?
        return result
    }
    newptr: Int32* = gc_realloc(buffer, (result as SizeT) + 1) // TODO: Is this the NULL byte?
    if(newptr) buffer = newptr
    dstptr@ = buffer as Octet*
    result
}

/** given a sequence of bytes, count all codepoints. That's probably slow,
 * don't do it all day long. */
countCodepoints: func (bytes: Buffer) -> SizeT {
    remaining := bytes size
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
    _buffer: Buffer

    /** Does not copy. */
    init: func ~fromBuffer (=_buffer) {
    }

    /** Construct a UTF-8 string from a normal ooc String, which is interpreted
     * as UTF-8. So, just the bytes are copied. */
    init: func ~fromString (input: String) {
        _buffer = input _buffer clone()
    }

    /** Read data from an array, does not copy. */
    init: func ~fromArray (bytes: Octet[]) {
        _buffer = Buffer new(bytes)
    }

    /** Read data from memory, does not copy. */
    init: func ~fromMemory (memory: Octet*, size: SizeT) {
        _buffer = Buffer new(memory as Char*, size) // TODO should not have to cast
    }

    /** This is the number of stored codepoints. */
    codepoints: SizeT {
        get {
            countCodepoints(_buffer)
        }
    }

    /** This is the number of stored bytes (utf-8). */
    size: SizeT {
        get {
            _buffer size
        }
    }

    clone: func -> This {
        new(_buffer clone())
    }

    iterator: func -> Iterator<Codepoint> {
        Utf8StringIterator<Codepoint> new(this)
    }

    print: func {
        fwrite(_buffer data, 1, _buffer size, stdout)
    }

    println: func {
        print()
        "\n" print()
    }

    equals?: func (other: This) -> Bool {
        if(this == null) return (other == null)
        if(other == null) return false
        _buffer equals?(other _buffer)
    }

    map: func (options: Int) -> This {
        newBytes: Int32*
        newLength := utf8proc_map_gc(_buffer data as Octet*, _buffer size, newBytes&, options) // TODO dat cast
        if(newLength < 0) {
            UnicodeError new(newLength) throw()
        }
        This new(newBytes, newLength)
    }

    normalizeNFC: func -> This {
        map((Utf8ProcOptions STABLE | Utf8ProcOptions COMPOSE | Utf8ProcOptions COMPAT) as Int)
    }

    normalizeNFD: func -> This {
        map((Utf8ProcOptions STABLE | Utf8ProcOptions DECOMPOSE | Utf8ProcOptions COMPAT) as Int)
    }
}

Utf8StringIterator: class <T> extends Iterator<Codepoint> {
    bytesRead := 0
    str: Utf8String

    init: func ~withStr (=str) {
    }

    hasNext?: func -> Bool {
        bytesRead < str _buffer size
    }

    next: func -> T {
        // calculate the pointer to the current utf-8 code unit
        ptr := str _buffer data as Octet* + bytesRead
        current: Codepoint
        bytesJustRead := utf8proc_iterate(ptr, str _buffer size - bytesRead, current&)
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
