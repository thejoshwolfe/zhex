# zhex

Yet another hexdump syntax.

This is a data language that compiles from text to binary primarily using hex codes similar to a hexdump.
The input is a text file in zhex syntax, described below, and the output is a stream of bytes.
A byte has 8 bits.

## Example

```
48 65 6c 6c 6f ; the string "Hello"
:0x5           ; assert that the current offset is 5
20776f726c640a ; the string " world\n"
:0xc           ; assert that the current offset is 12
; The whole file encodes the text "Hello world\n"
```

## Syntax

The entire input source file must be valid UTF-8.

Comments start with `';'` and cause the rest of the line to be ignored.

Spaces `' '` are ignored between syntactic elements.

Newlines `'\n'` delimit the end of a line.
The end of the input is also the end of a line.

Other forms of whitespace are not allowed: `'\t'`, `'\r'`, etc.

#### Byte value

Two hex digits `[0-9A-Fa-f]` encodes a byte value.
There can be whitespace between bytes, but not between the two hex digits of a byte.

Examples: `00` is the byte value `0`.
`1122` is two byte values, `17` and `34` in that order.
`11 22` is the same as `1122`.
`1 1` is invalid syntax.

#### Little endian integer

A `0x` followed by either 2, 4, 8, or 16 hex digits `[0-9A-Fa-f]` encodes a 1-, 2-, 4-, or 8-byte integer in little-endian byte order.
Examples: `0x00` is the byte value `0`.
`0x1234` is two byte values: `52` and `18` in that order.
`0x10203040` is four byte values: `64`, `48`, `32`, `16`.
`0x0011223344556677` is eight byte values: `119`, `102`, `85`, `68`, `51`, `34`, `17`, `0`.

A little endian integer must be followed by a character other than `[0-9A-Fa-f]` or be terminated by the end of the input.
If the number of digits is not 2, 4, 8, or 16, it is a syntax error.
You must include sufficient leading zeros to express the intended number of bytes the integer encodes.
Note: `0X` is not allowed; the `x` must be lowercase.

Note: the regular byte value syntax is suitable for encoding big endian integers.
To encode a big endian integer, simply omit the `0x` prefix and be sure to include sufficient leading zeros.
For example, to encode `0x0011223344556677` as a big endian integer, simply use `0011223344556677`.

#### Offset assertion

A `:0x` followed by 1 to 16 hex digits `[0-9A-Fa-f]` encodes an offset assertion.
An offset assertion requires that the specified number of bytes has been encoded thus far in the source file, otherwise it is an error.
An offset assertion must be the only syntactic element on a line, other than whitespace and possibly a comment.

Examples: `:0x0` asserts that no bytes have been encoded yet in the source file.
`:0x123` asserts that 291 bytes have been encoded so far.
`:0x0000123` is the same as `:0x123`.
