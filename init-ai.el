;; -*- coding: utf-8; lexical-binding: t; -*-
;;; init-ai.el --- AI coding features (gptel) -*- lexical-binding: t; -*-

;; gptel + gptel-agent + gptel-preset-collection + minuet, packaged as a
;; standalone Emacs module.
;;
;; Provider registry: `my/ai-providers'. Every provider exposes an
;; OpenAI-compatible chat API; one gptel backend is built per entry.
;;
;; API keys resolve through auth-source, i.e. ~/.authinfo by default:
;;   machine = API base_url host   (provider :host)
;;   login   = selects the entry   (provider :login)
;;   password= the API key
;; Providers without an authinfo entry can read their key from an
;; environment variable via (:auth (:env "VAR")). The default registry
;; ships only zhipu (public coding-plan endpoint, key from ZHIPUAI_API_KEY);
;; add your own providers by extending `my/ai-providers' before this file
;; is loaded (see README.md).

(defconst my/gptel-zhipu-endpoint
  "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
  "Zhipu GLM coding-plan endpoint (shared by gptel's zhipu backend and minuet).
For a standard Zhipu API key use
https://open.bigmodel.cn/api/paas/v4/chat/completions instead.")

(defvar my/ai-backends nil
  "Provider name -> gptel backend, built by `my/ai-build-backends'.")

(defcustom my/ai-providers
  '((zhipu
     :host "open.bigmodel.cn"
     :endpoint "/api/coding/paas/v4/chat/completions"
     :auth (:env "ZHIPUAI_API_KEY")
     :models (glm-5.3-flash glm-4.6 glm-4.5 glm-4.5-air glm-4.5-flash)
     :default glm-5.3-flash))
  "AI provider registry; `my/ai-build-backends' makes one backend per entry.
:host     API base_url host = the machine field of ~/.authinfo.
:login    authinfo login whose password is the API key.
:auth     (:env VAR) reads the key from VAR instead of authinfo.
:endpoint chat path, default \"/v1/chat/completions\" (OpenAI-compatible).
:protocol \"https\" (default) or \"http\" for local servers.
:models   model symbols offered in the menu.
:default  preselected model.

Set or extend this variable (with `setq' / `add-to-list') before this
file is loaded, then (re)build backends with `my/ai-build-backends'."
  :type '(repeat (cons symbol plist)))

(defun my/ai-provider-spec (name)
  "Return the `my/ai-providers' plist of provider NAME."
  (cdr (assq name my/ai-providers)))

(defun my/ai-backend (name)
  "Return the gptel backend built for provider NAME, or nil."
  (alist-get name my/ai-backends))

(defun my/ai-provider-default-model (name)
  "Default model symbol configured for provider NAME."
  (let ((spec (my/ai-provider-spec name)))
    (or (plist-get spec :default)
        (car (plist-get spec :models)))))

