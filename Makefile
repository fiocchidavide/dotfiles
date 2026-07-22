# Dotfiles bootstrap.  Run `make help` to list targets.
# Packages are auto-detected as the top-level directories in this repo.
STOW_DIR := $(CURDIR)
PACKAGES := $(patsubst %/,%,$(wildcard */))

.DEFAULT_GOAL := help
.PHONY: install brew link relink unlink doctor help

install: brew link ## install Homebrew deps, then symlink all packages

brew: ## install Homebrew dependencies from the Brewfile
	brew bundle --file="$(STOW_DIR)/Brewfile"

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
