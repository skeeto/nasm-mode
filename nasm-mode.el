;;; nasm-mode.el --- NASM x86 assembly major mode -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Christopher Wellons <wellons@nullprogram.com>
;; URL: https://github.com/skeeto/nasm-mode
;; Version: 1.1.1
;; Package-Requires: ((emacs "24.3"))

;;; Commentary:

;; A major mode for editing NASM x86 assembly programs.  It includes
;; syntax highlighting, automatic indentation, and imenu integration.
;; Unlike Emacs' generic `asm-mode`, it understands NASM-specific
;; syntax.

;; NASM Home: http://www.nasm.us/

;; Labels without colons are not recognized as labels by this mode,
;; since, without a parser equal to that of NASM itself, it's
;; otherwise ambiguous between macros and labels.  This covers both
;; indentation and imenu support.

;; The keyword lists are up to date as of NASM 2.12.01.
;; http://www.nasm.us/doc/nasmdocb.html

;; TODO:
;; [ ] Line continuation awareness
;; [x] Don't run comment command if type ';' inside a string
;; [ ] Nice multi-; comments, like in asm-mode
;; [x] Be able to hit tab after typing mnemonic and insert a TAB
;; [ ] Autocompletion
;; [ ] Help menu with basic summaries of instructions
;; [ ] Highlight errors, e.g. size mismatches "mov al, dword [rbx]"
;; [ ] Work nicely with outline-minor-mode
;; [ ] Highlighting of multiline macro definition arguments

;;; Code:

