.POSIX:
.SUFFIXES: .el .elc
EMACS = emacs

compile: nasm-mode.elc

clean:
	rm -f nasm-mode.elc

.el.elc:
	$(EMACS) -Q -batch -f batch-byte-compile $<
