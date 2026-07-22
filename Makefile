# Dotfiles bootstrap.  Run `make help` to list targets.
# Packages are auto-detected as the top-level directories in this repo.
STOW_DIR := $(CURDIR)
PACKAGES := $(patsubst %/,%,$(wildcard */))
# Resolve brew up front, falling back to the Apple-Silicon default path so a
# freshly installed Homebrew (not yet on PATH) is still found within `make`.
BREW := $(shell command -v brew 2>/dev/null || echo /opt/homebrew/bin/brew)

.DEFAULT_GOAL := help
.PHONY: install ensure-brew install-brew brew link relink unlink doctor help

install: ensure-brew brew link ## install Homebrew (if missing) + deps, then symlink

ensure-brew: ## install Homebrew only if it isn't already present
	@command -v brew >/dev/null 2>&1 || $(MAKE) install-brew

install-brew: ## install Homebrew via the official installer
	/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew: ## install Homebrew dependencies from the Brewfile
	$(BREW) bundle --file="$(STOW_DIR)/Brewfile"

link: ## symlink all packages into $HOME
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -v $(PACKAGES)

relink: ## re-symlink packages (after adding/removing files)
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -Rv $(PACKAGES)

unlink: ## remove all symlinks for every package
	stow --dir="$(STOW_DIR)" --target="$(HOME)" -Dv $(PACKAGES)

doctor: ## check runtime deps of x commands (uses a login shell for full PATH)
	@zsh -ic 'x doctor' 2>/dev/null || true

help: ## show this help
	@grep -hE '^[a-z][a-zA-Z_-]*:.*##' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'
