#!/bin/bash

# get the document's filename.
eval document=\$$#;

ext=${document##*.}
documentdir="$(dirname "$document")";
jobname="$(basename -s ".$ext" ".$document")";

cd "$documentdir";

# paths to the auxillary files we care about.
idx="$jobname.idx";
aux="$jobname.aux";
blg="$jobname.blg";
bbl="$jobname.bbl";
pdf="$jobname.pdf";

# Trash outdated auxillary files to force TeX to regenerate them.
if [ -e "$blg" ]; then
  awk '{ match($0, /^Database file #[0-9]+: /); if (RLENGTH > 0) { print substr($0, RLENGTH+1); } }' < "$blg" | while read bib; do
    if [ "$bib" -nt "$aux" ]; then
      rm "$idx" "$aux" "$blg" "$bbl" "$pdf";
      break;
    fi
  done
fi

ranbibtex=0; rerun=1;

# if the document IS a preamble.
if [[ "$document" = *'preamble.tex' ]]; then
  echo "-->Compiling preamble";
  "${@:1:$#-1}" -halt-on-error -output-format=pdf -jobname="$jobname" -ini \&latex "$document" \\dump;
  exit $?;
fi

# Check if the document specifies a fmt file.
firstline=$(head -n 1 "$document" | awk '/^%&.*/{print substr($1, 3)}')
if [ -e "$firstline" ]; then
  preamble="${firstline}.tex"
  echo "-->$preamble"
fi

# Compile the fmt file if necessary.
if [[ -e "$preamble" ]]; then

  fmt="$(basename -s .tex "$preamble").fmt";
  
  # do we need to update the fmt file?
  if [[ ! -e "$fmt" || "$preamble" -nt "$fmt" ]]; then
    
    echo "-->Compiling preamble";
    
    # compile preamble
    "${@:1:$#-1}" -halt-on-error -jobname="$(basename -s .tex "$preamble")" -output-format=pdf -ini \&latex "$preamble" \\dump; rc=$?;
    if [ $rc -ne 0 ]; then exit $rc; fi
    
    echo "--------------------------------------------------------------------------------";
  
  fi
fi

# Set up a basic preamble and wrap the document in \begin{document} / \end{document}
# when the file is a TeX fragment.

grep -q '\\begin{document}' "$document";
if [ $? != 0 ]; then
  fragment="$document";
  document="$TMPDIR/$jobname.$ext";
  
  if [ -z "$TM_LATEX_DEFAULT_PREAMBLE" ]; then
    export TM_LATEX_DEFAULT_PREAMBLE="$TM_BUNDLE_SUPPORT/lib/default-preamble.tex"
  fi
  
  echo "-->Compiling with default preamble $(basename "$TM_LATEX_DEFAULT_PREAMBLE")"
  cat "$TM_LATEX_DEFAULT_PREAMBLE" > "$document";
  
  echo "\\begin{document}" >> "$document";
  cat "$fragment" >> "$document";
  echo "\\end{document}" >> "$document";
fi

i=0;
while [ $i -lt 5 ]; do
  
  let i=i+1
  if [ $rerun -eq 0 ]; then break; else rerun=0; fi

  if [ $i -gt 1 ]; then
    echo "--------------------------------------------------------------------------------";
  fi
  
  # get file hashes so we can notice if they change.
  if [ -e "$idx" ]; then idxhash=$(md5 -q "$idx"); fi
  if [[ -e "$aux" && $(egrep '^\\bibdata' "$aux") ]]; then
    bibhash=$(egrep '^\\bib' "$aux" | md5 -q);
  fi
  
  echo "-->Typesetting $(basename "$document")";
  # run latex and watch the output for lines that tell us to run again.
  "${@:1:$#-1}"  -halt-on-error -synctex=1 -parse-first-line -output-format=pdf -jobname="$jobname" "$document" \
      | awk '{print $0;} /Rerun/ { r=1 } END{ exit r  }';

  rc=(${PIPESTATUS[@]}); rerun=${rc[1]};

  if [ ${rc[0]} -ne 0 ]; then exit ${rc[0]}; fi
  
  # run makeindex if the idx changed.
  if [[ -e "$idx" && $idxhash != $(md5 -q "$idx") ]]; then
    echo "--------------------------------------------------------------------------------";
    makeindex "$idx";
    rerun=1;
  fi
  
  # if the aux file was just created and has a \bibdata line or if bibhash has changed then run bibtex.
  if [[ -z "$ranbib" && \
        (-z "$bibhash" && $(egrep '^\\bibdata' "$aux") || \
         -n "$bibhash" && "$bibhash" != $(egrep '^\\bib' "$aux" | md5 -q)) ]];
  then
    echo "--------------------------------------------------------------------------------";
    echo "-->Compiling bibliography";
    bibtex "$TM_BIBTEX_FLAGS" "$aux";
    ranbib=1; rerun=1;
  fi

done
