;;; -*- lexical-binding: t; -*-
;; ERT tests for init-ai.el (standalone multi-provider gptel module).
;; Runner: emacs --batch -Q -L . -l tests/run.el
(require 'ert)
(require 'gptel)
(require 'minuet nil t)

(defun ai/restore-stock-registry ()
  "Reinstall the stock registry and backends after a test mutates them."
  (setq my/ai-providers (default-value 'my/ai-providers))
  (my/ai-build-backends)
  (setq-default gptel-backend (my/ai-backend 'zhipu)
                gptel-model (my/ai-provider-default-model 'zhipu)))

(ert-deftest ai/registry-builds-one-backend-per-provider ()
  (should (= (length my/ai-providers) (length my/ai-backends)))
  (dolist (entry my/ai-providers)
    (should (my/ai-backend (car entry)))))

(ert-deftest ai/default-backend-is-zhipu-glm ()
  (let ((zhipu (my/ai-backend 'zhipu)))
    (should (eq (default-value 'gptel-backend) zhipu))
    (should (eq (default-value 'gptel-model) 'glm-5.3-flash))
    (should (equal (gptel-backend-host zhipu) "open.bigmodel.cn"))
    (should (equal (gptel-backend-endpoint zhipu)
                   "/api/coding/paas/v4/chat/completions"))))

(ert-deftest ai/synthetic-registry-uses-authinfo-hosts-and-defaults ()
  ;; Generic provider entries: host/login come from the registry, keys from
  ;; authinfo at request time; endpoint defaults to /v1/chat/completions;
  ;; :protocol supports local http servers.
  (unwind-protect
      (progn
        (setq my/ai-providers
              '((relay
                 :host "relay.test" :login "relay-user"
                 :models (relay-a relay-b) :default relay-b)
                (plain
                 :host "plain.test" :login "plain-user"
                 :models (plain-a))
                (local
                 :host "localhost:9000" :login "local-user" :protocol "http"
                 :models (local-a) :default local-a)))
        (my/ai-build-backends)
        (should (equal (gptel-backend-host (my/ai-backend 'relay)) "relay.test"))
        (should (equal (gptel-backend-endpoint (my/ai-backend 'relay))
                       "/v1/chat/completions"))
        ;; :default wins over the first model.
        (should (eq (my/ai-provider-default-model 'relay) 'relay-b))
        ;; No :default -> first model.
        (should (eq (my/ai-provider-default-model 'plain) 'plain-a))
        (should (equal (gptel-backend-protocol (my/ai-backend 'local)) "http")))
    (ai/restore-stock-registry)))

(ert-deftest ai/key-resolution-env-wins-then-authinfo ()
  ;; env-var provider (zhipu)
  (let ((process-environment (cons "ZHIPUAI_API_KEY=test-env-key"
                                   process-environment)))
    (should (equal (my/ai-provider-key (my/ai-provider-spec 'zhipu))
                   "test-env-key")))
  ;; authinfo provider: isolated netrc fixture, never the user's real one
  (let* ((netrc (make-temp-file "authinfo-test-" nil
                                ".netrc"
                                "machine relay.test login relay-user password testpass\n"))
         (auth-sources (list netrc)))
    (unwind-protect
        (should (equal (my/ai-provider-key '(:host "relay.test" :login "relay-user"))
                       "testpass"))
      (delete-file netrc))))

(ert-deftest ai/key-missing-returns-nil ()
  (should-not (my/ai-provider-key '(:host "no-such-host.invalid"
                                    :login "no-such-user"))))

(ert-deftest ai/select-provider-switches-defaults ()
  (unwind-protect
      (progn
        (setq my/ai-providers
              (append my/ai-providers
                      '((switchme
                         :host "switch.test" :login "switch-user"
                         :models (switch-a switch-b) :default switch-b))))
        (my/ai-build-backends)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _collection &rest _)
                     "switch-b")))
          (my/ai-select-provider 'switchme))
        (should (eq (default-value 'gptel-backend) (my/ai-backend 'switchme)))
        (should (eq (default-value 'gptel-model) 'switch-b)))
    (ai/restore-stock-registry)))

(ert-deftest ai/gptel-default-mode-org ()
  (should (eq gptel-default-mode 'org-mode)))

(ert-deftest ai/glm-thinking-disabled ()
  (should (equal (get 'glm-5.3-flash :request-params)
                 '(:thinking (:type "disabled")))))

(ert-deftest ai/new-session-display-uses-full-frame ()
  (should (equal gptel-display-buffer-action
                 '(display-buffer-full-frame))))

(ert-deftest ai/session-buffers-use-full-width-soft-wrapping ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (gptel-mode 1)
    (my/gptel-setup-display)
    (should visual-line-mode)
    (should-not truncate-lines)
    (should-not visual-fill-column-width)))

(ert-deftest ai/open-session-restores-native-properties-and-styles ()
  (let* ((my/gptel-session-directory (make-temp-file "gptel-sessions-" t))
         (session (expand-file-name "test-session.org" my/gptel-session-directory))
         (backend (my/ai-backend 'zhipu)))
    (unwind-protect
        (progn
          (with-temp-file session
            (insert "#+Title: session\n\n"))
          (with-current-buffer (find-file-noselect session)
            (gptel-mode 1)
            (should gptel-mode)
            (should (eq gptel-backend backend))
            (should visual-line-mode)
            (should-not (get-char-property (point) 'gptel))
            (kill-buffer)))
      (delete-directory my/gptel-session-directory t))))

(ert-deftest ai/exit-save-writes-session-to-configured-directory ()
  (let* ((my/gptel-session-directory (make-temp-file "gptel-sessions-" t))
         (saved nil))
    (unwind-protect
        (with-temp-buffer
          (insert "hello")
          (delay-mode-hooks (org-mode))
          (gptel-mode 1)
          (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                    ((symbol-function 'save-buffer)
                     (lambda () (setq saved buffer-file-name))))
            (my/gptel-save-unsaved-sessions-on-exit))
          (should saved)
          (should (string-prefix-p (expand-file-name my/gptel-session-directory)
                                   (expand-file-name saved)))
          (should (string-match-p "\\.org\\'" saved)))
      (delete-directory my/gptel-session-directory t))))

(ert-deftest ai/agent-confirms-destructive-bash-only ()
  (let ((directory (make-temp-file "gptel-agent-" t)))
    (unwind-protect
        (let ((default-directory directory))
          ;; Routine tools run without confirmation.
          (should-not (my/gptel-agent-confirm-bash "ls -la"))
          (should-not (my/gptel-agent-confirm-write directory "new-file.txt" ""))
          ;; Destructive bash prompts.
          (should (my/gptel-agent-confirm-bash "rm -rf build/"))
          (should (my/gptel-agent-confirm-bash "git clean -fd"))
          (should (my/gptel-agent-confirm-bash "git reset --hard HEAD~1"))
          (should (my/gptel-agent-confirm-bash "find . -name '*.elc' -delete"))
          ;; Overwriting an existing file prompts.
          (write-region "" nil (expand-file-name "existing.txt" directory))
          (should (my/gptel-agent-confirm-write directory "existing.txt" "")))
      (delete-directory directory t))))

(ert-deftest ai/agent-and-presets-loaded ()
  (should (fboundp 'gptel-agent))
  (should (fboundp 'gptel-agent-compact)))

(ert-deftest ai/minuet-provider-config ()
  (when (boundp 'minuet-openai-compatible-options)
    (should (eq minuet-provider 'openai-compatible))
    (should (equal my/gptel-zhipu-endpoint
                   (plist-get minuet-openai-compatible-options :end-point)))
    (should (equal "glm-5.3-flash"
                   (plist-get minuet-openai-compatible-options :model)))))

(ert-deftest ai/minuet-thinking-disabled-via-optional ()
  (when (boundp 'minuet-openai-compatible-options)
    (should (equal '(:thinking (:type "disabled"))
                   (plist-get minuet-openai-compatible-options :optional)))
    (should-not (plist-get minuet-openai-compatible-options :thinking))))

(ert-deftest ai/version-probe ()
  (should (equal my/gptel-init-version "3.0-standalone")))
