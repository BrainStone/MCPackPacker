#! /usr/bin/env bash

function print_help() {
	cat <<EOF
pack_packer.sh - Create the a compressed datapack or resourcepack .zip file
Usage: ${BASH_SOURCE[0]} [options] <path> <file_name>

The goal of this script is to create a zipped resource pack.
By default it creates a minified version of the file, by minifying each
individual file in the <path>.

Options:
 -h, --help        display this help and exit
     --dev         don't minimize the contents of the .zip file and append
                   "DEV" before the file extension
EOF
}

function get_filesize() {
	du -b "$1" | cut -d$'\t' -f1
}

function calc_percent_reduction() {
	local original_size="$1"
	local new_size="$2"
	local formatted_change

	if [[ "$original_size" -eq 0 ]]; then
		formatted_change="-inf"
	elif [[ "$new_size" -eq "$original_size" ]]; then
		formatted_change="±0.00"
	else
		local diff=$((original_size - new_size))
		local sign="-"

		# Default case is that new file is smaller, that's why the signs are this way round!
		if [[ "$diff" -lt 0 ]]; then
			diff=$((-diff))
			sign="+"
		fi

		local percent_change=$(((diff * 10000) / original_size))
		formatted_change="${sign}$((percent_change / 100)).$(((percent_change / 10) % 10))$((percent_change % 10))"
	fi

	echo "${formatted_change}% (${original_size} -> ${new_size})"
}

function cache() {
	local key="$1"
	local source_file="$2"
	local target_file="$3"
	shift 3

	local md5
	md5="$(md5sum -b "$source_file" | cut -d' ' -f1)"
	local cache_file=".cache/${key}/${md5:0:2}/${md5:2:2}/${md5:4}"

	if [[ -f "$cache_file" ]]; then
		# Copy file from cache
		cp "$cache_file" "$target_file"
	else
		# Execute the command
		"$@"

		# Cache the file
		mkdir -p "$(dirname "$cache_file")"
		cp "$target_file" "$cache_file"
	fi
}

