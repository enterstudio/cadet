ELM_FILES = $(shell find src/ -type f -name '*.elm' -or -name '*.js')
LESS_FILES = $(shell find css/ -type f -name '*.less')

all: public/elm.js public/main.css worker.js elm-stuff

.PHONY: clean

clean:
	rm -f public/elm.js public/elm.min.js public/main.css bindata.go

worker.js: $(ELM_FILES)
	sysconfcpus -n 4 elm make --warn --output $@ --yes src/Worker.elm

public/elm.js: $(ELM_FILES)
	sysconfcpus -n 4 elm make --warn --output $@ --yes src/Main.elm

public/main.css: css/main.less
	lessc --autoprefix='last 2 Chrome versions, last 2 Firefox versions' --clean-css="--advanced" css/main.less $@
