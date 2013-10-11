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


/**
 * The String class represents character strings.
 * 
 * The String class is immutable by default, this means every writing operation
 * is done on a clone, which is then returned
 */
String: class extends Iterable<Codepoint> {
    _buffer: Buffer

    /** Does not copy. */
    init: func ~fromBuffer (=_buffer) {
    }

    init: func ~fromCStr (s: CString) {
        init(s, s length())
    }

    init: func ~fromCStrAndLength (s: CString, length: SizeT) {
        _buffer = Buffer new(s, length)
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

    /** Typically, one needs to know the number of stored bytes,
     * not codepoints. Thus, `length` returns the number of bytes. */
    length: func -> SizeT {
        _buffer size
    }

    clone: func -> This {
        new(_buffer clone())
    }

    equals?: func (other: This) -> Bool {
        if(this == null) return (other == null)
        if(other == null) return false
        _buffer equals?(other _buffer)
    }

    iterator: func -> Iterator<Codepoint> {
        Utf8StringIterator<Codepoint> new(this)
    }

    substring: func ~tillEnd (start: Int) -> This { substring(start, size) }

    substring: func (start: Int, end: Int) -> This{
        result := _buffer clone()
        result substring(start, end)
        result toString()
    }

    times: func (count: Int) -> This {
        result := _buffer clone(size * count)
        result times(count)
        result toString()
    }

    append: func ~str (other: This) -> This {
        if(!other) return this
        result := _buffer clone(size + other size)
        result append (other _buffer)
        result toString()
    }

    append: func ~char (other: Char) -> This {
        result := _buffer clone(size + 1)
        result append(other)
        result toString()
    }

    append: func ~cStr (other: CString) -> This {
        l := other length()
        result := _buffer clone(size + l)
        result append(other, l)
        result toString()
    }

    prepend: func ~str (other: This) -> This{
        result := _buffer clone()
        result prepend(other _buffer)
        result toString()
    }

    prepend: func ~char (other: Char) -> This {
        result := _buffer clone()
        result prepend(other)
        result toString()
    }

    empty?: func -> Bool { _buffer empty?() }

    startsWith?: func (s: This) -> Bool { _buffer startsWith? (s _buffer) }

    startsWith?: func ~char(c: Char) -> Bool { _buffer startsWith?(c) }

    endsWith?: func (s: This) -> Bool { _buffer endsWith? (s _buffer) }

    endsWith?: func ~char(c: Char) -> Bool { _buffer endsWith?(c) }

    find : func (what: This, offset: Int, searchCaseSensitive := true) -> Int {
        _buffer find(what _buffer, offset, searchCaseSensitive)
    }

    findAll: func ( what : This, searchCaseSensitive := true) -> ArrayList <Int> {
        _buffer findAll(what _buffer, searchCaseSensitive)
    }

    replaceAll: func ~str (what, whit : This, searchCaseSensitive := true) -> This {
        result := _buffer clone()
        result replaceAll (what _buffer, whit _buffer, searchCaseSensitive)
        result toString()
    }

    replaceAll: func ~char(oldie, kiddo: Char) -> This {
        (_buffer clone()) replaceAll~char(oldie, kiddo). toString()
    }
    
    map: func ~somethingElse (f: Func (Char) -> Char) -> This {
        (_buffer clone()) map(f). toString()
    }

    _bufArrayListToStrArrayList: func (x: ArrayList<Buffer>) -> ArrayList<This> {
        result := ArrayList<This> new( x size )
        for (i in x) result add (i toString())
        result
    }

    toLower: func -> This {
        (_buffer clone()) toLower(). toString()
    }

    toUpper: func -> This {
        (_buffer clone()) toUpper(). toString()
    }

    capitalize: func -> This {
        match (size) {
            case 0 => this
            case 1 => toUpper()
            case =>
                this[0..1] toUpper() + this[1..-1]
        }
    }

    indexOf: func ~char (c: Char, start: Int = 0) -> Int { _buffer indexOf(c, start) }

    indexOf: func ~string (s: This, start: Int = 0) -> Int { _buffer indexOf(s _buffer, start) }

    contains?: func ~char (c: Char) -> Bool { _buffer contains?(c) }

    contains?: func ~string (s: This) -> Bool { _buffer contains?(s _buffer) }

    trim: func ~pointer(s: Char*, sLength: Int) -> This {
        result := _buffer clone()
        result trim~pointer(s, sLength)
        result toString()
    }

    trim: func ~string(s : This) -> This {
        result := _buffer clone()
        result trim~buf(s _buffer)
        result toString()
    }

    trim: func ~char (c: Char) -> This {
        result := _buffer clone()
        result trim~char(c)
        result toString()
    }

    trim: func ~whitespace -> This {
        result := _buffer clone()
        result trim~whitespace()
        result toString()
    }

    trimLeft: func ~space -> This {
        result := _buffer clone()
        result trimLeft~space()
        result toString()
    }

    trimLeft: func ~char (c: Char) -> This {
        result := _buffer clone()
        result trimLeft~char(c)
        result toString()
    }

    trimLeft: func ~string (s: This) -> This {
        result := _buffer clone()
        result trimLeft~buf(s _buffer)
        result toString()
    }

    trimLeft: func ~pointer (s: Char*, sLength: Int) -> This {
        result := _buffer clone()
        result trimLeft~pointer(s, sLength)
        result toString()
    }

    trimRight: func ~space -> This {
        result := _buffer clone()
        result trimRight~space()
        result toString()
    }

    trimRight: func ~char (c: Char) -> This {
        result := _buffer clone()
        result trimRight~char(c)
        result toString()
    }

    trimRight: func ~string (s: This) -> This{
        result := _buffer clone()
        result trimRight~buf( s _buffer )
        result toString()
    }

    trimRight: func ~pointer (s: Char*, sLength: Int) -> This{
        result := _buffer clone()
        result trimRight~pointer(s, sLength)
        result toString()
    }

    reverse: func -> This {
        result := _buffer clone()
        result reverse()
        result toString()
    }

    count: func (what: Char) -> Int { _buffer count (what) }

    count: func ~string (what: This) -> Int { _buffer count~buf(what _buffer) }

    lastIndexOf: func (c: Char) -> Int { _buffer lastIndexOf(c) }

    print: func { _buffer print() }

    println: func { if(_buffer != null) _buffer println() }
    
    println: func ~withStream (stream: FStream) { if(_buffer != null) _buffer println(stream) }

    toInt: func -> Int                       { _buffer toInt() }
    toInt: func ~withBase (base: Int) -> Int { _buffer toInt~withBase(base) }
    toLong: func -> Long                        { _buffer toLong() }
    toLong: func ~withBase (base: Long) -> Long { _buffer toLong~withBase(base) }
    toLLong: func -> LLong                         { _buffer toLLong() }
    toLLong: func ~withBase (base: LLong) -> LLong { _buffer toLLong~withBase(base) }
    toULong: func -> ULong                         { _buffer toULong() }
    toULong: func ~withBase (base: ULong) -> ULong { _buffer toULong~withBase(base) }
    toFloat: func -> Float                         { _buffer toFloat() }
    toDouble: func -> Double                       { _buffer toDouble() }
    toLDouble: func -> LDouble                     { _buffer toLDouble() }

    /*forward: func -> BufferIterator<Char> {
        _buffer forward()
    }

    backward: func -> BackIterator<Char> {
        _buffer backward()
    }

    backIterator: func -> BufferIterator<Char> {
        _buffer backIterator()
    }*/

    cformat: final func ~str (...) -> This {
        list: VaList
        va_start(list, this)
        numBytes := vsnprintf(null, 0, _buffer data, list)
        va_end(list)

        copy := Buffer new(numBytes)
        copy size = numBytes
        va_start(list, this)
        vsnprintf(copy data, numBytes + 1, _buffer data, list)
        va_end(list)
        
        new(copy)
    }

    toCString: func -> CString { _buffer data as CString }

}

/* conversions C world -> String */

operator implicit as (c: Char*) -> String {
    c ? String new(c, strlen(c)) : null
}

operator implicit as (c: CString) -> String {
    c ? String new(c, strlen(c)) : null
}

/* conversions String -> C world */

operator implicit as (s: String) -> Char* {
    s ? s toCString() : null
}

operator implicit as (s: String) -> CString {
    s ? s toCString() : null
}

/* Comparisons */

operator == (str1: String, str2: String) -> Bool {
    str1 equals?(str2)
}

operator != (str1: String, str2: String) -> Bool {
    !str1 equals?(str2)
}

/* Access and modification */

operator [] (string: String, index: Int) -> Char {
    string _buffer [index]
}

operator [] (string: String, range: Range) -> String {
    string substring(range min, range max)
}

/* Concatenation and other fun stuff */

operator * (string: String, count: Int) -> String {
    string times(count)
}

operator + (left, right: String) -> String {
    left append(right)
}

operator + (left: String, right: CString) -> String {
    left append(right)
}

operator + (left: String, right: Char) -> String {
    left append(right)
}

operator + (left: Char, right: String) -> String {
    right prepend(left)
}

operator + (left: LLong, right: String) -> String {
    left toString() append(right)
}

operator + (left: String, right: LLong) -> String {
    left append(right toString())
}

operator + (left: LDouble, right: String) -> String {
    left toString() append(right)
}

operator + (left: String, right: LDouble) -> String {
    left append(right toString())
}

// constructor to be called from string literal initializers
makeStringLiteral: func (str: CString, strLen: Int) -> String {
    String new(Buffer new(str, strLen, true))
}

// lame static function to be called by int main, so i dont have to metaprogram it
import structs/ArrayList

strArrayListFromCString: func (argc: Int, argv: Char**) -> ArrayList<String> {
    result := ArrayList<String> new()
    argc times(|i| result add(argv[i] as CString toString()))
    result
}

strArrayListFromCString: func ~hack (argc: Int, argv: String*) -> ArrayList<String> {
    strArrayListFromCString(argc, argv as Char**)
}

cStringPtrToStringPtr: func (cstr: CString*, len: Int) -> String* {
    // Mostly to allow main to accept String*
    // func-name sucks, I am open to all suggestions 

    toRet: String* = gc_malloc(Pointer size * len) // otherwise the pointers are stack-allocated 
    for (i in 0..len) {
        toRet[i] = makeStringLiteral(cstr[i], cstr[i] length())
    }
    toRet
}

Utf8StringIterator: class <T> extends Iterator<Codepoint> {
    bytesRead := 0
    str: String

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
