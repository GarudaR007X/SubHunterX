#!/bin/bash

# Set strict error handling
set -euo pipefail

# Check if domain argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain> [wordlist] [resolvers] [nuclei-templates] [config]"
    exit 1
fi

# Variables with proper quoting and SubHunterX format
domain="$1"
wordlist="${2:-"~/subhunterx/assets/fuzz.txt"}"
reso="${3:-"~/subhunterx/assets/dnsresolvers.txt"}"
nuclei_templates="${4:-"~/nuclei-templates"}"
config_file="${5:-"~/subhunterx/config/config.ini"}"
output_dir="$HOME/Desktop/${domain}"
chaos_api=""

# Colors with proper quoting
REDCOLOR='\e[31m'
GREENCOLOR='\e[32m'
YELLOWCOLOR='\e[33m'
BLUECOLOR='\e[34m'
RESETCOLOR='\e[0m'  # Added reset color

# Start time for execution tracking
start_time=$(date +%s)

# Tool check with proper array handling
tools=(amass subfinder findomain assetfinder sublist3r unfurl httpx nmap whatweb ffuf waybackurls gau paramspider nuclei nikto sqlmap xsstrike commix gospider subjs crtsh naabu katana chaos shuffledns masscan pandoc linkfinder dalfox arjun github-subdomains)
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo "$tool is not installed. Please install it and try again."
        exit 1
    fi
done

# Create output directory with error handling
mkdir -p "$output_dir" || { echo "Failed to create output directory"; exit 1; }

# Subdomain Enumeration (Parallel Execution)
echo -e "${REDCOLOR}[+] Enumerating subdomains...${RESETCOLOR}"

amass enum  -silent -config "$config_file" -d "$domain" -o "$output_dir/amass.txt" & 
subfinder  -d "$domain" -o "$output_dir/subfinder.txt" & 
findomain -t "$domain" --quiet | tee -a "$output_dir/findomain.txt" & 
assetfinder -subs-only "$domain" | tee -a "$output_dir/assetfinder.txt" & 
sublist3r -d "$domain" -o "$output_dir/sublist3r.txt" &  
chaos -key "$chaos_api" -d "$domain" -o "$output_dir/chaos.txt" & 
crtsh -d "$domain" | tee -a "$output_dir/crtsh.txt"
github-subdomains -d "$domain" -t "$GITHUB_TOKEN" -o "$output_dir/github_subdomains.txt"
wait


 
    

