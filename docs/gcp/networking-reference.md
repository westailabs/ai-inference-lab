# GCP Networking — Quick Reference

## Health Check IP Ranges

GCP load balancers send health probes from **fixed IP ranges**. You must whitelist these in your firewall rules or the LB marks all backends as unhealthy.

| Range | Purpose |
|-------|---------|
| `130.211.0.0/22` | Legacy health check probes |
| `35.191.0.0/16` | Current health check probes |

**Documentation:** https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges

**Interview answer:** "GCP load balancers use dedicated IP ranges for health probes. You have to explicitly allow those source ranges through your firewall, otherwise the LB thinks your backends are down. It's a common gotcha with deny-all firewall policies."

---

## Private Google Access

Allows resources in a subnet to reach Google APIs (Cloud Storage, Secret Manager, etc.) **without needing external IP addresses**. Reduces attack surface.

**Enable on subnet:**
```hcl
private_ip_google_access = true
```

**Documentation:** https://cloud.google.com/vpc/docs/configure-private-google-access

---

## Serverless VPC Connector

Cloud Run runs **outside your VPC** by default. The VPC connector gives it a path into your private network.

- Minimum CIDR: `/28` (16 IPs)
- Uses f1-micro instances (cheapest)
- Required for Cloud Run → private resources

**Documentation:** https://cloud.google.com/vpc/docs/configure-serverless-vpc-access

---

## RFC 1918 Private IP Ranges

Standard private ranges — use these for all internal subnets:

| Range | Size | Common Use |
|-------|------|-----------|
| `10.0.0.0/8` | 16M addresses | Large orgs, GCP default |
| `172.16.0.0/12` | 1M addresses | Mid-size |
| `192.168.0.0/16` | 65K addresses | Small/home networks |

**Sizing guide:**
- `/24` = 254 usable hosts (good default for subnets)
- `/28` = 14 usable hosts (minimum for VPC connectors)
- `/16` = 65,534 hosts (regional allocation)

---

## Key GCP Networking Docs

- **VPC Overview:** https://cloud.google.com/vpc/docs/overview
- **Firewall Rules:** https://cloud.google.com/firewall/docs/firewalls
- **Cloud Run Networking:** https://cloud.google.com/run/docs/securing/private-networking
- **Load Balancing:** https://cloud.google.com/load-balancing/docs/load-balancing-overview
- **Subnet Design Best Practices:** https://cloud.google.com/architecture/best-practices-vpc-design
