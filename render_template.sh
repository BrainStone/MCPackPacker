#!/usr/bin/env bash

template_file="$1"

# Function to process a file and return its contents with indentation
function indent_insert_file() {
  local insert_file="$1"
  local indent="$2"
  # Read the contents of the insert file and add the detected indentation
  awk -v indent="$indent" '{print indent $0}' "$insert_file"
}

# Iterate through the template file
while IFS= read -r line; do
  # Look for markers in the format @XXX@, where XXX is any file name
  if [[ "$line" =~ ([ $'\t']*)@([^@]+)@ ]]; then
    # Extract the indent and file name from the marker
    indent="${BASH_REMATCH[1]}"
    insert_file="${BASH_REMATCH[2]}"
    if [[ -f "$insert_file" ]]; then
      # Process and insert the file content with proper indentation
      indent_insert_file "$insert_file" "$indent"
    else
      echo "File $insert_file not found!"
    fi
  else
    echo "$line"
  fi
done < "$template_file"
