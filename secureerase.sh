#!/bin/bash

if [[ "$EUID" -ne 0 ]];then
    echo "This script requires root privileges. Re running with sudo."
    sudo "$0" "$@"
    exit $?
fi

disk=""
final_pass=""
random_passes=3
args=("$@")
argc=${#args[@]}

for ((i=0;i<argc;i++)); do
    arg="${args[i]}"
    if [[ "$arg" == "-z" || "$arg" == "--zero-disk" ]];then
        final_pass="z"
    elif [[ "$arg" == "-r" || "$arg" == "--randomize-disk" ]];then
        final_pass="r"
    elif [[ "$arg" = "-p" || "$arg" == "--passes" ]];then
        if (($i + 1 < $argc)) && [[ "${args[i+1]}" =~ ^[0-9]+$ ]];then
            random_passes="${args[i+1]}"
        else
            echo "Error: --passes must be followed by number of passes."
            exit 2
        fi
    elif [[ -b "$arg" ]];then
        disk="$arg"
    fi
done

if [ -z "$disk" ] || [ ! -b "$disk" ];then
    echo "Usage: $0 /dev/sdX [-z | -r | --zero-disk | --randomize-disk ]"
    echo "Replace /dev/sdX with the target device you wish to erase e.g. /dev/sdb"
    echo "  -r --randomize-disk: Perform a final pass of random data to the disk in a final pass"
    echo "                       to prepare the disk for encryption and ensure data boundaries will be harder to detect etc."
    echo "  -z --zero-disk:      Perform a final pass of zeroes to the disk, equivalent of low-level fomatting it."
    echo "  -p --passes <number>: Number of random passes for extra security (default is 1)."
    exit 1;
fi;

# Determine the optimal block size
block_size=$(cat /sys/block/$(basename "$disk")/queue/optimal_io_size)
if [ "$block_size" -eq 0 ]; then
    # Fallback if optimal_io_size is not set
    block_size=$(cat /sys/block/$(basename "$disk")/queue/physical_block_size)
fi

# Set a default if still zero or use a reasonable default like 1M
if [ "$block_size" -eq 0 ]; then
    block_size=$((1024 * 1024)) # 1 MiB
else
    block_size=$((block_size * 2 * 1024))
fi

echo "Using block size: $block_size bytes"

read -p "This will erase all data on $disk. Are you sure you want to continue? (y/N) " confirm
if [[ "$confirm" != "y" ]];then
    echo "Aborted"
    exit 3;
fi

device_size=$(blockdev --getsize64 "$disk")
if [[ $? -ne 0 ]];then
    echo "Failed to get size of $disk"
    exit 4;
fi

total_passes=$((random_passes + 2))

if [[ -n $final_pass ]];then
    ((total_passes++))
fi

total_bytes=$((total_passes * device_size))

# Function to convert bytes to human-readable format
bytes_to_human() {
    local bytes=$1
    local unit="B"
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes} ${unit}"
    elif [ "$bytes" -lt $((1024 * 1024)) ]; then
        echo "$(awk "BEGIN{printf \"%.2f\", $bytes/1024}") KiB"
    elif [ "$bytes" -lt $((1024 * 1024 * 1024)) ]; then
        echo "$(awk "BEGIN{printf \"%.2f\", $bytes/(1024*1024)}") MiB"
    elif [ "$bytes" -lt $((1024 * 1024 * 1024 * 1024)) ]; then
        echo "$(awk "BEGIN{printf \"%.2f\", $bytes/(1024*1024*1024)}") GiB"
    else
        echo "$(awk "BEGIN{printf \"%.2f\", $bytes/(1024*1024*1024*1024)}") TiB"
    fi
}

hrb=$(bytes_to_human "$total_bytes")
echo "This will write a total of $hrb over $total_passes passes"

pv -tpreb -s "$device_size" -N "Pass 1 zeroes" --sync /dev/zero | dd of="$disk" bs="$block_size" oflag=direct status=none conv=fsync 2>/dev/null

pass=2
for ((i=1; i<= random_passes;i++));do
    pv -tpreb -s "$device_size" -N "Pass $pass random" --sync /dev/urandom | dd of="$disk" bs="$block_size" oflag=direct status=none conv=fsync 2>/dev/null
    ((pass++))
done

pv -tpreb -s "$device_size" -N "Pass $pass ones" --sync /dev/zero | tr '\0' '\377' | dd of="$disk" bs="$block_size" oflag=direct status=none conv=fsync 2>/dev/null
((pass++))

if [[ "$final_pass" == "z" ]];then
    pv -tpreb -s "$device_size" -N "Pass $pass zeroes" --sync /dev/zero | dd of="$disk" bs="$block_size" oflag=direct status=none conv=fsync 2>/dev/null
fi

if [[ "$final_pass" == "r" ]];then
    pv -tpreb -s "$device_size" -N "Pass $pass random" --sync /dev/urandom | dd of="$disk" bs="$block_size" oflag=direct status=none conv=fsync 2>/dev/null
fi

echo "Erase $disk is now complete. "
