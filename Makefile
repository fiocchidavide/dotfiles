# Dotfiles bootstrap.  Run `make help` to list targets.
# Packages are auto-detected as the top-level directories in this repo.
STOW_DIR := $(CURDIR)
PACKAGES := $(patsubst %/,%,$(wildcard */))
# Resolve brew up front, falling back to the Apple-Silicon default path so a
# freshly installed Homebrew (not yet on PATH) is still found within `make`.
BREW := $(shell command -v brew 2>/dev/null || echo /opt/homebrew/bin/brew)
ZSH_CUSTOM ?= $(HOME)/.oh-my-zsh/custom

.DEFAULT_GOAL := help
.PHONY: install ensure-brew install-brew brew omz link relink unlink doctor help

# link before omz so the stowed ~/.zshrc exists first (omz KEEP_ZSHRC keeps it).
install: ensure-brew brew link omz ## full bootstrap: Homebrew + deps + symlinks + oh-my-zsh

ensure-brew: ## install Homebrew only if it isn't already present
	@command -v brew >/dev/null 2>&1 || $(MAKE) install-brew

install-brew: ## install Homebrew via the official installer
	/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew: ## install Homebrew dependencies from the Brewfile
	$(BREW) bundle --file="$(STOW_DIR)/Brewfile"

omz: ## install oh-my-zsh + third-party zsh plugins (idempotent)
	@if [ ! -d "$(HOME)/.oh-my-zsh" ]; then \
		echo "→ installing oh-my-zsh"; \
		RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
			sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; \
	else echo "✓ oh-my-zsh already installed"; fi
	@for spec in Aloxaf/fzf-tab zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do \
		name=$${spec#*/}; dir="$(ZSH_CUSTOM)/plugins/$$name"; \
		if [ -d "$$dir" ]; then echo "✓ $$name"; \
		else echo "→ cloning $$name"; git clone --depth=1 "https://github.com/$$spec" "$$dir"; fi; \
	done

link: ## symlink all packages into $HOME
	@mkdir -p "$(HOME)/.config"
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -v $(PACKAGES)

relink: ## re-symlink packages (after adding/removing files)
	@mkdir -p "$(HOME)/.config"
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -Rv $(PACKAGES)

unlink: ## remove all symlinks for every package
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -Dv $(PACKAGES)

doctor: ## check runtime deps of x commands (uses a login shell for full PATH)
	@zsh -ic 'x doctor' 2>/dev/null || true

help: ## show this help
	@grep -hE '^[a-z][a-zA-Z_-]*:.*##' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'
