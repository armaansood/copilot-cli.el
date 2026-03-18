;;; copilot-cli.el --- Run GitHub Copilot CLI inside Emacs -*- lexical-binding: t; -*-

;; Copyright (c) 2025 Armaan Sood
;;
;; Author: Armaan Sood
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.4.0"))
;; Keywords: tools, ai, copilot
;; URL: https://github.com/armaansood/copilot-cli.el
;;
;; SPDX-License-Identifier: MIT
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:

;; copilot-cli.el provides an Emacs interface for GitHub Copilot CLI, letting
;; you run interactive Copilot sessions inside terminal buffers powered by
;; `eat' or `vterm'.  Modeled after `claude-code.el' by Steve Molitor but
;; adapted for Copilot CLI.
;;
;; Usage:
;;   M-x copilot-cli          Start a Copilot CLI session
;;   M-x copilot-cli-transient  Open the transient command menu
;;
;; Enable `copilot-cli-mode' to get a command map you can bind to a prefix key:
;;   (copilot-cli-mode 1)
;;   (global-set-key (kbd "C-c C") copilot-cli-command-map)

;;; Code:

;;;; Dependencies

(require 'transient)
(require 'project)
(require 'cl-lib)

;; Silence byte-compiler about eat and vterm symbols.
(defvar eat-buffer-name)
(defvar eat-term-name)
(defvar eat-kill-buffer-on-exit)
(defvar eat--terminal)
(defvar vterm-buffer-name)
(defvar vterm-shell)
(defvar vterm-kill-buffer-on-exit)
(defvar vterm-term-environment-variable)

(declare-function eat-make "eat")
(declare-function eat-mode "eat")
(declare-function eat-semi-char-mode "eat")
(declare-function eat-emacs-mode "eat")
(declare-function eat-term-send-string "eat")
(declare-function vterm "vterm")
(declare-function vterm-mode "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
(declare-function vterm-send-key "vterm")
(declare-function vterm-copy-mode "vterm")

;;;; Customization

(defgroup copilot-cli nil
  "Run GitHub Copilot CLI inside Emacs."
  :group 'tools
  :prefix "copilot-cli-")

(defcustom copilot-cli-program "copilot"
  "Name or path of the Copilot CLI binary."
  :type 'string
  :group 'copilot-cli)

(defcustom copilot-cli-program-switches nil
  "Extra command-line flags passed to the Copilot CLI binary."
  :type '(repeat string)
  :group 'copilot-cli)

(defcustom copilot-cli-terminal-backend
  (if (eq system-type 'windows-nt) 'comint 'eat)
  "Terminal backend used for Copilot CLI buffers.

On Windows the default is `comint' since `eat' and `vterm' require
Unix pseudo-terminals.  On other systems the default is `eat'."
  :type '(choice (const :tag "comint (built-in, works everywhere)" comint)
                 (const :tag "eat" eat)
                 (const :tag "vterm" vterm))
  :group 'copilot-cli)

