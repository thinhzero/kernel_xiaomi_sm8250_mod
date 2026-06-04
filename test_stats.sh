#!/bin/bash
get_network() {
    awk 'NR>2{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev
}
get_cpu() {
    awk '/^cpu[0-9]/{print $1, $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat
}

read rx1 tx1 < <(get_network)
cpu1=$(get_cpu)
sleep 1
read rx2 tx2 < <(get_network)
cpu2=$(get_cpu)

down=$(( (rx2 - rx1) / 1024 ))
up=$(( (tx2 - tx1) / 1024 ))

echo "Mang: Download :${down}KB/s / Upload :${up}KB/s"

cpu_text="CPU:"
while read -r c1 t1 i1 && read -r c2 t2 i2 <&3; do
    dt=$((t2 - t1))
    di=$((i2 - i1))
    if [ $dt -ne 0 ]; then
        usage=$(( 100 * (dt - di) / dt ))
    else
        usage=0
    fi
    cpu_text+=" ${c1^^}= ${usage}%,"
done <<< "$cpu1" 3<<< "$cpu2"

echo "${cpu_text%,}"