function command_exists() {
	if command -v "$1" &>/dev/null; then
		echo 1
	fi
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	print_help
	exit
elif [[ "$1" == "--dev" ]]; then
	# Empty string as test condition is false
	optimize=""
	shift
else
	optimize=1
fi

if [[ $# -lt 2 ]]; then
	print_help
	exit 1
fi

base_folder="$1"
result_file="$2"
[[ "$optimize" ]] || result_file="${result_file/\.zip/_DEV.zip}"

# Detect installed tools
jq_installed="$(command_exists jq)"
ffmpeg_installed="$(command_exists ffmpeg)"
oxipng_installed="$(command_exists oxipng)"
optipng_installed="$(command_exists optipng)"

# Shell options starting here
set -e
set -o pipefail
shopt -s globstar

# Ensure we're working relative to the script
cd "$(dirname "${BASH_SOURCE[0]}")"

# Cleanup the last build if it still exists. The folder will be recreated in the loop
rm -rf .build "$result_file"

total_source_file_size=0
total_target_file_size=0
sounds_json="{}"

if [[ "$optimize" ]]; then
	echo "Optimizing files..."
else
	echo "Copying files..."
fi

while IFS= read -r -u3 -d '' source_file; do
	echo -n "  Processing ${source_file}..."

	target_file="${source_file/"$base_folder"/.build}"

	if [[ -d "$source_file" ]]; then
		mkdir "$target_file"
	elif [[ "$optimize" && "$source_file" =~ .*\.(lang|mcfunction|properties)$ ]]; then
		# If function files suddenly become corrupted, blame the head here!
		(
			cat "$source_file"
			echo
		) | sed -E '/^(\s*$|#)/d' | head -c-1 >"$target_file"
	elif [[ "$optimize" && "$jq_installed" && "$source_file" =~ .*\.(json|mcmeta)$ ]]; then
		jq -c . "$source_file" >"$target_file"
	elif [[ "$optimize" && "$ffmpeg_installed" && "$source_file" =~ .*\.ogg$ ]]; then
		cache ogg_v1 "$source_file" "$target_file" \
			ffmpeg -hide_banner -loglevel error -y -i "$source_file" -c:a libopus -b:a 32k -ar 48000 -ac 2 -application audio -map_metadata -1 -flags:a +bitexact "$target_file"
	elif [[ "$optimize" && "$oxipng_installed" && "$source_file" =~ .*\.png$ ]]; then
		cache png_v2 "$source_file" "$target_file" \
			oxipng --quiet -o max --fast --zopfli --strip safe --out "$target_file" -- "$source_file"
	elif [[ "$optimize" && "$optipng_installed" && "$source_file" =~ .*\.png$ ]]; then
		cache png_v1 "$source_file" "$target_file" \
			optipng -quiet -o7 -zm1-9 -strip all -out "$target_file" -- "$source_file"
	else
		cp "$source_file" "$target_file"
	fi

	# Generate sounds.json
	if [[ "$source_file" =~ .*\.ogg$ ]]; then
		sound_path="${source_file/"$base_folder/assets/minecraft/sounds/"/}"
		sound_path="${sound_path%.*}"

		if [[ "$sound_path" =~ (.*)([0-9]+)$ ]]; then
			sound_names=(
				"${BASH_REMATCH[1]/"/"/.}"
				"${BASH_REMATCH[1]/"/"/.}.${BASH_REMATCH[2]}"
			)
		else
			sound_names=(
				"${sound_path/"/"/.}"
			)
		fi

		for sound_name in "${sound_names[@]}"; do
			sounds_json="$(
				echo "$sounds_json" | jq --arg name "$sound_name" --arg path "$sound_path" \
					'.[$name].category = "master" | .[$name].sounds += [$path]'
			)"
		done
	fi

	if [[ "$optimize" && -f "$source_file" ]]; then
		# Computing file size reduction
		source_file_size="$(get_filesize "$source_file")"
		target_file_size="$(get_filesize "$target_file")"

		# If optimizing made the file bigger, don't use the "optimized" file
		# This can happen with ogg files
		if [[ "$source_file_size" -lt "$target_file_size" ]]; then
			cp -f "$source_file" "$target_file"
			target_file_size="$source_file_size"

			echo -en "\b\b\b (X)..."
		fi

		total_source_file_size="$((total_source_file_size + source_file_size))"
		total_target_file_size="$((total_target_file_size + target_file_size))"

		echo -e "\b\b\b: $(calc_percent_reduction "$source_file_size" "$target_file_size")"
	else
		echo -e "\b\b\b   "
	fi
done 3< <(find "$base_folder" -print0)

# Write the sounds.json, but only if we actually found sound files!
if [[ "$sounds_json" != "{}" ]]; then
	echo -n "  Processing .build/assets/minecraft/sounds.json..."

	if [[ "$optimize" ]]; then
		source_file_size="${#sounds_json}"

		sounds_json="$(echo "$sounds_json" | jq -c .)"
	fi

	echo "$sounds_json" >.build/assets/minecraft/sounds.json

	if [[ "$optimize" ]]; then
		target_file_size="${#sounds_json}"

		total_source_file_size="$((total_source_file_size + source_file_size))"
		total_target_file_size="$((total_target_file_size + target_file_size))"

		echo -e "\b\b\b: $(calc_percent_reduction "$source_file_size" "$target_file_size")"
	else
		echo -e "\b\b\b   "
	fi
fi

if [[ "$optimize" ]]; then
	echo "Optimizing files DONE!"

	echo -e "\nTotal: $(calc_percent_reduction "$total_source_file_size" "$total_target_file_size")"
else
	echo "Copying files DONE!"
fi

cd .build
echo -en "\nCompressing files..."
zip -9rq "../$result_file" .
echo -e "\b\b\b DONE!"

if [[ "$optimize" ]]; then
	cd ..

	echo -en "\nRecompressing ${result_file}..."
	source_file_size="$(get_filesize "$result_file")"

	advzip -zpk4qi10 "$result_file"

	target_file_size="$(get_filesize "$result_file")"

	echo -e "\b\b\b: $(calc_percent_reduction "$source_file_size" "$target_file_size")"
	echo -e "Total (incl. zip compression): $(calc_percent_reduction "$total_source_file_size" "$target_file_size")"
fi
