#!/usr/bin/env bash
# =============================================================================
#  db — Enhanced Database Management CLI
#  Supports: PostgreSQL & MongoDB
#  Author:   okeomasilachi
# =============================================================================

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
BOLD='\e[1m'
GREEN='\e[32m'
RED='\e[31m'
BLUE='\e[34m'
YELLOW='\e[33m'
CYAN='\e[36m'
DIM='\e[2m'
NC='\e[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}${BOLD}ℹ  ${NC}${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}${BOLD}✓  ${NC}${GREEN}$*${NC}"; }
warn()    { echo -e "${YELLOW}${BOLD}⚠  ${NC}${YELLOW}$*${NC}"; }
error()   { echo -e "${RED}${BOLD}✗  ${NC}${RED}$*${NC}" >&2; }
section() { echo -e "\n${CYAN}${BOLD}── $* ─────────────────────────────────────${NC}"; }
divider() { echo -e "${DIM}─────────────────────────────────────────────────────${NC}"; }

confirm() {
    local msg="${1:-Are you sure?}"
    echo -e "${RED}${BOLD}⚠  WARNING:${NC} ${RED}$msg${NC}"
    read -rp "$(echo -e "${YELLOW}Type 'yes' to confirm: ${NC}")" answer
    [[ "$answer" == "yes" ]]
}

require_arg() {
    if [ -z "${2:-}" ]; then
        error "Missing argument: <$1>"
        echo -e "  Run ${CYAN}db help${NC} to see usage." >&2
        exit 1
    fi
}

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
cat << EOF

$(echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}")
$(echo -e "${BOLD}${BLUE}║           🗄️  DATABASE MANAGEMENT CLI  (db)               ║${NC}")
$(echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}")

$(echo -e "${BOLD}${YELLOW}TARGETS${NC}")
  postgres | pg      → PostgreSQL
  mongo    | mg      → MongoDB
  all                → Both databases at once

$(echo -e "${BOLD}${YELLOW}SERVICE MANAGEMENT${NC}")
  db status                          Check running status of all databases
  db <target> start                  Start the database service
  db <target> stop                   Stop the database service
  db <target> restart                Restart the database service

$(echo -e "${BOLD}${YELLOW}DATABASE OPERATIONS${NC}")
  db <target> list                   List all databases
  db <target> create <db>            Create a new database
  db <target> drop <db>              Drop a database (requires 'yes' confirmation)
  db <target> info <db>              Show size and object count of a database
  db <target> truncate <db>          Empty ALL tables/collections (keeps schema)

$(echo -e "${BOLD}${YELLOW}TABLE / COLLECTION OPERATIONS${NC}")
  db <target> tables <db>            List all tables (PG) or collections (Mongo)
  db <target> desc <db> <obj>        Describe schema of a table/collection
  db <target> clear <db> <obj>       Empty a single table/collection
  db <target> drop-table <db> <obj>  Drop a table/collection entirely
  db <target> rename <db> <old> <new> Rename a table/collection

$(echo -e "${BOLD}${YELLOW}DATA — READ${NC}")
  db <target> show <db> <obj> [n]    Show first N rows/docs (default: 20)
  db <target> count <db> <obj>       Count rows/docs
  db pg      query <db> "<sql>"      Run raw SQL query
  db mg      query <db> <col> [json] Find docs (optional JSON filter)

$(echo -e "${BOLD}${YELLOW}DATA — WRITE${NC}")
  db pg insert <db> <table> '<json>' Insert a row (JSON keys→columns)
  db mg insert <db> <col>   '<json>' Insert a MongoDB document
  db pg update <db> <table> "<where>" "<SET col=val>"  Update rows
  db mg update <db> <col>   '<filter>' '<update_doc>'  Update docs
  db pg delete <db> <table> "<where>"   Delete rows (with confirmation)
  db mg delete <db> <col>   '<filter>'  Delete docs (with confirmation)

$(echo -e "${BOLD}${YELLOW}UTILITIES${NC}")
  db <target> shell [db]             Interactive psql / mongosh shell
  db <target> export <db> <file>     Dump a database to a file
  db <target> import <db> <file>     Restore a database from a dump file
  db install                         Install PostgreSQL + MongoDB, disable boot-start
  db help                            Show this help

