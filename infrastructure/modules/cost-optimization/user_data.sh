#!/bin/bash
# User Data Script for ECS Spot Instances
# Task: cost-1 - ECS cluster configuration for spot instances

# Configure ECS agent
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config

# Enable CloudWatch logs
echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config

# Set up spot instance interrupt handling
cat > /opt/spot-interrupt-handler.sh << 'EOF'
#!/bin/bash
# Handle spot instance interruption gracefully

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Check for spot interruption notice
while true; do
    if curl -f -s http://169.254.169.254/latest/meta-data/spot/instance-action > /dev/null 2>&1; then
        echo "Spot interruption notice received. Draining tasks..."
        
        # Set ECS instance to DRAINING state
        aws ecs put-attributes \
            --region $REGION \
            --cluster ${cluster_name} \
            --attributes name=ecs.instance-draining,value=true,targetType=container-instance,targetId=$INSTANCE_ID
        
        # Wait for tasks to drain (max 2 minutes)
        sleep 120
        
        # Signal Auto Scaling Group
        aws autoscaling complete-lifecycle-action \
            --region $REGION \
            --lifecycle-hook-name spot-interruption \
            --auto-scaling-group-name $(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].Tags[?Key==`aws:autoscaling:groupName`].Value' --output text) \
            --instance-id $INSTANCE_ID \
            --lifecycle-action-result CONTINUE
        
        break
    fi
    sleep 5
done
EOF

chmod +x /opt/spot-interrupt-handler.sh

# Start spot interrupt handler in background
nohup /opt/spot-interrupt-handler.sh > /var/log/spot-interrupt-handler.log 2>&1 &

# Install CloudWatch agent
yum update -y
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "PyAirtable/ECS",
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
                        "file_path": "/var/log/ecs/ecs-agent.log",
                        "log_group_name": "/aws/ecs/${cluster_name}/ecs-agent",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/spot-interrupt-handler.log",
                        "log_group_name": "/aws/ecs/${cluster_name}/spot-interrupt",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Start ECS agent
start ecs

# Log successful initialization
echo "ECS Spot instance initialized successfully at $(date)" >> /var/log/user-data-init.log