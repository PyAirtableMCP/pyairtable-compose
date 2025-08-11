#!/usr/bin/env python3
"""
Emergency Stabilization Day 5: Monitoring System Test
Test the complete monitoring system functionality.
"""

import asyncio
import aiohttp
import json
import time
import sys
import os
from datetime import datetime

async def test_health_check():
    """Test the health check script"""
    print("🔍 Testing Health Check Script...")
    
    # Import and test the health checker
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    
    try:
        # Fix import by replacing hyphens with underscores
        import importlib.util
        spec = importlib.util.spec_from_file_location("health_check", os.path.join(os.path.dirname(__file__), "health-check.py"))
        health_check_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(health_check_module)
        run_single_check = health_check_module.run_single_check
        summary = await run_single_check()
        
        print(f"✅ Health check completed")
        print(f"   - Total services: {summary.total_services}")
        print(f"   - Healthy: {summary.healthy_services}")
        print(f"   - Degraded: {summary.degraded_services}")
        print(f"   - Failed: {summary.failed_services}")
        
        return True
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False

async def test_dashboard_api():
    """Test the dashboard API endpoint"""
    print("\n📊 Testing Dashboard API...")
    
    dashboard_url = "http://localhost:9999"
    health_api_url = f"{dashboard_url}/health"
    
    try:
        async with aiohttp.ClientSession() as session:
            # Test health API endpoint
            async with session.get(health_api_url, timeout=aiohttp.ClientTimeout(total=10)) as response:
                if response.status == 200:
                    data = await response.json()
                    print(f"✅ Dashboard API responding")
                    print(f"   - Services monitored: {data.get('total_services', 'unknown')}")
                    print(f"   - Dashboard URL: {dashboard_url}")
                    return True
                else:
                    print(f"❌ Dashboard API returned status {response.status}")
                    return False
    except Exception as e:
        print(f"❌ Dashboard API test failed: {e}")
        print(f"   (This is expected if dashboard is not running)")
        return False

def test_alert_manager():
    """Test the alert manager functionality"""
    print("\n🚨 Testing Alert Manager...")
    
    try:
        sys.path.append(os.path.dirname(os.path.abspath(__file__)))
        import importlib.util
        spec = importlib.util.spec_from_file_location("alert_manager", os.path.join(os.path.dirname(__file__), "alert-manager.py"))
        alert_manager_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(alert_manager_module)
        AlertManager = alert_manager_module.AlertManager
        
        # Create test alert manager
        alert_manager = AlertManager()
        
        # Test rule evaluation with mock data
        mock_health_data = {
            "services": [
                {
                    "name": "test-service",
                    "status": "DOWN",
                    "response_time_ms": None,
                    "error_message": "Connection refused"
                }
            ]
        }
        
        # Evaluate rules
        alert_manager.evaluate_rules(mock_health_data)
        
        # Check alert summary
        summary = alert_manager.get_alert_summary()
        
        print(f"✅ Alert manager functional")
        print(f"   - Alert rules loaded: {len(alert_manager.alert_rules)}")
        print(f"   - Active alerts: {summary['active_alerts']}")
        
        return True
    except Exception as e:
        print(f"❌ Alert manager test failed: {e}")
        return False

def test_file_system():
    """Test file system components"""
    print("\n📁 Testing File System Components...")
    
    test_files = [
        '/tmp/health-status.json',
        '/tmp/health-monitor.log',
        '/tmp/alert-manager.log'
    ]
    
    results = []
    for file_path in test_files:
        if os.path.exists(file_path):
            print(f"✅ Found: {file_path}")
            
            # Check if file is readable and has recent content
            try:
                stat = os.stat(file_path)
                age_seconds = time.time() - stat.st_mtime
                if age_seconds < 300:  # Less than 5 minutes old
                    print(f"   - Recent data (age: {int(age_seconds)}s)")
                else:
                    print(f"   - Stale data (age: {int(age_seconds/60)}m)")
                results.append(True)
            except Exception as e:
                print(f"   - Error reading file: {e}")
                results.append(False)
        else:
            print(f"⚠️  Missing: {file_path}")
            results.append(False)
    
    return all(results)

