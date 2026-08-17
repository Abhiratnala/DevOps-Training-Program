#!/bin/bash
set -e

#############################################
# VPC AUDIT + NGINX LOG ANALYSIS SCRIPT
#############################################

# AWS Configuration
REGION="us-east-1"

# Files
AUDIT_LOG="/var/log/vpc_audit.log"
ACCESS_LOG="/var/log/nginx/access.log"

OUTPUT_DIR="/var/log/vpc_reports"

#############################################
# CREATE OUTPUT DIRECTORY
#############################################

mkdir -p $OUTPUT_DIR


#############################################
# FUNCTION: AUDIT NAT GATEWAY
#############################################

audit_nat() {

echo "====================================" >> $AUDIT_LOG
echo "$(date) NAT Gateway Audit" >> $AUDIT_LOG
echo "====================================" >> $AUDIT_LOG


aws ec2 describe-nat-gateways \
--region $REGION \
--query "NatGateways[*].[NatGatewayId,State,VpcId,SubnetId]" \
--output table >> $AUDIT_LOG


echo "" >> $AUDIT_LOG

}



#############################################
# FUNCTION: AUDIT EC2 INSTANCES
#############################################

audit_instances() {


echo "====================================" >> $AUDIT_LOG
echo "$(date) EC2 Instance Audit" >> $AUDIT_LOG
echo "====================================" >> $AUDIT_LOG


aws ec2 describe-instances \
--region $REGION \
--query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]" \
--output table >> $AUDIT_LOG


echo "" >> $AUDIT_LOG

}



#############################################
# FUNCTION: NGINX LOG ANALYSIS
#############################################

analyze_logs() {


if [ ! -f "$ACCESS_LOG" ]; then

    echo "No nginx access log found: $ACCESS_LOG"

    return

fi



REPORT="$OUTPUT_DIR/nginx_report.txt"


echo "====================================" > $REPORT
echo "$(date) NGINX ACCESS LOG REPORT" >> $REPORT
echo "====================================" >> $REPORT



#############################################
# TOTAL REQUESTS
#############################################

echo "" >> $REPORT
echo "TOTAL REQUESTS" >> $REPORT

wc -l $ACCESS_LOG >> $REPORT



#############################################
# UNIQUE IP COUNT
#############################################

echo "" >> $REPORT
echo "UNIQUE IP COUNT" >> $REPORT

awk '{print $1}' $ACCESS_LOG \
| sort \
| uniq \
| wc -l >> $REPORT



#############################################
# TOP 5 REQUESTING IPs
#############################################

echo "" >> $REPORT
echo "TOP 5 REQUESTING IPS" >> $REPORT


awk '{print $1}' $ACCESS_LOG \
| sort \
| uniq -c \
| sort -nr \
| head -5 >> $REPORT



#############################################
# HTTP 500 ERRORS
#############################################

echo "" >> $REPORT
echo "HTTP 500 RESPONSES" >> $REPORT


grep " 500 " $ACCESS_LOG >> $REPORT || true



#############################################
# REDACT IP ADDRESSES
#############################################

echo "" >> $REPORT
echo "Creating redacted log..."


sed -E \
's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[REDACTED]/g' \
$ACCESS_LOG \
> $OUTPUT_DIR/access_redacted.log



echo "Redacted log:"
echo "$OUTPUT_DIR/access_redacted.log" >> $REPORT



}



#############################################
# MAIN EXECUTION
#############################################


echo "Starting VPC audit..."

audit_nat

audit_instances

analyze_logs


echo "Audit completed at $(date)" >> $AUDIT_LOG

echo "DONE"
