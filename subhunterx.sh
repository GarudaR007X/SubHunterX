#!/bin/bash

# Set strict error handling
set -euo pipefail

# Colors (defined before usage to avoid unbound variable errors)
REDCOLOR='\e[31m'
GREENCOLOR='\e[32m'
YELLOWCOLOR='\e[33m'
BLUECOLOR='\e[34m'
RESETCOLOR='\e[0m'

# Error handler
trap 'echo -e "${REDCOLOR}An error occurred. Exiting...${RESETCOLOR}"; exit 1' ERR

# Check if domain argument is provided
if [ $# -lt 1 ]; then
    echo -e "${REDCOLOR}Usage: \$0 <domain>${RESETCOLOR}"
    exit 1
fi

# Input and directories
domain="$1"
output_dir="/root/Desktop/${domain}"
mkdir -p "$output_dir" || { echo -e "${REDCOLOR}Failed to create output directory${RESETCOLOR}"; exit 1; }

# Extract TLD (fixed sed command)
tld=$(echo "$domain" | sed -E 's/.*\.([a-zA-Z]{2,3}(\.[a-zA-Z]{2,3})?)$/\1/')

# Check if required tools are installed
tools=(amass subfinder findomain assetfinder sublist3r httpx ffuf waybackurls gau gobuster shuffledns massdns katana chaos dnsx gf jq)
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${REDCOLOR}$tool is not installed. Please install it and try again.${RESETCOLOR}"
        exit 1
    fi
done

start_time=$(date)
echo -e "${YELLOWCOLOR}[+] Recon started at $start_time${RESETCOLOR}"

### Subdomain Enumeration ###
echo -e "${REDCOLOR}[+] Enumerating Subdomains...${RESETCOLOR}"

echo -e "${BLUECOLOR}[+] Running Amass...${GREENCOLOR}${RESETCOLOR}"
NO_COLOR=1 amass enum -active -d "$domain" -config "$AMASS_CONFIG" -rf "$RESOLVERS" -o "$output_dir/amass.txt"

echo -e "${BLUECOLOR}[+] Running Subfinder...${GREENCOLOR}${RESETCOLOR}"
subfinder -d "$domain" -o "$output_dir/subfinder.txt"

echo -e "${BLUECOLOR}[+] Running Findomain...${GREENCOLOR}${RESETCOLOR}"
findomain -t "$domain" --quiet > "$output_dir/findomain.txt"

echo -e "${BLUECOLOR}[+] Running Assetfinder...${GREENCOLOR}${RESETCOLOR}"
assetfinder -subs-only "$domain" > "$output_dir/assetfinder.txt"

echo -e "${BLUECOLOR}[+] Running Sublist3r...${GREENCOLOR}${RESETCOLOR}"
python3 -W ignore /usr/local/bin/sublist3r -d "$domain" -e baidu,yahoo,google,bing,ask,netcraft,threatcrowd,ssl,passivedns -o "$output_dir/sublist3r.txt"

echo -e "${BLUECOLOR}[+] Running Chaos...${GREENCOLOR}${RESETCOLOR}"
chaos -key "$CHAOS_API_KEY" -d "$domain" -o "$output_dir/chaos.txt"

echo -e "${BLUECOLOR}[+] Running Gobuster...${GREENCOLOR}${RESETCOLOR}"
gobuster dns -d "$domain" -w "$WORDLISTS" -o "$output_dir/gobuster.txt" -t 300 --timeout 2s -r 8.8.8.8 --no-color


### Combine Subdomains ###
echo -e "${REDCOLOR}[+] Merging and cleaning subdomains...${RESETCOLOR}"

grep -Eo "([a-zA-Z0-9_-]+\.)+${domain//./\\.}" "$output_dir/amass.txt" \
    | sed -E "s/\x1B\[[0-9;]*[mK]//g" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//' > "$output_dir/amass_cleaned.txt"

grep -Eo '\b[a-z0-9.-]+\b' "$output_dir/gobuster.txt" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//' | sort -u > "$output_dir/gobuster_cleaned.txt"

sort -u "$output_dir/amass_cleaned.txt" "$output_dir/gobuster_cleaned.txt" "$output_dir/assetfinder.txt" "$output_dir/chaos.txt" "$output_dir/findomain.txt" "$output_dir/subfinder.txt" "$output_dir/sublist3r.txt" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//' > "$output_dir/all_subdomains.txt"


### Resolve Subdomains ###
echo -e "${YELLOWCOLOR}[+] Resolving subdomains...${RESETCOLOR}"
echo -e "${BLUECOLOR}[+] Running Shuffledns...${GREENCOLOR}${RESETCOLOR}"
shuffledns -d "$domain" -list "$output_dir/all_subdomains.txt" -r "$RESOLVERS" -o "$output_dir/resolved_shuffledns.txt" -silent -nc -mode resolve
echo -e "${BLUECOLOR}[+] Running Massdns...${GREENCOLOR}${RESETCOLOR}"
massdns -t A -r "$RESOLVERS" -o S -w "$output_dir/massdns_output.txt" "$output_dir/all_subdomains.txt"
grep -Eo '^[^ ]+' "$output_dir/massdns_output.txt" | sed 's/\.$//' >> "$output_dir/resolved_massdns.txt"

sort -u "$output_dir/resolved_shuffledns.txt" "$output_dir/resolved_massdns.txt" > "$output_dir/resolved_subdomains.txt"

### Live Subdomain Check ###
echo -e "${REDCOLOR}[+] Checking for live subdomains with httpx...${RESETCOLOR}"

httpx -l "$output_dir/resolved_subdomains.txt" -o "$output_dir/live_subdomains.txt" -silent -threads 300 -mc 200,301,302,403,404,500,502,503

### API Filtering ###
echo -e "${REDCOLOR}[+] Searching for API subdomains...${RESETCOLOR}"

grep -i "api" "$output_dir/live_subdomains.txt" | sort -u > "$output_dir/api.txt"

### Crawl Endpoints with Katana ###
echo -e "${REDCOLOR}[+] Crawling live subdomains with Katana...${RESETCOLOR}"

katana -list "$output_dir/live_subdomains.txt" -o "$output_dir/katana_output.txt" -d 3
grep -E "\.js|\.json|\.php|\.xml|\.txt|\.env|api" "$output_dir/katana_output.txt" > "$output_dir/katana_filtered.txt"

### FFUF - Directory Brute-force ###
echo -e "${REDCOLOR}[+] Running FFUF for directory brute-force...${RESETCOLOR}"

ffuf -u "https://$domain/FUZZ" -w "$FUZZ" -mc 200,301,403 -t 50 -o "$output_dir/ffuf_output.json"
jq -r '.results[] | .url' "$output_dir/ffuf_output.json" | sort -u > "$output_dir/ffuf_filtered.txt"

### Crawl FFUF URLs with Katana ###
katana -list "$output_dir/ffuf_filtered.txt" -o "$output_dir/ffuf_katana_output.txt" -d 3

### Merge Files for GF Pattern Matching ###
cat "$output_dir/katana_filtered.txt" "$output_dir/ffuf_filtered.txt" "$output_dir/ffuf_katana_output.txt" | sort -u > "$output_dir/merged_files.txt"

### DNS Resolution to IPs ###
sed 's|https://||g; s|http://||g' "$output_dir/live_subdomains.txt" > "$output_dir/live_subdomains_stripped.txt"
dnsx -l "$output_dir/live_subdomains_stripped.txt" -resp-only | sort -u > "$output_dir/ips.txt"

### GF Pattern Matching ###
echo -e "${REDCOLOR}[+] Extracting GF pattern matches...${RESETCOLOR}"

patterns=(xss sqli lfi rce ssrf redirect debug interestingparams interestingsubs upload ssti s3 bucket idor cors)
for pattern in "${patterns[@]}"; do
    cat "$output_dir/merged_files.txt" | gf "$pattern" > "$output_dir/gf_${pattern}_results.txt"
done

end_time=$(date)
echo -e "${GREENCOLOR}[+] Subdomain Enumeration Completed!${RESETCOLOR}"
echo -e "${BLUECOLOR}Started at: $start_time${RESETCOLOR}"
echo -e "${BLUECOLOR}Finished at: $end_time${RESETCOLOR}"
