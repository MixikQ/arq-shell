#!/bin/bash
long_options="fill-limit:,free-upto:,arq-path:,help"
options="l:,u:,a:,h"
ARGS=$(getopt -o $options -l $long_options -n $0 -- $@)

declare -i fill_limit=70
declare -i free_upto
free_upto_default=true
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
       free_upto_default=false
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

if [ "$free_upto_default" = true ]; then
   free_upto=fill_limit
fi
if [ $free_upto -gt $fill_limit ]; then
   echo " -u|--free-upto option can't be greater than -l|--fill-limit option"
   do_exit=true
fi
if [ -d "$1" ]; then
   dir_path="$1"
   if [ "$arq_path_default" = true ]; then
      arq_path="${dir_path}_backup"
      mkdir -p "$arq_path"
   fi
else
   echo " Path do not exists or not a directory"
   do_exit=true
fi

if [ "$do_exit" = true ]; then
   exit 1
fi

size=$(df $dir_path --block-size=1K --output=size | awk "NR==2")
size="${size:2}"
avail_space=$(df $dir_path --block-size=1K --output=avail | awk "NR==2")
fill_pcent=$(df $dir_path --output=pcent | awk "NR==2")
fill_pcent="${fill_pcent%\%}"

readarray -t files < <(ls -prts1 --ignore="lost+found" "$dir_path" | grep -v / | awk '{print $1, $2}')
files=("${files[@]:1}")

declare -a file_to_arq
declare -i temp
free_space_target=$((size*(100-free_upto)/100))
while [ $avail_space -lt $free_space_target ]
do
   temp=$(echo "${files[0]}" | awk '{print $1}')
   avail_space=$(($avail_space+$temp))
   file_to_arq+=($(echo "${files[0]}" | awk '{print $2}'))
   files=("${files[@]:1}")
done

if [ ${#file_to_arq[@]} -gt 0 ]; then
   tar -czvf "${arq_path}/backup_$(date +"%d-%m-%Y-%H%M%S").tar.gz" --files-from <(printf "${dir_path}/%s\n" "${file_to_arq[@]}")
   for file in ${file_to_arq[@]}; do
      rm "${dir_path}/${file}"
      echo "${dir_path}/${file} removed"
   done
fi

