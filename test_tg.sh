#!/bin/bash
source .env
TARGET_DEVICE="thyme"
SCRIPT_START_TIME=$(date +%s)
MAIN_PID=$$

text="Dang build kernel : thyme\nMang: Download :0KB/s / Upload :0KB/s\nCPU: CPU0= 0%\nThoi gian da build : 00:00:00"

json_payload=$(cat <<JSON
{
    "chat_id": "$TG_CHAT_ID",
    "text": "$text",
    "reply_markup": {
        "inline_keyboard": [[
            {"text": "❌ Hủy Build Nhanh", "callback_data": "cancel_build"}
        ]]
    }
}
JSON
)

res=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$json_payload")
TG_MSG_ID=$(echo "$res" | grep -o '"message_id":[0-9]*' | head -n1 | cut -d':' -f2)
export TG_MSG_ID

echo "Message sent. ID: $TG_MSG_ID"

if [ -n "$TG_MSG_ID" ]; then
    (
        local last_update_id=""
        local res=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=-1")
        if echo "$res" | grep -q '"update_id":'; then
            last_update_id=$(echo "$res" | grep -o '"update_id":[0-9]*' | cut -d':' -f2 | tail -n1)
        fi

        get_network() { awk 'NR>2{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev; }
        get_cpu() { awk '/^cpu[0-9]/{print $1, $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat; }
        
        read rx1 tx1 < <(get_network)
        cpu1=$(get_cpu)

        for i in {1..15}; do
            sleep 1
            
            read rx2 tx2 < <(get_network)
            cpu2=$(get_cpu)
            down=$(( (rx2 - rx1) / 1024 ))
            up=$(( (tx2 - tx1) / 1024 ))
            rx1=$rx2
            tx1=$tx2
            
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
            cpu1=$cpu2
            cpu_text=${cpu_text%,}
            
            elapsed=$(( $(date +%s) - SCRIPT_START_TIME ))
            hh_mm_ss=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(( (elapsed/60)%60 )) $((elapsed%60)))
            
            msg_text="Dang build kernel : ${TARGET_DEVICE}\nMang: Download :${down}KB/s / Upload :${up}KB/s\n${cpu_text}\nThoi gian da build : ${hh_mm_ss}"
            
            local json_payload=$(cat <<JSON2
{
    "chat_id": "$TG_CHAT_ID",
    "message_id": "$TG_MSG_ID",
    "text": "$msg_text",
    "reply_markup": {
        "inline_keyboard": [[
            {"text": "❌ Hủy Build Nhanh", "callback_data": "cancel_build"}
        ]]
    }
}
JSON2
)
            curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
                -H "Content-Type: application/json" \
                -d "$json_payload" > /dev/null &
        done
    ) &
    POLLER_PID=$!
    wait $POLLER_PID
fi
