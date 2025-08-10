#!/usr/bin/env python3
"""
Comprehensive test coverage reporter that aggregates coverage data
from Python, Go, and JavaScript/TypeScript tests and generates
unified coverage reports with trends and notifications.
"""

import os
import json
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
import subprocess
import re


class CoverageReporter:
    """Unified coverage reporter for multi-language projects."""
    
    def __init__(self, project_root: str = None):
        self.project_root = Path(project_root or os.getcwd())
        self.coverage_dir = self.project_root / "coverage"
        self.reports_dir = self.coverage_dir / "reports"
        self.history_dir = self.coverage_dir / "history"
        
        # Create directories
        self.coverage_dir.mkdir(exist_ok=True)
        self.reports_dir.mkdir(exist_ok=True)
        self.history_dir.mkdir(exist_ok=True)
        
        # Load configuration
        config_path = self.project_root / "tests" / "coverage-config.json"
        with open(config_path) as f:
            self.config = json.load(f)
    
    def collect_python_coverage(self) -> Dict[str, Any]:
        """Collect coverage data from Python tests."""
        coverage_data = {
            "language": "python",
            "total_coverage": 0,
            "line_coverage": 0,
            "branch_coverage": 0,
            "services": {},
            "critical_modules": {},
            "files": []
        }
        
        try:
            # Look for coverage files
            coverage_files = list(self.coverage_dir.glob("**/python/**/coverage.json"))
            
            if not coverage_files:
                print("No Python coverage files found")
                return coverage_data
            
            total_lines = 0
            covered_lines = 0
            total_branches = 0
            covered_branches = 0
            
            for coverage_file in coverage_files:
                try:
                    with open(coverage_file) as f:
                        data = json.load(f)
                    
                    # Parse coverage.py JSON format
                    if "totals" in data:
                        totals = data["totals"]
                        file_lines = totals.get("num_statements", 0)
                        file_covered = totals.get("covered_lines", 0)
                        file_branches = totals.get("num_branches", 0)
                        file_branch_covered = totals.get("covered_branches", 0)
                        
                        total_lines += file_lines
                        covered_lines += file_covered
                        total_branches += file_branches
                        covered_branches += file_branch_covered
                    
                    # Process individual files
                    if "files" in data:
                        for filepath, file_data in data["files"].items():
                            summary = file_data.get("summary", {})
                            coverage_data["files"].append({
                                "path": filepath,
                                "line_coverage": summary.get("percent_covered", 0),
                                "lines_total": summary.get("num_statements", 0),
                                "lines_covered": summary.get("covered_lines", 0),
                                "branches_total": summary.get("num_branches", 0),
                                "branches_covered": summary.get("covered_branches", 0)
                            })
                
                except Exception as e:
                    print(f"Error processing Python coverage file {coverage_file}: {e}")
            
            # Calculate overall coverage
            if total_lines > 0:
                coverage_data["line_coverage"] = round((covered_lines / total_lines) * 100, 2)
            if total_branches > 0:
                coverage_data["branch_coverage"] = round((covered_branches / total_branches) * 100, 2)
            
            # Total coverage is typically line coverage
            coverage_data["total_coverage"] = coverage_data["line_coverage"]
            
            # Analyze by service
            self._analyze_python_services(coverage_data)
            
        except Exception as e:
            print(f"Error collecting Python coverage: {e}")
        
        return coverage_data
    
    def collect_go_coverage(self) -> Dict[str, Any]:
        """Collect coverage data from Go tests."""
        coverage_data = {
            "language": "go",
            "total_coverage": 0,
            "packages": {},
            "critical_packages": {},
            "files": []
        }
        
        try:
            # Look for Go coverage files
            coverage_files = list(self.coverage_dir.glob("**/go/**/*.out"))
            
            if not coverage_files:
                print("No Go coverage files found")
                return coverage_data
            
            total_statements = 0
            covered_statements = 0
            
            for coverage_file in coverage_files:
                try:
                    # Parse Go coverage profile
                    coverage_data_file = self._parse_go_coverage_profile(coverage_file)
                    
                    for file_data in coverage_data_file:
                        total_statements += file_data["statements_total"]
                        covered_statements += file_data["statements_covered"]
                        coverage_data["files"].append(file_data)
                
                except Exception as e:
                    print(f"Error processing Go coverage file {coverage_file}: {e}")
            
            # Calculate overall coverage
            if total_statements > 0:
                coverage_data["total_coverage"] = round((covered_statements / total_statements) * 100, 2)
            
            # Analyze by package
            self._analyze_go_packages(coverage_data)
            
        except Exception as e:
            print(f"Error collecting Go coverage: {e}")
        
        return coverage_data
    
    def collect_javascript_coverage(self) -> Dict[str, Any]:
        """Collect coverage data from JavaScript/TypeScript tests."""
        coverage_data = {
            "language": "javascript",
            "total_coverage": 0,
            "line_coverage": 0,
            "branch_coverage": 0,
            "function_coverage": 0,
            "statement_coverage": 0,
            "services": {},
            "files": []
        }
        
        try:
            # Look for Jest/NYC coverage files
            coverage_files = list(self.coverage_dir.glob("**/frontend/**/coverage-final.json"))
            coverage_files.extend(list(self.coverage_dir.glob("**/frontend/**/lcov.info")))
            
            if not coverage_files:
                print("No JavaScript coverage files found")
                return coverage_data
            
            for coverage_file in coverage_files:
                try:
                    if coverage_file.name.endswith('.json'):
                        self._parse_jest_coverage(coverage_file, coverage_data)
                    elif coverage_file.name.endswith('.info'):
                        self._parse_lcov_coverage(coverage_file, coverage_data)
                
                except Exception as e:
                    print(f"Error processing JS coverage file {coverage_file}: {e}")
            
            # Analyze by service
            self._analyze_javascript_services(coverage_data)
            
        except Exception as e:
            print(f"Error collecting JavaScript coverage: {e}")
        
        return coverage_data
    
    def _parse_go_coverage_profile(self, coverage_file: Path) -> List[Dict[str, Any]]:
        """Parse Go coverage profile format."""
        files_data = []
        
        with open(coverage_file) as f:
            lines = f.readlines()
        
        # Skip the first line (mode)
        current_file = None
        file_blocks = {}
        
        for line in lines[1:]:
            parts = line.strip().split()
            if len(parts) < 3:
                continue
            
            file_path = parts[0].split(':')[0]
            count = int(parts[2])
            
            if file_path not in file_blocks:
                file_blocks[file_path] = []
            
            file_blocks[file_path].append(count)
        
        # Calculate coverage for each file
        for file_path, blocks in file_blocks.items():
            total_blocks = len(blocks)
            covered_blocks = sum(1 for count in blocks if count > 0)
            coverage_percent = (covered_blocks / total_blocks * 100) if total_blocks > 0 else 0
            
            files_data.append({
                "path": file_path,
                "coverage": round(coverage_percent, 2),
                "statements_total": total_blocks,
                "statements_covered": covered_blocks
            })
        
        return files_data
    
    def _parse_jest_coverage(self, coverage_file: Path, coverage_data: Dict):
        """Parse Jest coverage JSON format."""
        with open(coverage_file) as f:
            data = json.load(f)
        
        total_lines = 0
        covered_lines = 0
        total_functions = 0
        covered_functions = 0
        total_branches = 0
        covered_branches = 0
        total_statements = 0
        covered_statements = 0
        
        for filepath, file_data in data.items():
            if filepath.startswith('/'):
                # Skip absolute paths that are outside project
                continue
            
            lines = file_data.get("l", {})
            functions = file_data.get("f", {})
            branches = file_data.get("b", {})
            statements = file_data.get("s", {})
            
            # Count covered items
            file_covered_lines = sum(1 for count in lines.values() if count > 0)
            file_covered_functions = sum(1 for count in functions.values() if count > 0)
            file_covered_statements = sum(1 for count in statements.values() if count > 0)
            
            total_lines += len(lines)
            covered_lines += file_covered_lines
            total_functions += len(functions)
            covered_functions += file_covered_functions
            total_statements += len(statements)
            covered_statements += file_covered_statements
            
            # Branches are more complex in Jest format
            file_covered_branches = 0
            file_total_branches = 0
            for branch_data in branches.values():
                if isinstance(branch_data, list):
                    file_total_branches += len(branch_data)
                    file_covered_branches += sum(1 for count in branch_data if count > 0)
            
            total_branches += file_total_branches
            covered_branches += file_covered_branches
            
            # Add file data
            file_coverage = {
                "path": filepath,
                "line_coverage": (file_covered_lines / len(lines) * 100) if lines else 0,
                "function_coverage": (file_covered_functions / len(functions) * 100) if functions else 0,
                "statement_coverage": (file_covered_statements / len(statements) * 100) if statements else 0,
                "branch_coverage": (file_covered_branches / file_total_branches * 100) if file_total_branches else 0
            }
            coverage_data["files"].append(file_coverage)
        
        # Calculate totals
        if total_lines > 0:
            coverage_data["line_coverage"] = round((covered_lines / total_lines) * 100, 2)
        if total_functions > 0:
            coverage_data["function_coverage"] = round((covered_functions / total_functions) * 100, 2)
        if total_branches > 0:
            coverage_data["branch_coverage"] = round((covered_branches / total_branches) * 100, 2)
        if total_statements > 0:
            coverage_data["statement_coverage"] = round((covered_statements / total_statements) * 100, 2)
        
        # Use statement coverage as total coverage (Jest default)
        coverage_data["total_coverage"] = coverage_data["statement_coverage"]
    
    def _parse_lcov_coverage(self, coverage_file: Path, coverage_data: Dict):
        """Parse LCOV coverage format."""
        with open(coverage_file) as f:
            content = f.read()
        
        # Parse LCOV format
        records = content.split('end_of_record')
        
        for record in records:
            if not record.strip():
                continue
            
            lines = record.strip().split('\n')
            file_data = {}
            
            for line in lines:
                if line.startswith('SF:'):
                    file_data['path'] = line[3:]
                elif line.startswith('LH:'):
                    file_data['lines_hit'] = int(line[3:])
                elif line.startswith('LF:'):
                    file_data['lines_found'] = int(line[3:])
                elif line.startswith('BRH:'):
                    file_data['branches_hit'] = int(line[4:])
                elif line.startswith('BRF:'):
                    file_data['branches_found'] = int(line[4:])
                elif line.startswith('FNH:'):
                    file_data['functions_hit'] = int(line[4:])
                elif line.startswith('FNF:'):
                    file_data['functions_found'] = int(line[4:])
            
            if 'path' in file_data:
                file_coverage = {
                    "path": file_data['path'],
                    "line_coverage": (file_data.get('lines_hit', 0) / file_data.get('lines_found', 1)) * 100,
                    "branch_coverage": (file_data.get('branches_hit', 0) / file_data.get('branches_found', 1)) * 100,
                    "function_coverage": (file_data.get('functions_hit', 0) / file_data.get('functions_found', 1)) * 100,
                }
                coverage_data["files"].append(file_coverage)
    
    def _analyze_python_services(self, coverage_data: Dict):
        """Analyze Python coverage by service."""
        services = {}
        critical_modules = {}
        
        for file_data in coverage_data["files"]:
            path = file_data["path"]
            
            # Extract service name
            if "python-services/" in path:
                service_name = path.split("python-services/")[1].split("/")[0]
                if service_name not in services:
                    services[service_name] = {"files": [], "avg_coverage": 0}
                services[service_name]["files"].append(file_data)
            
            # Check critical modules
            for module in self.config["coverage"]["python"]["critical_modules"]:
                if module in path.lower():
                    if module not in critical_modules:
                        critical_modules[module] = {"files": [], "avg_coverage": 0}
                    critical_modules[module]["files"].append(file_data)
        
        # Calculate averages
        for service_name, service_data in services.items():
            if service_data["files"]:
                avg_coverage = sum(f["line_coverage"] for f in service_data["files"]) / len(service_data["files"])
                service_data["avg_coverage"] = round(avg_coverage, 2)
        
        for module_name, module_data in critical_modules.items():
            if module_data["files"]:
                avg_coverage = sum(f["line_coverage"] for f in module_data["files"]) / len(module_data["files"])
                module_data["avg_coverage"] = round(avg_coverage, 2)
        
        coverage_data["services"] = services
        coverage_data["critical_modules"] = critical_modules
    
    def _analyze_go_packages(self, coverage_data: Dict):
        """Analyze Go coverage by package."""
        packages = {}
        critical_packages = {}
        
        for file_data in coverage_data["files"]:
            path = file_data["path"]
            
            # Extract package name
            if "/" in path:
                package_name = "/".join(path.split("/")[:-1])
                if package_name not in packages:
                    packages[package_name] = {"files": [], "avg_coverage": 0}
                packages[package_name]["files"].append(file_data)
            
            # Check critical packages
            for package in self.config["coverage"]["go"]["critical_packages"]:
                if package in path.lower():
                    if package not in critical_packages:
                        critical_packages[package] = {"files": [], "avg_coverage": 0}
                    critical_packages[package]["files"].append(file_data)
        
        # Calculate averages
        for package_name, package_data in packages.items():
            if package_data["files"]:
                avg_coverage = sum(f["coverage"] for f in package_data["files"]) / len(package_data["files"])
                package_data["avg_coverage"] = round(avg_coverage, 2)
        
        for package_name, package_data in critical_packages.items():
            if package_data["files"]:
                avg_coverage = sum(f["coverage"] for f in package_data["files"]) / len(package_data["files"])
                package_data["avg_coverage"] = round(avg_coverage, 2)
        
        coverage_data["packages"] = packages
        coverage_data["critical_packages"] = critical_packages
    
    def _analyze_javascript_services(self, coverage_data: Dict):
        """Analyze JavaScript coverage by service."""
        services = {}
        
        for file_data in coverage_data["files"]:
            path = file_data["path"]
            
            # Extract service name
            if "frontend-services/" in path:
                service_name = path.split("frontend-services/")[1].split("/")[0]
                if service_name not in services:
                    services[service_name] = {"files": [], "avg_coverage": 0}
                services[service_name]["files"].append(file_data)
        
        # Calculate averages
        for service_name, service_data in services.items():
            if service_data["files"]:
                avg_coverage = sum(f.get("statement_coverage", 0) for f in service_data["files"]) / len(service_data["files"])
                service_data["avg_coverage"] = round(avg_coverage, 2)
        
        coverage_data["services"] = services
    
    def generate_unified_report(self) -> Dict[str, Any]:
        """Generate unified coverage report across all languages."""
        print("Generating unified coverage report...")
        
        # Collect coverage from all languages
        python_coverage = self.collect_python_coverage()
        go_coverage = self.collect_go_coverage()
        js_coverage = self.collect_javascript_coverage()
        
        # Create unified report
        unified_report = {
            "timestamp": datetime.now().isoformat(),
            "languages": {
                "python": python_coverage,
                "go": go_coverage,
                "javascript": js_coverage
            },
            "summary": {
                "overall_coverage": 0,
                "languages_count": 0,
                "services_count": 0,
                "files_count": 0,
                "threshold_breaches": []
            }
        }
        
        # Calculate overall metrics
        total_coverage = 0
        languages_with_data = 0
        total_files = 0
        total_services = 0
        
        for lang, data in unified_report["languages"].items():
            if data["total_coverage"] > 0:
                total_coverage += data["total_coverage"]
                languages_with_data += 1
            
            total_files += len(data.get("files", []))
            
            if "services" in data:
                total_services += len(data["services"])
            elif "packages" in data:
                total_services += len(data["packages"])
        
        if languages_with_data > 0:
            unified_report["summary"]["overall_coverage"] = round(total_coverage / languages_with_data, 2)
        
        unified_report["summary"]["languages_count"] = languages_with_data
        unified_report["summary"]["services_count"] = total_services
        unified_report["summary"]["files_count"] = total_files
        
        # Check threshold breaches
        self._check_threshold_breaches(unified_report)
        
        # Save unified report
        report_file = self.reports_dir / f"unified_coverage_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(unified_report, f, indent=2)
        
        print(f"Unified coverage report saved to {report_file}")
        
        return unified_report
    
    def _check_threshold_breaches(self, report: Dict[str, Any]):
        """Check for coverage threshold breaches."""
        breaches = []
        
        # Check Python thresholds
        python_data = report["languages"]["python"]
        python_config = self.config["coverage"]["python"]["thresholds"]
        
        if python_data["total_coverage"] < python_config["global"]:
            breaches.append({
                "language": "python",
                "type": "global",
                "actual": python_data["total_coverage"],
                "threshold": python_config["global"]
            })
        
        for service_name, service_data in python_data.get("services", {}).items():
            if service_data["avg_coverage"] < python_config["per_service"]:
                breaches.append({
                    "language": "python",
                    "type": "service",
                    "service": service_name,
                    "actual": service_data["avg_coverage"],
                    "threshold": python_config["per_service"]
                })
        
        # Check Go thresholds
        go_data = report["languages"]["go"]
        go_config = self.config["coverage"]["go"]["thresholds"]
        
        if go_data["total_coverage"] < go_config["global"]:
            breaches.append({
                "language": "go",
                "type": "global",
                "actual": go_data["total_coverage"],
                "threshold": go_config["global"]
            })
        
        # Check JavaScript thresholds
        js_data = report["languages"]["javascript"]
        js_config = self.config["coverage"]["javascript"]["coverageThreshold"]["global"]
        
        if js_data["total_coverage"] < js_config["statements"]:
            breaches.append({
                "language": "javascript",
                "type": "global",
                "metric": "statements",
                "actual": js_data["total_coverage"],
                "threshold": js_config["statements"]
            })
        
        report["summary"]["threshold_breaches"] = breaches
    
    def generate_html_report(self, unified_report: Dict[str, Any]):
        """Generate HTML coverage report."""
        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>PyAirtable Compose - Coverage Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ background: #f4f4f4; padding: 20px; border-radius: 5px; margin-bottom: 20px; }}
        .summary {{ display: flex; gap: 20px; margin-bottom: 30px; }}
        .metric {{ background: white; border: 1px solid #ddd; padding: 15px; border-radius: 5px; text-align: center; flex: 1; }}
        .metric h3 {{ margin: 0 0 10px 0; color: #333; }}
        .metric .value {{ font-size: 2em; font-weight: bold; }}
        .coverage-high {{ color: #28a745; }}
        .coverage-medium {{ color: #ffc107; }}
        .coverage-low {{ color: #dc3545; }}
        .language-section {{ margin: 20px 0; }}
        .services {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
        .service {{ border: 1px solid #ddd; padding: 15px; border-radius: 5px; }}
        .coverage-bar {{ background: #e9ecef; height: 20px; border-radius: 10px; overflow: hidden; margin: 10px 0; }}
        .coverage-fill {{ height: 100%; transition: width 0.3s ease; }}
        .breach {{ background: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; padding: 10px; border-radius: 5px; margin: 5px 0; }}
        table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>PyAirtable Compose - Coverage Report</h1>
        <p>Generated on: {unified_report['timestamp']}</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Overall Coverage</h3>
            <div class="value coverage-{self._get_coverage_class(unified_report['summary']['overall_coverage'])}">{unified_report['summary']['overall_coverage']:.1f}%</div>
        </div>
        <div class="metric">
            <h3>Languages</h3>
            <div class="value">{unified_report['summary']['languages_count']}</div>
        </div>
        <div class="metric">
            <h3>Services</h3>
            <div class="value">{unified_report['summary']['services_count']}</div>
        </div>
        <div class="metric">
            <h3>Files</h3>
            <div class="value">{unified_report['summary']['files_count']}</div>
        </div>
    </div>
    
    {self._generate_breach_section(unified_report['summary']['threshold_breaches'])}
    
    {self._generate_language_sections(unified_report['languages'])}
    
</body>
</html>
        """
        
        html_file = self.reports_dir / f"coverage_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
        with open(html_file, 'w') as f:
            f.write(html_content)
        
        print(f"HTML coverage report generated: {html_file}")
    
    def _get_coverage_class(self, coverage: float) -> str:
        """Get CSS class based on coverage percentage."""
        if coverage >= 80:
            return "high"
        elif coverage >= 60:
            return "medium"
        else:
            return "low"
    
    def _generate_breach_section(self, breaches: List[Dict]) -> str:
        """Generate HTML for threshold breaches."""
        if not breaches:
            return ""
        
        html = "<div class='language-section'><h2>Threshold Breaches</h2>"
        for breach in breaches:
            html += f"<div class='breach'>"
            html += f"<strong>{breach['language'].title()}</strong> - "
            html += f"{breach['type'].title()}: {breach['actual']:.1f}% "
            html += f"(threshold: {breach['threshold']}%)"
            if 'service' in breach:
                html += f" - Service: {breach['service']}"
            html += "</div>"
        html += "</div>"
        return html
    
    def _generate_language_sections(self, languages: Dict) -> str:
        """Generate HTML sections for each language."""
        html = ""
        
        for lang, data in languages.items():
            if data['total_coverage'] == 0:
                continue
            
            html += f"<div class='language-section'>"
            html += f"<h2>{lang.title()} Coverage: {data['total_coverage']:.1f}%</h2>"
            
            # Services/packages
            services = data.get('services', data.get('packages', {}))
            if services:
                html += "<div class='services'>"
                for service_name, service_data in services.items():
                    coverage = service_data['avg_coverage']
                    html += f"<div class='service'>"
                    html += f"<h4>{service_name}</h4>"
                    html += f"<div class='coverage-bar'>"
                    html += f"<div class='coverage-fill coverage-{self._get_coverage_class(coverage)}' style='width: {coverage}%'></div>"
                    html += f"</div>"
                    html += f"<p>{coverage:.1f}% ({len(service_data['files'])} files)</p>"
                    html += f"</div>"
                html += "</div>"
            
            html += "</div>"
        
        return html
    
    def save_coverage_history(self, unified_report: Dict[str, Any]):
        """Save coverage data to history for trend analysis."""
        history_file = self.history_dir / f"coverage_history_{datetime.now().strftime('%Y%m%d')}.json"
        
        # Load existing history or create new
        if history_file.exists():
            with open(history_file) as f:
                history_data = json.load(f)
        else:
            history_data = {"entries": []}
        
        # Add current entry
        history_entry = {
            "timestamp": unified_report["timestamp"],
            "overall_coverage": unified_report["summary"]["overall_coverage"],
            "languages": {
                lang: data["total_coverage"] 
                for lang, data in unified_report["languages"].items()
                if data["total_coverage"] > 0
            },
            "services_count": unified_report["summary"]["services_count"],
            "files_count": unified_report["summary"]["files_count"]
        }
        
        history_data["entries"].append(history_entry)
        
        # Keep only recent entries (90 days)
        cutoff_date = datetime.now() - timedelta(days=90)
        history_data["entries"] = [
            entry for entry in history_data["entries"]
            if datetime.fromisoformat(entry["timestamp"].replace('Z', '+00:00')) > cutoff_date
        ]
        
        # Save history
        with open(history_file, 'w') as f:
            json.dump(history_data, f, indent=2)
        
        print(f"Coverage history saved to {history_file}")
    
    def run_full_coverage_analysis(self):
        """Run complete coverage analysis and reporting."""
        print("Starting comprehensive coverage analysis...")
        
        # Generate unified report
        unified_report = self.generate_unified_report()
        
        # Generate HTML report
        self.generate_html_report(unified_report)
        
        # Save to history
        self.save_coverage_history(unified_report)
        
        # Print summary
        print("\n" + "="*50)
        print("COVERAGE ANALYSIS SUMMARY")
        print("="*50)
        print(f"Overall Coverage: {unified_report['summary']['overall_coverage']:.1f}%")
        print(f"Languages: {unified_report['summary']['languages_count']}")
        print(f"Services: {unified_report['summary']['services_count']}")
        print(f"Files: {unified_report['summary']['files_count']}")
        
        # Print breaches
        if unified_report['summary']['threshold_breaches']:
            print(f"\n⚠️  {len(unified_report['summary']['threshold_breaches'])} threshold breaches found:")
            for breach in unified_report['summary']['threshold_breaches']:
                print(f"   - {breach['language'].title()} {breach['type']}: {breach['actual']:.1f}% < {breach['threshold']}%")
        else:
            print("\n✅ All coverage thresholds met!")
        
        print("="*50)
        
        return unified_report


def main():
    """Main function to run coverage analysis."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Comprehensive coverage reporter")
    parser.add_argument("--project-root", help="Project root directory", default=".")
    parser.add_argument("--languages", help="Comma-separated list of languages", default="python,go,javascript")
    parser.add_argument("--output-format", choices=["json", "html", "both"], default="both")
    
    args = parser.parse_args()
    
    reporter = CoverageReporter(args.project_root)
    
    try:
        unified_report = reporter.run_full_coverage_analysis()
        
        # Return appropriate exit code based on coverage
        overall_coverage = unified_report['summary']['overall_coverage']
        threshold_breaches = len(unified_report['summary']['threshold_breaches'])
        
        if threshold_breaches > 0:
            print(f"Exiting with code 1 due to {threshold_breaches} threshold breaches")
            exit(1)
        elif overall_coverage < 70:  # Warning threshold
            print(f"Exiting with code 1 due to low overall coverage: {overall_coverage:.1f}%")
            exit(1)
        else:
            print("Coverage analysis completed successfully!")
            exit(0)
            
    except Exception as e:
        print(f"Coverage analysis failed: {e}")
        exit(1)


if __name__ == "__main__":
    main()