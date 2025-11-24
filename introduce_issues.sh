#!/bin/bash

# Elasticsearch Cluster Issues Simulator
# This script creates various problematic scenarios in your local Elasticsearch cluster
# All issues will successfully index data but cause cluster problems

# Colors for output (moved up before any validation)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate environment file exists before sourcing
ENV_FILE="elastic-start-local/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: ${ENV_FILE} file not found${NC}"
    echo "Ensure ES_LOCAL_URL and ES_LOCAL_PASSWORD are defined there."
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

# Set up authentication and validate required variables
ES_URL="${ES_LOCAL_URL:-}"
ES_USER="elastic"
ES_PASS="${ES_LOCAL_PASSWORD:-}"

if [ -z "$ES_URL" ] || [ -z "$ES_PASS" ]; then
    echo -e "${RED}Error: ES_LOCAL_URL or ES_LOCAL_PASSWORD is not set in .env${NC}"
    echo "Please set both in ${ENV_FILE}"
    exit 1
fi


# Helper function to make Elasticsearch requests
es_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    if [ -z "$data" ]; then
        curl -sS --fail-with-body -X "$method" \
            -u "${ES_USER}:${ES_PASS}" \
            -H "Content-Type: application/json" \
            "${ES_URL}${endpoint}"
    else
        curl -sS --fail-with-body -X "$method" \
            -u "${ES_USER}:${ES_PASS}" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${ES_URL}${endpoint}"
    fi
}

echo -e "${YELLOW}Elasticsearch Cluster Issues Simulator${NC}"
echo "======================================="
echo

# Additional connectivity validation
echo -e "${GREEN}Validating prerequisites...${NC}"

# Check if Elasticsearch is accessible with retry logic
echo "Testing Elasticsearch connectivity..."
attempts=0; max_attempts=3
until http_code=$(curl -sS -o /dev/null -w '%{http_code}' -u "${ES_USER}:${ES_PASS}" "${ES_URL}/_cluster/health") \
  && [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; do
  attempts=$((attempts+1))
  if [ $attempts -ge $max_attempts ]; then
    echo -e "${RED}Error: Cannot connect to Elasticsearch at ${ES_URL}${NC}"
    echo "HTTP status: ${http_code:-n/a}"
    echo "Please ensure:"
    echo "1. Elasticsearch cluster is running and reachable"
    echo "2. URL and credentials in .env file are correct (user: ${ES_USER})"
    echo "3. Network connectivity is available"
    echo "4. Manual test: curl -sS -u '${ES_USER}:********' '${ES_URL}/_cluster/health?pretty'"
    exit 1
  fi
  echo "Attempt $attempts/$max_attempts failed, retrying in 2 seconds..."
  sleep 2
done

echo -e "${GREEN}✓ Prerequisites validated successfully${NC}"
echo

# Check cluster health first
echo -e "${GREEN}Checking initial cluster health...${NC}"
es_request GET "/_cluster/health?pretty" | grep -E "status|number_of_nodes"
echo

# Issue 1: Create index with more replicas than nodes
echo -e "${RED}Issue 1: Creating index with too many replicas${NC}"
echo "Creating index 'problematic-replicas' with 2 replicas (but only 1 node available)..."

es_request PUT "/problematic-replicas" '{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2
  }
}' | jq '.' 2>/dev/null || echo "Index created"

# Index some documents - they will index successfully but cluster will be yellow
echo "Indexing documents (will succeed but cluster health will be YELLOW)..."
for i in {1..10}; do
    es_request POST "/problematic-replicas/_doc" "{
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
      \"message\": \"Document $i with unassigned replica shards\",
      \"value\": $i
    }" > /dev/null
done

echo "Documents indexed successfully!"
echo
echo "Checking index health (should show YELLOW status due to unassigned replicas):"
es_request GET "/_cluster/health/problematic-replicas?pretty" | grep -E "status|unassigned_shards"
echo

# Issue 2: Create a problematic template like in the screenshot
echo -e "${RED}Issue 2: Creating a problematic index template with multi fields${NC}"
echo "Creating template 'my-bad-template' with duplicate multi fields and ignore_above issues..."

