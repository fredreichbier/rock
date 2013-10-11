import lang/[Codepoint, Utf8String]
import text/EscapeSequence

a := Utf8String new("\xc3\xb1")
b := Utf8String new("n\xcc\x83")

evilToString: func (u: Utf8String) -> String {
    String new(u bytes data, u bytes length)
}

compareStuff: func (a, b: Utf8String) {
    "Escaped: '%s' == '%s'" printfln(EscapeSequence escape(evilToString(a)),
                                 EscapeSequence escape(evilToString(b)))
    "Is '%s' == '%s'? %d" printfln(evilToString(a), evilToString(b), a equals?(b))
}

">>> Not normalized:" println()
compareStuff(a, b)

">>> NFC:" println()
compareStuff(a normalizeNFC(), b normalizeNFC())

">>> NFD:" println()
compareStuff(a normalizeNFD(), b normalizeNFD())