(defun my/ai-provider-key (spec)
  "Resolve the API key of provider SPEC, or nil.
The :auth environment variable wins, then the authinfo password of
:login on :host (see `auth-source-search')."
  (or (when-let ((var (plist-get (plist-get spec :auth) :env)))
        (getenv var))
      (when-let ((login (plist-get spec :login)))
        (require 'auth-source)
        (let* ((entry (car (auth-source-search
                            :max 1
                            :host (plist-get spec :host)
                            :user login
                            :require '(:secret))))
               (secret (plist-get entry :secret)))
          (cond ((functionp secret) (funcall secret))
                ((stringp secret) secret))))))

(defun my/ai-build-backends ()
  "Register one OpenAI-compatible gptel backend per `my/ai-providers' entry.
Every configured provider exposes an OpenAI-compatible /v1 API, so a
single backend type covers them all."
  (setq my/ai-backends nil)
  (dolist (entry my/ai-providers)
    (let ((name (car entry))
          (spec (cdr entry)))
      (push
       (cons name
             (gptel-make-openai
                 (symbol-name name)
               :host (plist-get spec :host)
               :protocol (or (plist-get spec :protocol) "https")
               :stream t
               :endpoint (or (plist-get spec :endpoint)
                             "/v1/chat/completions")
               ;; gptel negotiates gzip via curl --compressed by default; some
               ;; servers only flush compressed buffers once full, so SSE
               ;; arrives in one big chunk.
               :curl-args '("-H" "Accept-Encoding: identity")
               :key (lambda () (my/ai-provider-key spec))
               :models (plist-get spec :models)))
       my/ai-backends)))
  (setq my/ai-backends (nreverse my/ai-backends)))

(defun my/ai-check-keys ()
  "Report providers whose API key cannot be resolved."
  (let ((missing (cl-loop for (name . spec) in my/ai-providers
                          unless (my/ai-provider-key spec)
                          collect name)))
    (when missing
      (message "init-ai: no API key resolved for: %s"
               (mapconcat #'symbol-name missing ", ")))))

(defun my/ai-select-provider (provider)
  "Prompt for PROVIDER and a model, then set them as the gptel default.
Affects new gptel sessions; `gptel-menu' switches per buffer."
  (interactive
   (list (intern
          (completing-read "AI provider: "
                           (mapcar (lambda (e) (symbol-name (car e)))
                                   my/ai-backends)
                           nil t))))
  (let ((backend (my/ai-backend provider)))
    (unless backend
      (user-error "No AI provider backend: %s" provider))
    (let* ((models (mapcar #'symbol-name (gptel-backend-models backend)))
           (default (my/ai-provider-default-model provider))
           (model (completing-read
                   (format "Model for %s: " provider)
                   models nil t nil nil
                   (and (member default models) default))))
      (setq-default gptel-backend backend
                    gptel-model (intern model))
      (message "init-ai: default provider %s, model %s" provider model))))

(defcustom my/gptel-session-directory
  (expand-file-name "~/org/gptel/")
  "Directory for gptel sessions."
  :type 'directory)


(defun my/gptel-session-file-name (buffer)
  "Return a unique session filename for BUFFER."
  (let* ((name (replace-regexp-in-string
                "\\`[-.]+\\|[-.]+\\'" ""
                (replace-regexp-in-string "[^[:alnum:]_.-]+" "-"
                                          (buffer-name buffer))))
         (base (format-time-string
                (concat "%Y%m%d-%H%M%S-" (if (string-empty-p name) "gptel" name))))
         (file (expand-file-name (concat base ".org") my/gptel-session-directory))
         (suffix 1))
    (while (file-exists-p file)
      (setq file (expand-file-name (format "%s-%d.org" base suffix)
                                   my/gptel-session-directory)
            suffix (1+ suffix)))
    file))

(defun my/gptel-save-unsaved-sessions-on-exit ()
  "Ask to save each unsaved gptel buffer before Emacs exits."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and gptel-mode (null buffer-file-name) (> (buffer-size) 0)
                 (y-or-n-p (format "Save gptel session %s? " (buffer-name))))
        (make-directory my/gptel-session-directory t)
        (set-visited-file-name (my/gptel-session-file-name buffer) t)
        (save-buffer)))))

(defun my/gptel-open-session ()
  "Open a saved gptel session and let gptel restore its state."
  (interactive)
  (unless (file-directory-p my/gptel-session-directory)
    (user-error "No gptel session directory: %s" my/gptel-session-directory))
  (let* ((files (directory-files my/gptel-session-directory nil
                                 "\\.\\(org\\|md\\)\\'" t))
         (file (completing-read "Open gptel session: " files nil t)))
    (find-file (expand-file-name file my/gptel-session-directory))
    (gptel-mode 1)
    (current-buffer)))
