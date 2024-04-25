#!/bin/bash

# Define paths
HOSTS_FILE="/etc/hosts"
DOMAINS_FILE="$HOME/.config/mutombo.txt"
IP_BLOCK="127.0.0.1"
STATE_FILE="$HOME/mutombo"

# Load or initialize block state
echo "Checking state file at $STATE_FILE"
if [ -f "$STATE_FILE" ] && [ -r "$STATE_FILE" ]; then
	BLOCK_STATE=$(cat "$STATE_FILE")
	echo "Loaded BLOCK_STATE: $BLOCK_STATE"
else
	echo "No state file found or not readable. Setting default state: UNBLOCKED."
	BLOCK_STATE="UNBLOCKED"
fi

# Function to update the block status environment variable
update_block_state() {
	if [ "$BLOCK_STATE" == "BLOCKED" ]; then
		BLOCK_STATE="UNBLOCKED"
	else
		BLOCK_STATE="BLOCKED"
	fi
	echo "$BLOCK_STATE" >"$STATE_FILE"
	echo "Setting BLOCK STATE to $BLOCK_STATE."
}

# Function to check for start and end markers
check_markers() {
	local start_exists=$(grep -c "# MUTOMBO_START #" "$HOSTS_FILE")
	local end_exists=$(grep -c "# MUTOMBO_END #" "$HOSTS_FILE")

	if [ "$start_exists" -eq 0 ] || [ "$end_exists" -eq 0 ]; then
		echo "Error: Start or end markers are missing in the $HOSTS_FILE."
		echo "Please add the following lines to your hosts file manually using sudo:"
		echo "  # MUTOMBO_START #"
		echo "  # MUTOMBO_END #"
		exit 1
	fi
}

# Function to toggle entries within a designated block
toggle_mutombo_block() {
	check_markers
	local temp_file=$(mktemp)
	local in_block="false"

	echo "Starting toggle operation..."
	while IFS= read -r line; do
		if [[ "$line" == "# MUTOMBO_START #" ]]; then
			echo "$line" >>"$temp_file"
			in_block="true"
			# When UNBLOCKED, we add domains
			if [ "$BLOCK_STATE" == "UNBLOCKED" ]; then
				while IFS= read -r domain; do
					if [ ! -z "$domain" ]; then
						echo "$IP_BLOCK $domain" >>"$temp_file"
						echo "$IP_BLOCK www.$domain" >>"$temp_file"
					fi
				done <"$DOMAINS_FILE"
			fi
			continue
		elif [[ "$line" == "# MUTOMBO_END #" ]]; then
			echo "$line" >>"$temp_file"
			in_block="false"
			continue
		fi

		# Add non-domain lines directly to the temp file
		if [ "$in_block" == "false" ]; then
			echo "$line" >>"$temp_file"
		fi
	done <"$HOSTS_FILE"

	update_block_state # Toggle the state after processing

	# Overwrite the original hosts file with the new content
	sudo cp "$temp_file" "$HOSTS_FILE" # This overwrites the contents but keeps original permissions
	rm "$temp_file"                    # Clean up the temporary file

	# Clear DNS cache
	sudo dscacheutil -flushcache
	sudo killall -HUP mDNSResponder
	echo "DNS cache has been reset."
}

toggle_mutombo_block
