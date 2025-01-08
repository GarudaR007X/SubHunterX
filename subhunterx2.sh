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
nuclei_templates="${4:-"$HOME/nuclei-templates"}"
output_dir="/root/Desktop/${domain}"


# Colors with proper quoting
REDCOLOR='\e[31m'
GREENCOLOR='\e[32m'
YELLOWCOLOR='\e[33m'
BLUECOLOR='\e[34m'
RESETCOLOR='\e[0m'  

# Tool check with proper array handling
tools=(amass subfinder findomain assetfinder sublist3r unfurl httpx nmap whatweb ffuf waybackurls gau paramspider nuclei nikto sqlmap xsstrike commix gospider subjs crtsh naabu katana chaos shuffledns masscan pandoc linkfinder dalfox arjun gobuster github-subdomains)
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
amass enum -active -d "$domain" -config "$AMASS_CONFIG" -o "$output_dir/amass.txt" &


# Subfinder
echo -e "${BLUECOLOR}[+] Running Subfinder...${GREENCOLOR}"
subfinder -d "$domain" -o "$output_dir/subfinder.txt" &

# Findomain
echo -e "${BLUECOLOR}[+] Running Findomain...${GREENCOLOR}"
findomain -t shaadi.com --quiet >> "$output_dir/findomain.txt" &

# Assetfinder
echo -e "${BLUECOLOR}[+] Running Assetfinder...${GREENCOLOR}"
assetfinder -subs-only "$domain" | tee -a "$output_dir/assetfinder.txt" &

# Sublist3r
echo -e "${BLUECOLOR}[+] Running Sublist3r...${GREENCOLOR}"
python3 -W ignore /usr/local/bin/sublist3r -d "$domain" -e baidu,yahoo,google,bing,ask,netcraft,dnsdumpster,threatcrowd,ssl,passivedns -o "$output_dir/sublist3r.txt" &

# Chaos
echo -e "${BLUECOLOR}[+] Running Chaos...${GREENCOLOR}"
chaos -key "$CHAOS_API_KEY" -d "$domain" -o "$output_dir/chaos.txt" &

# CRTSH
echo -e "${BLUECOLOR}[+] Running CRTSH...${GREENCOLOR}"
crtsh -d "$domain" >> "$output_dir/crtsh.txt" &

# GitHub Subdomains
echo -e "${BLUECOLOR}[+] Running GitHub Subdomains...${GREENCOLOR}"
github-subdomains -d "$domain" -t "$GITHUB_TOKEN" -o "$output_dir/github_subdomains.txt" &

# Gobuster - Subdomain Brute-forcing
echo -e "${BLUECOLOR}[+] Running Gobuster...${GREENCOLOR}"

gobuster dns -d "$domain" -w "$WORDLIST" -o "$output_dir/gobuster.txt" -t 100 --delay 500ms &

# DNSRecon - Active Mode (Brute-forcing)
echo -e "${BLUECOLOR}[+] Running DNSRecon...${GREENCOLOR}"
dnsrecon -d "$domain" -t brt -w "$WORDLIST" -o "$output_dir/dnsrecon.txt" &

wait



# Combine and sort subdomains, excluding one file
echo -e "${REDCOLOR}[+] Merging and sorting subdomain files...$
{RESETCOLOR}"
grep -oP '\b[A-Za-z0-9.-]+'"$tld"'\b' "$output_dir/amass.txt" > "$output_dir/amasssubdomains.txt" 

grep -oP '\b[a-z0-9.-]+\b' "$output_dir/gobuster.txt" | sort -u > "$output_dir/cleaned_gobuster_subdomains.txt"

find "$output_dir" -type f -name "*.txt" ! -name "amass.txt gobuster.txt" -exec cat {} + | sort -u > "$output_dir/all_subdomains.txt"

# Resolve Subdomains with Shuffledns
echo -e "${YELLOWCOLOR}[+] Resolving subdomains with Shuffledns...${RESETCOLOR}"
shuffledns -list "$output_dir/all_subdomains.txt" -r "$RESOLVERS" -o "$output_dir/resolved_subdomains.txt"

# Checking live subdomains with httpx
echo -e "${REDCOLOR}[+] Checking for live subdomains...${RESETCOLOR}"
httpx -l "$output_dir/resolved_subdomains.txt" -o "$output_dir/live_subdomains.txt" -silent -threads 300 -mc 200,301,302,403,404,500,502,503

# Finding APIs from all subdomains 
echo -e "$REDCOLOR [+] Finding APIs...${RESETCOLOR}"
cat "$output_dir/live_subdomains.txt" | grep api | tee "$output_dir/api.txt"
uniq "$output_dir/api.txt" > "$output_dir/finalapi.txt"

# Discover endpoints with Katana
echo -e "${REDCOLOR}[+] Crawling with Katana...${RESETCOLOR}"
katana -list "$output_dir/live_subdomains.txt" -o "$output_dir/katana_output.txt" -d 3 --json
grep -E "\.js|\.json|\.php|\.xml|\.txt|\.env|api" "$output_dir/katana_output.txt" > "$output_dir/katana_filtered.txt"

#  GoSpider Web Crawling
echo -e "${REDCOLOR}[+] Web Crawling Started..${RESETCOLOR}"
gospider -S "$output_dir/live_subdomains.txt" -o "$output_dir/gospider_output.txt" -t 10 -j -u -d 3 --include ".js,.json,.php,.xml,.txt,.env"
grep -E "\.js|\.json|\.php|\.xml|\.txt|\.env" "$output_dir/gospider_output.txt" > "$output_dir/go_extracted_files.txt"

#  Directory and File Bruteforcing
echo -e "${REDCOLOR}[+] Running Directory Brute-forcing...${RESETCOLOR}"

# FFUF Command (for directory bruteforce)
ffuf -u "https://FUZZ.$domain" -w "$WORDLISTS" -mc 200,301,403 -t 50 -o "$output_dir/ffuf_output.txt"


# Gobuster Command (for directory bruteforce)
gobuster dir -u "$output_dir/live_subdomains.txt" -w "$wordlist" -o "$output_dir/gobuster_output.txt" -s "200,301,403"

# Combine the Results from both tools
cat "$output_dir/ffuf_output.txt" "$output_dir/gobuster_output.txt" | sort -u > "$output_dir/combined_bruteforce.txt"

#  LinkFinder (Extract links from GoSpider output)
echo -e "${REDCOLOR}[+] Extracting JavaScript and API links with LinkFinder...${RESETCOLOR}"
linkfinder -i "$output_dir/gospider_output.txt" -o "$output_dir/all_links.txt"
grep -E "\.js|\.json|\.php" "$output_dir/all_links.txt" > "$output_dir/filtered_links.txt"

#  Arjun (Parameter Discovery)
echo -e "${REDCOLOR}[+] Discovering parameters with Arjun...${RESETCOLOR}"
arjun -i "$output_dir/filtered_links.txt" -o "$output_dir/params.txt"

# 5. Merge go_extracted_files.txt and combined_bruteforce.txt
cat "$output_dir/katana_filtered.txt" "$output_dir/go_extracted_files.txt" "$output_dir/combined_bruteforce.txt" "$output_dir/filtered_links.txt" "$output_dir/params.txt" | sort -u > "$output_dir/merged_files.txt"

