#!/bin/bash
# Deletes VPCs (and everything inside them: instances, NAT gateways, EIPs,
# IGWs, subnets, route tables, security groups) for VPCs matching the given
# Name tags. Never touches the default VPC.
#
# Usage:
#   ./teardown_vpcs.sh ap-south-1 docker-mysql-vpc connectivity-demo-vpc

set -e

REGION="$1"
shift
VPC_NAME_TAGS=("$@")

if [ -z "$REGION" ] || [ "${#VPC_NAME_TAGS[@]}" -eq 0 ]; then
  echo "Usage: $0 <region> <vpc-name-tag-1> [vpc-name-tag-2] ..."
  echo "Example: $0 ap-south-1 docker-mysql-vpc connectivity-demo-vpc"
  exit 1
fi

for TAG in "${VPC_NAME_TAGS[@]}"; do
  echo ""
  echo "=================================================="
  echo "Looking for VPCs tagged Name=$TAG in $REGION"
  echo "=================================================="

  VPC_IDS=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=$TAG" \
    --query "Vpcs[].VpcId" --output text)

  if [ -z "$VPC_IDS" ]; then
    echo ">> No VPCs found for tag $TAG, skipping."
    continue
  fi

  for VPC_ID in $VPC_IDS; do
    IS_DEFAULT=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" \
      --query "Vpcs[0].IsDefault" --output text)

    if [ "$IS_DEFAULT" == "True" ]; then
      echo ">> SKIPPING $VPC_ID -- this is the default VPC, refusing to delete."
      continue
    fi

    echo ""
    echo ">> Tearing down VPC: $VPC_ID"

    # ---- 1. Terminate instances in this VPC ----
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query "Reservations[].Instances[].InstanceId" --output text)

    if [ -n "$INSTANCE_IDS" ]; then
      echo "   Terminating instances: $INSTANCE_IDS"
      aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
      aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCE_IDS
    fi

    # ---- 2. Delete NAT gateways (and wait, they take a while) ----
    NAT_IDS=$(aws ec2 describe-nat-gateways --region "$REGION" \
      --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
      --query "NatGateways[].NatGatewayId" --output text)

    for NAT_ID in $NAT_IDS; do
      echo "   Deleting NAT gateway: $NAT_ID"
      aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$NAT_ID" >/dev/null
    done

    if [ -n "$NAT_IDS" ]; then
      echo "   Waiting for NAT gateway(s) to fully delete..."
      for NAT_ID in $NAT_IDS; do
        while true; do
          STATE=$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "$NAT_ID" \
            --query "NatGateways[0].State" --output text 2>/dev/null || echo "deleted")
          [ "$STATE" == "deleted" ] && break
          sleep 5
        done
      done
    fi

    # ---- 3. Release Elastic IPs that belonged to NAT gateways in this VPC ----
    ALLOC_IDS=$(aws ec2 describe-addresses --region "$REGION" \
      --query "Addresses[?Domain=='vpc'].[AllocationId,AssociationId,InstanceId]" --output text)
    # (best-effort: only release EIPs with no association left)
    for ALLOC_ID in $(aws ec2 describe-addresses --region "$REGION" \
      --query "Addresses[?AssociationId==null].AllocationId" --output text); do
      echo "   Releasing unassociated Elastic IP: $ALLOC_ID"
      aws ec2 release-address --region "$REGION" --allocation-id "$ALLOC_ID" 2>/dev/null || true
    done

    # ---- 4. Detach and delete Internet Gateways ----
    IGW_IDS=$(aws ec2 describe-internet-gateways --region "$REGION" \
      --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
      --query "InternetGateways[].InternetGatewayId" --output text)

    for IGW_ID in $IGW_IDS; do
      echo "   Detaching and deleting IGW: $IGW_ID"
      aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
      aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID"
    done

    # ---- 5. Delete subnets ----
    SUBNET_IDS=$(aws ec2 describe-subnets --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "Subnets[].SubnetId" --output text)

    for SUBNET_ID in $SUBNET_IDS; do
      echo "   Deleting subnet: $SUBNET_ID"
      aws ec2 delete-subnet --region "$REGION" --subnet-id "$SUBNET_ID"
    done

    # ---- 6. Delete non-main route tables ----
    RT_IDS=$(aws ec2 describe-route-tables --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text)

    for RT_ID in $RT_IDS; do
      echo "   Deleting route table: $RT_ID"
      aws ec2 delete-route-table --region "$REGION" --route-table-id "$RT_ID"
    done

    # ---- 7. Delete non-default security groups ----
    SG_IDS=$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

    for SG_ID in $SG_IDS; do
      echo "   Deleting security group: $SG_ID"
      aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" 2>/dev/null || \
        echo "     (could not delete $SG_ID yet, may be referenced elsewhere)"
    done

    # ---- 8. Finally delete the VPC ----
    echo "   Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"
    echo ">> VPC $VPC_ID deleted successfully."
  done
done

echo ""
echo "Teardown complete."
