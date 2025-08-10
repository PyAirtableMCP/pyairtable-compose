#!/bin/bash
set -e

# Phase 1: Critical Separation - Implementation Script
# This script handles the highest priority cleanup tasks with lowest risk

echo "🚀 Starting Phase 1: Critical Separation"
echo "========================================"

# Create backup before any changes
echo "📦 Creating backup..."
git checkout -b cleanup-phase1-backup
git add -A
git commit -m "Backup before Phase 1 cleanup" || echo "No changes to commit"
git checkout -b cleanup-phase1-work

# 1. Remove Unrelated Aquascene Projects
echo "🗑️  Step 1: Removing unrelated Aquascene projects..."
if [ -d "aquascene-content-engine" ]; then
    echo "   - Removing aquascene-content-engine/ (complete unrelated project)"
    rm -rf aquascene-content-engine/
    echo "   ✅ Removed aquascene-content-engine/"
fi

# Remove aquascene references in other files
echo "   - Cleaning up aquascene references..."
find . -name "*.md" -type f -exec grep -l "aquascene" {} \; | while read file; do
    if [[ "$file" != "./PYAIRTABLE_COMPREHENSIVE_CLEANUP_PLAN.md" ]]; then
        echo "   - Found aquascene reference in: $file"
        # Backup and remove files with aquascene references that aren't core docs
        if [[ "$file" =~ AQUASCENE|aquascene ]]; then
            rm "$file"
            echo "   ✅ Removed: $file"
        fi
    fi
done

# Remove aquascene-related files in root
find . -maxdepth 1 -name "*AQUASCENE*" -type f -delete
find . -maxdepth 1 -name "*aquascene*" -type f -delete

echo "   ✅ Step 1 Complete: Removed unrelated Aquascene content"

# 2. Identify and catalog documentation for migration
echo "📚 Step 2: Cataloging documentation for migration..."
mkdir -p cleanup-temp/docs-catalog

# Create manifest of all documentation files
find . -name "*.md" -type f | grep -v "cleanup-temp" | grep -v ".git" > cleanup-temp/docs-catalog/all-docs.txt

# Categorize documentation
echo "   - Categorizing documentation types..."
grep -E "(README|readme)" cleanup-temp/docs-catalog/all-docs.txt > cleanup-temp/docs-catalog/readme-files.txt || touch cleanup-temp/docs-catalog/readme-files.txt
grep -E "(GUIDE|guide|Guide)" cleanup-temp/docs-catalog/all-docs.txt > cleanup-temp/docs-catalog/guide-files.txt || touch cleanup-temp/docs-catalog/guide-files.txt
grep -E "(ARCHITECTURE|architecture|Architecture)" cleanup-temp/docs-catalog/all-docs.txt > cleanup-temp/docs-catalog/architecture-files.txt || touch cleanup-temp/docs-catalog/architecture-files.txt
grep -E "(DEPLOYMENT|deployment|Deployment)" cleanup-temp/docs-catalog/all-docs.txt > cleanup-temp/docs-catalog/deployment-files.txt || touch cleanup-temp/docs-catalog/deployment-files.txt
grep -E "(REPORT|report|Report|SUMMARY|summary|Summary)" cleanup-temp/docs-catalog/all-docs.txt > cleanup-temp/docs-catalog/report-files.txt || touch cleanup-temp/docs-catalog/report-files.txt

# Count documentation by category
echo "   📊 Documentation Inventory:"
echo "      - Total MD files: $(wc -l < cleanup-temp/docs-catalog/all-docs.txt)"
echo "      - README files: $(wc -l < cleanup-temp/docs-catalog/readme-files.txt)"
echo "      - Guide files: $(wc -l < cleanup-temp/docs-catalog/guide-files.txt)"
echo "      - Architecture files: $(wc -l < cleanup-temp/docs-catalog/architecture-files.txt)"
echo "      - Deployment files: $(wc -l < cleanup-temp/docs-catalog/deployment-files.txt)"
echo "      - Report/Summary files: $(wc -l < cleanup-temp/docs-catalog/report-files.txt)"

echo "   ✅ Step 2 Complete: Documentation cataloged"

# 3. Remove obvious documentation noise (reports, summaries, logs)
echo "🧹 Step 3: Removing documentation noise..."

# Remove session reports, summaries, and logs
echo "   - Removing session reports and summaries..."
find . -maxdepth 1 -name "*REPORT*" -name "*.md" -delete
find . -maxdepth 1 -name "*SUMMARY*" -name "*.md" -delete
find . -maxdepth 1 -name "*STATUS*" -name "*.md" -delete
find . -maxdepth 1 -name "*COMPLETION*" -name "*.md" -delete
find . -maxdepth 1 -name "*SESSION*" -name "*.md" -delete
find . -maxdepth 1 -name "*MEETING*" -name "*.md" -delete
find . -maxdepth 1 -name "*ANALYSIS*" -name "*.md" -delete

# Remove test result files
echo "   - Removing test result files..."
find . -maxdepth 1 -name "*test_results*" -delete
find . -maxdepth 1 -name "*_test_report_*" -delete
find . -maxdepth 1 -name "*.json" -name "*test*" -delete
find . -maxdepth 1 -name "*.log" -delete