es_request PUT "/_index_template/my-bad-template" '{
  "index_patterns": ["bad-template*"],
  "template": {
    "aliases": {},
    "mappings": {
      "properties": {
        "message": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword"
            },
            "raw": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "text": {
          "type": "text",
          "fields": {
            "text": {
              "type": "text"
            }
          }
        }
      }
    },
    "settings": {}
  },
  "priority": 0
}' | jq '.' 2>/dev/null || echo "Template created"

echo
echo "Creating index matching the template pattern..."
es_request PUT "/bad-template-test"

echo
#echo "Indexing documents that will succeed but cause field confusion..."
#for i in {1..5}; do
#    es_request POST "/bad-template-test/_doc" "{
#      \"message\": \"This is a test message number $i that will be indexed with duplicate multi-field definitions\",
#      \"text\": \"Some text content that has a self-referencing multi-field\"
#    }" > /dev/null
#done
#echo "Documents indexed successfully despite template issues!"

# Issue 3: Create bad legacy template
echo -e "${RED}Issue 3: Creating bad legacy template${NC}"
echo "Creating legacy template 'bad-legacy-template' with problematic keyword multi-fields..."

es_request PUT "/_template/bad-legacy-template" '{
  "index_patterns": [
    "bad-legacy-index-*"
  ],
  "mappings": {
    "properties": {
      "message": {
        "type": "keyword",
        "fields": {
          "text": {
            "type": "keyword"
          },
          "raw": {
            "type": "keyword"
          }
        }
      }
    }
  }
}' | jq '.' 2>/dev/null || echo "Legacy template created"

echo

# Issue 4: Create bad component template
echo -e "${RED}Issue 4: Creating bad component template${NC}"
echo "Creating component template 'bad-component-template' with redundant keyword fields..."

es_request PUT "/_component_template/bad-component-template" '{
  "template": {
    "mappings": {
      "properties": {
        "message": {
          "type": "keyword",
          "fields": {
            "text": {
              "type": "keyword"
            },
            "raw": {
              "type": "keyword"
            }
          }
        }
      }
    }
  }
}' | jq '.' 2>/dev/null || echo "Component template created"

echo

# Issue 5: Create bad index template with keyword redundancy
echo -e "${RED}Issue 5: Creating bad index template with keyword redundancy${NC}"
echo "Creating index template 'bad-index-template' with wasteful keyword multi-fields..."

es_request PUT "/_index_template/bad-index-template" '{
  "index_patterns": [
    "bad-index-*"
  ],
  "template": {
    "mappings": {
      "properties": {
        "message": {
          "type": "keyword",
          "fields": {
            "text": {
              "type": "keyword"
            },
            "raw": {
              "type": "keyword"
            }
          }
        }
      }
    }
  }
}' | jq '.' 2>/dev/null || echo "Index template created"

echo

# Issue 6: Create index with impossible allocation requirements (RED status)
echo -e "${RED}Issue 6: Creating index with impossible allocation requirements${NC}"
echo "Creating index 'red-index' with allocation requirements that cannot be satisfied..."

es_request PUT "/red-index" '{
  "settings": {
    "index.routing.allocation.require.does_not_exist": "or_this",
    "number_of_replicas": 0
  }
}' | jq '.' 2>/dev/null || echo "Red index created"

echo "Index 'red-index' created with impossible allocation constraint (RED health expected)"

echo
echo -e "${YELLOW}Current cluster issues summary:${NC}"
echo "1. Index 'problematic-replicas' has unassigned shards (YELLOW health)"
echo "2. Index 'red-index' has impossible allocation requirements (RED health)"
echo "3. Template 'my-bad-template' has suboptimal mappings with duplicate multi-fields"
echo "4. Legacy template 'bad-legacy-template' has wasteful keyword multi-fields"
echo "5. Component template 'bad-component-template' has redundant keyword fields"
echo "6. Index template 'bad-index-template' has inefficient keyword field structure"
echo

echo
echo -e "${GREEN}To clean up these issues, run:${NC}"
echo "# Delete problematic indices"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/problematic-replicas"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/red-index"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/bad-template-test"
echo "# Delete faulty templates"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/_index_template/my-bad-template"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/_template/bad-legacy-template"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/_component_template/bad-component-template"
echo "curl -X DELETE -u elastic:${ES_LOCAL_PASSWORD} ${ES_URL}/_index_template/bad-index-template"