(require 'imenu)
(require 'nasmtok)

(defgroup nasm-mode ()
  "Options for `nasm-mode'."
  :group 'languages)

(defgroup nasm-mode-faces ()
  "Faces used by `nasm-mode'."
  :group 'nasm-mode)

(defcustom nasm-basic-offset (default-value 'tab-width)
  "Indentation level for `nasm-mode'."
  :type 'integer
  :group 'nasm-mode)

(defcustom nasm-after-mnemonic-whitespace :tab
  "In `nasm-mode', determines the whitespace to use after mnemonics.
This can be :tab, :space, or nil (do nothing)."
  :type '(choice (const :tab) (const :space) (const nil))
  :group 'nasm-mode)

(defface nasm-registers
  '((t :inherit (font-lock-variable-name-face)))
  "Face for registers."
  :group 'nasm-mode-faces)

(defface nasm-prefix
  '((t :inherit (font-lock-builtin-face)))
  "Face for prefix."
  :group 'nasm-mode-faces)

(defface nasm-types
  '((t :inherit (font-lock-type-face)))
  "Face for types."
  :group 'nasm-mode-faces)

(defface nasm-instructions
  '((t :inherit (font-lock-builtin-face)))
  "Face for instructions."
  :group 'nasm-mode-faces)

(defface nasm-directives
  '((t :inherit (font-lock-keyword-face)))
  "Face for directives."
  :group 'nasm-mode-faces)

(defface nasm-preprocessor
  '((t :inherit (font-lock-preprocessor-face)))
  "Face for preprocessor directives."
  :group 'nasm-mode-faces)

(defface nasm-labels
  '((t :inherit (font-lock-function-name-face)))
  "Face for nonlocal labels."
  :group 'nasm-mode-faces)

(defface nasm-local-labels
  '((t :inherit (font-lock-function-name-face)))
  "Face for local labels."
  :group 'nasm-mode-faces)

(defface nasm-section-name
  '((t :inherit (font-lock-type-face)))
  "Face for section name face."
  :group 'nasm-mode-faces)

(defface nasm-constant
  '((t :inherit (font-lock-constant-face)))
  "Face for constant."
  :group 'nasm-mode-faces)

;; Perhaps they are not all "types" strictly speaking, but they share the same
;; syntax highlighting.
(eval-and-compile
  (defconst nasm-types
    (append nasm-decorators nasm-functions nasm-sizes nasm-special)
    "NASM types for `nasm-mode'."))

(defconst nasm-nonlocal-label-rexexp
  "\\(\\_<[a-zA-Z_?][a-zA-Z0-9_$#@~?]*\\_>\\)\\s-*:"
  "Regexp for `nasm-mode' for matching nonlocal labels.")

(defconst nasm-local-label-regexp
  "\\(\\_<\\.[a-zA-Z_?][a-zA-Z0-9_$#@~?]*\\_>\\)\\(?:\\s-*:\\)?"
  "Regexp for `nasm-mode' for matching local labels.")

(defconst nasm-label-regexp
  (concat nasm-nonlocal-label-rexexp "\\|" nasm-local-label-regexp)
  "Regexp for `nasm-mode' for matching labels.")

(defconst nasm-constant-regexp
  "\\_<$?[-+]?[0-9][-+_0-9A-Fa-fHhXxDdTtQqOoBbYyeE.]*\\_>"
  "Regexp for `nasm-mode' for matching numeric constants.")

(defconst nasm-section-name-regexp
  "^\\s-*section[ \t]+\\(\\_<\\.[a-zA-Z0-9_$#@~.?]+\\_>\\)"
  "Regexp for `nasm-mode' for matching section names.")

(defmacro nasm--opt (keywords)
  "Prepare KEYWORDS for `looking-at'."
  `(eval-when-compile
     (regexp-opt ,keywords 'symbols)))

(defconst nasm-imenu-generic-expression
  `((nil ,(concat "^\\s-*" nasm-nonlocal-label-rexexp) 1)
    (nil ,(concat (nasm--opt '("%define" "%macro"))
                  "\\s-+\\([a-zA-Z0-9_$#@~.?]+\\)") 2))
  "Expressions for `imenu-generic-expression'.")

(defconst nasm-full-instruction-regexp
  (eval-when-compile
    (let ((pfx (nasm--opt nasm-prefix))
          (ins (nasm--opt nasm-instructions)))
      (concat "^\\(" pfx "\\s-+\\)?" ins "$")))
  "Regexp for `nasm-mode' matching a valid full NASM instruction field.
This includes prefixes or modifiers (eg \"mov\", \"rep mov\", etc match)")

(defconst nasm-font-lock-keywords
  `((,nasm-section-name-regexp (1 'nasm-section-name))
    (,(nasm--opt nasm-registers) . 'nasm-registers)
    (,(nasm--opt nasm-prefix) . 'nasm-prefix)
    (,(nasm--opt nasm-types) . 'nasm-types)
    (,(nasm--opt nasm-instructions) . 'nasm-instructions)
    (,(nasm--opt nasm-pp-directives) . 'nasm-preprocessor)
    (,(concat "^\\s-*" nasm-nonlocal-label-rexexp) (1 'nasm-labels))
    (,(concat "^\\s-*" nasm-local-label-regexp) (1 'nasm-local-labels))
    (,nasm-constant-regexp . 'nasm-constant)
    (,(nasm--opt nasm-directives) . 'nasm-directives))
  "Keywords for `nasm-mode'.")

(defconst nasm-mode-syntax-table
  (with-syntax-table (copy-syntax-table)
    (modify-syntax-entry ?_  "_")
    (modify-syntax-entry ?#  "_")
    (modify-syntax-entry ?@  "_")
    (modify-syntax-entry ?\? "_")
    (modify-syntax-entry ?~  "_")
    (modify-syntax-entry ?\. "w")
    (modify-syntax-entry ?\; "<")
    (modify-syntax-entry ?\n ">")
    (modify-syntax-entry ?\" "\"")
    (modify-syntax-entry ?\' "\"")
    (modify-syntax-entry ?\` "\"")
    (syntax-table))
  "Syntax table for `nasm-mode'.")

(defvar nasm-mode-map
  (let ((map (make-sparse-keymap)))
    (prog1 map
      (define-key map (kbd ":") #'nasm-colon)
      (define-key map (kbd ";") #'nasm-comment)
      (define-key map [remap join-line] #'nasm-join-line)))
  "Key bindings for `nasm-mode'.")

(defun nasm-colon ()
  "Insert a colon and convert the current line into a label."
  (interactive)
  (call-interactively #'self-insert-command)
  (nasm-indent-line))

(defun nasm-indent-line ()
  "Indent current line (or insert a tab) as NASM assembly code.
This will be called by `indent-for-tab-command' when TAB is
pressed.  We indent the entire line as appropriate whenever POINT
is not immediately after a mnemonic; otherwise, we insert a tab."
  (interactive)
  (let ((before      ; text before point and after indentation
         (save-excursion
           (let ((point (point))
                 (bti (progn (back-to-indentation) (point))))
             (buffer-substring-no-properties bti point)))))
    (if (string-match nasm-full-instruction-regexp before)
        ;; We are immediately after a mnemonic
        (cl-case nasm-after-mnemonic-whitespace
          (:tab   (insert "\t"))
          (:space (insert-char ?\s nasm-basic-offset)))
      ;; We're literally anywhere else, indent the whole line
      (let ((orig (- (point-max) (point))))
        (back-to-indentation)
        (if (or (looking-at (nasm--opt nasm-directives))
                (looking-at (nasm--opt nasm-pp-directives))
                (looking-at "\\[")
                (looking-at ";;+")
                (looking-at nasm-label-regexp))
            (indent-line-to 0)
          (indent-line-to nasm-basic-offset))
        (when (> (- (point-max) orig) (point))
          (goto-char (- (point-max) orig)))))))

(defun nasm--current-line ()
  "Return the current line as a string."
  (save-excursion
    (let ((start (progn (beginning-of-line) (point)))
          (end (progn (end-of-line) (point))))
      (buffer-substring-no-properties start end))))

(defun nasm--empty-line-p ()
  "Return non-nil if current line has non-whitespace."
  (not (string-match-p "\\S-" (nasm--current-line))))

(defun nasm--line-has-comment-p ()
  "Return non-nil if current line contains a comment."
  (save-excursion
    (end-of-line)
    (nth 4 (syntax-ppss))))

(defun nasm--line-has-non-comment-p ()
  "Return non-nil of the current line has code."
  (let* ((line (nasm--current-line))
         (match (string-match-p "\\S-" line)))
    (when match
      (not (eql ?\; (aref line match))))))

(defun nasm--inside-indentation-p ()
  "Return non-nil if point is within the indentation."
  (save-excursion
    (let ((point (point))
          (start (progn (beginning-of-line) (point)))
          (end (progn (back-to-indentation) (point))))
      (and (<= start point) (<= point end)))))

(defun nasm-comment-indent ()
  "Compute desired indentation for comment on the current line."
  comment-column)

(defun nasm-insert-comment ()
  "Insert a comment if the current line doesn’t contain one."
  (let ((comment-insert-comment-function nil))
    (comment-indent)))

(defun nasm-comment (&optional arg)
  "Begin or edit a comment with context-sensitive placement.

The right-hand comment gutter is far away from the code, so this
command uses the mark ring to help move back and forth between
code and the comment gutter.

* If no comment gutter exists yet, mark the current position and
  jump to it.
* If already within the gutter, pop the top mark and return to
  the code.
* If on a line with no code, just insert a comment character.
* If within the indentation, just insert a comment character.
  This is intended prevent interference when the intention is to
  comment out the line.

With a prefix ARG, kill the comment on the current line with
`comment-kill'."
  (interactive "p")
  (if (not (eql arg 1))
      (comment-kill nil)
    (cond
     ;; Empty line, or inside a string? Insert.
     ((or (nasm--empty-line-p) (nth 3 (syntax-ppss)))
      (insert ";"))
     ;; Inside the indentation? Comment out the line.
     ((nasm--inside-indentation-p)
      (insert ";"))
     ;; Currently in a right-side comment? Return.
     ((and (nasm--line-has-comment-p)
           (nasm--line-has-non-comment-p)
           (nth 4 (syntax-ppss)))
      (goto-char (mark))
      (pop-mark))
     ;; Line has code? Mark and jump to right-side comment.
     ((nasm--line-has-non-comment-p)
      (push-mark)
      (comment-indent))
     ;; Otherwise insert.
     ((insert ";")))))

(defun nasm-join-line (&optional arg)
  "Join this line to previous, but use a tab when joining with a label.
With prefix ARG, join the current line to the following line.  See `join-line'
for more information."
  (interactive "*P")
  (join-line arg)
  (if (looking-back nasm-label-regexp (line-beginning-position))
      (let ((column (current-column)))
        (cond ((< column nasm-basic-offset)
               (delete-char 1)
               (insert-char ?\t))
              ((and (= column nasm-basic-offset) (eql ?: (char-before)))
               (delete-char 1))))
    (nasm-indent-line)))

;;;###autoload
(define-derived-mode nasm-mode prog-mode "NASM"
  "Major mode for editing NASM assembly programs."
  :group 'nasm-mode
  (make-local-variable 'indent-line-function)
  (make-local-variable 'comment-start)
  (make-local-variable 'comment-insert-comment-function)
  (make-local-variable 'comment-indent-function)
  (setf font-lock-defaults '(nasm-font-lock-keywords nil :case-fold)
        indent-line-function #'nasm-indent-line
        comment-start ";"
        comment-indent-function #'nasm-comment-indent
        comment-insert-comment-function #'nasm-insert-comment
        imenu-generic-expression nasm-imenu-generic-expression))

(provide 'nasm-mode)

;;; nasm-mode.el ends here
