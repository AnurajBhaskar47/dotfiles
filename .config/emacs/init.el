(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes '(gruber-darker))
 '(custom-safe-themes
   '("e13beeb34b932f309fb2c360a04a460821ca99fe58f69e65557d6c1b10ba18c7"
     default))
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; --- package bootstrap ---
(require 'package)
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
	("nongnu" . "https://elpa.nongnu.org/nongnu/")
	("melpa" . "https://melpa.org/packages/")))
(package-initialize)
;; (unless package-archive-contents
;;   (package-refresh-contents))
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; --- core UX ---
(setq make-backup-files nil)
(menu-bar-mode 0)
(tool-bar-mode 0)
(column-number-mode 1)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode)
(recentf-mode 1)
(save-place-mode 1)
(global-auto-revert-mode 1)
(setq select-enable-clipboard t)
(setq select-enable-primary t)
(setq save-interprogram-paste-before-kill t)

;; --- evil ---
(setq evil-want-integration t)
(setq evil-want-keybinding nil)
(setq evil-want-C-u-scroll t)
(use-package evil
  :config
  (evil-mode 1))
(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; --- completion stack ---
(use-package vertico
  :init (vertico-mode 1))
(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
	completion-category-defaults nil
	completion-category-overrides '((file (styles basic partial-completion)))))
(use-package marginalia
  :init (marginalia-mode 1))
(use-package consult
  :bind (("C-s"     . consult-line)          ;; live search in current buffer
         ("C-c i"   . consult-imenu)         ;; symbols in current buffer
         ("C-c r"   . consult-ripgrep)       ;; live grep in folder/project
         ("C-x C-f" . consult-find)          ;; recursive file finder
         ("C-x b"   . consult-buffer)))
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)
  (corfu-cycle t)
  (corfu-preselect 'prompt))
(use-package cape)

;; --- lsp + diagnostics ---
(use-package flycheck
  :init (global-flycheck-mode 1))
(use-package lsp-mode
  :commands lsp lsp-deferred
  :init
  (setq lsp-keymap-prefix "C-c l")
  :config
  (lsp-enable-which-key-integration t))
(use-package lsp-ui
  :commands lsp-ui-mode)
(use-package lsp-java
  :after lsp-mode)
(use-package lsp-pyright
  :after lsp-mode)

;; --- language modes + lsp hooks ---
(use-package go-mode
  :hook (go-mode . lsp-deferred))
(use-package python-mode
  :hook (python-mode . lsp-deferred))
(use-package cc-mode
  :hook ((c-mode c++-mode) . lsp-deferred))
(use-package lua-mode
  :hook (lua-mode . lsp-deferred))
(add-hook 'java-mode-hook #'lsp-deferred)

;; --- format on save ---
(defun my/lsp-format-buffer-on-save ()
  (add-hook 'before-save-hook #'lsp-format-buffer nil t))
(defun my/lsp-format-and-imports-on-save ()
  (add-hook 'before-save-hook
            (lambda ()
              (lsp-organize-imports)
              (lsp-format-buffer))
            nil t))
(add-hook 'go-mode-hook #'my/lsp-format-buffer-on-save)
(add-hook 'c-mode-hook #'my/lsp-format-buffer-on-save)
(add-hook 'c++-mode-hook #'my/lsp-format-buffer-on-save)
(add-hook 'python-mode-hook #'my/lsp-format-and-imports-on-save)
(add-hook 'java-mode-hook #'my/lsp-format-and-imports-on-save)
(add-hook 'prog-mode-hook
          (lambda ()
            (setq tab-width 4
                  indent-tabs-mode t
                  c-basic-offset 4)))
