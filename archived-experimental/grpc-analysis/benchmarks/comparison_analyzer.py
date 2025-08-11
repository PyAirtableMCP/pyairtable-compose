#!/usr/bin/env python3
"""
REST vs gRPC Performance Comparison Analyzer
Compares benchmark results and provides detailed analysis
"""

import json
import statistics
import matplotlib.pyplot as plt
import pandas as pd
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import argparse

@dataclass
class PerformanceComparison:
    operation_type: str
    rest_avg_response_time_ms: float
    grpc_avg_response_time_ms: float
    rest_throughput_rps: float
    grpc_throughput_rps: float
    rest_payload_size_bytes: int
    grpc_payload_size_bytes: int
    rest_error_rate_percent: float
    grpc_error_rate_percent: float
    performance_improvement_percent: float
    throughput_improvement_percent: float
    payload_size_reduction_percent: float

class PerformanceAnalyzer:
    def __init__(self, rest_results_file: str, grpc_results_file: str):
        with open(rest_results_file, 'r') as f:
            self.rest_results = json.load(f)
        
        with open(grpc_results_file, 'r') as f:
            self.grpc_results = json.load(f)
    
    def analyze_overall_performance(self) -> Dict[str, Any]:
        """Compare overall performance metrics"""
        
        rest_summary = self.rest_results['summary']
        grpc_summary = self.grpc_results['summary']
        
        response_time_improvement = (
            (rest_summary['average_response_time_ms'] - grpc_summary['average_response_time_ms']) /
            rest_summary['average_response_time_ms'] * 100
        )
        
        throughput_improvement = (
            (grpc_summary['total_requests_per_second'] - rest_summary['total_requests_per_second']) /
            rest_summary['total_requests_per_second'] * 100
        )
        
        data_efficiency = (
            (rest_summary['total_data_transferred_mb'] - grpc_summary['total_data_transferred_mb']) /
            rest_summary['total_data_transferred_mb'] * 100
        )
        
        return {
            "response_time_improvement_percent": response_time_improvement,
            "throughput_improvement_percent": throughput_improvement,
            "data_transfer_reduction_percent": data_efficiency,
            "rest_metrics": {
                "avg_response_time_ms": rest_summary['average_response_time_ms'],
                "throughput_rps": rest_summary['total_requests_per_second'],
                "success_rate_percent": rest_summary['overall_success_rate'],
                "data_transferred_mb": rest_summary['total_data_transferred_mb']
            },
            "grpc_metrics": {
                "avg_response_time_ms": grpc_summary['average_response_time_ms'],
                "throughput_rps": grpc_summary['total_requests_per_second'],
                "success_rate_percent": grpc_summary['overall_success_rate'],
                "data_transferred_mb": grpc_summary['total_data_transferred_mb'],
                "avg_serialization_time_ms": grpc_summary.get('average_serialization_time_ms', 0),
                "avg_deserialization_time_ms": grpc_summary.get('average_deserialization_time_ms', 0)
            }
        }
    
    def analyze_operation_patterns(self) -> List[PerformanceComparison]:
        """Analyze performance by operation pattern"""
        
        # Group operations by type
        operation_groups = {
            "authentication": ["auth", "login", "token", "validate"],
            "workspace_management": ["workspace", "tenant"],
            "airtable_operations": ["airtable", "bases", "tables", "records"],
            "bulk_operations": ["batch", "bulk"],
            "real_time": ["permission", "notification", "stream"],
            "file_operations": ["file", "upload", "process"]
        }
        
        comparisons = []
        
        for group_name, keywords in operation_groups.items():
            rest_ops = self._filter_operations(self.rest_results['detailed_results'], keywords)
            grpc_ops = self._filter_operations(self.grpc_results['detailed_results'], keywords)
            
            if rest_ops and grpc_ops:
                rest_avg_response = statistics.mean([op['avg_response_time_ms'] for op in rest_ops])
                grpc_avg_response = statistics.mean([op['avg_response_time_ms'] for op in grpc_ops])
                
                rest_throughput = statistics.mean([op['requests_per_second'] for op in rest_ops])
                grpc_throughput = statistics.mean([op['requests_per_second'] for op in grpc_ops])
                
                rest_payload = statistics.mean([op['avg_payload_size_bytes'] for op in rest_ops])
                grpc_payload = statistics.mean([op['avg_payload_size_bytes'] for op in grpc_ops])
                
                rest_error_rate = statistics.mean([op['error_rate_percent'] for op in rest_ops])
                grpc_error_rate = statistics.mean([op['error_rate_percent'] for op in grpc_ops])
                
                performance_improvement = ((rest_avg_response - grpc_avg_response) / rest_avg_response) * 100
                throughput_improvement = ((grpc_throughput - rest_throughput) / rest_throughput) * 100
                payload_reduction = ((rest_payload - grpc_payload) / rest_payload) * 100 if rest_payload > 0 else 0
                
                comparisons.append(PerformanceComparison(
                    operation_type=group_name,
                    rest_avg_response_time_ms=rest_avg_response,
                    grpc_avg_response_time_ms=grpc_avg_response,
                    rest_throughput_rps=rest_throughput,
                    grpc_throughput_rps=grpc_throughput,
                    rest_payload_size_bytes=int(rest_payload),
                    grpc_payload_size_bytes=int(grpc_payload),
                    rest_error_rate_percent=rest_error_rate,
                    grpc_error_rate_percent=grpc_error_rate,
                    performance_improvement_percent=performance_improvement,
                    throughput_improvement_percent=throughput_improvement,
                    payload_size_reduction_percent=payload_reduction
                ))
        
        return comparisons
    
    def _filter_operations(self, operations: List[Dict], keywords: List[str]) -> List[Dict]:
        """Filter operations by keywords"""
        return [
            op for op in operations 
            if any(keyword.lower() in op['operation'].lower() for keyword in keywords)
        ]
    
    def analyze_serialization_performance(self) -> Dict[str, Any]:
        """Analyze serialization performance differences"""
        
        if 'serialization_comparisons' not in self.grpc_results:
            return {"error": "No serialization comparison data available"}
        
        comparisons = self.grpc_results['serialization_comparisons']
        
        avg_size_reduction = statistics.mean([c['size_reduction_percent'] for c in comparisons])
        avg_serialization_speedup = statistics.mean([c['serialization_speedup'] for c in comparisons])
        avg_deserialization_speedup = statistics.mean([c['deserialization_speedup'] for c in comparisons])
        
        return {
            "average_payload_size_reduction_percent": avg_size_reduction,
            "average_serialization_speedup": avg_serialization_speedup,
            "average_deserialization_speedup": avg_deserialization_speedup,
            "detailed_comparisons": comparisons,
            "bandwidth_savings": {
                "small_payloads": self._calculate_bandwidth_savings(comparisons, "simple"),
                "medium_payloads": self._calculate_bandwidth_savings(comparisons, "complex"),
                "large_payloads": self._calculate_bandwidth_savings(comparisons, "large")
            }
        }
    
    def _calculate_bandwidth_savings(self, comparisons: List[Dict], payload_type: str) -> Dict[str, float]:
        """Calculate bandwidth savings for different payload sizes"""
        
        comparison = next((c for c in comparisons if payload_type in c['operation']), None)
        if not comparison:
            return {"savings_percent": 0, "monthly_savings_mb": 0}
        
        size_reduction = comparison['size_reduction_percent']
        
        # Estimate monthly requests based on payload type
        monthly_requests = {
            "simple": 1000000,    # 1M simple requests (auth, permissions)
            "complex": 100000,    # 100K complex requests (listings, searches)
            "large": 10000        # 10K large requests (bulk operations)
        }.get(payload_type, 100000)
        
        original_size_mb = (comparison['json_size_bytes'] * monthly_requests) / (1024 * 1024)
        reduced_size_mb = (comparison['protobuf_size_bytes'] * monthly_requests) / (1024 * 1024)
        savings_mb = original_size_mb - reduced_size_mb
        
        return {
            "savings_percent": size_reduction,
            "monthly_requests": monthly_requests,
            "monthly_savings_mb": savings_mb,
            "annual_savings_gb": savings_mb * 12 / 1024
        }
    
    def analyze_concurrency_performance(self) -> Dict[str, Any]:
        """Analyze performance under different concurrency levels"""
        
        # This would analyze how REST vs gRPC perform under different concurrency levels
        # For now, provide theoretical analysis based on HTTP/1.1 vs HTTP/2
        
        return {
            "http1_limitations": {
                "head_of_line_blocking": "Sequential request processing",
                "connection_limit": "6-8 connections per domain in browsers",
                "connection_overhead": "TCP handshake + TLS handshake per connection",
                "header_redundancy": "Headers repeated in every request"
            },
            "http2_advantages": {
                "multiplexing": "Multiple streams over single connection",
                "header_compression": "HPACK compression reduces overhead",
                "flow_control": "Per-stream and connection-level flow control",
                "server_push": "Server can push resources proactively",
                "binary_framing": "More efficient than text-based HTTP/1.1"
            },
            "grpc_specific_benefits": {
                "connection_pooling": "Automatic connection reuse and pooling",
                "load_balancing": "Built-in client-side load balancing",
                "circuit_breaking": "Automatic failure detection and recovery",
                "streaming": "Bidirectional streaming with backpressure",
                "deadlines": "Request timeout and cancellation propagation"
            },
            "estimated_improvements": {
                "low_concurrency_1_10": "15-25% improvement",
                "medium_concurrency_10_50": "30-45% improvement", 
                "high_concurrency_50_plus": "50-70% improvement"
            }
        }
    
    def analyze_network_efficiency(self) -> Dict[str, Any]:
        """Analyze network efficiency improvements"""
        
        rest_summary = self.rest_results['summary']
        grpc_summary = self.grpc_results['summary']
        
        # Calculate theoretical network improvements
        compression_ratio = grpc_summary.get('average_compression_ratio', 0.7)
        
        return {
            "payload_compression": {
                "grpc_compression_ratio": compression_ratio,
                "estimated_bandwidth_reduction": (1 - compression_ratio) * 100,
                "gzip_additional_compression": "15-30% on top of protobuf"
            },
            "connection_efficiency": {
                "rest_connections": "Multiple HTTP/1.1 connections",
                "grpc_connections": "Single HTTP/2 connection with multiplexing",
                "handshake_reduction": "Significant reduction in TLS handshakes",
                "keep_alive": "Long-lived connections with efficient reuse"
            },
            "header_efficiency": {
                "rest_headers": "Full HTTP headers on every request",
                "grpc_headers": "HPACK compressed headers",
                "typical_header_compression": "85-95% header size reduction"
            },
            "flow_control": {
                "rest_limitations": "No built-in backpressure mechanism",
                "grpc_flow_control": "Automatic window-based flow control",
                "memory_efficiency": "Prevents buffer overflow on slow clients"
            }
        }
    
    def generate_recommendations(self, comparisons: List[PerformanceComparison]) -> List[Dict[str, Any]]:
        """Generate specific recommendations based on analysis"""
        
        recommendations = []
        
        # High-impact operations
        high_impact_ops = [c for c in comparisons if c.performance_improvement_percent > 30]
        if high_impact_ops:
            recommendations.append({
                "priority": "HIGH",
                "category": "Performance Critical Operations",
                "description": f"Migrate {len(high_impact_ops)} operation types showing >30% performance improvement",
                "operations": [op.operation_type for op in high_impact_ops],
                "estimated_benefit": f"Average {statistics.mean([op.performance_improvement_percent for op in high_impact_ops]):.1f}% performance improvement"
            })
        
        # High-frequency operations
        high_frequency_keywords = ["auth", "permission", "token", "validation"]
        high_freq_ops = [c for c in comparisons if any(kw in c.operation_type for kw in high_frequency_keywords)]
        if high_freq_ops:
            recommendations.append({
                "priority": "HIGH",
                "category": "High-Frequency Operations",
                "description": "Prioritize authentication and permission checking for gRPC migration",
                "operations": [op.operation_type for op in high_freq_ops],
                "reason": "These operations are called frequently and benefit significantly from reduced serialization overhead"
            })
        
        # Bulk operations
        bulk_ops = [c for c in comparisons if "bulk" in c.operation_type or "batch" in c.operation_type]
        if bulk_ops:
            recommendations.append({
                "priority": "MEDIUM",
                "category": "Bulk Operations",
                "description": "Implement streaming gRPC for bulk data operations",
                "operations": [op.operation_type for op in bulk_ops],
                "benefit": "Streaming reduces memory usage and improves user experience for large datasets"
            })
        
        # Real-time operations
        realtime_ops = [c for c in comparisons if "real_time" in c.operation_type or "stream" in c.operation_type]
        if realtime_ops:
            recommendations.append({
                "priority": "MEDIUM",
                "category": "Real-time Features",
                "description": "Use bidirectional streaming for real-time notifications and updates",
                "operations": [op.operation_type for op in realtime_ops],
                "benefit": "Native streaming support enables efficient real-time communication"
            })
        
        # Infrastructure recommendations
        recommendations.append({
            "priority": "LOW",
            "category": "Infrastructure",
            "description": "Implement gradual migration strategy",
            "steps": [
                "Start with internal service-to-service communication",
                "Migrate high-frequency operations first",
                "Implement gRPC-Web for browser clients",
                "Maintain REST endpoints for backward compatibility",
                "Monitor performance improvements and iterate"
            ]
        })
        
        return recommendations
    
    def create_performance_charts(self, comparisons: List[PerformanceComparison], output_dir: str = "."):
        """Create performance comparison charts"""
        
        # Response time comparison
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 12))
        
        operations = [c.operation_type for c in comparisons]
        rest_times = [c.rest_avg_response_time_ms for c in comparisons]
        grpc_times = [c.grpc_avg_response_time_ms for c in comparisons]
        
        x = range(len(operations))
        width = 0.35
        
        ax1.bar([i - width/2 for i in x], rest_times, width, label='REST', alpha=0.8)
        ax1.bar([i + width/2 for i in x], grpc_times, width, label='gRPC', alpha=0.8)
        ax1.set_ylabel('Response Time (ms)')
        ax1.set_title('Response Time Comparison')
        ax1.set_xticks(x)
        ax1.set_xticklabels(operations, rotation=45, ha='right')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # Throughput comparison
        rest_throughput = [c.rest_throughput_rps for c in comparisons]
        grpc_throughput = [c.grpc_throughput_rps for c in comparisons]
        
        ax2.bar([i - width/2 for i in x], rest_throughput, width, label='REST', alpha=0.8)
        ax2.bar([i + width/2 for i in x], grpc_throughput, width, label='gRPC', alpha=0.8)
        ax2.set_ylabel('Requests per Second')
        ax2.set_title('Throughput Comparison')
        ax2.set_xticks(x)
        ax2.set_xticklabels(operations, rotation=45, ha='right')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        # Payload size comparison
        rest_payload = [c.rest_payload_size_bytes / 1024 for c in comparisons]  # Convert to KB
        grpc_payload = [c.grpc_payload_size_bytes / 1024 for c in comparisons]  # Convert to KB
        
        ax3.bar([i - width/2 for i in x], rest_payload, width, label='REST (JSON)', alpha=0.8)
        ax3.bar([i + width/2 for i in x], grpc_payload, width, label='gRPC (Protobuf)', alpha=0.8)
        ax3.set_ylabel('Payload Size (KB)')
        ax3.set_title('Payload Size Comparison')
        ax3.set_xticks(x)
        ax3.set_xticklabels(operations, rotation=45, ha='right')
        ax3.legend()
        ax3.grid(True, alpha=0.3)
        
        # Performance improvement percentage
        improvements = [c.performance_improvement_percent for c in comparisons]
        colors = ['green' if imp > 0 else 'red' for imp in improvements]
        
        ax4.bar(x, improvements, color=colors, alpha=0.7)
        ax4.set_ylabel('Performance Improvement (%)')
        ax4.set_title('gRPC Performance Improvement vs REST')
        ax4.set_xticks(x)
        ax4.set_xticklabels(operations, rotation=45, ha='right')
        ax4.axhline(y=0, color='black', linestyle='-', alpha=0.3)
        ax4.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/performance_comparison.png", dpi=300, bbox_inches='tight')
        plt.close()
        
        # Create serialization comparison chart
        if 'serialization_comparisons' in self.grpc_results:
            self._create_serialization_chart(output_dir)
    
    def _create_serialization_chart(self, output_dir: str):
        """Create serialization performance chart"""
        
        comparisons = self.grpc_results['serialization_comparisons']
        
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
        
        operations = [c['operation'].replace('serialization_', '') for c in comparisons]
        json_sizes = [c['json_size_bytes'] / 1024 for c in comparisons]  # KB
        protobuf_sizes = [c['protobuf_size_bytes'] / 1024 for c in comparisons]  # KB
        
        x = range(len(operations))
        width = 0.35
        
        # Size comparison
        ax1.bar([i - width/2 for i in x], json_sizes, width, label='JSON', alpha=0.8)
        ax1.bar([i + width/2 for i in x], protobuf_sizes, width, label='Protobuf', alpha=0.8)
        ax1.set_ylabel('Payload Size (KB)')
        ax1.set_title('Serialization Size Comparison')
        ax1.set_xticks(x)
        ax1.set_xticklabels(operations)
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # Speed comparison
        json_times = [c['json_serialization_time_ms'] + c['json_deserialization_time_ms'] for c in comparisons]
        protobuf_times = [c['protobuf_serialization_time_ms'] + c['protobuf_deserialization_time_ms'] for c in comparisons]
        
        ax2.bar([i - width/2 for i in x], json_times, width, label='JSON', alpha=0.8)
        ax2.bar([i + width/2 for i in x], protobuf_times, width, label='Protobuf', alpha=0.8)
        ax2.set_ylabel('Serialization Time (ms)')
        ax2.set_title('Serialization Speed Comparison')
        ax2.set_xticks(x)
        ax2.set_xticklabels(operations)
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/serialization_comparison.png", dpi=300, bbox_inches='tight')
        plt.close()
    
    def generate_comprehensive_report(self, output_file: str = "performance_analysis_report.json"):
        """Generate comprehensive performance analysis report"""
        
        overall_performance = self.analyze_overall_performance()
        operation_comparisons = self.analyze_operation_patterns()
        serialization_analysis = self.analyze_serialization_performance()
        concurrency_analysis = self.analyze_concurrency_performance()
        network_analysis = self.analyze_network_efficiency()
        recommendations = self.generate_recommendations(operation_comparisons)
        
        report = {
            "executive_summary": {
                "response_time_improvement": f"{overall_performance['response_time_improvement_percent']:.1f}%",
                "throughput_improvement": f"{overall_performance['throughput_improvement_percent']:.1f}%",
                "bandwidth_reduction": f"{overall_performance['data_transfer_reduction_percent']:.1f}%",
                "key_benefits": [
                    "Faster serialization/deserialization with Protocol Buffers",
                    "HTTP/2 multiplexing eliminates head-of-line blocking",
                    "Reduced bandwidth usage with binary encoding",
                    "Built-in streaming for real-time operations",
                    "Type safety and better developer experience"
                ]
            },
            "detailed_analysis": {
                "overall_performance": overall_performance,
                "operation_comparisons": [
                    {
                        "operation_type": c.operation_type,
                        "performance_improvement_percent": c.performance_improvement_percent,
                        "throughput_improvement_percent": c.throughput_improvement_percent,
                        "payload_reduction_percent": c.payload_size_reduction_percent,
                        "rest_metrics": {
                            "avg_response_time_ms": c.rest_avg_response_time_ms,
                            "throughput_rps": c.rest_throughput_rps,
                            "payload_size_bytes": c.rest_payload_size_bytes
                        },
                        "grpc_metrics": {
                            "avg_response_time_ms": c.grpc_avg_response_time_ms,
                            "throughput_rps": c.grpc_throughput_rps,
                            "payload_size_bytes": c.grpc_payload_size_bytes
                        }
                    } for c in operation_comparisons
                ],
                "serialization_analysis": serialization_analysis,
                "concurrency_analysis": concurrency_analysis,
                "network_analysis": network_analysis
            },
            "migration_recommendations": recommendations,
            "cost_benefit_analysis": self._calculate_cost_benefits(operation_comparisons, serialization_analysis),
            "implementation_roadmap": self._create_implementation_roadmap(recommendations),
            "risk_assessment": self._assess_migration_risks()
        }
        
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        return report
    
    def _calculate_cost_benefits(self, comparisons: List[PerformanceComparison], 
                                serialization_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Calculate cost-benefit analysis for gRPC migration"""
        
        # Estimate monthly request volumes for PyAirtable
        monthly_volumes = {
            "authentication": 2000000,      # 2M auth requests
            "workspace_management": 500000,  # 500K workspace ops
            "airtable_operations": 1000000,  # 1M Airtable API calls
            "bulk_operations": 50000,        # 50K bulk operations
            "real_time": 5000000,           # 5M real-time checks
            "file_operations": 100000        # 100K file operations
        }
        
        total_cost_savings = 0
        performance_benefits = {}
        
        for comp in comparisons:
            monthly_reqs = monthly_volumes.get(comp.operation_type, 100000)
            
            # Infrastructure cost savings (reduced CPU/memory from better performance)
            cpu_savings_percent = comp.performance_improvement_percent / 100
            estimated_monthly_cpu_cost = 500  # $500/month baseline
            cpu_savings = estimated_monthly_cpu_cost * cpu_savings_percent
            
            # Bandwidth cost savings
            bandwidth_reduction = comp.payload_size_reduction_percent / 100
            avg_response_size_kb = comp.rest_payload_size_bytes / 1024
            monthly_data_gb = (monthly_reqs * avg_response_size_kb) / (1024 * 1024)
            bandwidth_cost_per_gb = 0.09  # $0.09/GB typical CDN cost
            bandwidth_savings = monthly_data_gb * bandwidth_reduction * bandwidth_cost_per_gb
            
            total_savings = cpu_savings + bandwidth_savings
            total_cost_savings += total_savings
            
            performance_benefits[comp.operation_type] = {
                "monthly_requests": monthly_reqs,
                "performance_improvement_percent": comp.performance_improvement_percent,
                "monthly_cpu_savings": cpu_savings,
                "monthly_bandwidth_savings": bandwidth_savings,
                "total_monthly_savings": total_savings
            }
        
        # Development and migration costs
        migration_costs = {
            "initial_development": 50000,      # $50K for initial gRPC implementation
            "testing_and_qa": 15000,          # $15K for testing
            "deployment_and_ops": 10000,      # $10K for deployment setup
            "training": 5000,                 # $5K for team training
            "total_one_time": 80000
        }
        
        # Calculate ROI
        monthly_savings = total_cost_savings
        annual_savings = monthly_savings * 12
        roi_months = migration_costs["total_one_time"] / monthly_savings if monthly_savings > 0 else float('inf')
        
        return {
            "monthly_savings": monthly_savings,
            "annual_savings": annual_savings,
            "migration_costs": migration_costs,
            "roi_timeline_months": roi_months,
            "break_even_point": f"{roi_months:.1f} months" if roi_months != float('inf') else "No break-even",
            "performance_benefits_by_operation": performance_benefits,
            "additional_benefits": {
                "developer_productivity": "15-25% improvement in API development speed",
                "system_reliability": "Better error handling and circuit breaking",
                "monitoring_visibility": "Rich metrics and distributed tracing",
                "scalability": "Better handling of high-concurrency scenarios"
            }
        }
    
    def _create_implementation_roadmap(self, recommendations: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Create implementation roadmap for gRPC migration"""
        
        return {
            "phase_1_foundations": {
                "duration": "2-3 months",
                "objectives": [
                    "Set up gRPC infrastructure and tooling",
                    "Implement core service protobuf definitions",
                    "Create gRPC server framework and middleware",
                    "Establish monitoring and observability"
                ],
                "deliverables": [
                    "gRPC service templates and code generation",
                    "Authentication and authorization middleware",
                    "Load balancing and service discovery",
                    "Metrics and tracing integration"
                ]
            },
            "phase_2_high_impact_migration": {
                "duration": "3-4 months",
                "objectives": [
                    "Migrate high-frequency operations (auth, permissions)",
                    "Implement connection pooling and optimization",
                    "Add circuit breaking and fault tolerance",
                    "Performance testing and optimization"
                ],
                "operations_to_migrate": [
                    rec["operations"] for rec in recommendations 
                    if rec["priority"] == "HIGH"
                ],
                "success_metrics": [
                    "30%+ improvement in auth operation response times",
                    "50%+ increase in concurrent request handling",
                    "Reduced error rates under load"
                ]
            },
            "phase_3_bulk_and_streaming": {
                "duration": "2-3 months",
                "objectives": [
                    "Implement streaming operations for bulk data",
                    "Add bidirectional streaming for real-time features",
                    "Optimize memory usage for large datasets",
                    "Enhanced client libraries"
                ],
                "features": [
                    "Streaming record uploads/downloads",
                    "Real-time notification streaming",
                    "Progressive file processing",
                    "Webhook streaming endpoints"
                ]
            },
            "phase_4_full_migration": {
                "duration": "2-3 months",
                "objectives": [
                    "Complete migration of remaining operations",
                    "Deprecate REST endpoints gradually",
                    "Client-side optimization and caching",
                    "Performance monitoring and alerting"
                ],
                "cleanup_tasks": [
                    "Remove deprecated REST endpoints",
                    "Consolidate authentication mechanisms",
                    "Update documentation and examples",
                    "Performance benchmarking and reports"
                ]
            }
        }
    
    def _assess_migration_risks(self) -> Dict[str, Any]:
        """Assess risks associated with gRPC migration"""
        
        return {
            "technical_risks": {
                "learning_curve": {
                    "risk_level": "MEDIUM",
                    "description": "Team needs to learn Protocol Buffers and gRPC concepts",
                    "mitigation": "Provide training and start with simple services"
                },
                "debugging_complexity": {
                    "risk_level": "MEDIUM", 
                    "description": "Binary protocol makes debugging more challenging",
                    "mitigation": "Implement comprehensive logging and use gRPC debugging tools"
                },
                "browser_compatibility": {
                    "risk_level": "LOW",
                    "description": "Direct gRPC not supported in browsers",
                    "mitigation": "Use gRPC-Web or maintain REST endpoints for browser clients"
                },
                "ecosystem_maturity": {
                    "risk_level": "LOW",
                    "description": "gRPC ecosystem less mature than REST for some tools",
                    "mitigation": "Evaluate tooling requirements before migration"
                }
            },
            "operational_risks": {
                "deployment_complexity": {
                    "risk_level": "MEDIUM",
                    "description": "gRPC requires HTTP/2 and proper load balancer configuration",
                    "mitigation": "Test thoroughly in staging and use proven infrastructure"
                },
                "monitoring_gaps": {
                    "risk_level": "LOW",
                    "description": "Need to adapt monitoring tools for gRPC",
                    "mitigation": "Implement gRPC-specific metrics and dashboards"
                },
                "rollback_complexity": {
                    "risk_level": "MEDIUM",
                    "description": "Rolling back from gRPC to REST requires careful planning",
                    "mitigation": "Maintain dual protocol support during transition"
                }
            },
            "business_risks": {
                "migration_timeline": {
                    "risk_level": "MEDIUM",
                    "description": "Migration may take longer than expected",
                    "mitigation": "Plan incremental migration and maintain backward compatibility"
                },
                "client_integration": {
                    "risk_level": "LOW",
                    "description": "External clients may struggle with gRPC adoption",
                    "mitigation": "Maintain REST API alongside gRPC for external clients"
                }
            },
            "overall_risk_assessment": "MEDIUM-LOW",
            "risk_mitigation_strategies": [
                "Start with internal service-to-service communication",
                "Maintain REST endpoints during transition period",
                "Implement comprehensive testing and monitoring",
                "Train team on gRPC best practices",
                "Use proven gRPC infrastructure patterns"
            ]
        }

def main():
    parser = argparse.ArgumentParser(description='REST vs gRPC Performance Analysis')
    parser.add_argument('--rest-results', required=True, help='REST benchmark results JSON file')
    parser.add_argument('--grpc-results', required=True, help='gRPC benchmark results JSON file')
    parser.add_argument('--output', default='performance_analysis_report.json', help='Output analysis file')
    parser.add_argument('--create-charts', action='store_true', help='Create performance charts')
    
    args = parser.parse_args()
    
    analyzer = PerformanceAnalyzer(args.rest_results, args.grpc_results)
    
    # Generate comprehensive report
    report = analyzer.generate_comprehensive_report(args.output)
    
    # Create charts if requested
    if args.create_charts:
        try:
            import matplotlib.pyplot as plt
            operation_comparisons = analyzer.analyze_operation_patterns()
            analyzer.create_performance_charts(operation_comparisons)
            print("Performance charts created: performance_comparison.png, serialization_comparison.png")
        except ImportError:
            print("matplotlib not available, skipping chart creation")
    
    # Print executive summary
    summary = report['executive_summary']
    print("\n" + "="*80)
    print("REST vs gRPC PERFORMANCE ANALYSIS")
    print("="*80)
    print(f"Response Time Improvement: {summary['response_time_improvement']}")
    print(f"Throughput Improvement: {summary['throughput_improvement']}")
    print(f"Bandwidth Reduction: {summary['bandwidth_reduction']}")
    
    print("\nKEY BENEFITS:")
    for benefit in summary['key_benefits']:
        print(f"  • {benefit}")
    
    # Print cost analysis
    cost_analysis = report['cost_benefit_analysis']
    print(f"\nCOST-BENEFIT ANALYSIS:")
    print(f"Monthly Savings: ${cost_analysis['monthly_savings']:.2f}")
    print(f"Annual Savings: ${cost_analysis['annual_savings']:.2f}")
    print(f"Migration Cost: ${cost_analysis['migration_costs']['total_one_time']:,}")
    print(f"ROI Timeline: {cost_analysis['roi_timeline_months']:.1f} months")
    
    # Print top recommendations
    print(f"\nTOP RECOMMENDATIONS:")
    for i, rec in enumerate(report['migration_recommendations'][:3], 1):
        print(f"  {i}. [{rec['priority']}] {rec['category']}: {rec['description']}")
    
    print(f"\nDetailed analysis saved to: {args.output}")

if __name__ == '__main__':
    main()