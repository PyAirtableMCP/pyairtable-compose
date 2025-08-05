import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2_client = boto3.client('ec2')
eks_client = boto3.client('eks')
cloudwatch_client = boto3.client('cloudwatch')
pricing_client = boto3.client('pricing', region_name='us-east-1')  # Pricing API only available in us-east-1
sns_client = boto3.client('sns')

# Environment variables
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', '${cluster_name}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', '${environment}')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def handler(event, context):
    """
    Main Lambda handler for cost optimization analysis
    """
    try:
        logger.info(f"Starting cost optimization analysis for cluster: {CLUSTER_NAME}")
        
        # Get cluster information
        cluster_info = get_cluster_info()
        
        # Analyze node groups
        node_group_analysis = analyze_node_groups(cluster_info)
        
        # Analyze EC2 instances
        instance_analysis = analyze_ec2_instances()
        
        # Get cost recommendations
        recommendations = generate_cost_recommendations(node_group_analysis, instance_analysis)
        
        # Send recommendations if any found
        if recommendations:
            send_cost_recommendations(recommendations)
        
        logger.info("Cost optimization analysis completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed',
                'recommendations_count': len(recommendations),
                'cluster': CLUSTER_NAME,
                'environment': ENVIRONMENT
            })
        }
        
    except Exception as e:
        logger.error(f"Error in cost optimization analysis: {str(e)}")
        raise e

def get_cluster_info() -> Dict[str, Any]:
    """
    Get EKS cluster information
    """
    try:
        response = eks_client.describe_cluster(name=CLUSTER_NAME)
        return response['cluster']
    except Exception as e:
        logger.error(f"Error getting cluster info: {str(e)}")
        raise e

