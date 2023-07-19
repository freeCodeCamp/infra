#!/bin/bash
input="$1"
os=$(uname)

if [[ $os == "Linux" ]]; then
  date --iso-8601=seconds -d "$input"
elif [[ $os == "Darwin" ]]; then
  case "$input" in
  *minute* | *minutes* | *min* | *mins*)
    amount=${input%% minute*}
    amount=${amount%% minutes*}
    amount=${amount%% min*}
    amount=${amount%% mins*}
    date -v-"$amount"M -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *hour* | *hours*)
    amount=${input%% hour*}
    amount=${amount%% hours*}
    date -v-"$amount"H -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *day* | *days*)
    amount=${input%% day*}
    amount=${amount%% days*}
    date -v-"$amount"d -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *week* | *weeks*)
    amount=${input%% week*}
    amount=${amount%% weeks*}
    days=$((amount * 7))
    date -v-"$days"d -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *month* | *months*)
    amount=${input%% month*}
    amount=${amount%% months*}
    date -v-"$amount"m -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  *year* | *years*)
    amount=${input%% year*}
    amount=${amount%% years*}
    date -v-"$amount"y -u +"%Y-%m-%dT%H:%M:%SZ"
    ;;
  esac
else
  echo "Unsupported operating system."
fi