$(echo -e "${BOLD}${YELLOW}EXAMPLES${NC}")
  $(echo -e "${GREEN}db status${NC}")
  $(echo -e "${GREEN}db pg start${NC}")
  $(echo -e "${GREEN}db pg create ekaulo${NC}")
  $(echo -e "${GREEN}db pg tables ekaulo${NC}")
  $(echo -e "${GREEN}db pg show ekaulo users${NC}")
  $(echo -e "${GREEN}db pg count ekaulo orders${NC}")
  $(echo -e "${GREEN}db pg desc ekaulo users${NC}")
  $(echo -e "${GREEN}db pg query ekaulo \"SELECT * FROM users WHERE active=true\"${NC}")
  $(echo -e "${GREEN}db pg insert ekaulo users '{\"name\":\"Alice\",\"email\":\"a@b.com\"}'${NC}")
  $(echo -e "${GREEN}db pg update ekaulo users \"id=1\" \"name='Bob'\"${NC}")
  $(echo -e "${GREEN}db pg delete ekaulo users \"id=1\"${NC}")
  $(echo -e "${GREEN}db pg drop ekaulo${NC}")
  $(echo -e "${GREEN}db mg insert ekaulo staff '{\"name\":\"John\",\"role\":\"dsp\"}'${NC}")
  $(echo -e "${GREEN}db mg query ekaulo staff '{\"role\":\"dsp\"}'${NC}")
  $(echo -e "${GREEN}db mg update ekaulo staff '{\"name\":\"John\"}' '{\"role\":\"cdsp\"}'${NC}")
  $(echo -e "${GREEN}db all stop${NC}")

EOF
    exit 0
}

# ─── Service resolution ───────────────────────────────────────────────────────
resolve_service() {
    case "$1" in
        postgres|postgresql|pg) echo "postgresql" ;;
        mongo|mongodb|mg)       echo "mongod" ;;
        all)                    echo "all" ;;
        *)                      echo "unknown" ;;
    esac
}

svc_action() {
    local action="$1" svc="$2"
    info "sudo systemctl $action $svc"
    if sudo systemctl "$action" "$svc"; then
        success "$svc ${action}ed."
    else
        error "Failed to $action $svc."
    fi
}

check_running() {
    local svc="$1"
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        warn "$svc is not running."
        local hint="pg"
        [ "$svc" = "mongod" ] && hint="mg"
        echo -e "  Start it with: ${CYAN}db $hint start${NC}"
        return 1
    fi
    return 0
}

# ─── PG helpers ──────────────────────────────────────────────────────────────
pg_exec()    { sudo -u postgres psql -qAX -c "$1" 2>&1; }
pg_db_exec() { sudo -u postgres psql -qAX -d "$1" -c "$2" 2>&1; }
pg_db_pp()   { sudo -u postgres psql -d "$1" -P pager=off -c "$2"; }   # pretty-print

# ─── Mongo helpers ───────────────────────────────────────────────────────────
mg_eval()    { mongosh --quiet --eval "$1" "$2" 2>/dev/null; }

# ─── Status ──────────────────────────────────────────────────────────────────
cmd_status() {
    section "Database Service Status"
    local svcs=("postgresql" "mongod")
    local names=("PostgreSQL" "MongoDB   ")
    for i in "${!svcs[@]}"; do
        local svc="${svcs[$i]}" name="${names[$i]}"
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            local pid; pid=$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)
            echo -e "  ${GREEN}${BOLD}●${NC} ${name}  ${GREEN}Running${NC} ${DIM}(PID $pid)${NC}"
        else
            echo -e "  ${RED}${BOLD}●${NC} ${name}  ${RED}Stopped${NC}"
        fi
    done
    divider
}

