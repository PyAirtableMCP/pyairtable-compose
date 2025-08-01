#!/usr/bin/env python3
"""
Airtable Schema Analyzer
Analyzes the complete schema of an Airtable base to understand its structure,
field types, relationships, and potential multi-tenant support challenges.
"""

import json
import requests
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
from collections import defaultdict

class AirtableSchemaAnalyzer:
    def __init__(self, personal_access_token: str, base_id: str):
        self.token = personal_access_token
        self.base_id = base_id
        self.base_url = "https://api.airtable.com/v0"
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
        self.schema_data = {}
        self.tables_metadata = {}
        
    def get_base_metadata(self) -> Dict[str, Any]:
        """Retrieve base metadata including all tables and their schemas."""
        url = f"{self.base_url}/meta/bases/{self.base_id}/tables"
        
        try:
            response = requests.get(url, headers=self.headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"Error retrieving base metadata: {e}")
            return {}
    
    def analyze_field_types(self, fields: List[Dict]) -> Dict[str, Any]:
        """Analyze field types and their configurations."""
        field_analysis = {
            'field_types': defaultdict(int),
            'complex_fields': [],
            'relationships': [],
            'formulas': [],
            'lookups': [],
            'rollups': []
        }
        
        for field in fields:
            field_type = field.get('type', 'unknown')
            field_analysis['field_types'][field_type] += 1
            
            # Analyze complex field types
            if field_type in ['multipleRecordLinks', 'linkedRecord']:
                field_analysis['relationships'].append({
                    'field_name': field.get('name'),
                    'type': field_type,
                    'options': field.get('options', {})
                })
                field_analysis['complex_fields'].append(field)
                
            elif field_type == 'formula':
                field_analysis['formulas'].append({
                    'field_name': field.get('name'),
                    'formula': field.get('options', {}).get('formula', '')
                })
                field_analysis['complex_fields'].append(field)
                
            elif field_type == 'lookup':
                field_analysis['lookups'].append({
                    'field_name': field.get('name'),
                    'options': field.get('options', {})
                })
                field_analysis['complex_fields'].append(field)
                
            elif field_type == 'rollup':
                field_analysis['rollups'].append({
                    'field_name': field.get('name'),
                    'options': field.get('options', {})
                })
                field_analysis['complex_fields'].append(field)
        
        return field_analysis
    
    def identify_relationship_patterns(self, tables_data: Dict) -> Dict[str, Any]:
        """Identify relationship patterns across tables."""
        relationships = []
        table_names = {table['id']: table['name'] for table in tables_data.get('tables', [])}
        
        for table in tables_data.get('tables', []):
            table_name = table['name']
            
            for field in table.get('fields', []):
                if field.get('type') in ['multipleRecordLinks', 'linkedRecord']:
                    options = field.get('options', {})
                    linked_table_id = options.get('linkedTableId')
                    linked_table_name = table_names.get(linked_table_id, 'Unknown')
                    
                    relationships.append({
                        'source_table': table_name,
                        'source_field': field.get('name'),
                        'target_table': linked_table_name,
                        'target_table_id': linked_table_id,
                        'relationship_type': field.get('type'),
                        'is_symmetric': options.get('isReversed', False),
                        'inverse_field_id': options.get('inverseLinkFieldId')
                    })
        
        return {
            'relationships': relationships,
            'relationship_count': len(relationships),
            'tables_with_relationships': len(set(r['source_table'] for r in relationships))
        }
    
    def analyze_complexity_indicators(self, tables_data: Dict) -> Dict[str, Any]:
        """Identify complexity indicators that may affect multi-tenant support."""
        complexity_analysis = {
            'total_tables': len(tables_data.get('tables', [])),
            'total_fields': 0,
            'complex_field_count': 0,
            'formula_dependencies': [],
            'lookup_dependencies': [],
            'cross_table_dependencies': 0,
            'potential_challenges': []
        }
        
        for table in tables_data.get('tables', []):
            table_field_count = len(table.get('fields', []))
            complexity_analysis['total_fields'] += table_field_count
            
            field_analysis = self.analyze_field_types(table.get('fields', []))
            complexity_analysis['complex_field_count'] += len(field_analysis['complex_fields'])
            
            # Check for cross-table dependencies
            if field_analysis['relationships'] or field_analysis['lookups'] or field_analysis['rollups']:
                complexity_analysis['cross_table_dependencies'] += 1
        
        # Identify potential multi-tenant challenges
        if complexity_analysis['cross_table_dependencies'] > 0:
            complexity_analysis['potential_challenges'].append(
                "Cross-table relationships may complicate tenant isolation"
            )
        
        if complexity_analysis['complex_field_count'] > complexity_analysis['total_fields'] * 0.3:
            complexity_analysis['potential_challenges'].append(
                "High proportion of complex fields may impact performance"
            )
        
        return complexity_analysis
    
    def generate_schema_report(self) -> str:
        """Generate a comprehensive schema analysis report."""
        metadata = self.get_base_metadata()
        
        if not metadata:
            return "Failed to retrieve base metadata"
        
        report_lines = []
        report_lines.append("=" * 80)
        report_lines.append("AIRTABLE SCHEMA ANALYSIS REPORT")
        report_lines.append("=" * 80)
        report_lines.append(f"Base ID: {self.base_id}")
        report_lines.append(f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report_lines.append("")
        
        # Overview
        tables = metadata.get('tables', [])
        report_lines.append("SCHEMA OVERVIEW")
        report_lines.append("-" * 40)
        report_lines.append(f"Total Tables: {len(tables)}")
        
        total_fields = sum(len(table.get('fields', [])) for table in tables)
        report_lines.append(f"Total Fields: {total_fields}")
        report_lines.append("")
        
        # Table Details
        report_lines.append("TABLE DETAILS")
        report_lines.append("-" * 40)
        
        for table in tables:
            table_name = table.get('name', 'Unknown')
            table_id = table.get('id', 'Unknown')
            fields = table.get('fields', [])
            
            report_lines.append(f"\nTable: {table_name} (ID: {table_id})")
            report_lines.append(f"  Field Count: {len(fields)}")
            
            # Analyze field types for this table
            field_analysis = self.analyze_field_types(fields)
            
            report_lines.append("  Field Types:")
            for field_type, count in field_analysis['field_types'].items():
                report_lines.append(f"    - {field_type}: {count}")
            
            # Show complex fields
            if field_analysis['complex_fields']:
                report_lines.append("  Complex Fields:")
                for field in field_analysis['complex_fields']:
                    field_name = field.get('name', 'Unknown')
                    field_type = field.get('type', 'Unknown')
                    report_lines.append(f"    - {field_name} ({field_type})")
        
        # Relationship Analysis
        relationship_analysis = self.identify_relationship_patterns(metadata)
        report_lines.append("\nRELATIONSHIP ANALYSIS")
        report_lines.append("-" * 40)
        report_lines.append(f"Total Relationships: {relationship_analysis['relationship_count']}")
        report_lines.append(f"Tables with Relationships: {relationship_analysis['tables_with_relationships']}")
        
        if relationship_analysis['relationships']:
            report_lines.append("\nRelationship Details:")
            for rel in relationship_analysis['relationships']:
                report_lines.append(
                    f"  {rel['source_table']}.{rel['source_field']} -> {rel['target_table']}"
                )
        
        # Complexity Analysis
        complexity = self.analyze_complexity_indicators(metadata)
        report_lines.append("\nCOMPLEXITY ANALYSIS")
        report_lines.append("-" * 40)
        report_lines.append(f"Complex Field Ratio: {complexity['complex_field_count']}/{complexity['total_fields']} ({complexity['complex_field_count']/complexity['total_fields']*100:.1f}%)")
        report_lines.append(f"Cross-table Dependencies: {complexity['cross_table_dependencies']}")
        
        # Multi-tenant Challenges
        report_lines.append("\nMULTI-TENANT SUPPORT CONSIDERATIONS")
        report_lines.append("-" * 40)
        
        if complexity['potential_challenges']:
            for challenge in complexity['potential_challenges']:
                report_lines.append(f"- {challenge}")
        else:
            report_lines.append("- No major multi-tenant challenges identified")
        
        # Additional recommendations
        report_lines.append("\nRECOMMENDations FOR MULTI-TENANT SUPPORT")
        report_lines.append("-" * 40)
        report_lines.append("- Implement tenant-scoped API access to prevent cross-tenant data access")
        report_lines.append("- Consider caching strategies for complex field calculations")
        report_lines.append("- Monitor performance impact of lookup and rollup fields")
        report_lines.append("- Ensure relationship integrity across tenant boundaries")
        
        if relationship_analysis['relationship_count'] > 0:
            report_lines.append("- Pay special attention to linked record fields in multi-tenant scenarios")
        
        # Raw Schema Data
        report_lines.append("\nRAW SCHEMA DATA")
        report_lines.append("-" * 40)
        report_lines.append(json.dumps(metadata, indent=2))
        
        return "\n".join(report_lines)
    
    def save_report(self, filename: str = None) -> str:
        """Save the schema analysis report to a file."""
        if filename is None:
            filename = f"airtable_schema_analysis_{self.base_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        
        report = self.generate_schema_report()
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(report)
        
        return filename

def main():
    # Airtable credentials
    PERSONAL_ACCESS_TOKEN = os.getenv("AIRTABLE_PAT", "your_personal_access_token_here")
    BASE_ID = os.getenv("AIRTABLE_BASE_ID", "your_base_id_here")
    
    print("Starting Airtable Schema Analysis...")
    print(f"Base ID: {BASE_ID}")
    print("-" * 50)
    
    analyzer = AirtableSchemaAnalyzer(PERSONAL_ACCESS_TOKEN, BASE_ID)
    
    try:
        # Generate and display the report
        report = analyzer.generate_schema_report()
        print(report)
        
        # Save the report to a file
        filename = analyzer.save_report()
        print(f"\nReport saved to: {filename}")
        
    except Exception as e:
        print(f"Error during analysis: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()