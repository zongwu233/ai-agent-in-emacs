;;; -*- lexical-binding: t; -*-
;; Batch test runner for the ai-agent-in-emacs module.
;; Usage: emacs --batch -Q -L . -l tests/run.el
;; ELPA_DIR overrides the package directory (default ~/.emacs.d/elpa).

(setq package-user-dir
      (expand-file-name (or (getenv "ELPA_DIR") "~/.emacs.d/elpa/")))

(require 'package)
(package-initialize)
(require 'use-package)
;; init-ai.el installs gptel-preset-collection via the :quelpa keyword.
(require 'quelpa-use-package nil t)

(require 'init-ai)
(require 'minuet nil t)

(setq gptel-confirm-tool-calls nil)

(load (expand-file-name "test-init-ai.el"
                        (file-name-directory (or load-file-name
                                                 default-directory)))
      nil t)

(ert-run-tests-batch-and-exit t)
