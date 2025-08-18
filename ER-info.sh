#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# ER-info — Termux tool for Website → IP lookups
# Author: ER-info
# License: MIT
# Description:
#   • Resolve single domain to IPv4/IPv6 (A/AAAA)
#   • Show CNAME, NS and WHOIS snippet
#   • Bulk resolve from file → CSV output
#   • Reverse lookup (IP → PTR hostname)
#   • Ping test
#   • Traceroute
# ================================================================

set -Eeuo pipefail

# -------- Colors --------
if command -v tput >/dev/null 2>&1; then
  C_RED="$(tput setaf 1)"; C_GRN="$(tput setaf 2)"; C_YLW="$(tput setaf 3)";
  C_BLU="$(tput setaf 4)"; C_MAG="$(tput setaf 5)"; C_CYN="$(tput setaf 6)";
  C_WHT="$(tput setaf 7)"; C_DIM="$(tput dim)"; C_RST="$(tput sgr0)"; C_BLD="$(tput bold)"
else
  C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_MAG=""; C_CYN=""; C_WHT=""; C_DIM=""; C_RST=""; C_BLD=""
fi

# -------- Utility helpers --------
err()  { echo -e "${C_RED}[!]${C_RST} $*" >&2; }
ok()   { echo -e "${C_GRN}[✓]${C_RST} $*"; }
info() { echo -e "${C_CYN}[-]${C_RST} $*"; }
die()  { err "$*"; exit 1; }

# Colors
C_RST='\033[0m'   # Reset
C_BLD='\033[1m'   # Bold
C_RED='\033[31m'
C_GRN='\033[32m'
C_YLW='\033[33m'
C_BLU='\033[34m'
C_MAG='\033[35m'
C_CYN='\033[36m'

# Validate a domain
valid_domain(){
  local d="$1"
  [[ "$d" =~ ^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$ ]]
}

# Validate IPv4/IPv6
valid_ip(){
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$ip" =~ ^[0-9a-fA-F:]+$ ]]
}

# Dependencies
needed_packages(){
  local pkgs=()
  command -v dig        >/dev/null 2>&1 || pkgs+=(dnsutils)
  command -v whois      >/dev/null 2>&1 || pkgs+=(whois)
  command -v traceroute >/dev/null 2>&1 || pkgs+=(traceroute)
  command -v ping       >/dev/null 2>&1 || pkgs+=(iputils)
  printf '%s\n' "${pkgs[@]}" | awk '!seen[$0]++'
}

install_deps(){
  local pkgs; pkgs=$(needed_packages || true)
  if [ -n "${pkgs:-}" ]; then
    info "Installing missing packages: ${pkgs}"
    if command -v pkg >/dev/null 2>&1; then
      yes | pkg update || true
      yes | pkg install -y ${pkgs}
    else
      die "Termux 'pkg' not found. Install dependencies manually."
    fi
  fi
}

# Banner
banner(){
  clear
  echo -e "\e[33m"
  echo "███████╗██████╗       ██╗███╗   ██╗███████╗ ██████╗ "
  echo "██╔════╝██╔══██╗      ██║████╗  ██║██╔════╝██╔═══██╗"
  echo "█████╗  ██████╔╝█████╗██║██╔██╗ ██║█████╗  ██║   ██║"
  echo "██╔══╝  ██╔══██╗╚════╝██║██║╚██╗██║██╔══╝  ██║   ██║"
  echo "███████╗██║  ██║      ██║██║ ╚████║██║     ╚██████╔╝"
  echo "╚══════╝╚═╝  ╚═╝      ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝ "
  echo -e "\e[0m"
  echo
}

pause(){ echo; read -rp "Press ENTER to continue..." _; }

