#!/bin/bash

LOG_DIR="."
ERROR_PATTERN=("ERROR" "FATAL" "CRITICAL")
REPORT_FILE="./log_analysis_report.txt"

# Initialize report
echo "analysing log files" > "$REPORT_FILE"
echo "==================" >> "$REPORT_FILE"

printf "\nList of log files updated in last 24 hours\n" >> "$REPORT_FILE"
LOG_FILES=$(find "$LOG_DIR" -name "*.log" -mtime -1)
echo "$LOG_FILES" >> "$REPORT_FILE"

# Iterate over each found file
for LOG_FILE in $LOG_FILES; do
    printf "\n" >> "$REPORT_FILE"
    echo "-------------------------------" >> "$REPORT_FILE"
    echo "Analyzing file: $LOG_FILE" >> "$REPORT_FILE"
    echo "-------------------------------" >> "$REPORT_FILE"

    for PATTERN in "${ERROR_PATTERN[@]}"; do
        echo "--- Processing: $LOG_FILE ---" >> "$REPORT_FILE"
        echo "Searching for $PATTERN logs in $LOG_FILE" >> "$REPORT_FILE"

        # Only print “No … logs found” if grep fails
        if ! grep "$PATTERN" "$LOG_FILE" >> "$REPORT_FILE"; then
            echo "No $PATTERN logs found." >> "$REPORT_FILE"
        fi

        # Count matches
        ERROR_COUNT=$(grep -c "$PATTERN" "$LOG_FILE")

        # Highlight if too many
        if [ "$ERROR_COUNT" -gt 10 ]; then
            echo "Action Required: $PATTERN entries found: $ERROR_COUNT" 
        fi
    done
done

printf "\n" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

echo "Log analysis complete. Report saved to $REPORT_FILE"
