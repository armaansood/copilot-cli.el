EMACS ?= emacs

.PHONY: all clean checkdoc compile test

default: all

EL_FILES := $(wildcard *.el)
TEST_FILES := $(wildcard *-test.el)
SRC_FILES := $(filter-out $(TEST_FILES),$(EL_FILES))

clean:
	rm -f *.elc

checkdoc:
	for FILE in $(SRC_FILES); do $(EMACS) --batch -L . -eval "(setq sentence-end-double-space nil)" -eval "(checkdoc-file \"$$FILE\")" ; done

compile: clean
	$(EMACS) --batch -L . --eval "(setq sentence-end-double-space nil)" -f batch-byte-compile $(SRC_FILES)

test:
	$(EMACS) --batch -L . -l ert -l copilot-cli-test.el -f ert-run-tests-batch-and-exit

all: checkdoc compile test
