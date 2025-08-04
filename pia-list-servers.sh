#!/bin/bash

# PIA VPN List Servers Script
# Lists available PIA servers with various filtering and display options

set -euo pipefail

# Get the script directory and load libraries
# Handle both direct execution and symlinked execution
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}")")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/servers.sh"

# Help function
show_help() {
    cat << EOF
PIA VPN List Servers Script

Usage: $0 [OPTIONS] [FILTER]

List available PIA servers with filtering and sorting options.

Arguments:
  FILTER         Optional filter pattern to match server names or countries

Options:
  -h, --help     Show this help message
  -c, --country  List servers grouped by country
  -f, --fastest  Test and show fastest servers (this may take time)
  -n, --names    Show only server names (one per line)
  -t, --test     Test connectivity to all servers
  -v, --verbose  Show detailed server information
  -j, --json     Output in JSON format
  --count NUM    Limit results to NUM servers (default: all)

Display Options:
  -s, --sort FIELD   Sort by field: name, country, latency (requires --test)
  --reverse          Reverse sort order

Examples:
  $0                        # List all servers
  $0 --country              # Group servers by country  
  $0 --fastest              # Show fastest servers
  $0 --names us_            # Show only US server names
  $0 --test --count 10      # Test top 10 servers
  $0 --json                 # JSON output for automation
  $0 UK                     # Show servers matching "UK"

EOF
}

