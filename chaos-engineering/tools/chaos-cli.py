#!/usr/bin/env python3
"""
PyAirtable Chaos Engineering CLI Tool

A command-line interface for managing chaos engineering experiments
on the PyAirtable platform.
"""

import argparse
import sys
import os
import subprocess
import json
import yaml
import time
from datetime import datetime
from pathlib import Path

class ChaosCLI:
    def __init__(self):
        self.base_path = Path(__file__).parent.parent
        self.experiments_path = self.base_path / "experiments"
        self.scenarios_path = self.base_path / "scenarios"
        
    def run_command(self, command, check=True):
        """Execute a shell command and return the result"""
        try:
            result = subprocess.run(
                command, shell=True, capture_output=True, text=True, check=check
            )
            return result
        except subprocess.CalledProcessError as e:
            print(f"❌ Command failed: {e}")
            print(f"stdout: {e.stdout}")
            print(f"stderr: {e.stderr}")
            return None

    def list_experiments(self):
        """List available chaos experiments"""
        print("🧪 Available Chaos Experiments:")
        print("=" * 50)
        
        experiments = {
            "basic-pod-failure": "Test pod restart and recovery mechanisms",
            "network-resilience": "Test network delays, partitions, and packet loss",
            "database-stress": "Test database connection failures and I/O stress",
            "cache-unavailability": "Test Redis cache failures and recovery",
            "resource-exhaustion": "Test CPU, memory, and disk stress scenarios",
            "resilience-testing": "Test circuit breakers, retries, and fallbacks",
            "full-resilience-suite": "Complete end-to-end resilience testing",
            "disaster-recovery": "Test major multi-component failures"
        }
        
        for name, description in experiments.items():
            print(f"  📋 {name:<25} {description}")
        
        print("\nUsage: chaos run <experiment-name> [options]")

    def check_prerequisites(self):
        """Check if all prerequisites are met"""
        print("🔍 Checking prerequisites...")
        
        checks = [
            ("kubectl", "kubectl version --client"),
            ("Chaos Mesh", "kubectl get pods -n chaos-engineering"),
            ("PyAirtable services", "kubectl get pods -n pyairtable"),
            ("Monitoring", "kubectl get pods -n monitoring")
        ]
        
        all_good = True
        for name, command in checks:
            result = self.run_command(command, check=False)
            if result and result.returncode == 0:
                print(f"  ✅ {name}: OK")
            else:
                print(f"  ❌ {name}: FAILED")
                all_good = False
        
        return all_good

    def health_check(self, phase="pre"):
        """Run system health check"""
        print(f"🏥 Running {phase}-experiment health check...")
        
        script_path = self.experiments_path / "health-check.sh"
        if not script_path.exists():
            print(f"❌ Health check script not found: {script_path}")
            return False
        
        result = self.run_command(f"bash {script_path} {phase}")
        return result is not None and result.returncode == 0

    def run_experiment(self, experiment_name, duration="5m", dry_run=False):
        """Run a chaos experiment"""
        if not self.check_prerequisites():
            print("❌ Prerequisites check failed. Please fix issues before running experiments.")
            return False
        
        if not self.health_check("pre"):
            print("❌ Pre-experiment health check failed. Aborting experiment.")
            return False
        
        print(f"🚀 Starting chaos experiment: {experiment_name}")
        print(f"⏱️ Duration: {duration}")
        print(f"🎯 Dry run: {dry_run}")
        
        # Build command
        script_path = self.experiments_path / "run-experiment.sh"
        command = f"bash {script_path} {experiment_name} {duration}"
        if dry_run:
            command += " --dry-run"
        
        # Run experiment
        start_time = datetime.now()
        result = self.run_command(command)
        end_time = datetime.now()
        
        if result and result.returncode == 0:
            print(f"✅ Experiment completed successfully!")
            print(f"⏱️ Total time: {end_time - start_time}")
            
            # Run post-experiment health check
            if not dry_run:
                self.health_check("post")
            
            return True
        else:
            print(f"❌ Experiment failed!")
            return False

    def emergency_stop(self):
        """Trigger emergency stop of all experiments"""
        print("🚨 EMERGENCY STOP - Halting all chaos experiments!")
        
        confirm = input("Are you sure you want to stop all experiments? (yes/no): ")
        if confirm.lower() != "yes":
            print("Emergency stop cancelled.")
            return
        
        script_path = self.base_path / "safety" / "emergency-stop.sh"
        if not script_path.exists():
            print(f"❌ Emergency stop script not found: {script_path}")
            return
        
        result = self.run_command(f"bash {script_path}")
        if result and result.returncode == 0:
            print("✅ Emergency stop completed successfully!")
        else:
            print("❌ Emergency stop failed! Manual intervention required.")

    def status(self):
        """Show current status of chaos experiments"""
        print("📊 Chaos Engineering Status")
        print("=" * 40)
        
        # Check running experiments
        print("\n🧪 Running Experiments:")
        result = self.run_command("kubectl get workflows -n chaos-engineering", check=False)
        if result and result.returncode == 0:
            if "No resources found" in result.stdout:
                print("  No workflows running")
            else:
                print(result.stdout)
        
        # Check chaos resources
        chaos_types = ["podchaos", "networkchaos", "stresschaos", "iochaos"]
        for chaos_type in chaos_types:
            result = self.run_command(f"kubectl get {chaos_type} -n chaos-engineering", check=False)
            if result and result.returncode == 0 and "No resources found" not in result.stdout:
                print(f"\n{chaos_type.upper()}:")
                print(result.stdout)
        
        # Check system health
        print("\n🏥 System Health:")
        services = ["api-gateway", "auth-service", "platform-services", "postgres", "redis"]
        for service in services:
            result = self.run_command(f"kubectl get pods -n pyairtable -l app={service}", check=False)
            if result and result.returncode == 0:
                running_pods = result.stdout.count("Running")
                total_pods = result.stdout.count(service) if service in result.stdout else 0
                if total_pods > 0:
                    print(f"  {service}: {running_pods}/{total_pods} pods running")
                else:
                    print(f"  {service}: No pods found")

    def install(self):
        """Install Chaos Mesh and monitoring components"""
        print("📦 Installing PyAirtable Chaos Engineering Framework...")
        
        # Install Chaos Mesh
        print("\n1. Installing Chaos Mesh...")
        script_path = self.base_path / "chaos-mesh" / "install.sh"
        if script_path.exists():
            result = self.run_command(f"bash {script_path}")
            if result and result.returncode == 0:
                print("✅ Chaos Mesh installed successfully!")
            else:
                print("❌ Chaos Mesh installation failed!")
                return False
        
        # Install monitoring
        print("\n2. Installing monitoring components...")
        monitoring_files = [
            self.base_path / "observability" / "chaos-monitoring.yaml",
            self.base_path / "observability" / "grafana-dashboards.yaml"
        ]
        
        for file_path in monitoring_files:
            if file_path.exists():
                result = self.run_command(f"kubectl apply -f {file_path}")
                if result and result.returncode == 0:
                    print(f"✅ Applied {file_path.name}")
                else:
                    print(f"❌ Failed to apply {file_path.name}")
        
        # Install safety guardrails
        print("\n3. Installing safety guardrails...")
        guardrails_path = self.base_path / "safety" / "guardrails.yaml"
        if guardrails_path.exists():
            result = self.run_command(f"kubectl apply -f {guardrails_path}")
            if result and result.returncode == 0:
                print("✅ Safety guardrails installed!")
            else:
                print("❌ Failed to install safety guardrails!")
        
        print("\n🎉 Installation completed!")
        print("\nNext steps:")
        print("1. Port-forward dashboards:")
        print("   kubectl port-forward svc/chaos-dashboard 2333:2333 -n chaos-engineering")
        print("   kubectl port-forward svc/chaos-grafana 3000:3000 -n chaos-engineering")
        print("2. Run your first experiment:")
        print("   chaos run basic-pod-failure")

    def uninstall(self):
        """Uninstall Chaos Mesh and components"""
        print("🗑️ Uninstalling PyAirtable Chaos Engineering Framework...")
        
        confirm = input("Are you sure you want to uninstall everything? (yes/no): ")
        if confirm.lower() != "yes":
            print("Uninstall cancelled.")
            return
        
        # Stop all experiments first
        self.emergency_stop()
        
        # Uninstall Chaos Mesh
        script_path = self.base_path / "chaos-mesh" / "uninstall.sh"
        if script_path.exists():
            result = self.run_command(f"bash {script_path}")
            if result and result.returncode == 0:
                print("✅ Chaos Mesh uninstalled!")
        
        # Remove monitoring components
        self.run_command("kubectl delete namespace chaos-engineering --ignore-not-found=true")
        
        print("✅ Uninstall completed!")

    def logs(self, component="all"):
        """Show logs from chaos engineering components"""
        print(f"📋 Showing logs for: {component}")
        
        if component == "all" or component == "controller":
            print("\n=== Chaos Mesh Controller ===")
            self.run_command("kubectl logs -n chaos-engineering -l app.kubernetes.io/component=controller-manager --tail=50")
        
        if component == "all" or component == "dashboard":
            print("\n=== Chaos Dashboard ===")
            self.run_command("kubectl logs -n chaos-engineering -l app.kubernetes.io/component=chaos-dashboard --tail=50")
        
        if component == "all" or component == "daemon":
            print("\n=== Chaos Daemon ===")
            self.run_command("kubectl logs -n chaos-engineering -l app.kubernetes.io/component=chaos-daemon --tail=50")

