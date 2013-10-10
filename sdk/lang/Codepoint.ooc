use utf8proc
include utf8proc

import lang/Utf8String

UnicodeError: class extends Exception {
    init: func (.message) {
        super(message)
    }

    init: func ~fromCode (code: SSizeT) {
        super(match(code) {
            case -1 => "Memory could not be allocated (NOMEM)"
            case -2 => "The given string is too long to be processed (OVERFLOW)"
            case -3 => "The given string is not a legal UTF-8 string. (INVALIDUTF8)"
            case -4 => "The REJECTNA flag was set, and an unassigned code point was found. (NOTASSIGNED)"
            case -5 => "Invalid options have been used. (INVALIDOPTS)"
            case => "Unknown error code: %d" format(code)
        })
    }
}

// U+0000 to U+10FFFF
Codepoint: cover from Int32 {
    valid?: extern(utf8proc_codepoint_valid) func -> Bool

    encodeToUtf8: extern(utf8proc_encode_char) func (dest: Octet*) -> SSizeT
    encodeToUtf8: func ~safe (dest: Octet[]) -> SSizeT {
        if(dest length < 4) {
            UnicodeError new("The given array has to be at least 4 bytes long") throw()
        }
        result := encodeToUtf8(dest data)
        if(result < 0) {
            UnicodeError new(result) throw()
        }
        result
    }

    toDescription: func -> String {
        "U+%04X" format(this)
    }

    toUtf8: func -> Utf8String {
        dest := Octet[4] new()
        bytesWritten := encodeToUtf8(dest)
        Utf8String new(dest data, bytesWritten)
    }
}
