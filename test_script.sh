#!/bin/bash

first_script="./arq.sh"
total_tests=0
passed_tests=0
failed_tests=0

create_virtual_disk() {
    local disk_name="$1"
    local size_mb="$2"
    dd if=/dev/zero of="$disk_name" bs=1M count="$size_mb" status=none
    mkfs.ext4 -q "$disk_name"
    mkdir -p "$PWD/test_disk"
    guestmount -a "$disk_name" -m /dev/sda --rw "$PWD/test_disk"
}

fill_disk_with_files() {
    local target_percent="$1"
    local test_dir="$PWD/test_disk"
    mkdir -p "$test_dir"

    local total_kb=$(df "$PWD/test_disk" --block-size=1K --output=size | awk 'NR==2')
    local available_kb=$(df "$PWD/test_disk" --block-size=1K --output=avail | awk 'NR==2')
    local target_used_kb=$((total_kb * target_percent / 100))
    local current_used_kb=$((total_kb - available_kb))

    while [ $current_used_kb -lt $target_used_kb ]; do
        dd if=/dev/urandom of="$test_dir/file_$RANDOM.dat" bs=1M count=$((RANDOM % 10 + 1)) status=none 2>/dev/null
        available_kb=$(df "$PWD/test_disk" --block-size=1K --output=avail | awk 'NR==2')
        current_used_kb=$((total_kb - available_kb))
    done
}

cleanup() {
    local disk_name="$1"
    guestunmount "$PWD/test_disk" 2>/dev/null
    rm -f "$disk_name"
    rmdir "$PWD/test_disk" 2>/dev/null
    rm -rf "$PWD/test_disk_backup" "/tmp/custom_backup_test"
}

run_test() {
    local disk_size="$1"
    local initial_fill="$2"
    local disk_name="test_disk_$((++total_tests)).img"

    echo "   Running test #$((total_tests))"
    echo "     Disk size = ${disk_size}M"
    echo "     Filled to ${initial_fill}+%"
    echo "     Free upto 60%"
    echo ""

    create_virtual_disk "$disk_name" "$disk_size"
    fill_disk_with_files "$initial_fill"

    if "$first_script" --fill-limit 70 --free-upto 60 "$PWD/test_disk" 2>/dev/null; then
        local size=$(df "$PWD/test_disk" --output=size | awk "NR==2")
        local lost_found_size=$(du -s -B1 "$PWD/test_disk/lost+found" | awk '{print $1}')
        local final_avail=$(df "$PWD/test_disk" --output=avail | awk "NR==2")
        final_avail=$((final_avail+lost_found_size))
        local final_fill=$(((size-final_avail)*100/size))
        if [ "$final_fill" -le 60 ] && [ -d "$PWD/test_disk_backup" ]; then
            ((passed_tests++))
            echo "   Test #$total_tests PASSED"
        else
            ((failed_tests++))
            echo "   Test #$total_tests FAILED"
        fi
    else
        ((failed_tests++))
        echo "   Test #$total_tests FAILED"
    fi
    echo ""

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

echo "   Running test #$((total_tests+1))"
echo "     Disk size = 120M"
echo "     Filled to 50+%"
echo "     Free upto 60%"

if "$first_script" --fill-limit 70 --free-upto 60 "$PWD/test_disk" 2>/dev/null; then
    size=$(df "$PWD/test_disk" --output=size | awk "NR==2")
    lost_found_size=$(du -s -B1 "$PWD/test_disk/lost+found" | awk '{print $1}')
    final_avail=$(df "$PWD/test_disk" --output=avail | awk "NR==2")
    final_avail=$((final_avail+lost_found_size))
    final_fill=$(((size-final_avail)*100/size))
    if [ "$final_fill" -eq 50 ] && [ ! -d "$PWD/test_disk_backup" ]; then
        ((passed_tests++))
        echo "   Test #$((total_tests+1)) PASSED"
    else
        ((failed_tests++))
        echo "   Test #$((total_tests+1)) FAILED"
    fi
else
    ((failed_tests++))
    echo "   Test #$((total_tests+1)) FAILED"
fi
echo ""

cleanup "$disk_name"
((total_tests++))

disk_name="test_disk_custom.img"
create_virtual_disk "$disk_name" 160
fill_disk_with_files 80

echo "   Running test #$((total_tests+1))"
echo "     Disk size = 160M"
echo "     Filled to 80+%"
echo "     Free upto 60%"

mkdir -p "/tmp/custom_backup_test"
if "$first_script" --fill-limit 70 --free-upto 60 --arq-path "/tmp/custom_backup_test" "$PWD/test_disk" 2>/dev/null; then
    if [ -d "/tmp/custom_backup_test" ] && [ "$(ls -A /tmp/custom_backup_test)" ]; then
        ((passed_tests++))
        echo "   Test #$((total_tests+1)) PASSED"
    else
        ((failed_tests++))
        echo "   Test #$((total_tests+1)) FAILED "
    fi
else
    ((failed_tests++))
    echo "   Test #$((total_tests+1)) FAILED "
fi
echo""

cleanup "$disk_name"
((total_tests++))

echo " Total tests = $total_tests"
echo " Failed tests = $failed_tests"
echo " Passed tests = $passed_tests"
[ $failed_tests -eq 0 ] && exit 0 || exit 1