# Parse command line arguments
GROUP_BY_COUNTRY=false
SHOW_FASTEST=false
NAMES_ONLY=false
TEST_CONNECTIVITY=false
VERBOSE=false
JSON_OUTPUT=false
COUNT_LIMIT=""
SORT_FIELD=""
REVERSE_SORT=false
FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--country)
            GROUP_BY_COUNTRY=true
            shift
            ;;
        -f|--fastest)
            SHOW_FASTEST=true
            shift
            ;;
        -n|--names)
            NAMES_ONLY=true
            shift
            ;;
        -t|--test)
            TEST_CONNECTIVITY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        --count)
            if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                COUNT_LIMIT="$2"
                shift 2
            else
                echo "ERROR: --count requires a number" >&2
                exit 1
            fi
            ;;
        -s|--sort)
            if [[ -n "${2:-}" ]]; then
                SORT_FIELD="$2"
                shift 2
            else
                echo "ERROR: --sort requires a field name" >&2
                exit 1
            fi
            ;;
        --reverse)
            REVERSE_SORT=true
            shift
            ;;
        -*)
            echo "ERROR: Unknown option $1" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$FILTER" ]]; then
                FILTER="$1"
            else
                echo "ERROR: Multiple filters provided" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Initialize (don't require root for listing)
load_env || true
load_servers

# Get server list
if [[ -n "$FILTER" ]]; then
    servers=($(search_servers "$FILTER"))
    if [[ ${#servers[@]} -eq 0 ]]; then
        echo "No servers found matching: $FILTER" >&2
        exit 1
    fi
else
    servers=($(list_all_servers))
fi

# Apply count limit
if [[ -n "$COUNT_LIMIT" ]] && [[ ${#servers[@]} -gt $COUNT_LIMIT ]]; then
    servers=("${servers[@]:0:$COUNT_LIMIT}")
fi

# Fastest servers mode
if [[ "$SHOW_FASTEST" == "true" ]]; then
    echo "Testing server connectivity (this may take a moment)..." >&2
    fastest_output=$(find_fastest_servers "${COUNT_LIMIT:-10}")
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "["
        first=true
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                server=$(echo "$line" | awk '{print $1}')
                latency=$(echo "$line" | grep -o '[0-9.]*ms' | sed 's/ms//')
                display_name=$(get_server_display_name "$server")
                hostname=$(get_server_hostname "$server")
                
                [[ "$first" == "false" ]] && echo ","
                cat << EOF
  {
    "name": "$server",
    "display_name": "$display_name", 
    "hostname": "$hostname",
    "latency_ms": $latency
  }
EOF
                first=false
            fi
        done <<< "$fastest_output"
        echo "]"
    else
        echo "Fastest PIA Servers:"
        echo "$fastest_output"
    fi
    exit 0
fi

# JSON output
if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "["
    first=true
    
    for server in "${servers[@]}"; do
        server_info=$(get_server_info "$server")
        IFS='|' read -r name display hostname country region <<< "$server_info"
        
        latency=""
        if [[ "$TEST_CONNECTIVITY" == "true" ]]; then
            latency=$(test_server_connectivity "$server" 2>/dev/null || echo "timeout")
        fi
        
        [[ "$first" == "false" ]] && echo ","
        
        cat << EOF
  {
    "name": "$name",
    "display_name": "$display",
    "hostname": "$hostname",
    "country": "$country",
    "region": "$region"$(if [[ -n "$latency" ]]; then echo ","; echo "    \"latency\": \"$latency\""; fi)
  }
EOF
        first=false
    done
    
    echo "]"
    exit 0
fi

# Names only output
if [[ "$NAMES_ONLY" == "true" ]]; then
    printf '%s\n' "${servers[@]}"
    exit 0
fi

# Prepare server data for display
declare -a server_data
declare -a latencies

for server in "${servers[@]}"; do
    server_info=$(get_server_info "$server")
    server_data+=("$server_info")
    
    if [[ "$TEST_CONNECTIVITY" == "true" ]]; then
        latency=$(test_server_connectivity "$server" 2>/dev/null || echo "timeout")
        latencies+=("$latency")
    else
        latencies+=("")
    fi
done

# Sort if requested
if [[ -n "$SORT_FIELD" ]]; then
    case "$SORT_FIELD" in
        name)
            # Already sorted by name from server list
            ;;
        country)
            # Sort by country (4th field)
            readarray -t sorted_indices < <(
                for i in "${!server_data[@]}"; do
                    echo "$i|${server_data[$i]}"
                done | sort -t'|' -k5 | cut -d'|' -f1
            )
            ;;
        latency)
            if [[ "$TEST_CONNECTIVITY" != "true" ]]; then
                echo "ERROR: --sort latency requires --test option" >&2
                exit 1
            fi
            # Sort by latency (numerical)
            readarray -t sorted_indices < <(
                for i in "${!latencies[@]}"; do
                    lat="${latencies[$i]}"
                    if [[ "$lat" == "timeout" ]]; then
                        lat="9999"
                    fi
                    printf "%06.2f|%d\n" "$lat" "$i"
                done | sort -n | cut -d'|' -f2
            )
            ;;
        *)
            echo "ERROR: Invalid sort field: $SORT_FIELD" >&2
            echo "Valid fields: name, country, latency" >&2
            exit 1
            ;;
    esac
    
    # Apply reverse if requested
    if [[ "$REVERSE_SORT" == "true" ]] && [[ -n "${sorted_indices:-}" ]]; then
        readarray -t sorted_indices < <(printf '%s\n' "${sorted_indices[@]}" | tac)
    fi
fi

# Group by country output
if [[ "$GROUP_BY_COUNTRY" == "true" ]]; then
    declare -A country_servers
    
    # Group servers by country
    for i in "${!server_data[@]}"; do
        IFS='|' read -r name display hostname country region <<< "${server_data[$i]}"
        if [[ -z "${country_servers[$country]:-}" ]]; then
            country_servers[$country]="$i"
        else
            country_servers[$country]+=" $i"
        fi
    done
    
    # Display grouped results
    echo "PIA Servers by Country:"
    echo ""
    
    for country in $(printf '%s\n' "${!country_servers[@]}" | sort); do
        echo "=== $country ==="
        for i in ${country_servers[$country]}; do
            IFS='|' read -r name display hostname country region <<< "${server_data[$i]}"
            
            if [[ "$VERBOSE" == "true" ]]; then
                printf "  %-20s %-25s %s" "$name" "$display" "$hostname"
                if [[ "$TEST_CONNECTIVITY" == "true" && -n "${latencies[$i]}" ]]; then
                    printf " (%s)" "${latencies[$i]}"
                fi
                echo
            else
                printf "  %-20s %s" "$name" "$display"
                if [[ "$TEST_CONNECTIVITY" == "true" && -n "${latencies[$i]}" ]]; then
                    printf " (%s)" "${latencies[$i]}"
                fi
                echo
            fi
        done
        echo
    done
    
    exit 0
fi

# Standard output
echo "Available PIA Servers:"
echo ""

if [[ "$VERBOSE" == "true" ]]; then
    printf "%-20s %-25s %-35s %-8s %s\n" "NAME" "DISPLAY NAME" "HOSTNAME" "COUNTRY" "LATENCY"
    echo "$(printf '=%.0s' {1..100})"
else
    printf "%-20s %-25s %-8s %s\n" "NAME" "DISPLAY NAME" "COUNTRY" "LATENCY"
    echo "$(printf '=%.0s' {1..70})"
fi

# Use sorted order if available
if [[ -n "${sorted_indices:-}" ]]; then
    indices=("${sorted_indices[@]}")
else
    indices=($(seq 0 $((${#server_data[@]} - 1))))
fi

for i in "${indices[@]}"; do
    IFS='|' read -r name display hostname country region <<< "${server_data[$i]}"
    
    latency_str=""
    if [[ "$TEST_CONNECTIVITY" == "true" && -n "${latencies[$i]}" ]]; then
        if [[ "${latencies[$i]}" == "timeout" ]]; then
            latency_str="TIMEOUT"
        else
            latency_str="${latencies[$i]}ms"
        fi
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        printf "%-20s %-25s %-35s %-8s %s\n" "$name" "$display" "$hostname" "$country" "$latency_str"
    else
        printf "%-20s %-25s %-8s %s\n" "$name" "$display" "$country" "$latency_str"
    fi
done

echo ""
echo "Total servers: ${#servers[@]}"

if [[ -n "$FILTER" ]]; then
    echo "Filter applied: $FILTER"
fi