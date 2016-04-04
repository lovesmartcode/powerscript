# parse args
date=$(date +%Y%m%d%H%M%S)
rand=$(cat /dev/urandom | tr -cd [:alnum:] | head -c 4)
ID=$date"_"$rand
includefuncs=""
requires=""
tmpfile="/tmp/.$(whoami).powscript.$date_$rand"
shopt -s extglob

input="$1"
[[ ! -n $startfunction ]] && startfunction=runfile

for arg in "$@"; do
  case "$arg" in
    --compile) 
      startfunction=compile
      shift
      ;;
  esac
done

empty "$1" && {
  echo 'Usage:
     powscript <file.powscript>
     powscript --compile <file.powscript>
  ';
}

transpile_sugar(){
  while IFS="" read -r line; do 
    stack_update "$line"
    [[ "$line" =~ ^(require )                           ]] && continue 
    [[ "$line" =~ (\$[a-zA-Z_0-9]*\[)                   ]] && transpile_array_get "$line"                  && continue
    [[ "$line" =~ ^([ ]*for )                           ]] && transpile_for "$line"                        && continue
    [[ "$line" =~ ^([  ]*when done)                     ]] && transpile_when_done "$line"                  && continue
    [[ "$line" =~ (await .* then foreachline)               ]] && transpile_then "$line" "pl" "pipe_each_line" && continue
    [[ "$line" =~ (await .* then \|)                        ]] && transpile_then "$line" "p"  "pipe"           && continue
    [[ "$line" =~ (await .* then)                           ]] && transpile_then "$line"                       && continue
    [[ "$line" =~ ^([ ]*if )                            ]] && transpile_if  "$line"                        && continue
    [[ "$line" =~ ^([ ]*switch )                        ]] && transpile_switch "$line"                     && continue
    [[ "$line" =~ ^([ ]*case )                          ]] && transpile_case "$line"                       && continue
    [[ "$line" =~ ([a-zA-Z_0-9]\+=)                     ]] && transpile_array_push "$line"                 && continue
    [[ "$line" =~ ^([a-zA-Z_0-9]*\([a-zA-Z_0-9, ]*\))   ]] && transpile_function "$line"                   && continue
    echo "$line" | transpile_all
  done <  $1
  stack_update ""
}

cat_requires(){
  while IFS="" read -r line; do 
    [[ "$line" =~ ^(require ) ]] && {                                               # include require-calls
      local file="${line//*require /}"; file="${file//[\"\']/}"
      echo -e "#\n# $line (included by powscript\n#\n"
      cat "$file";
    };
  done <  $1
  echo "" 
}

transpile_functions(){
  # *FIXME* this is bruteforce: if functionname is mentioned in textfile, include it
  while IFS="" read -r line; do 
    regex="((^|[ ])${powfunctions// /[ ]|(^|[ ])})"                                                  # include powscript-functions
    echo "$line" | grep -qE "$regex" && {
      for func in $powfunctions; do
        if [[ "$line" =~ ([ ]?$func[ ]) ]]; then 
          includefuncs="$includefuncs $func"; 
        fi
      done;
    }
  done <  $1
  [[ ! ${#includefuncs} == 0 ]] && echo -e "#\n# generated by powscript (https://github.com/coderofsalvation/powscript)\n#\n"
  for func in $includefuncs; do 
    declare -f $func; echo ""; 
  done
}

compile(){
  local dir="$(dirname "$1")"; local file="$(basename "$1")"; cd "$dir" &>/dev/null
  { cat_requires "$file" ; echo -e "#\n# application code\n#\n"; cat "$file"; } > $tmpfile
  #transpile_functions "$tmpfile"
  transpile_sugar "$tmpfile" | grep -v "^#" > $tmpfile.code
  transpile_functions $tmpfile.code
  cat $tmpfile.code
  for i in ${!footer[@]}; do echo "${footer[$i]}"; done 
  rm $tmpfile
}

runfile(){
  file=$1; shift;
  eval "$(compile "$file")"
}

$startfunction "$@" #"${0//.*\./}"
