#!/bin/bash

# Set strict error handling
set -euo pipefail

# Check if domain argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

# Variables with proper quoting and SubHunterX format
domain="$1"
output_dir="/root/Desktop/${domain}"

# Colors with proper quoting
REDCOLOR='\e[31m'
GREENCOLOR='\e[32m'
YELLOWCOLOR='\e[33m'
BLUECOLOR='\e[34m'
RESETCOLOR='\e[0m'  

# Tool check with proper array handling
tools=(amass subfinder findomain assetfinder sublist3r httpx ffuf waybackurls gau gobuster shuffledns massdns katana chaos dnsx gf)
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo " ${REDCOLOR} $tool is not installed. Please install it and try again.${RESETCOLOR}"
        exit 1
    fi
done

# Create output directory with error handling
mkdir -p "$output_dir" || { echo " ${REDCOLOR} Failed to create output directory"; exit 1; }
tld=$(echo "$domain" | sed 's/^.*\(\.[a-zA-Z0-9]*\.[a-zA-Z]\{2,3\}\)$/\1/')


echo -e "${REDCOLOR}[+] Enumeration of Subdomains with Multiple Tools...${RESETCOLOR}"

# Amass - Active Mode
echo -e "${BLUECOLOR}[+] Running Amass...${GREENCOLOR}"
amass enum -active -d "$domain" -config "$AMASS_CONFIG" -o "$output_dir/amass.txt" 


# Subfinder
echo -e "${BLUECOLOR}[+] Running Subfinder...${GREENCOLOR}"
subfinder -d "$domain" -o "$output_dir/subfinder.txt" 

# Findomain
echo -e "${BLUECOLOR}[+] Running Findomain...${GREENCOLOR}"
findomain -t "$domain" --quiet >> "$output_dir/findomain.txt"

# Assetfinder
echo -e "${BLUECOLOR}[+] Running Assetfinder...${GREENCOLOR}"
assetfinder -subs-only "$domain" | tee -a "$output_dir/assetfinder.txt" 

# Sublist3r
echo -e "${BLUECOLOR}[+] Running Sublist3r...${GREENCOLOR}"
python3 -W ignore /usr/local/bin/sublist3r -d "$domain" -e baidu,yahoo,google,bing,ask,netcraft,dnsdumpster,threatcrowd,ssl,passivedns -o "$output_dir/sublist3r.txt" 

# Chaos
echo -e "${BLUECOLOR}[+] Running Chaos...${GREENCOLOR}"
chaos -key "$CHAOS_API_KEY" -d "$domain" -o "$output_dir/chaos.txt" 

# Gobuster - Subdomain Brute-forcing
echo -e "${BLUECOLOR}[+] Running Gobuster...${GREENCOLOR}"
gobuster dns -d "$domain" -w "$WORDLISTS" -o "$output_dir/gobuster.txt" -t 200 --timeout 2s -r 8.8.8.8

# Combine and sort subdomains, excluding one file
echo -e "${REDCOLOR}[+] Merging and sorting subdomain files...${RESETCOLOR}"
grep -oP '\b[A-Za-z0-9.-]+"$tld"\b' "$output_dir/amass.txt" > "$output_dir/amasssubdomains.txt" 

grep -oP '\b[a-z0-9.-]+\b' "$output_dir/gobuster.txt" | sort -u > "$output_dir/cleaned_gobuster_subdomains.txt"

find "$output_dir" -type f -name "*.txt" ! -name "amass.txt" ! -name "gobuster.txt" -exec cat {} + | sort -u > "$output_dir/all_subdomains.txt"

# Resolve Subdomains with massdns
echo -e "${YELLOWCOLOR}[+] Resolving subdomains with Shuffledns...${RESETCOLOR}"
shuffledns -list "$output_dir/all_subdomains.txt" -r "$RESOLVERS" -o "$output_dir/resolved_subdomains.txt"
massdns -t A -r "$RESOLVERS" -o "$output_dir/mass_resolved_subdomains.txt" "$output_dir/all_subdomains.txt"
grep -Eo '^[^ ]+' "$output_dir/mass_resolved_subdomains.txt" | sed 's/\.$//' > "$output_dir/resolved_subdomains.txt"

# Checking live subdomains with httpx
echo -e "${REDCOLOR}[+] Checking for live subdomains...${RESETCOLOR}"
httpx -l "$output_dir/resolved_subdomains.txt" -o "$output_dir/live_subdomains.txt" -silent -threads 300 -mc 200,301,302,403,404,500,502,503

# Finding APIs from all subdomains 
echo -e "$REDCOLOR [+] Finding APIs...${RESETCOLOR}"
cat "$output_dir/live_subdomains.txt" | grep api | tee "$output_dir/api.txt"
uniq "$output_dir/api.txt" > "$output_dir/finalapi.txt"

# Discover endpoints with Katana
echo -e "${REDCOLOR}[+] Crawling with Katana...${RESETCOLOR}"
katana -list "$output_dir/live_subdomains.txt" -o "$output_dir/katana_output.txt" -d 3 
grep -E "\.js|\.json|\.php|\.xml|\.txt|\.env|api" "$output_dir/katana_output.txt" > "$output_dir/katana_filtered.txt"

#  Directory and File Bruteforcing
echo -e "${REDCOLOR}[+] Running Directory Brute-forcing...${RESETCOLOR}"

# FFUF Command (for directory bruteforce)
ffuf -u "https://FUZZ.$domain" -w "$FUZZ" -mc 200,301,403 -t 50 -o "$output_dir/ffuf_output.txt"
jq -r '.results[] | .url' "$output_dir/ffuf_output.txt" > "$output_dir/ffuf_filtered_urls.txt"
cat "$output_dir/ffuf_filtered_urls.txt"  | sort -u > "$output_dir/bruteforce.txt"

echo -e "${REDCOLOR}[+] Crawling with Katana...${RESETCOLOR}"
katana -list "$output_dir/bruteforce.txt" -o "$output_dir/ffuf_katana_output.txt" -d 3 

cat "$output_dir/katana_filtered.txt" "$output_dir/bruteforce.txt"  "$output_dir/ffuf_katana_output.txt"  | sort -u > "$output_dir/merged_files.txt"

sed 's|https://||g; s|http://||g' "$output_dir/live_subdomains.txt" > "$output_dir/live_subdomains2.txt"
cat "$output_dir/live_subdomains2.txt" | dnsx -resp-only | sort -u | tee "$output_dir/ips.txt"

# Gf Pattrens
echo -e "${REDCOLOR}[+] Finding links using GF patterns...${RESETCOLOR}"

cat "$output_dir/merged_files.txt" | gf xss > "$output_dir/gf_xss_results.txt"
cat "$output_dir/merged_files.txt" | gf sqli > "$output_dir/gf_sqli_results.txt"
cat "$output_dir/merged_files.txt" | gf lfi > "$output_dir/gf_lfi_results.txt"
cat "$output_dir/merged_files.txt" | gf rce > "$output_dir/gf_rce_results.txt"
cat "$output_dir/merged_files.txt" | gf ssrf > "$output_dir/gf_ssrf_results.txt"
cat "$output_dir/merged_files.txt" | gf redirect > "$output_dir/gf_redirect_results.txt"

echo -e "${GREENCOLOR}[+] Subdomain Enmeration is Done....!"