# ─── Install ─────────────────────────────────────────────────────────────────
cmd_install() {
    section "Installing PostgreSQL & MongoDB"

    info "Updating package lists..."
    sudo apt-get update -qq

    # PostgreSQL
    if ! command -v psql &>/dev/null; then
        info "Installing PostgreSQL..."
        sudo apt-get install -y postgresql postgresql-contrib
        success "PostgreSQL installed."
    else
        success "PostgreSQL already installed: $(psql --version 2>&1 | head -1)"
    fi

    # MongoDB
    if ! command -v mongod &>/dev/null; then
        info "Installing MongoDB..."
        # Detect the best supported Ubuntu codename for MongoDB repo.
        # MongoDB doesn't publish repos for every Ubuntu release immediately.
        # Use 'noble' (24.04) as the latest supported base for 25.x/26.x.
        local distro_codename
        distro_codename=$(lsb_release -cs)
        local mongo_repo_codename="$distro_codename"

        # Try to fetch a test release file; fall back to noble if not found
        local test_url="https://repo.mongodb.org/apt/ubuntu/${distro_codename}/mongodb-org/8.0/Release"
        if ! curl --silent --head --fail "$test_url" &>/dev/null; then
            warn "MongoDB repo not available for '$distro_codename'. Falling back to 'noble' (24.04) repo."
            mongo_repo_codename="noble"
        fi

        info "Adding MongoDB 8.0 repository for '$mongo_repo_codename'..."
        curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
            | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor

        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${mongo_repo_codename}/mongodb-org/8.0 multiverse" \
            | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null

        sudo apt-get update -qq
        sudo apt-get install -y mongodb-org
        success "MongoDB installed."
    else
        success "MongoDB already installed: $(mongod --version 2>&1 | head -1)"
    fi

    # Disable auto-start on boot
    section "Disabling auto-start on boot"
    for svc in postgresql mongod; do
        sudo systemctl stop "$svc" 2>/dev/null || true
        sudo systemctl disable "$svc" 2>/dev/null \
            && success "$svc disabled from boot." \
            || warn "$svc may already be disabled."
    done

    # Install this script globally
    section "Installing 'db' globally"
    local script_path; script_path="$(realpath "$0")"
    sudo cp "$script_path" /usr/local/bin/db
    sudo chmod +x /usr/local/bin/db
    success "'db' installed at /usr/local/bin/db"

    divider
    echo -e "\n${GREEN}${BOLD}All done!${NC}  Use ${CYAN}db help${NC} to get started.\n"
}

# ─── LIST databases ──────────────────────────────────────────────────────────
cmd_list() {
    local target="$1" svc="$2"
    check_running "$svc" || exit 1
    section "Databases on $target"
    if [ "$svc" = "postgresql" ]; then
        sudo -u postgres psql -l
    else
        mg_eval "db.getMongo().getDBNames().forEach(n => print('  • ' + n))" "admin"
    fi
}

# ─── Tables / Collections ────────────────────────────────────────────────────
cmd_tables() {
    local svc="$1" db="$2"
    require_arg "database" "$db"
    check_running "$svc" || exit 1
    section "Objects in '$db'"
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "\dt+" 2>&1 || error "Database '$db' not found."
    else
        mg_eval "db.getCollectionNames().forEach(c => print('  • ' + c))" "$db"
    fi
}

# ─── CREATE database ─────────────────────────────────────────────────────────
cmd_create() {
    local svc="$1" db="$2"
    require_arg "database name" "$db"
    check_running "$svc" || exit 1
    info "Creating database '$db'..."
    if [ "$svc" = "postgresql" ]; then
        sudo -u postgres createdb "$db" && success "Database '$db' created." || error "Failed (may already exist)."
    else
        mg_eval "db.createCollection('_init'); print('ok')" "$db"
        success "MongoDB database '$db' initialized."
    fi
}

# ─── DROP database ───────────────────────────────────────────────────────────
cmd_drop() {
    local svc="$1" db="$2"
    require_arg "database name" "$db"
    check_running "$svc" || exit 1
    confirm "This will PERMANENTLY DELETE database '$db'." || { echo "Cancelled."; exit 0; }
    if [ "$svc" = "postgresql" ]; then
        pg_exec "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db' AND pid<>pg_backend_pid();" > /dev/null
        sudo -u postgres dropdb "$db" && success "Database '$db' dropped." || error "Failed."
    else
        mg_eval "db.dropDatabase()" "$db"
        success "MongoDB database '$db' dropped."
    fi
}