(defcustom copilot-cli-term-name "xterm-256color"
  "TERM environment variable value for the terminal."
  :type 'string
  :group 'copilot-cli)

(defcustom copilot-cli-startup-delay 0.1
  "Seconds to wait after creating the terminal before sending input."
  :type 'number
  :group 'copilot-cli)

(defcustom copilot-cli-enable-notifications t
  "When non-nil, show notifications on process state changes."
  :type 'boolean
  :group 'copilot-cli)

(defcustom copilot-cli-notification-function #'copilot-cli-default-notification
  "Function called to display notifications.

Called with two arguments: TITLE and MESSAGE."
  :type 'function
  :group 'copilot-cli)

(defcustom copilot-cli-confirm-kill t
  "When non-nil, ask for confirmation before killing a Copilot CLI session."
  :type 'boolean
  :group 'copilot-cli)

(defcustom copilot-cli-no-delete-other-windows nil
  "When non-nil, do not delete other windows when displaying the buffer."
  :type 'boolean
  :group 'copilot-cli)

(defcustom copilot-cli-display-window-fn #'copilot-cli-display-buffer-below
  "Function used to display the Copilot CLI buffer.

Called with one argument, the BUFFER to display."
  :type 'function
  :group 'copilot-cli)

(defcustom copilot-cli-large-buffer-threshold 100000
  "Character count above which a buffer is considered large.

When sending a large buffer to Copilot CLI, the user is prompted for
confirmation."
  :type 'integer
  :group 'copilot-cli)

(defcustom copilot-cli-start-hook nil
  "Hook run after a Copilot CLI session starts."
  :type 'hook
  :group 'copilot-cli)

(defcustom copilot-cli-newline-keybinding-style 'newline-on-shift-return
  "How to bind the newline key in the terminal buffer.

`newline-on-shift-return' means S-<return> inserts a newline while
<return> sends the input.  `newline-on-return' reverses that mapping."
  :type '(choice (const :tag "Shift-Return inserts newline" newline-on-shift-return)
                 (const :tag "Return inserts newline" newline-on-return))
  :group 'copilot-cli)

(defface copilot-cli-repl-face
  '((t :inherit default))
  "Face used in Copilot CLI terminal buffers."
  :group 'copilot-cli)

;;;; Internal Variables

(defvar copilot-cli--directory-buffer-map (make-hash-table :test #'equal)
  "Hash table mapping directory paths to their Copilot CLI buffer names.")

(defvar copilot-cli--window-widths (make-hash-table :test #'equal)
  "Hash table tracking window widths for resize optimization.")

(defvar copilot-cli-command-history nil
  "History list for commands sent to Copilot CLI.")

;;;; Command Map

(defvar copilot-cli-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "c" #'copilot-cli)
    (define-key map "d" #'copilot-cli-start-in-directory)
    (define-key map "k" #'copilot-cli-kill)
    (define-key map "K" #'copilot-cli-kill-all)
    (define-key map "t" #'copilot-cli-toggle)
    (define-key map "b" #'copilot-cli-switch-to-buffer)
    (define-key map "B" #'copilot-cli-select-buffer)
    (define-key map "s" #'copilot-cli-send-command)
    (define-key map "x" #'copilot-cli-send-command-with-context)
    (define-key map "r" #'copilot-cli-send-region)
    (define-key map "o" #'copilot-cli-send-buffer-file)
    (define-key map "y" #'copilot-cli-send-return)
    (define-key map "n" #'copilot-cli-send-escape)
    (define-key map "1" #'copilot-cli-send-1)
    (define-key map "2" #'copilot-cli-send-2)
    (define-key map "3" #'copilot-cli-send-3)
    (define-key map "z" #'copilot-cli-toggle-read-only-mode)
    (define-key map "m" #'copilot-cli-transient)
    map)
  "Keymap for Copilot CLI commands.

Bind this map to a prefix key of your choice, for example:
  (global-set-key (kbd \"C-c C\") copilot-cli-command-map)")

;;;; Terminal Backend Abstraction

(cl-defgeneric copilot-cli--term-make (backend buffer-name program switches)
  "Create a terminal buffer using BACKEND.

BUFFER-NAME is the name for the new buffer.  PROGRAM is the executable
to run.  SWITCHES is a list of extra arguments.")

(cl-defgeneric copilot-cli--term-configure (backend)
  "Configure the terminal buffer for BACKEND after creation.")

(cl-defgeneric copilot-cli--term-send-string (backend string)
  "Send STRING to the terminal managed by BACKEND.")

(cl-defgeneric copilot-cli--term-send-key (backend key)
  "Send a special KEY to the terminal managed by BACKEND.

KEY is a symbol such as `return' or `escape'.")

(cl-defgeneric copilot-cli--term-setup-keymap (backend)
  "Set up key bindings in the terminal buffer for BACKEND.")

(cl-defgeneric copilot-cli--term-customize-faces (backend)
  "Apply face customizations for BACKEND.")

;; --- eat backend ---

(cl-defmethod copilot-cli--term-make ((_backend (eql eat)) buffer-name program switches)
  "Create an eat terminal buffer.

BUFFER-NAME, PROGRAM, and SWITCHES are as described in the generic."
  (require 'eat)
  (let ((eat-term-name copilot-cli-term-name)
        (eat-kill-buffer-on-exit t)
        ;; eat-make wraps NAME in *s, so strip ours to avoid double-wrapping.
        (raw-name (if (and (string-prefix-p "*" buffer-name)
                           (string-suffix-p "*" buffer-name))
                      (substring buffer-name 1 -1)
                    buffer-name)))
    (apply #'eat-make raw-name program nil (remq nil switches))
    (get-buffer buffer-name)))

(cl-defmethod copilot-cli--term-configure ((_backend (eql eat)))
  "Configure eat terminal with semi-char mode."
  (eat-semi-char-mode))

(cl-defmethod copilot-cli--term-send-string ((_backend (eql eat)) string)
  "Send STRING to the eat terminal in the current buffer."
  (when (and (boundp 'eat--terminal) eat--terminal)
    (eat-term-send-string eat--terminal string)))

(cl-defmethod copilot-cli--term-send-key ((_backend (eql eat)) key)
  "Send KEY to the eat terminal.

KEY should be `return' or `escape'."
  (when (and (boundp 'eat--terminal) eat--terminal)
    (pcase key
      ('return (eat-term-send-string eat--terminal "\r"))
      ('escape (eat-term-send-string eat--terminal "\e"))
      (_ (eat-term-send-string eat--terminal (format "%s" key))))))

(cl-defmethod copilot-cli--term-setup-keymap ((_backend (eql eat)))
  "Set up eat-specific key bindings."
  ;; eat-semi-char-mode handles most keybindings already.
  nil)

(cl-defmethod copilot-cli--term-customize-faces ((_backend (eql eat)))
  "Apply face customizations for eat."
  (face-remap-add-relative 'default 'copilot-cli-repl-face))

;; --- vterm backend ---

(cl-defmethod copilot-cli--term-make ((_backend (eql vterm)) buffer-name program switches)
  "Create a vterm terminal buffer.

BUFFER-NAME, PROGRAM, and SWITCHES are as described in the generic."
  (require 'vterm)
  (let ((vterm-buffer-name buffer-name)
        (vterm-shell (mapconcat #'shell-quote-argument
                                (cons program switches) " "))
        (vterm-kill-buffer-on-exit t)
        (vterm-term-environment-variable copilot-cli-term-name))
    (vterm buffer-name)
    (get-buffer buffer-name)))

(cl-defmethod copilot-cli--term-configure ((_backend (eql vterm)))
  "Configure vterm terminal settings."
  ;; vterm is ready to use after creation.
  nil)

(cl-defmethod copilot-cli--term-send-string ((_backend (eql vterm)) string)
  "Send STRING to the vterm terminal in the current buffer."
  (vterm-send-string string))

(cl-defmethod copilot-cli--term-send-key ((_backend (eql vterm)) key)
  "Send KEY to the vterm terminal.

KEY should be `return' or `escape'."
  (pcase key
    ('return (vterm-send-return))
    ('escape (vterm-send-key "<escape>"))
    (_ (vterm-send-string (format "%s" key)))))

(cl-defmethod copilot-cli--term-setup-keymap ((_backend (eql vterm)))
  "Set up vterm-specific key bindings."
  ;; vterm handles most keybindings natively.
  nil)

(cl-defmethod copilot-cli--term-customize-faces ((_backend (eql vterm)))
  "Apply face customizations for vterm."
  (face-remap-add-relative 'default 'copilot-cli-repl-face))

;; --- comint backend ---
;;
;; On Windows, Copilot CLI (an Ink/React TUI) writes directly to the
;; Windows Console API, which Emacs' ConPTY does not fully bridge.
;; The workaround is to host copilot inside a PowerShell process,
;; which provides the console that Ink needs.  On Unix systems,
;; make-process with a PTY works directly.

(defun copilot-cli--comint-build-command (program switches)
  "Build the process command list for PROGRAM with SWITCHES.

On Windows, wraps the command in a PowerShell invocation so that
Ink-based TUI apps get a proper console host."
  (let ((args (remq nil switches)))
    (if (eq system-type 'windows-nt)
        (let ((inner (mapconcat #'identity (cons program args) " ")))
          (list "powershell.exe" "-NoProfile" "-NoLogo" "-Command" inner))
      (cons program args))))

(cl-defmethod copilot-cli--term-make ((_backend (eql comint)) buffer-name program switches)
  "Create a process buffer with a PTY connection.

BUFFER-NAME, PROGRAM, and SWITCHES are as described in the generic.
On Windows the process is hosted inside PowerShell so that Ink-based
TUI apps render correctly."
  (let* ((buf (get-buffer-create buffer-name))
         (cmd (copilot-cli--comint-build-command program switches))
         (process-environment (append (list "TERM=xterm-256color") process-environment))
         (proc (make-process
                :name (string-trim buffer-name "*" "*")
                :buffer buf
                :command cmd
                :connection-type 'pty
                :noquery t
                :filter #'copilot-cli--comint-filter
                :sentinel #'copilot-cli--comint-sentinel)))
    (set-process-window-size proc 50 120)
    (with-current-buffer buf
      (setq-local copilot-cli--process proc))
    buf))

(defvar-local copilot-cli--process nil
  "The Copilot CLI process for this buffer.")

(defun copilot-cli--comint-filter (proc output)
  "Process filter that inserts OUTPUT with ANSI color rendering.

PROC is the process that produced the output."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((inhibit-read-only t)
            (moving (= (point) (point-max))))
        (save-excursion
          (goto-char (point-max))
          (insert (ansi-color-apply output)))
        (when moving
          (goto-char (point-max))
          (dolist (win (get-buffer-window-list (current-buffer) nil t))
            (set-window-point win (point-max))))))))

(defun copilot-cli--comint-sentinel (proc event)
  "Process sentinel that notifies when PROC ends.

EVENT describes what happened."
  (when (and copilot-cli-enable-notifications
             (memq (process-status proc) '(exit signal)))
    (funcall copilot-cli-notification-function
             "Copilot CLI"
             (format "Process %s" (string-trim event)))))

(cl-defmethod copilot-cli--term-configure ((_backend (eql comint)))
  "Configure comint/pty terminal settings."
  nil)

(cl-defmethod copilot-cli--term-send-string ((_backend (eql comint)) string)
  "Send STRING to the process in the current buffer."
  (when-let ((proc (or copilot-cli--process
                       (get-buffer-process (current-buffer)))))
    (when (process-live-p proc)
      (process-send-string proc string))))

(cl-defmethod copilot-cli--term-send-key ((_backend (eql comint)) key)
  "Send KEY to the process.

KEY should be `return' or `escape'."
  (when-let ((proc (or copilot-cli--process
                       (get-buffer-process (current-buffer)))))
    (when (process-live-p proc)
      (pcase key
        ('return (process-send-string proc "\r"))
        ('escape (process-send-string proc "\e"))
        (_ (process-send-string proc (format "%s" key)))))))

(cl-defmethod copilot-cli--term-setup-keymap ((_backend (eql comint)))
  "Set up key bindings for the comint/pty buffer."
  ;; Make the buffer accept typed input and forward it to the process.
  (local-set-key (kbd "RET")
                 (lambda () (interactive)
                   (copilot-cli--term-send-key 'comint 'return)))
  (local-set-key (kbd "<escape>")
                 (lambda () (interactive)
                   (copilot-cli--term-send-key 'comint 'escape)))
  ;; Forward self-inserting characters to the process.
  (local-set-key [remap self-insert-command]
                 (lambda () (interactive)
                   (copilot-cli--term-send-string
                    'comint (string last-command-event)))))

(cl-defmethod copilot-cli--term-customize-faces ((_backend (eql comint)))
  "Apply face customizations for comint/pty."
  (face-remap-add-relative 'default 'copilot-cli-repl-face))

;;;; Helper Functions

(defun copilot-cli--directory ()
  "Return the project root or `default-directory'."
  (or (when-let ((proj (project-current)))
        (project-root proj))
      default-directory))

(defun copilot-cli--buffer-name (&optional instance-name)
  "Generate a Copilot CLI buffer name for the current directory.

When INSTANCE-NAME is non-nil and not empty, append it as a suffix."
  (let ((dir-name (let ((d (file-name-nondirectory
                            (directory-file-name (copilot-cli--directory)))))
                    (if (string-empty-p d)
                        (copilot-cli--directory)
                      d))))
    (if (and instance-name (not (string-empty-p instance-name)))
        (format "*copilot-cli: %s<%s>*" dir-name instance-name)
      (format "*copilot-cli: %s*" dir-name))))

(defun copilot-cli--find-copilot-buffers-for-directory (dir)
  "Find all live Copilot CLI buffers with a running process for DIR."
  (let ((results nil)
        (stale nil)
        (dir (expand-file-name dir)))
    (maphash (lambda (d buf-name)
               (when (string= (expand-file-name d) dir)
                 (let ((buf (get-buffer buf-name)))
                   (if (and buf (get-buffer-process buf)
                             (process-live-p (get-buffer-process buf)))
                       (push buf-name results)
                     (push d stale)))))
             copilot-cli--directory-buffer-map)
    ;; Clean stale entries
    (dolist (d stale)
      (remhash d copilot-cli--directory-buffer-map))
    results))

(defun copilot-cli--extract-instance-name-from-buffer-name (name)
  "Extract the instance suffix from buffer NAME.

Returns the instance name string, or nil if there is no suffix."
  (when (string-match "\\*copilot-cli: .+<\\(.+\\)>\\*" name)
    (match-string 1 name)))

(defun copilot-cli--prompt-for-instance-name (dir existing force)
  "Prompt the user for an instance name.

DIR is the project directory.  EXISTING is a list of existing buffer
names.  When FORCE is non-nil, always prompt even if no instances exist."
  (if (or force existing)
      (read-string
       (format "Copilot CLI instance name for %s (empty for default): "
               (file-name-nondirectory (directory-file-name dir))))
    nil))

(defun copilot-cli--get-buffer ()
  "Get the current Copilot CLI buffer for this directory.

Returns the buffer if it exists and is alive, nil otherwise."
  (let ((dir (copilot-cli--directory)))
    (when-let ((buf-name (gethash dir copilot-cli--directory-buffer-map)))
      (when (get-buffer buf-name)
        (get-buffer buf-name)))))

(defun copilot-cli--send-string (string)
  "Send STRING to the current Copilot CLI instance."
  (if-let ((buf (copilot-cli--get-buffer)))
      (with-current-buffer buf
        (copilot-cli--term-send-string copilot-cli-terminal-backend string))
    (user-error "No active Copilot CLI session for this directory")))

(defun copilot-cli--send-key (key)
  "Send KEY to the current Copilot CLI instance.

KEY should be a symbol like `return' or `escape'."
  (if-let ((buf (copilot-cli--get-buffer)))
      (with-current-buffer buf
        (copilot-cli--term-send-key copilot-cli-terminal-backend key))
    (user-error "No active Copilot CLI session for this directory")))

(defun copilot-cli--cleanup-directory-mapping ()
  "Remove the directory-to-buffer mapping for the current buffer.

Intended for use in `kill-buffer-hook'."
  (let ((buf-name (buffer-name)))
    (maphash (lambda (dir name)
               (when (string= name buf-name)
                 (remhash dir copilot-cli--directory-buffer-map)))
             copilot-cli--directory-buffer-map)))

(defun copilot-cli--adjust-window-size-advice (orig-fn &rest args)
  "Advice around window size changes to avoid redundant terminal resizes.

Calls ORIG-FN with ARGS only when the window width actually changed."
  (let* ((win (selected-window))
         (key (window-buffer win))
         (old-width (gethash key copilot-cli--window-widths))
         (new-width (window-width win)))
    (unless (eql old-width new-width)
      (puthash key new-width copilot-cli--window-widths)
      (apply orig-fn args))))

;;;; Window Management

(defun copilot-cli-display-buffer-below (buffer)
  "Display BUFFER in a side window at the bottom.

Window height is 40%% of the frame."
  (display-buffer buffer
                  '((display-buffer-in-side-window)
                    (side . bottom)
                    (slot . 0)
                    (window-height . 0.4)
                    (preserve-size . (nil . t)))))

;;;; Notification

(defun copilot-cli-default-notification (title message)
  "Display a notification with TITLE and MESSAGE.

Shows a minibuffer message and briefly pulses the mode line."
  (message "%s: %s" title message)
  (when (facep 'pulse-highlight-start-face)
    (let ((buf (current-buffer)))
      (run-with-timer 0.1 nil
                      (lambda ()
                        (when (buffer-live-p buf)
                          (with-current-buffer buf
                            (force-mode-line-update))))))))

;;;; Core Start Function

(defun copilot-cli--start (arg extra-switches &optional force-prompt force-switch-to-buffer)
  "Start a Copilot CLI session.

ARG is the prefix argument: double prefix (16) prompts for directory.
EXTRA-SWITCHES is a list of additional CLI flags.
When FORCE-PROMPT is non-nil, always prompt for an instance name.
When FORCE-SWITCH-TO-BUFFER is non-nil, switch to the buffer directly
instead of using the display function."
  (let* ((dir (if (and arg (>= (prefix-numeric-value arg) 16))
                  (read-directory-name "Start Copilot CLI in: ")
                (copilot-cli--directory)))
         (default-directory dir)
         (existing (copilot-cli--find-copilot-buffers-for-directory dir))
         (instance-name (copilot-cli--prompt-for-instance-name
                         dir existing force-prompt))
         (buf-name (let ((default-directory dir))
                     (copilot-cli--buffer-name instance-name)))
         (existing-buf (get-buffer buf-name)))
    ;; If a buffer with this name already exists, just display it.
    (if existing-buf
        (if force-switch-to-buffer
            (switch-to-buffer existing-buf)
          (funcall copilot-cli-display-window-fn existing-buf))
      ;; Create a new session.
      (let* ((switches (append copilot-cli-program-switches extra-switches))
             (process-environment (cons (format "TERM=%s" copilot-cli-term-name)
                                        process-environment))
             (buf (copilot-cli--term-make copilot-cli-terminal-backend
                                          buf-name
                                          copilot-cli-program
                                          switches)))
        (when buf
          (puthash dir buf-name copilot-cli--directory-buffer-map)
          (with-current-buffer buf
            (copilot-cli--term-configure copilot-cli-terminal-backend)
            (copilot-cli--term-setup-keymap copilot-cli-terminal-backend)
            (copilot-cli--term-customize-faces copilot-cli-terminal-backend)
            (add-hook 'kill-buffer-hook #'copilot-cli--cleanup-directory-mapping nil t))
          (if force-switch-to-buffer
              (switch-to-buffer buf)
            (funcall copilot-cli-display-window-fn buf))
          (when copilot-cli-enable-notifications
            (funcall copilot-cli-notification-function
                     "Copilot CLI"
                     (format "Session started in %s"
                             (file-name-nondirectory
                              (directory-file-name dir)))))
          (run-hooks 'copilot-cli-start-hook))))))

;;;; Interactive Commands

;;;###autoload
(defun copilot-cli (&optional arg)
  "Start a Copilot CLI session for the current project.

With a double prefix argument (\\[universal-argument] \\[universal-argument]),
prompt for the directory.  ARG is the raw prefix argument."
  (interactive "P")
  (copilot-cli--start arg nil))

;;;###autoload
(defun copilot-cli-start-in-directory ()
  "Start a Copilot CLI session after prompting for a directory."
  (interactive)
  (let ((dir (read-directory-name "Start Copilot CLI in: ")))
    (let ((default-directory dir))
      (copilot-cli--start nil nil))))

;;;###autoload
(defun copilot-cli-kill ()
  "Kill the current Copilot CLI session."
  (interactive)
  (if-let ((buf (copilot-cli--get-buffer)))
      (when (or (not copilot-cli-confirm-kill)
                (yes-or-no-p "Kill this Copilot CLI session? "))
        (kill-buffer buf)
        (when copilot-cli-enable-notifications
          (funcall copilot-cli-notification-function
                   "Copilot CLI" "Session killed")))
    (user-error "No active Copilot CLI session for this directory")))

;;;###autoload
(defun copilot-cli-kill-all ()
  "Kill all Copilot CLI sessions."
  (interactive)
  (let ((count 0))
    (maphash (lambda (_dir buf-name)
               (when-let ((buf (get-buffer buf-name)))
                 (kill-buffer buf)
                 (cl-incf count)))
             copilot-cli--directory-buffer-map)
    (clrhash copilot-cli--directory-buffer-map)
    (if (zerop count)
        (message "No active Copilot CLI sessions")
      (when copilot-cli-enable-notifications
        (funcall copilot-cli-notification-function
                 "Copilot CLI"
                 (format "Killed %d session%s" count
                         (if (= count 1) "" "s")))))))

;;;###autoload
(defun copilot-cli-toggle ()
  "Toggle visibility of the Copilot CLI window.

If the window is visible, hide it.  If hidden, display it.  If no
session exists, start one."
  (interactive)
  (if-let ((buf (copilot-cli--get-buffer)))
      (if-let ((win (get-buffer-window buf)))
          (delete-window win)
        (funcall copilot-cli-display-window-fn buf))
    (copilot-cli nil)))

;;;###autoload
(defun copilot-cli-switch-to-buffer ()
  "Switch to the Copilot CLI buffer for the current directory.

Starts a session if none exists."
  (interactive)
  (if-let ((buf (copilot-cli--get-buffer)))
      (switch-to-buffer buf)
    (copilot-cli--start nil nil nil t)))

;;;###autoload
(defun copilot-cli-select-buffer ()
  "Select a Copilot CLI buffer from all active sessions."
  (interactive)
  (let ((buffers nil))
    (maphash (lambda (_dir buf-name)
               (when (get-buffer buf-name)
                 (push buf-name buffers)))
             copilot-cli--directory-buffer-map)
    (if buffers
        (let ((choice (completing-read "Select Copilot CLI buffer: " buffers nil t)))
          (switch-to-buffer choice))
      (user-error "No active Copilot CLI sessions"))))

;;;###autoload
(defun copilot-cli-send-command (command)
  "Send COMMAND string to the current Copilot CLI session.

Prompts for the command in the minibuffer."
  (interactive
   (list (read-string "Send to Copilot CLI: " nil 'copilot-cli-command-history)))
  (copilot-cli--send-string command)
  (copilot-cli--send-key 'return))

;;;###autoload
(defun copilot-cli-send-command-with-context (command)
  "Send COMMAND with the current file and line as context.

Prepends the current file path and line number to the command."
  (interactive
   (list (read-string "Send to Copilot CLI (with context): "
                      nil 'copilot-cli-command-history)))
  (let* ((file (or (buffer-file-name) ""))
         (line (line-number-at-pos))
         (context (if (string-empty-p file)
                      command
                    (format "%s (context: %s:%d)" command file line))))
    (copilot-cli--send-string context)
    (copilot-cli--send-key 'return)))

;;;###autoload
(defun copilot-cli-send-region (beg end)
  "Send the region between BEG and END to Copilot CLI.

If no region is active, send the entire buffer.  Prompts for
confirmation when the content exceeds `copilot-cli-large-buffer-threshold'."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (point-min) (point-max))))
  (let ((text (buffer-substring-no-properties beg end)))
    (when (and (> (length text) copilot-cli-large-buffer-threshold)
               (not (yes-or-no-p
                     (format "Send %d characters to Copilot CLI? "
                             (length text)))))
      (user-error "Aborted"))
    (copilot-cli--send-string text)))

;;;###autoload
(defun copilot-cli-send-return ()
  "Send Return (yes/confirm) to Copilot CLI."
  (interactive)
  (copilot-cli--send-key 'return))

;;;###autoload
(defun copilot-cli-send-escape ()
  "Send Escape (no/cancel) to Copilot CLI."
  (interactive)
  (copilot-cli--send-key 'escape))

;;;###autoload
(defun copilot-cli-send-1 ()
  "Send \"1\" to Copilot CLI to select option 1."
  (interactive)
  (copilot-cli--send-string "1")
  (copilot-cli--send-key 'return))

;;;###autoload
(defun copilot-cli-send-2 ()
  "Send \"2\" to Copilot CLI to select option 2."
  (interactive)
  (copilot-cli--send-string "2")
  (copilot-cli--send-key 'return))

;;;###autoload
(defun copilot-cli-send-3 ()
  "Send \"3\" to Copilot CLI to select option 3."
  (interactive)
  (copilot-cli--send-string "3")
  (copilot-cli--send-key 'return))

;;;###autoload
(defun copilot-cli-send-buffer-file ()
  "Send the current buffer's file path to Copilot CLI."
  (interactive)
  (if-let ((file (buffer-file-name)))
      (progn
        (copilot-cli--send-string file)
        (copilot-cli--send-key 'return))
    (user-error "Current buffer is not visiting a file")))

;;;###autoload
(defun copilot-cli-toggle-read-only-mode ()
  "Toggle between terminal char mode and read-only browsing mode.

In eat, switches between semi-char-mode and emacs-mode.
In vterm, toggles vterm-copy-mode."
  (interactive)
  (if-let ((buf (copilot-cli--get-buffer)))
      (with-current-buffer buf
        (pcase copilot-cli-terminal-backend
          ('eat
           (if (bound-and-true-p eat--semi-char-mode)
               (eat-emacs-mode)
             (eat-semi-char-mode)))
          ('vterm
           (vterm-copy-mode 'toggle))))
    (user-error "No active Copilot CLI session for this directory")))

;;;; Transient Menu

;;;###autoload (autoload 'copilot-cli-transient "copilot-cli" nil t)
(transient-define-prefix copilot-cli-transient ()
  "Copilot CLI commands."
  ["Start / Stop"
   ("c" "Start Copilot CLI" copilot-cli)
   ("d" "Start in directory" copilot-cli-start-in-directory)
   ("k" "Kill" copilot-cli-kill)]
  ["Send"
   ("s" "Send command" copilot-cli-send-command)
   ("x" "Send with context" copilot-cli-send-command-with-context)
   ("r" "Send region" copilot-cli-send-region)
   ("o" "Send file" copilot-cli-send-buffer-file)]
  ["Quick Response"
   ("y" "Yes (Enter)" copilot-cli-send-return)
   ("n" "No (Escape)" copilot-cli-send-escape)
   ("1" "Option 1" copilot-cli-send-1)
   ("2" "Option 2" copilot-cli-send-2)
   ("3" "Option 3" copilot-cli-send-3)]
  ["Window"
   ("t" "Toggle window" copilot-cli-toggle)
   ("b" "Switch to buffer" copilot-cli-switch-to-buffer)
   ("z" "Toggle read-only" copilot-cli-toggle-read-only-mode)])

;;;; Minor Mode

;;;###autoload
(define-minor-mode copilot-cli-mode
  "Global minor mode providing the `copilot-cli-command-map'.

Enable this mode and bind the command map to a prefix key:
  (copilot-cli-mode 1)
  (global-set-key (kbd \"C-c C\") copilot-cli-command-map)"
  :global t
  :lighter " CopilotCLI"
  :group 'copilot-cli)

;;;; Provide

(provide 'copilot-cli)

;;; copilot-cli.el ends here
