;;; copilot-cli-test.el --- Tests for copilot-cli -*- lexical-binding: t; -*-

;; Copyright (c) 2025 Armaan Sood
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; ERT test suite for the copilot-cli.el package.

;;; Code:

(require 'ert)
(require 'copilot-cli)

;;;; Buffer naming — copilot-cli--buffer-name

(ert-deftest copilot-cli-test-buffer-name-default ()
  "Buffer name without instance uses directory basename."
  (let ((default-directory "/home/user/my-project/"))
    (cl-letf (((symbol-function 'copilot-cli--directory)
               (lambda () default-directory)))
      (should (equal (copilot-cli--buffer-name)
                     "*copilot-cli: my-project*")))))

(ert-deftest copilot-cli-test-buffer-name-with-instance ()
  "Buffer name with instance appends `<instance>' suffix."
  (let ((default-directory "/home/user/my-project/"))
    (cl-letf (((symbol-function 'copilot-cli--directory)
               (lambda () default-directory)))
      (should (equal (copilot-cli--buffer-name "debug")
                     "*copilot-cli: my-project<debug>*")))))

(ert-deftest copilot-cli-test-buffer-name-empty-instance ()
  "Empty instance string produces the same result as no instance."
  (let ((default-directory "/tmp/foo/"))
    (cl-letf (((symbol-function 'copilot-cli--directory)
               (lambda () default-directory)))
      (should (equal (copilot-cli--buffer-name "")
                     "*copilot-cli: foo*")))))

(ert-deftest copilot-cli-test-buffer-name-nil-instance ()
  "Nil instance produces the default buffer name."
  (let ((default-directory "/tmp/bar/"))
    (cl-letf (((symbol-function 'copilot-cli--directory)
               (lambda () default-directory)))
      (should (equal (copilot-cli--buffer-name nil)
                     "*copilot-cli: bar*")))))

;;;; Directory resolution — copilot-cli--directory

(ert-deftest copilot-cli-test-directory-falls-back-to-default ()
  "When no project is found, fall back to `default-directory'."
  (let ((default-directory "/tmp/no-project/"))
    (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil)))
      (should (equal (copilot-cli--directory) "/tmp/no-project/")))))

(ert-deftest copilot-cli-test-directory-uses-project-root ()
  "When a project is found, return its root."
  (let ((default-directory "/tmp/inside-project/src/"))
    (cl-letf (((symbol-function 'project-current)
               (lambda (&rest _) '(vc Git "/tmp/inside-project/")))
              ((symbol-function 'project-root)
               (lambda (_proj) "/tmp/inside-project/")))
      (should (equal (copilot-cli--directory) "/tmp/inside-project/")))))

;;;; Customization defaults

(ert-deftest copilot-cli-test-default-program ()
  "Default program should be \"copilot\"."
  (should (equal (default-value 'copilot-cli-program) "copilot")))

(ert-deftest copilot-cli-test-default-program-switches ()
  "Default program switches should be nil."
  (should (null (default-value 'copilot-cli-program-switches))))

(ert-deftest copilot-cli-test-default-terminal-backend ()
  "Default terminal backend should be `eat'."
  (should (eq (default-value 'copilot-cli-terminal-backend) 'eat)))

(ert-deftest copilot-cli-test-default-term-name ()
  "Default TERM value should be \"xterm-256color\"."
  (should (equal (default-value 'copilot-cli-term-name) "xterm-256color")))

(ert-deftest copilot-cli-test-default-startup-delay ()
  "Default startup delay should be 0.1."
  (should (= (default-value 'copilot-cli-startup-delay) 0.1)))

(ert-deftest copilot-cli-test-default-enable-notifications ()
  "Notifications should be enabled by default."
  (should (eq (default-value 'copilot-cli-enable-notifications) t)))

(ert-deftest copilot-cli-test-default-confirm-kill ()
  "Kill confirmation should be enabled by default."
  (should (eq (default-value 'copilot-cli-confirm-kill) t)))

(ert-deftest copilot-cli-test-default-no-delete-other-windows ()
  "No-delete-other-windows should be nil by default."
  (should (null (default-value 'copilot-cli-no-delete-other-windows))))

(ert-deftest copilot-cli-test-default-display-window-fn ()
  "Default display function should be `copilot-cli-display-buffer-below'."
  (should (eq (default-value 'copilot-cli-display-window-fn)
              #'copilot-cli-display-buffer-below)))

(ert-deftest copilot-cli-test-default-large-buffer-threshold ()
  "Default large buffer threshold should be 100000."
  (should (= (default-value 'copilot-cli-large-buffer-threshold) 100000)))

(ert-deftest copilot-cli-test-default-newline-keybinding-style ()
  "Default newline keybinding style should be `newline-on-shift-return'."
  (should (eq (default-value 'copilot-cli-newline-keybinding-style)
              'newline-on-shift-return)))

(ert-deftest copilot-cli-test-default-notification-function ()
  "Default notification function should be `copilot-cli-default-notification'."
  (should (eq (default-value 'copilot-cli-notification-function)
              #'copilot-cli-default-notification)))

;;;; Command map

(ert-deftest copilot-cli-test-command-map-is-keymap ()
  "The command map should be a keymap."
  (should (keymapp copilot-cli-command-map)))

(ert-deftest copilot-cli-test-command-map-bindings ()
  "Key bindings in the command map should match expected commands."
  (let ((expected '(("c" . copilot-cli)
                    ("d" . copilot-cli-start-in-directory)
                    ("k" . copilot-cli-kill)
                    ("K" . copilot-cli-kill-all)
                    ("t" . copilot-cli-toggle)
                    ("b" . copilot-cli-switch-to-buffer)
                    ("B" . copilot-cli-select-buffer)
                    ("s" . copilot-cli-send-command)
                    ("x" . copilot-cli-send-command-with-context)
                    ("r" . copilot-cli-send-region)
                    ("o" . copilot-cli-send-buffer-file)
                    ("y" . copilot-cli-send-return)
                    ("n" . copilot-cli-send-escape)
                    ("1" . copilot-cli-send-1)
                    ("2" . copilot-cli-send-2)
                    ("3" . copilot-cli-send-3)
                    ("z" . copilot-cli-toggle-read-only-mode)
                    ("m" . copilot-cli-transient))))
    (dolist (pair expected)
      (should (eq (lookup-key copilot-cli-command-map (kbd (car pair)))
                  (cdr pair))))))

;;;; Instance name extraction — copilot-cli--extract-instance-name-from-buffer-name

(ert-deftest copilot-cli-test-extract-instance-name-present ()
  "Extract instance name from a buffer name with a suffix."
  (should (equal (copilot-cli--extract-instance-name-from-buffer-name
                  "*copilot-cli: project<test>*")
                 "test")))

(ert-deftest copilot-cli-test-extract-instance-name-absent ()
  "Return nil when buffer name has no instance suffix."
  (should (null (copilot-cli--extract-instance-name-from-buffer-name
                 "*copilot-cli: project*"))))

(ert-deftest copilot-cli-test-extract-instance-name-numeric ()
  "Extract a numeric instance name."
  (should (equal (copilot-cli--extract-instance-name-from-buffer-name
                  "*copilot-cli: myapp<2>*")
                 "2")))

(ert-deftest copilot-cli-test-extract-instance-name-complex ()
  "Extract an instance name containing hyphens and dots."
  (should (equal (copilot-cli--extract-instance-name-from-buffer-name
                  "*copilot-cli: repo<feat-1.2>*")
                 "feat-1.2")))

(ert-deftest copilot-cli-test-extract-instance-name-unrelated-buffer ()
  "Return nil for a buffer name that does not match the pattern."
  (should (null (copilot-cli--extract-instance-name-from-buffer-name
                 "*scratch*"))))

;;;; Display function

(ert-deftest copilot-cli-test-display-buffer-below-is-function ()
  "The display function should be a callable function."
  (should (functionp #'copilot-cli-display-buffer-below)))

;;;; Internal variables

(ert-deftest copilot-cli-test-directory-buffer-map-is-hash-table ()
  "The directory-buffer map should be a hash table."
  (should (hash-table-p copilot-cli--directory-buffer-map)))

(ert-deftest copilot-cli-test-window-widths-is-hash-table ()
  "The window-widths map should be a hash table."
  (should (hash-table-p copilot-cli--window-widths)))

(provide 'copilot-cli-test)
;;; copilot-cli-test.el ends here
