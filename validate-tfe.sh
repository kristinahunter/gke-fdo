#!/bin/bash
set -e

# Get Terraform outputs
TFE_HOSTNAME=$(terraform output -raw tfe_hostname)
# Try to get the zone name from Terraform if available
DNS_ZONE=$(terraform output -raw dns_zone_name 2>/dev/null || echo "")

# If DNS_ZONE is empty, try to extract it from TFE_HOSTNAME in a different way
if [ -z "$DNS_ZONE" ]; then
  # Get just the domain without the subdomain
  DOMAIN=$(echo $TFE_HOSTNAME | cut -d. -f2-)
  
  # List all DNS zones and try to find a matching one
  echo "Looking for matching DNS zone..."
  DNS_ZONE=$(gcloud dns managed-zones list --format="value(name)" --filter="dnsName:$DOMAIN." | head -1)
fi

# Get LoadBalancer IP
echo "Getting LoadBalancer IP..."
LB_IP=$(kubectl -n terraform-enterprise get svc terraform-enterprise -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$LB_IP" ]; then
  echo "WARNING: LoadBalancer IP not yet available. Run this command to get it when ready:"
  echo "  kubectl -n terraform-enterprise get svc terraform-enterprise -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
else
  echo "LoadBalancer IP: $LB_IP"
  echo ""
  
  if [ -z "$DNS_ZONE" ]; then
    echo "Could not determine DNS zone automatically."
    echo "Please run the following command with your DNS zone name:"
    echo "  gcloud dns record-sets update $TFE_HOSTNAME. --rrdatas=$LB_IP --ttl=300 --type=A --zone=YOUR_ZONE_NAME"
  else
    echo "Update your DNS A record with:"
    echo "  gcloud dns record-sets update $TFE_HOSTNAME. --rrdatas=$LB_IP --ttl=300 --type=A --zone=$DNS_ZONE"
  fi
  echo ""
fi

# Get pod name
TFEPOD=$(kubectl -n terraform-enterprise get pods -o name | grep terraform-enterprise | head -1 | cut -d'/' -f2)
if [ -z "$TFEPOD" ]; then
  echo "ERROR: Cannot find TFE pod"
  exit 1
fi

# Generate admin token
echo "Generating initial admin token..."
ADMIN_TOKEN=$(kubectl -n terraform-enterprise exec $TFEPOD -- tfectl admin token)
if [ -z "$ADMIN_TOKEN" ]; then
  echo "ERROR: Failed to generate admin token"
  exit 1
fi

echo "Initial admin token generated: $ADMIN_TOKEN"
echo ""
echo "To complete setup, visit:"
echo "https://$TFE_HOSTNAME/admin/account/new?token=$ADMIN_TOKEN"
echo ""
echo "Validation complete!"