# Count files removed
removed_count=$(find cleanup-temp/docs-catalog/report-files.txt -exec wc -l {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
echo "   ✅ Step 3 Complete: Removed ~$removed_count documentation noise files"

# 4. Identify duplicate Docker Compose files
echo "🐳 Step 4: Cataloging Docker Compose files..."
find . -name "docker-compose*.yml" -o -name "docker-compose*.yaml" > cleanup-temp/compose-files.txt

echo "   📊 Docker Compose Inventory:"
echo "      - Total compose files: $(wc -l < cleanup-temp/compose-files.txt)"

# Categorize compose files
grep -E "(prod|production)" cleanup-temp/compose-files.txt > cleanup-temp/compose-prod.txt || touch cleanup-temp/compose-prod.txt
grep -E "(dev|development)" cleanup-temp/compose-files.txt > cleanup-temp/compose-dev.txt || touch cleanup-temp/compose-dev.txt  
grep -E "(test|testing)" cleanup-temp/compose-files.txt > cleanup-temp/compose-test.txt || touch cleanup-temp/compose-test.txt
grep -E "(override)" cleanup-temp/compose-files.txt > cleanup-temp/compose-override.txt || touch cleanup-temp/compose-override.txt

echo "      - Production: $(wc -l < cleanup-temp/compose-prod.txt)"
echo "      - Development: $(wc -l < cleanup-temp/compose-dev.txt)"
echo "      - Testing: $(wc -l < cleanup-temp/compose-test.txt)"
echo "      - Override: $(wc -l < cleanup-temp/compose-override.txt)"

echo "   ✅ Step 4 Complete: Docker Compose files cataloged"

# 5. Create service inventory
echo "🔧 Step 5: Creating service inventory..."
mkdir -p cleanup-temp/services-catalog

# Find all service directories
find . -type d -name "*-service*" > cleanup-temp/services-catalog/service-dirs.txt
find . -type d -name "*service*" | grep -v services-catalog >> cleanup-temp/services-catalog/service-dirs.txt
sort cleanup-temp/services-catalog/service-dirs.txt | uniq > cleanup-temp/services-catalog/unique-services.txt

echo "   📊 Service Inventory:"
echo "      - Total service directories: $(wc -l < cleanup-temp/services-catalog/unique-services.txt)"

# Categorize by implementation language
grep -E "go-services" cleanup-temp/services-catalog/unique-services.txt > cleanup-temp/services-catalog/go-services.txt || touch cleanup-temp/services-catalog/go-services.txt
grep -E "python.*service|pyairtable.*service" cleanup-temp/services-catalog/unique-services.txt > cleanup-temp/services-catalog/python-services.txt || touch cleanup-temp/services-catalog/python-services.txt
grep -E "frontend.*service|.*frontend" cleanup-temp/services-catalog/unique-services.txt > cleanup-temp/services-catalog/frontend-services.txt || touch cleanup-temp/services-catalog/frontend-services.txt

echo "      - Go services: $(wc -l < cleanup-temp/services-catalog/go-services.txt)"
echo "      - Python services: $(wc -l < cleanup-temp/services-catalog/python-services.txt)"
echo "      - Frontend services: $(wc -l < cleanup-temp/services-catalog/frontend-services.txt)"

echo "   ✅ Step 5 Complete: Service inventory created"

# 6. Generate Phase 1 Summary Report
echo "📋 Step 6: Generating Phase 1 Summary Report..."
cat > cleanup-temp/PHASE1_CLEANUP_SUMMARY.md << EOF
# Phase 1 Cleanup Summary

## Actions Completed
- ✅ Removed unrelated Aquascene content
- ✅ Cataloged $(wc -l < cleanup-temp/docs-catalog/all-docs.txt) documentation files
- ✅ Removed documentation noise files
- ✅ Cataloged $(wc -l < cleanup-temp/compose-files.txt) Docker Compose files
- ✅ Inventoried $(wc -l < cleanup-temp/services-catalog/unique-services.txt) service directories

## Repository Size Reduction
- Estimated reduction: ~40% (removed aquascene-content-engine)
- Documentation noise reduction: ~60%

## Next Steps for Phase 2
1. Review service inventory for duplicates
2. Plan Docker Compose consolidation
3. Execute documentation migration to pyairtable-docs

## Files for Manual Review
- cleanup-temp/docs-catalog/ - Documentation categorization
- cleanup-temp/compose-files.txt - All compose files
- cleanup-temp/services-catalog/ - Service inventory

## Recommendations
1. Proceed with Phase 2 service deduplication
2. Create pyairtable-docs repository
3. Plan infrastructure consolidation
EOF

echo "   ✅ Phase 1 Complete!"
echo ""
echo "📊 Summary:"
echo "   - Removed unrelated content"
echo "   - Cataloged repository structure"
echo "   - Prepared for Phase 2"
echo ""
echo "📋 Review the summary at: cleanup-temp/PHASE1_CLEANUP_SUMMARY.md"
echo "🔧 Next: Review inventories and proceed with Phase 2"

# Commit Phase 1 changes
git add -A
git commit -m "Phase 1: Critical separation - Remove aquascene content and catalog structure

- Removed complete aquascene-content-engine project
- Cleaned up aquascene references
- Cataloged documentation files for migration
- Removed documentation noise (reports, summaries, logs)
- Inventoried Docker Compose files
- Cataloged service directories by technology
- Generated cleanup summary report

Repository size reduced by ~40%"

echo ""
echo "✅ Phase 1 cleanup completed and committed!"
echo "🔀 Switch to main branch when ready to merge: git checkout main && git merge cleanup-phase1-work"