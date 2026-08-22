#!/usr/bin/env bash
INSTANCE_ID="i-0a7585e221c5e2bf0"
REGION="ap-southeast-2"
SNS_TOPIC_ARN="${3:-}"

DASHBOARD_NAME="EC2-Dashboard-${INSTANCE_ID}"
WORK_DIR="$(mktemp -d)"

echo "==> Instance ID: ${INSTANCE_ID}"
echo "==> Region:      ${REGION}"

# If no SNS topic was passed, create one so alarms have somewhere to notify
if [[ -z "${SNS_TOPIC_ARN}" ]]; then
  echo "==> No SNS topic provided, creating one..."
  SNS_TOPIC_ARN="$(aws sns create-topic \
    --name "ec2-alarms-${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'TopicArn' \
    --output text)"
  echo "==> Created SNS topic: ${SNS_TOPIC_ARN}"
  echo "    Subscribe to it for notifications:"
  echo "    aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint you@example.com"
fi

# ---------- Helper to create an alarm ----------
create_alarm () {
  local ALARM_NAME="$1"
  local METRIC_NAME="$2"
  local STATISTIC="$3"
  local THRESHOLD="$4"
  local COMPARISON="$5"
  local UNIT="$6"

  echo "==> Creating alarm: ${ALARM_NAME}"
  aws cloudwatch put-metric-alarm \
    --alarm-name "${ALARM_NAME}" \
    --alarm-description "Alarm on ${METRIC_NAME} for ${INSTANCE_ID}" \
    --namespace "AWS/EC2" \
    --metric-name "${METRIC_NAME}" \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
    --statistic "${STATISTIC}" \
    --period 300 \
    --evaluation-periods 2 \
    --threshold "${THRESHOLD}" \
    --comparison-operator "${COMPARISON}" \
    --unit "${UNIT}" \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --ok-actions "${SNS_TOPIC_ARN}" \
    --region "${REGION}"
}

# ---------- 1. CPUUtilization alarm ----------
ALARM_CPU="High-CPU-${INSTANCE_ID}"
create_alarm "${ALARM_CPU}" "CPUUtilization" "Average" "80" "GreaterThanThreshold" "Percent"

# ---------- 2. NetworkIn alarm ----------
ALARM_NET_IN="High-NetworkIn-${INSTANCE_ID}"
create_alarm "${ALARM_NET_IN}" "NetworkIn" "Average" "50000000" "GreaterThanThreshold" "Bytes"

# ---------- 3. NetworkOut alarm ----------
ALARM_NET_OUT="High-NetworkOut-${INSTANCE_ID}"
create_alarm "${ALARM_NET_OUT}" "NetworkOut" "Average" "50000000" "GreaterThanThreshold" "Bytes"

# ---------- 4. StatusCheckFailed alarm ----------
ALARM_STATUS="StatusCheckFailed-${INSTANCE_ID}"
echo "==> Creating alarm: ${ALARM_STATUS}"
aws cloudwatch put-metric-alarm \
  --alarm-name "${ALARM_STATUS}" \
  --alarm-description "Alarm when instance/system status check fails for ${INSTANCE_ID}" \
  --namespace "AWS/EC2" \
  --metric-name "StatusCheckFailed" \
  --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
  --statistic "Maximum" \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 0 \
  --comparison-operator "GreaterThanThreshold" \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --region "${REGION}"

# ---------- 5. Build the dashboard JSON ----------
echo "==> Building dashboard definition..."
DASHBOARD_FILE="${WORK_DIR}/dashboard.json"

cat > "${DASHBOARD_FILE}" <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "CPU Utilization",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "${INSTANCE_ID}" ]
        ],
        "period": 300,
        "stat": "Average",
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "Network In / Out",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/EC2", "NetworkIn", "InstanceId", "${INSTANCE_ID}" ],
          [ "AWS/EC2", "NetworkOut", "InstanceId", "${INSTANCE_ID}" ]
        ],
        "period": 300,
        "stat": "Average",
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "Status Check Failed",
        "region": "${REGION}",
        "metrics": [
          [ "AWS/EC2", "StatusCheckFailed", "InstanceId", "${INSTANCE_ID}" ]
        ],
        "period": 60,
        "stat": "Maximum",
        "view": "timeSeries"
      }
    },
    {
      "type": "alarm",
      "x": 12, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "Alarm Status",
        "alarms": [
          "arn:aws:cloudwatch:${REGION}:$(aws sts get-caller-identity --query Account --output text):alarm:${ALARM_CPU}",
          "arn:aws:cloudwatch:${REGION}:$(aws sts get-caller-identity --query Account --output text):alarm:${ALARM_NET_IN}",
          "arn:aws:cloudwatch:${REGION}:$(aws sts get-caller-identity --query Account --output text):alarm:${ALARM_NET_OUT}",
          "arn:aws:cloudwatch:${REGION}:$(aws sts get-caller-identity --query Account --output text):alarm:${ALARM_STATUS}"
        ]
      }
    }
  ]
}
EOF

# ---------- 6. Create the dashboard ----------
echo "==> Creating CloudWatch dashboard '${DASHBOARD_NAME}'..."
aws cloudwatch put-dashboard \
  --dashboard-name "${DASHBOARD_NAME}" \
  --dashboard-body "file://${DASHBOARD_FILE}" \
  --region "${REGION}"

echo ""
echo "==> Done!"
echo "==> Alarms created:"
echo "    - ${ALARM_CPU}"
echo "    - ${ALARM_NET_IN}"
echo "    - ${ALARM_NET_OUT}"
echo "    - ${ALARM_STATUS}"
echo "==> Dashboard name: ${DASHBOARD_NAME}"
echo "==> View it at:"
echo "    https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${DASHBOARD_NAME}"

rm -rf "${WORK_DIR}"
