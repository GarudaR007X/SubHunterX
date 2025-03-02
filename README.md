# SubHunterX 🎯

An advanced bug bounty automation framework designed for efficient security assessments and reconnaissance.

## 🚀 Features

- Comprehensive subdomain enumeration using multiple tools
- Parallel execution for improved performance
- Live subdomain validation and web crawling
- Advanced web application fingerprinting
- API endpoint discovery and analysis
- Directory and file bruteforcing
- GF pattern matching for vulnerability identification
- DNS resolution and IP mapping
- Robust error handling and logging

## 🛠️ Prerequisites

### Core Tools
- Amass
- Subfinder
- Findomain
- Assetfinder
- Sublist3r
- HTTPx
- FFuf
- Waybackurls
- GAU
- Gobuster
- ShuffleDNS
- Massdns
- Katana
- Chaos
- DNSx
- GF

### Environment Requirements
- AMASS_CONFIG - Configuration file for Amass
- CHAOS_API_KEY - API key for Chaos
- RESOLVERS - DNS resolvers list
- WORDLISTS - Wordlist for bruteforcing

## 📥 Installation

```bash
https://github.com/0xayushc/SubHunterX
cd SubHunterX 
```
## 🚀 Usage
### Basic usage:
```Bash
./subhunterx.sh <domain>
```
## 🔍 Features Breakdown
- Subdomain Enumeration
- Active enumeration using Amass
- Passive enumeration using Subfinder, Findomain, Assetfinder, Sublist3r
- DNS bruteforcing with Gobuster
- Additional enumeration through Chaos
- DNS Resolution & Validation
- Subdomain resolution using ShuffleDNS and Massdns
- Live subdomain validation with HTTPx
- IP address mapping with DNSx
- Web Crawling & Discovery
- Comprehensive crawling with Katana
- API endpoint discovery
- Directory bruteforcing with FFuf
- Pattern matching using GF for:
  - XSS vulnerabilities
  - SQL injection
  - Local File Inclusion
  -  Remote Code Execution
  - SSRF
  - Open Redirects
### Output Organization
- Structured output directory: `/root/Desktop/<domain>/`
- Separate files for each tool's results
- Merged and deduplicated findings
- Filtered outputs for specific vulnerability types
## 🤝 Contributing
- Contributions are welcome! Please feel free to submit pull requests.

## 📝 License
- This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer
- This tool is for educational and authorized testing purposes only. Always obtain proper authorization before testing any systems.

## 🌟 Acknowledgments
- Thanks to all the amazing open-source tools that make this framework possible.
