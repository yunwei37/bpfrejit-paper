#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <source.tex> <output.tikz.pdf>" >&2
  exit 1
fi

src="$1"
out="$2"

src_dir="$(cd "$(dirname "$src")" && pwd -P)"
src_file="$(basename "$src")"
src_abs="${src_dir}/${src_file}"

out_dir="$(cd "$(dirname "$out")" && pwd -P)"
out_file="$(basename "$out")"
out_abs="${out_dir}/${out_file}"

paper_root="$(cd "$(dirname "$0")/.." && pwd -P)"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tikz-figure.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

wrapper="${tmpdir}/wrapper.tex"

cat >"$wrapper" <<EOF
\documentclass[varwidth=true,border=4pt]{standalone}
\input{${paper_root}/helpers/packages}
\input{${paper_root}/helpers/commands}

\setlength{\textwidth}{6.75in}
\setlength{\columnwidth}{3.25in}
\setlength{\linewidth}{\columnwidth}

\makeatletter
\renewenvironment{figure}[1][]{%
  \par\centering\setlength{\linewidth}{\columnwidth}%
}{\par}
\renewenvironment{figure*}[1][]{%
  \par\centering\setlength{\linewidth}{\textwidth}%
}{\par}
\makeatother

\begin{document}
\makeatletter
\renewcommand{\caption}{\@gobble}
\renewcommand{\label}{\@gobble}
\makeatother
\input{${src_abs}}
\end{document}
EOF

pdflatex \
  -interaction=nonstopmode \
  -halt-on-error \
  -output-directory "$tmpdir" \
  "$wrapper" >/dev/null

pdfcrop "${tmpdir}/wrapper.pdf" "$out_abs" >/dev/null
