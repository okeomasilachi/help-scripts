#!/bin/bash

# Enhanced Database Management Wrapper Script

# Colors for output
GREEN='\e[32m'
RED='\e[31m'
BLUE='\e[34m'
YELLOW='\e[33m'
NC='\e[0m' # No Color

usage() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${GREEN}             DATABASE MANAGEMENT TOOL (db)                      ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${YELLOW}Usage:${NC}"
    echo "  db status                        - Check if services are running"
    echo "  db <target> start|stop|restart   - Manage service status"
    echo ""
    echo -e "${YELLOW}Database Management:${NC}"
    echo "  db <target> list                 - List all databases"
    echo "  db <target> list <db>            - List tables/collections in a database"
    echo "  db <target> create <db>          - Create a new database"
    echo "  db <target> delete <db>          - Delete a database (with confirmation)"
    echo "  db <target> clear <db>           - Empty all data in a database (preserves schema)"
    echo ""
    echo -e "${YELLOW}Data & Interaction:${NC}"
    echo "  db <target> show <db> <obj>      - Show first 10 rows from a table/collection"
    echo "  db <target> shell <db>           - Enter interactive shell (psql/mongosh)"
    echo ""
    echo -e "${BLUE}Targets:${NC} postgres, mongo, all"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ${GREEN}db postgres list${NC}             - See all Postgres databases"
    echo -e "  ${GREEN}db mongo list ekaulo${NC}        - See all collections in 'ekaulo'"
    echo -e "  ${GREEN}db postgres show ekaulo users${NC} - View data in the 'users' table"
    echo -e "  ${GREEN}db all stop${NC}                  - Stop both database services"
    echo -e "${BLUE}================================================================${NC}"
    exit 1
}

if [ $# -eq 0 ] || [ "$1" = "help" ]; then
    usage
fi

# Helper to identify service name
get_service() {
    case "$1" in
        postgres|postgresql|postgress) echo "postgresql" ;;
        mongo|mongodb) echo "mongod" ;;
        mysql|mariadb) echo "mariadb" ;;
        *) echo "unknown" ;;
    esac
}

# 1. Global Status
if [ "$1" = "status" ] && [ $# -eq 1 ]; then
    echo -e "${BLUE}--- Database Service Status ---${NC}"
    for svc in postgresql mongod; do
        printf "%-12s: " "$svc"
        if systemctl is-active --quiet "$svc"; then
            echo -e "${GREEN}Running${NC}"
        else
            echo -e "${RED}Stopped${NC}"
        fi
    done
    exit 0
fi

target="$1"
action="$2"
service=$(get_service "$target")

if [ "$service" = "unknown" ] && [ "$target" != "all" ]; then
    echo -e "${RED}Error: Unknown target '$target'${NC}"
    usage
fi

# 2. Service Management (Start/Stop/Restart)
if [[ "$action" =~ ^(start|stop|restart)$ ]]; then
    if [ "$target" = "all" ]; then
        echo -e "${YELLOW}Executing: sudo systemctl $action postgresql mongod${NC}"
        sudo systemctl "$action" postgresql mongod
    else
        echo -e "${YELLOW}Executing: sudo systemctl $action $service${NC}"
        sudo systemctl "$action" "$service"
    fi
    exit 0
fi

# 3. Database Operations
db_name="$3"
object_name="$4"

case "$action" in
    list)
        if [ -z "$db_name" ]; then
            echo -e "${BLUE}Listing all databases in $target:${NC}"
            if [ "$service" = "postgresql" ]; then
                sudo -u postgres psql -l
            elif [ "$service" = "mongod" ]; then
                mongosh --eval "db.getMongo().getDBNames().forEach(print)" --quiet
            fi
        else
            echo -e "${BLUE}Listing objects in $target database '$db_name':${NC}"
            if [ "$service" = "postgresql" ]; then
                sudo -u postgres psql -d "$db_name" -c "\dt"
            elif [ "$service" = "mongod" ]; then
                mongosh "$db_name" --eval "db.getCollectionNames().forEach(print)" --quiet
            fi
        fi
        ;;

    create)
        if [ -z "$db_name" ]; then echo -e "${RED}Error: Database name required${NC}"; exit 1; fi
        echo -e "${YELLOW}Creating database '$db_name' in $target...${NC}"
        if [ "$service" = "postgresql" ]; then
            sudo -u postgres createdb "$db_name"
        elif [ "$service" = "mongod" ]; then
            mongosh "$db_name" --eval "db.createCollection('init')" --quiet
        fi
        echo -e "${GREEN}Done.${NC}"
        ;;

    delete)
        if [ -z "$db_name" ]; then echo -e "${RED}Error: Database name required${NC}"; exit 1; fi
        echo -e "${RED}WARNING: This will permanently delete database '$db_name' in $target.${NC}"
        read -p "Are you sure? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "Cancelled."; exit 0; fi
        
        if [ "$service" = "postgresql" ]; then
            sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name' AND pid <> pg_backend_pid();" >/dev/null 2>&1
            sudo -u postgres dropdb "$db_name"
        elif [ "$service" = "mongod" ]; then
            mongosh "$db_name" --eval "db.dropDatabase()" --quiet
        fi
        echo -e "${GREEN}Database deleted.${NC}"
        ;;

    clear)
        if [ -z "$db_name" ]; then echo -e "${RED}Error: Database name required${NC}"; exit 1; fi
        echo -e "${RED}WARNING: This will empty ALL tables/collections in database '$db_name'.${NC}"
        read -p "Are you sure? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "Cancelled."; exit 0; fi
        
        if [ "$service" = "postgresql" ]; then
            sudo -u postgres psql -d "$db_name" -c "DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP EXECUTE 'TRUNCATE TABLE public.' || quote_ident(r.tablename) || ' CASCADE'; END LOOP; END \$\$;"
        elif [ "$service" = "mongod" ]; then
            mongosh "$db_name" --eval "db.getCollectionNames().forEach(c => { if (c !== 'system.profile') db.getCollection(c).deleteMany({}) })" --quiet
        fi
        echo -e "${GREEN}All data cleared in '$db_name'.${NC}"
        ;;

    show)
        if [ -z "$db_name" ] || [ -z "$object_name" ]; then
            echo -e "${RED}Usage: db $target show <db> <table/collection>${NC}"
            exit 1
        fi
        if [ "$service" = "postgresql" ]; then
            sudo -u postgres psql -d "$db_name" -c "SELECT * FROM \"$object_name\" LIMIT 10;"
        elif [ "$service" = "mongod" ]; then
            mongosh "$db_name" --eval "db.getCollection(\"$object_name\").find().limit(10)" --quiet
        fi
        ;;

    shell)
        if [ -z "$db_name" ]; then db_name="postgres"; [ "$service" = "mongod" ] && db_name="test"; fi
        if [ "$service" = "postgresql" ]; then
            sudo -u postgres psql -d "$db_name"
        elif [ "$service" = "mongod" ]; then
            mongosh "$db_name"
        fi
        ;;

    *)
        echo -e "${RED}Error: Unknown action '$action'${NC}"
        usage
        ;;
esac