# ─── Info ────────────────────────────────────────────────────────────────────
cmd_info() {
    local svc="$1" db="$2"
    require_arg "database name" "$db"
    check_running "$svc" || exit 1
    section "Info: '$db'"
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "
            SELECT
              pg_size_pretty(pg_database_size(current_database())) AS size,
              count(*) AS table_count
            FROM information_schema.tables
            WHERE table_schema='public';"
    else
        mg_eval "
            const s = db.stats();
            print('  db:          ' + s.db);
            print('  collections: ' + s.collections);
            print('  documents:   ' + s.objects);
            print('  size:        ' + (s.dataSize/1024/1024).toFixed(2) + ' MB');
        " "$db"
    fi
}

# ─── TRUNCATE all tables/collections ─────────────────────────────────────────
cmd_truncate() {
    local svc="$1" db="$2"
    require_arg "database" "$db"
    check_running "$svc" || exit 1
    confirm "This will EMPTY ALL tables/collections in '$db' (schema kept)." || { echo "Cancelled."; exit 0; }
    if [ "$svc" = "postgresql" ]; then
        pg_db_exec "$db" "
            DO \$\$ DECLARE r RECORD; BEGIN
                FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname='public') LOOP
                    EXECUTE 'TRUNCATE TABLE public.' || quote_ident(r.tablename) || ' CASCADE';
                END LOOP;
            END \$\$;"
        success "All tables truncated in '$db'."
    else
        mg_eval "db.getCollectionNames().filter(c=>!c.startsWith('system.')).forEach(c=>{db.getCollection(c).deleteMany({});print('Cleared: '+c)})" "$db"
        success "All collections cleared in '$db'."
    fi
}

# ─── SHOW rows/docs ──────────────────────────────────────────────────────────
cmd_show() {
    local svc="$1" db="$2" obj="$3" limit="${4:-20}"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    check_running "$svc" || exit 1
    section "First $limit from '$obj' in '$db'"
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "SELECT * FROM \"$obj\" LIMIT $limit;"
    else
        mg_eval "db.getCollection('$obj').find().limit($limit).forEach(d=>print(JSON.stringify(d,null,2)))" "$db"
    fi
}

# ─── COUNT ───────────────────────────────────────────────────────────────────
cmd_count() {
    local svc="$1" db="$2" obj="$3"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    check_running "$svc" || exit 1
    section "Count: '$obj' in '$db'"
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "SELECT COUNT(*) AS total FROM \"$obj\";"
    else
        local n; n=$(mg_eval "print(db.getCollection('$obj').countDocuments())" "$db")
        echo -e "  ${CYAN}total_docs:${NC} $n"
    fi
}

# ─── DESCRIBE schema ─────────────────────────────────────────────────────────
cmd_desc() {
    local svc="$1" db="$2" obj="$3"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    check_running "$svc" || exit 1
    section "Schema: '$obj' in '$db'"
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "\d+ \"$obj\""
    else
        mg_eval "
            const doc = db.getCollection('$obj').findOne();
            if (!doc) { print('  (empty collection)'); }
            else { Object.keys(doc).forEach(k => print('  ' + k + ': ' + typeof doc[k])); }
        " "$db"
    fi
}

# ─── CLEAR single table/collection ───────────────────────────────────────────
cmd_clear() {
    local svc="$1" db="$2" obj="$3"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    check_running "$svc" || exit 1
    confirm "This will delete ALL data in '$obj' (schema preserved)." || { echo "Cancelled."; exit 0; }
    if [ "$svc" = "postgresql" ]; then
        pg_db_exec "$db" "TRUNCATE TABLE \"$obj\" CASCADE;"
        success "Table '$obj' cleared."
    else
        mg_eval "db.getCollection('$obj').deleteMany({}); print('cleared')" "$db"
        success "Collection '$obj' cleared."
    fi
}

# ─── DROP table/collection ───────────────────────────────────────────────────
cmd_drop_table() {
    local svc="$1" db="$2" obj="$3"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    check_running "$svc" || exit 1
    confirm "This will PERMANENTLY DROP '$obj' from '$db'." || { echo "Cancelled."; exit 0; }
    if [ "$svc" = "postgresql" ]; then
        pg_db_exec "$db" "DROP TABLE IF EXISTS \"$obj\" CASCADE;"
        success "Table '$obj' dropped."
    else
        mg_eval "db.getCollection('$obj').drop(); print('dropped')" "$db"
        success "Collection '$obj' dropped."
    fi
}

