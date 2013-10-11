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

    equals?: func (other: This) -> Bool {
        if(this bytes length != other bytes length) {
            false
        } else {
            memcmp(this bytes data, other bytes data, this bytes length) == 0
        }
    }

    map: func (options: Int) -> This {
        newBytes: Int32*
        newLength := utf8proc_map_gc(bytes data, bytes length, newBytes&, options)
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