def check_processes():
    """Check if monitoring processes are running"""
    print("\n🔄 Checking Running Processes...")
    
    pid_files = [
        '/tmp/monitoring-logs/health-checker.pid',
        '/tmp/monitoring-logs/alert-manager.pid',
        '/tmp/monitoring-logs/dashboard.pid'
    ]
    
    running_processes = []
    for pid_file in pid_files:
        if os.path.exists(pid_file):
            try:
                with open(pid_file, 'r') as f:
                    pid = int(f.read().strip())
                
                # Check if process is running
                try:
                    os.kill(pid, 0)  # Signal 0 just checks if process exists
                    process_name = os.path.basename(pid_file).replace('.pid', '')
                    print(f"✅ {process_name} running (PID: {pid})")
                    running_processes.append(process_name)
                except OSError:
                    process_name = os.path.basename(pid_file).replace('.pid', '')
                    print(f"❌ {process_name} not running (stale PID file)")
            except Exception as e:
                print(f"❌ Error checking {pid_file}: {e}")
        else:
            process_name = os.path.basename(pid_file).replace('.pid', '')
            print(f"⚠️  {process_name} PID file not found")
    
    return len(running_processes) > 0

async def run_comprehensive_test():
    """Run comprehensive monitoring system test"""
    print("🧪 PyAirtable Monitoring System Test")
    print("=" * 50)
    
    test_results = []
    
    # Test individual components
    test_results.append(await test_health_check())
    test_results.append(await test_dashboard_api())
    test_results.append(test_alert_manager())
    test_results.append(test_file_system())
    
    # Check running processes
    processes_running = check_processes()
    test_results.append(processes_running)
    
    # Summary
    print(f"\n📋 Test Summary")
    print("=" * 50)
    
    passed_tests = sum(test_results)
    total_tests = len(test_results)
    
    print(f"Tests passed: {passed_tests}/{total_tests}")
    
    if passed_tests == total_tests:
        print("🎉 All tests passed! Monitoring system is working correctly.")
        return True
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        
        if not processes_running:
            print("\n💡 To start the monitoring system, run:")
            print("   ./scripts/start-monitoring.sh")
        
        return False

def print_monitoring_status():
    """Print current monitoring system status"""
    print("\n📊 Current Monitoring Status")
    print("=" * 50)
    
    # Check health status file
    health_file = '/tmp/health-status.json'
    if os.path.exists(health_file):
        try:
            with open(health_file, 'r') as f:
                health_data = json.load(f)
            
            print(f"Last health check: {health_data.get('timestamp', 'unknown')}")
            print(f"Services monitored: {health_data.get('total_services', 0)}")
            print(f"Healthy services: {health_data.get('healthy_services', 0)}")
            print(f"Failed services: {health_data.get('failed_services', 0)}")
            
            if health_data.get('failed_services', 0) > 0:
                print("\n❌ Failed Services:")
                for service in health_data.get('services', []):
                    if service.get('status') == 'DOWN':
                        print(f"   - {service['name']}: {service.get('error_message', 'Unknown error')}")
        except Exception as e:
            print(f"Error reading health status: {e}")
    else:
        print("No health status data available")
    
    # Check alert status
    alert_file = '/tmp/alerts.log'
    if os.path.exists(alert_file):
        try:
            with open(alert_file, 'r') as f:
                lines = f.readlines()
            
            recent_alerts = [line for line in lines if line.strip()][-10:]  # Last 10 alerts
            if recent_alerts:
                print(f"\n🚨 Recent Alerts ({len(recent_alerts)} shown):")
                for alert in recent_alerts:
                    print(f"   {alert.strip()}")
            else:
                print("\n✅ No recent alerts")
        except Exception as e:
            print(f"Error reading alerts: {e}")
    else:
        print("\n✅ No alert log found")

async def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Test PyAirtable Monitoring System",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--comprehensive',
        action='store_true',
        help='Run comprehensive test suite'
    )
    
    parser.add_argument(
        '--status',
        action='store_true',
        help='Show current monitoring status'
    )
    
    args = parser.parse_args()
    
    if not args.comprehensive and not args.status:
        args.comprehensive = True  # Default to comprehensive test
    
    try:
        if args.comprehensive:
            success = await run_comprehensive_test()
            if success:
                print_monitoring_status()
                sys.exit(0)
            else:
                sys.exit(1)
        
        if args.status:
            print_monitoring_status()
    
    except KeyboardInterrupt:
        print("\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"Test failed with error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())