# ─── RENAME ──────────────────────────────────────────────────────────────────
cmd_rename() {
    local svc="$1" db="$2" old="$3" new_name="$4"
    require_arg "database" "$db"; require_arg "old name" "$old"; require_arg "new name" "$new_name"
    check_running "$svc" || exit 1
    info "Renaming '$old' → '$new_name' in '$db'..."
    if [ "$svc" = "postgresql" ]; then
        pg_db_exec "$db" "ALTER TABLE \"$old\" RENAME TO \"$new_name\";"
        success "Table renamed."
    else
        mg_eval "db.getCollection('$old').renameCollection('$new_name'); print('renamed')" "$db"
        success "Collection renamed."
    fi
}

# ─── QUERY (raw SQL / mongo find) ────────────────────────────────────────────
cmd_query() {
    local svc="$1" db="$2"
    require_arg "database" "$db"
    check_running "$svc" || exit 1
    if [ "$svc" = "postgresql" ]; then
        local sql="${3:-}"
        require_arg "SQL query" "$sql"
        sudo -u postgres psql -d "$db" -P pager=off -c "$sql"
    else
        local col="${3:-}" filter="${4:-{}}"
        require_arg "collection" "$col"
        section "Querying '$col' in '$db'"
        mg_eval "db.getCollection('$col').find($filter).forEach(d=>print(JSON.stringify(d,null,2)))" "$db"
    fi
}

# ─── INSERT ──────────────────────────────────────────────────────────────────
cmd_insert() {
    local svc="$1" db="$2" obj="$3" data="$4"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"; require_arg "JSON data" "$data"
    check_running "$svc" || exit 1
    if [ "$svc" = "postgresql" ]; then
        # Build INSERT from JSON using python3
        local sql
        sql=$(python3 - "$obj" "$data" << 'PYEOF'
import sys, json
table = sys.argv[1]
data  = json.loads(sys.argv[2])
cols  = ", ".join(f'"{k}"' for k in data)
vals  = ", ".join(
    f"'{str(v)}'" if isinstance(v, str) else
    "NULL" if v is None else
    str(v)
    for v in data.values()
)
print(f"INSERT INTO \"{table}\" ({cols}) VALUES ({vals}) RETURNING *;")
PYEOF
        )
        pg_db_pp "$db" "$sql"
        success "Row inserted into '$obj'."
    else
        mg_eval "const r=db.getCollection('$obj').insertOne($data); print('Inserted _id: '+r.insertedId)" "$db"
        success "Document inserted into '$obj'."
    fi
}

# ─── UPDATE ──────────────────────────────────────────────────────────────────
cmd_update() {
    local svc="$1" db="$2" obj="$3" filter_arg="$4" set_arg="$5"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"
    require_arg "filter/where" "$filter_arg"; require_arg "set/update" "$set_arg"
    check_running "$svc" || exit 1
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "UPDATE \"$obj\" SET $set_arg WHERE $filter_arg RETURNING *;"
        success "Rows updated."
    else
        mg_eval "const r=db.getCollection('$obj').updateMany($filter_arg,{\$set:$set_arg}); print('Matched: '+r.matchedCount+' | Modified: '+r.modifiedCount)" "$db"
        success "Documents updated."
    fi
}

# ─── DELETE rows/docs ────────────────────────────────────────────────────────
cmd_delete() {
    local svc="$1" db="$2" obj="$3" cond="$4"
    require_arg "database" "$db"; require_arg "table/collection" "$obj"; require_arg "where/filter" "$cond"
    check_running "$svc" || exit 1
    confirm "This will DELETE matching records from '$obj'." || { echo "Cancelled."; exit 0; }
    if [ "$svc" = "postgresql" ]; then
        pg_db_pp "$db" "DELETE FROM \"$obj\" WHERE $cond RETURNING *;"
        success "Rows deleted."
    else
        mg_eval "const r=db.getCollection('$obj').deleteMany($cond); print('Deleted: '+r.deletedCount)" "$db"
        success "Documents deleted."
    fi
}

# ─── SHELL ───────────────────────────────────────────────────────────────────
cmd_shell() {
    local svc="$1" db="${2:-}"
    check_running "$svc" || exit 1
    if [ "$svc" = "postgresql" ]; then
        [ -z "$db" ] && db="postgres"
        info "Opening psql → $db  (\\q to quit)"
        sudo -u postgres psql -d "$db"
    else
        [ -z "$db" ] && db="test"
        info "Opening mongosh → $db  (exit to quit)"
        mongosh "$db"
    fi
}

