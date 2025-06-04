#!/usr/bin/env zsh

# command-histogram.plugin.zsh
# Maintains a histogram of commands over time

# Configuration
: ${COMMAND_HISTOGRAM_FILE:="${HOME}/.zsh_command_history.db"}
: ${COMMAND_HISTOGRAM_MAX_ENTRIES:=10000}
: ${COMMAND_HISTOGRAM_CLEANUP_THRESHOLD:=50000}

# Ensure data directory exists
mkdir -p "$(dirname "$COMMAND_HISTOGRAM_FILE")"

# Hook function to capture commands before execution
function __command_histogram_preexec() {
    local cmd="$1"
    local timestamp=$(date +%s)
    local base_cmd
    
    # Extract base command (first word, handle pipes/redirects)
    base_cmd=$(echo "$cmd" | sed -E 's/^[[:space:]]*//' | cut -d' ' -f1 | cut -d'|' -f1 | cut -d'>' -f1 | cut -d'<' -f1)
    
    # Skip empty commands or those starting with space (private)
    [[ -z "$base_cmd" || "$cmd" =~ '^[[:space:]]' ]] && return
    
    # Append to histogram file: timestamp|base_command|full_command
    printf "%s|%s|%s\n" "$timestamp" "$base_cmd" "$cmd" >> "$COMMAND_HISTOGRAM_FILE"
    
    # Periodic cleanup
    if (( RANDOM % 100 == 0 )); then
        __command_histogram_cleanup
    fi
}

# Cleanup old entries if file grows too large
function __command_histogram_cleanup() {
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || return
    
    local line_count=$(wc -l < "$COMMAND_HISTOGRAM_FILE")
    if (( line_count > COMMAND_HISTOGRAM_CLEANUP_THRESHOLD )); then
        local temp_file=$(mktemp)
        tail -n "$COMMAND_HISTOGRAM_MAX_ENTRIES" "$COMMAND_HISTOGRAM_FILE" > "$temp_file"
        mv "$temp_file" "$COMMAND_HISTOGRAM_FILE"
    fi
}

# Display command histogram
function zistogram() {
    local period="${1:-all}"
    local limit="${2:-20}"
    local now=$(date +%s)
    local since=0
    
    case "$period" in
        "hour"|"1h")   since=$((now - 3600)) ;;
        "day"|"1d")    since=$((now - 86400)) ;;
        "week"|"1w")   since=$((now - 604800)) ;;
        "month"|"1m")  since=$((now - 2592000)) ;;
        "year"|"1y")   since=$((now - 31536000)) ;;
        "all"|*)       since=0 ;;
    esac
    
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || {
        echo "No command history found."
        return 1
    }
    
    awk -F'|' -v since="$since" -v limit="$limit" '
        $1 >= since { count[$2]++ }
        END {
            for (cmd in count) {
                printf "%d %s\n", count[cmd], cmd
            }
        }
    ' "$COMMAND_HISTOGRAM_FILE" | sort -nr | head -n "$limit" | \
    awk '{ printf "%4d %s\n", $1, $2 }'
}

# Show command timeline
function zistogram_timeline() {
    local cmd="$1"
    local period="${2:-day}"
    
    [[ -z "$cmd" ]] && {
        echo "Usage: zistogram_timeline <command> [hour|day|week|month]"
        return 1
    }
    
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || {
        echo "No command history found."
        return 1
    }
    
    local format_str
    case "$period" in
        "hour")  format_str="%Y-%m-%d %H:00" ;;
        "day")   format_str="%Y-%m-%d" ;;
        "week")  format_str="%Y-W%U" ;;
        "month") format_str="%Y-%m" ;;
        *)       format_str="%Y-%m-%d" ;;
    esac
    
    awk -F'|' -v cmd="$cmd" -v fmt="$format_str" '
        $2 == cmd {
            cmd_date = strftime(fmt, $1)
            count[cmd_date]++
        }
        END {
            for (date in count) {
                printf "%s %d\n", date, count[date]
            }
        }
    ' "$COMMAND_HISTOGRAM_FILE" | sort
}