(defun my/gptel-setup-display ()
  "Enable window-width soft wrapping without visual-fill-column margins."
  (visual-line-mode 1)
  (setq-local truncate-lines nil
              word-wrap t)
  (when (and (boundp 'visual-fill-column-mode)
             visual-fill-column-mode)
    (visual-fill-column-mode -1))
  (when (boundp 'visual-fill-column-center-text)
    (setq-local visual-fill-column-center-text nil))
  (when (boundp 'visual-fill-column-width)
    (setq-local visual-fill-column-width nil))
  ;; gptel-highlight's margin method modifies the window margin and forces a
  ;; full-window relayout; under Emacs 29.4 GUI it can livelock with redisplay.
  ;; The fringe path (highlight--decorate) is stable in practice and keeps the
  ;; markers visible.
  (gptel-highlight-mode 1)
  (make-local-variable 'mode-line-misc-info)
  (add-to-list 'mode-line-misc-info
               '(:eval (when (and gptel-mode
                                  (caddr gptel--token-usage-strings))
                         (concat " " (caddr gptel--token-usage-strings))))
               t))

(defun my/gptel-plan ()
  "Open a gptel-agent session with the planning preset."
  (interactive)
  (require 'project)
  (gptel-agent (if-let ((proj (project-current)))
                   (project-root proj)
                 default-directory)
               'gptel-plan))

(defun my/gptel-agent-confirm-bash (command)
  "Ask before Bash COMMANDS with common destructive operations."
  (string-match-p
   "\\_<\\(rm\\|rmdir\\|shred\\|unlink\\|wipefs\\|dd\\|truncate\\|mkfs[^[:space:]]*\\)\\_>\\|\\_<find\\_>.*\\_<-delete\\_>\\|\\_<git[[:space:]]+\\(clean\\|reset\\|restore\\)\\_>.*\\(--hard\\|-[[:alnum:]]*f\\|--staged\\|--worktree\\)"
   command))

(defun my/gptel-agent-confirm-write (path filename _content)
  "Ask before the Write tool overwrites PATH/FILENAME."
  (file-exists-p (expand-file-name filename path)))

(defun my/gptel-agent-configure-tool-confirmation ()
  "Allow routine agent tools and confirm destructive or privileged actions."
  (setq gptel-confirm-tool-calls 'auto)
  (dolist (name '("Bash" "Mkdir" "Edit" "Insert" "Write" "Eval" "Agent"))
    (when-let ((tool (gptel-get-tool name)))
      (let ((confirm
             (pcase name
               ("Bash" #'my/gptel-agent-confirm-bash)
               ("Write" #'my/gptel-agent-confirm-write)
               ("Agent" t)
               (_ nil))))
        (apply #'gptel-make-tool
               (append (cl-loop for slot in '(function name description args async category include)
                                for value = (pcase slot
                                              ('function (gptel-tool-function tool))
                                              ('name (gptel-tool-name tool))
                                              ('description (gptel-tool-description tool))
                                              ('args (gptel-tool-args tool))
                                              ('async (gptel-tool-async tool))
                                              ('category (gptel-tool-category tool))
                                              ('include (gptel-tool-include tool)))
                                append (list (intern (concat ":" (symbol-name slot))) value))
                       (list :confirm confirm)))))))
(use-package gptel
  :ensure t
  :demand t
  :custom
  (gptel-default-mode 'org-mode)
  (gptel-include-reasoning t)
  (gptel-display-buffer-action '(display-buffer-full-frame))
  ;; The fringe/margin method implements markers via line-prefix/wrap-prefix
  ;; overlays, but redisplay does not recompute wrapping for those lines after
  ;; first activation, so gptel session text stops soft-wrapping (repro on
  ;; Linux/Windows; toggling gptel-mode forces a reflow). The face method is
  ;; plain-text highlighting with no overlay prefixes and has no such issue.
  (gptel-highlight-methods '(face))
  (gptel-cache t)
  (gptel-use-header-line nil)
  :config
  (require 'gptel-openai)
  (setq gptel-expert-commands t)

  ;; gptel requires host/path separation: a full-URL :endpoint stacks the default
  ;; host on top and trips the api.openai.com check, building a responses backend
  ;; by mistake (see gptel-make-openai).
  (my/ai-build-backends)
  ;; Default to the zhipu backend; fall back to the first registered provider
  ;; so the module still works after users replace the stock registry.
  (let* ((provider (if (assq 'zhipu my/ai-backends)
                       'zhipu
                     (caar my/ai-backends)))
         (backend (my/ai-backend provider)))
    (when backend
      (setq-default gptel-backend backend
                    gptel-model (my/ai-provider-default-model provider))))
  ;; GLM 5.x thinks in interleaved mode; gptel's block parsing assumes reasoning
  ;; only precedes the answer. Disable thinking via Zhipu's official parameter.
  (put 'glm-5.3-flash :request-params '(:thinking (:type "disabled")))
  (add-hook 'kill-emacs-hook #'my/gptel-save-unsaved-sessions-on-exit)
  (add-hook 'gptel-post-response-functions #'gptel-end-of-response)
  (add-hook 'gptel-mode-hook #'my/gptel-setup-display)
  (add-hook 'after-init-hook #'my/ai-check-keys))

(use-package gptel-agent
  :ensure t
  :demand t
  :after gptel
  :config
  (gptel-agent-update)
  (my/gptel-agent-configure-tool-confirmation))

(use-package gptel-preset-collection
  :quelpa (gptel-preset-collection
           :fetcher github
           :repo "karthink/gptel-preset-collection")
  :after gptel
  :demand t)

(use-package minuet
  :ensure t
  :demand t
  :config
  (setq minuet-provider 'openai-compatible
        minuet-auto-suggestion-debounce-delay 0.4
        minuet-auto-suggestion-throttle-delay 1.0)
  (plist-put minuet-openai-compatible-options :end-point my/gptel-zhipu-endpoint)
  (plist-put minuet-openai-compatible-options :api-key "ZHIPUAI_API_KEY")
  (plist-put minuet-openai-compatible-options :model "glm-5.3-flash")
  (plist-put minuet-openai-compatible-options :optional '(:thinking (:type "disabled")))
  (define-key minuet-active-mode-map (kbd "TAB") #'minuet-accept-suggestion)
  (define-key minuet-active-mode-map [tab] #'minuet-accept-suggestion)
  (add-hook 'prog-mode-hook #'minuet-auto-suggestion-mode)
  ;; Optional: keep evil out of the module's required dependencies.
  (when (fboundp 'evil-normalize-keymaps)
    (add-hook 'minuet-active-mode-hook #'evil-normalize-keymaps)))

(defconst my/gptel-init-version "3.0-standalone"
  "Config version probe: M-: my/gptel-init-version after restarting Emacs.")

(provide 'init-ai)
;;; init-ai.el ends here
