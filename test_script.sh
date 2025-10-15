#!/bin/bash

arq="./arq.sh"
if [ ! -f $arq ]; then
    echo "Please put "arq.sh" in same directory with the test"
    exit 1
fi
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
    local lost_found_size=$(du -s -B1 "$PWD/test_disk/lost+found" | awk '{print $1}')
    local available_kb=$(df "$PWD/test_disk" --block-size=1K --output=avail | awk 'NR==2')
    available_kb=$((available_kb+lost_found_size))
    local target_used_kb=$((total_kb * target_percent / 100))
    local current_used_kb=$((total_kb - available_kb))

    while [ $current_used_kb -le $target_used_kb ]; do
        dd if=/dev/zero of="$test_dir/file_$RANDOM.dat" bs=1M count=$((RANDOM % 15 + 1)) status=none 2>/dev/null
        available_kb=$(df "$PWD/test_disk" --block-size=1K --output=avail | awk 'NR==2')
        available_kb=$((available_kb+lost_found_size))
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
    local fill_limit="$3"
    local free_upto="$4"
    local custom_arq_path="$5"
    local disk_name="test_disk_$((++total_tests)).img"

    echo "   Running test #$((total_tests))"
    echo "     Disk size = ${disk_size}M"
    echo "     Filled to ${initial_fill}+%"
    echo "     Fill limit ${fill_limit}%"
    echo "     Free upto ${free_upto}%"
    echo ""

    create_virtual_disk "$disk_name" "$disk_size"
    fill_disk_with_files "$initial_fill"
    if [ $custom_arq_path -eq 0 ]; then
        if "$arq" --fill-limit "$fill_limit" --free-upto "$free_upto" "$PWD/test_disk" 2>/dev/null; then
            local size=$(df "$PWD/test_disk" --output=size | awk "NR==2")
            local lost_found_size=$(du -s -B1 "$PWD/test_disk/lost+found" | awk '{print $1}')
            local final_avail=$(df "$PWD/test_disk" --output=avail | awk "NR==2")
            final_avail=$((final_avail+lost_found_size))
            local final_fill=$(((size-final_avail)*100/size))
            if [ "$final_fill" -le "$free_upto" ] && [ -d "$PWD/test_disk_backup" ]; then
                ((passed_tests++))
                echo "   Test #$total_tests PASSED"
            else
                if [ $initial_fill -lt $fill_limit ]; then
                    ((passed_tests++))
                    echo "   Test #$total_tests PASSED"
                else
                    ((failed_tests++))
                    echo "   Test #$total_tests FAILED"
                fi
            fi
        else
            ((failed_tests++))
            echo "   Test #$total_tests FAILED"
        fi
        echo ""
    else
        mkdir -p /tmp/custom_backup_test
        if "$arq" --fill-limit "$fill_limit" --free-upto "$free_upto" --arq-path "/tmp/custom_backup_test" "$PWD/test_disk" 2>/dev/null; then
            local size=$(df "$PWD/test_disk" --output=size | awk "NR==2")
            local lost_found_size=$(du -s -B1 "$PWD/test_disk/lost+found" | awk '{print $1}')
            local final_avail=$(df "$PWD/test_disk" --output=avail | awk "NR==2")
            final_avail=$((final_avail+lost_found_size))
            local final_fill=$(((size-final_avail)*100/size))
            if [ "$final_fill" -le "$free_upto" ] && [ -d "/tmp/custom_backup_test" ]; then
                ((passed_tests++))
                echo "   Test #$total_tests PASSED"
            else
                if [ $initial_fill -lt $fill_limit ]; then
                    ((passed_tests++))
                    echo "   Test #$total_tests PASSED"
                else
                    ((failed_tests++))
                    echo "   Test #$total_tests FAILED"
                fi
            fi
        fi
        echo ""
    fi
    # read -p "Press Enter to continue..."
    cleanup "$disk_name"
}

if [ ! -f "$arq" ]; then
    exit 1
fi

chmod +x "$arq"

    #run_test [disk_size] [initial_fill] [fill_limit] [free_upto] [custom_arq_path]
run_test "$((RANDOM % 300 + 500))" 55 50 5 1
run_test "$((RANDOM % 300 + 500))" 90 70 30 0
run_test "$((RANDOM % 300 + 500))" 75 70 60 0
run_test "$((RANDOM % 300 + 500))" 85 70 60 0
run_test "$((RANDOM % 300 + 500))" 50 60 20 0

echo " Total tests = $total_tests"
echo " Passed tests = $passed_tests"
echo " Failed tests = $failed_tests"
[ $failed_tests -eq 0 ] && exit 0 || exit 1
