#!/bin/bash

shopt -s extglob;

# get the document's filename.
eval document=\$$#;

# enable synctex by default
synctex=1;

dirname="$(dirname "$document")";
ext=${document##*.}
basename=$(basename -s ".$ext" "$document");
jobname="$basename";

args='-halt-on-error -no-parse-first-line -output-format=pdf -file-line-error';

if [ -n "$TM_LATEX_HIDE_AUX_FILES" ]; then jobname=".$jobname"; fi

cd "$dirname";

# paths to the auxillary files we care about. we will
# watch changes in these files, and compile accordingly.

syn="$jobname.synctex.gz"
log="$jobname.log";
idx="$jobname.idx";
aux="$jobname.aux";
blg="$jobname.blg";
bbl="$jobname.bbl";
pdf="$jobname.pdf";

# if the document IS a preamble.
if [[ "$document" = *'.ltx' ]]; then
  echo "-->Dumping format file";
  eval echo '$' ${@:1:$#-1} $args -jobname='$jobname' \
                                  -ini \
                                  '\"\&latex\"' \
                                  '\"$document\"' \
                                  '\\\\dump' >&2;
                                  
  eval ${@:1:$#-1} $args -jobname='$jobname' \
                         -ini \
                         '\&latex' \
                         '"$document"' \
                         '\\dump';
  rc=$?;
  rm -f "$pdf"; rm -f "$log";
  exit $rc;
fi

# Set up a basic preamble and wrap the document in \begin{document} / \end{document}
# when the file is a TeX fragment.

if ! grep -q '\\documentclass' "$document"; then
  
  # See if the file specifies a fmt.
  if head -n 1 "$document" | grep -q '^%&'; then
    
    fmt="$(head -n 1 "$document" | ruby -ne 'puts $_.match(/^%&\s*(\/?(?:\\ |[^ ])*?)(?:\.fmt|\.ltx)?(?=\s)/)[1]')";
    
  # Otherwise, we use the default.
  else

    fmt="${TM_LATEX_DEFAULT_FORMAT:-$TM_BUNDLE_SUPPORT/lib/tmdefault.fmt}";
    
  fi

  fmt="${fmt%\.*(fmt|ltx)}.fmt";
  ltx="${fmt%\.fmt}.ltx";

  export TEXFORMATS=":${TEXFORMATS}:$(dirname "$fmt"):"
  
  args="$args -fmt=\"$(basename -s ".fmt" "$fmt")\"";
    
  # turn off synctex when compiling document fragments.
  synctex=0; rm -f "$syn";
  
  fragment="$document-frag";
  mv "$document" "$fragment"
  # document="$TMPDIR/$(basename "$document")";
  
  echo "\\begin{document}" > "$document";
  cat "$fragment" >> "$document";
  echo >> "$document"; 
  echo "\\end{document}" >> "$document"; 
  
fi


# Compile the fmt file if necessary.
if [[ -a "$ltx" ]]; then
  pushd "$(dirname "$ltx")" > /dev/null
  
  # do we need to update the fmt file?
  if [[ ! -e "$fmt" || "$ltx" -nt "$fmt" ]]; then
    
    echo "-->Precompiling format file $(basename "$fmt")";
    
    if [ -n "$TM_LATEX_DEBUG" ]; then
      eval echo '$' ${@:1:$#-1} '$args' \
                                -jobname='"$(basename -s '.ltx' "$ltx")"' \
                                -ini '\&latex' '\"$ltx\"' '\\\\dump' >&2;
    fi

    
    # compile preamble
    eval ${@:1:$#-1} '$args' \
                     -jobname='"$(basename -s '.ltx' "$ltx")"' \
                     -ini '\&latex' '\"$ltx\"' '\\dump';
    
    rc=$?;
    if [ $rc -ne 0 ]; then
      echo "-->Failed to dump the default format file, quitting"
      exit $rc;
    fi
    
    #rm "$(dirname "$ltx")/$(basename -s .ltx "$ltx").(log|pdf)";
    
  else
    echo "-->Using precompiled format $(basename "$fmt")"
  fi
    
  popd > /dev/null
fi

# Trash outdated auxillary files to force TeX to regenerate them.
if [ -e "$blg" ]; then
  awk '{ match($0, /^Database file #[0-9]+: /); if (RLENGTH > 0) { print substr($0, RLENGTH+1); } }' < "$blg" | while read bib; do
    if [ "$bib" -nt "$aux" ]; then
      rm "$idx" "$aux" "$blg" "$bbl" "$pdf";
      break;
    fi
  done
fi

# some flags to help us determine when to run or not run
ranbibtex=0; rerun=1;

for i in `jot 4`; do # we never need more than five iterations.
  
  # check if we are done compiling.
  if [ $rerun -eq 0 ]; then break; else rerun=0; fi

  if [ $i -gt 1 ]; then
    echo "--------------------------------------------------------------------------------";
  fi
  
  # get index/citation hashes so we can notice if they change.
  if [ -e "$idx" ]; then idxhash=$(md5 -q "$idx"); fi
  if [[ -e "$aux" && $(egrep '^\\bibdata' "$aux") ]]; then
    bibhash=$(egrep '^\\bib' "$aux" | md5 -q);
  fi
  
  echo "-->Typesetting $(basename "$document")";
  
  if [ -n "$TM_LATEX_DEBUG" ]; then
    eval echo '$' "${@:1:$#-1}" $args \
                                -jobname='"$jobname"' \
                                -synctex='"$synctex"' \
                                '"$document"' >&2;
  fi
  
  # run latex and watch the output for lines that tell us to run again.
  eval ${@:1:$#-1} $args \
                   -jobname='"$jobname"' \
                   -synctex='"$synctex"' \
                   '"$document"' \
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
