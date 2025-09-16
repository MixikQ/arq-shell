#!/bin/bash
long_options="fill-limit:,free-upto:,arq-path:,help"
options="l:,u:,a:,h"
ARGS=$(getopt -o $options -l $long_options -n $0 -- $@)

declare -i fill_limit=70
declare -i free_upto=30
#dir_path_default=true
arq_path_default=true
do_exit=false

eval set -- "$ARGS"

while true; do
   case "$1" in
     -h|--help)
       echo "Help is out"
       exit 1
       ;;
     -l|--fill-limit)
       fill_limit=$2
       shift 2
       ;;
     -u|--free-upto)
       free_upto=$2
       shift 2
       ;;
     -a|--arq-path)
       if [ -d "$2" ]; then
          arq_path_default=false
          arq_path="$2"
       else
          echo " -a|--arq-path: Path do not exists or not a directory"
          do_exit=true
       fi
       shift 2
       ;;
     --)
       shift
       break
       ;;
     *)
       echo "Internl error" >&2
       exit 1
       ;;
   esac
done

if [ $free_upto -gt $fill_limit ]; then
   echo " -u|--free-upto option can't be greater than -l|--fill-limit option"
   do_exit=true
fi
if [ -d "$1" ]; then
   dir_path="$1"
   if [ "$arq_path_default" = true ]; then
      arq_path="${dir_path}_backup"
   fi
else
   echo " Path do not exists or not a directory"
   do_exit=true
fi

if [ "$do_exit" = true ]; then
   exit 1
fi


size=$(df $folder_path --output=pcent | awk "NR==2 {print $1}")
size="${size%\%}"

echo "fill_limit = $fill_limit"
echo "free_upto = $free_upto"
echo "dir_path = $dir_path"
echo "arq_path = $arq_path"
