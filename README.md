# copilot-cli.el

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Emacs: 29.1+](https://img.shields.io/badge/Emacs-29.1%2B-purple.svg)](https://www.gnu.org/software/emacs/)

An Emacs interface for [GitHub Copilot CLI](https://github.com/github/copilot-cli), providing seamless integration between Emacs and GitHub Copilot's terminal-based coding assistant.

## Features

- **Seamless Emacs Integration** -- Start, manage, and interact with Copilot CLI without leaving Emacs.
- **Stay in Your Buffer** -- Send code, regions, or commands to Copilot while keeping focus in your working buffer.
- **Multiple Instances** -- Run separate Copilot sessions for different projects, each rooted in its own directory.
- **Quick Responses** -- Answer prompts (y/n/1/2/3) with single keybindings, no buffer switching required.
- **Smart Context** -- Optionally include file paths and line numbers when sending commands.
- **Transient Menu** -- Discover all commands through a visual menu powered by `transient`.
- **Read-Only Mode** -- Toggle read-only to select and copy text with normal Emacs keybindings.
- **Terminal Choice** -- Works with both `eat` (recommended) and `vterm` terminal backends.
- **Cross-Platform** -- Works on Windows, macOS, and Linux.
- **Fully Customizable** -- Configure keybindings, notifications, terminal backend, and display behavior.

## Prerequisites

- **Emacs 29.1+**
- **GitHub Copilot CLI** installed and configured (`copilot` binary in PATH)
- **transient** (built into Emacs 29+)
- **eat** (recommended) or **vterm** for the terminal backend

## Installation

### Using use-package with :vc (Emacs 29+)

```elisp
;; Terminal backend (recommended):
(use-package eat :ensure t)

;; Install copilot-cli.el
(use-package copilot-cli
  :vc (:url "https://github.com/armaansood/copilot-cli.el" :rev :newest)
  :config
  (copilot-cli-mode)
  :bind-keymap ("C-c g" . copilot-cli-command-map))
```

### Using straight.el

```elisp
(use-package eat
  :straight (:type git :host codeberg :repo "akib/emacs-eat"
             :files ("*.el" ("term" "term/*.el") "*.texi" "*.ti"
                     ("terminfo/e" "terminfo/e/*")
                     ("terminfo/65" "terminfo/65/*")
                     ("integration" "integration/*")
                     (:exclude ".dir-locals.el" "*-tests.el"))))

(use-package copilot-cli
  :straight (:type git :host github :repo "armaansood/copilot-cli.el"
             :branch "main" :depth 1 :files ("*.el"))
  :config
  (copilot-cli-mode)
  :bind-keymap ("C-c g" . copilot-cli-command-map))
```

### Manual Installation

```bash
git clone https://github.com/armaansood/copilot-cli.el ~/.emacs.d/site-lisp/copilot-cli
```

```elisp
(add-to-list 'load-path "~/.emacs.d/site-lisp/copilot-cli")
(require 'copilot-cli)
(copilot-cli-mode)
(global-set-key (kbd "C-c g") copilot-cli-command-map)
```

## Quick Start

1. Install the package and set the `C-c g` keymap (see above).
2. Open a file in a project.
3. Press `C-c g c` to start Copilot CLI in the project root.

That's it. Copilot CLI launches in a terminal buffer, and you can interact with it entirely through keybindings from any buffer.

## Usage

### Starting and Stopping

| Keybinding | Command | Description |
|---|---|---|
| `C-c g c` | `copilot-cli` | Start Copilot CLI in the current project root |
| `C-c g d` | `copilot-cli-start-in-directory` | Start Copilot CLI in a specific directory |
| `C-c g k` | `copilot-cli-kill` | Kill the Copilot CLI instance for the current directory |

### Sending Commands

| Keybinding | Command | Description |
|---|---|---|
| `C-c g s` | `copilot-cli-send-command` | Type a command in the minibuffer and send it to Copilot |
| `C-c g x` | `copilot-cli-send-command-with-context` | Send a command with the current file path and line number |
| `C-c g r` | `copilot-cli-send-region` | Send the active region (or entire buffer if no selection) |

### Quick Responses

| Keybinding | Command | Description |
|---|---|---|
| `C-c g y` | `copilot-cli-send-return` | Send Return (accept / yes) |
| `C-c g n` | `copilot-cli-send-escape` | Send Escape (reject / no) |
| `C-c g 1` | `copilot-cli-send-1` | Choose option 1 |
| `C-c g 2` | `copilot-cli-send-2` | Choose option 2 |
| `C-c g 3` | `copilot-cli-send-3` | Choose option 3 |

### Window Management

| Keybinding | Command | Description |
|---|---|---|
| `C-c g t` | `copilot-cli-toggle` | Show or hide the Copilot CLI window |
| `C-c g b` | `copilot-cli-switch-to-buffer` | Jump to the Copilot CLI buffer |
| `C-c g z` | `copilot-cli-toggle-read-only-mode` | Toggle read-only mode for easy text selection |

### Transient Menu

| Keybinding | Command | Description |
|---|---|---|
| `C-c g m` | `copilot-cli-transient` | Open the visual transient menu listing all commands |

## Keybinding Reference

All keybindings live under the `C-c g` prefix (configurable via `copilot-cli-command-map`):

| Key | Command |
|---|---|
| `c` | Start Copilot CLI |
| `d` | Start in directory |
| `k` | Kill instance |
| `s` | Send command |
| `x` | Send command with context |
| `r` | Send region |
| `y` | Send Return |
| `n` | Send Escape |
| `1` | Send 1 |
| `2` | Send 2 |
| `3` | Send 3 |
| `t` | Toggle window |
| `b` | Switch to buffer |
| `z` | Toggle read-only mode |
| `m` | Transient menu |

## Customization

All options are under the `copilot-cli` customization group (`M-x customize-group RET copilot-cli`):

| Variable | Default | Description |
|---|---|---|
| `copilot-cli-program` | `"copilot"` | Path to the Copilot CLI executable |
| `copilot-cli-program-args` | `'()` | Extra arguments passed to the executable |
| `copilot-cli-terminal-backend` | `'eat` | Terminal backend: `eat` or `vterm` |
| `copilot-cli-buffer-name` | `"*copilot-cli*"` | Base name for Copilot CLI buffers |
| `copilot-cli-window-height` | `0.4` | Window height as a fraction of the frame |
| `copilot-cli-window-position` | `'bottom` | Where to display the window (`bottom` or `right`) |
| `copilot-cli-send-context` | `nil` | When non-nil, include file/line context with commands |
| `copilot-cli-notify-on-complete` | `t` | Show a notification when Copilot finishes a response |

### Switching to vterm

If you prefer `vterm` over `eat`:

```elisp
(setq copilot-cli-terminal-backend 'vterm)
```

## Multiple Instances

Each Copilot CLI session is scoped to a directory. When you run `copilot-cli` (`C-c g c`), it starts a session rooted in your project directory. If you switch to a file in a different project and invoke it again, a separate instance is created for that project.

All commands automatically target the instance associated with the current buffer's project root, so you can work across multiple projects without manually switching sessions.

## Why This Exists

GitHub Copilot CLI is a terminal application (TUI) that requires a real terminal emulator to render correctly. It does not work in Emacs' built-in `shell-mode` or `term-mode`, particularly on Windows where PTY support is limited. This package solves that problem by running Copilot CLI inside `eat` or `vterm`, both of which provide full terminal emulation, and layers ergonomic Emacs integration on top: keybindings for every action, context-aware command sending, per-project instance management, and a transient menu for discoverability.

The result is that you never need to leave Emacs to use Copilot CLI.

## Inspired By

This package was inspired by [claude-code.el](https://github.com/stevemolitor/claude-code.el) by Steve Molitor, which takes a similar approach for Anthropic's Claude Code CLI.

## Contributing

Contributions are welcome.

- Open an issue for bugs or feature requests.
- Submit a pull request for changes.
- Run `make all` before submitting to ensure checkdoc, byte-compilation, and tests pass.

## License

[MIT](LICENSE)
