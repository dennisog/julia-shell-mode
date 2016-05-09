;;; julia-shell.el --- Major mode for an inferior Julia shell
;;
;; Author: Dennis Ogbe <dogbe@purdue.edu>
;; Package-Requires: ((julia-mode "0.3"))
;; Based on the inferior-julia part of `julia-mode.el' and functionality of
;; `matlab.el'
;;
;;; Usage:
;; Put the following code in your init.el:
;; (add-to-list 'load-path "path-to-julia-shell-mode")
;; (require 'julia-shell)
;;
;; To interact with `julia-shell' from `julia-mode', add the following code to
;; your init.el:
;; (defun my-julia-mode-hooks ()
;;   (require 'julia-shell-mode))
;; (add-hook 'julia-mode-hook 'my-julia-mode-hooks)
;; (define-key julia-mode-map (kbd "C-c C-c") 'julia-shell-run-region-or-line)
;; (define-key julia-mode-map (kbd "C-c C-s") 'julia-shell-save-and-go)
;;
;;; Commentary:
;; This major mode aims to provide a comfortable julia-shell experience in
;; emacs and is inspired by Eric Ludlam's `matlab.el'. Check README.md for more
;; information.
;;
;;; TODO
;; -  directory tracking
;; -  maybe clean up julia-shell-run-region
;;
;;; License:
;;
;; Copyright (c) 2015 Dennis Ogbe
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'comint)
(require 'julia-mode) ;; since we're using latexsubs

;;; User-changeable variables =================================================

(defgroup julia-shell nil
  "Julia-shell mode."
  :prefix "julia-shell-"
  :group 'julia)

(defcustom julia-shell-program "julia"
  "Path to the program used by `inferior-julia'."
  :type 'string
  :group 'julia-shell)

(defcustom julia-shell-arguments '()
  "Commandline arguments to pass to `julia-shell-program'.

By default, the following arguments are sent to julia:

--color=no
--load <julia-emacsinit  file>"
  :type 'string
  :group 'julia-shell)

(defcustom julia-shell-buffer-name "*Julia*"
  "The name of the inferior julia-shell buffer."
  :type 'string
  :group 'julia-shell)

(defcustom julia-shell-prompt-regexp "julia> "
  "Regexp for matching `inferior-julia' prompt."
  :type 'string
  :group 'julia-shell)

;;; Internal variables ========================================================

(defvar inferior-julia-shell-mode-map
  (let ((map (nconc (make-sparse-keymap) comint-mode-map)))
    (define-key map (kbd "TAB") 'julia-shell-tab)
    (define-key map (kbd "RET") 'julia-shell-send-input-hide-completions)
    (define-key map [up] 'comint-previous-input)
    (define-key map [down] 'comint-next-input)
    (define-key map [(backspace)] 'julia-shell-delete-backwards-no-prompt)
    map)
  "Basic mode map for `inferior-julia-shell-mode'.")

(defvar julia-shell-latex-sub-table nil
  "Hashtable holding LaTeX substitions.")

(defvar julia-title-ascii
"               _
   _       _ _(_)_
  (_)     | (_) (_)
   _ _   _| |_  __ _
  | | | | | | |/ _` |
  | | |_| | | | (_| |
 _/ |\\__'_|_|_|\\__'_|
|__/
"
"The ASCII art that gets loaded on the start of `julia-shell'.")

;;; The mode definition & startup function ====================================

(define-derived-mode inferior-julia-shell-mode comint-mode "Julia"
  "Major mode for `inferior-julia-shell'.

\\<inferior-julia-shell-mode-map>"
  nil "Julia"
  (setq comint-prompt-regexp julia-shell-prompt-regexp)
  (setq comint-prompt-read-only nil)
  (set (make-local-variable 'font-lock-defaults) '(julia-font-lock-keywords t))
  (set (make-local-variable 'paragraph-start) julia-shell-prompt-regexp)
  (set (make-local-variable 'indent-line-function) 'julia-indent-line))

;;;###autoload
(defun inferior-julia-shell ()
  "Run an inferior instance of `julia' inside Emacs."
  (interactive)
  (let* ((julia-shell-program julia-shell-program)
         (buffer (get-buffer-create julia-shell-buffer-name))
         (julia-version
          (shell-command-to-string (concat julia-shell-program " --version | awk '{print $3}'")))
         (julia-emacsinit
          (expand-file-name "julia-shell-emacstools.jl"
                            (file-name-directory (locate-library "julia-shell"))))
         ;; always load the julia EmacsTools using command-line arguments
         (julia-default-args (list "-q" "--color=no" "--load" julia-emacsinit)))
    (pop-to-buffer-same-window julia-shell-buffer-name)
    (when (not (comint-check-proc julia-shell-buffer-name))
      (animate-string (concat
                       julia-title-ascii
                       "\nA fresh approach to technical computing\n\n"
                       "Version " julia-version "\n")
                      0 0)
      (apply #'make-comint-in-buffer
             "Julia" julia-shell-buffer-name
             julia-shell-program
             nil
             (append julia-default-args julia-shell-arguments)))
    (inferior-julia-shell-mode)))

;;;###autoload
(defalias 'run-julia #'inferior-julia-shell
  "Run an inferior instance of `julia' inside Emacs.")

;;; Helper functions ==========================================================

(defun julia-shell-on-prompt-p ()
  "Return t if on a julia prompt."
  (save-excursion
    (let ((inhibit-field-text-motion t))
      (goto-char (point-max))
      (beginning-of-line)
      (looking-at julia-shell-prompt-regexp))))

(defun julia-shell-on-empty-prompt-p ()
  "Return t if on an empty julia prompt."
  (save-excursion
    (let ((inhibit-field-text-motion t))
      (goto-char (point-max))
      (beginning-of-line)
      (looking-at (concat julia-shell-prompt-regexp "\\s-*$")))))

(defun julia-shell-active-p ()
  "Return t if the julia shell is active."
  (if (get-buffer julia-shell-buffer-name)
      (with-current-buffer julia-shell-buffer-name
        (if (comint-check-proc (current-buffer))
            (current-buffer)))))

(defun julia-shell-buffer-or-complain ()
  "Return a running julia-shell buffer.  Otherwise complain."
  (or (julia-shell-active-p)
      (error "There is no active Julia buffer!")))

(defun julia-shell-delete-backwards-no-prompt ()
  "Delete one char backwards without destroying the julia prompt."
  (interactive)
  (let ((promptend (save-excursion
                     (let ((inhibit-field-text-motion t))
                       (beginning-of-line)
                       (looking-at julia-shell-prompt-regexp)
                       (match-end 0)))))
    (unless (<= (point) promptend)
      (delete-char -1))))

(defun julia-shell-send-input-hide-completions ()
  "Like `comint-send-input', but make sure to close any remaining completion windows."
  (interactive)
  (julia-shell-tab-hide-completions)
  (comint-send-input))

;;; Julia shell interaction ===================================================

(defun julia-shell-collect-command-output (command)
  "Collect output of COMMAND from an interactive julia shell without changing point."
  (let ((command-output-begin nil)
        (str nil)
        (last-cmd nil)
        (last-cmd-with-prompt nil)
        (inhibit-field-text-motion t)
        (julia-shell-buffer (julia-shell-buffer-or-complain)))
    (with-current-buffer julia-shell-buffer
      ;; save the last command and delete the old prompt
      (beginning-of-line)
      (setq last-cmd-with-prompt
            (buffer-substring (point) (line-end-position)))
      (setq last-cmd (replace-regexp-in-string
                      julia-shell-prompt-regexp "" last-cmd-with-prompt))
      (delete-region (point) (line-end-position))
      ;; send the command
      (setq command-output-begin (point))
      (comint-simple-send (get-buffer-process (current-buffer))
                          command)
      ;; collect the output
      (goto-char (point-max))
      (while (not (julia-shell-on-empty-prompt-p))
        (accept-process-output (get-buffer-process julia-shell-buffer))
        (goto-char (point-max))) ;; we now have all of the output.
      ;; save output to string
      (forward-line -1)
      (setq str (buffer-substring-no-properties command-output-begin (line-end-position)))
      ;; delete the output from the command line
      (delete-region command-output-begin (point-max))
      ;; restore prompt and insert last command
      (goto-char (point-max))
      (delete-blank-lines)
      (beginning-of-line)
      (comint-send-string (get-buffer-process (current-buffer)) "\n")
      (insert-string last-cmd)
      ;; return the shell output
      str)))

(defun julia-shell-get-completion-list (str)
  "Get a list of completions from julis, STR is the substring to complete."
    (let* ((julia-shell-buffer (julia-shell-buffer-or-complain))
           (completion-command (concat "EmacsTools.get_completions(\"" str "\")"))
           (output nil)
           (completions nil)
           (bad-string-regexp "^\\\\$")) ;; a single backslash breaks things
      (with-current-buffer julia-shell-buffer
        ;; get the completions from julia
        (unless (string-match bad-string-regexp str)
          (setq output (julia-shell-collect-command-output completion-command))
          ;; build a completion list, a list of lists
          (dolist (item (split-string output "\n"))
            (push (list item) completions))
          ;; the last command is always a newline
          (nreverse (cdr completions))))))

(defun julia-shell-get-latex-symbol-table ()
  "Return a hashtable of LaTeX symbols and their unicode counterparts."
  (let ((latexsub-table (make-hash-table :test 'equal))
        (julia-shell-buffer (julia-shell-buffer-or-complain))
        (symbol-command "EmacsTools.get_latex_symbols()")
        (output nil))
    (with-current-buffer julia-shell-buffer
      (setq output (julia-shell-collect-command-output symbol-command))
      (dolist (line (split-string output "\n"))
        (let ((table-entry nil))
          (setq table-entry (split-string line))
          (when (= (length table-entry) 2)
            (apply 'puthash (append table-entry (list latexsub-table))))))
      latexsub-table)))

(defvar julia-shell-window-exists-for-display-completion-flag nil
  "Non-nil means there was an 'other-window' available when `display-completion-list' is called.")

(defun julia-shell-tab ()
  "Suggest completions for the current command.
If the command is a LaTeX symbol, replace it with its unicode character."
  (interactive)
  ;; save the old command
  (goto-char (point-max))
  (let ((inhibit-field-text-motion t))
    (beginning-of-line))
  (re-search-forward julia-shell-prompt-regexp)
  (let* ((lastcmd (buffer-substring (point) (line-end-position)))
         (tempcmd lastcmd)
         (completions nil)
         (limitpos nil)
         (latexsub nil))
    ;; search for character which limits completion, and limit command to it
    (setq limitpos
          (if (string-match ".*\\([( /[.,;=']\\)" lastcmd)
              (1+ (match-beginning 1))
            0))
    ;; TEMPCMD will hold the LHS of a split command
    (if (not (eql limitpos 0))
        (setq tempcmd (substring lastcmd 0 limitpos)))
    ;; delete the the old command
    (setq lastcmd (substring lastcmd limitpos))
    (delete-region (+ (point) limitpos) (line-end-position))
    ;; if there is a LaTeX sub, our work is done
    ;; note: in the future, it would be good to retrieve
    ;; a list of latex subs from julia on launch and build
    ;; the hash table in julia-shell mode. This can
    ;; done in the EmacsTools julia module.
    (setq latexsub (gethash lastcmd julia-latexsubs))
    (goto-char (point-max))
    (if latexsub
        (progn (insert latexsub)
               (julia-shell-tab-hide-completions))
      ;; else collect the completion list
      ;; if we want to complete the "." operator, we want to send the left side
      ;; of the command to julia for completion
      (setq completions (julia-shell-get-completion-list
                         (if (string-match "^.*\\.$" tempcmd)
                             tempcmd
                           (if (string-match "^.*[])]" lastcmd)
                               (substring lastcmd 0 (- (length lastcmd) 1))
                             lastcmd))))
      (goto-char (point-max))
      ;; if there is only one completion, insert it right away and we're done
      (if (eq (length completions) 1)
          (progn (insert (car (car completions)))
                 (julia-shell-tab-hide-completions))
        ;; else open a completions buffer --- this (until the end of this
        ;; function) is taken unmodified from `matlab.el'
        (let ((try (try-completion lastcmd completions)))
          ;; Insert in a good completion.
          (cond ((or (eq try nil) (eq try t)
                     (and (stringp try)
                          (string= try lastcmd)))
                 (insert lastcmd)
                 ;; Before displaying the completions buffer, check to see if
                 ;; the completions window is already displayed, or if there is
                 ;; a next window to display.  This determines how to remove the
                 ;; completions later.
                 (if (get-buffer-window "*Completions*")
                     nil ;; Recycle old value of the display flag.
                   ;; Else, reset this variable.
                   (setq julia-shell-window-exists-for-display-completion-flag
                         ;; Else, it isn't displayed, save an action.
                         (if (eq (next-window) (selected-window))
                             ;; If there is no other window, the post action is
                             ;; to delete.
                             'delete
                           ;; If there is a window to display, the post
                           ;; action is to bury.
                           'bury)))
                 (with-output-to-temp-buffer "*Completions*"
                   (display-completion-list (mapcar 'car completions))))
                ((stringp try)
                 (insert try)
                 (julia-shell-tab-hide-completions))
                (t
                 (insert lastcmd))))))))

(defun julia-shell-tab-hide-completions ()
  "Hide any completion windows for `julia-shell-tab'."
    (cond ((eq julia-shell-window-exists-for-display-completion-flag 'delete)
	 (when (get-buffer "*Completions*")
	   (delete-windows-on "*Completions*")))
	((eq julia-shell-window-exists-for-display-completion-flag 'bury)
	 (let ((orig (selected-window))
	       (bw nil))
	   (while (setq bw (get-buffer-window "*Completions*"))
	     (select-window bw)
	     (bury-buffer))
	   (select-window orig))))
  ;; Reset state.
  (setq julia-shell-window-exists-for-display-completion-flag nil))

;;; Julia shell interaction from `julia-mode' =================================

(defun julia-shell-run-region (beg end)
  "Send the region between BEG and END to the Julia interpreter."
  (interactive "r")
  (let* ((julia-shell-buffer (julia-shell-buffer-or-complain))
         (last-cmd nil)
         (last-cmd-with-prompt nil)
         (inhibit-field-text-motion t)
         (command
          (let ((str (buffer-substring-no-properties beg end)))
            ;; remove blank lines
            (while (string-match "\n\\s-*\n" str)
              (setq str (concat (substring str 0 (match-beginning 0))
                                "\n"
                                (substring str (match-end 0)))))
            str)))
    (with-current-buffer julia-shell-buffer
      (if (not (julia-shell-on-prompt-p))
          (error "Julia shell is busy!")
        ;; save the last command and delete the old prompt
        (beginning-of-line)
        (setq last-cmd-with-prompt
              (buffer-substring (point) (line-end-position)))
        (setq last-cmd (replace-regexp-in-string
                        julia-shell-prompt-regexp "" last-cmd-with-prompt))
        (delete-region (point) (line-end-position))
        ;; send the command
        (comint-simple-send (get-buffer-process (current-buffer))
                            command)
        (goto-char (point-max))
        (insert last-cmd)
        (goto-char (point-max))))))

(defun julia-shell-run-region-or-line ()
  "Send the active region from BEG to END to the Julia interpreter.
If region is not active, send the current line."
  (interactive)
   (if (and transient-mark-mode mark-active)
     (julia-shell-run-region (mark) (point))
   (julia-shell-run-region (point-at-bol) (point-at-eol))))

(defun julia-shell-save-and-go ()
  "Save this file and evaluate it in a Julia shell."
  (interactive)
  (let ((julia-shell-buffer (julia-shell-buffer-or-complain))
        (filename (buffer-file-name))
        (last-cmd nil)
        (last-cmd-with-prompt nil)
        (inhibit-field-text-motion t))
    (save-buffer)
    (with-current-buffer julia-shell-buffer
      (if (not (julia-shell-on-prompt-p))
          (error "Julia shell is busy!")
        (beginning-of-line)
        (setq last-cmd-with-prompt
              (buffer-substring (point) (line-end-position)))
        (setq last-cmd (replace-regexp-in-string
                        julia-shell-prompt-regexp "" last-cmd-with-prompt))
        (delete-region (point) (line-end-position))
        (comint-simple-send (get-buffer-process (current-buffer))
                            (format "include(\"%s\")" filename))
        (goto-char (point-max))
        (insert last-cmd)
        (goto-char (point-max))))))

(provide 'julia-shell)
;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not obsolete)
;; End:
;;; julia-shell.el ends here
