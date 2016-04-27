# nasm-mode

`nasm-mode` is a major mode for editing [NASM][nasm] x86 assembly
programs. It includes syntax highlighting, automatic indentation, and
imenu integration. Unlike Emacs' generic `asm-mode`, it understands
NASM-specific syntax. Requires Emacs 24.3 or higher.

The instruction and keyword lists are from NASM 2.12.01.

## Known Issues

* Due to limitations of Emacs' syntax tables, like many other major
  modes, double and single quoted strings don't properly handle
  backslashes, which, unlike backquoted strings, aren't escapes in
  NASM syntax.


[nasm]: http://www.nasm.us/
