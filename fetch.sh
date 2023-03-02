#!/usr/bin/env bash

# Overwrite current data.
set -e
DIR=$(dirname $(realpath $0))
echo "| Rank | Relative % | CPU | Benchmarks | Average | High | Low |" > "${DIR}/cpu.md"
echo "|------|------------|-----|------------|---------|------|-----|" >> "${DIR}/cpu.md"
echo "[" > "${DIR}/cpu.json"

# Get current time.
UNIX=$(date +%s)
DATE=$(date --date "@${UNIX}")
echo "$UNIX" > "${DIR}/unix"

# Function: Remove `$1` and filter out whitespace/colon/comma.
filter_json() { awk '{$1=""}1' | awk '{$1=$1}1' | sed 's/^"//g' | sed 's/",$//g'; }

# Get raw JSON data from XMRig website.
RAW_JSON_DATA=$(wget -qO- https://api.xmrig.com/1/benchmarks)
echo "$RAW_JSON_DATA" > "${DIR}/raw.json"
# JSON response is an array, each element looks like this:
#
# {
#   "cpu":         "AMD EPYC 7T83 64-Core Processor"
#   "hashrate":    103706.4692095493
#	"hashrate_1t": 405.10339534980193
#	"count":       28
#	"size":        200000000
#	"threads":     256
# },

# Filter for CPU names.
CPU_LIST=$(echo "$RAW_JSON_DATA" | grep cpu | filter_json)
CPU_FASTEST=$(echo "$CPU_LIST" | head -n 1)
CPU_SLOWEST=$(echo "$CPU_LIST" | tail -n 1)
CPU_COUNT=$(echo "$CPU_LIST" | wc -l)
# `\n` terminated list of all CPUs found in above JSON data.
#
# AMD EPYC 7T83 64-Core Processor
# AMD Eng Sample: 100-000000053-04_32/20_N
# AMD EPYC 7763 64-Core Processor
# [...]

# Get fastest hashrate to compare percentages.
set_fastest_hashrate() {
	local cpu=$(wget -qO- "https://api.xmrig.com/1/benchmarks?cpu=${CPU_FASTEST}" | grep "hashrate\"" | filter_json)
	FASTEST_HASH=$(echo "$cpu" | head -n 1)
}
set_fastest_hashrate

# For each CPU, find average hashrate, append to `cpu.json`.
RANK=1
fail_count=0
IFS=$'\n'
for CPU in $CPU_LIST; do
	echo "Starting: ${CPU}"

	# Get CPU-specific data.
	until CPU_DATA=$(wget -qO- "https://api.xmrig.com/1/benchmarks?cpu=${CPU}"); do
		# Try again on failure.
		echo "CPU request failure: $CPU ... Attempt [${fail_count}/5]"
		sleep 5
		((fail_count++))
		if [[ $fail_count -gt 5 ]]; then
			echo "********************************* CPU request failure: $CPU ... SKIPPING *********************************"
			fail_count=0
			continue 2
		fi
	done

	# How many times a benchmark has been submitted.
	# Continue on failure.
	if ! COUNT=$(echo "$CPU_DATA" | grep -c id); then
		echo "********************************* CPU failure: $CPU ... SKIPPING *********************************"
		continue
	fi

	# `\n` terminated list of hashrate from all benchmarks.
	LIST=$(echo "$CPU_DATA" | grep "hashrate\"" | filter_json | tr -d '",')

	# Highest hashrate.
	HIGH=$(echo "$LIST" | head -n 1)

	# Lowest hashrate.
	LOW=$(echo "$LIST" | tail -n 1)

	# Combined hashrate of all the benchmarks.
	COMBINED=$(echo "$LIST" | awk -M -v PREC=200 '{SUM+=$1} END {printf "%.7f\n", SUM }')

	# (count / combined) = average hashrate.
	AVERAGE=$(echo "$COMBINED" "$COUNT" | awk '{printf "%.7f\n", $1 / $2 }')

	# % of hashrate compared to the fastest.
	PERCENT=$(echo "$HIGH" "$FASTEST_HASH" | awk '{printf "%.2f\n", ($1 / $2) * 100.0 }')
	PERCENT_INT=${PERCENT/.*/}
	if [[ $PERCENT_INT -lt 1 ]]; then
		EMOJI=🗿
	elif [[ $PERCENT_INT -le 5 ]]; then
		EMOJI=🔴
	elif [[ $PERCENT_INT -le 15 ]]; then
		EMOJI=🟠
	elif [[ $PERCENT_INT -le 80 ]]; then
		EMOJI=🟡
	elif [[ $PERCENT_INT -ge 80 ]]; then
		EMOJI=🟢
	fi

	if [[ $PERCENT_INT = 100 ]]; then
		EMOJI=⚡️
	fi

	# Append in Markdown form.
	echo "| $RANK - $EMOJI | ${PERCENT}% | $CPU | $COUNT | ${AVERAGE/.*/} | ${HIGH/.*/} | ${LOW/.*/} |" >> "${DIR}/cpu.md"

	# Append in JSON form.
cat << EOM >> "${DIR}/cpu.json"
    {
        "cpu": "$CPU",
        "rank": $RANK,
        "percent": $PERCENT,
        "benchmarks": $COUNT,
        "average": $AVERAGE,
        "high": $HIGH,
        "low": $LOW
    },
EOM

	# Print to console.
	printf "%s\n" \
		"rank        | $RANK"    \
		"%           | $PERCENT" \
		"emoji       | $EMOJI"   \
		"cpu         | $CPU"     \
		"benchmarks  | $COUNT"   \
		"average     | $AVERAGE" \
		"high        | $HIGH"    \
		"low         | $LOW"     \
		"-----------------------------------------------------------"

	((RANK++))
done

# End JSON array.
sed -i '$ d' "${DIR}/cpu.json"
echo "    }" >> "${DIR}/cpu.json"
echo "]" >> "${DIR}/cpu.json"

# Update `uptime`.
UPTIME=$(<"${DIR}/uptime")
UPTIME=$((UPTIME+1))
echo "${UPTIME}" > "${DIR}/uptime"

# Update `GitHub Time Used`.
ALREADY_USED=$(<"${DIR}/time")
UNIX_NOW=$(date +%s)
TIME_USED=$((UNIX_NOW - UNIX))
TIME_USED=$((ALREADY_USED + TIME_USED))
echo "$TIME_USED" > "${DIR}/time"

# Update `README.md`.
cat << EOM > "${DIR}/README.md"
This repo runs a GitHub Action every day that:
1. Fetches CPU benchmarks from [\`XMRig's API\`](https://xmrig.com/benchmark)
2. Finds the average hashrate for each CPU
3. Formats the data here in \`JSON\` and \`Markdown\`

## Stats
* Uptime: \`$UPTIME\` days
* CPUs listed: \`$CPU_COUNT\`
* Fastest CPU: \`$CPU_FASTEST\`
* Slowest CPU: \`$CPU_SLOWEST\`
* Total GitHub time used: \`$TIME_USED\` seconds
* Last updated: \`$DATE\` (\`$UNIX\`)

## List
EOM

column -t -s '|' -o '|' "${DIR}/cpu.md" >> "${DIR}/README.md"
