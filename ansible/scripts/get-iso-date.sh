#!/bin/bash
input="$1"
os=$(uname)

# Function to convert time expressions to UTC ISO 8601 format on Linux
convert_to_utc_linux() {
  case "$1" in
  *minute* | *minutes* | *min* | *mins*)
    amount=${1%%minute*}
    amount=${amount%%minutes*}
    amount=${amount%%min*}
    amount=${amount%%mins*}
    date --iso-8601=seconds -u -d "-$amount minutes"
    ;;
  *hour* | *hours*)
    amount=${1%%hour*}
    amount=${amount%%hours*}
    date --iso-8601=seconds -u -d "-$amount hours"
    ;;
  *day* | *days*)
    amount=${1%%day*}
    amount=${amount%%days*}
    date --iso-8601=seconds -u -d "-$amount days"
    ;;
  *week* | *weeks*)
    amount=${1%%week*}
    amount=${amount%%weeks*}
    days=$((amount * 7))
    date --iso-8601=seconds -u -d "-$days days"
    ;;
  *month* | *months*)
    amount=${1%%month*}
    amount=${amount%%months*}
    date --iso-8601=seconds -u -d "-$amount months"
    ;;
  *year* | *years*)
    amount=${1%%year*}
    amount=${amount%%years*}
    date --iso-8601=seconds -u -d "-$amount years"
    ;;
  esac
}

# Function to convert time expressions to UTC ISO 8601 format on macOS
convert_to_utc_darwin() {
  case "$1" in
  *minute* | *minutes* | *min* | *mins*)
    amount=${1%%minute*}
    amount=${amount%%minutes*}
    amount=${amount%%min*}
    amount=${amount%%mins*}
    date -v-"$amount"M -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *hour* | *hours*)
    amount=${1%%hour*}
    amount=${amount%%hours*}
    date -v-"$amount"H -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *day* | *days*)
    amount=${1%%day*}
    amount=${amount%%days*}
    date -v-"$amount"d -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *week* | *weeks*)
    amount=${1%%week*}
    amount=${amount%%weeks*}
    days=$((amount * 7))
    date -v-"$days"d -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *month* | *months*)
    amount=${1%%month*}
    amount=${amount%%months*}
    date -v-"$amount"m -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *year* | *years*)
    amount=${1%%year*}
    amount=${amount%%years*}
    date -v-"$amount"y -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  esac
}

if [[ $os == "Linux" ]]; then
  convert_to_utc_linux "$input"
elif [[ $os == "Darwin" ]]; then
  convert_to_utc_darwin "$input"
else
  echo "Unsupported operating system."
  exit 1
fi
