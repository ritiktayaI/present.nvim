.PHONY: test

test:
	~/bin/nvim-macos-arm64/bin/nvim --headless --noplugin -u scripts/minimal_init.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './scripts/minimal_init.vim' }"
