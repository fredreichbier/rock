import lang/[Codepoint, Utf8String]

"Is unicode snowman (0x2603) valid? %d" printfln(0x2603 as Codepoint valid?())
"Is random gibberish (0x111111) valid? %d" printfln(0x111111 as Codepoint valid?())

"Convert unicode snowman to UTF-8:" println()
array := Octet[4] new()
bytes := 0x2603 as Codepoint encodeToUtf8(array)
"Wrote %d bytes." printfln(bytes)
for(i in 0..array length) {
    "[%d] %x " printf(i, array[i])
}
"" println()

// this is "þØ¬"
someString := Utf8String new("\xc3\xbe\xc3\x98\xc2\xac")
"%d bytes, %d codepoints" printfln(someString bytes length, someString codepoints)

for(cp in someString) {
    "Got codepoint: %s which is: " printf(cp toDescription())
    cp toUtf8() println()
}

"%s" printfln(0xE01E0 as Codepoint toDescription())

// taken from http://www.cl.cam.ac.uk/~mgk25/ucs/examples/UTF-8-test.txt
//invalidString := Utf8String new("\xed\xa0\x80\xed\xb0\x80")

