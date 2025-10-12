#!/bin/bash

first_script="./first_script.sh"
total_tests=0
passed_tests=0
failed_tests=0

create_virtual_disk() {
    local disk_name="$1"
    local size_mb="$2"
    dd if=/dev/zero of="$disk_name" bs=1M count="$size_mb" status=none
    mkfs.ext4 -q "$disk_name"
    mkdir -p /mnt/test_disk
    mount -o loop "$disk_name" /mnt/test_disk
}

fill_disk_with_files() {
    local target_percent="$1"
    local test_dir="/mnt/test_disk/test_data"
    mkdir -p "$test_dir"
    
    local total_kb=$(df /mnt/test_disk --block-size=1K --output=size | awk 'NR==2')
    local available_kb=$(df /mnt/test_disk --block-size=1K --output=avail | awk 'NR==2')
    local target_used_kb=$((total_kb * target_percent / 100))
    local current_used_kb=$((total_kb - available_kb))
    
    while [ $current_used_kb -lt $target_used_kb ]; do
        dd if=/dev/urandom of="$test_dir/file_$RANDOM.dat" bs=1K count=$((RANDOM % 500 + 1)) status=none 2>/dev/null
        available_kb=$(df /mnt/test_disk --block-size=1K --output=avail | awk 'NR==2')
        current_used_kb=$((total_kb - available_kb))
    done
}

cleanup() {
    local disk_name="$1"
    umount /mnt/test_disk 2>/dev/null
    rm -f "$disk_name"
    rmdir /mnt/test_disk 2>/dev/null
    rm -rf "/mnt/test_disk_backup" "/tmp/custom_backup_test"
}

run_test() {
    local disk_size="$1"
    local initial_fill="$2"
    local disk_name="test_disk_$((++total_tests)).img"
    
    create_virtual_disk "$disk_name" "$disk_size"
    fill_disk_with_files "$initial_fill"
    
    if "$first_script" --fill-limit=70 --free-upto=60 /mnt/test_disk 2>/dev/null; then
        local final_fill=$(df /mnt/test_disk --output=pcent | awk 'NR==2' | sed 's/%//')
        if [ "$final_fill" -le 60 ] && [ -d "/mnt/test_disk_backup" ]; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    else
        ((failed_tests++))
    fi
    
    cleanup "$disk_name"
}

if [ ! -f "$first_script" ]; then
    exit 1
fi

chmod +x "$first_script"

run_test 200 80

run_test 150 75

run_test 180 90

disk_name="test_disk_below_limit.img"
create_virtual_disk "$disk_name" 120
fill_disk_with_files 50

if "$first_script" --fill-limit=70 --free-upto=60 /mnt/test_disk 2>/dev/null; then
    local final_fill=$(df /mnt/test_disk --output=pcent | awk 'NR==2' | sed 's/%//')
    if [ "$final_fill" -eq 50 ] && [ ! -d "/mnt/test_disk_backup" ]; then
        ((passed_tests++))
    else
        ((failed_tests++))
    fi
else
    ((failed_tests++))
fi

cleanup "$disk_name"
((total_tests++))

disk_name="test_disk_custom.img"
create_virtual_disk "$disk_name" 160
fill_disk_with_files 80

mkdir -p "/tmp/custom_backup_test"
if "$first_script" --fill-limit=70 --free-upto=60 --arq-path="/tmp/custom_backup_test" /mnt/test_disk 2>/dev/null; then
    if [ -d "/tmp/custom_backup_test" ] && [ "$(ls -A /tmp/custom_backup_test)" ]; then
        ((passed_tests++))
    else 
        ((failed_tests++))
    fi
else
    ((failed_tests++))
fi

cleanup "$disk_name"
((total_tests++))

[ $failed_tests -eq 0 ] && exit 0 || exit 1
