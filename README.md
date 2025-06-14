# Pi-hole SSL Config Script

A robust, user-friendly, and visually appealing Bash script to automate SSL certificate setup for Pi-hole using multiple DNS providers and certificate authorities. Features include dry-run mode, colorized output, interactive guided setup, root/elevation checks, and a fun ASCII art banner.

---

## Features

- **Automated SSL setup** for Pi-hole with support for multiple DNS providers and CAs
- **Interactive mode** (`--init`) for guided, user-friendly configuration
- **Dry-run mode** (`--dry-run`) to preview actions without making changes
- **Colorized output** for clarity and emphasis
- **Root/elevation checks** for safe operation
- **ASCII art banner** combining a padlock and Pi-hole motif
- **Supports Docker and non-Docker Pi-hole installations**

---

## Usage

```sh
sudo ./pihole-ssl-config.sh [OPTIONS]
```

### Common Options

- `--domain DOMAIN`                : Fully qualified domain name to secure (required)
- `--cert-provider PROVIDER`       : Certificate provider: `zerossl` (default) or `letsencrypt`
- `--dns-provider PROVIDER`        : DNS provider: `cloudflare` (default), `namecheap`, `godaddy`, `route53`, `digitalocean`, `linode`, `gcloud`, `desec`
- `--zerossl-email EMAIL`          : Email for ZeroSSL (if using zerossl)
- `--zerossl-key KEY`              : API key for ZeroSSL (if using zerossl)
- `--cf-email EMAIL`               : Cloudflare account email
- `--cf-token TOKEN`               : Cloudflare API token
- `--docker`                       : Enable Docker mode for containerized Pi-hole
- `--docker-container NAME`        : Docker container name (default: pihole)
- `--key-length LENGTH`            : Certificate key length: `ec-256` (default), `2048`, `4096`
- `--dry-run`                      : Show what would be done without executing commands
- `--revert`                       : Revert to last known good configuration
- `--init`                         : Start interactive guided setup
- `--help`                         : Show help message and exit

### Example Commands

```sh
# Basic setup with Cloudflare and ZeroSSL
sudo ./pihole-ssl-config.sh --domain pihole.example.com --cf-email user@example.com --cf-token YOUR_TOKEN

# Setup with Let's Encrypt and Namecheap
sudo ./pihole-ssl-config.sh --domain pihole.example.com --cert-provider letsencrypt --dns-provider namecheap --namecheap-username user --namecheap-key API_KEY

# Docker setup with DigitalOcean
sudo ./pihole-ssl-config.sh --domain pihole.example.com --docker --dns-provider digitalocean --do-token TOKEN

# Dry run to see what would happen
./pihole-ssl-config.sh --domain pihole.example.com --cf-email user@example.com --cf-token YOUR_TOKEN --dry-run

# Interactive guided setup
./pihole-ssl-config.sh --init
```

---

## Interactive Mode (`--init`)

- Prompts for all required options and credentials
- Shows a colorized ASCII art banner
- Prints a ready-to-run command with all selected options (does not execute it)
- Can be run as a normal user (no root required for `--init` or `--dry-run`)

---

## Supported DNS Providers & Credentials

- **Cloudflare**: `--cf-email`, `--cf-token`
- **Namecheap**: `--namecheap-username`, `--namecheap-key`, `--namecheap-sourceip`
- **GoDaddy**: `--godaddy-key`, `--godaddy-secret`
- **AWS Route53**: `--aws-access-key`, `--aws-secret-key`, `--aws-region`
- **DigitalOcean**: `--do-token`
- **Linode**: `--linode-token`
- **Google Cloud**: `--gcp-service-file`
- **deSEC**: `--desec-token`

---

## Requirements

- Bash 4+
- `tput` for color support (optional, but recommended)
- Root privileges for real operations (not required for `--init` or `--dry-run`)
- Pi-hole installed (Docker or native)

---

## Security & Safety

- The script checks for root/elevation before making changes
- Credentials are only used for the duration of the script
- Backups are made before modifying Pi-hole or webserver configs
- Use `--dry-run` to preview all actions safely

---

## Troubleshooting

- If you see color codes instead of colors, ensure your terminal supports ANSI colors and `tput` is available
- For Docker setups, ensure the container name matches your Pi-hole instance
- For DNS API errors, double-check your credentials and permissions

---

## License

MIT License. See `LICENSE` file for details.

---

## Credits

- ASCII art inspired by the Pi-hole and security community
- Script by [Your Name or GitHub handle]

---

## Contributing

Pull requests and suggestions are welcome! Please open an issue or PR for improvements.