# Combine and sort subdomains with error handling
if ! cat "$output_dir"/*.txt | sort -u > "$output_dir/all_subdomains.txt"; then
    echo "Failed to combine subdomain files"
    exit 1
fi

# Live Subdomain Detection
echo -e "${GREENCOLOR}[+] Detecting live subdomains...${RESETCOLOR}"
httpx -l "$output_dir/all_subdomains.txt" -silent -threads 300 -o "$output_dir/live_subdomains.txt"

# GoSpider Web Crawling
echo -e "${BLUECOLOR}[+] Crawling live subdomains with GoSpider...${RESETCOLOR}"
gospider -S "$output_dir/live_subdomains.txt" -o "$output_dir/gospider_output" -t 10

# Enhanced Subdomain Enumeration with ShuffleDNS
echo -e "${YELLOWCOLOR}[+] Running ShuffleDNS for subdomain enumeration...${RESETCOLOR}"
shuffledns -d "$domain" -list "$output_dir/all_subdomains.txt" -r "$reso" -o "$output_dir/shuffledns.txt"

# Directory and File Bruteforcing
echo -e "${REDCOLOR}[+] Running directory and file enumeration tools...${RESETCOLOR}"
ffuf -w "$wordlist" -u "https://FUZZ.$domain" -o "$output_dir/ffuf.txt" &
gobuster dir -u "https://$domain" -w "$wordlist" -o "$output_dir/gobuster.txt" &
if ! python3 dirsearch.py -u "https://$domain" -w "$wordlist" -o "$output_dir/dirsearch.txt"; then
    echo "Warning: Dirsearch failed"
fi
wait

# Port Scanning (Parallel Execution)
echo -e "${REDCOLOR}[+] Running port scans...${RESETCOLOR}"
masscan -iL "$output_dir/live_subdomains.txt" -p1-65535 --rate 1000 -oG "$output_dir/masscan.txt" &
nmap -iL "$output_dir/live_subdomains.txt" -sV -sC -oA "$output_dir/nmap_scan" &
wait

# Shodan API Integration with error handling
echo -e "${REDCOLOR}[+] Querying Shodan...${RESETCOLOR}"
while IFS= read -r subdomain; do
    ip=$(dig +short "$subdomain") || continue
    if [[ -n "$ip" ]]; then
        echo -e "${YELLOWCOLOR}[+] Querying Shodan for IP: $ip...${RESETCOLOR}"
        if ! shodan host "$ip" > "$output_dir/shodan_${ip}.txt"; then
            echo "Warning: Shodan query failed for $ip"
        fi
    fi
done < "$output_dir/live_subdomains.txt"

# Web Application Fingerprinting
echo -e "${YELLOWCOLOR}[+] Fingerprinting web technologies...${RESETCOLOR}"
whatweb -i "$output_dir/live_subdomains.txt" --no-errors --log-verbose="$output_dir/whatweb.txt"

# Endpoint Discovery
echo -e "${GREENCOLOR}[+] Discovering endpoints...${RESETCOLOR}"
while IFS= read -r domain; 
    waybackurls "$domain" >> "$output_dir/waybackurls.txt"
    gau "$domain" >> "$output_dir/gau.txt"
done < "$output_dir/live_subdomains.txt"
katana -t "$domain" -o "$output_dir/katana.txt"

# JavaScript Analysis
echo -e "${BLUECOLOR}[+] Analyzing JavaScript...${RESETCOLOR}"
if ! cat "$output_dir/live_subdomains.txt" | subjs | tee "$output_dir/subjs.txt"; then
    echo "Warning: SubJS analysis failed"
fi
linkfinder -i "$output_dir/subjs.txt" -o "$output_dir/linkfinder.txt"

# Parameter Discovery using Arjun
echo -e "${BLUECOLOR}[+] Discovering parameters...${RESETCOLOR}"
arjun -i "$domain" -o "$output_dir/arjun_parameters.json"

# API Endpoint Identification (Without testing APIs)
echo -e "${YELLOWCOLOR}[+] Identifying API endpoints...${RESETCOLOR}"
{
    grep -i "api" "$output_dir/waybackurls.txt" "$output_dir/gau.txt" "$output_dir/katana.txt" || true
} | sort -u > "$output_dir/api_endpoints.txt"

# Vulnerability Scanning with error handling
echo -e "${YELLOWCOLOR}[+] Running vulnerability scans...${RESETCOLOR}"
nuclei -l "$output_dir/live_subdomains.txt" -t "$nuclei_templates/cves/" -o "$output_dir/cves.txt"
nuclei -l "$output_dir/live_subdomains.txt" -t "$nuclei_templates/vulnerabilities/" -o "$output_dir/vulnerabilities.txt"
nikto -h "$output_dir/live_subdomains.txt" -output "$output_dir/nikto.txt"
sqlmap -m "$output_dir/live_subdomains.txt" --batch --output-dir="$output_dir/sqlmap"
xsstrike -u "$output_dir/live_subdomains.txt" --output "$output_dir/xsstrike.txt"

# Automated Exploitation
echo -e "${REDCOLOR}[+] Running automated exploitation...${RESETCOLOR}"
commix -m "$output_dir/live_subdomains.txt" --output-dir="$output_dir/commix"

# Report Generation with error handling
echo -e "${GREENCOLOR}[+] Generating report...${RESETCOLOR}"
{
    echo "# Bug Bounty Report for $domain"
    echo "## Live Subdomains"
    cat "$output_dir/live_subdomains.txt"
    echo "## API Endpoints"
    cat "$output_dir/api_endpoints.txt"
    echo "## Non-API Endpoints"
    cat "$output_dir/non_api_endpoints.txt"
    echo "## Shodan Results"
    cat "$output_dir"/shodan_*.txt || true
    echo "## Vulnerabilities"
    cat "$output_dir/cves.txt" "$output_dir/vulnerabilities.txt" || true
    echo "## Exploitation Results"
    cat "$output_dir/commix/results.txt" || true
} > "$output_dir/report.md"

# Convert report to PDF
echo -e "${BLUECOLOR}[+] Converting report to PDF...${RESETCOLOR}"
if ! pandoc "$output_dir/report.md" -o "$output_dir/report.pdf"; then
    echo "Warning: PDF conversion failed"
fi

# End time and duration calculation
end_time=$(date +%s)
duration=$((end_time - start_time))
echo -e "${GREENCOLOR}[+] Script completed in ${duration} seconds.${RESETCOLOR}"