# ─── EXPORT / IMPORT ─────────────────────────────────────────────────────────
cmd_export() {
    local svc="$1" db="$2" file="$3"
    require_arg "database" "$db"; require_arg "output file" "$file"
    check_running "$svc" || exit 1
    info "Exporting '$db' → $file ..."
    if [ "$svc" = "postgresql" ]; then
        sudo -u postgres pg_dump "$db" > "$file"
    else
        mongodump --db="$db" --archive="$file" --gzip
    fi
    success "Exported to $file"
}

cmd_import() {
    local svc="$1" db="$2" file="$3"
    require_arg "database" "$db"; require_arg "input file" "$file"
    [ ! -f "$file" ] && { error "File not found: $file"; exit 1; }
    check_running "$svc" || exit 1
    confirm "Restore '$db' from $file? (may overwrite existing data)" || { echo "Cancelled."; exit 0; }
    info "Importing '$db' ← $file ..."
    if [ "$svc" = "postgresql" ]; then
        sudo -u postgres psql "$db" < "$file"
    else
        mongorestore --db="$db" --archive="$file" --gzip --drop
    fi
    success "Imported from $file"
}

# ─── Main dispatch ───────────────────────────────────────────────────────────
main() {
    [ $# -eq 0 ] && usage

    local cmd="${1:-}"
    case "$cmd" in
        help|-h|--help)  usage ;;
        status)          cmd_status; exit 0 ;;
        install)         cmd_install; exit 0 ;;
    esac

    local target="${1:-}"
    local svc; svc=$(resolve_service "$target")

    if [ "$svc" = "unknown" ]; then
        error "Unknown target: '$target'  (valid: postgres | pg | mongo | mg | all)"
        exit 1
    fi

    local action="${2:-}"
    [ -z "$action" ] && { error "Missing action."; usage; }

    # "all" target — only service commands
    if [ "$svc" = "all" ]; then
        case "$action" in
            start|stop|restart)
                for s in postgresql mongod; do svc_action "$action" "$s"; done
                exit 0 ;;
            status) cmd_status; exit 0 ;;
            *) error "Action '$action' not supported with target 'all'."; exit 1 ;;
        esac
    fi

    local db="${3:-}"
    local obj="${4:-}"
    local arg5="${5:-}"
    local arg6="${6:-}"

    case "$action" in
        start|stop|restart)    svc_action "$action" "$svc" ;;
        list)                  cmd_list "$target" "$svc" ;;
        tables|collections)    cmd_tables "$svc" "$db" ;;
        create)                cmd_create "$svc" "$db" ;;
        drop)                  cmd_drop "$svc" "$db" ;;
        info)                  cmd_info "$svc" "$db" ;;
        truncate)              cmd_truncate "$svc" "$db" ;;
        show)                  cmd_show "$svc" "$db" "$obj" "${arg5:-20}" ;;
        count)                 cmd_count "$svc" "$db" "$obj" ;;
        desc|describe)         cmd_desc "$svc" "$db" "$obj" ;;
        clear)                 cmd_clear "$svc" "$db" "$obj" ;;
        drop-table|drop-col)   cmd_drop_table "$svc" "$db" "$obj" ;;
        rename)                cmd_rename "$svc" "$db" "$obj" "$arg5" ;;
        query)                 cmd_query "$svc" "$db" "$obj" "${arg5:-}" ;;
        insert)                cmd_insert "$svc" "$db" "$obj" "$arg5" ;;
        update)                cmd_update "$svc" "$db" "$obj" "$arg5" "$arg6" ;;
        delete)                cmd_delete "$svc" "$db" "$obj" "$arg5" ;;
        shell)                 cmd_shell "$svc" "$db" ;;
        export)                cmd_export "$svc" "$db" "$obj" ;;
        import)                cmd_import "$svc" "$db" "$obj" ;;
        *)
            error "Unknown action: '$action'"
            echo -e "  Run ${CYAN}db help${NC} for all commands."
            exit 1 ;;
    esac
}

main "$@"
