# ai-agent-in-emacs

Standalone Emacs module for AI coding features, extracted from
[zongwu233/emacs.d](https://github.com/zongwu233/emacs.d). Powered by
[gptel](https://github.com/karthink/gptel),
[gptel-agent](https://github.com/karthink/gptel-agent),
[gptel-preset-collection](https://github.com/karthink/gptel-preset-collection)
and [minuet](https://github.com/milanglacier/minuet-ai.el).

- **Multi-provider registry** — `my/ai-providers` declares one OpenAI-compatible
  provider per entry; one gptel backend is built per entry.
- **authinfo-backed keys** — hosts, logins and API keys come from `~/.authinfo`
  via `auth-source` (see below); alternatively a key can be read from an
  environment variable.
- **Agent safety rails** — routine gptel-agent tools run freely; destructive
  Bash commands and overwriting Writes ask for confirmation.
- **Sessions** — dedicated chat buffers use `org-mode`; unsaved sessions are
  offered for save on exit; sessions can be reopened with gptel state.
- **Inline completion** — minuet on the same OpenAI-compatible endpoint.

## Requirements

- Emacs >= 29
- `curl` (gptel transport)
- Packages: `gptel`, `gptel-agent`, `minuet` (MELPA), `gptel-preset-collection`
  (quelpa, fetched automatically), `quelpa` + `quelpa-use-package` for the
  GitHub fetch.

## Installation

```bash
git clone https://github.com/zongwu233/ai-agent-in-emacs.git ~/.emacs.d/site-lisp/ai-agent-in-emacs
```

```emacs-lisp
(add-to-list 'load-path (expand-file-name "site-lisp/ai-agent-in-emacs"
                                          user-emacs-directory))
(require 'init-ai-agent)
```

[zongwu233/emacs.d](https://github.com/zongwu233/emacs.d) clones this repo
automatically (shallow) into `site-lisp/` on first load. `use-package :ensure`
installs missing packages on first load.

## Providers and authinfo

The stock registry ships a single public provider (`zhipu`, key from
`ZHIPUAI_API_KEY`). All other providers are declared directly in
`~/.authinfo` — hosts, logins, API keys **and model lists** never appear
in any config file.

Add the netrc fields `provider`, `models`, `dmodel` and `transport` to an
authinfo line:

```
machine api.example-relay.com login my-username password sk-... \
    provider my-relay dmodel model-a models "model-a model-b model-c"
machine localhost:9000 login local-me password sk-local \
    provider local transport http models "my-local-model"
```

| Field | Meaning |
|-------|---------|
| `provider` | provider name (required; turns the entry into a registry entry) |
| `models` | model symbols offered in the menu; keep it **last** on the line |
| `dmodel` | preselected default model |
| `transport` | `http` for local servers (default `https`) |

The `machine` field is the API base_url host, `login` selects the entry
and `password` is the API key; endpoints default to
`/v1/chat/completions`. After editing authinfo, run `M-x
my/ai-load-authinfo-providers` to (re)load them.

Alternatively, declare entries in elisp **before**
`(require 'init-ai-agent)`:

```emacs-lisp
(setq my/ai-providers
      (append my/ai-providers
              '((my-relay
                 :host "api.example-relay.com"   ; machine   field of ~/.authinfo
                 :login "my-username"            ; login     field of ~/.authinfo
                 :models (model-a model-b)
                 :default model-a))))
```

Per-entry options:

| Key | Meaning |
|-----|---------|
| `:host` | API base_url host — the `machine` field of `~/.authinfo` |
| `:login` | authinfo login selecting the entry; its `password` is the API key |
| `:auth` | `(:env "VARNAME")` — read the key from an env var instead |
| `:endpoint` | chat path, default `/v1/chat/completions` (OpenAI-compatible) |
| `:protocol` | `https` (default) or `http` for local servers |
| `:models` | model symbols offered in the menu |
| `:default` | preselected model |

After changing the registry at runtime, rebuild backends with `M-x
my/ai-build-backends`. `M-x my/ai-select-provider` switches the default
provider/model for new gptel sessions; `gptel-menu` switches per buffer.
`M-x my/ai-check-keys` reports providers whose key cannot be resolved.

## Commands

| Command | Purpose |
|---------|---------|
| `gptel` | chat buffer (org-mode) |
| `gptel-menu` | per-buffer backend/model switch |
| `my/ai-select-provider` | default provider + model |
| `gptel-agent` | agent session in current project |
| `my/gptel-plan` | agent session with the planning preset |
| `gptel-agent-compact` | compact agent context |
| `my/gptel-open-session` | reopen a saved session |
| `minuet-show-suggestion` | inline completion |

No keybindings are forced on you; bind them in your config, e.g. with
[general.el](https://github.com/noctuid/general.el):

```emacs-lisp
(which-key-add-key-based-replacements "SPC a" "ai")
(general-define-key :prefix "SPC" :states 'normal
  "a s" 'gptel
  "a a" 'gptel-agent
  "a P" 'my/ai-select-provider)
```

## Tests

```bash
emacs --batch -Q -L . -l tests/run.el
```

Uses the packages installed under `~/.emacs.d/elpa` (override with
`ELPA_DIR=...`). Tests never touch the real `~/.authinfo` — key resolution is
exercised against a temporary netrc fixture.

## License

[MIT](LICENSE)
