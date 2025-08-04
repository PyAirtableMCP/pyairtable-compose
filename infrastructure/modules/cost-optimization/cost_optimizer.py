#!/usr/bin/env python3
"""
Cost Optimization Lambda Function
Task: cost-1 - Automated cost optimization and rightsizing recommendations
"""

import json
import boto3
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class CostOptimizer:
    def __init__(self):
        self.ecs_client = boto3.client('ecs')
        self.autoscaling_client = boto3.client('autoscaling')
        self.ce_client = boto3.client('ce')
        self.sns_client = boto3.client('sns')
        self.cloudwatch = boto3.client('cloudwatch')
        
        self.cluster_name = os.environ.get('CLUSTER_NAME', '${cluster_name}')
        self.environment = os.environ.get('ENVIRONMENT', 'production')
        self.sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        self.cost_threshold = float(os.environ.get('COST_THRESHOLD', '100'))

    def get_current_costs(self) -> Dict[str, Any]:
        """Get current daily costs from Cost Explorer"""
        try:
            end_date = datetime.now().date()
            start_date = end_date - timedelta(days=1)
            
            response = self.ce_client.get_cost_and_usage(
                TimePeriod={
                    'Start': start_date.strftime('%Y-%m-%d'),
                    'End': end_date.strftime('%Y-%m-%d')
                },
                Granularity='DAILY',
                Metrics=['BlendedCost'],
                GroupBy=[
                    {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                    {'Type': 'TAG', 'Key': 'Service'}
                ]
            )
            
            return response
        except Exception as e:
            logger.error(f"Error getting costs: {str(e)}")
            return {}

    def analyze_ecs_resource_usage(self) -> List[Dict[str, Any]]:
        """Analyze ECS service resource usage for optimization"""
        recommendations = []
        
        try:
            # Get cluster services
            services_response = self.ecs_client.list_services(cluster=self.cluster_name)
            
            for service_arn in services_response['serviceArns']:
                service_name = service_arn.split('/')[-1]
                
                # Get service details
                service_detail = self.ecs_client.describe_services(
                    cluster=self.cluster_name,
                    services=[service_arn]
                )
                
                if not service_detail['services']:
                    continue
                    
                service = service_detail['services'][0]
                
                # Get CloudWatch metrics for the service
                cpu_utilization = self.get_service_cpu_utilization(service_name)
                memory_utilization = self.get_service_memory_utilization(service_name)
                
                # Generate recommendations based on utilization
                recommendation = self.generate_service_recommendation(
                    service_name, service, cpu_utilization, memory_utilization
                )
                
                if recommendation:
                    recommendations.append(recommendation)
                    
        except Exception as e:
            logger.error(f"Error analyzing ECS resources: {str(e)}")
            
        return recommendations

    def get_service_cpu_utilization(self, service_name: str) -> float:
        """Get average CPU utilization for a service over the last 24 hours"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/ECS',
                MetricName='CPUUtilization',
                Dimensions=[
                    {'Name': 'ServiceName', 'Value': service_name},
                    {'Name': 'ClusterName', 'Value': self.cluster_name}
                ],
                StartTime=datetime.utcnow() - timedelta(hours=24),
                EndTime=datetime.utcnow(),
                Period=3600,  # 1 hour periods
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                return sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            return 0.0
            
        except Exception as e:
            logger.error(f"Error getting CPU utilization for {service_name}: {str(e)}")
            return 0.0

    def get_service_memory_utilization(self, service_name: str) -> float:
        """Get average memory utilization for a service over the last 24 hours"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/ECS',
                MetricName='MemoryUtilization',
                Dimensions=[
                    {'Name': 'ServiceName', 'Value': service_name},
                    {'Name': 'ClusterName', 'Value': self.cluster_name}
                ],
                StartTime=datetime.utcnow() - timedelta(hours=24),
                EndTime=datetime.utcnow(),
                Period=3600,  # 1 hour periods
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                return sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            return 0.0
            
        except Exception as e:
            logger.error(f"Error getting memory utilization for {service_name}: {str(e)}")
            return 0.0

    def generate_service_recommendation(self, service_name: str, service: Dict, 
                                     cpu_util: float, memory_util: float) -> Dict[str, Any]:
        """Generate rightsizing recommendation for a service"""
        recommendation = {
            'service_name': service_name,
            'current_cpu_utilization': cpu_util,
            'current_memory_utilization': memory_util,
            'recommendation_type': None,
            'potential_savings': 0,
            'action': None
        }
        
        # Get current task definition
        task_def_arn = service['taskDefinition']
        task_def_response = self.ecs_client.describe_task_definition(
            taskDefinition=task_def_arn
        )
        
        if not task_def_response['taskDefinition']['containerDefinitions']:
            return None
            
        container_def = task_def_response['taskDefinition']['containerDefinitions'][0]
        current_cpu = container_def.get('cpu', 256)
        current_memory = container_def.get('memory', 512)
        
        # Rightsizing logic
        if cpu_util < 20 and memory_util < 30:  # Under-utilized
            recommendation['recommendation_type'] = 'downsize'
            recommendation['action'] = 'Consider reducing CPU/memory allocation'
            # Estimate 30% cost savings
            recommendation['potential_savings'] = self.estimate_service_cost(current_cpu, current_memory) * 0.3
            
        elif cpu_util > 80 or memory_util > 85:  # Over-utilized
            recommendation['recommendation_type'] = 'upsize'
            recommendation['action'] = 'Consider increasing CPU/memory allocation'
            recommendation['potential_savings'] = 0  # No savings, but performance improvement
            
        elif cpu_util < 40 and memory_util < 50:  # Moderate under-utilization
            recommendation['recommendation_type'] = 'optimize'
            recommendation['action'] = 'Consider slight resource reduction'
            recommendation['potential_savings'] = self.estimate_service_cost(current_cpu, current_memory) * 0.15
            
        return recommendation if recommendation['recommendation_type'] else None

    def estimate_service_cost(self, cpu: int, memory: int) -> float:
        """Estimate monthly cost for a service based on CPU and memory"""
        # Fargate pricing (us-east-1)
        cpu_cost_per_hour = 0.04416  # per vCPU-hour
        memory_cost_per_hour = 0.004858  # per GB-hour
        
        # Convert CPU units to vCPUs (1024 CPU units = 1 vCPU)
        vcpus = cpu / 1024
        # Convert memory to GB
        memory_gb = memory / 1024
        
        hourly_cost = (vcpus * cpu_cost_per_hour) + (memory_gb * memory_cost_per_hour)
        monthly_cost = hourly_cost * 24 * 30  # Approximate monthly cost
        
        return monthly_cost

    def check_spot_instance_utilization(self) -> List[Dict[str, Any]]:
        """Check if more workloads can be moved to spot instances"""
        recommendations = []
        
        try:
            # Get Auto Scaling Groups
            asg_response = self.autoscaling_client.describe_auto_scaling_groups()
            
            for asg in asg_response['AutoScalingGroups']:
                if 'spot' not in asg['AutoScalingGroupName'].lower():
                    continue
                    
                spot_usage = self.analyze_spot_usage(asg)
                if spot_usage:
                    recommendations.append(spot_usage)
                    
        except Exception as e:
            logger.error(f"Error checking spot instance utilization: {str(e)}")
            
        return recommendations

    def analyze_spot_usage(self, asg: Dict) -> Dict[str, Any]:
        """Analyze spot instance usage and interruptions"""
        asg_name = asg['AutoScalingGroupName']
        
        try:
            # Get CloudWatch metrics for spot interruptions
            interruption_response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/AutoScaling',
                MetricName='GroupTotalInstances',
                Dimensions=[{'Name': 'AutoScalingGroupName', 'Value': asg_name}],
                StartTime=datetime.utcnow() - timedelta(days=7),
                EndTime=datetime.utcnow(),
                Period=86400,  # Daily
                Statistics=['Average']
            )
            
            if interruption_response['Datapoints']:
                avg_instances = sum(dp['Average'] for dp in interruption_response['Datapoints']) / len(interruption_response['Datapoints'])
                
                return {
                    'asg_name': asg_name,
                    'current_capacity': asg['DesiredCapacity'],
                    'average_instances': avg_instances,
                    'recommendation': 'Consider increasing spot percentage if interruption rate is low',
                    'potential_savings': self.estimate_spot_savings(asg['DesiredCapacity'])
                }
                
        except Exception as e:
            logger.error(f"Error analyzing spot usage for {asg_name}: {str(e)}")
            
        return None

    def estimate_spot_savings(self, instance_count: int) -> float:
        """Estimate potential savings from using more spot instances"""
        # Assume average savings of 60% with spot instances
        avg_instance_cost_per_hour = 0.0464  # t3.medium on-demand price
        hourly_savings = instance_count * avg_instance_cost_per_hour * 0.6
        monthly_savings = hourly_savings * 24 * 30
        
        return monthly_savings

    def send_cost_alert(self, recommendations: List[Dict], current_cost: float):
        """Send cost optimization recommendations via SNS"""
        if not self.sns_topic_arn:
            logger.warning("No SNS topic ARN configured for alerts")
            return
            
        try:
            total_potential_savings = sum(r.get('potential_savings', 0) for r in recommendations)
            
            message = {
                'timestamp': datetime.utcnow().isoformat(),
                'cluster': self.cluster_name,
                'environment': self.environment,
                'current_daily_cost': current_cost,
                'cost_threshold': self.cost_threshold,
                'total_potential_monthly_savings': total_potential_savings,
                'recommendations': recommendations[:10]  # Limit to top 10
            }
            
            subject = f"Cost Optimization Report - {self.environment}"
            if current_cost > self.cost_threshold:
                subject = f"🚨 COST ALERT: {subject} - Threshold Exceeded"
                
            formatted_message = self.format_alert_message(message)
            
            self.sns_client.publish(
                TopicArn=self.sns_topic_arn,
                Subject=subject,
                Message=formatted_message
            )
            
            logger.info(f"Cost alert sent with {len(recommendations)} recommendations")
            
        except Exception as e:
            logger.error(f"Error sending cost alert: {str(e)}")

    def format_alert_message(self, message: Dict) -> str:
        """Format the alert message in a readable format"""
        formatted = f"""
Cost Optimization Report
========================

Cluster: {message['cluster']}
Environment: {message['environment']}
Timestamp: {message['timestamp']}

Current Daily Cost: ${message['current_daily_cost']:.2f}
Cost Threshold: ${message['cost_threshold']:.2f}
Status: {'⚠️ OVER THRESHOLD' if message['current_daily_cost'] > message['cost_threshold'] else '✅ Within Budget'}

Total Potential Monthly Savings: ${message['total_potential_monthly_savings']:.2f}

Recommendations:
================
"""
        
        for i, rec in enumerate(message['recommendations'], 1):
            formatted += f"""
{i}. Service: {rec.get('service_name', rec.get('asg_name', 'Unknown'))}
   Type: {rec.get('recommendation_type', 'spot_optimization')}
   Action: {rec.get('action', rec.get('recommendation', 'No action specified'))}
   Potential Savings: ${rec.get('potential_savings', 0):.2f}/month
   CPU Utilization: {rec.get('current_cpu_utilization', 'N/A'):.1f}%
   Memory Utilization: {rec.get('current_memory_utilization', 'N/A'):.1f}%
"""
        
        formatted += f"""

For detailed analysis, check the CloudWatch logs and Cost Explorer.
Generated by PyAirtable Cost Optimizer Lambda
"""
        
        return formatted


