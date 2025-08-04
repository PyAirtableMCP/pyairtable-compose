#!/usr/bin/env python3
"""
Cost Estimation Script for PyAirtable Multi-Region Infrastructure
This script calculates estimated monthly costs for the multi-region deployment.
"""

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional
from datetime import datetime


@dataclass
class ResourceCost:
    name: str
    cost_per_hour: float
    quantity: int
    region: str
    description: str = ""
    
    @property
    def monthly_cost(self) -> float:
        """Calculate monthly cost (assuming 730 hours per month)"""
        return self.cost_per_hour * self.quantity * 730


class CostCalculator:
    """Multi-region infrastructure cost calculator"""
    
    def __init__(self):
        # AWS pricing as of 2024 (prices may vary by region)
        self.pricing = {
            # EKS Cluster (per cluster)
            "eks_cluster": 0.10,  # $0.10/hour per cluster
            
            # EKS Node Groups (per node)
            "eks_node_m5_large": 0.096,     # m5.large
            "eks_node_m5_xlarge": 0.192,    # m5.xlarge
            
            # RDS PostgreSQL
            "rds_r6g_large": 0.192,         # db.r6g.large
            "rds_r6g_xlarge": 0.384,        # db.r6g.xlarge
            
            # ElastiCache Redis
            "redis_r6g_large": 0.163,       # cache.r6g.large
            
            # MSK Kafka
            "msk_m5_large": 0.25,           # kafka.m5.large (includes storage)
            
            # Application Load Balancer
            "alb": 0.0252,                  # $0.0252/hour + $0.008/LCU
            
            # NAT Gateway
            "nat_gateway": 0.045,           # $0.045/hour + data processing
            
            # CloudFront
            "cloudfront_requests": 0.0075,  # per 10,000 requests (first 1B)
            "cloudfront_data": 0.085,       # per GB (first 10 TB)
            
            # Data Transfer
            "data_transfer_out": 0.09,      # per GB (first 1 GB free)
            "data_transfer_cross_region": 0.02,  # per GB
            
            # Storage
            "ebs_gp3": 0.08,               # per GB per month
            "s3_standard": 0.023,          # per GB per month
        }
        
        self.regions = {
            "us-east-1": {"name": "US East", "multiplier": 1.0},
            "eu-west-1": {"name": "EU West", "multiplier": 1.15},
            "ap-southeast-1": {"name": "AP Southeast", "multiplier": 1.20}
        }
    
    def calculate_eks_costs(self, region: str, is_primary: bool = False) -> List[ResourceCost]:
        """Calculate EKS cluster costs"""
        costs = []
        multiplier = self.regions[region]["multiplier"]
        
        # EKS Control Plane
        costs.append(ResourceCost(
            name="EKS Control Plane",
            cost_per_hour=self.pricing["eks_cluster"] * multiplier,
            quantity=1,
            region=region,
            description="Managed Kubernetes control plane"
        ))
        
        # Worker Nodes
        node_count = 3 if is_primary else 2
        costs.append(ResourceCost(
            name="EKS Worker Nodes (m5.large)",
            cost_per_hour=self.pricing["eks_node_m5_large"] * multiplier,
            quantity=node_count,
            region=region,
            description=f"{node_count} worker nodes for container workloads"
        ))
        
        return costs
    
    def calculate_database_costs(self, region: str, is_primary: bool = False) -> List[ResourceCost]:
        """Calculate RDS database costs"""
        costs = []
        multiplier = self.regions[region]["multiplier"]
        
        if is_primary:
            # Primary database with Multi-AZ
            costs.append(ResourceCost(
                name="RDS Primary (Multi-AZ)",
                cost_per_hour=self.pricing["rds_r6g_xlarge"] * multiplier * 2,  # Multi-AZ doubles cost
                quantity=1,
                region=region,
                description="Primary PostgreSQL database with Multi-AZ"
            ))
        else:
            # Read replica
            costs.append(ResourceCost(
                name="RDS Read Replica",
                cost_per_hour=self.pricing["rds_r6g_large"] * multiplier,
                quantity=1,
                region=region,
                description="Read replica for regional queries"
            ))
        
        # Database storage (200 GB)
        costs.append(ResourceCost(
            name="RDS Storage (gp3)",
            cost_per_hour=self.pricing["ebs_gp3"] * 200 / 730,  # Convert monthly to hourly
            quantity=1,
            region=region,
            description="200 GB gp3 storage for database"
        ))
        
        return costs
    
    def calculate_cache_costs(self, region: str) -> List[ResourceCost]:
        """Calculate ElastiCache Redis costs"""
        costs = []
        multiplier = self.regions[region]["multiplier"]
        
        costs.append(ResourceCost(
            name="ElastiCache Redis Cluster",
            cost_per_hour=self.pricing["redis_r6g_large"] * multiplier,
            quantity=3,  # 3 nodes for high availability
            region=region,
            description="Redis cluster with 3 nodes"
        ))
        
        return costs
    
    def calculate_kafka_costs(self, region: str) -> List[ResourceCost]:
        """Calculate MSK Kafka costs"""
        costs = []
        multiplier = self.regions[region]["multiplier"]
        
        costs.append(ResourceCost(
            name="MSK Kafka Cluster",
            cost_per_hour=self.pricing["msk_m5_large"] * multiplier,
            quantity=3,  # 3 brokers minimum
            region=region,
            description="Managed Kafka cluster with 3 brokers"
        ))
        
        return costs
    
    def calculate_network_costs(self, region: str) -> List[ResourceCost]:
        """Calculate network infrastructure costs"""
        costs = []
        multiplier = self.regions[region]["multiplier"]
        
        # Application Load Balancer
        costs.append(ResourceCost(
            name="Application Load Balancer",
            cost_per_hour=self.pricing["alb"] * multiplier,
            quantity=1,
            region=region,
            description="Regional load balancer"
        ))
        
        # NAT Gateways (3 for HA)
        costs.append(ResourceCost(
            name="NAT Gateways",
            cost_per_hour=self.pricing["nat_gateway"] * multiplier,
            quantity=3,
            region=region,
            description="NAT gateways for private subnet internet access"
        ))
        
        return costs
    
    def calculate_global_costs(self) -> List[ResourceCost]:
        """Calculate global service costs"""
        costs = []
        
        # CloudFront Distribution
        costs.append(ResourceCost(
            name="CloudFront Distribution",
            cost_per_hour=100 / 730,  # Estimated $100/month for moderate usage
            quantity=1,
            region="global",
            description="Global CDN distribution"
        ))
        
        # Route53 Hosted Zone
        costs.append(ResourceCost(
            name="Route53 Hosted Zone",
            cost_per_hour=0.50 / 730,  # $0.50/month per hosted zone
            quantity=1,
            region="global",
            description="DNS hosted zone"
        ))
        
        # Route53 Health Checks
        costs.append(ResourceCost(
            name="Route53 Health Checks",
            cost_per_hour=(0.50 * 3) / 730,  # $0.50/month per health check
            quantity=1,
            region="global",
            description="Health checks for each region"
        ))
        
        # Cross-region data transfer (estimated)
        costs.append(ResourceCost(
            name="Cross-Region Data Transfer",
            cost_per_hour=50 / 730,  # Estimated $50/month
            quantity=1,
            region="global",
            description="Data transfer between regions"
        ))
        
        return costs
    
    def calculate_storage_costs(self, region: str) -> List[ResourceCost]:
        """Calculate storage costs"""
        costs = []
        
        # S3 buckets for logs and backups (estimated 100 GB per region)
        costs.append(ResourceCost(
            name="S3 Storage",
            cost_per_hour=(self.pricing["s3_standard"] * 100) / 730,
            quantity=1,
            region=region,
            description="S3 storage for logs and backups"
        ))
        
        return costs
    
    def calculate_total_costs(self, environment: str = "prod") -> Dict:
        """Calculate total infrastructure costs"""
        all_costs = []
        
        # Regional costs
        for region_id, region_info in self.regions.items():
            is_primary = region_id == "us-east-1"
            
            # Calculate costs for each service
            all_costs.extend(self.calculate_eks_costs(region_id, is_primary))
            all_costs.extend(self.calculate_database_costs(region_id, is_primary))
            all_costs.extend(self.calculate_cache_costs(region_id))
            all_costs.extend(self.calculate_kafka_costs(region_id))
            all_costs.extend(self.calculate_network_costs(region_id))
            all_costs.extend(self.calculate_storage_costs(region_id))
        
        # Global costs
        all_costs.extend(self.calculate_global_costs())
        
        # Group costs by region
        costs_by_region = {}
        total_cost = 0
        
        for cost in all_costs:
            if cost.region not in costs_by_region:
                costs_by_region[cost.region] = []
            costs_by_region[cost.region].append(cost)
            total_cost += cost.monthly_cost
        
        # Apply environment scaling factor
        env_factors = {
            "dev": 0.3,      # Smaller instances, fewer resources
            "staging": 0.6,  # Medium instances, testing load
            "prod": 1.0      # Full production load
        }
        
        scaling_factor = env_factors.get(environment, 1.0)
        scaled_total = total_cost * scaling_factor
        
        return {
            "costs_by_region": costs_by_region,
            "total_monthly_cost": total_cost,
            "environment": environment,
            "scaling_factor": scaling_factor,
            "scaled_monthly_cost": scaled_total,
            "calculation_date": datetime.now().isoformat()
        }
    
    def generate_report(self, costs_data: Dict, output_format: str = "text") -> str:
        """Generate cost report in specified format"""
        if output_format == "json":
            return json.dumps(costs_data, indent=2, default=str)
        
        # Text format
        report = []
        report.append("=" * 80)
        report.append("PyAirtable Multi-Region Infrastructure Cost Estimate")
        report.append("=" * 80)
        report.append(f"Environment: {costs_data['environment'].upper()}")
        report.append(f"Calculation Date: {costs_data['calculation_date'][:10]}")
        report.append(f"Scaling Factor: {costs_data['scaling_factor']}")
        report.append("")
        
        # Regional breakdown
        total_by_region = {}
        for region, costs in costs_data["costs_by_region"].items():
            region_total = sum(cost.monthly_cost for cost in costs)
            total_by_region[region] = region_total
            
            region_name = self.regions.get(region, {}).get("name", region.title())
            report.append(f"{region_name} ({region}):")
            report.append("-" * 40)
            
            for cost in sorted(costs, key=lambda x: x.monthly_cost, reverse=True):
                cost_str = f"${cost.monthly_cost * costs_data['scaling_factor']:,.2f}"
                report.append(f"  {cost.name:<30} {cost_str:>12}")
                if cost.description:
                    report.append(f"    {cost.description}")
            
            report.append(f"  {'Regional Subtotal:':<30} ${region_total * costs_data['scaling_factor']:,.2f}")
            report.append("")
        
        # Summary
        report.append("=" * 80)
        report.append("COST SUMMARY")
        report.append("=" * 80)
        
        for region, total in sorted(total_by_region.items()):
            region_name = self.regions.get(region, {}).get("name", region.title())
            scaled_total = total * costs_data['scaling_factor']
            report.append(f"{region_name:<20} ${scaled_total:>10,.2f}")
        
        report.append("-" * 40)
        report.append(f"{'TOTAL MONTHLY:':<20} ${costs_data['scaled_monthly_cost']:>10,.2f}")
        report.append(f"{'TOTAL YEARLY:':<20} ${costs_data['scaled_monthly_cost'] * 12:>10,.2f}")
        report.append("")
        
        # Cost optimization suggestions
        report.append("COST OPTIMIZATION OPPORTUNITIES:")
        report.append("-" * 40)
        if costs_data['environment'] == 'prod':
            report.append("• Consider Reserved Instances for consistent workloads (up to 30% savings)")
            report.append("• Use Spot Instances for non-critical workloads (up to 70% savings)")
            report.append("• Implement auto-scaling to reduce idle capacity")
            report.append("• Archive old logs and backups to cheaper storage classes")
            report.append("• Monitor and optimize data transfer between regions")
        else:
            report.append("• Use smaller instance types for non-production environments")
            report.append("• Implement scheduled scaling to shut down resources after hours")
            report.append("• Use single-AZ deployments where high availability isn't critical")
        
        report.append("")
        report.append("Note: Estimates are based on current AWS pricing and may vary.")
        report.append("Actual costs depend on usage patterns, data transfer, and additional services.")
        
        return "\n".join(report)


def main():
    parser = argparse.ArgumentParser(
        description="Calculate PyAirtable multi-region infrastructure costs"
    )
    parser.add_argument(
        "--environment", "-e",
        choices=["dev", "staging", "prod"],
        default="prod",
        help="Environment to calculate costs for"
    )
    parser.add_argument(
        "--format", "-f",
        choices=["text", "json"],
        default="text",
        help="Output format"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output file (default: stdout)"
    )
    
    args = parser.parse_args()
    
    try:
        calculator = CostCalculator()
        costs_data = calculator.calculate_total_costs(args.environment)
        report = calculator.generate_report(costs_data, args.format)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(report)
            print(f"Cost report written to {args.output}")
        else:
            print(report)
    
    except Exception as e:
        print(f"Error calculating costs: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()