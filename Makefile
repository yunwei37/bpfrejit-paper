SHELL := /bin/bash

# ---------- TikZ figures ----------
TIKZ_SOURCES := $(wildcard figures/*.tex)
TIKZ_OUTPUTS := $(TIKZ_SOURCES:.tex=.tikz.pdf)
TIKZ_HELPERS := helpers/build_tikz_figure.sh helpers/packages.tex helpers/commands.tex

# ---------- draw.io figures ----------
DRAWIO_SOURCES := $(filter-out figures/sosp26-bpfrejit.drawio,$(wildcard figures/*.drawio))
DRAWIO_OUTPUTS := $(DRAWIO_SOURCES:.drawio=.drawio.pdf)

.PHONY: all tikz tikz-clean drawio drawio-clean

all: tikz drawio

# ---------- TikZ rules ----------
tikz: $(TIKZ_OUTPUTS)

figures/%.tikz.pdf: figures/%.tex $(TIKZ_HELPERS)
	./helpers/build_tikz_figure.sh "$<" "$@"

tikz-clean:
	rm -f $(TIKZ_OUTPUTS)

# ---------- draw.io rules ----------
drawio: $(DRAWIO_OUTPUTS)

figures/%.drawio.pdf: figures/%.drawio
	xvfb-run -a drawio --export --format pdf --crop \
	  --output "$@" "$<" 2>/dev/null

drawio-clean:
	rm -f $(DRAWIO_OUTPUTS)