# Show detailed command usage
function zistogram_detail() {
    local cmd="$1"
    local limit="${2:-10}"
    
    [[ -z "$cmd" ]] && {
        echo "Usage: zistogram_detail <command> [limit]"
        return 1
    }
    
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || {
        echo "No command history found."
        return 1
    }
    
    awk -F'|' -v cmd="$cmd" '
        $2 == cmd { full[$3]++; total++ }
        END {
            printf "Total uses of %s: %d\n\n", cmd, total
            for (full_cmd in full) {
                printf "%4d %s\n", full[full_cmd], full_cmd
            }
        }
    ' "$COMMAND_HISTOGRAM_FILE" | \
    (read header; echo "$header"; sort -nr) | head -n $((limit + 2))
}

# Show statistics
function zistogram_stats() {
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || {
        echo "No command history found."
        return 1
    }
    
    awk -F'|' '
        {
            commands[$2]++
            total++
            if (NR == 1) first_time = $1
            last_time = $1
        }
        END {
            unique = length(commands)
            days = (last_time - first_time) / 86400
            
            printf "Statistics:\n"
            printf "  Total commands: %d\n", total
            printf "  Unique commands: %d\n", unique
            printf "  Days tracked: %.1f\n", days
            printf "  Average per day: %.1f\n", (days > 0) ? total/days : 0
            printf "  Data file: %s\n", ENVIRON["COMMAND_HISTOGRAM_FILE"]
        }
    ' "$COMMAND_HISTOGRAM_FILE"
}

# Export data as CSV
function zistogram_export() {
    local output_file="${1:-command_histogram.csv}"
    
    [[ -f "$COMMAND_HISTOGRAM_FILE" ]] || {
        echo "No command history found."
        return 1
    }
    
    echo "timestamp,command,full_command" > "$output_file"
    awk -F'|' '{ 
        gsub(/,/, "\\,", $2)
        gsub(/,/, "\\,", $3)
        printf "%s,%s,%s\n", $1, $2, $3 
    }' "$COMMAND_HISTOGRAM_FILE" >> "$output_file"
    
    echo "Exported to $output_file"
}

# Clear histogram data
function zistogram_clear() {
    read -q "REPLY?Clear all command history? (y/N) "
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        > "$COMMAND_HISTOGRAM_FILE"
        echo "Command history cleared."
    fi
}

# Help function
function zistogram_help() {
    cat << 'EOF'
Command Histogram Plugin

Commands:
  zistogram [period] [limit]       Show top commands (default: all time, top 20)
                               Periods: hour|day|week|month|year|all
  
  zistogram_timeline <cmd> [period] Show usage timeline for specific command
                               Periods: hour|day|week|month
  
  zistogram_detail <cmd> [limit]   Show detailed usage of specific command
  
  zistogram_stats                  Show overall statistics
  
  zistogram_export [file]          Export data as CSV
  
  zistogram_clear                  Clear all histogram data
  
  zistogram_help                   Show this help

Examples:
  zistogram day 10                 Top 10 commands from last day
  zistogram_timeline git week      Git usage over weeks
  zistogram_detail vim 5           Top 5 vim command variants

Configuration:
  COMMAND_HISTOGRAM_FILE       Data file location (default: ~/.zsh_command_history.db)
  COMMAND_HISTOGRAM_MAX_ENTRIES Maximum entries to keep (default: 10000)
EOF
}

# Register the preexec hook
autoload -Uz add-zsh-hook
add-zsh-hook preexec __command_histogram_preexec

# Completion for zistogram functions
function _zistogram_periods() {
    _describe 'periods' '(hour day week month year all)'
}

function _zistogram_commands() {
    if [[ -f "$COMMAND_HISTOGRAM_FILE" ]]; then
        local commands=($(awk -F'|' '{print $2}' "$COMMAND_HISTOGRAM_FILE" | sort -u))
        _describe 'commands' commands
    fi
}

compdef '_arguments "1:period:_zistogram_periods" "2:limit:"' zistogram
compdef '_arguments "1:command:_zistogram_commands" "2:period:_zistogram_periods"' zistogram_timeline
compdef '_arguments "1:command:_zistogram_commands" "2:limit:"' zistogram_detail