def handler(event, context):
    """Lambda function entry point"""
    logger.info("Starting cost optimization analysis")
    
    cost_optimizer = CostOptimizer()
    
    try:
        # Get current costs
        cost_data = cost_optimizer.get_current_costs()
        current_cost = 0.0
        
        if cost_data and 'ResultsByTime' in cost_data:
            for result in cost_data['ResultsByTime']:
                if result['Total']:
                    current_cost += float(result['Total']['BlendedCost']['Amount'])
        
        # Analyze ECS resources
        ecs_recommendations = cost_optimizer.analyze_ecs_resource_usage()
        logger.info(f"Generated {len(ecs_recommendations)} ECS recommendations")
        
        # Check spot instance utilization
        spot_recommendations = cost_optimizer.check_spot_instance_utilization()
        logger.info(f"Generated {len(spot_recommendations)} spot instance recommendations")
        
        # Combine all recommendations
        all_recommendations = ecs_recommendations + spot_recommendations
        
        # Send alert if there are recommendations or cost is high
        if all_recommendations or current_cost > cost_optimizer.cost_threshold:
            cost_optimizer.send_cost_alert(all_recommendations, current_cost)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed',
                'current_daily_cost': current_cost,
                'recommendations_count': len(all_recommendations),
                'potential_monthly_savings': sum(r.get('potential_savings', 0) for r in all_recommendations)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in cost optimization analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }