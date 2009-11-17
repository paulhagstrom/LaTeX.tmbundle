#!/bin/bash

info() {
  echo "-->" $*;
};

seperator(){
  echo "--------------------------------------------------------------------------------";
};

perform_command(){
  if [ -z "$TM_LATEX_DEBUG" ]; then
    eval echo '$' $* >&2;
  fi
  eval $*;
}

shopt -s extglob;

# parse the arguments we've been given
engine=$1;
if [ "$#" -gt "2" ]; then flags="${@:2:$#-1}"; fi
info "Flags: $flags";
eval document=\$$#;

# enable synctex by default
synctex=1;

dirname="$(dirname "$document")";
cd "$dirname";

ext=${document##*.}
basename=$(basename -s ".$ext" "$document");

if [ -n "$TM_LATEX_HIDE_AUX_FILES" ];
then
  # this is kind of experimental and doesn't work reliably…
  # bibtex won't find your aux files and of course it's not
  # possible to TELL BIBTEX TO LOOK SOMEWHERE ELSE.
jobname=".$basename";
else jobname="$basename"; fi

flags="$flags -halt-on-error -no-parse-first-line -file-line-error";

# xelatex will barf on -output-format
if [[ "$1" = *'pdflatex' ]]; then flags="$flags -output-format=pdf"; fi

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
  
  info "Dumping format file";
  
  perform_command "$engine" "$flags" -jobname='$jobname.$engine' -ini '\&latex' '"$document"' '\\dump'; rc=$?;
  rm -f "$pdf"; rm -f "$log";
  
  exit $rc;
fi


# add a -fmt argument if there is no \documentclass
if ! grep -q '\\documentclass' "$document"; then
  
  # See if the file specifies a fmt.
  if head -n 1 "$document" | grep -q '^%&'; then
    
    ltx="$(head -n 1 "$document" | ruby -ne 'puts $_.match(/^%&\s*(\/?(?:\\ |[^ ])*?)(?:\.fmt|\.ltx)?(?=\s)/)[1]')";
    
  else # we use the default.
    
    ltx="${TM_LATEX_DEFAULT_FORMAT:-$TM_BUNDLE_SUPPORT/lib/tmdefault.ltx}";
    
  fi

  ltx="${ltx%\.*(fmt|ltx)}.ltx";
  fmt="${ltx%\.ltx}.$engine.fmt";

  export TEXFORMATS=":${TEXFORMATS}:$(dirname "$fmt"):"
  
  # add the fmt file as a command line argument.
  # This is a lot easier than trying to create a
  # new file with a  %! firstline.
  flags="$flags -fmt=\"$(basename -s ".fmt" "$fmt")\"";
  
fi


# Compile the fmt file if necessary.
if [[ -a "$ltx" ]]; then
  pushd "$(dirname "$ltx")" > /dev/null
  
  # do we need to update the fmt file?  (check that the fmt file doesn't exist or the ltx file is newer.)
  if [[ ! -e "$fmt" || "$ltx" -nt "$fmt" ]]; then
    
    info "Precompiling format file $(basename "$fmt")";
    
    # compile preamble
    perform_command $engine $flags -jobname='"$(basename -s '.ltx' "$ltx")"' \
                     -ini '\&latex' '\"$ltx\"' '\\dump';
    
    rc=$?;
    if [ $rc -ne 0 ]; then
      info "Failed to dump the format file, quitting"
      exit $rc;
    fi
    
    rm "$(dirname "$ltx")/$(basename -s .ltx "$ltx").(log|pdf)";
    
  else
    info "Using precompiled format $(basename "$fmt")"
  fi
    
  popd > /dev/null
fi

# Trash outdated auxillary files to force TeX to regenerate them.
if [ -e "$blg" ]; then
  cat "$blg" | awk '{ match($0, /^Database file #[0-9]+: /); if (RLENGTH > 0) { print substr($0, RLENGTH+1); } }' | while read bib; do
    if [ "$bib" -nt "$aux" ]; then
      rm "$idx" "$aux" "$blg" "$bbl" "$pdf";
      break;
    fi
  done
fi

# some flags to help us determine when to run or not run
ranbibtex=0; rerun=1;


if [ -n "$TM_LATEX_CLEAN_FIRST" ];then
  info 'Cleaning';
  seperator;
  latexmk -CA;
fi

# this is the main compile loop.
# we always start by running 

for i in `jot 4`; do # we never need more than five iterations.
  
  # check if we are done compiling.
  if [ $rerun -eq 0 ]; then break; else rerun=0; fi

  if [ $i -gt 1 ]; then seperator; fi
  
  # get index/citation hashes so we can notice if they change.
  if [ -e "$idx" ]; then idxhash=$(md5 -q "$idx"); fi
  if [ -e "$aux" ]; then bibhash=$(egrep '^\\bib' "$aux" | md5 -q); fi
  
  info "Typesetting $(basename "$document")";
  
  # run latex and watch the output for lines that tell us to run again.
  perform_command $engine $flags \
                   -jobname='"$jobname"' \
                   -synctex='"$synctex"' \
                   '"$document"' \
    | awk '{print $0;} /Rerun/ { r=1 } END{ exit r  }';

  rc=(${PIPESTATUS[@]}); rerun=${rc[1]};

  if [ ${rc[0]} -ne 0 ]; then exit ${rc[0]}; fi
  
  # run makeindex if the idx changed.
  if [[ -e "$idx" && $idxhash != $(md5 -q "$idx") ]]; then
    seperator;
    info 'Making index';
    makeindex "$idx";
    rerun=1;
  fi
  
  
  
  if [[ -z "$ranbib" && "$bibhash" != $(egrep '^\\bib' "$aux" | md5 -q) ]];
    then
    
    seperator;
    info 'Compiling bibliography';
    perform_command bibtex "$TM_BIBTEX_FLAGS" '"$aux"';
    
    ranbib=1; rerun=1;
  fi

done

mv "$pdf" "$basename.pdf"