# Single domain resolver
resolve_domain(){
  local domain="$1"
  valid_domain "$domain" || die "Invalid domain: $domain"
  echo -e "${C_BLD}${C_BLU}Query:${C_RST} $domain\n"

  echo -e "${C_MAG}A (IPv4) records:${C_RST}"
  dig +short A "$domain" | sed '/^$/d' | nl -ba || true

  echo -e "\n${C_MAG}AAAA (IPv6) records:${C_RST}"
  dig +short AAAA "$domain" | sed '/^$/d' | nl -ba || true

  echo -e "\n${C_MAG}CNAME chain:${C_RST}"
  dig +short CNAME "$domain" | sed '/^$/d' | nl -ba || true

  echo -e "\n${C_MAG}NS (Nameservers):${C_RST}"
  dig +short NS "$domain" | sed '/^$/d' | nl -ba || true

  echo -e "\n${C_MAG}WHOIS (registrar snippet):${C_RST}"
  whois "$domain" 2>/dev/null | sed -n '1,40p' || true
}

# Bulk resolve
bulk_resolve(){
  local file="$1"
  [ -f "$file" ] || die "File not found: $file"
  local out="ER-info-results.csv"
  echo "domain,ipv4_list,ipv6_list" > "$out"
  while IFS= read -r domain || [ -n "$domain" ]; do
    [ -z "$domain" ] && continue
    if valid_domain "$domain"; then
      local ipv4 ipv6
      ipv4=$(dig +short A "$domain" | paste -sd ';' -)
      ipv6=$(dig +short AAAA "$domain" | paste -sd ';' -)
      echo "$domain,$ipv4,$ipv6" >> "$out"
      ok "Resolved $domain"
    else
      err "Skipping invalid domain: $domain"
    fi
  done < "$file"
  echo; ok "Saved CSV: $out"
}

# Reverse lookup
reverse_lookup(){
  local ip="$1"
  valid_ip "$ip" || die "Invalid IP: $ip"
  echo -e "${C_MAG}PTR (reverse DNS):${C_RST}"
  dig +short -x "$ip" | sed '/^$/d' | nl -ba || true
}

# Ping
ping_test(){
  local target="$1"
  [ -n "$target" ] || die "Target required"
  info "Sending 4 echo requests"
  ping -c 4 "$target" || true
}

# Traceroute
trace_path(){
  local target="$1"
  [ -n "$target" ] || die "Target required"
  traceroute -n "$target" || true
}

# About
about(){
  echo -e "${C_BLD}ER-info${C_RST} — DNS & network lookups for Termux"
  echo "Features: domain→IP (A/AAAA), CNAME, NS, WHOIS, bulk CSV, reverse lookup, ping, traceroute."
  echo "Bulk file format: one domain per line."
  echo "CSV saved as ER-info-results.csv in current directory."
}

# Menu
menu(){
  while true; do
    banner
    echo -e "${C_BLD}${C_YLW}Main Menu${C_RST}\n"
    echo -e "${C_YLW}≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠${C_RST}"
    echo -e "${C_BLU}1) Resolve single domain → IP${C_RST}\n"
    echo -e "${C_BLU}2) Bulk resolve from file (one domain per line)${C_RST}\n"
    echo -e "${C_BLU}3) Reverse lookup (IP → Hostname)${C_RST}\n"
    echo -e "${C_BLU}4) Ping test${C_RST}\n"
    echo -e "${C_BLU}5) Traceroute${C_RST}\n"
    echo -e "${C_MAG}6) About${C_RST}\n"
    echo -e "${C_RED}0) Exit${C_RST}\n"
    echo -e "${C_YLW}≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠≠${C_RST}"
    read -rp "Select an option: " opt
    case "$opt" in
      1) read -rp "Enter domain: " d; clear; resolve_domain "$d"; pause ;;
      2) read -rp "Path to file: " f; clear; bulk_resolve "$f"; pause ;;
      3) read -rp "Enter IP (v4/v6): " ip; clear; reverse_lookup "$ip"; pause ;;
      4) read -rp "Target (domain or IP): " t; clear; ping_test "$t"; pause ;;
      5) read -rp "Target (domain or IP): " t; clear; trace_path "$t"; pause ;;
      6) clear; about; pause ;;
      0) echo "Bye!"; exit 0 ;;
      *) err "Invalid option"; sleep 1 ;;
    esac
  done
}

trap 'echo -e "\n${C_DIM}Interrupted. Exiting...${C_RST}"; exit 130' INT

install_deps
menu