def analyze_node_groups(cluster_info: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Analyze EKS node groups for cost optimization opportunities
    """
    try:
        node_groups = []
        
        # Get all node groups
        response = eks_client.list_nodegroups(clusterName=CLUSTER_NAME)
        
        for ng_name in response['nodegroups']:
            ng_response = eks_client.describe_nodegroup(
                clusterName=CLUSTER_NAME,
                nodegroupName=ng_name
            )
            
            nodegroup = ng_response['nodegroup']
            
            # Analyze utilization
            utilization = get_node_group_utilization(ng_name)
            
            # Check for cost optimization opportunities
            analysis = {
                'name': ng_name,
                'instance_types': nodegroup.get('instanceTypes', []),
                'capacity_type': nodegroup.get('capacityType', 'ON_DEMAND'),
                'scaling_config': nodegroup.get('scalingConfig', {}),
                'utilization': utilization,
                'recommendations': []
            }
            
            # Check if using spot instances
            if analysis['capacity_type'] == 'ON_DEMAND':
                analysis['recommendations'].append({
                    'type': 'spot_instances',
                    'description': 'Consider switching to SPOT capacity type for cost savings',
                    'potential_savings': '50-70%'
                })
            
            # Check for low utilization
            if utilization['cpu_utilization'] < 30:
                analysis['recommendations'].append({
                    'type': 'right_sizing',
                    'description': f'Low CPU utilization ({utilization["cpu_utilization"]}%). Consider smaller instance types',
                    'potential_savings': '20-40%'
                })
            
            # Check for over-provisioning
            desired_capacity = analysis['scaling_config'].get('desiredSize', 0)
            min_capacity = analysis['scaling_config'].get('minSize', 0)
            
            if desired_capacity > min_capacity * 1.5:
                analysis['recommendations'].append({
                    'type': 'scaling_optimization',
                    'description': f'Node group may be over-provisioned. Current: {desired_capacity}, Min: {min_capacity}',
                    'potential_savings': '10-30%'
                })
            
            node_groups.append(analysis)
        
        return node_groups
        
    except Exception as e:
        logger.error(f"Error analyzing node groups: {str(e)}")
        return []

def get_node_group_utilization(node_group_name: str) -> Dict[str, float]:
    """
    Get utilization metrics for a node group
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        # Get CPU utilization
        cpu_response = cloudwatch_client.get_metric_statistics(
            Namespace='AWS/EKS',
            MetricName='node_cpu_utilization',
            Dimensions=[
                {
                    'Name': 'ClusterName',
                    'Value': CLUSTER_NAME
                },
                {
                    'Name': 'NodeGroup',
                    'Value': node_group_name
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Average']
        )
        
        # Calculate average CPU utilization
        cpu_utilization = 0
        if cpu_response['Datapoints']:
            cpu_utilization = sum(dp['Average'] for dp in cpu_response['Datapoints']) / len(cpu_response['Datapoints'])
        
        # Get memory utilization
        memory_response = cloudwatch_client.get_metric_statistics(
            Namespace='AWS/EKS',
            MetricName='node_memory_utilization',
            Dimensions=[
                {
                    'Name': 'ClusterName',
                    'Value': CLUSTER_NAME
                },
                {
                    'Name': 'NodeGroup',
                    'Value': node_group_name
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Average']
        )
        
        # Calculate average memory utilization
        memory_utilization = 0
        if memory_response['Datapoints']:
            memory_utilization = sum(dp['Average'] for dp in memory_response['Datapoints']) / len(memory_response['Datapoints'])
        
        return {
            'cpu_utilization': round(cpu_utilization, 2),
            'memory_utilization': round(memory_utilization, 2)
        }
        
    except Exception as e:
        logger.warning(f"Error getting utilization for node group {node_group_name}: {str(e)}")
        return {'cpu_utilization': 0, 'memory_utilization': 0}

def analyze_ec2_instances() -> List[Dict[str, Any]]:
    """
    Analyze EC2 instances for cost optimization
    """
    try:
        instances = []
        
        # Get EC2 instances tagged with our cluster
        response = ec2_client.describe_instances(
            Filters=[
                {
                    'Name': 'tag:kubernetes.io/cluster/' + CLUSTER_NAME,
                    'Values': ['owned', 'shared']
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running']
                }
            ]
        )
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                
                # Get spot instance status
                is_spot = instance.get('InstanceLifecycle') == 'spot'
                
                # Get instance pricing information
                pricing_info = get_instance_pricing(instance['InstanceType'])
                
                analysis = {
                    'instance_id': instance['InstanceId'],
                    'instance_type': instance['InstanceType'],
                    'launch_time': instance['LaunchTime'].isoformat(),
                    'is_spot': is_spot,
                    'pricing': pricing_info,
                    'recommendations': []
                }
                
                # Recommend spot instances if not already using
                if not is_spot and pricing_info.get('spot_savings'):
                    analysis['recommendations'].append({
                        'type': 'spot_conversion',
                        'description': 'Convert to spot instance for cost savings',
                        'potential_savings': f"{pricing_info['spot_savings']}%"
                    })
                
                # Check for newer generation instances
                if is_older_generation(instance['InstanceType']):
                    analysis['recommendations'].append({
                        'type': 'instance_upgrade',
                        'description': 'Consider upgrading to newer generation instance for better price/performance',
                        'potential_savings': '10-20%'
                    })
                
                instances.append(analysis)
        
        return instances
        
    except Exception as e:
        logger.error(f"Error analyzing EC2 instances: {str(e)}")
        return []

def get_instance_pricing(instance_type: str) -> Dict[str, Any]:
    """
    Get pricing information for an instance type
    """
    try:
        # This is a simplified pricing lookup
        # In a real implementation, you'd use the AWS Pricing API
        pricing_data = {
            't3.micro': {'on_demand': 0.0104, 'spot_avg': 0.0031},
            't3.small': {'on_demand': 0.0208, 'spot_avg': 0.0062},
            't3.medium': {'on_demand': 0.0416, 'spot_avg': 0.0125},
            't3.large': {'on_demand': 0.0832, 'spot_avg': 0.0250},
            't3.xlarge': {'on_demand': 0.1664, 'spot_avg': 0.0499},
            # Add more instance types as needed
        }
        
        if instance_type in pricing_data:
            on_demand = pricing_data[instance_type]['on_demand']
            spot_avg = pricing_data[instance_type]['spot_avg']
            spot_savings = round(((on_demand - spot_avg) / on_demand) * 100, 1)
            
            return {
                'on_demand_hourly': on_demand,
                'spot_average_hourly': spot_avg,
                'spot_savings': spot_savings
            }
        
        return {}
        
    except Exception as e:
        logger.warning(f"Error getting pricing for {instance_type}: {str(e)}")
        return {}

def is_older_generation(instance_type: str) -> bool:
    """
    Check if instance type is from an older generation
    """
    older_generations = ['t2', 'm4', 'c4', 'r4', 'm3', 'c3', 'r3']
    instance_family = instance_type.split('.')[0]
    return instance_family in older_generations

def generate_cost_recommendations(node_group_analysis: List[Dict], instance_analysis: List[Dict]) -> List[Dict[str, Any]]:
    """
    Generate consolidated cost optimization recommendations
    """
    recommendations = []
    
    # Process node group recommendations
    for ng in node_group_analysis:
        for rec in ng['recommendations']:
            recommendations.append({
                'category': 'Node Group',
                'resource': ng['name'],
                'type': rec['type'],
                'description': rec['description'],
                'potential_savings': rec.get('potential_savings', 'Unknown'),
                'priority': get_recommendation_priority(rec['type'])
            })
    
    # Process instance recommendations
    for instance in instance_analysis:
        for rec in instance['recommendations']:
            recommendations.append({
                'category': 'EC2 Instance',
                'resource': instance['instance_id'],
                'type': rec['type'],
                'description': rec['description'],
                'potential_savings': rec.get('potential_savings', 'Unknown'),
                'priority': get_recommendation_priority(rec['type'])
            })
    
    # Sort by priority (high, medium, low)
    priority_order = {'high': 0, 'medium': 1, 'low': 2}
    recommendations.sort(key=lambda x: priority_order.get(x['priority'], 3))
    
    return recommendations

def get_recommendation_priority(rec_type: str) -> str:
    """
    Get priority level for recommendation type
    """
    high_priority = ['spot_instances', 'spot_conversion']
    medium_priority = ['right_sizing', 'scaling_optimization']
    
    if rec_type in high_priority:
        return 'high'
    elif rec_type in medium_priority:
        return 'medium'
    else:
        return 'low'

def send_cost_recommendations(recommendations: List[Dict[str, Any]]):
    """
    Send cost recommendations via SNS
    """
    try:
        if not SNS_TOPIC_ARN:
            logger.warning("SNS_TOPIC_ARN not set, skipping notification")
            return
        
        # Create summary
        total_recommendations = len(recommendations)
        high_priority = len([r for r in recommendations if r['priority'] == 'high'])
        medium_priority = len([r for r in recommendations if r['priority'] == 'medium'])
        low_priority = len([r for r in recommendations if r['priority'] == 'low'])
        
        # Format message
        message = f"""
🏷️ Cost Optimization Report - {CLUSTER_NAME}

📊 Summary:
• Total Recommendations: {total_recommendations}
• High Priority: {high_priority}
• Medium Priority: {medium_priority}
• Low Priority: {low_priority}

🔥 Top Recommendations:
"""
        
        # Add top 5 recommendations
        for i, rec in enumerate(recommendations[:5], 1):
            priority_emoji = {'high': '🔴', 'medium': '🟡', 'low': '🟢'}[rec['priority']]
            message += f"""
{i}. {priority_emoji} {rec['category']}: {rec['resource']}
   Type: {rec['type']}
   Description: {rec['description']}
   Potential Savings: {rec['potential_savings']}
"""
        
        message += f"""
📈 Environment: {ENVIRONMENT}
⏰ Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC

💡 Review these recommendations to optimize your AWS costs!
"""
        
        # Send SNS notification
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"💰 Cost Optimization Report - {CLUSTER_NAME}",
            Message=message
        )
        
        logger.info(f"Sent cost optimization report with {total_recommendations} recommendations")
        
    except Exception as e:
        logger.error(f"Error sending cost recommendations: {str(e)}")
        raise e