def main():
    parser = argparse.ArgumentParser(
        description="PyAirtable Chaos Engineering CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  chaos list                          # List available experiments
  chaos run basic-pod-failure         # Run basic pod failure test
  chaos run network-resilience 10m    # Run network test for 10 minutes
  chaos run database-stress --dry-run # Dry run database stress test
  chaos status                        # Show current experiment status
  chaos stop                          # Emergency stop all experiments
  chaos install                       # Install chaos engineering framework
  chaos health                        # Run health check
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # List command
    subparsers.add_parser('list', help='List available experiments')
    
    # Run command
    run_parser = subparsers.add_parser('run', help='Run a chaos experiment')
    run_parser.add_argument('experiment', help='Experiment name')
    run_parser.add_argument('duration', nargs='?', default='5m', help='Experiment duration (default: 5m)')
    run_parser.add_argument('--dry-run', action='store_true', help='Dry run mode')
    
    # Status command
    subparsers.add_parser('status', help='Show experiment status')
    
    # Stop command
    subparsers.add_parser('stop', help='Emergency stop all experiments')
    
    # Health command
    health_parser = subparsers.add_parser('health', help='Run health check')
    health_parser.add_argument('phase', nargs='?', default='pre', choices=['pre', 'post'], help='Health check phase')
    
    # Install command
    subparsers.add_parser('install', help='Install chaos engineering framework')
    
    # Uninstall command
    subparsers.add_parser('uninstall', help='Uninstall chaos engineering framework')
    
    # Logs command
    logs_parser = subparsers.add_parser('logs', help='Show component logs')
    logs_parser.add_argument('component', nargs='?', default='all', 
                           choices=['all', 'controller', 'dashboard', 'daemon'],
                           help='Component to show logs for')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    cli = ChaosCLI()
    
    try:
        if args.command == 'list':
            cli.list_experiments()
        elif args.command == 'run':
            cli.run_experiment(args.experiment, args.duration, args.dry_run)
        elif args.command == 'status':
            cli.status()
        elif args.command == 'stop':
            cli.emergency_stop()
        elif args.command == 'health':
            cli.health_check(args.phase)
        elif args.command == 'install':
            cli.install()
        elif args.command == 'uninstall':
            cli.uninstall()
        elif args.command == 'logs':
            cli.logs(args.component)
    except KeyboardInterrupt:
        print("\n❌ Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()