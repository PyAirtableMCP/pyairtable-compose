#!/bin/bash

# Karpenter Node Bootstrap Script
# Optimized for cost and performance

# Set up logging
exec > >(tee /var/log/karpenter-bootstrap.log|logger -t karpenter-bootstrap -s 2>/dev/console) 2>&1

# Update system packages
yum update -y

# Install essential packages
yum install -y \
    amazon-cloudwatch-agent \
    htop \
    curl \
    wget \
    unzip \
    jq \
    awscli

# Configure CloudWatch agent for cost-optimized monitoring
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "CWAgent/Karpenter",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Configure Docker for better performance
cat <<EOF > /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
    "storage-driver": "overlay2"
}
EOF

# Restart Docker
systemctl restart docker

# Optimize kernel parameters
cat <<EOF >> /etc/sysctl.conf
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576

# Virtual memory optimizations for containers
vm.max_map_count = 262144
vm.swappiness = 1
EOF

sysctl -p

# Configure log rotation for container logs
cat <<EOF > /etc/logrotate.d/docker-containers
/var/lib/docker/containers/*/*.log {
    rotate 5
    daily
    compress
    size=10M
    missingok
    delaycompress
    copytruncate
}
EOF

# Bootstrap the node with EKS
/etc/eks/bootstrap.sh ${cluster_name} \
    --kubelet-extra-args '--node-labels=provisioner=karpenter,cost-optimization=spot'

# Install Node Problem Detector for better observability
if ! command -v node-problem-detector &> /dev/null; then
    wget -O /usr/local/bin/node-problem-detector \
        https://github.com/kubernetes/node-problem-detector/releases/download/v0.8.12/node-problem-detector-v0.8.12-linux_amd64.tar.gz
    tar -xzf node-problem-detector-v0.8.12-linux_amd64.tar.gz -C /usr/local/bin/ --strip-components=1
    chmod +x /usr/local/bin/node-problem-detector
fi

# Create systemd service for node problem detector
cat <<EOF > /etc/systemd/system/node-problem-detector.service
[Unit]
Description=Kubernetes Node Problem Detector
After=kubelet.service

[Service]
Type=simple
ExecStart=/usr/local/bin/node-problem-detector --v=2 --logtostderr --config.system-log-monitor=/config/kernel-monitor.json --port=20256
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node-problem-detector
systemctl start node-problem-detector

# Set up instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Tag the instance with metadata
aws ec2 create-tags --region $(echo $AZ | sed 's/.$//')  --resources $INSTANCE_ID --tags \
    Key=Name,Value=${cluster_name}-karpenter-node \
    Key=karpenter.sh/cluster,Value=${cluster_name} \
    Key=InstanceType,Value=$INSTANCE_TYPE \
    Key=AvailabilityZone,Value=$AZ

echo "Karpenter node bootstrap completed successfully"
echo "Instance ID: $INSTANCE_ID"
echo "Instance Type: $INSTANCE_TYPE"
echo "Availability Zone: $AZ"