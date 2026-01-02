#!/bin/bash
# analyze_topic_suggestions.sh
# Diagnostic script to analyze topic suggestion failures
# This script adds debug logging to the app and analyzes output

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}📊 TOPIC SUGGESTION FAILURE ANALYSIS${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Check for database
DB_PATH="$HOME/Library/Containers/com.example.localGemmaMacos/Data/Documents/local_gemma_rag.db"

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}❌ Database not found at: $DB_PATH${NC}"
    echo "   Please run the app first to create the database."
    exit 1
fi

echo -e "${GREEN}✅ Database found at: $DB_PATH${NC}"
echo ""

# Get chunk count using sqlite3
echo -e "${YELLOW}📚 Analyzing database contents...${NC}"
echo "---------------------------------------------------------"

# Count chunks
CHUNK_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM chunks;")
echo "   Total chunks: $CHUNK_COUNT"

# Get sample chunk contents
echo ""
echo -e "${YELLOW}📜 Sample chunk contents (first 5):${NC}"
echo "---------------------------------------------------------"

sqlite3 "$DB_PATH" "SELECT id, substr(content, 1, 100) || '...' as preview FROM chunks LIMIT 5;" | while read line; do
    echo "   $line"
done

# Extract unique words to analyze topics
echo ""
echo -e "${YELLOW}🔍 Extracting key topics from chunks...${NC}"
echo "---------------------------------------------------------"

# Get all chunk content and extract unique words
sqlite3 "$DB_PATH" "SELECT content FROM chunks;" | tr ' ' '\n' | sort | uniq -c | sort -rn | head -30 | while read line; do
    echo "   $line"
done

echo ""
echo -e "${YELLOW}📝 Full chunk contents for manual analysis:${NC}"
echo "---------------------------------------------------------"
echo "   (Viewing first 3 full chunks)"
echo ""

sqlite3 "$DB_PATH" "SELECT '--- Chunk ' || id || ' ---' || char(10) || content FROM chunks LIMIT 3;"

echo ""
echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}📊 ANALYSIS COMPLETE${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Review the chunk contents above"
echo -e "  2. Compare with the failed questions from the app logs"
echo -e "  3. Check if the question topics actually exist in the chunks"
echo -e "${BLUE}======================================================================${NC}"
