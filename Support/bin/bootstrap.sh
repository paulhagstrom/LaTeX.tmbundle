#!/bin/bash

# get the document's filename.
eval document=\$$#;

# enable synctex by default
synctex=1;

dirname="$(dirname "$document")";
ext=${document##*.}
basename=$(basename -s ".$ext" "$document");
jobname="$basename";

if [ -n $TM_LATEX_HIDE_AUX_FILES ]; then jobname=".$jobname"; fi

cd "$dirname";

# paths to the auxillary files we care about.
syn="$jobname.synctex.gz"
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

# Set up a basic preamble and wrap the document in \begin{document} / \end{document}
# when the file is a TeX fragment.
grep -q '\\begin{document}' "$document";
if [ $? != 0 ]; then
  
  # turn off synctex when compiliing document fragments.
  synctex=0; rm "$syn";
  
  fragment="$document";
  document="$TMPDIR/$(basename "$document")-wrap";
    
  if [ -z "$TM_LATEX_DEFAULT_PREAMBLE" ]; then
    export TM_LATEX_DEFAULT_PREAMBLE="$TM_BUNDLE_SUPPORT/lib/default-preamble"
  fi
  
  echo "-->Using default preamble"
  
  # cat "$TM_LATEX_DEFAULT_PREAMBLE" > "$document";
  
  echo "%&$(dirname "$TM_LATEX_DEFAULT_PREAMBLE")/$(basename -s ".tex" "$TM_LATEX_DEFAULT_PREAMBLE")" > "$document";
  echo "\\begin{document}" >> "$document";
  cat "$fragment" >> "$document";
  echo "\\end{document}" >> "$document";
  
fi

# if the document IS a preamble.
if [[ "$document" = *'preamble.tex' ]]; then
  echo "-->Compiling preamble";
  "${@:1:$#-1}" -halt-on-error -output-format=pdf -jobname="$jobname" -ini \&latex "$document" \\dump;
  exit $?;
fi

# Check if the document specifies a fmt file.
ltx="$(head -n 1 "$document" | awk '/^%&.*/{print substr($1, 3)}').ltx"
# Compile the fmt file if necessary.
if [[ -a "$ltx" ]]; then
  pushd $(dirname "$ltx")

  fmt="$(dirname "$ltx")/$(basename -s .ltx "$ltx").fmt";
  
  # do we need to update the fmt file?
  if [[ ! -e "$fmt" || "$ltx" -nt "$fmt" ]]; then
    
    echo "-->Compiling preamble";
    
    # compile preamble
    "${@:1:$#-1}" -halt-on-error \
                  -jobname="$(basename -s '.ltx' "$ltx")" \
                  -output-format=pdf \
                  -ini \&latex "$ltx" \\dump;
    
    rc=$?;
    if [ $rc -ne 0 ]; then
      echo "-->Failed to compile default preamble."
      exit $rc;
    fi
    
  fi
  
  popd
fi


# some flags to help us determine when to run or not run
ranbibtex=0; rerun=1;


for i in `jot 4`; do # we never need more than five iterations.
  
  # check if we are done compiling.
  if [ $rerun -eq 0 ]; then break; else rerun=0; fi

  # if [ $i -gt 1 ]; then
    echo "--------------------------------------------------------------------------------";
  # fi
  
  # get index/citation hashes so we can notice if they change.
  if [ -e "$idx" ]; then idxhash=$(md5 -q "$idx"); fi
  if [[ -e "$aux" && $(egrep '^\\bibdata' "$aux") ]]; then
    bibhash=$(egrep '^\\bib' "$aux" | md5 -q);
  fi
  
  echo "-->Typesetting $(basename "$document")";
  
  # run latex and watch the output for lines that tell us to run again.
  "${@:1:$#-1}"  -halt-on-error      \
                 -synctex=$synctex   \
                 -parse-first-line   \
                 -output-format=pdf  \
                 -jobname="$jobname" \
                 "$document"         \
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
    eval bibtex "$TM_BIBTEX_FLAGS" '"$aux"';
    ranbib=1; rerun=1;
  fi

done

mv "$pdf" "$basename.pdf"
if [ $synctex -eq 1 ]; then mv "$syn" "$basename.synctex.gz"; fi
