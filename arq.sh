#!/bin/bash
long_options="fill-limit:,free-upto:,arq-path:,help"
options="l:,u:,a:,h"
ARGS=$(getopt -o $options -l $long_options -n $0 -- $@)

declare -i fill_limit=70
declare -i free_upto
declare -i lost_found_size=0
declare dir_path
declare arq_path
declare folder_name
free_upto_default=true
arq_path_default=true
do_exit=false

eval set -- "$ARGS"

while true; do
   case "$1" in
     -h|--help)
       echo "Usage: arq [OPTION]... [DIRECTORY]...                                           "
       echo "Archieves files that have not been updated for a long time                      "
       echo "Do not work recursive, only files in specified directory                        "
       echo "                                                                                "
       echo "List of possible arguments:                                                     "
       echo "   -l, --fill-limit=PERCENTS             set directory fill limit to X percents "
       echo "                                           default = 70                         "
       echo "   -u, --free-upto=PERCENTS              set directory filled space after       "
       echo "                                         archieving to X percents               "
       echo "                                           default value = fill-limit           "
       echo "   -a, --arq-path=/path/to/directory/    set custom path to archieving directory"
       echo "                                           default is PARENT DIRECTORY          "
       echo "   -h, --help              display this help and exit                           "
     exit 1
       ;;
     -l|--fill-limit)
       fill_limit=$2
       if [ $fill_limit -lt 1 -o $fill_limit -gt 99 ]; then
          echo " -l|--fill-limit: Fill limit must be in interval (0; 100)" >&2
          do_exit=true
       fi
       shift 2
       ;;
     -u|--free-upto)
       free_upto=$2
       if [ $free_upto -lt 1 -o $free_upto -gt 99 ]; then
          echo " -u|--free-upto: Free upto must be in interval (0; 100)" >&2
          do_exit=true
       fi
       free_upto_default=false
       shift 2
       ;;
     -a|--arq-path)
       if [ -d "$2" ]; then
          arq_path_default=false
          arq_path="$2"
       else
          echo " -a|--arq-path: Path do not exists or not a directory" >&2
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
   echo " -u|--free-upto option can't be greater than -l|--fill-limit option" >&2
   do_exit=true
fi
if [ -d "$1" ]; then
   dir_path="$1"
   folder_name="${dir_path%/}"
   folder_name="${folder_name##*/}"
   if [ "$arq_path_default" = true ]; then
      arq_path="$(dirname "$dir_path")/${folder_name}_backup"
      mkdir -p "$arq_path"
   fi
else
   echo " Path do not exists or not a directory" >&2
   do_exit=true
fi

if [ "$do_exit" = true ]; then
   exit 1
fi

if [ -e "${dir_path%/}/lost+found" ]; then
   lost_found_size=$(du -s -B1 "${dir_path%/}/lost+found" | awk '{print $1}')
fi
size=$(df $dir_path --block-size=1K --output=size | awk "NR==2")
size="${size:2}"
avail_space=$(df $dir_path --block-size=1K --output=avail | awk "NR==2")
avail_space=$((avail_space+lost_found_size))
fill_pcent=$(((size-avail_space)*100/size))
echo "Fill percentage is $fill_pcent%"

readarray -t files < <(ls -prts1 --ignore="lost+found" "$dir_path" | grep -v / | awk '{print $1, $2}')
files=("${files[@]:1}")

if [ $fill_pcent -lt $fill_limit ]; then
   echo "Fill percentage is under $fill_limit%, there are nothing to archieve"
   exit 0
fi

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
   tar -czvf "${arq_path}/backup_$(date +"%d-%m-%Y-%H%M%S").tar.gz" --files-from <(printf "${dir_path}/%s\n" "${file_to_arq[@]}" >/dev/null) 2>/dev/null
   echo " Files are archieving to ${arq_path}:"
   echo "Files:"
   for file in ${file_to_arq[@]}; do
      rm -f "${dir_path}/${file}"
      echo "${file}"
   done
   echo "archived and removed from $dir_path"
   echo "Fill percentage after archieving is $(((size-avail_space)*100/size))%"
fi

exit 0
