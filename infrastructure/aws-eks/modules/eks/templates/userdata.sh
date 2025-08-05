#!/bin/bash

# EKS Optimized AMI User Data Script
# This script configures the EKS worker node

# Set up logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Update the system
yum update -y

# Install additional packages for monitoring and security
yum install -y \
    amazon-cloudwatch-agent \
    htop \
    curl \
    wget \
    unzip \
    jq \
    awscli

# Configure CloudWatch agent for enhanced monitoring
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/eks/${cluster_name}/worker-logs",
                        "log_stream_name": "{instance_id}/messages"
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "/aws/eks/${cluster_name}/worker-logs",
                        "log_stream_name": "{instance_id}/secure"
                    },
                    {
                        "file_path": "/var/log/cloud-init.log",
                        "log_group_name": "/aws/eks/${cluster_name}/worker-logs",
                        "log_stream_name": "{instance_id}/cloud-init"
                    }
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

# Set up container runtime optimizations
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

# Restart Docker with new configuration
systemctl restart docker

# Configure kubelet with additional arguments
KUBELET_CONFIG=/etc/kubernetes/kubelet/kubelet-config.json
if [ -f "$KUBELET_CONFIG" ]; then
    # Backup original config
    cp $KUBELET_CONFIG $KUBELET_CONFIG.backup
    
    # Add additional kubelet configurations
    jq '. + {
        "maxPods": 110,
        "kubeReserved": {
            "cpu": "100m",
            "memory": "100Mi",
            "ephemeral-storage": "1Gi"
        },
        "systemReserved": {
            "cpu": "100m",
            "memory": "100Mi",
            "ephemeral-storage": "1Gi"
        },
        "evictionHard": {
            "memory.available": "100Mi",
            "nodefs.available": "10%",
            "nodefs.inodesFree": "5%"
        }
    }' $KUBELET_CONFIG.backup > $KUBELET_CONFIG
fi

# Set up log rotation for container logs
cat <<EOF > /etc/logrotate.d/docker-containers
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=10M
    missingok
    delaycompress
    copytruncate
}
EOF

# Set up node problem detector (optional)
# This helps identify and report various node-level problems to Kubernetes
if command -v systemctl &> /dev/null; then
    cat <<EOF > /etc/systemd/system/node-problem-detector.service
[Unit]
Description=Kubernetes Node Problem Detector
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node-problem-detector --v=2 --logtostderr --config.system-log-monitor=/config/kernel-monitor.json,/config/docker-monitor.json --port=20256
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
fi

# Configure kernel parameters for better performance
cat <<EOF >> /etc/sysctl.conf
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576

# Virtual memory optimizations
vm.max_map_count = 262144
vm.swappiness = 1
EOF

sysctl -p

# Bootstrap the EKS node
/etc/eks/bootstrap.sh ${cluster_name} ${bootstrap_arguments} --kubelet-extra-args="${kubelet_extra_args}"

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack $${AWS::StackName} --resource AutoScalingGroup --region $${AWS::Region} || true

echo "EKS node bootstrap completed successfully"